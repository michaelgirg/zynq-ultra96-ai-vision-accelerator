# Synthesize the Ultra96-V1 production-v2 dual-clock DMA project and emit the
# reports required before implementation. Run manually in licensed Vivado.

set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir "../.."]]
if {![info exists project_path]} {
    set project_path [file normalize [file join $repo_root "vivado/u96_production_v2_vivado/u96_production_v2.xpr"]]
}
set ip_repo_dir [file normalize [file join $repo_root "vivado/ip_repo_ultra96_production_v2"]]
if {![info exists report_dir]} {
    set report_dir [file normalize [file join $repo_root "hardware/reports/production_v2/synth"]]
}
if {![info exists ultra96_board_label]} {
    set ultra96_board_label "Ultra96-V1"
}
if {![info exists ultra96_create_script]} {
    set ultra96_create_script "create_ultra96_v1_production_v2_project.tcl"
}

if {![file exists $project_path]} {
    error "Missing production-v2 project: $project_path. Run $ultra96_create_script first."
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

set production_ip [get_ips -quiet -filter {IPDEF =~ "*:axis_preprocess_vector_cdc:*"}]
if {[llength $production_ip] == 0} {
    error "The production-v2 packaged IP is missing from the project."
}
if {[llength [get_ips -quiet -filter {IS_LOCKED == 1}]] != 0} {
    error "One or more project IPs are locked; review ip_status.rpt before synthesis."
}

set bd_files [get_files -quiet "*.bd"]
if {[llength $bd_files] != 0} {
    generate_target all $bd_files
}
update_compile_order -fileset sources_1

set top_module [get_property top [get_filesets sources_1]]
if {$top_module eq ""} {
    error "No synthesis top is set. Recreate the production-v2 block design."
}
puts "Synthesis top: $top_module"

reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
puts "synth_1 status: $synth_status"
if {[string first "synth_design Complete" $synth_status] < 0} {
    error "Production-v2 synthesis did not complete successfully."
}

open_run synth_1
report_timing_summary -file [file join $report_dir "timing_summary.rpt"]
report_utilization -file [file join $report_dir "utilization.rpt"]
report_utilization -hierarchical -hierarchical_depth 6 \
    -file [file join $report_dir "hierarchical_utilization.rpt"]
report_cdc -details -file [file join $report_dir "cdc.rpt"]
report_clock_interaction -file [file join $report_dir "clock_interaction.rpt"]
report_methodology -file [file join $report_dir "methodology.rpt"]
report_power -file [file join $report_dir "power.rpt"]

puts ""
puts "$ultra96_board_label production-v2 synthesis complete."
puts "Reports: $report_dir"
puts "Review timing, CDC, clock interaction, methodology, utilization, and power before implementation."
puts ""

close_project
