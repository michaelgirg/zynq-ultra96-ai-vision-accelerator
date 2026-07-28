# Verification Plan

## Goal

Upgrade the project from directed RTL testbenches into a reusable
SystemVerilog verification environment with:

- AXI4-Lite master BFM,
- pixel scoreboard,
- SystemVerilog assertions,
- functional coverage,
- directed verification tests,
- mini UVM AXI4-Lite environment,
- Questa UCDB coverage reports.

## Production-v2 release flow

The commands below preserve the original scalar verification flow. The current
production gate is the larger `verif/uvm_axis` environment documented in
`verif/uvm_axis/README.md` and launched by
`verif/uvm_axis/run_server_regression.sh`. It contains eleven focused UVM tests,
production-register RAL and diagnostics, runtime arithmetic prediction,
malformed-packet/reset recovery, protocol and datapath assertions, and a
separate 100-seed run. Local Questa Starter compiles that environment but cannot
execute its constrained-random/coverage workload. The complete eleven-test
execution and merged coverage review passed on the licensed verification server;
the results are recorded in `verif/uvm_axis/README.md` and
`verif/coverage/vector_stream_coverage_plan.md`.

The class-free local gate, `scripts/run_local_rtl_regression.ps1`, verifies two
consecutive frames in every mode, the 1/2/4-lane sweep, three asynchronous CDC
ratios with partial-request and held-response reset aborts, assertion checks,
UVM compilation, and eight independent Python-predicted frames. It does not
launch Vivado.

## Verification Structure

```text
verif/
  axi_lite_master_bfm.sv
  preprocess_scoreboard.sv
  preprocess_sva.sv
  preprocess_coverage.sv
  preprocess_verif_pkg.sv
  filelist.f
  tests/
    test_axi_lite_directed_verif.sv
  coverage/
    coverage_plan.md
    coverage_report.md
  uvm/
    preprocess_if.sv
    preprocess_uvm_pkg.sv
    axi_lite_item.sv
    axi_lite_sequencer.sv
    axi_lite_driver.sv
    axi_lite_monitor.sv
    axi_lite_agent.sv
    preprocess_scoreboard_uvm.sv
    preprocess_coverage_uvm.sv
    preprocess_env.sv
    sequences/
    tests/
    top/
    filelist.f
```

## Licensed Simulator Setup

Run from the repository root on the licensed simulator host:

```bash
source /apps/reconfig/enable_std
```

## Compile

```bash
rm -rf work transcript vsim.wlf *.ucdb *_coverage_report.txt coverage_report.txt

vlib work
vmap work work

vlog -sv -assertdebug -cover bcesft -mfcu -cuname preprocess_verif_cu -f verif/filelist.f
```

## Run Threshold Verification

```bash
vsim -c -coverage -assertdebug -onfinish stop work.test_axi_lite_directed_verif \
  +INPUT_MEM=generated/test_vectors/sample_000_input.mem \
  +EXPECTED_MEM=generated/test_vectors/sample_000_threshold.mem \
  +MODE=0 \
  -do "run -all; coverage save threshold_verif.ucdb; quit -f"
```

## Run Sobel Verification

```bash
vsim -c -coverage -assertdebug -onfinish stop work.test_axi_lite_directed_verif \
  +INPUT_MEM=generated/test_vectors/sample_000_input.mem \
  +EXPECTED_MEM=generated/test_vectors/sample_000_sobel.mem \
  +MODE=1 \
  -do "run -all; coverage save sobel_verif.ucdb; quit -f"
```

## Run Control Coverage

```bash
vsim -c -coverage -assertdebug -onfinish stop work.test_axi_lite_control_coverage \
  -do "run -all; coverage save control_verif.ucdb; quit -f"
```

## Merge And Report

```bash
vcover merge verif_combined.ucdb threshold_verif.ucdb sobel_verif.ucdb control_verif.ucdb
vcover report verif_combined.ucdb -details > verif_coverage_report.txt
cat verif_coverage_report.txt
```

## Mini UVM Flow

The non-UVM flow above is the stable baseline. The mini UVM flow is separate
and uses `verif/uvm/filelist.f`, so it can grow without breaking the directed
BFM/SVA/coverage tests.

### Compile UVM

```bash
rm -rf work transcript vsim.wlf *.ucdb *_coverage_report.txt coverage_report.txt

source /apps/reconfig/enable_std

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

### Run UVM Threshold Test

```bash
vsim -c -coverage -assertdebug -onfinish stop work.preprocess_uvm_top \
  +UVM_TESTNAME=preprocess_threshold_test \
  +INPUT_MEM=generated/test_vectors/sample_000_input.mem \
  +EXPECTED_MEM=generated/test_vectors/sample_000_threshold.mem \
  -do "run -all; coverage save uvm_threshold.ucdb; quit -f"
```

### Run UVM Sobel Test

```bash
vsim -c -coverage -assertdebug -onfinish stop work.preprocess_uvm_top \
  +UVM_TESTNAME=preprocess_sobel_test \
  +INPUT_MEM=generated/test_vectors/sample_000_input.mem \
  +EXPECTED_MEM=generated/test_vectors/sample_000_sobel.mem \
  -do "run -all; coverage save uvm_sobel.ucdb; quit -f"
```

### Run UVM Control Coverage Tests

```bash
vsim -c -coverage -assertdebug -onfinish stop work.preprocess_uvm_top \
  +UVM_TESTNAME=preprocess_control_test \
  -do "run -all; coverage save uvm_control.ucdb; quit -f"

vsim -c -coverage -assertdebug -onfinish stop work.preprocess_uvm_top \
  +UVM_TESTNAME=preprocess_random_test \
  -do "run -all; coverage save uvm_random.ucdb; quit -f"
```

### Run UVM Hardening Tests

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

### UVM Coverage Report

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


## What This Adds

The original `tb/` folder remains useful for simple directed bring-up. The
`verif/` folder is the more advanced layer for AMD-style design verification:

- reusable BFM,
- reusable scoreboard,
- SVA safety checks,
- functional coverage bins,
- UVM sequence item/sequencer/driver/monitor/agent/env/test classes,
- UVM scoreboard and coverage subscriber,
- busy-write and reset hardening sequences,
- coverage-report workflow.

## MODE=3 Vector AXI4-Stream UVM Closure

The separate `verif/uvm_axis/` environment verifies the packed four-filter data
plane with an AXI-Lite control agent, AXI4-Stream source/sink components,
scoreboard, functional coverage, and protocol/frame assertions.

The July 10, 2026 licensed Questa regression passed:

```text
vector4_stream_test: PASS, 784/784 packed outputs
vector4_backpressure_test: PASS, 784/784 packed outputs
vector4_busy_write_test: PASS, 784/784 packed outputs
vector4_saturation_test: PASS, 784/784 packed outputs
UVM_ERROR: 0
UVM_FATAL: 0
Assertion failures: 0
Stream functional coverage: 100.00%, 26/26 bins
Control functional coverage: 100.00%, 26/26 bins
```

The tests cover random input gaps, randomized output backpressure, TLAST and
full-TKEEP behavior, stable output during stalls, border/interior pixels, all
four packed channels, active and saturated values, all four filters and every
configuration entry, atomic shadow/commit behavior, and busy-time writes.

Run the preserved regression from the repository root:

```bash
source /apps/reconfig/enable_std
bash verif/uvm_axis/run_server_regression.sh
```

Raw filtered code/toggle coverage is recorded separately and is not the release
gate for this focused MODE=3 plan. Closure requires the targeted functional
bins, clean scoreboards, zero UVM errors/fatals, and zero assertion failures.
