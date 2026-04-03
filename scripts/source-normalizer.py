#!/usr/bin/env python3
"""Normalize tracked workspace text files using .editorconfig rules."""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

try:
    import editorconfig
    from charset_normalizer import from_bytes
except ImportError as exc:
    raise SystemExit(
        "Missing dependency. Install with: python -m pip install -r requirements-normalizer.txt"
    ) from exc


UTF8_BOM = b"\xef\xbb\xbf"
UTF16LE_BOM = b"\xff\xfe"
UTF16BE_BOM = b"\xfe\xff"

SIMPLE_SUFFIXES = {
    ".bat",
    ".c",
    ".cc",
    ".cmd",
    ".cpp",
    ".cxx",
    ".def",
    ".h",
    ".hh",
    ".hpp",
    ".hxx",
    ".idl",
    ".ini",
    ".inl",
    ".json",
    ".md",
    ".props",
    ".ps1",
    ".py",
    ".rc",
    ".rc2",
    ".sln",
    ".targets",
    ".txt",
    ".vcxproj",
    ".xml",
    ".yaml",
    ".yml",
}
COMPOUND_SUFFIXES = (".vcxproj.filters",)


@dataclass
class FileInspection:
    label: str
    text: str | None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=".", help="Workspace root")
    parser.add_argument("--write", action="store_true", help="Rewrite files in place")
    parser.add_argument("--check", action="store_true", help="Exit non-zero if changes are needed")
    parser.add_argument("--report-encodings", action="store_true", help="Show encoding summary")
    return parser.parse_args()


def matches_target_file(path: Path) -> bool:
    lower_name = path.name.lower()
    if lower_name.endswith(COMPOUND_SUFFIXES):
        return True
    return path.suffix.lower() in SIMPLE_SUFFIXES


def iter_target_files(root: Path) -> list[Path]:
    git = ["git", "-C", str(root), "ls-files", "--cached", "--others", "--exclude-standard"]
    result = subprocess.run(git, capture_output=True, text=True, check=True)
    files: list[Path] = []
    for line in result.stdout.splitlines():
        path = root / line
        if path.is_file() and matches_target_file(path):
            files.append(path)
    return sorted(files)


def inspect_file_bytes(data: bytes) -> FileInspection:
    if not data:
        return FileInspection("empty", "")
    if data.startswith(UTF8_BOM):
        return FileInspection("utf-8-bom", data.decode("utf-8-sig"))
    if data.startswith(UTF16LE_BOM) or data.startswith(UTF16BE_BOM):
        return FileInspection("utf-16", data.decode("utf-16"))
    try:
        return FileInspection("utf-8", data.decode("utf-8"))
    except UnicodeDecodeError:
        result = from_bytes(data).best()
        if result is None or not result.encoding:
            return FileInspection("legacy:undetected", None)
        try:
            decoded = data.decode(result.encoding)
        except (LookupError, UnicodeDecodeError):
            return FileInspection(f"legacy:{result.encoding.lower()}", None)
        return FileInspection(f"legacy:{result.encoding.lower()}", decoded)


def normalize_text(text: str, *, trim_trailing: bool, final_newline: bool, eol: str) -> str:
    normalized = text.replace("\r\n", "\n").replace("\r", "\n")
    if trim_trailing:
        normalized = "\n".join(line.rstrip(" \t") for line in normalized.split("\n"))
    if final_newline:
        normalized = normalized.rstrip("\n") + "\n" if normalized else ""
    else:
        normalized = normalized.rstrip("\n")
    if eol == "crlf":
        return normalized.replace("\n", "\r\n")
    return normalized


def encode_text(text: str, charset: str) -> bytes:
    lowered = charset.lower()
    if lowered == "utf-8":
        return text.encode("utf-8")
    if lowered == "utf-8-bom":
        return UTF8_BOM + text.encode("utf-8")
    if lowered == "utf-16le":
        return UTF16LE_BOM + text.encode("utf-16-le")
    raise ValueError(f"Unsupported target charset '{charset}'")


def main() -> int:
    args = parse_args()
    root = Path(args.root).resolve()
    counters: Counter[str] = Counter()
    changed: list[str] = []

    for path in iter_target_files(root):
        raw = path.read_bytes()
        inspection = inspect_file_bytes(raw)
        counters[inspection.label] += 1
        if inspection.text is None:
            changed.append(f"UNDECODABLE {path.relative_to(root)} [{inspection.label}]")
            continue

        props = editorconfig.get_properties(os.path.abspath(path))
        charset = props.get("charset", "utf-8")
        eol = props.get("end_of_line", "lf")
        trim_trailing = props.get("trim_trailing_whitespace", "false").lower() == "true"
        final_newline = props.get("insert_final_newline", "false").lower() == "true"
        normalized = normalize_text(
            inspection.text,
            trim_trailing=trim_trailing,
            final_newline=final_newline,
            eol=eol,
        )
        encoded = encode_text(normalized, charset)
        rel = str(path.relative_to(root))
        if encoded != raw:
            changed.append(rel)
            if args.write:
                path.write_bytes(encoded)

    if args.report_encodings:
        for key in sorted(counters):
            print(f"{key}: {counters[key]}")

    if changed:
        for entry in changed:
            print(entry)
        if args.check or not args.write:
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
