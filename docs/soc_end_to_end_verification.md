# End-to-end RV32 vision-SoC simulation

The October 24, 2026 local run passed all three clock ratios: **306 jobs, 210
successful frames, 164,640 exact word comparisons and 48 native-C capture
checks**. The [compact evidence record](evidence/soc_end_to_end.json) includes
per-clock counts, feature hashes and source identities. These are simulation
checks, not functional-coverage closure percentages.

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
limit is a calibrated wall-clock timeout. A nonresponding AXI-Lite slave can
still stall the CPU; the behavioral fabric always responds.

## Implementation boundary

Frame abort and operand retention change synthesizable RTL. Current discovery
is `0x00020001`; preserved routed bitstream/XSA and timing/resource numbers are
the earlier `0x00020000` checkpoint. New firmware rejects that older version.
A user-run Vivado rebuild is required before deploying recovery-aware firmware.
Existing licensed UVM results remain baseline evidence; the version-expectation
update is locally compiled, with licensed rerun separate. This simulation does
not establish updated timing or physical-board operation.
