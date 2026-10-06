# flow/innovus/mmmc.tcl - multi-mode multi-corner setup (Innovus and Tempus)
# Expects flow/config.tcl already sourced and SDC_FILE set by the caller.

create_library_set -name libs_slow -timing [list $LIB_SLOW]
create_library_set -name libs_fast -timing [list $LIB_FAST]

if {$CAP_TABLE ne ""} {
    create_rc_corner -name rc_typ -cap_table $CAP_TABLE -qx_tech_file $QRC_TECH -T 25
} else {
    create_rc_corner -name rc_typ -qx_tech_file $QRC_TECH -T 25
}

create_delay_corner -name dc_slow -library_set libs_slow -rc_corner rc_typ
create_delay_corner -name dc_fast -library_set libs_fast -rc_corner rc_typ

create_constraint_mode -name func -sdc_files [list $SDC_FILE]

create_analysis_view -name av_setup -constraint_mode func -delay_corner dc_slow
create_analysis_view -name av_hold  -constraint_mode func -delay_corner dc_fast

set_analysis_view -setup [list av_setup] -hold [list av_hold]
