# RV32IM accelerator-controller firmware

This freestanding firmware implements the mailbox-to-DMA control loop for the
five-stage RV32IM soft processor. The controller claims a host job, configures
the real vision accelerator, arms S2MM before MM2S, polls both DMA channels,
checks accelerator diagnostics, and reports completion or failure through the
hardware mailbox.

Build with a bare-metal RISC-V GNU toolchain:

```sh
cd software/riscv
make CROSS_COMPILE=riscv64-unknown-elf-
```

The build produces separate 128-bit-line `controller_imem.mem` and
`controller_dmem.mem` files for the Harvard local memories. `IMEM_HEX` and
`DMEM_HEX` on `rv32_pipeline_axi_top` select those files for simulation or
synthesis initialization.

The mailbox `TRANSFER_BYTES` field follows AXI DMA byte-length semantics. The
accelerator consumes one 32-bit beat per pixel with full `TKEEP`, so a standard
784-pixel frame uses `784 * 4 = 3136` transfer bytes.

The local machine used for this integration does not currently expose a
RISC-V bare-metal compiler, so source-level firmware compilation remains an
external toolchain step. The same control sequence is executed instruction by
instruction in `rv32_dma_control_tb` and is covered by the local Questa
regression.
