# Ultra96-V2 ARM host helper

`rv32_controller.c` loads and verifies RV32 instruction/data words through the
ARM-only AXI portals, releases the five-stage soft processor, submits vision
jobs through the ownership mailbox, and acknowledges completion or failure.

The host must keep `BOOT_CONTROL.bit0` clear while loading both memories. Load
the firmware ELF's instruction and data images as 32-bit words at the matching
portal offsets, verify readback, release RV32 reset, then submit descriptors.
For the current one-pixel-per-32-bit-beat stream contract, set
`transfer_bytes = image_pixels * 4`.
