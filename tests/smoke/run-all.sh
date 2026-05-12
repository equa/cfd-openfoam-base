#!/bin/bash
#
# Smoke tests — run inside the built image to verify a working OF installation.
# Each check prints PASS or FAIL and exits non-zero on the first failure.
#
set -e

PASS="[PASS]"
FAIL="[FAIL]"

# OF's bashrc uses local var=$(...) constructs that confuse set -e
set +e
# shellcheck disable=SC1090
source "${FOAM_ETC}/bashrc"
set -e

echo "=== OpenFOAM smoke tests ==="

# 1. Version check
echo -n "foamVersion ... "
foam_ver=$(foamVersion 2>/dev/null | head -1) || { echo "$FAIL (foamVersion failed)"; exit 1; }
echo "$PASS ($foam_ver)"

# 2. A core solver is present and responds
echo -n "icoFoam -help ... "
icoFoam -help &>/dev/null || { echo "$FAIL"; exit 1; }
echo "$PASS"

# 3. foamRun (used for steady RANS — the main EQUA use case)
echo -n "foamRun -help ... "
foamRun -help &>/dev/null || { echo "$FAIL"; exit 1; }
echo "$PASS"

# 4. blockMesh (mesh generation utility)
echo -n "blockMesh -help ... "
blockMesh -help &>/dev/null || { echo "$FAIL"; exit 1; }
echo "$PASS"

# 5. MPI round-trip
echo -n "mpirun -np 2 echo ... "
mpirun -np 2 echo "mpi ok" &>/dev/null || { echo "$FAIL"; exit 1; }
echo "$PASS"

echo "=== All smoke tests passed ==="
