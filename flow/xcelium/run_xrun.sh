#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# run_xrun.sh - RTL simulation + code coverage with Cadence Xcelium
#
#   flow/xcelium/run_xrun.sh <kyber|dilithium> <barrett|montgomery> <P> [NTEST]
#   flow/xcelium/run_xrun.sh all [NTEST]          # all 12 configurations + merged coverage
#
# Same self-checking testbench and vectors as the open-source regression.
# Coverage: block, expression, toggle, FSM on the DUT; report via IMC.
# ---------------------------------------------------------------------------
set -eu
REPO=$(cd "$(dirname "$0")/../.." && pwd)
WORK=$REPO/build/xcelium
mkdir -p "$WORK" "$REPO/build/vec"
cd "$WORK"

RTL="$REPO/rtl/ntt_core.v $REPO/rtl/ntt_butterfly.v $REPO/rtl/ntt_modmul.v $REPO/rtl/ntt_bank.v $REPO/rtl/ntt_tw_rom.v"

one() {   # scheme red P ntest
    local s=$1 r=$2 p=$3 n=$4
    local si=$([ "$s" = kyber ] && echo 0 || echo 1)
    local ri=$([ "$r" = barrett ] && echo 0 || echo 1)
    local name=${s}_${r}_p${p}
    python3 "$REPO/model/gen_vectors.py" --scheme "$s" --n "$n" --out "$REPO/build/vec/$s" >/dev/null
    xrun -64bit -q -timescale 1ns/1ps -access +r \
        -incdir "$REPO/rtl" \
        -top tb_ntt_core \
        -defparam tb_ntt_core.SCHEME=$si -defparam tb_ntt_core.RED=$ri \
        -defparam tb_ntt_core.P=$p       -defparam tb_ntt_core.NTEST=$n \
        -coverage b:e:t:f -covoverwrite -covworkdir cov_work -covscope ntt -covtest "$name" \
        -covdut ntt_core \
        -xmlibdirname "xcelium.d.$name" \
        -l "xrun_$name.log" \
        "$REPO/tb/tb_ntt_core.v" $RTL \
        +vec="$REPO/build/vec/$s"
    grep -E "^(PASS|FAIL|CONFIG)" "xrun_$name.log" | sed "s/^/$name: /"
}

if [ "${1:-}" = all ]; then
    N=${2:-16}
    for s in kyber dilithium; do for r in barrett montgomery; do for p in 1 2 4; do
        one $s $r $p "$N"
    done; done; done
    # merge all runs and report
    cat > imc_report.tcl <<EOF
merge cov_work/ntt/* -out merged -overwrite
load -run cov_work/ntt/merged
report -summary -inst -metrics all -out coverage_summary.rpt
report -detail  -inst -metrics fsm -out coverage_fsm.rpt
exit
EOF
    imc -exec imc_report.tcl -nocopyright > imc.log 2>&1 || echo "WARN: IMC report step failed, see $WORK/imc.log"
    echo "coverage: $WORK/coverage_summary.rpt"
else
    one "${1:?scheme}" "${2:?reduction}" "${3:?P}" "${4:-16}"
fi
