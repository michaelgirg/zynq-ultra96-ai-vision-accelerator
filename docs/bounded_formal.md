# Executed bounded formal safety check

The real `rv32_axi_lite_master` passed Yosys SAT safety checking for 32 steps.
The [evidence record](evidence/rv32_axi_master_bmc.json) binds the engine version,
RTL and harness hashes. An intentional write-data corruption in an ignored
derived copy was detected within an 8-step check, confirming harness sensitivity.
The original RTL is never modified by that test.

Properties cover request address/data/strobes, stalled AW/W/AR payload stability,
single-outstanding ownership, processor-response stability and read/write error
mapping. Initial reset is assumed; subsequent requests, response values, slave
delays, backpressure and resets are unconstrained. No fairness is assumed.

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
