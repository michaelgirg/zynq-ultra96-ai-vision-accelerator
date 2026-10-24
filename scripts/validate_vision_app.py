"""Build/run the host application with functional DMA/cache and optional RTL capture replay."""
from __future__ import annotations

import argparse
import csv
from contextlib import nullcontext
import hashlib
import io
import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def compile_app(build: Path, model: Path, main: str, compiler: str, sanitize: bool = False) -> Path:
    source = ROOT / "software/ultra96"
    exe = build / (Path(main).stem + ".exe")
    files = [source / name for name in ("vision_runtime.c", "vision_sim.c",
        "vision_benchmark.c", "vector_front_reference.c", "vector_classifier.c", main)]
    includes = [source, model, ROOT / "software/riscv/include", ROOT / "software/riscv/build"]
    model_sha = json.loads((model / "manifest.json").read_text())["checkpoint_sha256"]
    if Path(compiler).stem.lower() == "cl":
        if sanitize:
            raise ValueError("sanitizer lane requires GCC or Clang")
        command = [compiler, "/nologo", "/O2", "/W4", "/WX", "/fp:strict", "/D_CRT_SECURE_NO_WARNINGS"]
        command += [f"/DVISION_MODEL_SHA256={model_sha}"]
        command += [f"/I{p}" for p in includes] + [str(p) for p in files] + [f"/Fe:{exe}"]
    else:
        command = [compiler, "-std=c99", "-O2", "-Wall", "-Wextra", "-Werror", "-ffp-contract=off"]
        command += [f"-DVISION_MODEL_SHA256={model_sha}"]
        if sanitize:
            command += ["-fsanitize=address,undefined", "-fno-omit-frame-pointer", "-g"]
        for path in includes:
            command += ["-I", str(path)]
        command += [str(p) for p in files] + ["-o", str(exe)]
    result = subprocess.run(command, cwd=build, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
    return exe


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cc")
    parser.add_argument("--sanitize", action="store_true")
    parser.add_argument("--keep-build", action="store_true")
    parser.add_argument("--capture-root", type=Path)
    parser.add_argument("--output", type=Path, default=ROOT / "generated/experiments/vision-app.json")
    args = parser.parse_args()
    cc = args.cc or shutil.which("cc") or shutil.which("gcc") or shutil.which("clang") or shutil.which("cl")
    if not cc:
        raise SystemExit("Native C compiler required; use --cc cl from an MSVC shell")
    if not (ROOT / "software/riscv/build/controller_images.h").exists():
        raise SystemExit("Build RV32 firmware first (scripts/build_riscv_firmware.ps1 or make -C software/riscv)")
    frames = 0
    csv_rows = []
    model_results = []
    for name, directory in (("baseline", "generated/classifier"),
                            ("candidate", "generated/candidates/vector_conv4/classifier")):
        model = ROOT / directory
        manifest = json.loads((model / "manifest.json").read_text())
        samples = {s["name"]: s for s in manifest["samples"]}
        retained = ROOT / f"generated/experiments/vision-app-build/{name}"
        if args.keep_build:
            retained.mkdir(parents=True, exist_ok=True)
        context = nullcontext(str(retained)) if args.keep_build else tempfile.TemporaryDirectory(prefix="vision-app-")
        with context as temp:
            build = Path(temp)
            tests = compile_app(build, model, "test_vision_runtime.c", cc, args.sanitize)
            test_output = subprocess.check_output([str(tests)], text=True)
            print(test_output, end="")
            unit_checks = re.search(r"runtime (\d+) checks", test_output)
            if not unit_checks:
                raise AssertionError("missing runtime unit-test success marker")
            demo = compile_app(build, model, "vision_demo_native.c", cc, args.sanitize)
            for index in range(8):
                sample = f"sample_{index:03}"
                command = [str(demo), str(ROOT / f"generated/test_vectors/{sample}_input.mem"),
                           str(model / f"{sample}.mem"), "2"]
                if args.capture_root:
                    command += [str(args.capture_root / f"{name}_{sample}.mem")]
                result = subprocess.run(command, check=True, capture_output=True, text=True)
                rows = list(csv.DictReader(io.StringIO(result.stdout)))
                if len(rows) != 9:
                    raise AssertionError("expected one warmup plus two measurements for each of three paths")
                for row in rows:
                    if row["measurement_domain"] != "host-functional-model" or int(row["result"]):
                        raise AssertionError("native backend misrepresented a board result")
                    if int(row["prediction"]) != samples[sample]["prediction"]:
                        raise AssertionError(f"application prediction mismatch: {name} {sample}")
                    if int(row["tick_hz"]) <= 0 or row["accel_cycles"] != "0":
                        raise AssertionError("invalid timer or fabricated hardware cycles")
                    if row["model_sha256"] != manifest["checkpoint_sha256"]:
                        raise AssertionError("unbound model identity in benchmark")
                    row.update(model=name, sample=sample)
                csv_rows += rows
                frames += 6  # two control paths x (one warmup + two measurements)
            for malformed in ("0", "-1", "1001", "2junk"):
                command[3] = malformed
                if subprocess.run(command, capture_output=True).returncode == 0:
                    raise AssertionError("demo accepted malformed repeat count")
        print(f"PASS: {name}: application boot/model/cache/DMA/prediction and software-reference parity")
        model_results.append({"model": name, "checkpoint_sha256": manifest["checkpoint_sha256"],
                              "runtime_checks": int(unit_checks.group(1)), "images": 8})
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps({"backend": "native-functional-model", "physical_hardware": False,
        "rv32_firmware_execution": False, "rtl_capture_replay": bool(args.capture_root),
        "dma_frames": frames, "benchmark_rows": len(csv_rows), "sanitizers": args.sanitize,
        "speedup_claimed": False, "models": model_results,
        "source_sha256_lf": {str(p.relative_to(ROOT)).replace("\\", "/"):
            hashlib.sha256(p.read_bytes().replace(b"\r\n", b"\n")).hexdigest()
            for p in sorted(list((ROOT / "software/ultra96").glob("*.c")) +
                            list((ROOT / "software/ultra96").glob("*.h")))}}, indent=2) + "\n")
    with args.output.with_suffix(".csv").open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(csv_rows[0]))
        writer.writeheader(); writer.writerows(csv_rows)


if __name__ == "__main__":
    main()
