# RV32IM heterogeneous control SoC

## Architecture

The five-stage in-order RV32IM pipeline is a control processor. Image pixels
never pass through its load/store path: AXI DMA moves each frame between DDR
and the vision accelerator over AXI4-Stream.

```text
ARM Cortex-A53 host
        |
        v
AXI job mailbox <------> five-stage RV32IM + private I/D caches
                                  |
                                  v
                         RV32 AXI4-Lite master
                                  |
                                  v
                           AXI SmartConnect
                         /        |        \
                accelerator    AXI DMA    mailbox
                                  |
                 DDR -> MM2S -> accelerator -> S2MM -> DDR
```

`core_pipeline` remains vendor-neutral. `rv32_mmio_router` sends addresses in
the configured MMIO windows to `rv32_axi_lite_master`; all other valid local
addresses retain the existing D-cache and backing-memory path. The router and
bridge permit one outstanding aligned 32-bit request, so the MEM stage simply
stalls until the selected target returns a response.

## Address map

| Region | Base | Size | Ownership |
| --- | ---: | ---: | --- |
| local instruction/data memory | `0x0000_0000` | 64 KiB | RV32 private |
| vision accelerator | `0xA000_0000` | 4 KiB | ARM and RV32 |
| AXI DMA | `0xA001_0000` | 64 KiB | ARM and RV32 |
| job mailbox | `0xA002_0000` | 4 KiB | ARM and RV32 |
| host instruction-memory portal | `0xA003_0000` | 64 KiB | ARM only |
| host data-memory portal | `0xA004_0000` | 64 KiB | ARM only |

`config/soc_address_map.json` is canonical. CI compares it with the
SystemVerilog package and RV32 firmware header.

## MMIO timing

For a store, MEM presents address, data, write strobes, and `req_valid`. The
router locks the selected MMIO destination, the AXI bridge captures the
request, and AW/W complete independently in either order. The bridge waits for
`BVALID`; `BRESP != OKAY` becomes `resp_fault`. The processor consumes the
registered response and advances the store.

For a load, the bridge holds AR until handshake, then waits for R. It captures
`RDATA` and converts `RRESP != OKAY` to `resp_fault`. The response remains
stable under processor backpressure. The pipeline writes the returned word in
WB, including normal load-use forwarding behavior.

## Mailbox ownership protocol

| Offset | Register | Description |
| ---: | --- | --- |
| `0x00` | `COMMAND` | exact command value: submit, claim, complete, fail, or acknowledge |
| `0x04` | `STATUS` | bit 0 pending, bit 1 busy, bit 2 done, bit 3 failed |
| `0x08` | `INPUT_ADDR` | MM2S source address in DDR |
| `0x0C` | `OUTPUT_ADDR` | S2MM destination address in DDR |
| `0x10` | `TRANSFER_BYTES` | byte length used for both DMA channels |
| `0x14` | `MODE` | accelerator mode 0-3 |
| `0x18` | `THRESHOLD` | threshold value 0-255 |
| `0x1C` | `JOB_ID` | host-selected correlation identifier |
| `0x20` | `RESULT` | controller result (`0x600D` on success) |
| `0x24` | `ERROR_CODE` | controller failure code |
| `0x28` | `MAILBOX_ID` | read-only `0x5A424D42` (`ZBMB`) |
| `0x2C` | `BOOT_CONTROL` | bit 0 releases RV32 reset after host memory loading |

The host writes a descriptor and submits it. RV32 claims the pending job,
which freezes descriptor writes, then writes result/error and completes or
fails it. The host reads the terminal state and acknowledges it before the
next descriptor. Illegal transitions return AXI `SLVERR`.

`TRANSFER_BYTES` uses AXI DMA byte units. Because the current stream contract
is one 32-bit beat with full `TKEEP` per pixel, a 784-pixel frame is 3,136
bytes on both MM2S and S2MM.

## Verification matrix

| Layer | Evidence |
| --- | --- |
| MMIO router | 206 directed checks: decode boundaries, cache bypass, faults, and backpressure |
| AXI master | 2,060 checks over 106 randomized transactions, both AW/W orders, errors, reset, and response stalls |
| processor wrapper | firmware-like program through full AXI channels with dependent load use |
| real accelerator | RV32 configures, starts, polls, and checks a threshold frame against real accelerator RTL |
| DMA control | RV32 programs MM2S/S2MM, behavioral DMA moves the stream, and mailbox receives completion |
| mailbox | 54 checks covering lifecycle, ownership, illegal transitions, and AXI backpressure |
| preservation | complete imported RV32IM pipeline/cache/M-extension regression remains passing |

The behavioral DMA model verifies controller sequencing without requiring an
encrypted Xilinx simulation model. Vivado synthesis, implementation, CDC/DRC,
and bitstream evidence are a separate tool run. Physical-board execution must
not be claimed until an Ultra96-V2 is available.
