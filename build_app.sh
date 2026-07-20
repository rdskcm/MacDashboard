#!/bin/bash
# Build "MacDashboard.app": universal (arm64 + x86_64) release, hand-rolled bundle,
# ad-hoc codesign. Output: dist/MacDashboard.app
# Usage: ./build_app.sh [--install] [--allow-single-arch]
#   --install             also copies the built app to ~/Applications
#   --allow-single-arch   don't fail if only one architecture builds (default: fail)
set -euo pipefail
cd "$(dirname "$0")"

INSTALL=0
ALLOW_SINGLE_ARCH=0
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    --allow-single-arch) ALLOW_SINGLE_ARCH=1 ;;
    *) echo "unknown argument: $arg" >&2; exit 1 ;;
  esac
done

APP_NAME="MacDashboard"
DIST="dist/$APP_NAME.app"
VERSION="1.0"
CODENAME="Cadia"

echo "== swift build (universal via per-arch --triple + lipo) =="
# `swift build --arch arm64 --arch x86_64` requires xcbuild, which is only
# shipped with Xcode (not Command Line Tools). Build each slice separately
# via --triple (works under CLT), then merge with lipo.
ARM64_BIN=".build/arm64-apple-macosx/release/MacDashboard"
X86_64_BIN=".build/x86_64-apple-macosx/release/MacDashboard"
BIN=""

AI_FLAGS=()
if [ "${MACDASHBOARD_AI:-}" = "1" ]; then
  echo "MACDASHBOARD_AI=1 — building with AI assistant enabled" >&2
  AI_FLAGS=(-Xswiftc -DAI_ENABLED)
fi

ARM64_OK=0
X86_64_OK=0
swift build -c release --product MacDashboard --triple arm64-apple-macosx14.0 "${AI_FLAGS[@]+"${AI_FLAGS[@]}"}" && ARM64_OK=1 || ARM64_OK=0
swift build -c release --product MacDashboard --triple x86_64-apple-macosx14.0 "${AI_FLAGS[@]+"${AI_FLAGS[@]}"}" && X86_64_OK=1 || X86_64_OK=0

if [ "$ARM64_OK" = "1" ] && [ "$X86_64_OK" = "1" ] \
   && [ -x "$ARM64_BIN" ] && [ -x "$X86_64_BIN" ]; then
  UNIVERSAL_BIN=".build/universal-MacDashboard"
  rm -f "$UNIVERSAL_BIN"
  lipo -create -output "$UNIVERSAL_BIN" "$ARM64_BIN" "$X86_64_BIN"
  ARCHES="$(lipo -archs "$UNIVERSAL_BIN")"
  case "$ARCHES" in
    *arm64*x86_64*|*x86_64*arm64*) ;;
    *) echo "!! lipo produced single-arch binary ($ARCHES) — treating as error" >&2; exit 1 ;;
  esac
  BIN="$UNIVERSAL_BIN"
  echo "universal build OK: $ARCHES"
else
  echo "!! per-arch --triple build failed for one or both slices — falling back to native arch" >&2
  [ "$ARM64_OK" = "1" ] || echo "   (arm64 slice failed)" >&2
  [ "$X86_64_OK" = "1" ] || echo "   (x86_64 slice failed)" >&2
  swift build -c release --product MacDashboard
  BIN=".build/release/MacDashboard"
  NATIVE_ARCH="$(uname -m)"
  echo "!! WARNING: shipping single-arch app (native: $NATIVE_ARCH) — will NOT run on the other architecture" >&2
  if [ "$ALLOW_SINGLE_ARCH" != "1" ]; then
    echo "!! refusing to ship a single-arch release build — pass --allow-single-arch to override" >&2
    exit 1
  fi
fi
[ -x "$BIN" ] || { echo "binary not found: $BIN" >&2; exit 1; }

echo "== bundle =="
rm -rf "$DIST"
mkdir -p "$DIST/Contents/MacOS" "$DIST/Contents/Resources"
cp "$BIN" "$DIST/Contents/MacOS/MacDashboard"

cat > "$DIST/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleDisplayName</key><string>MacDashboard</string>
    <key>CFBundleExecutable</key><string>MacDashboard</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>com.rdskcm.mac-dashboard</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleLocalizations</key><array><string>en</string><string>ru</string></array>
    <key>CFBundleName</key><string>MacDashboard</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION} (${CODENAME})</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>The dashboard reads the Login Items list via System Events.</string>
    <key>NSHumanReadableCopyright</key><string>© 2026 rdskcm. MIT License.</string>
</dict>
</plist>
PLIST

echo "== localized InfoPlist.strings =="
mkdir -p "$DIST/Contents/Resources/en.lproj" "$DIST/Contents/Resources/ru.lproj"

cat > "$DIST/Contents/Resources/en.lproj/InfoPlist.strings" <<'EOSTRINGS'
NSHumanReadableCopyright = "© 2026 rdskcm. MIT License.";
NSAppleEventsUsageDescription = "The dashboard reads the Login Items list via System Events.";
EOSTRINGS

cat > "$DIST/Contents/Resources/ru.lproj/InfoPlist.strings" <<'EOSTRINGS'
NSHumanReadableCopyright = "© 2026 rdskcm. Лицензия MIT.";
NSAppleEventsUsageDescription = "Дашборд читает список объектов автозагрузки (Login Items) через System Events.";
EOSTRINGS

echo "== icon (best-effort) =="
if swift tools/make_icon.swift "$DIST/Contents/Resources/AppIcon.icns"; then
  echo "icon OK"
else
  echo "!! icon generation failed — shipping without custom icon" >&2
  /usr/libexec/PlistBuddy -c "Delete :CFBundleIconFile" "$DIST/Contents/Info.plist" 2>/dev/null || true
fi

echo "== codesign (ad-hoc) =="
codesign --force --deep --sign - "$DIST"

echo "== result =="
lipo -archs "$DIST/Contents/MacOS/MacDashboard" 2>/dev/null || true
du -sh "$DIST"
codesign -dv "$DIST" 2>&1 | head -3

if [ "$INSTALL" = "1" ]; then
  echo "== install to ~/Applications =="
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/$APP_NAME.app"
  cp -R "$DIST" "$HOME/Applications/$APP_NAME.app"
  echo "installed: $HOME/Applications/$APP_NAME.app"
  # Remove the stale pre-rename bundle (old Russian display name) so the Dock/
  # Spotlight don't keep two copies around after the MacDashboard rename.
  if [ -d "$HOME/Applications/Дашборд Mac.app" ]; then
    rm -rf "$HOME/Applications/Дашборд Mac.app"
    echo "removed stale: $HOME/Applications/Дашборд Mac.app"
  fi
fi
echo "DONE"
