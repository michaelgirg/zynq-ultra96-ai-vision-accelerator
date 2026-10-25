# Ultra96-V2 application and benchmark

The portable application joins firmware boot/readback, IP discovery, runtime
model programming, DMA buffer ownership, job submission, prediction and CSV
diagnostics. Both baseline and candidate exports are supported without changing
the saved model files or synthesizable RTL.

## What has actually run

| Layer | Evidence |
| --- | --- |
| Native functional backend | 160 runtime checks per model; 16 image/model combinations, 144 modeled DMA frames and 192 benchmark rows including software references |
| RTL capture replay | The same application consumes baseline/candidate feature frames captured by the real Questa SoC test |
| Cortex-A53 adapter/demo | Two linked ELFs, real XSA-generated standalone BSP, strict warnings, all allocated ELF sections checked, reserved low-DDR DMA ranges |
| Benchmark guards | Eleven unit tests; reject model/timer/sample/prediction mismatches, failed runs and fabricated model-speedup comparisons |
| Board measurements | Not run; no board latency, throughput or speedup result is claimed |

The [native application record](evidence/application_validation.json) binds
source identities and checkpoint hashes. Native-mode timing values are deliberately
not presented as FPGA performance. The [Vitis build record](evidence/vitis_application.json)
binds both linked ELFs to the fresh XSA and source hashes. The earlier compile-only
fixtures/check script were removed; this flow uses actual generated headers and libraries.
Linking an ELF is not execution on the board.

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
DMA. It validates IDs, accelerator minimum version `0x00020001`, mailbox extension
version `0x00010000`, frame size and mode support;
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

The [mailbox diagnostics](job_diagnostics.md) expose control-clock job timing,
first-fault records and live AXI quarantine. The runtime captures these before
ACK and, on bridge quarantine, reads only the mailbox: it must not revisit the
potentially hung DMA/accelerator target. Native models leave hardware cycle
measurements at zero.

The demo runs direct ARM polling first while RV32 is held reset, then boots RV32
once for polling followed by IRQ measurements. It never hot-resets the running
controller to switch paths. In IRQ mode the GIC ISR latches causes and clears
only the IRQ W1C register; main validates terminal ownership/job ID/results and
captures diagnostics before job ACK. Completion, failure and watchdog causes
are enabled; stale causes are cleared while masked before submission. Spurious,
conflicting or lost events fail closed without classifying stale output.

The wait spins on an ISR-latched flag with timer and iteration bounds, **not** on
mailbox status MMIO. No unbounded WFI or CPU-sleep/power-saving claim is made.
Watchdog cause takes priority and blocks target MMIO, ACK and buffer reuse.
Native tests exercise this contract; actual GIC interrupt delivery still needs
board execution. The GIC ID is derived from the real generated SDT (this XSA:
SPI 92 + 32 = 124), not a guessed hard-coded BSP fixture.

A timer cannot protect a CPU stalled inside an MMIO access. The Vitis backend
uses direct device accesses; a nonresponding AXI slave still requires external
watchdog/reset intervention. The new watchdog monitors RV32 master progress,
not ARM accesses; it preserves the pending transaction and requires coordinated
fabric reset after quarantine. No bounded AXI-response guarantee is claimed.
Firmware hot-reload with CPU reset alone is unsafe during pending MMIO, including
an idle controller's status polling. Restart the platform coherently instead.

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

Build the real standalone platform and both baseline/candidate applications
from an already completed SoC XSA (no Vivado run or board connection):

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build_vitis_application.ps1 `
  -VitisPath "<install>/Vitis/bin/vitis.bat" `
  -ToolchainBin "<install>/gnu/aarch64/nt/aarch64-none/bin"
```

Optional `-Xsa <soc.xsa>` and `-Workspace <dedicated-build-directory>` keep large
generated builds on another drive. Defaults are the repo's generated SoC XSA
and ignored `vitis/vision_standalone/`. The script refuses an existing platform
with a different XSA; use a new workspace rather than deleting an existing one.
It checks a per-invocation success receipt because the Vitis launcher can return
zero even when Python failed. Windows cleanup targets only its own spawned
server process tree to avoid stale workspace locks, never another Vitis instance.

Outputs are `vision_baseline/build/vision_baseline.elf`,
`vision_candidate/build/vision_candidate.elf`, a generated platform with FSBL/PMU
firmware and `vision_build_evidence.json` under the workspace. The linker limits
code/data/heap/stack to `[0x00100000,0x10000000)` and reserves an exclusive 8 KiB
DMA region at `0x10000000`; frame arrays occupy separate aligned 4 KiB slots.
Linker assertions plus symbol and allocated-section checks reject overlap,
wrong sizes, missing sections, or unexpected placement. Four portable negative
layout tests run in CI. This is an identity-mapped standalone application, not
a Linux virtual-address DMA driver or a shared DDR allocator.

The generated BSP is configured for **PS UART1, J1, 115200 8N1**. Vitis initially
selected UART0 (the wireless-module UART), so using its default would hide output
from the debug pod. The connector mapping is documented in the
[Avnet hardware guide](https://www.avnet.com/wcm/connect/b85b9556-0b2a-42b3-ad6a-8dcf3eac1ff9/Ultra96-V2-HW-User-Guide-v1_3.pdf?MOD=AJPERES).

## Later physical-board deployment

1. Use the bitstream-inclusive XSA paired with the linked application; verify
   its hash against the build receipt. The adapter compile-checks generated BSP
   peripheral addresses against the canonical SoC address map.
2. Start from a coordinated platform reset, initialize PS/DDR through the
   generated platform boot flow and program the matching PL bitstream.
3. Launch one selected model ELF with exclusive DMA/mailbox ownership. Confirm
   identity-mapped cacheable DDR and Device MMIO settings from the standalone BSP.
   It runs eight images with one warmup plus five measured iterations per path.
   It checks **all output features and predictions** against the software reference.
4. Capture UART CSV and run `summarize_vision_benchmark.py` on it. Repeat with a
   coordinated reset for the other model; do not hot-reload a polling RV32 core.

The adapter uses AMD's cache/MMIO/timer APIs, following the cache-ownership
pattern in the [AXI DMA example](https://github.com/Xilinx/embeddedsw/blob/xilinx_v2025.2/XilinxProcessorIPLib/drivers/axidma/examples/xaxidma_example_simple_poll.c).
The generated BSP controls the real timer frequency.

## Benchmark interpretation

Four paths use the same image, convolution parameters and float classifier:
portable scalar software, RV32 polling, RV32 mailbox IRQ and direct ARM polling.
Boot/model programming occurs before measurement and is excluded from
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
