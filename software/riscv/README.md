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

On Windows, the repository script performs the same build without requiring
GNU Make. Point it at the RISC-V `bin` directory installed with Vitis:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build_riscv_firmware.ps1 `
  -ToolchainBin "<Vitis-install>\gnu\riscv\nt\bin"
```

The build produces separate 32-bit-word `controller_imem.mem` and
`controller_dmem.mem` files for the block-RAM-backed Harvard local memories.
`IMEM_HEX` and `DMEM_HEX` on `rv32_pipeline_axi_top` select those files for
simulation or synthesis initialization.

The mailbox `TRANSFER_BYTES` field follows AXI DMA byte-length semantics. The
accelerator consumes one 32-bit beat per pixel with full `TKEEP`, so a standard
784-pixel frame uses `784 * 4 = 3136` transfer bytes.

The build checks that the ELF entry point and `.text` address are both zero
before generating memory files. This prevents linker metadata from shifting
PC-relative startup code away from the processor reset vector. The compiled
firmware control sequence and the hand-authored directed sequence are both
covered by the local Questa regression when the firmware images are present.
The compiled-image suite covers successful completion plus bad descriptor,
accelerator-ID, MM2S, S2MM, and accelerator-diagnostic failures.
