#!/bin/bash
# Renames the app template in one shot: package/target names in Package.swift,
# the Sources/ and Tests/ directories, the @main entry file, the identity in
# AppInfo.swift, and every mention in the READMEs and AGENTS.md.
#
# Usage:
#   ./Scripts/rename.sh <NewName> [com.example.newid]
#
# <NewName> must be a valid Swift identifier (it becomes the package name,
# library target name, directory name and struct prefix). The executable
# target becomes <NewName>App. The bundle ID defaults to
# com.example.<NewName>. The display name can be changed afterwards directly
# in AppInfo.swift (it may contain spaces).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

die() { echo "error: $*" >&2; exit 1; }

[[ $# -ge 1 ]] || die "usage: ./Scripts/rename.sh <NewName> [com.example.newid]"
NEW="$1"
BUNDLE_ID="${2:-}"

# --- Current name: the library target directory under Sources/ -----------------
# The library target is the one whose name does NOT end in "App".
SOURCE_DIRS=(Sources/*/)
[[ ${#SOURCE_DIRS[@]} -ge 2 ]] || die "expected at least two directories under Sources/"
OLD=""
for dir in "${SOURCE_DIRS[@]}"; do
    name="$(basename "$dir")"
    if [[ "$name" != *App ]]; then
        OLD="$name"
        break
    fi
done
[[ -n "$OLD" ]] || die "could not find library target directory under Sources/"
[[ "$OLD" != "$NEW" ]] || die "already named $OLD"

[[ "$NEW" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]] || die "$NEW is not a valid Swift identifier"
if [[ -z "$BUNDLE_ID" ]]; then
    BUNDLE_ID="com.example.$NEW"
    echo "note: no bundle ID given, defaulting to $BUNDLE_ID (edit AppInfo.swift to change)"
fi

echo "==> Renaming $OLD -> $NEW (bundle ID: $BUNDLE_ID)"

# --- Move directories and the @main entry file ----------------------------------
# Library target directory
git mv "Sources/$OLD" "Sources/$NEW"
# Executable target directory
if [[ -d "Sources/${OLD}App" ]]; then
    git mv "Sources/${OLD}App" "Sources/${NEW}App"
fi
if [[ -d "Tests/${OLD}Tests" ]]; then
    git mv "Tests/${OLD}Tests" "Tests/${NEW}Tests"
fi
if [[ -f "Sources/${NEW}App/${OLD}App.swift" ]]; then
    git mv "Sources/${NEW}App/${OLD}App.swift" "Sources/${NEW}App/${NEW}App.swift"
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
