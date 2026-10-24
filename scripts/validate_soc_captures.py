"""Check simulated DDR features and run the real C head on each captured frame."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import subprocess
import tempfile
from pathlib import Path

from validate_vector_classifier import ROOT, compile_classifier, validate_exports


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--capture-dir", type=Path, default=ROOT / "generated/experiments/soc-e2e")
    parser.add_argument("--cc")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    reports = []
    for name, directory in (("baseline", "generated/classifier"),
                            ("candidate", "generated/candidates/vector_conv4/classifier")):
        model_dir = ROOT / directory
        manifest = validate_exports(model_dir)
        samples = {sample["name"]: sample for sample in manifest["samples"]}
        with tempfile.TemporaryDirectory(prefix="soc-classifier-") as temp:
            executable = compile_classifier(model_dir, Path(temp), args.cc)
            for index in range(8):
                sample = samples[f"sample_{index:03}"]
                capture = args.capture_dir / f"{name}_sample_{index:03}.mem"
                actual = [int(word, 16) for word in capture.read_text().split()]
                golden = [int(word, 16) for word in (model_dir / sample["mem"]).read_text().split()]
                if len(actual) != 784 or actual != golden:
                    raise AssertionError(f"simulated DDR features differ: {capture.name}")
                result = subprocess.check_output([str(executable), str(capture)], text=True).split()
                if len(result) != 11 or int(result[0]) != sample["prediction"]:
                    raise AssertionError(f"C prediction mismatch: {capture.name}")
                if not all(math.isclose(float(a), b, rel_tol=2e-4, abs_tol=2e-4)
                           for a, b in zip(result[1:], sample["logits"])):
                    raise AssertionError(f"C logits mismatch: {capture.name}")
                reports.append({"model": name, "sample": sample["name"],
                                "prediction": int(result[0]), "words": len(actual),
                                "capture_sha256": hashlib.sha256(
                                    capture.read_bytes().replace(b"\r\n", b"\n")).hexdigest(),
                                "max_logit_error": max(abs(float(a)-b)
                                    for a, b in zip(result[1:], sample["logits"]))})
        print(f"PASS: {name}: 8 real SoC-simulation DDR frames -> native C predictions/logits")
    if args.report:
        args.report.write_text(json.dumps({"passed": True, "frames": reports}, indent=2) + "\n",
                               encoding="utf-8")


if __name__ == "__main__":
    main()
