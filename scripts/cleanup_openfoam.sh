#!/bin/bash
#
# Remove build intermediates and strip binaries from a compiled OpenFOAM tree.
# Runs inside the openfoam-stripped stage; the result is copied into the lean
# runtime image. OF tools (wclean, wrmo, strip) must be available.
#
# Does NOT clean site extensions — those do not exist in this base image.
#
set -e

# shellcheck disable=SC1090
source "${FOAM_ETC}/bashrc"

cd "${WM_PROJECT_DIR}"

# Remove build intermediates produced by wmake
wclean all      2>/dev/null || true
wcleanLnIncludeAll 2>/dev/null || true
wrmo -all       2>/dev/null || true
wrmdep -all     2>/dev/null || true

# Remove source, git history, docs and tutorials — only compiled artifacts remain
rm -rf .git src doc test tutorials Allwmake applications

cd "${WM_THIRD_PARTY_DIR}"
rm -rf .git scotch* openmpi*

# Strip debug symbols — reduces binary size considerably
find "${FOAM_APPBIN}" -type f -exec strip --strip-unneeded {} \; 2>/dev/null || true
find "${FOAM_LIBBIN}" -name "*.so" -exec strip --strip-unneeded {} \; 2>/dev/null || true
