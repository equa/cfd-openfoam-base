#!/usr/bin/env bash
#
# Build openfoam13-base and openfoam13-dev LOCALLY and push them to GHCR.
#
# This is the supported way to refresh these images. The GitHub workflow can
# still do it, but a full OpenFOAM Allwmake against a 2-4 vCPU hosted runner
# sits close to the 6-hour job limit and has been flaky; a workstation with a
# dozen cores does it comfortably. The workflow remains for when someone wants
# CI to try, and for the lint/release jobs.
#
# It does exactly what .github/workflows/release.yml does, in the same order and
# with the same tags, so an image built here is not a different kind of artefact
# from one built there:
#
#     build both targets -> smoke-test the runtime image -> tag -> push
#
# Why this matters beyond convenience: these images pin nothing, so their Ubuntu
# package set is frozen at build time. The 2026-09 scan found ~900 medium+
# findings in the stack, largely because the base had not been rebuilt since
# 2026-05 and every Ubuntu security update since was simply missing. Rebuilding
# IS the fix for most of them. See cfd-restful-backend/docs/sbom.md.
#
# Usage:
#     scripts/build-and-push.sh                  # build, smoke-test, push :beta
#     scripts/build-and-push.sh --no-push        # build and smoke-test only
#     NCOMPPROCS=8 scripts/build-and-push.sh     # override compile parallelism
#
# Requires: podman or docker, and a GHCR login with write:packages --
#     echo "$GITHUB_PAT" | podman login ghcr.io -u <your-github-user> --password-stdin
#
set -euo pipefail

cd "$(dirname "$0")/.."

REGISTRY=${REGISTRY:-ghcr.io/equa}
NCOMPPROCS=${NCOMPPROCS:-$(nproc 2>/dev/null || echo 4)}
PUSH=yes
ALLOW_DIRTY=${ALLOW_DIRTY:-no}

while [ $# -gt 0 ]; do
    case "$1" in
        --no-push)     PUSH=no; shift ;;
        --allow-dirty) ALLOW_DIRTY=yes; shift ;;
        -h|--help)     sed -n '2,32p' "$0"; exit 0 ;;
        *)             echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

ENGINE=${CONTAINER_ENGINE:-$(command -v podman || command -v docker || true)}
[ -n "$ENGINE" ] || { echo "build-and-push: no podman or docker on PATH" >&2; exit 1; }

# ── Can we actually push, BEFORE spending an hour compiling? ─────────────────
#
# `podman login --get-login` is not this check, which was learned the expensive
# way: it reads back the cached credential's USERNAME, so a read-only token
# reports exactly like a write-capable one. GHCR verifies identity at login and
# scope at the first blob upload, i.e. at the very end of this script:
#
#     denied: permission_denied: The token provided does not match expected
#     scopes.
#
# So inspect the cached credential's OAuth scopes up front. Two failure modes,
# both silent until push:
#   * a fine-grained PAT -- GitHub Packages only supports CLASSIC tokens, and a
#     fine-grained one yields no x-oauth-scopes header at all
#   * a classic token carrying read:packages but not write:packages
#
# The token is read out of the auth file and sent only to api.github.com. If the
# check cannot reach a verdict (no jq, unusual auth path, offline) it warns and
# continues rather than blocking a build that might be fine.
check_push_scope() {
    [ "$PUSH" = yes ] || return 0

    local auth_file auth token scopes
    for auth_file in \
        "${REGISTRY_AUTH_FILE:-}" \
        "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/containers/auth.json" \
        "$HOME/.config/containers/auth.json" \
        "$HOME/.docker/config.json"
    do
        [ -n "$auth_file" ] && [ -f "$auth_file" ] && break
        auth_file=""
    done

    if [ -z "$auth_file" ] || ! command -v jq >/dev/null || ! command -v curl >/dev/null; then
        echo "build-and-push: NOTE: cannot verify push scope (no auth file, jq or curl)." >&2
        echo "                 If the push fails at the end, that is why." >&2
        return 0
    fi

    auth=$(jq -r '.auths["ghcr.io"].auth // empty' "$auth_file" 2>/dev/null || true)
    if [ -z "$auth" ]; then
        echo "build-and-push: no ghcr.io credential in $auth_file." >&2
        echo "                 echo \"\$GITHUB_PAT\" | $(basename "$ENGINE") login ghcr.io -u <user> --password-stdin" >&2
        exit 1
    fi

    token=$(printf '%s' "$auth" | base64 -d 2>/dev/null | cut -d: -f2- || true)
    [ -n "$token" ] || { echo "build-and-push: NOTE: could not decode the cached credential; skipping scope check." >&2; return 0; }

    scopes=$(curl -sS -m 15 -I -H "Authorization: token $token" https://api.github.com 2>/dev/null \
             | tr -d '\r' | awk -F': ' 'tolower($1)=="x-oauth-scopes"{print $2}' || true)

    if [ -z "$scopes" ]; then
        cat >&2 <<'MSG'
build-and-push: the cached ghcr.io token reports no OAuth scopes, which means it
                is a FINE-GRAINED personal access token. GitHub Packages only
                supports classic tokens, so the push would be denied after the
                whole build.

                Create a classic PAT with write:packages (untick the `repo`
                scope the UI auto-selects -- these packages are linked to this
                repository and inherit its permissions), then:

                    podman logout ghcr.io
                    echo "$PAT" | podman login ghcr.io \
                        -u <your-github-user> --password-stdin

                Pass SKIP_SCOPE_CHECK=1 to build anyway.
MSG
        [ "${SKIP_SCOPE_CHECK:-0}" = 1 ] || exit 1
    elif ! printf '%s' "$scopes" | grep -q 'write:packages'; then
        echo "build-and-push: the cached ghcr.io token has scopes [$scopes]," >&2
        echo "                 which do not include write:packages. The push would" >&2
        echo "                 be denied after the whole build. Log in with a" >&2
        echo "                 classic PAT that has write:packages." >&2
        echo "                 Pass SKIP_SCOPE_CHECK=1 to build anyway." >&2
        [ "${SKIP_SCOPE_CHECK:-0}" = 1 ] || exit 1
    else
        echo "build-and-push: ghcr.io token scopes OK [$scopes]"
    fi
}

# The image is going to be identified by a commit, so it had better correspond
# to one. A dirty tree pushed as ":beta-<sha>" is a lie that is impossible to
# unpick later -- the SBOM will name a commit whose contents were never built.
SHA=$(git rev-parse HEAD)
SHORT=$(git rev-parse --short HEAD)
if ! git diff --quiet || ! git diff --cached --quiet; then
    if [ "$ALLOW_DIRTY" = yes ]; then
        echo "build-and-push: WARNING: working tree is dirty; the pushed" >&2
        echo "                 :beta-${SHA} tag will NOT match that commit." >&2
    else
        echo "build-and-push: working tree is dirty. Commit first, or pass" >&2
        echo "                --allow-dirty if you know what you are doing." >&2
        exit 1
    fi
fi

check_push_scope

echo "build-and-push: engine=$ENGINE  parallelism=$NCOMPPROCS  commit=$SHORT"
echo "build-and-push: this takes 30-60 minutes on a cold cache."
echo

# Both targets share the openfoam-builder layer, so the expensive compilation
# happens once and the second build reuses it from the local layer cache --
# same reasoning as the CI job, different cache.
for target in openfoam13-base openfoam13-dev; do
    echo "── building ${target} ──────────────────────────────────────────" >&2
    "$ENGINE" build \
        --target "$target" \
        --build-arg "WM_NCOMPPROCS=${NCOMPPROCS}" \
        -f Containerfile \
        -t "${target}:candidate" \
        .
done

echo
echo "── smoke-testing openfoam13-base ──────────────────────────────────" >&2
"$ENGINE" run --rm "openfoam13-base:candidate" bash /tests/smoke/run-all.sh

if [ "$PUSH" != yes ]; then
    echo
    echo "build-and-push: --no-push given; candidates left as openfoam13-{base,dev}:candidate"
    exit 0
fi

echo
for image in openfoam13-base openfoam13-dev; do
    for tag in "beta" "beta-${SHA}"; do
        "$ENGINE" tag "${image}:candidate" "${REGISTRY}/${image}:${tag}"
        echo "pushing ${REGISTRY}/${image}:${tag}"
        "$ENGINE" push "${REGISTRY}/${image}:${tag}"
    done
done

cat <<EOF

build-and-push: done. ${REGISTRY}/openfoam13-{base,dev}:beta now point at ${SHORT}.

Downstream does NOT update by itself: cfd-restful-backend builds FROM
openfoam13-*:beta, so it picks these up on its next release build. Trigger one
(push to its beta, or run the Release workflow by hand) and the weekly scan
will then report against the refreshed OS layer.
EOF
