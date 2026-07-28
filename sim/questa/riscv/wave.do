add wave -divider Core
add wave sim:/core_single_cycle_tb/dut/clk_i
add wave sim:/core_single_cycle_tb/dut/rst_i
add wave -radix hexadecimal sim:/core_single_cycle_tb/dut/current_pc
add wave -radix hexadecimal sim:/core_single_cycle_tb/dut/instruction
add wave -radix hexadecimal sim:/core_single_cycle_tb/dut/alu_result
add wave -radix hexadecimal sim:/core_single_cycle_tb/dut/writeback_data
add wave sim:/core_single_cycle_tb/dut/halted_o
add wave sim:/core_single_cycle_tb/dut/illegal_instruction_o
add wave sim:/core_single_cycle_tb/dut/instruction_fault_o
add wave sim:/core_single_cycle_tb/dut/data_fault_o
configure wave -signalnamewidth 1
