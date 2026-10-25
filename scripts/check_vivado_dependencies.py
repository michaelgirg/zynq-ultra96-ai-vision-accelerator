"""Check portable Vivado source/constraint/script inputs without running Vivado."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
JOIN = re.compile(r'\[file\s+join\s+\$(script_dir|v2_script_dir|repo_root|v2_repo_root)\s+"([^"$]+\.(?:tcl|sv|xdc))"\]')
ENTRY = re.compile(r'(?:Invoke-VivadoStage|Invoke-VivadoScript)\s+"([^"]+\.tcl)"')


def check(root: Path = ROOT) -> list[str]:
    errors = []
    scripts = root / "vivado/scripts"
    for source in sorted(scripts.glob("*.tcl")):
        for variable, relative in JOIN.findall(source.read_text(encoding="utf-8")):
            base = source.parent if variable.endswith("script_dir") else root
            target = (base / relative).resolve()
            if not target.is_relative_to(root.resolve()) or not target.is_file():
                errors.append(f"{source.relative_to(root)}: missing/out-of-repository input {relative}")
    for source in sorted((root / "scripts").glob("run_ultra96*.ps1")):
        for relative in ENTRY.findall(source.read_text(encoding="utf-8")):
            if not (scripts / relative).is_file():
                errors.append(f"{source.relative_to(root)}: missing entry script {relative}")
    return errors


if __name__ == "__main__":
    failures = check()
    if failures:
        raise SystemExit("Vivado dependency check failed:\n- " + "\n- ".join(failures))
    print("PASS: Vivado Tcl sources, RTL/constraint inputs and PowerShell entry scripts exist")
