# Package the RV32 control subsystem and job mailbox as reusable Vivado IP.

set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir "../.."]]
set ip_repo_dir [file normalize [file join $repo_root "vivado/ip_repo_rv32_soc"]]
set package_part_name "xczu3eg-sbva484-1-i"
set vendor_name "user.org"
set library_name "u96_ai_vision"

file mkdir $ip_repo_dir

set common_files [list \
    [file join $repo_root "rtl/riscv/common/rv32i_pkg.sv"] \
    [file join $repo_root "rtl/riscv/common/pc.sv"] \
    [file join $repo_root "rtl/riscv/common/imm_gen.sv"] \
    [file join $repo_root "rtl/riscv/common/branch_unit.sv"] \
    [file join $repo_root "rtl/riscv/common/decoder.sv"] \
    [file join $repo_root "rtl/riscv/common/alu.sv"] \
    [file join $repo_root "rtl/riscv/common/regfile.sv"] \
]
set pipeline_files [list \
    [file join $repo_root "rtl/riscv/pipeline/if_id_reg.sv"] \
    [file join $repo_root "rtl/riscv/pipeline/id_ex_reg.sv"] \
    [file join $repo_root "rtl/riscv/pipeline/ex_mem_reg.sv"] \
    [file join $repo_root "rtl/riscv/pipeline/mem_wb_reg.sv"] \
    [file join $repo_root "rtl/riscv/pipeline/forwarding_unit.sv"] \
    [file join $repo_root "rtl/riscv/pipeline/load_use_hazard_unit.sv"] \
    [file join $repo_root "rtl/riscv/pipeline/pipeline_control.sv"] \
    [file join $repo_root "rtl/riscv/pipeline/mul_unit.sv"] \
    [file join $repo_root "rtl/riscv/pipeline/div_unit.sv"] \
    [file join $repo_root "rtl/riscv/pipeline/muldiv_unit.sv"] \
    [file join $repo_root "rtl/riscv/pipeline/slow_line_memory.sv"] \
    [file join $repo_root "rtl/riscv/pipeline/plru.sv"] \
    [file join $repo_root "rtl/riscv/pipeline/dcache.sv"] \
    [file join $repo_root "rtl/riscv/pipeline/icache.sv"] \
    [file join $repo_root "rtl/riscv/pipeline/core_pipeline.sv"] \
]
set soc_files [list \
    [file join $repo_root "rtl/riscv/soc/soc_address_map_pkg.sv"] \
    [file join $repo_root "rtl/riscv/soc/rv32_mmio_router.sv"] \
    [file join $repo_root "rtl/riscv/soc/rv32_axi_lite_master.sv"] \
    [file join $repo_root "rtl/riscv/soc/rv32_pipeline_axi_top.sv"] \
    [file join $repo_root "rtl/riscv/soc/rv32_axi_memory_portal.sv"] \
    [file join $repo_root "rtl/riscv/soc/rv32_pipeline_axi_subsystem.sv"] \
]

foreach rtl_file [concat $common_files $pipeline_files $soc_files \
                  [list [file join $repo_root "rtl/riscv/soc/rv32_job_mailbox.sv"]]] {
    if {![file exists $rtl_file]} {
        error "Missing RV32 IP source: $rtl_file"
    }
}

set subsystem_root [file join $ip_repo_dir "rv32_pipeline_axi_subsystem"]
if {[file exists $subsystem_root]} { file delete -force $subsystem_root }
create_project -in_memory rv32_subsystem_packager -part $package_part_name
add_files -norecurse [concat $common_files $pipeline_files $soc_files]
set_property top rv32_pipeline_axi_subsystem [current_fileset]
update_compile_order -fileset sources_1
ipx::package_project -root_dir $subsystem_root -vendor $vendor_name \
    -library $library_name -taxonomy /UserIP -import_files -set_current true
set core [ipx::current_core]
set_property name rv32_pipeline_axi_subsystem $core
set_property display_name "RV32IM AXI Control Subsystem" $core
set_property description "Five-stage RV32IM controller with private caches, one-outstanding AXI4-Lite master, progress watchdog/quarantine, and ARM-loadable instruction/data memory portals." $core
set_property version 1.0 $core
set_property supported_families {zynquplus Production} $core
ipx::infer_bus_interfaces $core
if {[llength [ipx::get_bus_interfaces -quiet S_AXI_ACLK -of_objects $core]] == 0} {
    error "RV32 subsystem S_AXI_ACLK clock interface was not inferred."
}
foreach busif_name {M_AXI S_AXI_IMEM S_AXI_DMEM} {
    if {[llength [ipx::get_bus_interfaces -quiet $busif_name -of_objects $core]] == 0} {
        error "RV32 subsystem bus interface $busif_name was not inferred."
    }
    ipx::associate_bus_interfaces -busif $busif_name -clock S_AXI_ACLK $core
}
ipx::update_checksums $core
ipx::check_integrity $core
ipx::save_core $core
close_project

set mailbox_root [file join $ip_repo_dir "rv32_job_mailbox"]
if {[file exists $mailbox_root]} { file delete -force $mailbox_root }
create_project -in_memory rv32_mailbox_packager -part $package_part_name
add_files -norecurse [file join $repo_root "rtl/riscv/soc/rv32_job_mailbox.sv"]
set_property top rv32_job_mailbox [current_fileset]
update_compile_order -fileset sources_1
ipx::package_project -root_dir $mailbox_root -vendor $vendor_name \
    -library $library_name -taxonomy /UserIP -import_files -set_current true
set core [ipx::current_core]
set_property name rv32_job_mailbox $core
set_property display_name "RV32/ARM Job Mailbox" $core
set_property description "AXI4-Lite job ownership, completion/failure IRQs, 64-bit job timing, first-fault diagnostics, bridge watchdog status, and RV32 reset control." $core
set_property version 1.0 $core
set_property supported_families {zynquplus Production} $core
ipx::infer_bus_interfaces $core
if {[llength [ipx::get_bus_interfaces -quiet S_AXI -of_objects $core]] == 0} {
    error "Mailbox S_AXI interface was not inferred."
}
ipx::associate_bus_interfaces -busif S_AXI -clock S_AXI_ACLK $core
ipx::update_checksums $core
ipx::check_integrity $core
ipx::save_core $core
close_project

puts "RV32 control IP packaged in $ip_repo_dir"
