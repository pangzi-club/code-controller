#!/bin/bash
# Shows how this app's template-managed files differ from a local
# swiftui-starter checkout. Read-only: it never overwrites anything, because
# forks legitimately add app-specific targets, entitlements and docs.
#
# Usage: ./Scripts/template-diff.sh /path/to/swiftui-starter
#    or: make template-diff SOURCE=/path/to/swiftui-starter
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="${1:-}"
[[ -n "$SOURCE" ]] || {
    echo "usage: $0 /path/to/swiftui-starter" >&2
    exit 1
}
[[ -d "$SOURCE" ]] || {
    echo "error: not a directory: $SOURCE" >&2
    exit 1
}

VERSION="$(sed -nE 's/^Template version:[[:space:]]*(.+)$/\1/p' "$SOURCE/TEMPLATE.md" 2>/dev/null | head -1)"
echo "==> Comparing against $SOURCE${VERSION:+ (template $VERSION)}"

FILES=(
    Makefile
    Scripts/App.entitlements
    Scripts/check-l10n.py
    Scripts/make-app.sh
    Scripts/make-icon.swift
    Scripts/rename.sh
    docs/ui-testing.md
)

status=0
for file in "${FILES[@]}"; do
    upstream="$SOURCE/$file"
    local="$ROOT/$file"
    if [[ ! -f "$upstream" ]]; then
        echo "warning: upstream is missing $file" >&2
        status=1
        continue
    fi
    if [[ ! -f "$local" ]]; then
        echo
        echo "=== $file: missing locally ==="
        status=1
        continue
    fi
    if ! cmp -s "$upstream" "$local"; then
        echo
        echo "=== $file (upstream → local) ==="
        diff -u -L "upstream/$file" -L "local/$file" "$upstream" "$local" || true
        status=1
    fi
done

# The privacy manifest lives under the library target, whose name changes with
# Scripts/rename.sh, so compare it by pattern.
for local in "$ROOT"/Sources/*/Resources/PrivacyInfo.xcprivacy; do
    [[ -f "$local" ]] || continue
    relative="${local#"$ROOT"/}"
    upstream="$SOURCE/$relative"
    [[ -f "$upstream" ]] || continue
    if ! cmp -s "$upstream" "$local"; then
        echo
        echo "=== $relative (upstream → local) ==="
        diff -u -L "upstream/$relative" -L "local/$relative" "$upstream" "$local" || true
        status=1
    fi
done

if [[ "$status" -eq 0 ]]; then
    echo "ok: template-managed files match"
else
    echo
    echo "Review the diffs and port the upstream changes that apply. App-specific"
    echo "targets, entitlements and docs are expected to differ; see TEMPLATE.md."
fi
