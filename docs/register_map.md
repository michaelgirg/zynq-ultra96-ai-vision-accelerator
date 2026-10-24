# Production-v2 AXI4-Lite Register Map

This is the implemented register contract of `axis_preprocess_vector_axi_lite`
and `axis_preprocess_vector_cdc`. The bus is 32 bits wide, little-endian, and
word aligned. Existing offsets remain stable; v2 discovery, diagnostics,
counters, and interrupts occupy previously unused space beginning at `0x70`.

## Access rules

- `RW`: readable and writable; only asserted `WSTRB` byte lanes change.
- `RO`: writes return `SLVERR` and have no side effect.
- `WO`: reads return zero with `SLVERR`.
- `W1C`: writing a one clears that bit; writing zero preserves it.
- A legal write with `WSTRB=0` is an `OKAY` no-op.
- Unmapped or misaligned accesses return `SLVERR`.
- Configuration and start/commit writes are rejected with `SLVERR` while a
  frame is active. Diagnostic W1C, interrupt-enable, and counter-clear writes
  remain legal while busy.

## Registers

| Offset | Name | Access | Reset | Description |
| ---: | --- | :---: | ---: | --- |
| `0x00` | `CTRL` | WO | `0` | bit 0 start; bit 1 clear legacy done/error; bit 2 abort/flush frame |
| `0x04` | `STATUS` | RO | `0` | bit 0 busy; bit 1 done; bit 2 packet error; bit 3 armed |
| `0x08` | `THRESHOLD` | RW | `128` | unsigned threshold in bits `[7:0]` |
| `0x0C` | `IMAGE_PIXELS` | RO | `784` | compile-time frame pixel count |
| `0x10` | `PIXELS_PER_CYCLE` | RO | `1` | input pixels accepted per cycle |
| `0x14` | `PROCESSING_CYCLES` | RO | `0` | cycles latched at the latest completed frame |
| `0x18`-`0x28` | reserved | - | - | legacy buffered-interface offsets; not implemented by the stream top |
| `0x2C` | `MODE` | RW | `0` | 0 threshold, 1 Sobel, 2 scalar conv, 3 vector conv |
| `0x30`-`0x50` | `CONV_K00`-`CONV_K22` | RW | model defaults | nine signed INT8 scalar-convolution taps |
| `0x54` | `CONV_BIAS` | RW | `-128` | signed INT32 scalar-convolution bias |
| `0x58` | `CONV_SHIFT` | RW | `3` | arithmetic right shift in bits `[4:0]` |
| `0x5C` | `CONV_RELU_EN` | RW | `1` | bit 0 enables ReLU |
| `0x60` | `VECTOR_CFG_INDEX` | RW | `0` | filter in `[5:4]`, entry in `[3:0]` |
| `0x64` | `VECTOR_CFG_DATA` | RW | model default | indirect vector shadow-bank data/readback |
| `0x68` | `VECTOR_CFG_COMMIT` | WO | `0` | bit 0 atomically commits all shadow entries while idle |
| `0x6C` | `VECTOR_CFG_VERSION` | RO | `0` | increments after each accepted commit |
| `0x70` | `IP_ID` | RO | `0x5A424156` | ASCII `ZBAV` |
| `0x74` | `IP_VERSION` | RO | `0x00020001` | major 2, minor 0, patch 1 (recoverable frame abort) |
| `0x78` | `CAPABILITIES` | RO | `0x000F044F` | implemented features, decoded below |
| `0x7C` | `FRAME_COUNT` | RO | `0` | saturating completed-frame count |
| `0x80` | `ERROR_COUNT` | RO | `0` | saturating packet/rejected-access event count |
| `0x84` | `INPUT_STALL_CYCLES` | RO | `0` | cycles active with input valid and input not ready |
| `0x88` | `OUTPUT_STALL_CYCLES` | RO | `0` | cycles output valid and output not ready |
| `0x8C` | `ERROR_STATUS` | W1C | `0` | sticky detailed error bits |
| `0x90` | `INT_STATUS` | W1C | `0` | sticky interrupt causes |
| `0x94` | `INT_ENABLE` | RW | `0` | interrupt cause mask |
| `0x98` | `PERF_CONTROL` | WO | `0` | bit 0 clears all four saturating counters |

Frame dimensions remain compile-time parameters in v2. Runtime width/height
registers are intentionally deferred because every current line buffer is sized
for a fixed frame geometry.

`CTRL.abort` is legal while busy and flushes all four streaming paths, including
partial-frame counters, FIFOs and line-buffer validity. It clears armed/done/
legacy packet-error state, but preserves coefficient banks, configuration
version, AXI responses and sticky diagnostic history. Stop/reset DMA before
reusing the stream. An abort explicitly cancels any stalled stream beat; it is
not normal completion. Write abort alone (not combined with start). Older
`0x00020000` bitstreams do not implement abort; the recovery-aware firmware
rejects those versions rather than assuming it exists.

## Indirect vector configuration

`VECTOR_CFG_INDEX[5:4]` selects filter 0-3. The entry field means:

| Entry | Data encoding |
| ---: | --- |
| 0-8 | signed INT8 kernel tap in `VECTOR_CFG_DATA[7:0]` |
| 9 | signed INT32 bias |
| 10 | shift in `[4:0]`, ReLU enable in bit 8 |

Writes update only the shadow bank. `VECTOR_CFG_COMMIT.bit0` copies all shadow
entries to the committed bank in one idle cycle. `CTRL.start` snapshots the
committed bank into active state, so later shadow writes cannot alter an
in-flight frame.

## Capability bits

`CAPABILITIES = 0x000F044F`:

| Bits | Meaning |
| ---: | --- |
| `[3:0]` | mode support bitmap; all four modes implemented |
| `[7:4]` | four vector filters |
| `[15:8]` | four AXI-Stream data bytes |
| `16` | atomic vector configuration commit |
| `17` | per-byte WSTRB preservation |
| `18` | AXI `SLVERR` response policy |
| `19` | counters and interrupt controller |

## Error and interrupt bits

`ERROR_STATUS`:

| Bit | Cause |
| ---: | --- |
| 0 | completed frame reported a packet-format error |
| 1 | AXI-Lite write was rejected |
| 2 | AXI-Lite read was rejected |

`INT_STATUS` and `INT_ENABLE` share this encoding:

| Bit | Cause |
| ---: | --- |
| 0 | frame completed |
| 1 | packet error |
| 2 | rejected AXI-Lite read or write |

`irq` is level-sensitive and equals `|(INT_STATUS & INT_ENABLE)`. Event set has
priority over a same-cycle W1C clear, preventing a newly arriving cause from
being lost.

## Software sequence

1. Confirm `IP_ID`, compatible `IP_VERSION`, and required capability bits.
2. Program mode and mode-specific shadow configuration while idle.
3. Commit vector configuration when using mode 3.
4. Clear stale `ERROR_STATUS` and `INT_STATUS`; enable desired interrupts.
5. Write `CTRL.start` and transfer exactly `IMAGE_PIXELS` input beats with
   `TLAST` on the final accepted beat.
6. Wait for IRQ or poll `STATUS.done`.
7. Read status, counters, and processing cycles; W1C handled causes.

For the CDC wrapper, assertion of either external reset flushes both synchronized
bridge halves. Software must not expect an outstanding AXI-Lite transaction to
survive either reset assertion; begin new accesses only after both domains have
deasserted reset and completed synchronization. Each reset assertion must remain
active long enough to be sampled by the opposite clock domain's two-stage reset
status synchronizer; four cycles of the slower clock is the verification rule.
