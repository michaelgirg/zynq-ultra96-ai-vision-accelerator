onerror {quit -code 1}

set work_lib riscv_soc_unit_work

if {[file isdirectory $work_lib]} {
    if {[file exists "$work_lib/_info"]} {
        catch {vdel -lib $work_lib -all}
    } else {
        file delete -force $work_lib
    }
}
vlib $work_lib

vlog -work $work_lib -sv ../../../rtl/riscv/soc/soc_address_map_pkg.sv
vlog -work $work_lib -sv ../../../rtl/riscv/soc/rv32_mmio_router.sv
vlog -work $work_lib -sv ../../../rtl/riscv/soc/rv32_axi_lite_master.sv
vlog -work $work_lib -sv ../../../rtl/riscv/soc/rv32_job_mailbox.sv
vlog -work $work_lib -sv ../../../tb/riscv/unit/soc/rv32_mmio_router_tb.sv
vlog -work $work_lib -sv ../../../tb/riscv/unit/soc/rv32_axi_lite_master_tb.sv
vlog -work $work_lib -sv ../../../tb/riscv/unit/soc/rv32_axi_watchdog_tb.sv
vlog -work $work_lib -sv ../../../tb/riscv/unit/soc/rv32_job_mailbox_tb.sv

foreach testbench {
    rv32_mmio_router_tb
    rv32_axi_lite_master_tb
    rv32_axi_watchdog_tb
    rv32_job_mailbox_tb
} {
    vsim -c $work_lib.$testbench
    onfinish stop
    run -all
    quit -sim
}

echo "RISC-V SoC unit tests completed"
quit -code 0
