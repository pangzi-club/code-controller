#!/bin/bash
# Assembles a proper .app bundle from the SwiftPM build.
# App identity (display name, bundle ID, version) is parsed from the
# AppInfo.swift next to the sources; the target/binary name is derived from
# Package.swift via `swift package describe`, so nothing is duplicated here.
# Usage: ./Scripts/make-app.sh   (result: build/<display name>.app)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

die() { echo "error: $*" >&2; exit 1; }

# --- Target/binary name: ask SwiftPM -----------------------------------------
[[ -x /usr/bin/python3 ]] || die "/usr/bin/python3 not available"
PACKAGE_JSON="$(swift package describe --type json)"
# Pick the executable target by type: test targets appear in the list too.
TARGET_NAME="$(/usr/bin/python3 -c 'import json,sys; print(next(t["name"] for t in json.load(sys.stdin)["targets"] if t.get("type") == "executable"))' <<<"$PACKAGE_JSON")"
PACKAGE_NAME="$(/usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["name"])' <<<"$PACKAGE_JSON")"
[[ -n "$TARGET_NAME" && -n "$PACKAGE_NAME" ]] || die "could not read names from Package.swift"

# --- Identity: parsed from AppInfo.swift --------------------------------------
# The path is discovered so the script keeps working after Scripts/rename.sh.
APPINFO="$(ls Sources/*/AppInfo.swift 2>/dev/null | head -1)"
[[ -n "$APPINFO" && -f "$APPINFO" ]] || die "Sources/*/AppInfo.swift not found"
read_swift_constant() {
    sed -nE "s/^[[:space:]]*static let $1[[:space:]]*=[[:space:]]*\"([^\"]+)\".*/\1/p" "$APPINFO"
}
APP_DISPLAY_NAME="$(read_swift_constant displayName)"
BUNDLE_ID="$(read_swift_constant bundleID)"
VERSION="$(read_swift_constant version)"
[[ -n "$APP_DISPLAY_NAME" && -n "$BUNDLE_ID" && -n "$VERSION" ]] \
    || die "displayName / bundleID / version not found in $APPINFO"

echo "==> Identity: $APP_DISPLAY_NAME $VERSION ($BUNDLE_ID), target: $TARGET_NAME"

echo "==> Building (release)…"
swift build -c release

BUILD_DIR="$ROOT/build"
APP_DIR="$BUILD_DIR/$APP_DISPLAY_NAME.app"
CONTENTS="$APP_DIR/Contents"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

echo "==> Copying binary and resources…"
cp ".build/release/$TARGET_NAME" "$CONTENTS/MacOS/$TARGET_NAME"
# Bundle.module resolves this resource bundle from the app's Resources directory.
cp -R ".build/release/${PACKAGE_NAME}_${TARGET_NAME}.bundle" "$CONTENTS/Resources/"

echo "==> Generating app icon…"
swift Scripts/make-icon.swift "$BUILD_DIR"
iconutil -c icns "$BUILD_DIR/AppIcon.iconset" -o "$CONTENTS/Resources/AppIcon.icns"
rm -rf "$BUILD_DIR/AppIcon.iconset"

echo "==> Writing Info.plist…"
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_DISPLAY_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_DISPLAY_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>$TARGET_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

echo "==> Ad-hoc code signing…"
codesign --force --sign - "$APP_DIR"

echo "==> Done: $APP_DIR"
