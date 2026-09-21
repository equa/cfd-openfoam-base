# cfd-openfoam-base

OpenFOAM 13 base container images for the Equa CFD platform.

## Images

| Image | Purpose |
|-------|---------|
| `ghcr.io/equa/openfoam13-base:beta` | Lean runtime. No build tools or source. Use as base for images that run simulations. |
| `ghcr.io/equa/openfoam13-dev:beta` | Full build environment + Neovim. Use as base when compiling code against OpenFOAM (e.g. site extensions). |

Both images are built from Ubuntu 24.04 with system OpenMPI.

## Usage in a downstream Containerfile

```dockerfile
# Runtime image — for final deployment
FROM ghcr.io/equa/openfoam13-base:beta AS runtime

# Development / compilation image — e.g. for building site extensions
FROM ghcr.io/equa/openfoam13-dev:beta AS builder
```

## Building locally

```bash
# Production image
podman build --target openfoam13-base -t openfoam13-base:local .

# Dev image
podman build --target openfoam13-dev -t openfoam13-dev:local .

# Override core count for compilation (default: 4)
podman build --build-arg WM_NCOMPPROCS=12 --target openfoam13-base -t openfoam13-base:local .
```

## Refreshing the published images

**Build these locally and push, rather than relying on CI.** A full OpenFOAM
`Allwmake` on a 2–4 vCPU GitHub-hosted runner sits close to the six-hour job
limit and has been flaky; a workstation does it comfortably in a fraction of
the time.

```bash
echo "$GITHUB_PAT" | podman login ghcr.io -u <your-github-user> --password-stdin
scripts/build-and-push.sh              # build both, smoke-test, push :beta
scripts/build-and-push.sh --no-push    # dry run
```

The script does exactly what the workflow does, in the same order and with the
same tags, so a locally built image is not a different kind of artefact. It
refuses to push from a dirty working tree, because the `:beta-<sha>` tag would
name a commit whose contents were never built.

**Do this periodically even when nothing here changes.** These images pin no
package versions, so their Ubuntu package set is frozen at build time and every
Ubuntu security update after that is simply missing. The September 2026 scan
found roughly 900 medium-or-higher findings across the stack, largely because
the base had not been rebuilt since May. Rebuilding is the fix for most of
them — see
[`cfd-restful-backend/docs/sbom.md`](https://github.com/equa/cfd-restful-backend/blob/beta/docs/sbom.md).

Downstream does not update by itself: `cfd-restful-backend` builds `FROM
openfoam13-*:beta`, so it picks up a refreshed base on its next release build.

## First-time setup

```bash
npm install   # generates package-lock.json; commit the result
```

## Updating OpenFOAM version

1. Change the `ARG OF_VERSION` default in `Containerfile`.
2. Update the hardcoded `13` references in the `openfoam13-base` stage and image names.
3. Rename the smoke-test image references if needed.
4. Commit with `feat: upgrade to OpenFOAM <version>`.

## Branching policy

All work happens on the `beta` branch. Releases are produced automatically
by `semantic-release` on each push. See `AGENTS.md` for commit conventions.
