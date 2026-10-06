#!/usr/bin/env bash
# regress.sh - full RTL regression with Icarus Verilog (open-source, runs anywhere / in CI).
#   2 schemes x 2 reductions x P = 1,2,4 for the core, plus modmul unit tests.
# Usage: scripts/regress.sh [NTEST]        (default 16 polynomials per config)
# The same testbenches run unchanged on Cadence Xcelium: see flow/xcelium/run_xrun.sh
set -u
cd "$(dirname "$0")/.."
NTEST=${1:-16}
NMUL=${NMUL:-200000}
OUT=build/regress
mkdir -p "$OUT" build/vec
RTL="rtl/ntt_core.v rtl/ntt_butterfly.v rtl/ntt_modmul.v rtl/ntt_bank.v rtl/ntt_tw_rom.v"

python3 model/gen_rtl.py >/dev/null
for s in kyber dilithium; do
    python3 model/gen_vectors.py --scheme $s --n "$NTEST" --out build/vec/$s >/dev/null
done

run() {   # name, iverilog args..., -- , vvp plusargs...
    local name=$1; shift
    local args=() plus=()
    while [ "$1" != "--" ]; do args+=("$1"); shift; done; shift
    plus=("$@")
    if ! iverilog -g2005 -Irtl -o "$OUT/$name.vvp" "${args[@]}" > "$OUT/$name.compile.log" 2>&1; then
        echo "COMPILE-FAIL $name"; return
    fi
    vvp -n "$OUT/$name.vvp" "${plus[@]}" > "$OUT/$name.log" 2>&1
    grep -E "^(PASS|FAIL)" "$OUT/$name.log" | sed "s/^/$name: /" || echo "$name: NO RESULT"
}

jobs_list=()
for si in 0 1; do
    sname=$([ $si = 0 ] && echo kyber || echo dilithium)
    for ri in 0 1; do
        rname=$([ $ri = 0 ] && echo barrett || echo montgomery)
        run "modmul_${sname}_${rname}" -s tb_modmul -P tb_modmul.SCHEME=$si -P tb_modmul.RED=$ri \
            -P tb_modmul.NVEC=$NMUL tb/tb_modmul.v rtl/ntt_modmul.v -- &
        for p in 1 2 4; do
            run "core_${sname}_${rname}_P${p}" -s tb_ntt_core -P tb_ntt_core.SCHEME=$si -P tb_ntt_core.RED=$ri \
                -P tb_ntt_core.P=$p -P tb_ntt_core.NTEST=$NTEST tb/tb_ntt_core.v $RTL -- +vec=build/vec/$sname &
        done
    done
done
wait

echo "---------------------------------------------"
grep -h "^CONFIG" $OUT/core_*.log | sort
total_fail=$(grep -L "^PASS" $OUT/*.log | grep -v compile | wc -l)
checks=$(grep -h "^PASS" $OUT/*.log | grep -oE "[0-9]+ (coefficient checks|products)" | awk '{s+=$1} END {print s}')
if [ "$total_fail" -eq 0 ]; then
    echo "REGRESSION PASSED: $(ls $OUT/*.log | grep -vc compile) runs, $checks checks"
else
    echo "REGRESSION FAILED: $total_fail run(s) did not pass"; exit 1
fi
