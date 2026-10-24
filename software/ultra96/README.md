# Ultra96-V2 ARM host helper

The [complete application guide](../../docs/ultra96_application.md) covers the
portable runtime, functional simulation backend, Vitis adapter/demo, cache-safe
buffer ownership, diagnostics and three-path benchmark. Run
`python scripts/validate_vision_app.py` after building the RV32 images; use
`--cc cl` in an MSVC shell. All native performance records are explicitly
marked as functional-model measurements, not board results.
The complete runtime requires the versioned mailbox diagnostics extension and
retains job timing/first-fault telemetry. On AXI quarantine it avoids reading the
stalled target. See the [reset/interrupt contract](../../docs/job_diagnostics.md);
CPU reset alone is not a safe hot-reload/recovery operation during pending MMIO.

## Four-filter classifier

`vector_classifier.c` consumes a completed mode-3 DMA output buffer containing
784 packed words. It applies 2x2 max pooling, a 64-neuron ReLU layer, and a
ten-class output layer. It uses float32 classifier parameters; the FPGA
convolution remains INT8. Compile it with the matching exported model directory
on the include path. Baseline exports live in `generated/classifier`; candidate
exports live in `generated/candidates/vector_conv4/classifier`.

```c
#include "vector_classifier.h"
#include "vector_classifier_weights.h"

/* After successful DMA completion and platform-specific cache invalidation: */
float logits[VECTOR_CLASSIFIER_CLASSES];
int digit = vector_classifier_predict(output_words, &vector_classifier_model, logits);
```

Program all four filters' nine taps, bias, and shift/ReLU words from the matching
`vector_front_config.h` through the vector shadow registers while idle, then
commit before submitting a mode-3 job. Do not pair candidate classifier weights
with baseline convolution coefficients. The caller owns DMA buffer allocation,
address validation, cache maintenance, and mailbox job sequencing.

See `docs/vector_model_training.md` for training, export, and C/RTL checks.
The candidate C classifier has native-host validation on all 10,000 MNIST test
images. Check `scripts/check_vector_model_bundle.py` before using an exported
model; its frozen pairing includes the checkpoint, coefficients, classifier
weights, and evaluation evidence.

## RV32 boot and jobs

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
Include `software/riscv/include` when compiling this helper; it uses the shared
mailbox register contract. Boot rejects an unsupported mailbox or bridge
quarantine before touching either portal. Submit/wait return
`RV32_JOB_NEEDS_RESET` without submitting/acknowledging if quarantine is set.

Reset is asserted before validating replacement images, and empty IMEM is
rejected. Native tests: `python scripts/validate_rv32_boot.py` (add `--cc cl`
in an MSVC shell). Recovery-aware firmware requires `IP_VERSION=0x00020001`;
saved older bitstream/XSA files need rebuilding. Error 7 quarantines later
jobs; mailbox ACK alone does not restore DMA service.

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
