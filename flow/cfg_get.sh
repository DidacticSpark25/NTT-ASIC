#!/usr/bin/env bash
# cfg_get.sh VAR - print a variable from flow/config.tcl (lets shell scripts share the Tcl config).
# An environment variable of the same name wins, e.g.  STD_VERILOG=/path/cells.v make gls
cd "$(dirname "$0")/.."
if [ -n "${!1:-}" ]; then echo "${!1}"; exit 0; fi
[ -f flow/config.tcl ] || { echo "flow/config.tcl missing: cp flow/config.example.tcl flow/config.tcl" >&2; exit 1; }
TCL=$(command -v tclsh || command -v tclsh8.6 || command -v tclsh8.5 || true)
if [ -z "$TCL" ]; then
    echo "tclsh not found: set $1 in the environment instead (export $1=/full/path)" >&2; exit 1
fi
echo "source flow/config.tcl; puts \$$1" | "$TCL"
