onerror {quit -code 1}

set work_lib core_work
do compile.do

foreach test {core_single_cycle_tb core_single_cycle_m_tb} {
    echo "Running $test"
    vsim -c -voptargs=+acc $work_lib.$test
    onfinish stop
    run -all
    quit -sim
}

echo "All single-cycle integration tests completed"
quit -code 0
