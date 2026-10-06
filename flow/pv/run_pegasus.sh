#!/usr/bin/env bash
# run_pegasus.sh <build_dir> <drc|lvs> - deck-based physical verification with Cadence Pegasus.
# Template: confirm the deck's expected include/variables on your install (see flow/pv/README.md).
set -eu
REPO=$(cd "$(dirname "$0")/../.." && pwd)
BUILD=$(cd "${1:?build dir}" && pwd)
MODE=${2:?drc|lvs}
OUT=$BUILD/pv_$MODE
mkdir -p "$OUT" && cd "$OUT"
GDS=$BUILD/pnr/out/ntt_top.gds

if [ "$MODE" = drc ]; then
    RULES=$("$REPO/flow/cfg_get.sh" PVS_DRC_RULES)
    cat > drc.ctl <<EOF
include "$RULES"
layout_path "$GDS"
layout_primary "ntt_top"
layout_format gdsii
results_db -drc "ntt_top.drc_errors.ascii" -ascii
report_summary -drc "ntt_top.drc.sum" -replace
EOF
    pegasus -drc -dp 4 -control drc.ctl > pegasus_drc.log 2>&1 || true
    tail -n 30 ntt_top.drc.sum 2>/dev/null || tail -n 30 pegasus_drc.log
else
    RULES=$("$REPO/flow/cfg_get.sh" PVS_LVS_RULES)
    CDL=$("$REPO/flow/cfg_get.sh" STD_CDL)
    cat > lvs.ctl <<EOF
include "$RULES"
layout_path "$GDS"
layout_primary "ntt_top"
layout_format gdsii
schematic_path "$BUILD/pnr/out/ntt_top.lvs.v" verilog
schematic_path "$CDL" cdl
schematic_primary "ntt_top"
lvs_report_file "ntt_top.lvs.rpt"
EOF
    pegasus -lvs -dp 4 -control lvs.ctl > pegasus_lvs.log 2>&1 || true
    grep -iE "CORRECT|INCORRECT|MATCH" ntt_top.lvs.rpt 2>/dev/null | head || tail -n 30 pegasus_lvs.log
fi
