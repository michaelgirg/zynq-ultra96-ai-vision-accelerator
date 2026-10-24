# Documentation guide

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
