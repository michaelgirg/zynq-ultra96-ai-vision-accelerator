"""Compile and execute the portable ARM boot-helper contract on the host."""
from __future__ import annotations

import argparse
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cc")
    args = parser.parse_args()
    cc = args.cc or shutil.which("cc") or shutil.which("gcc") or shutil.which("clang") or shutil.which("cl")
    if not cc:
        raise SystemExit("C compiler required (or run from an MSVC developer shell)")
    source = ROOT / "software/ultra96"
    with tempfile.TemporaryDirectory(prefix="rv32-boot-") as temp:
        exe = Path(temp) / "boot_test.exe"
        files = [str(source / name) for name in ("rv32_controller.c", "test_rv32_controller.c")]
        if Path(cc).stem.lower() == "cl":
            command = [cc, "/nologo", "/O2", "/W4", "/WX", f"/I{source}", *files, f"/Fe:{exe}"]
        else:
            command = [cc, "-std=c99", "-O2", "-Wall", "-Wextra", "-Werror", "-I", str(source), *files, "-o", str(exe)]
        subprocess.run(command, cwd=temp, check=True)
        subprocess.run([str(exe)], check=True)


if __name__ == "__main__":
    main()
