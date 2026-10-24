# Ultra96-V2 application and benchmark

The portable application joins firmware boot/readback, IP discovery, runtime
model programming, DMA buffer ownership, job submission, prediction and CSV
diagnostics. Both baseline and candidate exports are supported without changing
the saved model files or synthesizable RTL.

## What has actually run

| Layer | Evidence |
| --- | --- |
| Native functional backend | 98 runtime checks per model; 16 image/model combinations, 96 modeled DMA frames and 144 benchmark rows including software references |
| RTL capture replay | The same application consumes baseline/candidate feature frames captured by the real Questa SoC test |
| Cortex-A53 adapter/demo | Six AArch64 objects compiled with strict warnings against installed Vitis 2025.2 standalone-v9.4 headers |
| Benchmark guards | Ten unit tests; reject model/timer/sample/prediction mismatches, failed runs and fabricated model-speedup comparisons |
| Board measurements | Not run; no board latency, throughput or speedup result is claimed |

The [native application record](evidence/application_validation.json) binds
source identities and checkpoint hashes. Native-mode timing values are deliberately
not presented as FPGA performance. The Vitis cross-compile uses compile-only
`xparameters.h`/`bspconfig.h` fixtures; it is **not** a generated BSP, linked
deployable ELF, or hardware test.

## Source layout

- `software/ultra96/vision_runtime.*`: platform-independent device lifecycle.
- `vector_front_reference.*`: scalar bit-exact four-filter convolution, with
  zero borders, signed coefficients, modulo-32-bit accumulation and saturation.
- `vision_benchmark.*`: same-front-end/same-classifier software baseline and CSV.
- `vision_sim.*`: functional MMIO/mailbox/DMA/cache model; **does not execute RV32**.
- `vision_demo_native.c`: runnable CLI application with optional RTL capture replay.
- `vision_platform_vitis.*`, `vision_demo_vitis.c`: standalone A53 adapter/demo.

The separate Questa gate executes actual GCC-built RV32 instructions and real
portal/mailbox/CDC/accelerator RTL. Capture replay connects its feature evidence
to the portable application, but is not live C-to-RTL co-simulation.

## Ownership and recovery

The application requires exclusive ownership of the mailbox, accelerator and
DMA. It validates IDs, minimum version `0x00020001`, frame size and mode support;
loads/readbacks firmware while RV32 is held reset; verifies all 44 model words;
and checks the vector commit version. RV32-controlled mode releases the core;
direct ARM-controlled mode keeps it reset.

Input/output buffers are separate, exclusively reserved, 64-byte-aligned
3,136-byte ranges in the supported low-DDR window. The host packs input pixels,
cleans both DMA buffers and issues a barrier before launch. It invalidates output
and issues barriers only after successful completion, then runs the float32
classifier. The simulator keeps separate CPU/device copies and checks cache and
barrier ordering; shared-memory shortcuts cannot hide missing cache maintenance.

Both control paths use finite monotonic timer deadlines plus a secondary poll
cap for a stopped timer. Diagnostics retain job ID, failing stage, firmware error,
DMA/accelerator status and recovery result. These hardware status snapshots may
be **post-firmware-recovery**; the firmware error code preserves the cause.
An ARM-controlled DMA failure resets/aborts before reuse. An RV32 host timeout
or failed reset quarantines the device: no classification, output invalidate,
new submission or buffer reuse is permitted until platform reset/reinitialization.
Do not ACK a still-running job to pretend it has been cancelled.

A timer cannot protect a CPU stalled inside an MMIO access. The Vitis backend
uses direct device accesses; a nonresponding AXI slave still requires external
watchdog/reset intervention. No bounded AXI-response guarantee is claimed.

## Local commands

Build the RV32 images first. Use GCC/Clang on `PATH`, or an x64 MSVC developer
shell with `--cc cl`:

```powershell
python scripts/validate_vision_app.py --cc cl --keep-build
python -m unittest discover -s scripts -p test_vision_benchmark.py
python scripts/summarize_vision_benchmark.py generated/experiments/vision-app.csv
```

To replay real RTL feature captures after the SoC gate:

```powershell
python scripts/validate_vision_app.py --cc cl `
  --capture-root generated/experiments/soc-e2e/3333ps `
  --output generated/experiments/vision-app-replay.json
```

`--keep-build` retains CLI executables under ignored
`generated/experiments/vision-app-build/{baseline,candidate}/`. A CLI accepts
`input.mem expected_features.mem repeats [rtl_capture.mem]`. Its first iteration
is tagged as warmup. GCC/Clang CI also runs AddressSanitizer/UndefinedBehaviorSanitizer.

Cross-compile against installed A53 headers without running Vitis/Vivado:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/check_vitis_application.ps1 `
  -VitisRoot "<install>/Vitis" `
  -ToolchainBin "<install>/gnu/aarch64/nt/aarch64-none/bin"
```

## Later Vitis deployment

1. Generate a standalone **Cortex-A53 64-bit** domain from the updated SoC XSA.
   Use the generated BSP headers/libraries, never the compile-contract fixtures.
   Confirm its address map matches `config/soc_address_map.json`.
2. Compile the six sources listed in `check_vitis_application.ps1`, with include
   directories for the selected classifier bundle, firmware images, register
   headers and sample images. Define `VISION_MODEL_SHA256` to the selected
   classifier manifest's 64-character checkpoint hash (a raw preprocessing token).
   The build-check script supplies this automatically; manual Vitis builds must too.
3. Reserve/link the two aligned arrays in identity-mapped low DDR, separate from
   code, heap, stack and other DMA users. The runtime rejects out-of-window pointers;
   that check does not itself reserve memory. Configure MMIO as Device memory.
4. Link the actual standalone BSP, program hardware and launch the application.
   It runs eight images with one warmup plus five measured iterations per path.
   It checks **all output features and predictions** against the software reference.
5. Capture UART CSV and run `summarize_vision_benchmark.py` on it.

The adapter uses AMD's cache/MMIO/timer APIs, following the cache-ownership
pattern in the [AXI DMA example](https://github.com/Xilinx/embeddedsw/blob/xilinx_v2025.2/XilinxProcessorIPLib/drivers/axidma/examples/xaxidma_example_simple_poll.c).
The generated BSP controls the real timer frequency; the compile fixture does not.

## Benchmark interpretation

Three paths use the same image, convolution parameters and float classifier:
portable scalar software, RV32-controlled acceleration and direct ARM-controlled
acceleration. Boot/model programming occurs once per path and is excluded from
steady-state latency. Report preparation, cache clean, submission/wait, output
invalidate, classifier and total separately. `software_front_ticks` measures
the scalar software convolution. Concurrent DMA channels are not misrepresented
as independently timed transfers; accelerator cycles are separate telemetry.

The analyzer excludes warmups and reports median/p95. Speedup is calculated only
for paired physical-board rows with the same checkpoint, backend, sample,
iteration, timer frequency and prediction. Native functional-model rows produce
**no speedup result**. Keep compiler flags, clocks, cache settings and workload
fixed across board runs. The scalar reference is not an optimized NEON/library
baseline, and RV32 control is not assumed faster than ARM control.
