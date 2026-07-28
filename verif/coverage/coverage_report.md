# Coverage Report Notes

## Current Baseline

The server baseline before the verification upgrade used two directed AXI-Lite
tests:

```text
Threshold sample_000: PASS
Sobel sample_000: PASS
Merged RTL coverage: 82.72%
```

## First Verification Upgrade Run

After adding the BFM/SVA/coverage environment, the server run showed:

```text
Compile: PASS, 0 errors, 0 warnings
Threshold verification: PASS
Sobel verification: PASS
Assertion failures: 0
Total covergroup coverage: 94.31%
AXI functional coverage: 100.00%
Filtered total coverage: 78.90%
```

## Control Coverage Run

After adding `test_axi_lite_control_coverage`, the server run showed:

```text
Compile: PASS, 0 errors, 0 warnings
Threshold verification: PASS
Sobel verification: PASS
Control coverage test: PASS
Assertion failures: 0
```

The first control test also checked the threshold boundary and invalid-mode
coverage path, but it instantiated its own AXI coverage collector and lowered
the aggregate covergroup percentage because that focused test was not intended
to repeat every AXI access scenario. The test was then adjusted so:

- AXI functional coverage is collected in the directed threshold/Sobel tests,
- register/control functional coverage is collected in the control test,
- control coverage now targets start-only, start+clear, invalid modes,
  threshold boundary values, and busy-time writes.

The uncovered bins were expected for the baseline because it only covered two
directed tests. Missing coverage was mostly from:

- AXI response backpressure,
- invalid mode writes,
- busy-time configuration writes,
- reset during active traffic,
- threshold boundary values,
- intentionally unused upper register/data bits.

## Mini UVM Four-Test Closure

The current mini UVM run uses four tests:

```text
preprocess_threshold_test
preprocess_sobel_test
preprocess_control_test
preprocess_random_test
```

The July 5, 2026 UF server run showed:

```text
Compile: PASS, 0 errors, 0 warnings
UVM threshold test: PASS, scoreboard matched 784 output pixels
UVM Sobel test: PASS, scoreboard matched 784 output pixels
UVM control test: PASS
UVM random control test: PASS
UVM errors: 0
UVM fatals: 0
Assertion failures: 0
Total UVM covergroup coverage: 100.00%
UVM covergroup bins covered: 28/28
Filtered total coverage by instance: 71.50%
```

The UVM functional coverage closed all targeted bins:

```text
AXI transaction kind: read/write
AXI write addresses: control, threshold, input address/data/mask, output address, mode
AXI read addresses: status, image pixels, pixels per cycle, processing cycles, output data, mode
Mode writes: threshold, Sobel, invalid mode 2, invalid mode 3
Threshold writes: 0, 1, 127, 128, 254, 255
Control writes: start-only, clear-only, start+clear
```

The lower filtered total code coverage is expected because the report includes
wide unused register bits, defensive paths, and UVM classes/sequences that are
not all targeted by the image/control regression. The main closure metric for
this milestone is the targeted UVM functional coverage plus zero scoreboard and
assertion failures.

## UVM Hardening Pass

Two additional UVM tests were added after the stable mini UVM milestone:

```text
preprocess_busy_write_test
preprocess_reset_test
```

`preprocess_busy_write_test` starts an active threshold operation, attempts
writes to threshold, mode, input data, and control while the accelerator is
busy, then checks that threshold/mode state stayed stable and the final
threshold output still matches the 784-pixel golden vector.

`preprocess_reset_test` applies reset during idle, active threshold processing,
and active Sobel processing. It checks that status, threshold, mode, and cycle
count return to reset defaults, then runs a clean threshold operation and reads
all 784 output pixels for scoreboard comparison.

The July 5, 2026 UF server hardening runs showed:

```text
UVM busy-write test: PASS, scoreboard matched 784 output pixels
UVM busy-write errors: 0
UVM busy-write warnings: 1 Questa code-coverage optimization warning
UVM busy-write UVM_ERROR: 0
UVM busy-write UVM_FATAL: 0
UVM reset test: PASS, scoreboard matched 784 output pixels
UVM reset errors: 0
UVM reset warnings: 0
UVM reset UVM_ERROR: 0
UVM reset UVM_FATAL: 0
```

The final six-test merged coverage report showed:

```text
Compile: PASS, 0 errors
UVM threshold test: PASS, scoreboard matched 784 output pixels
UVM Sobel test: PASS, scoreboard matched 784 output pixels
UVM control test: PASS
UVM random test: PASS
UVM busy-write test: PASS, scoreboard matched 784 output pixels
UVM reset test: PASS, scoreboard matched 784 output pixels
UVM errors: 0
UVM fatals: 0
Assertion failures: 0
Scoreboards: threshold, Sobel, busy-write, and reset each match 784 pixels
Targeted UVM functional coverage: 100.00%
UVM covergroup bins covered: 28/28
Filtered total coverage by instance: 75.89%
```

The filtered code coverage remains a secondary metric. The useful closure
criteria for this milestone are targeted UVM functional coverage, zero
scoreboard mismatches, zero UVM errors/fatals, and zero assertion failures.

## AXI4-Stream Vector Convolution Closure

The July 10, 2026 licensed Questa regression validated the four-filter `MODE=3`
learned INT8 convolution path with a separate AXI4-Stream UVM environment:

```text
Compile: PASS, 0 errors, 0 warnings
Directed vector test: PASS, 784/784 packed outputs
Backpressure test: PASS, 784/784 packed outputs
Busy-write test: PASS, 784/784 packed outputs
Saturation/clamp test: PASS, 784/784 packed outputs
UVM errors/fatals: 0/0
Assertion failures: 0
Stream functional coverage: 100.00%, 26/26 bins
Control functional coverage: 100.00%, 26/26 bins
Total targeted covergroup coverage: 100.00%
Filtered total coverage by instance: 47.72%
```

The saturation test deliberately programs zero kernels with bias `255`, shift
`0`, and ReLU enabled. It proves that interior pixels clamp to `255` in all
four packed channels while border pixels remain zero. The lower filtered code
coverage includes interface toggles and baseline RTL outside the focused
MODE=3 plan, so the release criterion is targeted functional coverage plus
scoreboard and assertion cleanliness.
