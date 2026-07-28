# Implement the Ultra96-V1 production-v2 dual-clock DMA project, emit release
# reports, generate the bitstream, and export an XSA. Run only after synth review.

set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir "../.."]]
if {![info exists project_path]} {
    set project_path [file normalize [file join $repo_root "vivado/u96_production_v2_vivado/u96_production_v2.xpr"]]
}
set ip_repo_dir [file normalize [file join $repo_root "vivado/ip_repo_ultra96_production_v2"]]
if {![info exists report_dir]} {
    set report_dir [file normalize [file join $repo_root "hardware/reports/production_v2/impl"]]
}
if {![info exists xsa_path]} {
    set xsa_path [file normalize [file join $repo_root "vivado/ultra96_v1_ai_vision_production_v2.xsa"]]
}
if {![info exists ultra96_board_label]} {
    set ultra96_board_label "Ultra96-V1"
}

if {![file exists $project_path]} {
    error "Missing production-v2 project: $project_path."
}

file mkdir $report_dir
if {[info exists ::env(ULTRA96_BOARD_REPO)] &&
    [file exists $::env(ULTRA96_BOARD_REPO)]} {
    set_param board.repoPaths [list [file normalize $::env(ULTRA96_BOARD_REPO)]]
}
open_project $project_path
set project_ip_repos [list $ip_repo_dir]
if {[info exists additional_ip_repos]} {
    set project_ip_repos [concat $project_ip_repos $additional_ip_repos]
}
set_property ip_repo_paths $project_ip_repos [current_project]
update_ip_catalog
report_ip_status -file [file join $report_dir "ip_status.rpt"]

if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "Production-v2 synthesis is not complete. Run and review the synthesis script first."
}

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
puts "impl_1 status: $impl_status"
if {[string first "write_bitstream Complete" $impl_status] < 0} {
    error "Production-v2 implementation did not complete bitstream generation successfully."
}

open_run impl_1
report_timing_summary -file [file join $report_dir "timing_summary.rpt"]
report_utilization -file [file join $report_dir "utilization.rpt"]
report_utilization -hierarchical -hierarchical_depth 6 \
    -file [file join $report_dir "hierarchical_utilization.rpt"]
report_cdc -details -file [file join $report_dir "cdc.rpt"]
report_clock_interaction -file [file join $report_dir "clock_interaction.rpt"]
report_methodology -file [file join $report_dir "methodology.rpt"]
report_power -file [file join $report_dir "power.rpt"]
report_drc -file [file join $report_dir "drc.rpt"]

write_hw_platform -fixed -include_bit -force -file $xsa_path

puts ""
puts "$ultra96_board_label production-v2 implementation and XSA export complete."
puts "Reports: $report_dir"
puts "XSA: $xsa_path"
puts ""

close_project
