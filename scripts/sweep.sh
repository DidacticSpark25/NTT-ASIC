#!/usr/bin/env bash
# sweep.sh - design-space sweep on the Cadence flow.
#   scheme {kyber, dilithium} x reduction {barrett, montgomery} x P {1,2,4}
#
#   scripts/sweep.sh                     # Genus only (fast: ~minutes per config)
#   PNR=1 scripts/sweep.sh               # + Innovus to GDSII and Tempus (hours total)
#   SCHEMES=kyber PS="2 4" scripts/sweep.sh
#   CLK=2.5 scripts/sweep.sh             # tighter clock for every config
#
# Runs configs one at a time so it never needs more than one licence of each tool.
# Results: build/<cfg>/... then results/ppa.{csv,md,png} via scripts/collect_ppa.py
set -u
cd "$(dirname "$0")/.."
SCHEMES=${SCHEMES:-"kyber dilithium"}
REDS=${REDS:-"barrett montgomery"}
PS=${PS:-"1 2 4"}
CLK=${CLK:-3.0}
PNR=${PNR:-0}

for s in $SCHEMES; do for r in $REDS; do for p in $PS; do
    cfg="${s}_${r}_p${p}"
    echo "==================== $cfg (CLK=${CLK}ns) ===================="
    make --no-print-directory syn SCHEME=$s RED=$r P=$p CLK=$CLK > build/sweep_${cfg}_syn.log 2>&1 \
        && echo "  syn  OK" || { echo "  syn  FAILED (build/sweep_${cfg}_syn.log)"; continue; }
    if [ "$PNR" = 1 ]; then
        make --no-print-directory pnr SCHEME=$s RED=$r P=$p CLK=$CLK > build/sweep_${cfg}_pnr.log 2>&1 \
            && echo "  pnr  OK" || { echo "  pnr  FAILED (build/sweep_${cfg}_pnr.log)"; continue; }
        make --no-print-directory sta SCHEME=$s RED=$r P=$p CLK=$CLK > build/sweep_${cfg}_sta.log 2>&1 \
            && echo "  sta  OK" || echo "  sta  FAILED (build/sweep_${cfg}_sta.log)"
    fi
done; done; done

python3 scripts/collect_ppa.py
