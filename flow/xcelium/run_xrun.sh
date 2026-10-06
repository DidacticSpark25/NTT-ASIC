#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# run_xrun.sh - RTL simulation + code coverage with Cadence Xcelium
#
#   flow/xcelium/run_xrun.sh <kyber|dilithium> <barrett|montgomery> <P> [NTEST]
#   flow/xcelium/run_xrun.sh all [NTEST]                 # all 12 configs + merged coverage
#   WAVES=1 flow/xcelium/run_xrun.sh kyber barrett 2 1   # also dump waveforms for SimVision
#
# Same self-checking testbench and vectors as the open-source regression.
# Coverage: block, expression, toggle, FSM on the DUT; report via IMC.
#
# Test vectors: generated with python3 when it is available, otherwise the
# pre-generated set in tb/vectors/ (16 polynomials per scheme) is used, so the
# lab machine needs nothing but Xcelium.
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

    local vec
    if command -v python3 >/dev/null 2>&1; then
        python3 "$REPO/model/gen_vectors.py" --scheme "$s" --n "$n" --out "$REPO/build/vec/$s" >/dev/null
        vec=$REPO/build/vec/$s
    else
        vec=$REPO/tb/vectors/$s
        if [ "$n" -gt 16 ]; then n=16; fi
    fi

    local access=+r
    local wave_args=()
    if [ "${WAVES:-0}" = 1 ]; then
        # record every signal of the testbench and DUT into a SimVision database
        {
            echo "database -open waves -shm -into waves_$name.shm -default"
            echo "probe -create tb_ntt_core -depth all -all -memories -shm -database waves"
            echo "run"
            echo "exit"
        } > "waves_$name.tcl"
        access=+rwc
        wave_args=(-input "waves_$name.tcl")
    fi

    xrun -64bit -q -timescale 1ns/1ps -access "$access" ${wave_args[@]+"${wave_args[@]}"} \
        -incdir "$REPO/rtl" \
        -top tb_ntt_core \
        -defparam tb_ntt_core.SCHEME=$si -defparam tb_ntt_core.RED=$ri \
        -defparam tb_ntt_core.P=$p       -defparam tb_ntt_core.NTEST=$n \
        -coverage b:e:t:f -covoverwrite -covworkdir cov_work -covscope ntt -covtest "$name" \
        -covdut ntt_core \
        -xmlibdirname "xcelium.d.$name" \
        -l "xrun_$name.log" \
        "$REPO/tb/tb_ntt_core.v" $RTL \
        +vec="$vec"
    grep -E "^(PASS|FAIL|CONFIG)" "xrun_$name.log" | sed "s/^/$name: /"
    if [ "${WAVES:-0}" = 1 ]; then
        echo "waveforms: $WORK/waves_$name.shm"
        echo "open with: simvision $WORK/waves_$name.shm -input $REPO/flow/xcelium/waves.svcf &"
    fi
}

if [ "${1:-}" = all ]; then
    N=${2:-16}
    for s in kyber dilithium; do for r in barrett montgomery; do for p in 1 2 4; do
        one $s $r $p "$N"
    done; done; done
    # merge all runs and report
    {
        echo "merge cov_work/ntt/* -out merged -overwrite"
        echo "load -run cov_work/ntt/merged"
        echo "report -summary -inst -metrics all -out coverage_summary.rpt"
        echo "report -detail  -inst -metrics fsm -out coverage_fsm.rpt"
        echo "exit"
    } > imc_report.tcl
    imc -exec imc_report.tcl -nocopyright > imc.log 2>&1 || echo "WARN: IMC report step failed, see $WORK/imc.log"
    echo "coverage: $WORK/coverage_summary.rpt"
else
    one "${1:?scheme}" "${2:?reduction}" "${3:?P}" "${4:-16}"
fi
