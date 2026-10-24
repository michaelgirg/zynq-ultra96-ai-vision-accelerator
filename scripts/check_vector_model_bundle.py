"""Freeze and verify paired CNN checkpoints, front ends, exports, and evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def digest(path: Path) -> str:
    data = path.read_bytes()
    if path.suffix in (".json", ".h", ".mem", ".c"):
        data = data.replace(b"\r\n", b"\n")
    return hashlib.sha256(data).hexdigest()


def checked_path(root: Path, value: str) -> Path:
    path = (root / value).resolve()
    if not path.is_relative_to(root.resolve()):
        raise ValueError("bundle path escapes repository")
    return path


def check_bundle(bundle_path: Path, root: Path = ROOT) -> dict:
    bundle = json.loads(bundle_path.read_text(encoding="utf-8"))
    if bundle.get("schema_version") != 1:
        raise ValueError("unsupported model bundle schema")
    paths = {}
    for role, entry in bundle["files"].items():
        path = checked_path(root, entry["path"])
        if digest(path) != entry["sha256"]:
            raise ValueError(f"model bundle integrity mismatch: {role}")
        paths[role] = path
    export = json.loads(paths["classifier_manifest"].read_text(encoding="utf-8"))
    links = {"checkpoint": "checkpoint_sha256", "front_manifest": "front_manifest_sha256",
             "classifier_weights": "header_sha256", "front_config_header": "front_config_sha256",
             "front_config_mem": "front_config_mem_sha256"}
    for role, field in links.items():
        if digest(paths[role]) != export[field]:
            raise ValueError(f"classifier export pairing mismatch: {role}")
    for sample in export["samples"]:
        sample_role = "sample_" + sample["name"]
        if sample_role not in paths or digest(paths[sample_role]) != sample["sha256"]:
            raise ValueError("classifier sample pairing mismatch")
    checkpoint_hash = digest(paths["checkpoint"])
    front_hash = digest(paths["front_manifest"])
    for role in ("test_evaluation", "training_metrics", "quantized_validation", "c_dataset_evaluation"):
        if role not in paths:
            continue
        report = json.loads(paths[role].read_text(encoding="utf-8"))
        if report["checkpoint_sha256"] != checkpoint_hash:
            raise ValueError(f"evaluation/checkpoint pairing mismatch: {role}")
        if "front_manifest_sha256" in report and report["front_manifest_sha256"] != front_hash:
            raise ValueError(f"evaluation/front-end pairing mismatch: {role}")
    if "quantized_validation" in paths:
        report = json.loads(paths["quantized_validation"].read_text(encoding="utf-8"))
        metrics = json.loads(paths["training_metrics"].read_text(encoding="utf-8"))
        if report["split"] != "validation" or report["validation_indices_sha256"] != metrics["validation_indices_sha256"]:
            raise ValueError("quantized validation split mismatch")
        selection = json.loads(paths["quantized_selection"].read_text(encoding="utf-8"))
        selected = [item for item in selection["candidates"] if item["seed"] == selection["selected_seed"]]
        if len(selected) != 1 or selected[0]["checkpoint_sha256"] != checkpoint_hash:
            raise ValueError("quantized selection/checkpoint mismatch")
        clean = report["results"]["clean"]
        if (selection["selected_seed"] != metrics["seed"] or
                selection["validation_indices_sha256"] != metrics["validation_indices_sha256"] or
                selected[0]["fixed_feature_validation_accuracy"] != clean["fixed_feature_accuracy"] or
                selected[0]["fixed_feature_validation_loss"] != clean["fixed_feature_loss"]):
            raise ValueError("quantized selection metrics do not match validation report")
    if "c_dataset_evaluation" in paths:
        report = json.loads(paths["c_dataset_evaluation"].read_text(encoding="utf-8"))
        if (report["classifier_manifest_sha256"] != digest(paths["classifier_manifest"]) or
                report["c_source_sha256"] != digest(paths["c_source"]) or
                report["c_header_sha256"] != digest(paths["c_header"]) or
                report["c_harness_sha256"] != digest(paths["c_harness"])):
            raise ValueError("C dataset report belongs to different exports/source")
        if report["samples"] != 10000 or report["predictions_matched"] != 10000 or report["logit_mismatches"] != 0:
            raise ValueError("C dataset report does not establish full test parity")
        test = json.loads(paths["test_evaluation"].read_text(encoding="utf-8"))
        if report["c_accuracy"] != test["results"]["clean"]["fixed_feature_accuracy"]:
            raise ValueError("C and Python test accuracy differ")
    return bundle


def freeze_bundle(output: Path, checkpoint: Path, front: Path, classifier: Path, extra: dict | None = None) -> None:
    roles = {"checkpoint": checkpoint, "front_manifest": front,
             "classifier_manifest": classifier / "manifest.json",
             "classifier_weights": classifier / "vector_classifier_weights.h",
             "front_config_header": classifier / "vector_front_config.h",
             "front_config_mem": classifier / "vector_front_config.mem",
             "c_source": ROOT / "software/ultra96/vector_classifier.c",
             "c_harness": ROOT / "software/ultra96/test_vector_classifier.c",
             "c_header": ROOT / "software/ultra96/vector_classifier.h"}
    manifest = json.loads((classifier / "manifest.json").read_text(encoding="utf-8"))
    roles.update({"sample_" + sample["name"]: classifier / sample["mem"] for sample in manifest["samples"]})
    roles.update(extra or {})
    bundle = {"schema_version": 1,
              "text_hash_policy": "SHA256 after CRLF-to-LF normalization; checkpoints are byte-exact",
              "files": {role: {"path": path.resolve().relative_to(ROOT).as_posix(), "sha256": digest(path)}
                        for role, path in roles.items()}}
    # Validate the complete pairing before replacing the published lock file.
    temporary = output.with_suffix(".pending.json")
    try:
        temporary.write_text(json.dumps(bundle, indent=2) + "\n", encoding="utf-8")
        check_bundle(temporary)
        temporary.replace(output)
    finally:
        temporary.unlink(missing_ok=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="Explicitly refresh locks after validation/export")
    args = parser.parse_args()
    baseline = ROOT / "generated/classifier"
    candidate = ROOT / "generated/candidates/vector_conv4"
    if args.write:
        freeze_bundle(baseline / "bundle.json", ROOT / "generated/model/vector_conv4_cnn.pt",
                      ROOT / "generated/test_vectors/vector_conv4_manifest.json", baseline)
        extras = {"test_evaluation": candidate / "evaluation/evaluation.json",
                  "training_metrics": candidate / "metrics_vector_conv4.json",
                  "quantized_validation": candidate / "quantized_validation/evaluation.json",
                  "quantized_selection": candidate / "quantized_selection.json",
                  "historical_selection": candidate / "selection.json",
                  "c_dataset_evaluation": candidate / "c_dataset_evaluation.json"}
        freeze_bundle(candidate / "bundle.json", candidate / "vector_conv4_cnn.pt",
                      candidate / "evaluation/front_manifest.json", candidate / "classifier", extras)
    for path in (baseline / "bundle.json", candidate / "bundle.json"):
        bundle = check_bundle(path)
        print(f"PASS: {path.relative_to(ROOT)} binds {len(bundle['files'])} artifacts")


if __name__ == "__main__":
    main()
