# Package the production-v2 dual-clock vector preprocessor for Ultra96-V1.
# This uses a separate IP repository and never modifies historical packages.

set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir "../.."]]
set ip_repo_dir [file normalize [file join $repo_root "vivado/ip_repo_ultra96_production_v2"]]
set ip_root [file normalize [file join $ip_repo_dir "axis_preprocess_vector_cdc"]]

# Keep this name private to packaging. This Tcl can be sourced by the V2
# project creator, whose project part is the industrial-grade -1-i device.
set package_part_name "xczu3eg-sbva484-1-e"
set vendor_name "user.org"
set library_name "u96_ai_vision"
set ip_name "axis_preprocess_vector_cdc"
set ip_version "2.0"

puts "Repo root: $repo_root"
puts "Production-v2 IP output: $ip_root"

file mkdir $ip_repo_dir
if {[file exists $ip_root]} {
    puts "Replacing existing production-v2 packaged IP at $ip_root"
    file delete -force $ip_root
}

create_project -in_memory axis_preprocess_v2_u96_packager -part $package_part_name

set rtl_files [list \
    [file join $repo_root "rtl/sobel_core.sv"] \
    [file join $repo_root "rtl/image_sobel_engine.sv"] \
    [file join $repo_root "rtl/axis_threshold_preprocess.sv"] \
    [file join $repo_root "rtl/axis_sobel_preprocess.sv"] \
    [file join $repo_root "rtl/axis_conv3x3_parallel_preprocess.sv"] \
    [file join $repo_root "rtl/axis_conv3x3_vector4_preprocess.sv"] \
    [file join $repo_root "rtl/axis_preprocess_vector_axi_lite.sv"] \
    [file join $repo_root "rtl/axis_preprocess_vector_cdc.sv"] \
]

foreach rtl_file $rtl_files {
    if {![file exists $rtl_file]} {
        error "Missing RTL source: $rtl_file"
    }
}

add_files -norecurse $rtl_files
set_property top axis_preprocess_vector_cdc [current_fileset]
update_compile_order -fileset sources_1

ipx::package_project \
    -root_dir $ip_root \
    -vendor $vendor_name \
    -library $library_name \
    -taxonomy /UserIP \
    -import_files \
    -set_current true

set core [ipx::current_core]
set_property name $ip_name $core
set_property display_name "Ultra96 AI Vision Production-v2 CDC Preprocessor" $core
set_property description "Dual-clock production AXI4-Lite/AXI4-Stream vision preprocessor with diagnostics, IRQ, CDC bridge, and four packed INT8 features." $core
set_property vendor $vendor_name $core
set_property library $library_name $core
set_property version $ip_version $core
set_property core_revision 1 $core
set_property supported_families {zynquplus Production} $core

ipx::infer_bus_interfaces $core

foreach busif_name {S_AXI S_AXIS M_AXIS} {
    set busif [ipx::get_bus_interfaces -quiet $busif_name -of_objects $core]
    if {[llength $busif] == 0} {
        error "Bus interface $busif_name was not inferred."
    }
}

ipx::associate_bus_interfaces -busif S_AXI -clock S_AXI_ACLK $core
ipx::associate_bus_interfaces -busif S_AXIS -clock AXIS_ACLK $core
ipx::associate_bus_interfaces -busif M_AXIS -clock AXIS_ACLK $core

ipx::update_checksums $core
ipx::check_integrity $core
ipx::save_core $core

set_property ip_repo_paths [list $ip_repo_dir] [current_project]
update_ip_catalog

puts ""
puts "Production-v2 dual-clock packaged IP complete."
puts "VLNV: $vendor_name:$library_name:$ip_name:$ip_version"
puts "IP repo: $ip_repo_dir"
puts ""

close_project
