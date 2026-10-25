"""Summarize measured CSV; never infer FPGA speedup from functional-model timings."""
from __future__ import annotations
import argparse
import csv
import json
import math
import re
import statistics
from collections import defaultdict
from pathlib import Path


def summarize(rows: list[dict]) -> dict:
    groups = defaultdict(list)
    for row in rows:
        if row["measurement_domain"] not in ("board", "host-functional-model"):
            raise ValueError("unknown measurement domain")
        if not re.fullmatch(r"[a-fA-F0-9]{64}", row["model_sha256"]):
            raise ValueError("benchmark is not bound to a model checkpoint")
        if row["warmup"] not in ("0", "1") or int(row["result"]) != 0:
            raise ValueError("invalid warmup flag or failed run in performance input")
        hz, ticks = int(row["tick_hz"]), int(row["total_ticks"])
        if hz <= 0 or ticks < 0:
            raise ValueError("invalid timer data")
        if row["warmup"] == "1":
            continue
        key = tuple(row[k] for k in ("model_sha256", "backend", "measurement_domain", "path"))
        groups[key].append(row)
    summaries = []
    for key, data in sorted(groups.items()):
        hz = {int(r["tick_hz"]) for r in data}
        if len(hz) != 1:
            raise ValueError("timer frequency changed within a benchmark group")
        identities = [(r["sample"], r["iteration"]) for r in data]
        if len(set(identities)) != len(identities):
            raise ValueError("duplicate sample/iteration timing records")
        values = sorted(int(r["total_ticks"]) * 1e6 / int(r["tick_hz"]) for r in data)
        summaries.append(dict(zip(("model_sha256", "backend", "measurement_domain", "path"), key),
            samples=len(data), median_us=statistics.median(values),
            p95_us=values[math.ceil(len(values)*.95)-1]))
    speedups = []
    for key, accelerated in groups.items():
        model, backend, domain, path = key
        if domain != "board" or path not in ("rv32-control", "rv32-irq", "arm-control"):
            continue
        software = groups.get((model, backend, domain, "software"))
        if not software:
            continue
        reference = {(r["sample"], r["iteration"]): r for r in software}
        ratios = []
        if len(reference) != len(accelerated):
            raise ValueError("unbalanced software/hardware samples")
        for row in accelerated:
            other = reference.get((row["sample"], row["iteration"]))
            if not other or row["prediction"] != other["prediction"] or row["tick_hz"] != other["tick_hz"]:
                raise ValueError("software/hardware workload or prediction mismatch")
            if int(row["total_ticks"]) <= 0 or int(other["total_ticks"]) <= 0:
                raise ValueError("zero-duration board measurement")
            ratios.append(int(other["total_ticks"]) / int(row["total_ticks"]))
        speedups.append({"model_sha256": model, "backend": backend, "path": path,
                         "paired_median_end_to_end_speedup": statistics.median(ratios)})
    return {"groups": summaries, "speedups": speedups,
            "note": "Warmups excluded. Speedup requires paired same-model physical-board records; native-model timings are not FPGA performance."}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("csv", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    with args.csv.open(newline="") as f:
        result = summarize(list(csv.DictReader(line for line in f if not line.startswith("#"))))
    text = json.dumps(result, indent=2) + "\n"
    if args.output:
        args.output.write_text(text)
    else:
        print(text, end="")


if __name__ == "__main__":
    main()
