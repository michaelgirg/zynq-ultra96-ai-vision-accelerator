transcript on

if {![info exists work_lib]} {
    set work_lib work
}

# Start from a fresh Questa library. Generated libraries are not tracked,
# so this must also work from a clean checkout.
if {[file isdirectory $work_lib]} {
    catch {vdel -lib $work_lib -all}
}

vlib $work_lib

# Compile the shared package before every module that imports it.
vlog -work $work_lib -sv ../../../rtl/riscv/common/rv32i_pkg.sv
vlog -work $work_lib -sv ../../../rtl/riscv/common/pc.sv
vlog -work $work_lib -sv ../../../rtl/riscv/common/imem.sv
vlog -work $work_lib -sv ../../../rtl/riscv/common/imm_gen.sv
vlog -work $work_lib -sv ../../../rtl/riscv/common/branch_unit.sv
vlog -work $work_lib -sv ../../../rtl/riscv/common/decoder.sv
vlog -work $work_lib -sv ../../../rtl/riscv/common/alu.sv
vlog -work $work_lib -sv ../../../rtl/riscv/common/regfile.sv
vlog -work $work_lib -sv ../../../rtl/riscv/common/dmem.sv

# Completed single-cycle reference core.
vlog -work $work_lib -sv ../../../rtl/riscv/single_cycle/muldiv_single_cycle.sv
vlog -work $work_lib -sv ../../../rtl/riscv/single_cycle/core_single_cycle.sv

vlog -work $work_lib -sv ../../../tb/riscv/unit/common/pc_tb.sv
vlog -work $work_lib -sv ../../../tb/riscv/unit/common/imem_tb.sv
vlog -work $work_lib -sv ../../../tb/riscv/unit/common/imm_gen_tb.sv
vlog -work $work_lib -sv ../../../tb/riscv/unit/common/branch_unit_tb.sv
vlog -work $work_lib -sv ../../../tb/riscv/unit/common/decoder_tb.sv
vlog -work $work_lib -sv ../../../tb/riscv/unit/common/alu_tb.sv
vlog -work $work_lib -sv ../../../tb/riscv/unit/common/regfile_tb.sv
vlog -work $work_lib -sv ../../../tb/riscv/unit/common/dmem_tb.sv
vlog -work $work_lib -sv ../../../tb/riscv/unit/single_cycle/muldiv_single_cycle_tb.sv
vlog -work $work_lib -sv ../../../tb/riscv/integration/single_cycle/core_single_cycle_tb.sv
vlog -work $work_lib -sv ../../../tb/riscv/integration/single_cycle/core_single_cycle_m_tb.sv
