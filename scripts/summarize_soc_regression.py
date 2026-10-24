"""Produce a compact, path-safe record after the three-clock SoC gate passes."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = (
    "rtl/riscv/pipeline/core_pipeline.sv",
    "rtl/axis_preprocess_vector_axi_lite.sv",
    "rtl/axis_preprocess_vector_cdc.sv",
    "software/riscv/src/main.c", "software/riscv/linker.ld",
    "tb/riscv/integration/soc/rv32_soc_end_to_end_tb.sv",
    "tb/riscv/integration/soc/soc_dma_model.sv",
    "tb/riscv/integration/soc/soc_sim_bus_pkg.sv",
    "tb/riscv/integration/soc/soc_sim_axi.svh",
    "scripts/validate_soc_captures.py",
)


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--results", type=Path, default=ROOT / "generated/experiments/soc-e2e")
    parser.add_argument("--output", type=Path, default=ROOT / "generated/experiments/soc-e2e/summary.json")
    args = parser.parse_args()
    clocks = []
    for period in (3333, 6500, 1850):
        log = (args.results / f"soc_{period}ps.log").read_text()
        match = re.search(r"PASS: end-to-end SoC jobs=(\d+) frames=(\d+) compared=(\d+) "
                          r"axis_half_ps=(\d+) resets=(\d+)", log)
        if not match or "Errors: 0, Warnings: 0" not in log or re.search(r"\*\* (Error|Fatal):", log):
            raise ValueError(f"missing/unclean simulation result for {period} ps")
        jobs, frames, compared, half, resets = map(int, match.groups())
        if (jobs, frames, compared, half, resets) != (102, 70, 54880, period, 17):
            raise ValueError("regression counts changed; review the test plan before recording evidence")
        c = json.loads((args.results / f"{period}ps/c_predictions.json").read_text())
        if c.get("passed") is not True or len(c["frames"]) != 16:
            raise ValueError("missing C capture validation")
        clocks.append({"axis_half_period_ps": half, "jobs": jobs, "successful_frames": frames,
                       "compared_words": compared, "dma_resets": resets,
                       "native_c_frames": len(c["frames"]),
                       "native_c_max_logit_error": max(f["max_logit_error"] for f in c["frames"]),
                       "feature_captures": [{k: f[k] for k in ("model", "sample", "capture_sha256")}
                                            for f in c["frames"]]})
    report = {"schema": 1, "simulator": "Questa Intel Starter FPGA Edition 2021.2",
              "control_clock_mhz": 100, "test_poll_limit": 1024,
              "production_poll_limit": 1000000, "ip_version": "0x00020001",
              "scope": "real RV32/portals/mailbox/CDC/accelerator RTL; behavioral fabric/DMA/DDR; native host C",
              "vivado_rebuilt": False, "physical_board_execution": False,
              "totals": {"jobs": sum(c["jobs"] for c in clocks),
                         "successful_frames": sum(c["successful_frames"] for c in clocks),
                         "compared_words": sum(c["compared_words"] for c in clocks),
                         "native_c_frames": sum(c["native_c_frames"] for c in clocks)},
              "clocks": clocks, "source_sha256_lf": {p: digest(ROOT / p) for p in SOURCES}}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"PASS: recorded {report['totals']}")


if __name__ == "__main__":
    main()
