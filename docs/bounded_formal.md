# Executed bounded formal safety checks

The real `rv32_axi_lite_master` passed Yosys SAT safety checking for 32 steps.
The [evidence record](evidence/rv32_axi_master_bmc.json) binds the engine version,
RTL and harness hashes. Intentional write-data corruption and removal of
quarantine gating in ignored derived copies are detected, confirming sensitivity.
The original RTL is never modified by that test.

Properties cover request address/data/strobes, stalled AW/W/AR payload stability,
single-outstanding ownership, processor-response stability and read/write error
mapping. The harness uses a four-cycle watchdog threshold (production default:
1,000,000), checks exact expiry/channel capture, sticky fault records, quarantine,
late-response faults and CPU-reset drain. Initial fabric reset is assumed;
subsequent requests, response values, slave delays, backpressure, processor reset
and fabric reset are unconstrained. No fairness is assumed.

This is **bounded safety evidence**, not an unbounded proof, liveness proof,
whole-SoC formal signoff or physical CDC/metastability analysis. The `SYNTHESIS`
define excludes concurrent simulation-only SVAs from the Yosys frontend; the
formal harness supplies executable immediate assertions for the same actual RTL.

With native Yosys:

```text
python scripts/run_bounded_formal.py --depth 32
```

Optional local WebAssembly runner (no Vivado/license/server needed):

```powershell
python -m pip install -r requirements-formal.txt
python scripts/run_bounded_formal.py --yosys .venv/Scripts/yowasp-yosys.exe
```

Logs, the derived mutant and results are ignored under
`generated/experiments/formal`. CI repeats the check and sensitivity test with
native Yosys. Modes and bounds are distinct concepts in the
[YosysHQ formal documentation](https://symbiyosys.readthedocs.io/en/latest/reference.html).

## Mailbox ownership and diagnostics

The actual `rv32_job_mailbox` also passes 32-step bounded safety checking:
ownership exclusivity, descriptor freeze while owned, response stability,
IRQ enable/W1C/set dominance, terminal commands, first-fault retention and reset.
Only initial reset is assumed; subsequent bus inputs, stalls, strobes, reset
and fault inputs are arbitrary. This is not a liveness or unbounded proof.

```text
python scripts/run_mailbox_formal.py --depth 32
```

The optional `--yosys .venv/Scripts/yowasp-yosys.exe` runner works locally.
[Evidence](evidence/rv32_mailbox_bmc.json) binds RTL and properties. The runner
creates an ignored derivative of the actual module, changes two unsupported
function-return statements to equivalent function-name assignments, and inserts
the immediate assertions from `verif/formal/rv32_mailbox_properties.svh`.
It never substitutes a behavioral model or edits the production RTL. Removing
W1C or permitting first-fault overwrites makes the same check fail. Logs and
mutants stay in `generated/experiments/mailbox-formal`; CI repeats both checks.
