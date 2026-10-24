"""Compare native C and PyTorch on every MNIST test image's integer features."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
import torch
from torch.utils.data import DataLoader
from torchvision import datasets, transforms

from export_vector_conv import fixed_features, integer_accumulators, quantize_parameters
from vector_conv_model import VectorConvClassifier

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from validate_vector_classifier import compile_classifier, text_hash, validate_exports


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkpoint", type=Path, default=Path("generated/candidates/vector_conv4/vector_conv4_cnn.pt"))
    parser.add_argument("--front-manifest", type=Path, default=Path("generated/candidates/vector_conv4/evaluation/front_manifest.json"))
    parser.add_argument("--model-dir", type=Path, default=Path("generated/candidates/vector_conv4/classifier"))
    parser.add_argument("--data-dir", type=Path, default=Path("generated/data"))
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cc")
    args = parser.parse_args()
    torch.set_num_threads(4)
    manifest = validate_exports(args.model_dir.resolve())
    checkpoint_hash = hashlib.sha256(args.checkpoint.read_bytes()).hexdigest()
    if checkpoint_hash != manifest["checkpoint_sha256"] or text_hash(args.front_manifest) != manifest["front_manifest_sha256"]:
        raise ValueError("checkpoint/front-end/export pairing mismatch")
    checkpoint = torch.load(args.checkpoint, map_location="cpu", weights_only=True)
    model = VectorConvClassifier().eval()
    model.load_state_dict(checkpoint["model_state"])
    front = json.loads(args.front_manifest.read_text(encoding="utf-8"))
    weights, biases, _ = quantize_parameters(model)
    if weights.to(torch.int32).tolist() != front["weights"] or biases.tolist() != front["biases"]:
        raise ValueError("front-end parameters do not match checkpoint")
    shifts = torch.tensor(front["shifts"])
    scales = torch.tensor(front["output_scales"]).reshape(1, 4, 1, 1)
    dataset = datasets.MNIST(str(args.data_dir), train=False, download=False, transform=transforms.ToTensor())
    if len(dataset) != 10000:
        raise ValueError("full-dataset check requires all 10,000 MNIST test images")
    labels_all, expected_all = [], []
    payload_hash = hashlib.sha256()
    with tempfile.TemporaryDirectory(prefix="vector-dataset-") as temporary:
        build = Path(temporary)
        binary = build / "features.bin"
        with binary.open("wb") as stream, torch.inference_mode():
            for images, labels in DataLoader(dataset, batch_size=128, shuffle=False):
                features = fixed_features(integer_accumulators(torch.round(images * 255).to(torch.uint8), weights, biases), shifts)
                expected_all.append(model.classify_features(features.float() * scales))
                labels_all.append(labels)
                channels = features.to(torch.int64).reshape(-1, 4, 784)
                packed = channels[:, 0] | channels[:, 1] << 8 | channels[:, 2] << 16 | channels[:, 3] << 24
                payload = packed.numpy().astype("<u4").tobytes()
                stream.write(payload)
                payload_hash.update(payload)
        executable = compile_classifier(args.model_dir.resolve(), build, args.cc)
        result = subprocess.run([str(executable), "--batch", str(binary)], check=True, capture_output=True, text=True)
    rows = [row.split() for row in result.stdout.splitlines()]
    if len(rows) != len(dataset) or any(len(row) != 11 for row in rows):
        raise AssertionError("C batch output has incorrect frame/logit count")
    predictions = np.array([int(row[0]) for row in rows])
    actual = np.array([[float(value) for value in row[1:]] for row in rows])
    expected = torch.cat(expected_all).numpy()
    labels = torch.cat(labels_all).numpy()
    agreement = int(np.count_nonzero(predictions == expected.argmax(1)))
    errors = np.abs(actual - expected)
    tolerance = np.maximum(2e-4, 2e-4 * np.maximum(np.abs(actual), np.abs(expected)))
    bad_logits = int(np.count_nonzero(~np.isfinite(actual) | (errors > tolerance)))
    if agreement != 10000 or bad_logits:
        raise AssertionError(f"C/PyTorch parity failure: matching predictions={agreement}, bad logits={bad_logits}")
    confusion = np.bincount(labels * 10 + predictions, minlength=100).reshape(10, 10)
    report = {
        "checkpoint_sha256": checkpoint_hash, "front_manifest_sha256": text_hash(args.front_manifest),
        "classifier_manifest_sha256": text_hash(args.model_dir / "manifest.json"),
        "c_source_sha256": text_hash(ROOT / "software/ultra96/vector_classifier.c"),
        "c_header_sha256": text_hash(ROOT / "software/ultra96/vector_classifier.h"),
        "c_harness_sha256": text_hash(ROOT / "software/ultra96/test_vector_classifier.c"),
        "dataset": "MNIST official test split in original index order", "samples": 10000,
        "dataset_images_sha256": hashlib.sha256(dataset.data.numpy().tobytes()).hexdigest(),
        "dataset_labels_sha256": hashlib.sha256(dataset.targets.numpy().astype("u1").tobytes()).hexdigest(),
        "packed_features_sha256": payload_hash.hexdigest(), "predictions_matched": agreement,
        "logits_compared": 100000, "logit_mismatches": bad_logits,
        "max_absolute_logit_error": float(errors.max()), "absolute_tolerance": 2e-4, "relative_tolerance": 2e-4,
        "c_correct": int(np.count_nonzero(predictions == labels)),
        "c_accuracy": float(np.mean(predictions == labels)),
        "pytorch_fixed_feature_accuracy": float(np.mean(expected.argmax(1) == labels)),
        "c_confusion_matrix": confusion.tolist(),
        "arithmetic": "integer convolution reference followed by native-host float32 C classifier",
        "compiler": Path(args.cc).name if args.cc else "auto-detected native C compiler",
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"PASS: {agreement}/10000 C predictions and 100000 logits match PyTorch; C accuracy={report['c_accuracy']:.4f}; max logit error={errors.max():.6g}")


if __name__ == "__main__":
    main()
