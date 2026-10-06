# ---------------------------------------------------------------------------
# flow/innovus/pnr.tcl - netlist to GDSII with Cadence Innovus (gpdk045)
#
#   floorplan -> power grid -> pins -> place -> CTS -> route -> post-route opt
#   -> fillers -> DRC / connectivity / antenna -> extraction -> GDSII
#
# Run via the Makefile (make pnr ...). Environment:
#   REPO, BUILD   as for Genus
#   UTIL          core utilization (default 0.60)
# Written for the Innovus "legacy" command set used in most university installs
# (Innovus 17.x - 21.x). Report-only commands are wrapped in `catch` so a version
# difference in a report never kills a multi-hour run.
# ---------------------------------------------------------------------------
set REPO  $::env(REPO)
set BUILD $::env(BUILD)
set UTIL  [expr {[info exists ::env(UTIL)] ? $::env(UTIL) : 0.60}]
source $REPO/flow/config.tcl

file mkdir out rpt db
setMultiCpuUsage -localCpu $NUM_CPUS
proc rpt {cmd} { if {[catch {uplevel 1 $cmd} msg]} { puts "WARN: report failed: $cmd :: $msg" } }
proc layer_num {name} { regexp {(\d+)$} $name -> n; return $n }

# ---------------- design import ----------------
set SDC_FILE        $BUILD/syn/out/ntt_top.syn.sdc
set init_verilog    $BUILD/syn/out/ntt_top.syn.v
set init_top_cell   ntt_top
set init_lef_file   [list $TECH_LEF $MACRO_LEF]
set init_mmmc_file  $REPO/flow/innovus/mmmc.tcl
set init_pwr_net    $PWR_NET
set init_gnd_net    $GND_NET
init_design

setDesignMode -process 45
setAnalysisMode -analysisType onChipVariation -cppr both

# ---------------- floorplan ----------------
set CORE_MARGIN 12
floorPlan -site $SITE -r 1.0 $UTIL $CORE_MARGIN $CORE_MARGIN $CORE_MARGIN $CORE_MARGIN

globalNetConnect $PWR_NET -type pgpin -pin $PWR_NET -inst * -override
globalNetConnect $GND_NET -type pgpin -pin $GND_NET -inst * -override
globalNetConnect $PWR_NET -type tiehi -inst *
globalNetConnect $GND_NET -type tielo -inst *

# ---------------- power grid ----------------
addRing -nets [list $PWR_NET $GND_NET] -type core_rings -follow core \
    -layer [list top $RING_LAYER_H bottom $RING_LAYER_H left $RING_LAYER_V right $RING_LAYER_V] \
    -width 2.0 -spacing 1.0 -offset 1.0
addStripe -nets [list $PWR_NET $GND_NET] -layer $STRIPE_LAYER -direction vertical \
    -width 1.0 -spacing 1.0 -set_to_set_distance 40 -start_from left -start_offset 15
sroute -connect {corePin} -nets [list $PWR_NET $GND_NET] \
    -corePinTarget {firstAfterRowEnd} -allowJogging 1 -allowLayerChange 1

# ---------------- I/O pins: inputs left, outputs right ----------------
set ins  [dbGet [dbGet -p top.terms.isInput 1].name]
set outs [dbGet [dbGet -p top.terms.isOutput 1].name]
editPin -side Left  -layer Metal4 -spreadType side -pin $ins  -fixOverlap 1 -unit MICRON
editPin -side Right -layer Metal4 -spreadType side -pin $outs -fixOverlap 1 -unit MICRON
saveDesign db/ntt_top_floorplan.enc

# ---------------- placement ----------------
setPlaceMode -timingDriven true -congEffort high
place_opt_design -out_dir rpt/place_opt
rpt { checkPlace rpt/check_place.rpt }
# routing-congestion snapshot: this is the number the P = 1/2/4 study compares
rpt { reportCongestion -hotSpot > rpt/congestion_place.rpt }
rpt { reportCongestion -overflow >> rpt/congestion_place.rpt }
rpt { timeDesign -preCTS -outDir rpt/prects -prefix prects }
saveDesign db/ntt_top_place.enc

# ---------------- clock tree synthesis ----------------
set_ccopt_property buffer_cells   $CTS_BUFS
set_ccopt_property inverter_cells $CTS_INVS
create_ccopt_clock_tree_spec -file out/ccopt.spec
source out/ccopt.spec
ccopt_design -outDir rpt/ccopt
rpt { report_ccopt_clock_trees -file rpt/clock_trees.rpt }
rpt { report_ccopt_skew_groups -file rpt/skew_groups.rpt }
optDesign -postCTS -hold -outDir rpt/postcts_opt
rpt { timeDesign -postCTS       -outDir rpt/postcts -prefix postcts }
rpt { timeDesign -postCTS -hold -outDir rpt/postcts -prefix postcts_hold }
saveDesign db/ntt_top_cts.enc

# ---------------- routing ----------------
setNanoRouteMode -routeTopRoutingLayer    [layer_num $ROUTE_TOP] \
                 -routeBottomRoutingLayer [layer_num $ROUTE_BOTTOM] \
                 -routeWithTimingDriven true -routeWithSiDriven true \
                 -drouteFixAntenna true
routeDesign -globalDetail
setExtractRCMode -engine postRoute -effortLevel medium
optDesign -postRoute -setup -hold -outDir rpt/postroute_opt
saveDesign db/ntt_top_route.enc

# ---------------- fillers ----------------
setFillerMode -core $FILLER_CELLS -corePrefix FILL
addFiller
ecoRoute

# ---------------- sign-off checks inside Innovus ----------------
rpt { verify_drc -limit 100000 -report rpt/verify_drc.rpt }
rpt { verifyConnectivity -type all -error 100000 -report rpt/verify_conn.rpt }
rpt { verifyProcessAntenna -report rpt/verify_antenna.rpt }

# ---------------- final reports ----------------
rpt { timeDesign -postRoute       -outDir rpt/signoff -prefix postroute }
rpt { timeDesign -postRoute -hold -outDir rpt/signoff -prefix postroute_hold }
rpt { report_timing -max_paths 20 > rpt/timing_setup.rpt }
rpt { summaryReport -noHtml -outfile rpt/summary.rpt }
rpt { reportGateCount -level 3 -outfile rpt/gate_count.rpt }
rpt { report_area > rpt/area.rpt }
rpt { reportDensityMap > rpt/density.rpt }
rpt {
    set_power_analysis_mode -reset
    set_power_analysis_mode -method static -analysis_view av_setup
    set_default_switching_activity -input_activity 0.2 -seq_activity 0.1
    report_power -outfile rpt/power.rpt
}
# die size for the PPA table
rpt {
    set fp [open rpt/die.rpt w]
    puts $fp "DIE_BOX  [dbGet top.fPlan.box]"
    puts $fp "CORE_BOX [dbGet top.fPlan.coreBox]"
    puts $fp "UTIL     $UTIL"
    close $fp
}

# ---------------- outputs ----------------
rcOut -spef out/ntt_top.spef -rc_corner rc_typ
saveNetlist out/ntt_top.pnr.v
saveNetlist out/ntt_top.lvs.v -includePowerGround -excludeLeafCell
rpt { write_sdf out/ntt_top.sdf -view av_setup }
defOut -floorplan -netlist -routing out/ntt_top.def
streamOut out/ntt_top.gds -mapFile $GDS_MAP -merge [list $STD_GDS] \
    -stripes 1 -units 2000 -mode ALL
saveDesign db/ntt_top_final.enc

puts "INNOVUS DONE"
exit
