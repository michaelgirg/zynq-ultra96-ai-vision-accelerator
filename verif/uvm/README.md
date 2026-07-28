# Mini UVM Verification Environment

This folder contains a small UVM environment for the existing AXI4-Lite
controlled image preprocessing accelerator. It does not replace the directed
tests in `tb/` or the non-UVM verification layer in `verif/`.

## Components

```text
preprocess_if.sv              AXI4-Lite signal interface
axi_lite_item.sv              UVM sequence item
axi_lite_sequencer.sv         UVM sequencer
axi_lite_driver.sv            AXI4-Lite driver
axi_lite_monitor.sv           AXI4-Lite monitor
axi_lite_agent.sv             Reusable AXI4-Lite agent
preprocess_scoreboard_uvm.sv  Golden pixel scoreboard
preprocess_coverage_uvm.sv    UVM coverage subscriber
preprocess_env.sv             Environment wiring
sequences/                    Threshold, Sobel, control, random, busy, reset sequences
tests/                        UVM test classes
top/preprocess_uvm_top.sv     DUT top-level testbench
filelist.f                    UVM compile filelist
```

## Licensed Questa Run

Run from the repository root on a host with Questa and UVM installed.

```bash
source /apps/reconfig/enable_std

rm -rf work transcript vsim.wlf *.ucdb *_coverage_report.txt coverage_report.txt

QUESTA_BIN="$(command -v vsim)"
QUESTA_ROOT="$(cd "$(dirname "$QUESTA_BIN")/.." && pwd)"
UVM_SRC="$QUESTA_ROOT/verilog_src/uvm-1.2/src"
ls "$UVM_SRC/uvm_pkg.sv"

vlib work
vmap work work

vlog -sv -assertdebug -cover bcesft -mfcu -cuname preprocess_uvm_cu \
  +define+UVM_NO_DPI \
  +incdir+"$UVM_SRC" \
  +incdir+verif/uvm \
  "$UVM_SRC/uvm_pkg.sv" \
  -f verif/uvm/filelist.f
```

Threshold test:

```bash
vsim -c -coverage -assertdebug -onfinish stop work.preprocess_uvm_top \
  +UVM_TESTNAME=preprocess_threshold_test \
  +INPUT_MEM=generated/test_vectors/sample_000_input.mem \
  +EXPECTED_MEM=generated/test_vectors/sample_000_threshold.mem \
  -do "run -all; coverage save uvm_threshold.ucdb; quit -f"
```

Sobel test:

```bash
vsim -c -coverage -assertdebug -onfinish stop work.preprocess_uvm_top \
  +UVM_TESTNAME=preprocess_sobel_test \
  +INPUT_MEM=generated/test_vectors/sample_000_input.mem \
  +EXPECTED_MEM=generated/test_vectors/sample_000_sobel.mem \
  -do "run -all; coverage save uvm_sobel.ucdb; quit -f"
```

Control coverage tests:

```bash
vsim -c -coverage -assertdebug -onfinish stop work.preprocess_uvm_top \
  +UVM_TESTNAME=preprocess_control_test \
  -do "run -all; coverage save uvm_control.ucdb; quit -f"

vsim -c -coverage -assertdebug -onfinish stop work.preprocess_uvm_top \
  +UVM_TESTNAME=preprocess_random_test \
  -do "run -all; coverage save uvm_random.ucdb; quit -f"
```

Hardening tests:

```bash
vsim -c -coverage -assertdebug -onfinish stop work.preprocess_uvm_top \
  +UVM_TESTNAME=preprocess_busy_write_test \
  +INPUT_MEM=generated/test_vectors/sample_000_input.mem \
  +EXPECTED_MEM=generated/test_vectors/sample_000_threshold.mem \
  -do "run -all; coverage save uvm_busy_write.ucdb; quit -f"

vsim -c -coverage -assertdebug -onfinish stop work.preprocess_uvm_top \
  +UVM_TESTNAME=preprocess_reset_test \
  +INPUT_MEM=generated/test_vectors/sample_000_input.mem \
  +EXPECTED_MEM=generated/test_vectors/sample_000_threshold.mem \
  -do "run -all; coverage save uvm_reset.ucdb; quit -f"
```

Coverage report:

```bash
vcover merge uvm_combined.ucdb \
  uvm_threshold.ucdb \
  uvm_sobel.ucdb \
  uvm_control.ucdb \
  uvm_random.ucdb \
  uvm_busy_write.ucdb \
  uvm_reset.ucdb
vcover report uvm_combined.ucdb -details > uvm_coverage_report.txt
cat uvm_coverage_report.txt
```
