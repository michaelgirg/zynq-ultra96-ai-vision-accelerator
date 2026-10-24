"""Train the hardware-matched CNN with a held-out validation split."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import random
from pathlib import Path

import torch
from torch import nn
from torch.utils.data import DataLoader, Subset
from torchvision import datasets, transforms

from vector_conv_model import VECTOR_FILTERS, VectorConvClassifier


def split_indices(count: int, validation_size: int, seed: int) -> tuple[list[int], list[int]]:
    if not 0 < validation_size < count:
        raise ValueError("validation size must be between zero and dataset size")
    indices = torch.randperm(count, generator=torch.Generator().manual_seed(seed)).tolist()
    return indices[validation_size:], indices[:validation_size]


def evaluate(model: nn.Module, loader: DataLoader, device: torch.device) -> dict:
    model.eval()
    confusion = torch.zeros((10, 10), dtype=torch.int64)
    loss_sum = 0.0
    with torch.inference_mode():
        for images, labels in loader:
            logits = model(images.to(device))
            loss_sum += nn.functional.cross_entropy(logits, labels.to(device), reduction="sum").item()
            predictions = logits.argmax(dim=1).cpu()
            confusion += torch.bincount(labels * 10 + predictions, minlength=100).reshape(10, 10)
    total = int(confusion.sum())
    return {
        "samples": total,
        "accuracy": float(confusion.diag().sum()) / max(total, 1),
        "loss": loss_sum / max(total, 1),
        "confusion_matrix": confusion.tolist(),
        "per_class_accuracy": (confusion.diag() / confusion.sum(1).clamp(min=1)).tolist(),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-dir", type=Path, default=Path("generated/data"))
    parser.add_argument("--output-dir", type=Path, default=Path("generated/experiments/vector_conv4"))
    parser.add_argument("--epochs", type=int, default=20)
    parser.add_argument("--batch-size", type=int, default=128)
    parser.add_argument("--lr", type=float, default=1e-3)
    parser.add_argument("--weight-decay", type=float, default=1e-4)
    parser.add_argument("--seed", type=int, default=17)
    parser.add_argument("--split-seed", type=int, default=2026)
    parser.add_argument("--validation-size", type=int, default=5000)
    parser.add_argument("--rotation", type=float, default=10.0)
    parser.add_argument("--translation", type=float, default=0.08)
    parser.add_argument("--device", choices=("auto", "cpu", "cuda"), default="auto")
    parser.add_argument("--threads", type=int, default=4)
    parser.add_argument("--download", action="store_true")
    parser.add_argument("--evaluate-test", action="store_true", help="Evaluate the selected checkpoint once; never used for selection")
    parser.add_argument("--overwrite", action="store_true")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if args.epochs < 1 or args.batch_size < 1 or args.threads < 1 or args.lr <= 0:
        raise ValueError("epochs, batch size, threads, and learning rate must be positive")
    if not 0 <= args.rotation <= 30 or not 0 <= args.translation <= 0.25 or args.weight_decay < 0:
        raise ValueError("augmentation or weight decay is outside the supported range")
    checkpoint_path = args.output_dir / "vector_conv4_cnn.pt"
    if checkpoint_path.exists() and not args.overwrite:
        raise FileExistsError(f"refusing to overwrite {checkpoint_path}; use a new output directory")
    random.seed(args.seed)
    os.environ.setdefault("CUBLAS_WORKSPACE_CONFIG", ":4096:8")
    torch.manual_seed(args.seed)
    torch.set_num_threads(args.threads)
    torch.use_deterministic_algorithms(True)
    device = torch.device(("cuda" if torch.cuda.is_available() else "cpu") if args.device == "auto" else args.device)
    clean = transforms.ToTensor()
    augment = transforms.Compose([
        transforms.RandomAffine(args.rotation, translate=(args.translation, args.translation)),
        transforms.ToTensor(),
    ])
    training_set = datasets.MNIST(str(args.data_dir), train=True, download=args.download, transform=augment)
    validation_set = datasets.MNIST(str(args.data_dir), train=True, download=False, transform=clean)
    train_indices, validation_indices = split_indices(len(training_set), args.validation_size, args.split_seed)
    training_loader = DataLoader(Subset(training_set, train_indices), batch_size=args.batch_size,
                                 shuffle=True, generator=torch.Generator().manual_seed(args.seed))
    validation_loader = DataLoader(Subset(validation_set, validation_indices), batch_size=args.batch_size)
    model = VectorConvClassifier().to(device)
    optimizer = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=args.weight_decay)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=args.epochs)
    criterion = nn.CrossEntropyLoss()
    best_key = (-1.0, float("-inf"))
    best_state = None
    best_epoch = 0
    history = []
    for epoch in range(1, args.epochs + 1):
        model.train()
        loss_sum = 0.0
        for images, labels in training_loader:
            optimizer.zero_grad(set_to_none=True)
            loss = criterion(model(images.to(device)), labels.to(device))
            loss.backward()
            optimizer.step()
            loss_sum += loss.item() * labels.numel()
        validation = evaluate(model, validation_loader, device)
        history.append({"epoch": epoch, "train_loss": loss_sum / len(train_indices),
                        "validation_accuracy": validation["accuracy"], "validation_loss": validation["loss"],
                        "learning_rate": optimizer.param_groups[0]["lr"]})
        key = (validation["accuracy"], -validation["loss"])
        if key > best_key:
            best_key, best_epoch = key, epoch
            best_state = {name: value.detach().cpu().clone() for name, value in model.state_dict().items()}
        scheduler.step()
        print(f"epoch={epoch} train_loss={history[-1]['train_loss']:.4f} validation_accuracy={validation['accuracy']:.4f}", flush=True)
    model.load_state_dict(best_state)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    split_digest = hashlib.sha256(json.dumps(validation_indices).encode()).hexdigest()
    checkpoint = {
        "model_state": best_state, "filters": VECTOR_FILTERS, "image_shape": [28, 28],
        "epochs": args.epochs, "selected_epoch": best_epoch, "seed": args.seed,
        "split_seed": args.split_seed, "validation_indices": validation_indices,
        "selection": "highest validation accuracy, then lowest validation loss",
    }
    torch.save(checkpoint, checkpoint_path)
    metrics = {
        "checkpoint": checkpoint_path.name, "filters": VECTOR_FILTERS, "seed": args.seed,
        "torch_version": str(torch.__version__), "device": device.type, "selected_epoch": best_epoch,
        "training_samples": len(train_indices), "validation_samples": len(validation_indices),
        "epochs": args.epochs, "batch_size": args.batch_size,
        "optimizer": {"name": "AdamW", "learning_rate": args.lr, "weight_decay": args.weight_decay},
        "scheduler": "CosineAnnealingLR over all epochs",
        "split_seed": args.split_seed, "validation_indices_sha256": split_digest,
        "augmentation": {"rotation_degrees": args.rotation, "translation_fraction": args.translation},
        "selection": checkpoint["selection"], "history": history,
        "validation": evaluate(model, validation_loader, device),
    }
    if args.evaluate_test:
        test_set = datasets.MNIST(str(args.data_dir), train=False, download=args.download, transform=clean)
        metrics["test"] = evaluate(model, DataLoader(test_set, batch_size=args.batch_size), device)
    metrics["checkpoint_sha256"] = hashlib.sha256(checkpoint_path.read_bytes()).hexdigest()
    (args.output_dir / "metrics_vector_conv4.json").write_text(json.dumps(metrics, indent=2) + "\n", encoding="utf-8")
    print(f"selected_epoch={best_epoch} validation_accuracy={best_key[0]:.4f}; saved {checkpoint_path}", flush=True)


if __name__ == "__main__":
    main()
