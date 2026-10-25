# Current RV32 SoC implementation checkpoint

Vivado 2025.2 completed the full Ultra96-V2 flow on October 24, 2026 at source
`1f519a5`: synthesis, routing, final reports, bitstream and bitstream-inclusive
XSA. This includes accelerator recovery version `0x00020001`, retained pipeline
operands, mailbox IRQ/timestamps and AXI watchdog/quarantine. No physical-board
execution is implied.

| Metric | Routed result |
| --- | ---: |
| Device | `xczu3eg-sbva484-1-i` |
| Control / stream clocks | 100.000 / 150.015 MHz |
| Setup WNS / TNS / failing endpoints | +1.203 ns / 0 / 0 |
| Hold WHS / THS / failing endpoints | +0.008 ns / 0 / 0 |
| Pulse-width slack / failing endpoints | +1.833 ns / 0 |
| Bus-skew constraints | 18 passing; minimum slack +5.843 ns |
| CDC | 29 informational, zero warning/critical findings |
| Methodology | Zero findings |
| DRC | Zero error/critical findings; 97 ordinary warnings |
| LUTs / registers | 17,790 (25.21%) / 22,593 (16.01%) |
| BRAM / DSP | 38 (17.59%) / 49 (13.61%) |
| Estimated power | 2.126 W, medium confidence, vectorless |

The [portable evidence](evidence/rv32_soc_implementation.json) records exact RTL
and constraint hashes, report hashes, metrics and artifacts. The XSA's single
embedded bitstream was hash-checked against the routed output. The
[dated SHA256 manifest](../hardware/reports/ultra96_v2_rv32_soc_2026_10_24_sha256.txt)
identifies this build; the undated manifest remains the older historical
checkpoint, not this one. Later software/formal/packager edits do not change the
synthesizable RTL in this checkpoint.

## Warning disposition

Warnings remain visible; no blanket severity overrides or waivers were added.

| Rule | Count | Review and disposition |
| --- | ---: | --- |
| DPIP-2 | 43 | DSP input pipeline suggestions in compute datapaths. Current routed setup/hold pass. Adding stages changes latency/control alignment and requires new simulation and implementation; not justified solely to remove advisories. |
| DPOP-3 | 2 | DSP output/PREG suggestions. Same timing-based disposition; retained. |
| DPOP-4 | 49 | DSP MREG suggestions. Same timing-based disposition; retained. |
| REQP-1935 | 2 | Generated AXI DMA MM2S/S2MM store-and-forward XPM FIFOs use synchronous SDP BRAM with NO_CHANGE. Same-address collisions could corrupt data. Retained as a vendor-IP advisory: behavioral DMA tests do not prove the encrypted/generated FIFO collision behavior. Vendor-IP simulation or board stress is still needed for that runtime boundary. |
| RTSTAT-10 | 1 | One rule instance lists 126 unused DMA/XPM memory output nets, not 126 independent DRC failures. These are generated memory `dout` nets, not missing top-level connections. Retained without editing vendor internals. |

The power report has no simulation-activity file and warns about default reset
activity. Its estimate is not measured board power or a validated power budget.
Board-catalog and packaging metadata advisories are distinct from final routed
CDC/methodology/DRC checks; this build is not globally warning-free.

The packagers originally used in-memory (non-project) mode, producing critical
warning `Ipptcl 7-1601` about future unsupported packaging. Both now create real
on-disk projects under ignored `vivado/*_packager_vivado/` directories. A subsequent
**packaging-only** Vivado 2025.2 run completed with integrity checks passing and
zero occurrences of that critical warning. It did not reroute or replace the
bitstream/XSA above. Plain SystemVerilog port/interface metadata warnings remain
visible; they are not treated as failures in routed timing.

## Reproduce and record

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_ultra96_v2_rv32_soc_local.ps1 -VivadoPath "<Vivado-install>/bin/vivado.bat" -Stage all
python scripts/capture_vivado_evidence.py --source-ref <actual-build-commit> --output generated/experiments/vivado-implementation.json
```

Pass `--build-root <build-checkout>` if reports/artifacts are in a separate
build mirror. The capture tool rejects a claimed revision if RTL/constraint
contents differ, checks timing/skew/CDC/DRC and XSA bitstream identity, and emits
no machine-specific paths. Retain the original reports locally for review.
