onerror {quit -code 1}

set work_lib pipeline_core_work
do compile_pipeline.do

vlog -work $work_lib -sv ../../../rtl/riscv/pipeline/core_pipeline.sv
vlog -work $work_lib -sv ../../../tb/riscv/integration/pipeline/core_pipeline_tb.sv
vlog -work $work_lib -sv ../../../tb/riscv/integration/pipeline/core_pipeline_m_tb.sv
vlog -work $work_lib -sv ../../../tb/riscv/integration/pipeline/core_pipeline_cache_tb.sv
vlog -work $work_lib -sv ../../../tb/riscv/integration/pipeline/core_pipeline_cache_fault_tb.sv

foreach test {core_pipeline_tb core_pipeline_m_tb core_pipeline_cache_tb core_pipeline_cache_fault_tb} {
    echo "Running $test"
    vsim -c $work_lib.$test
    onfinish stop
    run -all
    quit -sim
}

echo "Pipeline core integration tests completed"
quit -code 0
