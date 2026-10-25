"""Record the executed mailbox/watchdog checks without local paths or transcripts."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = (
    "rtl/riscv/soc/rv32_axi_lite_master.sv",
    "rtl/riscv/soc/rv32_job_mailbox.sv",
    "rtl/riscv/soc/rv32_pipeline_axi_top.sv",
    "rtl/riscv/soc/rv32_pipeline_axi_subsystem.sv",
    "software/riscv/include/job_mailbox.h",
    "tb/riscv/unit/soc/rv32_axi_watchdog_tb.sv",
    "tb/riscv/unit/soc/rv32_job_mailbox_tb.sv",
    "tb/riscv/integration/soc/rv32_soc_end_to_end_tb.sv",
    "vivado/scripts/create_ultra96_v1_production_v2_project.tcl",
    "vivado/scripts/package_rv32_control_soc_ip.tcl",
    "scripts/summarize_job_diagnostics.py",
)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--log", type=Path, default=ROOT / "generated/experiments/soc-unit-diagnostics.log")
    parser.add_argument("--output", type=Path, default=ROOT / "generated/experiments/job-diagnostics.json")
    args = parser.parse_args()
    log = args.log.read_text()
    expected = {
        "mailbox_checks": r"PASS: rv32_job_mailbox_tb \(15885 checks\)",
        "mailbox_random": r"PASS: randomized mailbox 20 seeds / 320 jobs",
        "watchdog_checks": r"PASS: rv32_axi_watchdog_tb \(184 checks; 6/6 channel scenarios\)",
        "baseline_axi": r"PASS: RV32 AXI4-Lite master \(2060 checks, 55 writes, 51 reads, 12 faults\)",
    }
    if re.search(r"\*\* (Error|Fatal):", log) or "Errors: 0, Warnings: 0" not in log:
        raise ValueError("unclean simulation log")
    if not all(re.search(pattern, log) for pattern in expected.values()):
        raise ValueError("missing/changed test counts; review the verification contract")
    report = {
        "simulator": "Questa Intel Starter FPGA Edition 2021.2", "result": "PASS",
        "mailbox_checks": 15885, "mailbox_random_seeds": 20, "mailbox_random_jobs": 320,
        "watchdog_checks": 184, "baseline_axi_checks": 2060,
        "watchdog_channel_scenarios": 6, "watchdog_test_cycles": 8,
        "watchdog_production_default_cycles": 1000000,
        "mailbox_version": "0x00010000",
        "scope": "directed RTL mailbox/IRQ/timing/first-fault tests and real AXI-master watchdog-to-mailbox integration",
        "code_or_uvm_coverage_claimed": False, "vivado_rebuilt": False,
        "physical_board_execution": False,
        "source_sha256_lf": {name: hashlib.sha256((ROOT / name).read_bytes().replace(b"\r\n", b"\n")).hexdigest()
                             for name in SOURCES},
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print("PASS: recorded mailbox/watchdog directed simulation evidence")


if __name__ == "__main__":
    main()
