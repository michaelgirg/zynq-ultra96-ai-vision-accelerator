"""Portable repository-integrity checks for CI and local review."""

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TEXT_SUFFIXES = {
    ".S", ".c", ".f", ".h", ".json", ".ld", ".md", ".ps1", ".py",
    ".sh", ".sv", ".tcl", ".yml", ".yaml",
}
LINE_ORIENTED_HASH_SUFFIXES = {".h", ".mem"}
HASH_MANIFEST = ROOT / "generated" / "test_vectors" / "manifest.json"
VECTOR_MANIFEST = ROOT / "generated" / "test_vectors" / "vector_conv4_manifest.json"
REGISTER_DOC = ROOT / "docs" / "register_map.md"
REGISTER_RTL = ROOT / "rtl" / "axis_preprocess_vector_axi_lite.sv"
SOC_MAP = ROOT / "config" / "soc_address_map.json"
SOC_MAP_RTL = ROOT / "rtl" / "riscv" / "soc" / "soc_address_map_pkg.sv"
SOC_MAP_HEADER = ROOT / "software" / "riscv" / "include" / "soc_address_map.h"
SOC_MAP_TCL = ROOT / "vivado" / "scripts" / "create_ultra96_v1_production_v2_project.tcl"
REGISTER_HEADER = ROOT / "software" / "riscv" / "include" / "vision_accel_regs.h"
MAILBOX_RTL = ROOT / "rtl" / "riscv" / "soc" / "rv32_job_mailbox.sv"
MAILBOX_HEADER = ROOT / "software" / "riscv" / "include" / "job_mailbox.h"
PIXELS_PER_FRAME = 28 * 28


def repository_path(value: str) -> Path:
    path = (ROOT / value.replace("\\", "/")).resolve()
    if ROOT not in path.parents and path != ROOT:
        raise ValueError(f"path escapes repository: {value}")
    return path


def sha256(path: Path) -> str:
    data = path.read_bytes()
    if path.suffix in LINE_ORIENTED_HASH_SUFFIXES:
        # The checked-in manifest predates Linux CI and records CRLF byte
        # hashes. Canonicalize line-oriented artifacts so a checkout's EOL
        # policy cannot create a false integrity failure.
        data = data.replace(b"\r\n", b"\n").replace(b"\r", b"\n").replace(b"\n", b"\r\n")
    return hashlib.sha256(data).hexdigest()


def check_text_hygiene(errors: list[str]) -> None:
    for path in ROOT.rglob("*"):
        if (
            not path.is_file()
            or ".git" in path.parts
            or "generated" in path.parts
            or path.suffix not in TEXT_SUFFIXES
        ):
            continue
        text = path.read_text(encoding="utf-8")
        if text and not text.endswith("\n"):
            errors.append(f"{path.relative_to(ROOT)}: missing final newline")
        for line_number, line in enumerate(text.splitlines(), start=1):
            if line.endswith((" ", "\t")):
                errors.append(f"{path.relative_to(ROOT)}:{line_number}: trailing whitespace")


def check_hashed_vectors(errors: list[str]) -> None:
    manifest = json.loads(HASH_MANIFEST.read_text(encoding="utf-8"))
    for sample in manifest["samples"]:
        for key, expected_hash in sample["sha256"].items():
            path = repository_path(sample[key])
            if not path.is_file():
                errors.append(f"{sample['name']}: missing {key}: {path.relative_to(ROOT)}")
            elif sha256(path) != expected_hash:
                errors.append(f"{sample['name']}: SHA256 mismatch for {key}")


def mem_word_count(path: Path) -> int:
    return sum(1 for line in path.read_text(encoding="utf-8").splitlines() if line.strip())


def check_vector_manifest(errors: list[str]) -> None:
    manifest = json.loads(VECTOR_MANIFEST.read_text(encoding="utf-8"))
    if manifest["filters"] != 4 or len(manifest["weights"]) != 4:
        errors.append("vector manifest must describe four filters")
    if any(len(kernel) != 3 or any(len(row) != 3 for row in kernel) for kernel in manifest["weights"]):
        errors.append("vector manifest kernels must all be 3x3")
    for sample in manifest["samples"]:
        for key in ("input_mem", "conv4_mem"):
            path = repository_path(sample[key])
            if not path.is_file():
                errors.append(f"{sample['name']}: missing {key}: {path.relative_to(ROOT)}")
            elif mem_word_count(path) != PIXELS_PER_FRAME:
                errors.append(f"{sample['name']}: {key} must contain {PIXELS_PER_FRAME} words")


def check_register_map(errors: list[str]) -> None:
    rtl = REGISTER_RTL.read_text(encoding="utf-8")
    rtl_offsets = {
        name: int(value, 16)
        for name, value in re.findall(r"ADDR_([A-Z0-9_]+)\s*=\s*8'h([0-9a-fA-F]+)", rtl)
    }
    doc = REGISTER_DOC.read_text(encoding="utf-8")
    documented = re.findall(r"^\|\s*`(0x[0-9A-Fa-f]+)`\s*\|\s*`([A-Z0-9_]+)`", doc, re.MULTILINE)
    for address, name in documented:
        if name not in rtl_offsets:
            errors.append(f"register map lists {name}, absent from RTL constants")
        elif rtl_offsets[name] != int(address, 16):
            errors.append(f"register map offset mismatch for {name}: doc={address}, rtl=0x{rtl_offsets[name]:02X}")

    header = REGISTER_HEADER.read_text(encoding="utf-8")
    header_offsets = {
        name: int(value, 16)
        for name, value in re.findall(
            r"#define\s+VISION_REG_([A-Z0-9_]+)\s+0x([0-9a-fA-F]+)u", header
        )
    }
    for name, value in header_offsets.items():
        if name not in rtl_offsets:
            errors.append(f"RV32 accelerator header lists {name}, absent from RTL constants")
        elif rtl_offsets[name] != value:
            errors.append(
                f"RV32 accelerator header mismatch for {name}: "
                f"header=0x{value:03X}, rtl=0x{rtl_offsets[name]:03X}"
            )


def check_soc_address_map(errors: list[str]) -> None:
    regions = json.loads(SOC_MAP.read_text(encoding="utf-8"))["regions"]
    rtl = SOC_MAP_RTL.read_text(encoding="utf-8")
    rtl_values = {
        name: int(value.replace("_", ""), 16)
        for name, value in re.findall(
            r"localparam\s+logic\s+\[31:0\]\s+([A-Z0-9_]+)\s*=\s*32'h([0-9a-fA-F_]+)",
            rtl,
        )
    }
    header = SOC_MAP_HEADER.read_text(encoding="utf-8")
    header_values = {
        name: int(value, 16)
        for name, value in re.findall(
            r"#define\s+SOC_([A-Z0-9_]+)\s+0x([0-9a-fA-F]+)u", header
        )
    }
    tcl = SOC_MAP_TCL.read_text(encoding="utf-8")
    tcl_regions = {
        interface: (int(base, 16), int(size, 16))
        for interface, base, size in re.findall(
            r'"([A-Za-z0-9_/]+)"\s+\[list\s+'
            r'(0x[0-9a-fA-F]+)\s+(0x[0-9a-fA-F]+)\s+'
            r'(?:arm-rv32|arm-only)\]',
            tcl,
        )
    }
    tcl_region_names = {
        "VISION_ACCEL": "pre/S_AXI",
        "AXI_DMA": "dma/S_AXI_LITE",
        "MAILBOX": "mailbox/S_AXI",
        "HOST_IMEM": "rv32/S_AXI_IMEM",
        "HOST_DMEM": "rv32/S_AXI_DMEM",
    }

    occupied: list[tuple[int, int, str]] = []
    for name, region in regions.items():
        base = int(region["base"], 16)
        size = int(region["size"], 16)
        if size <= 0 or size & (size - 1):
            errors.append(f"SoC region {name} size must be a positive power of two")
        for suffix, expected in (("BASE", base), ("SIZE", size)):
            constant = f"{name}_{suffix}"
            if constant not in rtl_values:
                errors.append(f"SoC map RTL is missing {constant}")
            elif rtl_values[constant] != expected:
                errors.append(
                    f"SoC map mismatch for {constant}: "
                    f"json=0x{expected:08X}, rtl=0x{rtl_values[constant]:08X}"
                )
            if constant not in header_values:
                errors.append(f"SoC map firmware header is missing {constant}")
            elif header_values[constant] != expected:
                errors.append(
                    f"SoC firmware map mismatch for {constant}: "
                    f"json=0x{expected:08X}, header=0x{header_values[constant]:08X}"
                )
        occupied.append((base, base + size, name))
        if name in tcl_region_names:
            interface = tcl_region_names[name]
            if interface not in tcl_regions:
                errors.append(f"Vivado map is missing {interface} for {name}")
            elif tcl_regions[interface] != (base, size):
                tcl_base, tcl_size = tcl_regions[interface]
                errors.append(
                    f"Vivado map mismatch for {name}: "
                    f"json=0x{base:08X}/0x{size:X}, "
                    f"tcl=0x{tcl_base:08X}/0x{tcl_size:X}"
                )

    occupied.sort()
    for (_, previous_end, previous_name), (base, _, name) in zip(occupied, occupied[1:]):
        if base < previous_end:
            errors.append(f"SoC regions overlap: {previous_name} and {name}")


def check_mailbox_map(errors: list[str]) -> None:
    rtl = MAILBOX_RTL.read_text(encoding="utf-8")
    rtl_offsets = {
        name: int(value, 16)
        for name, value in re.findall(
            r"localparam\s+logic\s+\[11:0\]\s+ADDR_([A-Z0-9_]+)\s*=\s*12'h([0-9a-fA-F]+)",
            rtl,
        )
    }
    header = MAILBOX_HEADER.read_text(encoding="utf-8")
    header_offsets = {
        name: int(value, 16)
        for name, value in re.findall(
            r"#define\s+MAILBOX_REG_([A-Z0-9_]+)\s+0x([0-9a-fA-F]+)u", header
        )
    }
    for name, value in header_offsets.items():
        rtl_name = "MAILBOX_ID" if name == "ID" else name
        if rtl_name not in rtl_offsets:
            errors.append(f"mailbox firmware header lists {name}, absent from RTL constants")
        elif rtl_offsets[rtl_name] != value:
            errors.append(
                f"mailbox header mismatch for {name}: "
                f"header=0x{value:03X}, rtl=0x{rtl_offsets[rtl_name]:03X}"
            )


def check_riscv_mem_packing(errors: list[str]) -> None:
    from bin_to_riscv_mem import pack_lines

    expected = "00000000000000000000000004030201"
    if pack_lines(bytes((1, 2, 3, 4)), 0) != [expected]:
        errors.append("RV32 memory packer changed little-endian word/line ordering")
    if pack_lines(bytes((1, 2, 3, 4)), 16) != ["0" * 32, expected]:
        errors.append("RV32 memory packer changed section-offset handling")


def main() -> None:
    errors: list[str] = []
    check_text_hygiene(errors)
    check_hashed_vectors(errors)
    check_vector_manifest(errors)
    check_register_map(errors)
    check_soc_address_map(errors)
    check_mailbox_map(errors)
    check_riscv_mem_packing(errors)
    if errors:
        raise SystemExit("Repository consistency failed:\n- " + "\n- ".join(errors))
    print("Repository consistency checks passed")


if __name__ == "__main__":
    main()
