# RV32IM source provenance

The five-stage in-order RV32IM implementation in this directory was vendored
from `michaelgirg/ooop-riscv` at commit:

```text
191604a1449d8a8134e74a31c614bc2fd8d18f8e
```

Imported source directories:

- `rtl/common`
- `rtl/pipeline`
- `rtl/single_cycle`
- `tb`
- `sim/questa`

Only path references and repository text-hygiene issues were normalized during
the import; the processor behavior is unchanged.

The unfinished out-of-order implementation is intentionally excluded. Files
under `rtl/riscv/soc` are integration-specific additions maintained in this
repository. Future imports must identify a new source commit and pass the
vendored baseline regressions before SoC-specific changes are reapplied.
