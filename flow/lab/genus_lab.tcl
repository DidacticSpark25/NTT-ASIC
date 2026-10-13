# ---------------------------------------------------------------------------
# flow/lab/genus_lab.tcl - the exact Genus sequence used for the lab run
# (Kyber, Barrett, P=2, 3.0 ns, Cadence 45 nm GPDK045 training library).
#
#   cd <repo> ; genus -files flow/lab/genus_lab.tcl
#
# Edit LIBS below. Outputs: syn_out/{area,timing,power,gates,qor}.rpt,
#                           syn_out/ntt_top_netlist.v, syn_out/ntt_top.sdc
# ---------------------------------------------------------------------------
set LIBS    /path/to/FOUNDRY/digital/45nm/LIBS    ;# <-- EDIT (contains lib/ lef/ captbl/ qx/)
set SCHEME  0      ;# 0 = kyber, 1 = dilithium
set RED     0      ;# 0 = barrett, 1 = montgomery
set P       2      ;# butterflies per clock
set CLK_NS  3.0
set OUT     syn_out

set REPO [file normalize [file join [file dirname [info script]] .. ..]]
cd $REPO
file mkdir $OUT build/lab_cfg

# per-run configuration header included by rtl/ntt_top.v
set fp [open build/lab_cfg/ntt_cfg.vh w]
puts $fp "`define NTT_SCHEME $SCHEME\n`define NTT_RED $RED\n`define NTT_P $P"
close $fp

read_libs $LIBS/lib/max/slow.lib
set_db init_hdl_search_path [list build/lab_cfg rtl]
# -sv: Genus reads plain .v as strict Verilog-2001 otherwise
read_hdl -sv {ntt_top.v ntt_core.v ntt_butterfly.v ntt_modmul.v ntt_bank.v ntt_tw_rom.v}
elaborate ntt_top
check_design -unresolved

create_clock -name clk -period $CLK_NS [get_ports clk]
set_input_delay  [expr 0.2*$CLK_NS] -clock clk [remove_from_collection [all_inputs] [get_ports clk]]
set_output_delay [expr 0.2*$CLK_NS] -clock clk [all_outputs]

syn_generic
syn_map
syn_opt

report_qor    > $OUT/qor.rpt
report_area   > $OUT/area.rpt
report_timing > $OUT/timing.rpt
report_power  > $OUT/power.rpt
report_gates  > $OUT/gates.rpt
write_hdl     > $OUT/ntt_top_netlist.v
write_sdc     > $OUT/ntt_top.sdc
report_qor
