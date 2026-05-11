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
