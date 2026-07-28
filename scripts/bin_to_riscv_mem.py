"""Pack a little-endian RV32 binary into slow_line_memory hex lines."""

from __future__ import annotations

import argparse
from pathlib import Path


def pack_lines(data: bytes, offset_bytes: int, line_bytes: int = 16) -> list[str]:
    if offset_bytes < 0 or offset_bytes % line_bytes:
        raise ValueError(f"offset must be a nonnegative multiple of {line_bytes} bytes")
    image = bytearray(offset_bytes)
    image.extend(data)
    if len(image) % line_bytes:
        image.extend(b"\x00" * (line_bytes - len(image) % line_bytes))
    return [
        image[index : index + line_bytes][::-1].hex()
        for index in range(0, len(image), line_bytes)
    ]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--offset-bytes", type=lambda value: int(value, 0), default=0)
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    lines = pack_lines(args.input.read_bytes(), args.offset_bytes)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("\n".join(lines) + ("\n" if lines else ""), encoding="ascii")


if __name__ == "__main__":
    main()
