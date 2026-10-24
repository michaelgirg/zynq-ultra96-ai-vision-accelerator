"""Compile the portable C classifier and compare logits with PyTorch goldens."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import shutil
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def text_hash(path: Path) -> str:
    return hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model-dir", type=Path, default=ROOT / "generated/classifier")
    parser.add_argument("--cc", default=None)
    args = parser.parse_args()
    model_dir = args.model_dir.resolve()
    manifest = json.loads((model_dir / "manifest.json").read_text(encoding="utf-8"))
    if text_hash(model_dir / "vector_classifier_weights.h") != manifest["header_sha256"]:
        raise ValueError("classifier weights header integrity mismatch")
    if text_hash(model_dir / "vector_front_config.h") != manifest["front_config_sha256"]:
        raise ValueError("classifier front-end configuration integrity mismatch")
    if text_hash(model_dir / "vector_front_config.mem") != manifest["front_config_mem_sha256"]:
        raise ValueError("classifier front-end memory configuration integrity mismatch")
    compiler = args.cc or shutil.which("cc") or shutil.which("gcc") or shutil.which("clang") or shutil.which("cl")
    if not compiler:
        raise SystemExit("C compiler required: put cc/gcc/clang on PATH or run from an MSVC developer shell")
    source_dir = ROOT / "software/ultra96"
    with tempfile.TemporaryDirectory(prefix="vector-classifier-") as temporary:
        build = Path(temporary)
        executable = build / "classifier.exe"
        sources = [str(source_dir / name) for name in ("vector_classifier.c", "test_vector_classifier.c")]
        if Path(compiler).stem.lower() == "cl":
            command = [compiler, "/nologo", "/W4", "/WX", "/fp:strict", "/D_CRT_SECURE_NO_WARNINGS",
                       f"/I{source_dir}", f"/I{model_dir}", *sources, f"/Fe:{executable}"]
        else:
            command = [compiler, "-std=c99", "-O2", "-Wall", "-Wextra", "-Werror", "-ffp-contract=off",
                       "-I", str(source_dir), "-I", str(model_dir), *sources, "-o", str(executable)]
        subprocess.run(command, cwd=build, check=True, capture_output=True, text=True)
        maximum_error = 0.0
        for sample in manifest["samples"]:
            path = model_dir / sample["mem"]
            if text_hash(path) != sample["sha256"]:
                raise ValueError(f"golden input integrity mismatch: {sample['name']}")
            fields = subprocess.check_output([str(executable), str(path)], text=True).split()
            if len(fields) != 11 or int(fields[0]) != sample["prediction"]:
                raise AssertionError(f"C prediction mismatch: {sample['name']}")
            for actual_text, expected in zip(fields[1:], sample["logits"]):
                actual = float(actual_text)
                maximum_error = max(maximum_error, abs(actual - expected))
                if not math.isclose(actual, expected, rel_tol=2e-4, abs_tol=2e-4):
                    raise AssertionError(f"C logit mismatch: {sample['name']}: {actual} != {expected}")
        for count in (0, 783, 785):
            path = build / "malformed.mem"
            path.write_text("00000000\n" * count, encoding="ascii")
            result = subprocess.run([str(executable), str(path)], capture_output=True)
            if result.returncode == 0:
                raise AssertionError(f"C harness accepted {count} words")
    print(f"PASS: C/PyTorch classifier parity on {len(manifest['samples'])} cases; max logit error={maximum_error:.6g}; malformed lengths rejected")


if __name__ == "__main__":
    main()
