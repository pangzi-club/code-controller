#!/bin/bash
# Assembles proper .app bundles from the SwiftPM build, one per architecture
# (arm64 + x86_64 by default) so Apple Silicon and Intel Macs each get a native
# bundle. The App Store build remains a single universal bundle inside the .pkg.
# App identity (display name, bundle ID, version, build) is parsed from the
# AppInfo.swift next to the sources; the target/binary name and minimum macOS
# version are derived from Package.swift via `swift package describe`, so
# nothing is duplicated here.
#
# Local and Developer ID builds sign with Scripts/App.entitlements
# (unsandboxed by default); the App Store build signs with
# Scripts/App.sandbox.entitlements.
#
# Usage:
#   ./Scripts/make-app.sh                  # Developer ID (or ad-hoc), arm64 + x86_64
#   ARCHS="arm64" ./Scripts/make-app.sh    # build a subset of architectures
#   DEV=1 ./Scripts/make-app.sh            # local dev build: .dev bundle ID + "-Dev" name
#   MAS=1 ./Scripts/make-app.sh            # App Store build + .pkg, sandboxed, universal
#
# Environment overrides:
#   ARCHS                architectures for direct/dev builds (default "arm64 x86_64")
#   SIGN_IDENTITY        signing identity (defaults to Developer ID Application
#                        for a normal build, Apple Distribution for MAS=1)
#   INSTALLER_IDENTITY   installer certificate for the MAS .pkg
#   PROVISION_PROFILE    optional profile to embed (required for TestFlight)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

die() { echo "error: $*" >&2; exit 1; }

MAS="${MAS:-0}"
DEV="${DEV:-0}"
if [[ "$MAS" == "1" && "$DEV" == "1" ]]; then
    die "MAS=1 and DEV=1 are mutually exclusive"
fi

if [[ "$MAS" == "1" ]]; then
    # App Store builds ship one universal bundle in the .pkg.
    if [[ -n "${ARCHS:-}" ]]; then
        echo "note: MAS=1 builds a universal app; ignoring ARCHS=$ARCHS"
    fi
    ARCH_LIST=(universal)
else
    ARCHS="${ARCHS:-arm64 x86_64}"
    read -r -a ARCH_LIST <<<"$ARCHS" || true
    [[ ${#ARCH_LIST[@]} -gt 0 ]] || die "ARCHS is empty"
    for ARCH in "${ARCH_LIST[@]}"; do
        case "$ARCH" in
            arm64|x86_64) ;;
            *) die "unsupported architecture '$ARCH' (expected arm64 or x86_64)" ;;
        esac
    done
fi

# --- Target/binary name and minimum OS: ask SwiftPM --------------------------
command -v python3 >/dev/null 2>&1 || die "python3 not found in PATH"
PACKAGE_JSON="$(swift package describe --type json)"
# Pick the executable target by type: test targets appear in the list too.
TARGET_NAME="$(python3 -c 'import json,sys; print(next(t["name"] for t in json.load(sys.stdin)["targets"] if t.get("type") == "executable"))' <<<"$PACKAGE_JSON")"
PACKAGE_NAME="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["name"])' <<<"$PACKAGE_JSON")"
MIN_MACOS="$(python3 -c 'import json,sys; print(next((p["version"] for p in json.load(sys.stdin).get("platforms", []) if p.get("name", "").lower() == "macos"), "13.0"))' <<<"$PACKAGE_JSON")"
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
BUILD="$(read_swift_constant build)"
[[ -n "$APP_DISPLAY_NAME" && -n "$BUNDLE_ID" && -n "$VERSION" && -n "$BUILD" ]] \
    || die "displayName / bundleID / version / build not found in $APPINFO"

# Direct distribution does not require App Sandbox; the App Store does.
if [[ "$MAS" == "1" ]]; then
    ENTITLEMENTS="$ROOT/Scripts/App.sandbox.entitlements"
else
    ENTITLEMENTS="$ROOT/Scripts/App.entitlements"
fi
[[ -f "$ENTITLEMENTS" ]] || die "${ENTITLEMENTS#"$ROOT"/} not found"
PRIVACY_MANIFEST="$(dirname "$APPINFO")/Resources/PrivacyInfo.xcprivacy"
[[ -f "$PRIVACY_MANIFEST" ]] || die "$PRIVACY_MANIFEST not found"

# App Review rejects a Mac App Store build without App Sandbox. Fail early
# instead of producing a package that cannot be submitted.
if [[ "$MAS" == "1" ]]; then
    SANDBOX_ENABLED="$(/usr/libexec/PlistBuddy -c "Print :com.apple.security.app-sandbox" "$ENTITLEMENTS" 2>/dev/null || true)"
    [[ "$SANDBOX_ENABLED" == "true" ]] \
        || die "MAS=1 requires com.apple.security.app-sandbox in ${ENTITLEMENTS#"$ROOT"/}"
fi

# Dev builds get their own identity: TCC grants and UserDefaults are keyed by
# bundle ID, so local runs keep separate state instead of colliding with the
# shipping build (and, when sandboxed, a separate container).
if [[ "$DEV" == "1" ]]; then
    EFFECTIVE_BUNDLE_ID="$BUNDLE_ID.dev"
    EFFECTIVE_DISPLAY_NAME="$APP_DISPLAY_NAME-Dev"
else
    EFFECTIVE_BUNDLE_ID="$BUNDLE_ID"
    EFFECTIVE_DISPLAY_NAME="$APP_DISPLAY_NAME"
fi

echo "==> Identity: $EFFECTIVE_DISPLAY_NAME $VERSION ($BUILD) ($EFFECTIVE_BUNDLE_ID), target: $TARGET_NAME"

BUILD_DIR="$ROOT/build"

echo "==> Generating app icon…"
swift Scripts/make-icon.swift "$BUILD_DIR"
iconutil -c icns "$BUILD_DIR/AppIcon.iconset" -o "$BUILD_DIR/AppIcon.icns"
rm -rf "$BUILD_DIR/AppIcon.iconset"

echo "==> Writing Info.plist…"
cat > "$BUILD_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$EFFECTIVE_DISPLAY_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$EFFECTIVE_DISPLAY_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$EFFECTIVE_BUNDLE_ID</string>
    <key>CFBundleVersion</key>
    <string>$BUILD</string>
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
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>zh-Hans</string>
    </array>
    <key>LSMinimumSystemVersion</key>
    <string>$MIN_MACOS</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

# If the app reads protected folders (Downloads, Desktop, Documents, camera,
# microphone, …), add the matching NS*UsageDescription keys to the heredoc
# above and localized copies under Contents/Resources/<lang>.lproj/
# InfoPlist.strings so the system prompt follows the user's language.

# --- Signing ------------------------------------------------------------------
find_codesigning_identity() {
    security find-identity -v -p codesigning 2>/dev/null \
        | sed -nE 's/^[[:space:]]*[0-9]+\) [0-9A-F]+ "(.+)".*/\1/p' \
        | grep -E "$1" | head -1 || true
}

IDENTITY="${SIGN_IDENTITY:-}"
if [[ "$MAS" == "1" ]]; then
    [[ -n "$IDENTITY" ]] || IDENTITY="$(find_codesigning_identity '^(Apple Distribution|3rd Party Mac Developer Application): ')"
    [[ -n "$IDENTITY" ]] || die "MAS=1 needs an Apple Distribution certificate in the keychain (or set SIGN_IDENTITY)"
else
    # Developer ID is the right certificate for direct distribution. When the
    # keychain has none, fall back to ad-hoc signing (local builds only).
    [[ -n "$IDENTITY" ]] || IDENTITY="$(find_codesigning_identity '^Developer ID Application: ')"
fi

# --- Build and package each architecture --------------------------------------
APP_DIRS=()
for ARCH in "${ARCH_LIST[@]}"; do
    if [[ "$ARCH" == "universal" ]]; then
        SWIFT_ARCH_ARGS=(--arch arm64 --arch x86_64)
        APP_SUFFIX=""
    else
        SWIFT_ARCH_ARGS=(--arch "$ARCH")
        APP_SUFFIX="-$ARCH"
    fi

    echo "==> Building (release): $ARCH…"
    # Single-arch builds reuse one product directory, so package each
    # architecture immediately instead of copying them all after the loop.
    swift build -c release "${SWIFT_ARCH_ARGS[@]}"
    BIN_DIR="$(swift build -c release "${SWIFT_ARCH_ARGS[@]}" --show-bin-path)"
    [[ -x "$BIN_DIR/$TARGET_NAME" ]] || die "built binary not found at $BIN_DIR/$TARGET_NAME"

    APP_DIR="$BUILD_DIR/$EFFECTIVE_DISPLAY_NAME$APP_SUFFIX.app"
    CONTENTS="$APP_DIR/Contents"

    echo "==> Packaging $EFFECTIVE_DISPLAY_NAME$APP_SUFFIX.app…"
    rm -rf "$APP_DIR"
    mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

    cp "$BIN_DIR/$TARGET_NAME" "$CONTENTS/MacOS/$TARGET_NAME"
    BINARY_ARCHS="$(lipo -archs "$CONTENTS/MacOS/$TARGET_NAME")"
    if [[ "$ARCH" == "universal" ]]; then
        [[ "$BINARY_ARCHS" == *arm64* && "$BINARY_ARCHS" == *x86_64* ]] \
            || die "expected a universal binary (arm64 + x86_64), got: $BINARY_ARCHS"
    else
        [[ "$BINARY_ARCHS" == "$ARCH" ]] || die "expected a $ARCH binary, got: $BINARY_ARCHS"
    fi
    echo "    binary architectures: $BINARY_ARCHS"

    # Bundle.module resolves this resource bundle from the library target's
    # Resources directory (the binary target name differs from the library's).
    RESOURCE_BUNDLE="$(ls -d "$BIN_DIR/${PACKAGE_NAME}_"*.bundle 2>/dev/null | head -1)"
    [[ -n "$RESOURCE_BUNDLE" ]] || die "resource bundle not found in $BIN_DIR"
    cp -R "$RESOURCE_BUNDLE" "$CONTENTS/Resources/"
    # App Store validation reads the manifest from the app bundle's resource root;
    # the copy inside the SwiftPM resource bundle alone is not enough.
    cp "$PRIVACY_MANIFEST" "$CONTENTS/Resources/PrivacyInfo.xcprivacy"
    cp "$BUILD_DIR/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
    cp "$BUILD_DIR/Info.plist" "$CONTENTS/Info.plist"

    echo "==> Code signing…"
    echo "    entitlements: ${ENTITLEMENTS#"$ROOT"/}"
    if [[ -n "$IDENTITY" ]]; then
        echo "    identity: $IDENTITY"
        # Hardened runtime is required once notarization is added; keep it on
        # from the start so the signed app behaves like the future release.
        codesign --force --sign "$IDENTITY" --options runtime --timestamp \
            --entitlements "$ENTITLEMENTS" "$APP_DIR"
    else
        echo "    no Developer ID identity found — falling back to ad-hoc"
        codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP_DIR"
    fi
    codesign --verify --strict "$APP_DIR"

    APP_DIRS+=("$APP_DIR")
done

rm -f "$BUILD_DIR/Info.plist" "$BUILD_DIR/AppIcon.icns"

# --- Mac App Store package ----------------------------------------------------
if [[ "$MAS" == "1" ]]; then
    INSTALLER_IDENTITY="${INSTALLER_IDENTITY:-}"
    if [[ -z "$INSTALLER_IDENTITY" ]]; then
        INSTALLER_IDENTITY="$(security find-identity -v -p basic 2>/dev/null \
            | sed -nE 's/^[[:space:]]*[0-9]+\) [0-9A-F]+ "(.+)".*/\1/p' \
            | grep -E '^(3rd Party Mac Developer Installer|Mac Installer Distribution): ' \
            | head -1 || true)"
    fi
    [[ -n "$INSTALLER_IDENTITY" ]] \
        || die "MAS=1 needs an installer certificate (Mac Installer Distribution) — set INSTALLER_IDENTITY"
    MAS_APP_DIR="$BUILD_DIR/$EFFECTIVE_DISPLAY_NAME.app"
    PKG="$BUILD_DIR/$APP_DISPLAY_NAME-$VERSION-$BUILD.pkg"
    echo "==> Packaging $PKG…"
    productbuild --component "$MAS_APP_DIR" /Applications --sign "$INSTALLER_IDENTITY" "$PKG"
    echo "    installer identity: $INSTALLER_IDENTITY"
fi

echo "==> Done:"
for APP_DIR in "${APP_DIRS[@]}"; do
    echo "    $APP_DIR ($(lipo -archs "$APP_DIR/Contents/MacOS/$TARGET_NAME"))"
done
