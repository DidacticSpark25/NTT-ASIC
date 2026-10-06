#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# run_gls.sh - gate-level simulation of the synthesized or routed netlist (Xcelium)
#
#   flow/xcelium/run_gls.sh <build_dir> syn        # post-synthesis, zero delay
#   flow/xcelium/run_gls.sh <build_dir> pnr        # post-route with SDF timing
#
# <build_dir> is the configuration directory made by `make syn/pnr`,
# e.g. build/kyber_barrett_p2. Scheme and P are read from its ntt_cfg.vh.
# ---------------------------------------------------------------------------
set -eu
REPO=$(cd "$(dirname "$0")/../.." && pwd)
BUILD=$(cd "${1:?build dir}" && pwd)
STAGE=${2:-syn}
STD_VERILOG=$("$REPO/flow/cfg_get.sh" STD_VERILOG)

si=$(awk '/NTT_SCHEME/{print $3}' "$BUILD/ntt_cfg.vh")
ri=$(awk '/NTT_RED/{print $3}'    "$BUILD/ntt_cfg.vh")
p=$(awk '/NTT_P/{print $3}'       "$BUILD/ntt_cfg.vh")
s=$([ "$si" = 0 ] && echo kyber || echo dilithium)
N=${NTEST:-4}
python3 "$REPO/model/gen_vectors.py" --scheme "$s" --n "$N" --out "$REPO/build/vec/$s" >/dev/null

mkdir -p "$BUILD/gls_$STAGE" && cd "$BUILD/gls_$STAGE"
if [ "$STAGE" = pnr ]; then
    NET=$BUILD/pnr/out/ntt_top.pnr.v
    EXTRA=(+sdf="$BUILD/pnr/out/ntt_top.sdf" -sdf_verbose)
    TIMING=()
else
    NET=$BUILD/syn/out/ntt_top.syn.v
    EXTRA=()
    TIMING=(-notimingchecks -nospecify)
fi

xrun -64bit -q -timescale 1ns/1ps -access +r -define GLS \
    -incdir "$REPO/rtl" -top tb_ntt_core \
    -defparam tb_ntt_core.SCHEME=$si -defparam tb_ntt_core.RED=$ri \
    -defparam tb_ntt_core.P=$p -defparam tb_ntt_core.NTEST=$N \
    "${TIMING[@]}" \
    -v "$STD_VERILOG" "$NET" "$REPO/tb/tb_ntt_core.v" \
    "${EXTRA[@]}" +vec="$REPO/build/vec/$s" -l gls.log
grep -E "^(PASS|FAIL)" gls.log
