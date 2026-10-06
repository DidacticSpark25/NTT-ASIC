# ---------------------------------------------------------------------------
# flow/genus/syn.tcl - logic synthesis with Cadence Genus (gpdk045, slow corner)
#
# Run via the Makefile (make syn ...), which sets:
#   REPO   absolute path of the repository
#   BUILD  absolute path of this configuration's build directory
#          (contains ntt_cfg.vh and ntt_top.sdc)
# Outputs in $BUILD/syn: out/ntt_top.syn.v, out/ntt_top.syn.sdc, out/lec.do, rpt/*
# ---------------------------------------------------------------------------
set REPO  $::env(REPO)
set BUILD $::env(BUILD)
source $REPO/flow/config.tcl

file mkdir out rpt
set_db information_level 7
set_db max_cpus_per_server $NUM_CPUS

# ---------------- libraries ----------------
set_db library   [list $LIB_SLOW]
set_db lef_library [list $TECH_LEF $MACRO_LEF]
if {[file exists $QRC_TECH]} { set_db qrc_tech_file $QRC_TECH }

# ---------------- RTL ----------------
# ntt_cfg.vh (per configuration) lives in $BUILD; shared headers live in rtl/
set_db init_hdl_search_path [list $BUILD $REPO/rtl]
read_hdl -language v2001 [list \
    $REPO/rtl/ntt_top.v      \
    $REPO/rtl/ntt_core.v     \
    $REPO/rtl/ntt_butterfly.v\
    $REPO/rtl/ntt_modmul.v   \
    $REPO/rtl/ntt_bank.v     \
    $REPO/rtl/ntt_tw_rom.v ]
elaborate ntt_top
check_design -unresolved > rpt/check_design.rpt
check_design -all        >> rpt/check_design.rpt

# ---------------- constraints ----------------
read_sdc $BUILD/ntt_top.sdc
report_timing -lint > rpt/timing_lint.rpt

# ---------------- synthesis ----------------
# keep module boundaries so report_area can split banks / butterflies / ROMs
set_db auto_ungroup none
set_db syn_generic_effort high
set_db syn_map_effort     high
set_db syn_opt_effort     high

syn_generic
report_area > rpt/area_generic.rpt
syn_map
syn_opt

# ---------------- reports ----------------
# report_area is hierarchical: it splits banks / butterflies / ROMs / control,
# which is what the PPA study needs.
report_qor                         > rpt/qor.rpt
report_area                        > rpt/area.rpt
report_gates                       > rpt/gates.rpt
report_timing -max_paths 20        > rpt/timing.rpt
report_power                       > rpt/power.rpt
report_messages                    > rpt/messages.rpt

# ---------------- outputs ----------------
write_hdl > out/ntt_top.syn.v
write_sdc > out/ntt_top.syn.sdc
write_do_lec -revised_design out/ntt_top.syn.v \
             -logfile out/lec.log > out/lec.do
write_db  out/ntt_top.syn.db

puts "GENUS DONE"
exit
