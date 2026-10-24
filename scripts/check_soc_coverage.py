"""Check only the explicitly planned directed SoC bins, not UVM/code coverage."""
from __future__ import annotations
import argparse
import json
from pathlib import Path

EXPECTED = {"modes": 15, "models": 3, "faults": 65535, "recoveries": 65535,
            "descriptors": 4095, "discovery": 3, "abort": 15, "quarantine": 1}


def check(path: Path, period: int) -> dict:
    data = json.loads(path.read_text())
    if data.get("axis_half_period_ps") != period:
        raise ValueError("coverage clock identity mismatch")
    for name, mask in EXPECTED.items():
        if data.get(name) != mask:
            raise ValueError(f"missing/illegal directed coverage bins: {name}")
    return {"axis_half_period_ps": period, "hit": 57, "planned": 57,
            "kind": "directed-event-bitmaps", "masks": data}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("--period", type=int)
    args = parser.parse_args()
    for period in ([args.period] if args.period else [3333, 6500, 1850]):
        check(args.root / f"{period}ps/coverage.json", period)
        print(f"PASS: {period} ps directed SoC bins 57/57; no UVM/code-coverage claim")


if __name__ == "__main__": main()
