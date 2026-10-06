# ---------------------------------------------------------------------------
# flow/config.example.tcl - technology setup for Cadence GPDK045 (gsclib045).
#
#   cp flow/config.example.tcl flow/config.tcl     # flow/config.tcl is git-ignored
#   flow/find_pdk.sh /path/to/gpdk045              # prints the paths on your install
#
# Every Cadence script in this repo sources flow/config.tcl, so this is the only
# file you edit when moving between machines or PDK versions.
# Never commit library, LEF, QRC, GDS or rule-deck files: they are under NDA.
# ---------------------------------------------------------------------------

set GPDK045_ROOT  /cad/libraries/gpdk045                       ;# <-- EDIT
set GSCLIB        $GPDK045_ROOT/gsclib045_all_v4.4/gsclib045    ;# <-- check version

# Liberty: setup corner (slow, 0.9/1.0 V) and hold corner (fast, 1.2 V)
set LIB_SLOW      $GSCLIB/timing/slow_vdd1v0_basicCells.lib
set LIB_FAST      $GSCLIB/timing/fast_vdd1v2_basicCells.lib

# Verilog simulation models of the standard cells (gate-level simulation)
set STD_VERILOG   $GSCLIB/verilog/slow_vdd1v0_basicCells.v

# Physical views
set TECH_LEF      $GSCLIB/lef/gsclib045_tech.lef
set MACRO_LEF     $GSCLIB/lef/gsclib045_macro.lef
set QRC_TECH      $GSCLIB/qrc/qx/gpdk045.tch
set CAP_TABLE     ""                                            ;# optional, QRC tech preferred

# GDS export and physical verification
set STD_GDS       $GSCLIB/gds/gsclib045.gds                     ;# std-cell layouts merged into the GDS
set GDS_MAP       $GPDK045_ROOT/gpdk045_v_6_0/soce/streamOut.map
set STD_CDL       $GSCLIB/cdl/gsclib045.cdl                     ;# for LVS
set PVS_DRC_RULES $GPDK045_ROOT/gpdk045_v_6_0/pvs/pvlDRC.rul
set PVS_LVS_RULES $GPDK045_ROOT/gpdk045_v_6_0/pvs/pvlLVS.rul

# Library specifics
set SITE          CoreSite
set PWR_NET       VDD
set GND_NET       VSS
set FILLER_CELLS  {FILL64 FILL32 FILL16 FILL8 FILL4 FILL2 FILL1}
set DRIVE_CELL    BUFX2
set CTS_BUFS      {CLKBUFX2 CLKBUFX4 CLKBUFX8 CLKBUFX12 CLKBUFX16 CLKBUFX20}
set CTS_INVS      {CLKINVX2 CLKINVX4 CLKINVX8 CLKINVX12 CLKINVX16 CLKINVX20}

# Metal stack: gpdk045 has Metal1..Metal11
set RING_LAYER_H  Metal11
set RING_LAYER_V  Metal10
set STRIPE_LAYER  Metal10
set ROUTE_TOP     Metal9
set ROUTE_BOTTOM  Metal1

# Run control
set NUM_CPUS      8
