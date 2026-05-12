#!/bin/bash
#
# Compile OpenFOAM + ThirdParty inside the container build.
# Environment variables are set by the Containerfile:
#   FOAM_INST_DIR, OPENFOAM_VERSION, FOAM_ETC, WM_NCOMPPROCS
#
set -e

ETC_TMP=${FOAM_INST_DIR}/OpenFOAM-${OPENFOAM_VERSION}/etc
# Use the system-provided OpenMPI rather than building from ThirdParty
sed -i -e "s%\(export *WM_MPLIB=\).*%\1SYSTEMOPENMPI%" "$ETC_TMP/bashrc"
# Remove paraview setup since unused and prone to errors on some dists
sed -i '/[Pp]ara[Vv]iew/d' "${ETC_TMP}/bashrc"
unset ETC_TMP

# OF's bashrc uses local var=$(...) constructs that confuse set -e
set +e
# shellcheck disable=SC1090
source "${FOAM_ETC}/bashrc"
set -e

cd "${WM_PROJECT_DIR}"
echo "Building OpenFOAM ${OPENFOAM_VERSION} using ${WM_NCOMPPROCS} cores"
./Allwmake
