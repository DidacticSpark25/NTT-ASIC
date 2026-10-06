# ---------------------------------------------------------------------------
# flow/tempus/sta.tcl - sign-off static timing on the routed netlist + SPEF
# (make sta ...). Setup at slow corner, hold at fast corner, OCV with CPPR.
# ---------------------------------------------------------------------------
set REPO  $::env(REPO)
set BUILD $::env(BUILD)
source $REPO/flow/config.tcl
file mkdir rpt

set SDC_FILE $BUILD/syn/out/ntt_top.syn.sdc
read_view_definition $REPO/flow/innovus/mmmc.tcl
read_verilog $BUILD/pnr/out/ntt_top.pnr.v
set_top_module ntt_top
read_spef -rc_corner rc_typ $BUILD/pnr/out/ntt_top.spef

set_analysis_mode -analysisType onChipVariation -cppr both
update_timing -full

report_analysis_summary                          > rpt/summary.rpt
report_timing -late  -max_paths 50               > rpt/setup.rpt
report_timing -early -max_paths 50               > rpt/hold.rpt
report_constraint -all_violators                 > rpt/violators.rpt
report_clocks                                    > rpt/clocks.rpt
check_timing -verbose                            > rpt/check_timing.rpt

puts "TEMPUS DONE"
exit
