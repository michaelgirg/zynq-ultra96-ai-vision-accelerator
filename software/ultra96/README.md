# Ultra96-V2 ARM host helper

`rv32_controller.c` loads and verifies RV32 instruction/data words through the
ARM-only AXI portals, releases the five-stage soft processor, submits vision
jobs through the ownership mailbox, and acknowledges completion or failure.

The host must keep `BOOT_CONTROL.bit0` clear while loading both memories. Load
the firmware ELF's instruction and data images as 32-bit words at the matching
portal offsets, verify readback, release RV32 reset, then submit descriptors.
For the current one-pixel-per-32-bit-beat stream contract, set
`transfer_bytes = image_pixels * 4`.

`scripts/build_riscv_firmware.ps1` emits `controller_images.h` with both word
arrays and exact word counts. Pass those arrays to `rv32_boot_controller`; it
keeps the core in reset on a bounds or readback failure and releases it only
after both 64 KiB portals verify successfully.

```c
rv32_boot_controller(
    RV32_MAILBOX_BASE_DEFAULT,
    RV32_HOST_IMEM_BASE_DEFAULT,
    RV32_HOST_DMEM_BASE_DEFAULT,
    rv32_controller_imem_words,
    RV32_CONTROLLER_IMEM_WORD_COUNT,
    rv32_controller_dmem_words,
    RV32_CONTROLLER_DMEM_WORD_COUNT
);
```
