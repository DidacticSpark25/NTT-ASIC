# ---------------------------------------------------------------------------
# flow/voltus/power.tcl - sign-off power with Cadence Voltus (make power ...)
#
# Static (vectorless) power on the routed design with default switching activity.
# For activity-annotated power, dump a VCD/SAIF from a gate-level Xcelium run and
# replace set_default_switching_activity with read_activity_file.
#
# IR-drop (rail) analysis needs power-grid libraries generated once per PDK;
# set RUN_RAIL=1 to try it (see the comments at the end).
# ---------------------------------------------------------------------------
set REPO  $::env(REPO)
set BUILD $::env(BUILD)
source $REPO/flow/config.tcl
file mkdir rpt

set SDC_FILE $BUILD/syn/out/ntt_top.syn.sdc
read_lib -lef [list $TECH_LEF $MACRO_LEF]
read_view_definition $REPO/flow/innovus/mmmc.tcl
read_verilog $BUILD/pnr/out/ntt_top.pnr.v
set_top_module ntt_top -ignore_undefined_cell
read_def  $BUILD/pnr/out/ntt_top.def
read_spef -rc_corner rc_typ $BUILD/pnr/out/ntt_top.spef

set_power_analysis_mode -reset
set_power_analysis_mode -method static -analysis_view av_setup -write_static_currents true
set_default_switching_activity -input_activity 0.2 -seq_activity 0.1
set_power_output_dir rpt/power
report_power -outfile rpt/power.rpt
report_power -hierarchy all -outfile rpt/power_hier.rpt

if {[info exists ::env(RUN_RAIL)] && $::env(RUN_RAIL) == 1} {
    # One-time PGV characterisation of the standard cells (takes a while)
    set_pg_library_mode -celltype techonly -extraction_tech_file $QRC_TECH -default_power_voltage 1.0
    generate_pg_library -output rpt/pgv
    set_rail_analysis_mode -method static -accuracy xd \
        -power_grid_library rpt/pgv/techonly.cl -extraction_tech_file $QRC_TECH
    set_pg_nets -net $PWR_NET -voltage 1.0 -threshold 0.95   ;# 5% IR-drop budget
    set_pg_nets -net $GND_NET -voltage 0.0 -threshold 0.05
    set_power_data -format current -scale 1 [list rpt/power/static_${PWR_NET}.ptiavg rpt/power/static_${GND_NET}.ptiavg]
    analyze_rail -type net -results_directory rpt/rail $PWR_NET
}

puts "VOLTUS DONE"
exit
