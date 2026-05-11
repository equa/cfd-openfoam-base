# AGENTS.md

This file is the single source of truth for AI agents and human
contributors working in `cfd-openfoam-base`.

## Repository purpose

`cfd-openfoam-base` builds and publishes two OpenFOAM 13 container images:

- `ghcr.io/equa/openfoam13-base` — lean runtime, no build tools
- `ghcr.io/equa/openfoam13-dev` — full build environment + developer tooling

These images are the foundation for all downstream CFD images in the
`cfd/` repository group. They are analogous to `equa-base` in the broader
Equa platform, but scoped to CFD workloads.

## Branching policy

All work happens on the `beta` branch only.

## Commit conventions

All commits follow [Conventional Commits](https://www.conventionalcommits.org/).
Enforced by `commitlint`.

`feat:`, `fix:`, and `docs:` trigger a release and appear in the CHANGELOG.
`chore:`, `ci:`, `style:` do not trigger a release.

## CI behaviour

The build workflow triggers on push to `beta` **only when** `Containerfile`,
`scripts/`, or `tests/` change. This avoids re-running a multi-hour OpenFOAM
compilation for documentation-only edits.

`workflow_dispatch` is available for a manual rebuild at any time.

## Key files

| File | Purpose |
|------|---------|
| `Containerfile` | All image definitions — source of truth for toolchain versions |
| `scripts/build_openfoam.sh` | Configures and compiles OpenFOAM + ThirdParty |
| `scripts/cleanup_openfoam.sh` | Strips binaries and removes build intermediates |
| `tests/smoke/run-all.sh` | Smoke tests run inside the built image |
| `.github/workflows/release.yml` | CI: lint → build → smoke test → push → release |

## Adding a tool to the dev image

1. Add the `apt-get install` line to the `openfoam13-dev` stage in `Containerfile`.
2. If it is a tool that should be verified, add a version check to `tests/smoke/run-all.sh`.
3. Commit with `feat: add <tool> to dev image`.

## Updating OpenFOAM version

See the instructions in `README.md`. When bumping the version, update:
- `ARG OF_VERSION` default in `Containerfile`
- Hardcoded version references in `openfoam13-base` stage
- Image names in the workflow and README
