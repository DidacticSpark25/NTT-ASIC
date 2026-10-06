#!/usr/bin/env bash
# run_lec.sh <build_dir> - RTL vs synthesized netlist equivalence with Cadence Conformal LEC.
# Uses the dofile Genus wrote (write_do_lec), which already knows the RTL files,
# include paths and the sequential mapping done during synthesis.
set -eu
BUILD=$(cd "${1:?build dir}" && pwd)
cd "$BUILD/syn"
lec -XL -nogui -dofile out/lec.do > out/lec_run.log 2>&1 || true
echo "Conformal log: $BUILD/syn/out/lec.log"
# Look for the compare summary: expect 0 non-equivalent points
grep -iE "non-equivalent|equivalent points|compare results" out/lec_run.log out/lec.log 2>/dev/null | tail -n 10
