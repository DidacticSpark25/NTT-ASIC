#!/usr/bin/env bash
# gls_yosys.sh <scheme> <reduction> <P> - open-source gate-level check:
# synthesize ntt_top with Yosys, then run the self-checking testbench on the netlist.
# Catches simulation/synthesis mismatches before you spend lab hours in Genus.
set -eu
cd "$(dirname "$0")/.."
S=${1:-kyber}; R=${2:-barrett}; P=${3:-2}; N=${NTEST:-3}
SI=$([ "$S" = kyber ] && echo 0 || echo 1); RI=$([ "$R" = barrett ] && echo 0 || echo 1)
D=build/yosys/${S}_${R}_p${P}
mkdir -p "$D" build/vec
printf '`define NTT_SCHEME %s\n`define NTT_RED %s\n`define NTT_P %s\n' $SI $RI $P > "$D/ntt_cfg.vh"
python3 model/gen_vectors.py --scheme "$S" --n "$N" --out "build/vec/$S" >/dev/null
yosys -q -l "$D/yosys.log" -p "read_verilog -Irtl -I$D rtl/ntt_top.v rtl/ntt_core.v rtl/ntt_butterfly.v \
    rtl/ntt_modmul.v rtl/ntt_bank.v rtl/ntt_tw_rom.v; synth -top ntt_top -flatten; \
    tee -q -o $D/stat.txt stat; write_verilog -noattr $D/ntt_top.yosys.v" 2>/dev/null
SIMCELLS=$(dirname "$(command -v yosys)")/../share/yosys/simcells.v
iverilog -g2005 -DGLS -Irtl -o "$D/gls.vvp" -s tb_ntt_core -P tb_ntt_core.SCHEME=$SI -P tb_ntt_core.RED=$RI \
    -P tb_ntt_core.P=$P -P tb_ntt_core.NTEST=$N tb/tb_ntt_core.v "$D/ntt_top.yosys.v" "$SIMCELLS" 2>/dev/null
echo "yosys cells: $(grep -m1 'Number of cells' $D/stat.txt | awk '{print $NF}')"
vvp -n "$D/gls.vvp" +vec="build/vec/$S" | grep -E "^(PASS|FAIL)" | sed "s/^/gls ${S}_${R}_p${P}: /"
