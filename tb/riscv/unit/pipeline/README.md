# Pipeline Unit Tests

This directory contains procedural self-checking tests for the pipeline-only
modules. The current Questa Starter flow should avoid SVA assertions, so tests
use tasks, `if` checks, `$error`, and `$fatal`.

Run from `sim/questa`:

```powershell
vsim -c -do run_pipeline_unit.do
```

Covered modules:

- `if_id_reg_tb.sv`
- `id_ex_reg_tb.sv`
- `ex_mem_reg_tb.sv`
- `mem_wb_reg_tb.sv`
- `forwarding_unit_tb.sv`
- `load_use_hazard_unit_tb.sv`
- `pipeline_control_tb.sv`
- `mul_unit_tb.sv`

The pipeline top-level smoke test lives in `tb/integration/pipeline/` and runs
with `vsim -c -do run_pipeline_core.do`.
