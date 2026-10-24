"""Evaluate clean/perturbed float and hardware-quantized CNN features."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import torch
from torch.utils.data import DataLoader, Subset
from torchvision import datasets, transforms
from torchvision.transforms import functional as image_ops

from export_vector_conv import choose_shifts, fixed_features, integer_accumulators, quantize_parameters
from vector_conv_model import VectorConvClassifier


def prepare_front(model: VectorConvClassifier, checkpoint: dict, dataset, count: int) -> dict:
    excluded = set(checkpoint.get("validation_indices", []))
    indices = [index for index in range(len(dataset)) if index not in excluded][:count]
    if not indices:
        raise ValueError("no training-only calibration samples")
    weights, biases, scales = quantize_parameters(model)
    accumulators = []
    for images, _ in DataLoader(Subset(dataset, indices), batch_size=128):
        accumulators.append(integer_accumulators(torch.round(images * 255).to(torch.uint8), weights, biases))
    shifts = choose_shifts(torch.cat(accumulators), 0.999)
    return {"weights": weights.to(torch.int32).tolist(), "biases": biases.tolist(),
            "shifts": shifts.tolist(), "relu_enable": [1] * 4,
            "output_scales": (scales * 2.0 ** shifts.float() / 255).tolist(),
            "calibration_samples": len(indices), "calibration_source": "training indices excluding held-out validation"}


def evaluate(model: VectorConvClassifier, loader: DataLoader, front: dict, condition: str) -> dict:
    device = next(model.parameters()).device
    weights = torch.tensor(front["weights"], dtype=torch.int8)
    biases = torch.tensor(front["biases"], dtype=torch.int32)
    shifts = torch.tensor(front["shifts"], dtype=torch.int64)
    scales = torch.tensor(front["output_scales"]).reshape(1, 4, 1, 1)
    confusion = torch.zeros(10, 10, dtype=torch.int64)
    float_correct = agreement = total = saturated = active = 0
    fixed_loss_sum = 0.0
    generator = torch.Generator().manual_seed(2026)
    with torch.inference_mode():
        for images, labels in loader:
            if condition == "shift_right_2":
                images = image_ops.affine(images, angle=0.0, translate=[2, 0], scale=1.0, shear=[0.0, 0.0])
            elif condition == "rotate_10":
                images = image_ops.rotate(images, angle=10.0)
            elif condition == "noise_005":
                images = (images + 0.05 * torch.randn(images.shape, generator=generator)).clamp(0, 1)
            pixels = torch.round(images * 255).to(torch.uint8)
            float_predictions = model((pixels.float() / 255).to(device)).argmax(1).cpu()
            features = fixed_features(integer_accumulators(pixels, weights, biases), shifts)
            fixed_logits = model.classify_features((features.float() * scales).to(device))
            fixed_predictions = fixed_logits.argmax(1).cpu()
            fixed_loss_sum += torch.nn.functional.cross_entropy(fixed_logits, labels.to(device), reduction="sum").item()
            confusion += torch.bincount(labels * 10 + fixed_predictions, minlength=100).reshape(10, 10)
            float_correct += int((float_predictions == labels).sum())
            agreement += int((float_predictions == fixed_predictions).sum())
            total += labels.numel()
            interior = features[:, :, 1:-1, 1:-1]
            saturated += int((interior == 255).sum())
            active += interior.numel()
    return {"samples": total, "float_accuracy": float_correct / total,
            "fixed_feature_accuracy": int(confusion.diag().sum()) / total,
            "fixed_feature_loss": fixed_loss_sum / total,
            "prediction_agreement": agreement / total, "interior_saturation_fraction": saturated / active,
            "fixed_feature_confusion_matrix": confusion.tolist(),
            "fixed_feature_per_class_accuracy": (confusion.diag() / confusion.sum(1).clamp(min=1)).tolist()}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--front-manifest", type=Path)
    parser.add_argument("--data-dir", type=Path, default=Path("generated/data"))
    parser.add_argument("--split", choices=("validation", "test"), default="validation")
    parser.add_argument("--calibration-samples", type=int, default=2048)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--threads", type=int, default=4)
    parser.add_argument("--clean-only", action="store_true", help="Evaluate the deployment metric for candidate selection")
    args = parser.parse_args()
    if args.calibration_samples < 1 or args.threads < 1:
        raise ValueError("calibration count and threads must be positive")
    torch.set_num_threads(args.threads)
    checkpoint = torch.load(args.checkpoint, map_location="cpu", weights_only=True)
    model = VectorConvClassifier()
    model.load_state_dict(checkpoint["model_state"])
    model.eval()
    train = datasets.MNIST(str(args.data_dir), train=True, download=False, transform=transforms.ToTensor())
    if args.split == "validation":
        if not checkpoint.get("validation_indices"):
            raise ValueError("legacy checkpoint has no held-out validation split; select --split test explicitly")
        dataset = Subset(train, checkpoint["validation_indices"])
    else:
        dataset = datasets.MNIST(str(args.data_dir), train=False, download=False, transform=transforms.ToTensor())
    front = (json.loads(args.front_manifest.read_text(encoding="utf-8")) if args.front_manifest
             else checkpoint.get("front_manifest") or prepare_front(model, checkpoint, train, args.calibration_samples))
    if checkpoint.get("front_manifest"):
        for field in ("weights", "biases", "shifts", "relu_enable", "output_scales"):
            if front[field] != checkpoint["front_manifest"][field]:
                raise ValueError("front end differs from configuration used for checkpoint selection")
    weights, biases, _ = quantize_parameters(model)
    if weights.to(torch.int32).tolist() != front["weights"] or biases.tolist() != front["biases"]:
        raise ValueError("front-end manifest does not match checkpoint")
    results = {}
    for condition in (("clean",) if args.clean_only else ("clean", "shift_right_2", "rotate_10", "noise_005")):
        results[condition] = evaluate(model, DataLoader(dataset, batch_size=128), front, condition)
        print(f"{condition}: float={results[condition]['float_accuracy']:.4f} fixed_features={results[condition]['fixed_feature_accuracy']:.4f}", flush=True)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    front_text = json.dumps(front, indent=2) + "\n"
    report = {"checkpoint_sha256": hashlib.sha256(args.checkpoint.read_bytes()).hexdigest(),
              "front_manifest_sha256": hashlib.sha256(front_text.encode()).hexdigest(),
              "validation_indices_sha256": hashlib.sha256(json.dumps(checkpoint.get("validation_indices", [])).encode()).hexdigest(),
              "split": args.split, "torch_version": str(torch.__version__), "results": results,
              "arithmetic": "INT8 convolution; uint8 features; floating-point classifier"}
    (args.output_dir / "evaluation.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    (args.output_dir / "front_manifest.json").write_text(front_text, encoding="utf-8")


if __name__ == "__main__":
    main()
