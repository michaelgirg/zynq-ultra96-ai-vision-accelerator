# End-to-end RV32 vision-SoC simulation

The October 24, 2026 local run passed all three clock ratios: **306 jobs, 210
successful frames, 164,640 exact word comparisons and 48 native-C capture
checks**. The [compact evidence record](evidence/soc_end_to_end.json) includes
per-clock counts, feature hashes and source identities. These are simulation
checks, not functional-coverage closure percentages.

The expanded run additionally hits **57/57 explicitly planned directed bins at
each clock ratio**: four modes, two vector models, 16 mode/fault combinations,
16 corresponding recoveries, 12 rejected descriptor classes, two discovery
failures, four abort/strobe cases and reset-failure quarantine. These event
bitmaps are checked by `scripts/check_soc_coverage.py`; they are not UVM covergroup,
code or toggle coverage. Bound assertions check held instruction metadata and
retention of forwarded rs1/rs2 operands through stalls. Abort corner tests cover
zero WSTRB, upper-byte-only writes, low-byte abort before input and repeated abort.

## Scope

The local Questa test joins the real RV32IM core, caches, BRAM backing memories,
AXI memory portals, ownership mailbox and dual-clock accelerator. The host loads
and reads back GCC-built firmware through AXI while the mailbox holds the core
in reset; there is no hierarchical DUT-memory preload. The capability lookup
table is loaded into DMEM and read by the CPU, testing the Harvard linker layout.

Host, round-robin AXI-Lite fabric, simple-mode DMA registers and DDR are behavioral
models. This does not verify AMD SmartConnect, encrypted AXI DMA IP, PS DDR, ARM
cache maintenance or physical hardware. Captured mode-3 DDR words run through
the portable C classifier on the native host, not an ARM CPU in simulation.

## Regression contract

Each stream-clock half-period (3,333 ps, 6,500 ps and 1,850 ps) runs against a
100 MHz control clock with source gaps, sink backpressure, separated host AW/W
and delayed host response acceptance.

| Check | Per clock ratio |
| --- | ---: |
| Baseline 28x28 frames: 8 images x 4 modes | 32 |
| Candidate coefficients programmed through AXI: 8 images | 8 |
| Invalid descriptors, each followed by a valid frame | 12 failures + 12 frames |
| MM2S error, S2MM error, partial timeout, bad TKEEP in each mode | 16 failures + 16 recovery frames |
| Wrong IP ID and old IP version, each followed by a valid frame | 2 failures + 2 frames |
| DMA reset never clears; next job remains quarantined | 2 failures |
| Total jobs / successful golden-checked frames | 102 / 70 |
| Exact 32-bit output comparisons | 54,880 |
| Captured baseline/candidate frames checked through native C | 16 |

Checks include full TKEEP, exact beat count, final-beat TLAST, buffer guards,
mailbox result/error/job ID, ACK-to-idle and CPU faults. Invalid descriptors and
quarantined jobs may not start DMA. Recoverable faults are followed by a full
frame without resetting the CPU; candidate coefficients must survive recovery.
Every job additionally checks its level IRQ/cause, submit/claim/end timestamp
ordering, exact end-minus-submit duration, cumulative completion/failure counts
and IRQ deassertion on ACK. Bridge timeout/drain and independent mailbox fault
access are tested separately in the focused [watchdog suite](job_diagnostics.md).

Descriptors must use exactly `IMAGE_PIXELS * 4` bytes, supported modes and a
threshold <=255. Buffers must be word aligned, non-overlapping and contained
in `[0x00100000, 0x80000000)`. This supported low-DDR software window does not
prove allocation or access permissions; the host still reserves buffers and
performs cache maintenance. Tests include short/long/non-word lengths, null,
misaligned, overlapping, MMIO, out-of-range and wrapping addresses.

## Fixes covered

- Boot helper asserts reset before checking replacement images, including empty
  IMEM. Native C tests verify rejection stops a running core without portal writes.
- Read-only firmware constants live in DMEM because data loads cannot access IMEM.
- Firmware validates exact frame length, both buffers and mode capabilities.
- Polling watches both DMA errors: an S2MM failure must not appear as MM2S timeout.
- Recovery resets DMA and aborts/flushes partial accelerator state. A finite reset
  deadline returns error 7 on failure and quarantines later jobs until platform
  recovery/reboot; ACK does not clear quarantine. Codes 1-6 retain their meanings.
- EX operands retain forwarded values across long MEM/EX stalls. A focused
  seven-transaction MMIO regression failed on counter/store values before the fix
  and passes afterward.

DMA reset semantics follow AMD's [AXI DMA driver documentation](https://xilinx.github.io/embeddedsw.github.io/axidma/doc/html/api/group___a_x_i_d_m_a.html):
resetting either channel resets the entire engine.

## Run locally

Use a shell with Questa, a RISC-V bare-metal GNU toolchain and native C compiler.
For MSVC, use an x64 Developer PowerShell/Command Prompt. From the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run_soc_end_to_end.ps1 `
  -ToolchainBin "<Vitis-install>\gnu\riscv\nt\bin" -CCompiler cl
python .\scripts\validate_rv32_boot.py --cc cl
```

With GCC/Clang on `PATH`, omit `-CCompiler cl`. `-PythonExe` selects Python;
PyTorch is not required. Logs/captures remain in ignored
`generated/experiments/soc-e2e/`. Run simulations sequentially on a single-session
Starter license. The runner uses a **test-only** 1,024-poll firmware deadline;
normal builds retain 1,000,000 polls. Source/control flow are identical. Neither
limit is a calibrated wall-clock timeout. The separate hardware progress
watchdog can detect a nonresponding RV32 target but does not manufacture a
response or guarantee CPU progress; the behavioral fabric in this full-frame
suite always responds.

## Implementation boundary

Frame abort, operand retention and mailbox/watchdog changes affect synthesizable RTL. Current accelerator discovery
is `0x00020001`; preserved routed bitstream/XSA and timing/resource numbers are
the earlier `0x00020000` checkpoint. New firmware rejects that older version.
A user-run Vivado rebuild is required before deploying recovery-aware firmware.
The complete application also requires the new mailbox version `0x00010000`.
Existing licensed UVM results remain baseline evidence; the version-expectation
update is locally compiled, with licensed rerun separate. This simulation does
not establish updated timing or physical-board operation.
