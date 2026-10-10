#!/usr/bin/env python3
"""Checks the English interface: every t("…") text in the app's sources needs an entry in
Core/English.swift, with the same number of %@ values, and Russian text outside t() is only
allowed on lines marked `// l10n: own names` (languages under their own names). Prints what is
missing and exits 1.

usage: tools/l10n-check.py            from the repository
       tools/l10n-check.py --missing  only the missing Russian texts, one JSON string per line
"""
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from swiftstrings import CYR, key_of, literals, wrapped  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "app/Sources/ExeRunner"
ENGLISH = SOURCES / "Core/English.swift"


def holes(text: str) -> int:
    return len(re.findall(r"%@|%\d\$@", text))


def main() -> None:
    keys: dict[str, str] = {}
    unwrapped: list[str] = []
    for path in sorted(SOURCES.rglob("*.swift")):
        if path.name in ("English.swift", "Localization.swift"):
            continue
        src = path.read_text(encoding="utf-8")
        for start, end, _ in literals(src):
            literal = src[start:end]
            if wrapped(src, start):
                keys.setdefault(key_of(literal), f"{path.relative_to(ROOT)}:{src.count(chr(10), 0, start) + 1}")
            elif CYR.search(literal) and "// l10n: own names" not in src[start:src.find(chr(10), start)]:
                # languages listed under their own names stay as they are
                unwrapped.append(f"{path.relative_to(ROOT)}:{src.count(chr(10), 0, start) + 1}: {literal[:70]}")

    english = ENGLISH.read_text(encoding="utf-8")
    table: dict[str, str] = {}
    for line in english.splitlines():
        spans = literals(line)
        if len(spans) == 2 and line.strip().startswith('"'):
            table[key_of(line[spans[0][0]:spans[0][1]])] = key_of(line[spans[1][0]:spans[1][1]])

    # a text that reads the same in both languages needs no entry
    missing = [k for k in keys if k not in table and CYR.search(k)]
    differ = [k for k in keys if k in table and holes(k) != holes(table[k])]
    if "--missing" in sys.argv:
        for k in missing:
            print(json.dumps(k, ensure_ascii=False))
        return
    for line in unwrapped:
        print("Russian text outside t():", line)
    for k in missing:
        print(f"no English for {json.dumps(k, ensure_ascii=False)} ({keys[k]})")
    for k in differ:
        print(f"other number of values in English for {json.dumps(k, ensure_ascii=False)}")
    print(f"l10n: {len(keys)} texts, {len(missing)} without English, {len(differ)} with other values, "
          f"{len(unwrapped)} outside t()")
    sys.exit(1 if missing or differ or unwrapped else 0)


if __name__ == "__main__":
    main()
