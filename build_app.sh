#!/bin/bash
# Build "MacDashboard.app": Apple Silicon (arm64) release, hand-rolled bundle,
# ad-hoc codesign. Output: dist/MacDashboard.app
# Usage: ./build_app.sh [--install]
#   --install             also copies the built app to ~/Applications
set -euo pipefail
cd "$(dirname "$0")"

INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    *) echo "unknown argument: $arg" >&2; exit 1 ;;
  esac
done

APP_NAME="MacDashboard"
DIST="dist/$APP_NAME.app"
VERSION="2.1"
# Codename names the whole 2.x branch, not the point release — stays "Krieg" until 3.0.
# Only a NON-empty codename is appended to CFBundleShortVersionString — an empty one must not
# leave "2.1 ()".
CODENAME="Krieg"
if [ -n "$CODENAME" ]; then
  SHORT_VERSION="$VERSION ($CODENAME)"
else
  SHORT_VERSION="$VERSION"
fi

echo "== toolchain =="
# The LC_BUILD_VERSION `sdk` field of the binary decides which appearance macOS
# gives the app (an old sdk => old compatibility look), so it must record the SDK
# this script really compiled against. Three flags make that hold (V27-TOOLCHAIN):
#   --build-system native  the default `swiftbuild` system injects its own -sdk next
#                          to ours (duplicate -sdk => mixed-SDK link failures)
#   -Xswiftc -sdk          compile against exactly $SDK_PATH
#   -platform_version      with --triple alone, ld records sdk == minos (14.0)
# The check under "== result ==" fails the build if the recorded value drifts.
MIN_MACOS="14.0"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
if [ ! -d "$SDK_PATH" ] || [ -z "$SDK_VERSION" ]; then
  echo "!! could not resolve the macOS SDK via xcrun (path='$SDK_PATH', version='$SDK_VERSION')" >&2
  exit 1
fi
echo "developer dir: $(xcode-select -p)"
echo "macOS SDK: $SDK_VERSION ($SDK_PATH); deployment target: $MIN_MACOS"

echo "== swift build (Apple Silicon, arm64) =="
# Apple Silicon only: Intel Macs stay on v2.1. --triple pins the architecture and
# the deployment target independently of the host this script runs on.
EXPECTED_ARCH="arm64"
BIN=".build/$EXPECTED_ARCH-apple-macosx/release/MacDashboard"

AI_FLAGS=()
if [ "${MACDASHBOARD_AI:-}" = "1" ]; then
  echo "MACDASHBOARD_AI=1 — building with AI assistant enabled" >&2
  AI_FLAGS=(-Xswiftc -DAI_ENABLED)
fi

swift build -c release --product MacDashboard --build-system native \
  --triple "$EXPECTED_ARCH-apple-macosx$MIN_MACOS" \
  -Xswiftc -sdk -Xswiftc "$SDK_PATH" \
  -Xlinker -platform_version -Xlinker macos -Xlinker "$MIN_MACOS" -Xlinker "$SDK_VERSION" \
  "${AI_FLAGS[@]+"${AI_FLAGS[@]}"}"
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
    <key>CFBundleShortVersionString</key><string>${SHORT_VERSION}</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key><string>${MIN_MACOS}</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>The dashboard uses Apple events for two things: it reads your Login Items list via System Events, and — only when you confirm it in the app — it asks Finder to empty the Trash.</string>
    <key>NSDesktopFolderUsageDescription</key>
    <string>The dashboard measures how much space your Desktop folder uses, for the "home folders" section of the report. It reads folder sizes only — file contents are never opened.</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>The dashboard measures how much space your Documents folder uses, for the "home folders" section of the report. It reads folder sizes only — file contents are never opened.</string>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>The dashboard measures how much space your Downloads folder uses, for the "home folders" section of the report. It reads folder sizes only — file contents are never opened.</string>
    <key>NSRemovableVolumesUsageDescription</key>
    <string>The dashboard reports free space and Time Machine destinations for connected volumes, including removable disks. It reads volume sizes only — file contents are never opened.</string>
    <key>NSHumanReadableCopyright</key><string>© 2026 rdskcm. MIT License.</string>
</dict>
</plist>
PLIST

# NSAppleEventsUsageDescription is ONE app-wide string: macOS shows the same text for the
# System Events prompt (login items) and the Finder prompt (empty Trash), so it must name
# both — including the destructive one. NSDesktopFolderUsageDescription,
# NSDocumentsFolderUsageDescription, NSDownloadsFolderUsageDescription, and
# NSRemovableVolumesUsageDescription follow the same three-place rule (Info.plist plus en/ru
# InfoPlist.strings), no shared source: keep all three in sync for each key.
echo "== localized InfoPlist.strings =="
mkdir -p "$DIST/Contents/Resources/en.lproj" "$DIST/Contents/Resources/ru.lproj"

cat > "$DIST/Contents/Resources/en.lproj/InfoPlist.strings" <<'EOSTRINGS'
NSHumanReadableCopyright = "© 2026 rdskcm. MIT License.";
NSAppleEventsUsageDescription = "The dashboard uses Apple events for two things: it reads your Login Items list via System Events, and — only when you confirm it in the app — it asks Finder to empty the Trash.";
NSDesktopFolderUsageDescription = "The dashboard measures how much space your Desktop folder uses, for the \"home folders\" section of the report. It reads folder sizes only — file contents are never opened.";
NSDocumentsFolderUsageDescription = "The dashboard measures how much space your Documents folder uses, for the \"home folders\" section of the report. It reads folder sizes only — file contents are never opened.";
NSDownloadsFolderUsageDescription = "The dashboard measures how much space your Downloads folder uses, for the \"home folders\" section of the report. It reads folder sizes only — file contents are never opened.";
NSRemovableVolumesUsageDescription = "The dashboard reports free space and Time Machine destinations for connected volumes, including removable disks. It reads volume sizes only — file contents are never opened.";
EOSTRINGS

cat > "$DIST/Contents/Resources/ru.lproj/InfoPlist.strings" <<'EOSTRINGS'
NSHumanReadableCopyright = "© 2026 rdskcm. Лицензия MIT.";
NSAppleEventsUsageDescription = "Дашборд использует Apple events для двух задач: читает список объектов автозагрузки (Login Items) через System Events и — только после вашего подтверждения в приложении — просит Finder очистить Корзину.";
NSDesktopFolderUsageDescription = "Дашборд измеряет, сколько места занимает папка «Рабочий стол», для раздела отчёта о папках домашней директории. Читаются только размеры папок — содержимое файлов не открывается.";
NSDocumentsFolderUsageDescription = "Дашборд измеряет, сколько места занимает папка «Документы», для раздела отчёта о папках домашней директории. Читаются только размеры папок — содержимое файлов не открывается.";
NSDownloadsFolderUsageDescription = "Дашборд измеряет, сколько места занимает папка «Загрузки», для раздела отчёта о папках домашней директории. Читаются только размеры папок — содержимое файлов не открывается.";
NSRemovableVolumesUsageDescription = "Дашборд показывает свободное место и адреса резервных копий Time Machine для подключённых томов, включая съёмные диски. Читаются только размеры томов — содержимое файлов не открывается.";
EOSTRINGS

echo "== icon (best-effort) =="
if swift tools/make_icon.swift "$DIST/Contents/Resources/AppIcon.icns"; then
  echo "icon OK"
else
  echo "!! icon generation failed — shipping without custom icon" >&2
  /usr/libexec/PlistBuddy -c "Delete :CFBundleIconFile" "$DIST/Contents/Info.plist" 2>/dev/null || true
fi

echo "== codesign (ad-hoc, hardened runtime) =="
# --options runtime: without the hardened runtime DYLD_INSERT_LIBRARIES is honoured
# and library validation is off, so any local process running as this user could
# inject into an app the README asks users to grant Full Disk Access and inherit its
# TCC grants. --entitlements: the hardened runtime blocks in-process Apple events
# (AdviceActionRunner.emptyTrash) unless com.apple.security.automation.apple-events
# is present.
# No --deep: Apple documents it as a testing convenience, and combined with
# --entitlements it would grant these entitlements to any nested code added later.
# Nested code, if ever added, must be signed explicitly.
codesign --force --options runtime --entitlements MacDashboard.entitlements --sign - "$DIST"

echo "== result =="
# Fail-loud gate (V27-TOOLCHAIN): the binary must be arm64 only and record the SDK
# compiled against above and the deployment target. Runs before --install, so a
# wrong build is never installed.
FINAL_BIN="$DIST/Contents/MacOS/MacDashboard"
# "27" and "27.0" are the same version; xcrun and vtool need not format alike.
norm_version() { sed -E 's/(\.0)+$//' <<<"$1"; }
FINAL_ARCHS="$(lipo -archs "$FINAL_BIN")"
echo "archs: $FINAL_ARCHS (expected: $EXPECTED_ARCH)"
if [ "$FINAL_ARCHS" != "$EXPECTED_ARCH" ]; then
  echo "!! ARCH MISMATCH: $FINAL_BIN has archs '$FINAL_ARCHS', expected exactly '$EXPECTED_ARCH'" >&2
  exit 1
fi
BUILD_INFO="$(vtool -show-build "$FINAL_BIN")"
REC_SDK="$(awk '$1=="sdk"{print $2; exit}' <<<"$BUILD_INFO")"
REC_MINOS="$(awk '$1=="minos"{print $2; exit}' <<<"$BUILD_INFO")"
echo "binary records minos ${REC_MINOS:-none} / sdk ${REC_SDK:-none}; compiled against SDK $SDK_VERSION, target $MIN_MACOS"
if [ "$(norm_version "$REC_SDK")" != "$(norm_version "$SDK_VERSION")" ]; then
  echo "!! SDK MISMATCH: binary records sdk ${REC_SDK:-none}, but it was compiled against SDK $SDK_VERSION" >&2
  exit 1
fi
if [ "$(norm_version "$REC_MINOS")" != "$(norm_version "$MIN_MACOS")" ]; then
  echo "!! DEPLOYMENT TARGET MISMATCH: binary records minos ${REC_MINOS:-none}, expected $MIN_MACOS" >&2
  exit 1
fi
echo "SDK check OK: arm64 binary records sdk $SDK_VERSION"
du -sh "$DIST"
codesign -dvv "$DIST" 2>&1 | grep -E '^(Identifier|CodeDirectory|Signature)' | head -3

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
