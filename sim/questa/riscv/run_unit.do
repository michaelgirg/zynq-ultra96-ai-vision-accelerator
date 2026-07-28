onerror {quit -code 1}

set work_lib unit_work
do compile.do

foreach test {pc_tb imem_tb imm_gen_tb branch_unit_tb decoder_tb alu_tb regfile_tb dmem_tb muldiv_single_cycle_tb} {
    echo "Running $test"
    vsim -c -voptargs=+acc $work_lib.$test
    run -all
    quit -sim
}

echo "All completed-module unit tests finished"
quit -code 0
