#!/usr/bin/env python3
"""Verifies that every Localizable.strings file has the same key set.

Missing keys silently fall back to the English key, so a mismatch is easy to
ship unnoticed. Run via `make check-l10n` after touching any .strings file.
"""

import collections
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
KEY_PATTERN = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"')


def keys_in(path):
    keys = []
    for line in path.read_text(encoding="utf-8").splitlines():
        match = KEY_PATTERN.match(line)
        if match:
            keys.append(match.group(1))
    return keys


def main():
    files = {}
    for path in sorted(ROOT.glob("Sources/*/Resources/*/Localizable.strings")):
        language = path.parent.stem
        if language.lower() in files:
            print(f"error: duplicate {language} strings file: {path}", file=sys.stderr)
            return 1
        files[language.lower()] = (language, path)

    if len(files) < 2:
        print("error: expected at least two Localizable.strings files", file=sys.stderr)
        return 1

    parsed = {}
    failed = False
    for language, path in files.values():
        keys = keys_in(path)
        parsed[language] = set(keys)
        print(f"{language}: {len(parsed[language])} keys in {path.relative_to(ROOT)}")
        duplicates = [key for key, count in collections.Counter(keys).items() if count > 1]
        if duplicates:
            failed = True
            print(f"  duplicate keys: {', '.join(sorted(duplicates))}")

    for language in sorted(parsed):
        for other in sorted(set(parsed) - {language}):
            missing = parsed[other] - parsed[language]
            if missing:
                failed = True
                print(f"  missing in {language} (present in {other}): {', '.join(sorted(missing))}")

    if failed:
        print("error: localization keys are not in sync", file=sys.stderr)
        return 1
    print("ok: localization keys match")
    return 0


if __name__ == "__main__":
    sys.exit(main())
