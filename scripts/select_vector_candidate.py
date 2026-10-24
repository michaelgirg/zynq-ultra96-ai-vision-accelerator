"""Select a CNN training run using held-out validation metrics only."""

import argparse
import hashlib
import json
import shutil
import math
from pathlib import Path


def load_candidate(run: Path) -> tuple:
    metrics = json.loads((run / "metrics_vector_conv4.json").read_text(encoding="utf-8"))
    if "validation" not in metrics or metrics.get("validation_samples", 0) <= 0:
        raise ValueError("every candidate must have held-out validation evidence")
    checkpoint = run / "vector_conv4_cnn.pt"
    digest = hashlib.sha256(checkpoint.read_bytes()).hexdigest()
    if digest != metrics["checkpoint_sha256"]:
        raise ValueError("candidate checkpoint integrity mismatch")
    report_dir = run / "quantized_validation"
    report = json.loads((report_dir / "evaluation.json").read_text(encoding="utf-8"))
    front_digest = hashlib.sha256((report_dir / "front_manifest.json").read_bytes().replace(b"\r\n", b"\n")).hexdigest()
    if report["split"] != "validation":
        raise ValueError("test-set results cannot be used for candidate selection")
    if report["checkpoint_sha256"] != digest or report["front_manifest_sha256"] != front_digest:
        raise ValueError("quantized validation belongs to different checkpoint/configuration")
    if report["validation_indices_sha256"] != metrics["validation_indices_sha256"]:
        raise ValueError("quantized validation uses a different validation split")
    clean = report["results"]["clean"]
    if clean["samples"] != metrics["validation_samples"]:
        raise ValueError("quantized validation sample count differs")
    accuracy, loss = clean["fixed_feature_accuracy"], clean["fixed_feature_loss"]
    if not math.isfinite(accuracy) or not 0 <= accuracy <= 1 or not math.isfinite(loss) or loss < 0:
        raise ValueError("invalid quantized validation metrics")
    return accuracy, -loss, run, metrics, report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("runs", nargs="+", type=Path)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    candidates = []
    split_hash = None
    for run in args.runs:
        candidate = load_candidate(run)
        metrics = candidate[3]
        current_split = metrics["validation_indices_sha256"]
        if split_hash is not None and current_split != split_hash:
            raise ValueError("candidate validation splits differ")
        split_hash = current_split
        candidates.append(candidate)
    selected = max(candidates, key=lambda candidate: candidate[:2])
    if args.output_dir.exists():
        raise FileExistsError("use a new selection directory; refusing to overwrite")
    args.output_dir.mkdir(parents=True)
    for name in ("vector_conv4_cnn.pt", "metrics_vector_conv4.json"):
        shutil.copyfile(selected[2] / name, args.output_dir / name)
    shutil.copytree(selected[2] / "quantized_validation", args.output_dir / "quantized_validation")
    summary = {
        "selection": "highest fixed-feature validation accuracy, then lowest fixed-feature loss; test results unused",
        "selected_seed": selected[3]["seed"], "validation_indices_sha256": split_hash,
        "candidates": [{"seed": item[3]["seed"], "fixed_feature_validation_accuracy": item[0],
                        "fixed_feature_validation_loss": -item[1], "selected_epoch": item[3]["selected_epoch"],
                        "checkpoint_sha256": item[3]["checkpoint_sha256"]} for item in candidates],
    }
    (args.output_dir / "selection.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(f"Selected seed {selected[3]['seed']} at validation accuracy {selected[0]:.4f}; copied to {args.output_dir}")


if __name__ == "__main__":
    main()
