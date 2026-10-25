# Ultra96-V2 Build Flow

The production hardware flow targets the Ultra96-V2 board and the `xczu3eg-sbva484-1-i` device.

## Board setup

Install the Ultra96-V2 board definition in Vivado, or point `ULTRA96_BOARD_REPO` at the board-store directory containing the board files. The repository includes `vivado/scripts/check_ultra96_v2_board.tcl` for a quick board-part check.
The V2 entry sources the shared `check_ultra96_v1_board.tcl` helper with V2
selection enabled; its historical filename does not select a V1 board.
Keep the entire tracked script directory together when copying the build flow.

## Vivado flow

From the repository root, run the scripts with Vivado in batch mode:

```text
vivado -mode batch -source vivado/scripts/check_ultra96_v2_board.tcl
vivado -mode batch -source vivado/scripts/run_ultra96_v2_parallelism_sweep.tcl
vivado -mode batch -source vivado/scripts/create_ultra96_v2_production_v2_project.tcl
vivado -mode batch -source vivado/scripts/run_ultra96_v2_production_v2_synth.tcl
vivado -mode batch -source vivado/scripts/run_ultra96_v2_production_v2_implementation.tcl
```

On Windows, `scripts/run_ultra96_v2_local_vivado.ps1` wraps these stages. Pass `-VivadoPath` when Vivado is not on `PATH`, and pass `-BoardRepo` when the board definition is stored outside Vivado's default board store.

Generated Vivado projects, logs, reports, bitstreams, and XSA files are intentionally excluded from source control. Release binaries are distributed separately with the matching SHA256 manifest.
The optional 1/2/4-filter sweep runs out-of-context synthesis with a 100 MHz
clock constraint; its estimates are not routed implementation/signoff results.
It is separate from the RV32 `-Stage all` build.

Without launching Vivado, check source dependencies with
`python scripts/check_vivado_dependencies.py`. CI also executes the board probe
and sweep orchestration with mocked Vivado commands (`tclsh tb/scripts/vivado_flow_test.tcl`);
that test does not claim synthesis or real board-store discovery.

All Tcl paths are derived from `[info script]`, and PowerShell wrappers derive
the repository root from `$PSScriptRoot`. Vivado, board-store, and toolchain
locations are runtime arguments or environment variables; no developer machine
path is tracked. Packaged project IP uses the neutral
`user.org:u96_ai_vision` VLNV namespace.

## RV32 heterogeneous control SoC

The RV32 flow extends the released accelerator-only checkpoint with the
five-stage controller as SmartConnect master 1, the hardware mailbox, and
ARM-loadable 64 KiB instruction/data portals while preserving the 100 MHz
control and 150 MHz stream domains.

On Windows, run all RV32 packaging, project creation, synthesis,
implementation, reports, bitstream, and XSA stages with:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run_ultra96_v2_rv32_soc_local.ps1 -Stage all
```

The `package` and `all` stages refresh both the accelerator and RV32 IP
packages. Project creation also detects and replaces stale packaged-IP vendor
metadata, so ignored output from an older checkout cannot silently enter the
block design.

If Vivado is not on `PATH`, append
`-VivadoPath "<Vivado-install>\2025.2\bin\vivado.bat"`. If the board files are
installed through the Windows Vivado Store, the wrapper discovers that board
repository automatically. For any other location, append
`-BoardRepo "<board-store>"`.
The new generated project is `vivado/u96v2_rv32_soc_vivado`; the bitstream and
bitstream-inclusive XSA are generated only after implementation succeeds. The
RV32 project creator safely replaces this ignored generated project directory,
so `-Stage all` can be rerun after a failed build.

The completed current build closes timing at +1.203 ns setup WNS and +0.008
ns hold WHS with zero failing endpoints. See
`docs/rv32_soc_integration.md` for utilization and signoff details, and
`hardware/reports/ultra96_v2_rv32_soc_2026_10_24_sha256.txt` for artifact hashes.
This checkpoint establishes implementation readiness; execution on a physical
Ultra96-V2 remains a separate runtime-validation step.
