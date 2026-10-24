"""Execute bounded safety checks on the real RV32 AXI master using Yosys SAT."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--yosys")
    parser.add_argument("--depth", type=int, default=32)
    parser.add_argument("--output", type=Path, default=ROOT / "generated/experiments/formal")
    args = parser.parse_args()
    executable = args.yosys or shutil.which("yosys") or shutil.which("yowasp-yosys")
    if not executable:
        raise SystemExit("Install Yosys or use the optional yowasp-yosys package")
    if not 2 <= args.depth <= 128:
        raise SystemExit("depth must be 2..128")
    args.output.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    wasm = "yowasp" in Path(executable).name
    prefix = "/repo/" if wasm else ""
    if wasm:
        env["YOWASP_MOUNT"] = "/repo=."
        env["YOWASP_CACHE_DIR"] = str(ROOT / ".venv/yowasp-cache")
    help_text = subprocess.check_output([executable, "-Q", "-T", "-p", "help chformal"],
                                        cwd=ROOT, env=env, text=True)
    lower = "async2sync; chformal -lower; " if "-lower" in help_text else ""
    commands = (f"read_verilog -formal -D SYNTHESIS -sv {prefix}rtl/riscv/soc/rv32_axi_lite_master.sv "
                f"{prefix}verif/formal/rv32_axi_master_harness.sv; "
                "prep -top rv32_axi_master_harness; flatten; " + lower +
                f"sat -verify -prove-asserts -set-assumes -seq {args.depth}")
    result = subprocess.run([executable, "-p", commands], cwd=ROOT, env=env,
                            capture_output=True, text=True, timeout=240)
    (args.output / "axi_master.log").write_text(result.stdout + result.stderr)
    if result.returncode or "SUCCESS!" not in result.stdout:
        raise SystemExit("Formal check failed; inspect the AXI-master log")
    # Non-vacuity/sensitivity check: corrupt a real write-data output in an
    # ignored derived copy, never the RTL source. The same properties must fail.
    source_path = ROOT / "rtl/riscv/soc/rv32_axi_lite_master.sv"
    source = source_path.read_text()
    mutation = "assign M_AXI_WDATA = request_wdata ^ 32'd1;"
    if source.count("assign M_AXI_WDATA = request_wdata;") != 1:
        raise SystemExit("mutation target changed; review the sensitivity check")
    mutant = args.output.resolve() / "axi_master_mutant.sv"
    mutant.write_text(source.replace("assign M_AXI_WDATA = request_wdata;", mutation))
    mutant_path = prefix + mutant.relative_to(ROOT).as_posix()
    mutant_commands = commands.replace(prefix + "rtl/riscv/soc/rv32_axi_lite_master.sv", mutant_path)
    mutant_commands = mutant_commands.replace(f"-seq {args.depth}", "-seq 8")
    negative = subprocess.run([executable, "-p", mutant_commands], cwd=ROOT, env=env,
                              capture_output=True, text=True, timeout=120)
    (args.output / "mutation.log").write_text(negative.stdout + negative.stderr)
    if negative.returncode == 0 or "proof did fail" not in negative.stdout + negative.stderr:
        raise SystemExit("formal harness did not detect the intentional write-data defect")
    # Removing quarantine must also fail, independently of payload checking.
    target = "(state == AXI_IDLE) && !quarantined && !processor_reset"
    if source.count(target) != 1:
        raise SystemExit("quarantine mutation target changed")
    quarantine_mutant = args.output.resolve() / "quarantine_mutant.sv"
    quarantine_mutant.write_text(source.replace(target, "(state == AXI_IDLE) && !processor_reset"))
    quarantine_commands = commands.replace(prefix + "rtl/riscv/soc/rv32_axi_lite_master.sv",
        prefix + quarantine_mutant.relative_to(ROOT).as_posix())
    negative_quarantine = subprocess.run([executable, "-p", quarantine_commands], cwd=ROOT, env=env,
        capture_output=True, text=True, timeout=120)
    (args.output / "quarantine_mutation.log").write_text(negative_quarantine.stdout + negative_quarantine.stderr)
    if negative_quarantine.returncode == 0 or "proof did fail" not in negative_quarantine.stdout + negative_quarantine.stderr:
        raise SystemExit("formal harness did not detect the intentional quarantine defect")
    version = subprocess.check_output([executable, "-V"], cwd=ROOT, env=env, text=True).strip()
    report = {"engine": version, "mode": "bounded-safety", "depth_cycles": args.depth,
              "result": "PASS", "top": "rv32_axi_master_harness",
              "scope": "AXI payload/stall stability, one-outstanding ownership, timeout threshold/capture, quarantine, CPU-reset drain and response mapping",
              "watchdog_cycles_in_harness": 4, "watchdog_cycles_production_default": 1000000,
              "assumptions": ["reset asserted at initial step"],
              "unbounded_proof": False, "liveness_proven": False,
              "intentional_write_data_mutation_detected": True,
              "intentional_quarantine_mutation_detected": True,
              "source_sha256_lf": {str(p.relative_to(ROOT)).replace("\\", "/"):
                  hashlib.sha256(p.read_bytes().replace(b"\r\n", b"\n")).hexdigest()
                  for p in (source_path, ROOT / "verif/formal/rv32_axi_master_harness.sv")}}
    (args.output / "result.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"PASS: real RV32 AXI master bounded safety, {args.depth} cycles; not an unbounded/liveness proof")


if __name__ == "__main__":
    main()
