"""Export a portable ARM float classifier for packed four-filter RTL outputs."""

from __future__ import annotations

import argparse
import hashlib
import json
import random
from pathlib import Path

import torch

from export_vector_conv import fixed_features, integer_accumulators, packed_mem_lines, quantize_parameters, write_header
from vector_conv_model import VectorConvClassifier


ROOT = Path(__file__).resolve().parents[1]


def text_hash(path: Path) -> str:
    return hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest()


def unpack_words(words: list[int]) -> torch.Tensor:
    if len(words) != 784:
        raise ValueError("classifier requires exactly 784 packed words")
    return torch.tensor([[[(word >> (8 * channel)) & 255 for word in words]
                          for channel in range(4)]], dtype=torch.float32).reshape(1, 4, 28, 28)


def render_weights(model: VectorConvClassifier, scales: torch.Tensor) -> str:
    fc1, fc2 = model.classifier[0], model.classifier[2]
    folded = fc1.weight.detach().clone().reshape(64, 4, 196)
    folded *= scales.reshape(1, 4, 1)
    arrays = {"fc1_weights": folded, "fc1_bias": fc1.bias,
              "fc2_weights": fc2.weight, "fc2_bias": fc2.bias}
    lines = ['#pragma once', '#include "vector_classifier.h"', '']
    for name, tensor in arrays.items():
        values = tensor.detach().reshape(-1).tolist()
        lines.append(f"static const float vector_{name}[{len(values)}] = {{")
        for index in range(0, len(values), 8):
            # Nine significant digits round-trip every IEEE-754 float32 value.
            literals = []
            for value in values[index:index + 8]:
                literal = format(value, ".9g")
                if "." not in literal and "e" not in literal:
                    literal += ".0"
                literals.append(literal + "f")
            lines.append("    " + ", ".join(literals) + ",")
        lines.extend(["};", ""])
    lines.extend(["static const vector_classifier_model_t vector_classifier_model = {",
                  "    vector_fc1_weights, vector_fc1_bias, vector_fc2_weights, vector_fc2_bias",
                  "};", ""])
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkpoint", type=Path, default=Path("generated/model/vector_conv4_cnn.pt"))
    parser.add_argument("--front-manifest", type=Path, default=Path("generated/test_vectors/vector_conv4_manifest.json"))
    parser.add_argument("--output-dir", type=Path, default=Path("generated/classifier"))
    parser.add_argument("--input-vector-dir", type=Path, default=Path("generated/test_vectors"))
    args = parser.parse_args()
    torch.set_num_threads(2)
    checkpoint = torch.load(args.checkpoint, map_location="cpu", weights_only=True)
    model = VectorConvClassifier()
    model.load_state_dict(checkpoint["model_state"])
    model.eval()
    manifest = json.loads(args.front_manifest.read_text(encoding="utf-8"))
    weights, biases, weight_scales = quantize_parameters(model)
    if weights.to(torch.int32).tolist() != manifest["weights"] or biases.tolist() != manifest["biases"]:
        raise ValueError("checkpoint and front-end manifest have different convolution parameters")
    scales = torch.tensor(manifest["output_scales"], dtype=torch.float32)
    if scales.shape != (4,) or not torch.isfinite(scales).all() or not (scales > 0).all():
        raise ValueError("front-end scales must be four finite positive values")
    shifts = torch.tensor(manifest["shifts"], dtype=torch.int64)
    expected_scales = weight_scales * torch.pow(2.0, shifts.float()) / 255.0
    if shifts.shape != (4,) or (shifts < 0).any() or (shifts > 31).any():
        raise ValueError("front-end shifts must be four values in 0..31")
    if manifest["relu_enable"] != [1, 1, 1, 1] or not torch.allclose(scales, expected_scales, rtol=1e-6, atol=0):
        raise ValueError("front-end activation/scaling contract does not match classifier")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    header = args.output_dir / "vector_classifier_weights.h"
    header.write_text(render_weights(model, scales), encoding="utf-8")
    write_header(args.output_dir / "vector_front_config.h", weights, biases, shifts, scales)
    config_words = []
    for channel in range(4):
        config_words.extend(int(value) & 0xFFFFFFFF for value in weights[channel].reshape(-1).tolist())
        config_words.extend([int(biases[channel]) & 0xFFFFFFFF, 0x100 | int(shifts[channel])])
    config_mem = args.output_dir / "vector_front_config.mem"
    config_mem.write_text("".join(f"{word:08X}\n" for word in config_words), encoding="ascii")
    cases = []
    if "samples" in manifest:
        for sample in manifest["samples"]:
            path = ROOT / sample["conv4_mem"].replace("\\", "/")
            cases.append((sample["name"], [int(line, 16) for line in path.read_text().splitlines() if line.strip()]))
    else:
        paths = sorted(args.input_vector_dir.glob("sample_*_input.mem"))
        if not paths:
            raise ValueError("no input vectors available for candidate export")
        for path in paths:
            pixels = [int(line, 16) for line in path.read_text().splitlines() if line.strip()]
            if len(pixels) != 784 or any(not 0 <= value <= 255 for value in pixels):
                raise ValueError("invalid candidate input image")
            image = torch.tensor(pixels, dtype=torch.uint8).reshape(1, 1, 28, 28)
            features = fixed_features(integer_accumulators(image, weights, biases), shifts)[0]
            cases.append((path.name.replace("_input.mem", ""), [int(word, 16) for word in packed_mem_lines(features)]))
    cases.extend([("zeros", [0] * 784), ("saturated", [0xFFFFFFFF] * 784)])
    # Distinct channels and spatial maxima expose NHWC/NCHW and pooling mistakes.
    cases.append(("channel_order", [sum(((i * (c + 1) + c * 31) % 256) << (8 * c)
                                      for c in range(4)) for i in range(784)]))
    rng = random.Random(2026)
    cases.extend((f"random_{i:03}", [rng.getrandbits(32) for _ in range(784)]) for i in range(16))
    golden = []
    with torch.inference_mode():
        for name, words in cases:
            logits = model.classify_features(unpack_words(words) * scales.reshape(1, 4, 1, 1))[0]
            path = args.output_dir / f"{name}.mem"
            path.write_text("".join(f"{word:08X}\n" for word in words), encoding="ascii")
            golden.append({"name": name, "mem": path.name, "logits": logits.tolist(),
                           "prediction": int(logits.argmax()), "sha256": text_hash(path)})
    metadata = {"checkpoint_sha256": hashlib.sha256(args.checkpoint.read_bytes()).hexdigest(),
                "front_manifest_sha256": text_hash(args.front_manifest),
                "header_sha256": text_hash(header),
                "front_config_sha256": text_hash(args.output_dir / "vector_front_config.h"),
                "front_config_mem_sha256": text_hash(config_mem),
                "arithmetic": "uint8 max pooling; float32 classifier; channel scales folded into fc1",
                "samples": golden}
    (args.output_dir / "manifest.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    print(f"Exported classifier and {len(golden)} PyTorch golden cases to {args.output_dir}")


if __name__ == "__main__":
    main()
