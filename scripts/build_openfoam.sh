#!/bin/bash
#
# Compile OpenFOAM + ThirdParty inside the container build.
# Environment variables are set by the Containerfile:
#   FOAM_INST_DIR, OPENFOAM_VERSION, FOAM_ETC, WM_NCOMPPROCS
#
set -e

# Use the system-provided OpenMPI rather than building from ThirdParty
sed -i -e "s%\(export *WM_MPLIB=\).*%\1SYSTEMOPENMPI%" \
    "${FOAM_INST_DIR}/OpenFOAM-${OPENFOAM_VERSION}/etc/bashrc"

# shellcheck disable=SC1090
source "${FOAM_ETC}/bashrc"

# Remove solver families that are not needed for HVAC/building simulation.
# This cuts compile time significantly.
rm -rf \
    "${FOAM_SOLVERS}/combustion" \
    "${FOAM_SOLVERS}/DNS" \
    "${FOAM_SOLVERS}/electromagnetics" \
    "${FOAM_SOLVERS}/financial" \
    "${FOAM_SOLVERS}/stressAnalysis" \
    "${FOAM_SOLVERS}/multiphase" \
    "${FOAM_SOLVERS}/lagrangian" \
    "${FOAM_SOLVERS}/discreteMethods"

cd "${WM_PROJECT_DIR}"
echo "Building OpenFOAM ${OPENFOAM_VERSION} using ${WM_NCOMPPROCS} cores"
./Allwmake
