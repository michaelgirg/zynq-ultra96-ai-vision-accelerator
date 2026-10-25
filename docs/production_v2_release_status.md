# Production-V2 Release Status

The [current RV32 implementation checkpoint](implementation_signoff.md) includes
`0x00020001` recovery, retained operands and mailbox/watchdog RTL: +1.203 ns
setup WNS, +0.008 ns hold WHS, zero failing endpoints. Its source/artifact-bound
record is separate from the earlier accelerator-only snapshot below. Licensed
UVM results remain baseline evidence, not a new licensed regression.

## Verification

| Area | Result |
| --- | --- |
| Python predictor | 6,272/6,272 outputs matched |
| Directed RTL | Modes 0-3, backpressure, consecutive frames, and error paths pass |
| Scalable convolution | 1-, 2-, and 4-filter configurations pass |
| CDC/reset stress | Three asynchronous clock ratios and reset-abort recovery pass |
| UVM | 11 focused tests plus a 100-seed randomized predictor run pass with zero UVM errors/fatals or assertion failures |
| Functional coverage | 100% targeted coverage |

## Preserved accelerator-only Ultra96-V2 implementation

| Metric | Result |
| --- | ---: |
| Target device | `xczu3eg-sbva484-1-i` |
| Control/data clocks | 100 MHz / 150.015 MHz |
| Routed setup WNS | +1.951 ns |
| Routed hold WHS | +0.010 ns |
| Routed TNS / failing endpoints | 0 / 0 |
| CDC critical or warning findings | 0 |
| Methodology findings | 0 |
| DRC errors or critical warnings | 0 |
| CLB LUTs | 10,968 / 70,560 (15.54%) |
| CLB registers | 13,599 / 141,120 (9.64%) |
| Block RAM tiles | 6 / 216 (2.78%) |
| DSP48E2 blocks | 45 / 360 (12.50%) |
| Estimated on-chip power | 2.084 W |

The implementation generated a bitstream-inclusive XSA. Release binaries are
distributed separately from the source tree; the accompanying SHA256 manifest
identifies the exact files.
