#!/bin/bash
# Renames the app template in one shot: package/target names in Package.swift,
# the Sources/ and Tests/ directories, the @main struct file, the identity in
# AppInfo.swift, and every mention in the READMEs and AGENTS.md.
#
# Usage:
#   ./Scripts/rename.sh <NewName> [com.example.newid]
#
# <NewName> must be a valid Swift identifier (it becomes the package name,
# target name, directory name and struct prefix). The bundle ID defaults to
# com.example.<NewName>. The display name can be changed afterwards directly
# in AppInfo.swift (it may contain spaces).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

die() { echo "error: $*" >&2; exit 1; }

[[ $# -ge 1 ]] || die "usage: ./Scripts/rename.sh <NewName> [com.example.newid]"
NEW="$1"
BUNDLE_ID="${2:-}"

# --- Current name: the single target directory under Sources/ -----------------
SOURCE_DIRS=(Sources/*/)
[[ ${#SOURCE_DIRS[@]} -eq 1 ]] || die "expected exactly one directory under Sources/"
OLD="$(basename "${SOURCE_DIRS[0]}")"
[[ "$OLD" != "$NEW" ]] || die "already named $OLD"

[[ "$NEW" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]] || die "$NEW is not a valid Swift identifier"
if [[ -z "$BUNDLE_ID" ]]; then
    BUNDLE_ID="com.example.$NEW"
    echo "note: no bundle ID given, defaulting to $BUNDLE_ID (edit AppInfo.swift to change)"
fi

echo "==> Renaming $OLD -> $NEW (bundle ID: $BUNDLE_ID)"

# --- Move directories and the @main struct file -------------------------------
git mv "Sources/$OLD" "Sources/$NEW"
if [[ -d "Tests/${OLD}Tests" ]]; then
    git mv "Tests/${OLD}Tests" "Tests/${NEW}Tests"
fi
if [[ -f "Sources/$NEW/${OLD}App.swift" ]]; then
    git mv "Sources/$NEW/${OLD}App.swift" "Sources/$NEW/${NEW}App.swift"
fi

# --- Replace every occurrence in docs and sources ------------------------------
for f in Package.swift README.md README.ZH.md AGENTS.md; do
    [[ -f "$f" ]] && sed -i '' "s/$OLD/$NEW/g" "$f"
done
ROOTS=(Sources)
[[ -d Tests ]] && ROOTS+=(Tests)
find "${ROOTS[@]}" -type f \( -name '*.swift' -o -name '*.strings' \) \
    | xargs sed -i '' "s/$OLD/$NEW/g"

# --- Bundle ID is rewritten explicitly (it shares no text with the name) -------
sed -i '' -E "s/^([[:space:]]*static let bundleID[[:space:]]*=[[:space:]]*)\"[^\"]+\".*/\1\"$BUNDLE_ID\"/" \
    "Sources/$NEW/AppInfo.swift"

# --- Stale build caches reference the old target name --------------------------
rm -rf .build build

echo "==> Done. Next:"
echo "    make dev      # debug run"
echo "    make app      # assemble ${NEW}.app"
echo "    swift test"
echo "Note: the UserDefaults domain follows the bundle ID, so previously saved"
echo "state (folders, theme, window frame) will not carry over."
