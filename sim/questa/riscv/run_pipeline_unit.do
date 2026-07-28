onerror {quit -code 1}

set work_lib pipeline_unit_work
do compile_pipeline.do

foreach test {if_id_reg_tb id_ex_reg_tb ex_mem_reg_tb mem_wb_reg_tb forwarding_unit_tb load_use_hazard_unit_tb pipeline_control_tb mul_unit_tb div_unit_tb muldiv_unit_tb slow_line_memory_tb plru_tb dcache_tb icache_tb} {
    echo "Running $test"
    # Normal optimization is enough for self-checking tests. Questa 2021.2
    # can crash internally when +acc is applied to the large I-cache TB.
    # Add -voptargs=+acc manually only when an interactive waveform needs it.
    vsim -c $work_lib.$test
    onfinish stop
    run -all
    quit -sim
}

echo "All completed pipeline unit tests finished"
quit -code 0
