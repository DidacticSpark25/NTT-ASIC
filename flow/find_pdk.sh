#!/usr/bin/env bash
# find_pdk.sh - locate the GPDK045 files flow/config.tcl needs on *your* install.
# Usage: flow/find_pdk.sh /path/to/gpdk045
# File names differ slightly between gpdk045 / gsclib045 releases; this prints every
# candidate so you can paste the right ones into flow/config.tcl.
ROOT=${1:?usage: flow/find_pdk.sh /path/to/gpdk045}
show() { printf "\n# %s\n" "$1"; find "$ROOT" -iname "$2" 2>/dev/null | head -n 8; }
show "LIB_SLOW (setup corner)"  "slow*basic*.lib"
show "LIB_FAST (hold corner)"   "fast*basic*.lib"
show "STD_VERILOG (cell models)" "*basicCells*.v"
show "TECH_LEF"                 "*tech*.lef"
show "MACRO_LEF"                "gsclib045*macro*.lef"
show "QRC_TECH"                 "*.tch"
show "CAP_TABLE"                "*.capTbl"
show "STD_GDS"                  "gsclib045*.gds*"
show "GDS_MAP"                  "*stream*.map"
show "STD_CDL"                  "gsclib045*.cdl"
show "PVS/Pegasus DRC rules"    "*DRC*.rul"
show "PVS/Pegasus LVS rules"    "*LVS*.rul"
show "Calibre rules"            "*calibre*"
