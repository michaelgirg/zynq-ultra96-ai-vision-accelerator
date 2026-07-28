onerror {quit -code 1}

set work_lib pipeline_core_work
do compile_pipeline.do

vlog -work $work_lib -sv ../../../rtl/riscv/soc/soc_address_map_pkg.sv
vlog -work $work_lib -sv ../../../rtl/riscv/soc/rv32_mmio_router.sv
vlog -work $work_lib -sv ../../../rtl/riscv/soc/rv32_axi_lite_master.sv
vlog -work $work_lib -sv ../../../rtl/riscv/pipeline/core_pipeline.sv
vlog -work $work_lib -sv ../../../rtl/riscv/soc/rv32_pipeline_axi_top.sv
vlog -work $work_lib -sv ../../../rtl/axis_threshold_preprocess.sv
vlog -work $work_lib -sv ../../../rtl/sobel_core.sv
vlog -work $work_lib -sv ../../../rtl/image_sobel_engine.sv
vlog -work $work_lib -sv ../../../rtl/axis_sobel_preprocess.sv
vlog -work $work_lib -sv ../../../rtl/axis_conv3x3_parallel_preprocess.sv
vlog -work $work_lib -sv ../../../rtl/axis_conv3x3_vector4_preprocess.sv
vlog -work $work_lib -sv ../../../rtl/axis_preprocess_vector_axi_lite.sv
vlog -work $work_lib -sv ../../../tb/riscv/integration/pipeline/core_pipeline_tb.sv
vlog -work $work_lib -sv ../../../tb/riscv/integration/pipeline/core_pipeline_m_tb.sv
vlog -work $work_lib -sv ../../../tb/riscv/integration/pipeline/core_pipeline_cache_tb.sv
vlog -work $work_lib -sv ../../../tb/riscv/integration/pipeline/core_pipeline_cache_fault_tb.sv
vlog -work $work_lib -sv ../../../tb/riscv/integration/pipeline/core_pipeline_mmio_tb.sv
vlog -work $work_lib -sv ../../../tb/riscv/integration/soc/rv32_pipeline_axi_top_tb.sv
vlog -work $work_lib -sv ../../../tb/riscv/integration/soc/rv32_vision_accelerator_tb.sv
vlog -work $work_lib -sv ../../../tb/riscv/integration/soc/rv32_dma_control_tb.sv

foreach test {core_pipeline_tb core_pipeline_m_tb core_pipeline_cache_tb core_pipeline_cache_fault_tb core_pipeline_mmio_tb rv32_pipeline_axi_top_tb rv32_vision_accelerator_tb rv32_dma_control_tb} {
    echo "Running $test"
    vsim -c $work_lib.$test
    onfinish stop
    run -all
    quit -sim
}

echo "Pipeline core integration tests completed"
quit -code 0
