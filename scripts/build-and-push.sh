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
