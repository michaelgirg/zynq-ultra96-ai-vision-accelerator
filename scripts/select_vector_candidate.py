"""Select a CNN training run using held-out validation metrics only."""

import argparse
import hashlib
import json
import shutil
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("runs", nargs="+", type=Path)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    candidates = []
    split_hash = None
    for run in args.runs:
        metrics = json.loads((run / "metrics_vector_conv4.json").read_text(encoding="utf-8"))
        if "validation" not in metrics or metrics.get("validation_samples", 0) <= 0:
            raise ValueError("every candidate must have held-out validation evidence")
        current_split = metrics["validation_indices_sha256"]
        if split_hash is not None and current_split != split_hash:
            raise ValueError("candidate validation splits differ")
        split_hash = current_split
        checkpoint = run / "vector_conv4_cnn.pt"
        if hashlib.sha256(checkpoint.read_bytes()).hexdigest() != metrics["checkpoint_sha256"]:
            raise ValueError("candidate checkpoint integrity mismatch")
        candidates.append((metrics["validation"]["accuracy"], -metrics["validation"]["loss"], run, metrics))
    selected = max(candidates, key=lambda candidate: candidate[:2])
    if args.output_dir.exists():
        raise FileExistsError("use a new selection directory; refusing to overwrite")
    args.output_dir.mkdir(parents=True)
    for name in ("vector_conv4_cnn.pt", "metrics_vector_conv4.json"):
        shutil.copyfile(selected[2] / name, args.output_dir / name)
    summary = {
        "selection": "highest validation accuracy, then lowest validation loss; test results unused",
        "selected_seed": selected[3]["seed"], "validation_indices_sha256": split_hash,
        "candidates": [{"seed": item[3]["seed"], "validation_accuracy": item[0],
                        "validation_loss": -item[1], "selected_epoch": item[3]["selected_epoch"],
                        "checkpoint_sha256": item[3]["checkpoint_sha256"]} for item in candidates],
    }
    (args.output_dir / "selection.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(f"Selected seed {selected[3]['seed']} at validation accuracy {selected[0]:.4f}; copied to {args.output_dir}")


if __name__ == "__main__":
    main()
