# Documentation guide

- [Complete Ultra96 application and benchmark](ultra96_application.md): native
  functional backend, RTL capture replay, A53 adapter, diagnostics and limits.
- [Executed bounded formal check](bounded_formal.md): real AXI-master safety,
  initial-reset assumption, 32-step bound and intentional-defect sensitivity.

- [End-to-end SoC simulation](soc_end_to_end_verification.md): real portal boot,
  full-frame golden checks, native C predictions, failure recovery and limits.

## Current production documents

- [Four-filter model training and ARM classifier](vector_model_training.md):
  validation-based training, robustness results, candidate parameters, and C/RTL checks.
- [Ultra96-V2 release status](production_v2_release_status.md): implementation,
  timing, CDC, DRC, utilization, and power evidence.
- [Verification plan](verification_plan.md): reusable verification architecture
  and execution flow.
- [Production-v2 register map](register_map.md): AXI4-Lite software contract.
- [Ultra96-V2 build flow](ultra96_v2_build.md): portable Vivado flow.
- [RV32IM heterogeneous control SoC](rv32_soc_integration.md): processor,
  MMIO/AXI, DMA, mailbox, host boot, firmware, verification, and routed
  Ultra96-V2 implementation evidence plus portable reproduction commands.

Repository scripts use repository-relative paths, runtime tool overrides, and
ignored build directories. CI rejects machine-specific paths, private host
identifiers, credential-like text, and generated-file drift.

## Historical engineering snapshots

The following files retain prior architecture and implementation checkpoints.
They are useful for design evolution, but the production-v2 documents above are
the current source of truth:

- `axi_stream_dma_architecture.md`
- `convolution_latency_performance_audit.md`
- `ppa_comparison.md`
- `results.md`
- `timing_closure.md`
