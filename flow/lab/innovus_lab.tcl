# ---------------------------------------------------------------------------
# flow/lab/innovus_lab.tcl - the exact Innovus sequence used for the lab run.
#
#   cd <repo>/pnr ; innovus -files ../flow/lab/innovus_lab.tcl
#
# Needs syn_out/ from flow/lab/genus_lab.tcl. Edit LIBS below.
# Outputs in pnr/: ntt_top.gds, ntt_top_pnr.v, summary.rpt, area.rpt, power.rpt,
#                  rpt_signoff/ (post-route setup + hold), *.enc checkpoints
# ---------------------------------------------------------------------------
set LIBS /path/to/FOUNDRY/digital/45nm/LIBS          ;# <-- EDIT
set REPO [file normalize [file join [file dirname [info script]] .. ..]]
file mkdir $REPO/pnr
cd $REPO/pnr

# ---- timing corners: slow lib for setup, fast lib for hold ----
set fp [open mmmc.tcl w]
puts $fp "create_library_set -name slow_set -timing \[list $LIBS/lib/max/slow.lib\]
create_library_set -name fast_set -timing \[list $LIBS/lib/min/fast.lib\]
create_rc_corner -name rc_typ -T 25
create_delay_corner -name dc_slow -library_set slow_set -rc_corner rc_typ
create_delay_corner -name dc_fast -library_set fast_set -rc_corner rc_typ
create_constraint_mode -name func -sdc_files \[list $REPO/syn_out/ntt_top.sdc\]
create_analysis_view -name av_setup -constraint_mode func -delay_corner dc_slow
create_analysis_view -name av_hold  -constraint_mode func -delay_corner dc_fast
set_analysis_view -setup \[list av_setup\] -hold \[list av_hold\]"
close $fp

# ---- import ----
set init_verilog   $REPO/syn_out/ntt_top_netlist.v
set init_top_cell  ntt_top
set init_lef_file  $LIBS/lef/gsclib045.fixed.lef     ;# tech + cells in one LEF (Metal1..Metal9, CoreSite)
set init_mmmc_file [pwd]/mmmc.tcl
set init_pwr_net   VDD
set init_gnd_net   VSS
init_design
# post-route timing and optimization refuse to run without OCV mode (IMPOPT-7027)
setAnalysisMode -analysisType onChipVariation -cppr both

# ---- floorplan + power grid ----
floorPlan -site CoreSite -r 1.0 0.6 10 10 10 10
globalNetConnect VDD -type pgpin -pin VDD -inst * -override
globalNetConnect VSS -type pgpin -pin VSS -inst * -override
globalNetConnect VDD -type tiehi -inst *
globalNetConnect VSS -type tielo -inst *
addRing -nets {VDD VSS} -type core_rings -follow core \
    -layer {top Metal9 bottom Metal9 left Metal8 right Metal8} -width 2 -spacing 1 -offset 1
addStripe -nets {VDD VSS} -layer Metal8 -direction vertical -width 1 -spacing 1 \
    -set_to_set_distance 40 -start_offset 15
sroute -connect {corePin} -nets {VDD VSS}
saveDesign floorplan.enc

# ---- placement + clock tree ----
setPlaceMode -place_global_place_io_pins true
place_opt_design
saveDesign placed.enc
create_ccopt_clock_tree_spec
ccopt_design
optDesign -postCTS -hold
timeDesign -postCTS -outDir rpt_postcts
saveDesign cts.enc

# ---- routing + post-route optimization ----
routeDesign
setExtractRCMode -engine postRoute
optDesign -postRoute -setup -hold
addFiller -cell {FILL64 FILL32 FILL16 FILL8 FILL4 FILL2 FILL1} -prefix FILL

# ---- checks and reports ----
verify_drc
verifyConnectivity
timeDesign -postRoute       -outDir rpt_signoff
timeDesign -postRoute -hold -outDir rpt_signoff
report_area > area.rpt
report_power -outfile power.rpt
summaryReport -noHtml -outfile summary.rpt

# ---- outputs ----
saveNetlist ntt_top_pnr.v
streamOut ntt_top.gds -units 2000 -mode ALL
saveDesign final.enc
