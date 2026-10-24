# Create a separate Ultra96-V1 DMA project for the production-v2 dual-clock IP.
# PL0 is the 100 MHz control domain; PL1 is the 150 MHz stream/data domain.

set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir "../.."]]
if {![info exists project_name]} {
    set project_name "u96_production_v2"
}
if {![info exists project_dir]} {
    set project_dir [file normalize [file join $repo_root "vivado/u96_production_v2_vivado"]]
}
if {![info exists bd_name]} {
    set bd_name "u96v2bd"
}
set ip_repo_dir [file normalize [file join $repo_root "vivado/ip_repo_ultra96_production_v2"]]
set rv32_ip_repo_dir [file normalize [file join $repo_root "vivado/ip_repo_rv32_soc"]]
if {![info exists enable_rv32_soc]} {
    set enable_rv32_soc 0
}

if {![info exists part_name]} {
    set part_name "xczu3eg-sbva484-1-e"
}
set ip_vendor_name "user.org"
set preproc_vlnv "${ip_vendor_name}:u96_ai_vision:axis_preprocess_vector_cdc:2.0"
set rv32_vlnv "${ip_vendor_name}:u96_ai_vision:rv32_pipeline_axi_subsystem:1.0"
set mailbox_vlnv "${ip_vendor_name}:u96_ai_vision:rv32_job_mailbox:1.0"
if {![info exists ultra96_board_variant]} {
    set ultra96_board_variant "v1"
}
if {![info exists ultra96_board_label]} {
    set ultra96_board_label "Ultra96-V1"
}
if {![info exists ultra96_board_check_script]} {
    set ultra96_board_check_script "check_ultra96_v1_board.tcl"
}
if {![info exists ultra96_board_preferred]} {
    set ultra96_board_preferred [list \
        "em.avnet.com:ultra96v1:part0:1.2" \
        "avnet.com:ultra96v1:part0:1.2" \
        "em.avnet.com:ultra96:part0:1.2" \
        "avnet.com:ultra96:part0:1.2" \
    ]
}

proc find_ultra96_board_part {} {
    global ultra96_board_variant ultra96_board_preferred
    set available [get_board_parts -quiet *ultra96*]

    foreach candidate $ultra96_board_preferred {
        if {[lsearch -exact $available $candidate] >= 0} {
            return $candidate
        }
    }

    foreach candidate $available {
        set lower_name [string tolower $candidate]
        if {$ultra96_board_variant eq "v2" &&
            [string match "*ultra96v2*" $lower_name]} {
            return $candidate
        }
        if {$ultra96_board_variant ne "v2" &&
            [string match "*ultra96v1*" $lower_name]} {
            return $candidate
        }
        if {$ultra96_board_variant ne "v2" &&
            [string match "*ultra96:*" $lower_name] &&
            ![string match "*ultra96v2*" $lower_name]} {
            return $candidate
        }
    }
    return ""
}

proc packaged_ip_uses_vendor {component_file vendor_name} {
    if {![file exists $component_file]} {
        return 0
    }
    set component_handle [open $component_file r]
    set component_xml [read $component_handle]
    close $component_handle
    return [expr {[string first ">$vendor_name<" $component_xml] >= 0}]
}

puts "Repo root: $repo_root"
puts "$ultra96_board_label production-v2 project: $project_dir"

if {[file exists [file join $project_dir "$project_name.xpr"]]} {
    if {[info exists recreate_existing_project] && $recreate_existing_project} {
        set expected_project_parent [file normalize [file join $repo_root "vivado"]]
        if {[file dirname $project_dir] ne $expected_project_parent ||
            ![string match "*_vivado" [file tail $project_dir]]} {
            error "Refusing to remove unexpected project directory: $project_dir"
        }
        puts "Replacing generated project: $project_dir"
        file delete -force $project_dir
    } else {
        error "Project already exists: $project_dir. This script will not overwrite it."
    }
}

set preproc_component [file join $ip_repo_dir "axis_preprocess_vector_cdc/component.xml"]
if {![packaged_ip_uses_vendor $preproc_component $ip_vendor_name]} {
    puts "Production-v2 packaged IP is missing or stale. Packaging it now."
    source [file join $script_dir "package_axis_preprocess_vector_cdc_ip_ultra96.tcl"]
}
set rv32_component [file join $rv32_ip_repo_dir "rv32_pipeline_axi_subsystem/component.xml"]
set mailbox_component [file join $rv32_ip_repo_dir "rv32_job_mailbox/component.xml"]
if {$enable_rv32_soc &&
    (![packaged_ip_uses_vendor $rv32_component $ip_vendor_name] ||
     ![packaged_ip_uses_vendor $mailbox_component $ip_vendor_name])} {
    puts "RV32 control IP is missing or stale. Packaging it now."
    source [file join $script_dir "package_rv32_control_soc_ip.tcl"]
}

# Optional machine-specific board repository. System-installed board files need
# no override; on a custom installation export ULTRA96_BOARD_REPO first.
if {[info exists ::env(ULTRA96_BOARD_REPO)] &&
    [file exists $::env(ULTRA96_BOARD_REPO)]} {
    set_param board.repoPaths [list [file normalize $::env(ULTRA96_BOARD_REPO)]]
}

set board_part [find_ultra96_board_part]
if {$board_part eq ""} {
    error "No $ultra96_board_label board definition is installed. Run $ultra96_board_check_script and set ULTRA96_BOARD_REPO if needed."
}

puts "Using board part: $board_part"

create_project $project_name $project_dir -part $part_name
set_property board_part $board_part [current_project]
set project_ip_repos [list $ip_repo_dir]
if {$enable_rv32_soc} { lappend project_ip_repos $rv32_ip_repo_dir }
set_property ip_repo_paths $project_ip_repos [current_project]
update_ip_catalog

if {[llength [get_ipdefs -all $preproc_vlnv]] == 0} {
    error "Could not find packaged IP VLNV: $preproc_vlnv"
}
if {$enable_rv32_soc &&
    ([llength [get_ipdefs -all $rv32_vlnv]] == 0 ||
     [llength [get_ipdefs -all $mailbox_vlnv]] == 0)} {
    error "Could not find the packaged RV32 subsystem and mailbox IP."
}

create_bd_design $bd_name

create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:* ps
apply_bd_automation \
    -rule xilinx.com:bd_rule:zynq_ultra_ps_e \
    -config {apply_board_preset "1"} \
    [get_bd_cells ps]

set_property -dict [list \
    CONFIG.PSU__USE__M_AXI_GP0 {1} \
    CONFIG.PSU__USE__M_AXI_GP1 {0} \
    CONFIG.PSU__USE__S_AXI_GP2 {1} \
    CONFIG.PSU__FPGA_PL0_ENABLE {1} \
    CONFIG.PSU__FPGA_PL1_ENABLE {1} \
    CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {100} \
    CONFIG.PSU__CRL_APB__PL1_REF_CTRL__FREQMHZ {150} \
    CONFIG.PSU__CRL_APB__PL1_REF_CTRL__DIVISOR0 {5} \
    CONFIG.PSU__CRL_APB__PL1_REF_CTRL__DIVISOR1 {2} \
    CONFIG.PSU__USE__FABRIC__RST {1} \
    CONFIG.PSU__NUM_FABRIC_RESETS {1} \
    CONFIG.PSU__USE__IRQ0 {1} \
] [get_bd_cells ps]

create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:* rst_ctrl
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:* rst_axis

create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:* locked
set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {1}] [get_bd_cells locked]

create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:* dma
set_property -dict [list \
    CONFIG.c_include_sg {0} \
    CONFIG.c_include_mm2s {1} \
    CONFIG.c_include_s2mm {1} \
    CONFIG.c_m_axi_mm2s_data_width {32} \
    CONFIG.c_m_axi_s2mm_data_width {32} \
    CONFIG.c_s_axis_s2mm_tdata_width {32} \
] [get_bd_cells dma]

create_bd_cell -type ip -vlnv $preproc_vlnv pre

if {$enable_rv32_soc} {
    create_bd_cell -type ip -vlnv $rv32_vlnv rv32
    create_bd_cell -type ip -vlnv $mailbox_vlnv mailbox
    create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:* rv32_reset_inv
    set_property -dict [list CONFIG.C_OPERATION {not} CONFIG.C_SIZE {1}] \
        [get_bd_cells rv32_reset_inv]
}

create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:* sc_ctrl
if {$enable_rv32_soc} {
    set_property -dict [list CONFIG.NUM_SI {2} CONFIG.NUM_MI {5}] [get_bd_cells sc_ctrl]
} else {
    set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {2}] [get_bd_cells sc_ctrl]
}

create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:* sc_hp
set_property -dict [list CONFIG.NUM_SI {2} CONFIG.NUM_MI {1}] [get_bd_cells sc_hp]

create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:* irq_concat
set_property CONFIG.NUM_PORTS {8} [get_bd_cells irq_concat]

create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:* irq_zero
set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {0}] [get_bd_cells irq_zero]

# Control clock/reset domain: PS HPM, AXI-Lite interconnect, DMA control, and
# the software-facing half of the production CDC bridge.
connect_bd_net [get_bd_pins ps/pl_clk0] [get_bd_pins ps/maxihpm0_fpd_aclk]
connect_bd_net [get_bd_pins ps/pl_clk0] [get_bd_pins rst_ctrl/slowest_sync_clk]
connect_bd_net [get_bd_pins ps/pl_clk0] [get_bd_pins sc_ctrl/aclk]
connect_bd_net [get_bd_pins ps/pl_clk0] [get_bd_pins dma/s_axi_lite_aclk]
connect_bd_net [get_bd_pins ps/pl_clk0] [get_bd_pins pre/S_AXI_ACLK]
if {$enable_rv32_soc} {
    connect_bd_net [get_bd_pins ps/pl_clk0] [get_bd_pins rv32/S_AXI_ACLK]
    connect_bd_net [get_bd_pins ps/pl_clk0] [get_bd_pins mailbox/S_AXI_ACLK]
}

connect_bd_net [get_bd_pins ps/pl_resetn0] [get_bd_pins rst_ctrl/ext_reset_in]
connect_bd_net [get_bd_pins locked/dout] [get_bd_pins rst_ctrl/dcm_locked]
connect_bd_net [get_bd_pins rst_ctrl/peripheral_aresetn] [get_bd_pins sc_ctrl/aresetn]
connect_bd_net [get_bd_pins rst_ctrl/peripheral_aresetn] [get_bd_pins dma/axi_resetn]
connect_bd_net [get_bd_pins rst_ctrl/peripheral_aresetn] [get_bd_pins pre/S_AXI_ARESETN]
if {$enable_rv32_soc} {
    connect_bd_net [get_bd_pins rst_ctrl/peripheral_reset] [get_bd_pins rv32/system_rst_i]
    connect_bd_net [get_bd_pins rst_ctrl/peripheral_aresetn] [get_bd_pins mailbox/S_AXI_ARESETN]
    connect_bd_net [get_bd_pins mailbox/rv32_resetn] [get_bd_pins rv32_reset_inv/Op1]
    foreach signal {timeout quarantined fault_addr fault_info fault_wait} {
        connect_bd_net [get_bd_pins rv32/axi_${signal}_o] [get_bd_pins mailbox/axi_${signal}]
    }
    connect_bd_net [get_bd_pins rv32_reset_inv/Res] [get_bd_pins rv32/core_rst_i]
}

# Stream/data clock/reset domain: DMA memory and stream paths, HP port, and the
# vector datapath half of the production CDC bridge.
connect_bd_net [get_bd_pins ps/pl_clk1] [get_bd_pins ps/saxihp0_fpd_aclk]
connect_bd_net [get_bd_pins ps/pl_clk1] [get_bd_pins rst_axis/slowest_sync_clk]
connect_bd_net [get_bd_pins ps/pl_clk1] [get_bd_pins sc_hp/aclk]
connect_bd_net [get_bd_pins ps/pl_clk1] [get_bd_pins dma/m_axi_mm2s_aclk]
connect_bd_net [get_bd_pins ps/pl_clk1] [get_bd_pins dma/m_axi_s2mm_aclk]
connect_bd_net [get_bd_pins ps/pl_clk1] [get_bd_pins pre/AXIS_ACLK]

connect_bd_net [get_bd_pins ps/pl_resetn0] [get_bd_pins rst_axis/ext_reset_in]
connect_bd_net [get_bd_pins locked/dout] [get_bd_pins rst_axis/dcm_locked]
connect_bd_net [get_bd_pins rst_axis/peripheral_aresetn] [get_bd_pins sc_hp/aresetn]
connect_bd_net [get_bd_pins rst_axis/peripheral_aresetn] [get_bd_pins pre/AXIS_ARESETN]

connect_bd_intf_net [get_bd_intf_pins ps/M_AXI_HPM0_FPD] [get_bd_intf_pins sc_ctrl/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins sc_ctrl/M00_AXI] [get_bd_intf_pins dma/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins sc_ctrl/M01_AXI] [get_bd_intf_pins pre/S_AXI]
if {$enable_rv32_soc} {
    connect_bd_intf_net [get_bd_intf_pins rv32/M_AXI] [get_bd_intf_pins sc_ctrl/S01_AXI]
    connect_bd_intf_net [get_bd_intf_pins sc_ctrl/M02_AXI] [get_bd_intf_pins mailbox/S_AXI]
    connect_bd_intf_net [get_bd_intf_pins sc_ctrl/M03_AXI] [get_bd_intf_pins rv32/S_AXI_IMEM]
    connect_bd_intf_net [get_bd_intf_pins sc_ctrl/M04_AXI] [get_bd_intf_pins rv32/S_AXI_DMEM]
}

connect_bd_intf_net [get_bd_intf_pins dma/M_AXI_MM2S] [get_bd_intf_pins sc_hp/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins dma/M_AXI_S2MM] [get_bd_intf_pins sc_hp/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins sc_hp/M00_AXI] [get_bd_intf_pins ps/S_AXI_HP0_FPD]

connect_bd_intf_net [get_bd_intf_pins dma/M_AXIS_MM2S] [get_bd_intf_pins pre/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins pre/M_AXIS] [get_bd_intf_pins dma/S_AXIS_S2MM]

connect_bd_net [get_bd_pins dma/mm2s_introut] [get_bd_pins irq_concat/In0]
connect_bd_net [get_bd_pins dma/s2mm_introut] [get_bd_pins irq_concat/In1]
connect_bd_net [get_bd_pins pre/irq] [get_bd_pins irq_concat/In2]
if {$enable_rv32_soc} {
    connect_bd_net [get_bd_pins mailbox/irq] [get_bd_pins irq_concat/In3]
} else {
    connect_bd_net [get_bd_pins irq_zero/dout] [get_bd_pins irq_concat/In3]
}
foreach irq_index {4 5 6 7} {
    connect_bd_net [get_bd_pins irq_zero/dout] [get_bd_pins irq_concat/In${irq_index}]
}
connect_bd_net [get_bd_pins irq_concat/dout] [get_bd_pins ps/pl_ps_irq0]

if {$enable_rv32_soc} {
    # Create the control mappings explicitly so the ARM and RV32 masters see
    # the exact firmware map. The memory portals are deliberately ARM-only.
    set canonical_regions [dict create \
        "dma/S_AXI_LITE"  [list 0xA0010000 0x00010000 arm-rv32] \
        "pre/S_AXI"       [list 0xA0000000 0x00001000 arm-rv32] \
        "mailbox/S_AXI"   [list 0xA0020000 0x00001000 arm-rv32] \
        "rv32/S_AXI_IMEM" [list 0xA0030000 0x00010000 arm-only] \
        "rv32/S_AXI_DMEM" [list 0xA0040000 0x00010000 arm-only]]
    set control_masters [list \
        [list arm  [get_bd_addr_spaces ps/Data]] \
        [list rv32 [get_bd_addr_spaces rv32/M_AXI]]]

    foreach interface_name [dict keys $canonical_regions] {
        set slave_segments [get_bd_addr_segs -quiet -of_objects \
            [get_bd_intf_pins $interface_name]]
        if {[llength $slave_segments] != 1} {
            error "Expected one slave segment for $interface_name, found [llength $slave_segments]"
        }
        set slave_segment [lindex $slave_segments 0]
        lassign [dict get $canonical_regions $interface_name] \
            region_offset region_range region_access
        set region_tag [string map {/ _} $interface_name]

        foreach master_entry $control_masters {
            lassign $master_entry master_name address_space
            if {$master_name eq "rv32" && $region_access eq "arm-only"} {
                exclude_bd_addr_seg -quiet -target_address_space \
                    $address_space $slave_segment
                puts "Address $master_name -> $interface_name: excluded (ARM-only)"
            } else {
                create_bd_addr_seg -range $region_range -offset $region_offset \
                    $address_space $slave_segment \
                    SEG_${master_name}_${region_tag}
                puts "Address $master_name -> $interface_name: $region_offset / $region_range"
            }
        }
    }
}

# Auto-assign only the remaining data-plane mappings (notably DMA to PS DDR).
assign_bd_address

foreach clock_pin {ps/pl_clk0 ps/pl_clk1 dma/s_axi_lite_aclk dma/m_axi_mm2s_aclk dma/m_axi_s2mm_aclk} {
    set clock_object [get_bd_pins $clock_pin]
    puts "Clock $clock_pin FREQ_HZ=[get_property CONFIG.FREQ_HZ $clock_object] CLK_DOMAIN=[get_property CONFIG.CLK_DOMAIN $clock_object]"
}
puts "AXI DMA pre-validation asynchronous-clock mode: [get_property CONFIG.c_prmry_is_aclk_async [get_bd_cells dma]]"

validate_bd_design

# Vivado 2025.2 derives this read-only DMA property from the connected clock
# domains. Query it only after the 100 MHz AXI-Lite and 150 MHz data clocks are
# connected and the block design has propagated its parameters.
set dma_async_mode [string tolower [get_property CONFIG.c_prmry_is_aclk_async [get_bd_cells dma]]]
puts "AXI DMA derived asynchronous-clock mode: $dma_async_mode"
if {$dma_async_mode ni {1 true}} {
    error "AXI DMA did not derive asynchronous-clock mode from the connected control/data clocks."
}
save_bd_design

set wrapper_path [make_wrapper -files [get_files [file join $project_dir "$project_name.srcs/sources_1/bd/$bd_name/$bd_name.bd"]] -top]
add_files -norecurse $wrapper_path
set_property top ${bd_name}_wrapper [current_fileset]
update_compile_order -fileset sources_1

puts ""
puts "$ultra96_board_label production-v2 block design created."
puts "Project: [file join $project_dir "$project_name.xpr"]"
puts "Board part: $board_part"
puts "Control clock: 100 MHz PL0"
puts "Stream clock: 150 MHz PL1"
puts "Processor target: psu_cortexa53_0"
if {$enable_rv32_soc} {
    puts "RV32 controller: enabled at 100 MHz with ARM-loadable I/D memory portals"
}
puts ""

close_project
