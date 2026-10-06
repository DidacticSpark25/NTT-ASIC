#!/usr/bin/env bash
# cfg_get.sh VAR - print a variable from flow/config.tcl (lets shell scripts share the Tcl config)
cd "$(dirname "$0")/.."
[ -f flow/config.tcl ] || { echo "flow/config.tcl missing: cp flow/config.example.tcl flow/config.tcl" >&2; exit 1; }
echo "source flow/config.tcl; puts \$$1" | tclsh
