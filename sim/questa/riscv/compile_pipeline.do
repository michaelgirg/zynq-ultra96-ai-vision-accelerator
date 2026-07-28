transcript on

if {![info exists work_lib]} {
    set work_lib pipeline_work
}

# Start from a fresh Questa library. Generated libraries are not tracked,
# so this must also work from a clean checkout.
if {[file isdirectory $work_lib]} {
    if {[file exists "$work_lib/_info"]} {
        catch {vdel -lib $work_lib -all}
    } else {
        file delete -force $work_lib
    }
}

vlib $work_lib

# Shared RTL. The package must be compiled first.
vlog -work $work_lib -sv ../../../rtl/riscv/common/rv32i_pkg.sv
foreach source {
    pc.sv
    imem.sv
    imm_gen.sv
    branch_unit.sv
    decoder.sv
    alu.sv
    regfile.sv
    dmem.sv
} {
    vlog -work $work_lib -sv ../../../rtl/riscv/common/$source
}

# Completed pipeline modules.
vlog -work $work_lib -sv ../../../rtl/riscv/pipeline/if_id_reg.sv
vlog -work $work_lib -sv ../../../rtl/riscv/pipeline/id_ex_reg.sv
vlog -work $work_lib -sv ../../../rtl/riscv/pipeline/ex_mem_reg.sv
vlog -work $work_lib -sv ../../../rtl/riscv/pipeline/mem_wb_reg.sv
vlog -work $work_lib -sv ../../../rtl/riscv/pipeline/forwarding_unit.sv
vlog -work $work_lib -sv ../../../rtl/riscv/pipeline/load_use_hazard_unit.sv
vlog -work $work_lib -sv ../../../rtl/riscv/pipeline/pipeline_control.sv
vlog -work $work_lib -sv ../../../rtl/riscv/pipeline/mul_unit.sv
vlog -work $work_lib -sv ../../../rtl/riscv/pipeline/div_unit.sv
vlog -work $work_lib -sv ../../../rtl/riscv/pipeline/muldiv_unit.sv
vlog -work $work_lib -sv ../../../rtl/riscv/pipeline/slow_line_memory.sv
vlog -work $work_lib -sv ../../../rtl/riscv/pipeline/plru.sv
vlog -work $work_lib -sv ../../../rtl/riscv/pipeline/dcache.sv
vlog -work $work_lib -sv ../../../rtl/riscv/pipeline/icache.sv

# Pipeline unit tests for completed modules.
vlog -work $work_lib -sv ../../../tb/riscv/unit/pipeline/if_id_reg_tb.sv
vlog -work $work_lib -sv ../../../tb/riscv/unit/pipeline/id_ex_reg_tb.sv
vlog -work $work_lib -sv ../../../tb/riscv/unit/pipeline/ex_mem_reg_tb.sv
vlog -work $work_lib -sv ../../../tb/riscv/unit/pipeline/mem_wb_reg_tb.sv
vlog -work $work_lib -sv ../../../tb/riscv/unit/pipeline/forwarding_unit_tb.sv
vlog -work $work_lib -sv ../../../tb/riscv/unit/pipeline/load_use_hazard_unit_tb.sv
vlog -work $work_lib -sv ../../../tb/riscv/unit/pipeline/pipeline_control_tb.sv
vlog -work $work_lib -sv ../../../tb/riscv/unit/pipeline/mul_unit_tb.sv
vlog -work $work_lib -sv ../../../tb/riscv/unit/pipeline/div_unit_tb.sv
vlog -work $work_lib -sv ../../../tb/riscv/unit/pipeline/muldiv_unit_tb.sv
vlog -work $work_lib -sv ../../../tb/riscv/unit/pipeline/slow_line_memory_tb.sv
vlog -work $work_lib -sv ../../../tb/riscv/unit/pipeline/plru_tb.sv
vlog -work $work_lib -sv ../../../tb/riscv/unit/pipeline/dcache_tb.sv
vlog -work $work_lib -sv ../../../tb/riscv/unit/pipeline/icache_tb.sv

# Pipeline top-level integration is compiled by run_pipeline_core.do.
# vlog -work $work_lib -sv ../../../rtl/riscv/pipeline/core_pipeline.sv
# vlog -work $work_lib -sv ../../../tb/riscv/integration/pipeline/core_pipeline_tb.sv
