# Optional 1/2/4-filter out-of-context synthesis sweep, not routed signoff.
set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir "../.."]]
if {![info exists part_name]} { set part_name "xczu3eg-sbva484-1-e" }
if {![info exists report_dir]} {
    set report_dir [file join $repo_root "hardware/reports/vector_parallelism_sweep"]
}
set rtl_files [list \
    [file join $repo_root "rtl/axis_conv3x3_vector4_preprocess.sv"] \
    [file join $repo_root "rtl/axis_conv3x3_scalable_preprocess.sv"] \
    [file join $repo_root "rtl/axis_conv3x3_scalable_benchmark_top.sv"] \
]
set clock_file [file join $script_dir "../constraints/scalable_conv_100mhz.xdc"]
foreach input_file [concat $rtl_files [list $clock_file]] {
    if {![file isfile $input_file]} { error "Missing sweep input: $input_file" }
}
foreach filters {1 2 4} {
    set output_dir [file join $report_dir "filters_$filters"]
    file mkdir $output_dir
    create_project -in_memory "vector_filters_$filters" -part $part_name
    read_verilog -sv $rtl_files
    read_xdc $clock_file
    synth_design -top axis_conv3x3_scalable_benchmark_top -part $part_name \
        -mode out_of_context -generic "PARALLEL_FILTERS=$filters"
    report_utilization -file [file join $output_dir "utilization.rpt"]
    report_timing_summary -file [file join $output_dir "timing_summary.rpt"]
    write_checkpoint -force [file join $output_dir "synth.dcp"]
    close_project
}
puts "Out-of-context synthesis sweep complete: $report_dir"
