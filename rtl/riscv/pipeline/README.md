# Pipeline RTL

This directory contains the five-stage pipelined RV32I core.

## Files

- `core_pipeline.sv`: shared five-stage top-level integration
- `if_id_reg.sv`: IF/ID pipeline register
- `id_ex_reg.sv`: ID/EX pipeline register
- `ex_mem_reg.sv`: EX/MEM pipeline register
- `mem_wb_reg.sv`: MEM/WB pipeline register
- `forwarding_unit.sv`: EX-stage operand forwarding control
- `load_use_hazard_unit.sv`: one-cycle load-use hazard detector
- `pipeline_control.sv`: PC stall/redirect and pipeline flush arbiter

## Current Status

The pipeline register modules, forwarding unit, load-use hazard unit, pipeline
control unit, and top-level smoke integration test pass in Questa.

## Ownership Reminder

Coordinate changes to module ports, package structs, bubble constants, and the
top-level wiring before editing shared interfaces. Small local implementation
changes are fine, but anything that changes a field name, width, enum, or
pipeline-register payload needs both teammates to know.
