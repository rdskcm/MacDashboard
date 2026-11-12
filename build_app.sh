#!/bin/bash
# Build "Moonport.app": Apple Silicon (arm64) release, hand-rolled bundle,
# codesign (stable local identity, ad-hoc fallback). Output: dist.noindex/Moonport.app
# Usage: ./build_app.sh [--install]
#   --install             also moves the built app to ~/Applications (dist.noindex/ is left empty)
set -euo pipefail
cd "$(dirname "$0")"

INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    *) echo "unknown argument: $arg" >&2; exit 1 ;;
  esac
done

APP_NAME="Moonport"
DIST="dist.noindex/$APP_NAME.app"
VERSION="2.3.2"
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
# this script really compiled against. Two flags make that hold (V27-TOOLCHAIN):
#   (default build system) BUILD-WARNINGS (2026-11): no duplicate-SDK failure any more;
#                          --build-system native, deprecated by SwiftPM, was dropped.
#   -Xswiftc -sdk          compile against exactly $SDK_PATH
#   -platform_version      with --triple alone, ld records sdk == minos ($MIN_MACOS)
# The check under "== result ==" fails the build if the recorded value drifts.
# MIN-MACOS-26: keep in step with `.macOS(.v26)` in Package.swift (swift build / swift test).
MIN_MACOS="26.0"
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
SWIFT_BUILD_ARGS=(-c release --product MacDashboard
  --triple "$EXPECTED_ARCH-apple-macosx$MIN_MACOS"
  -Xswiftc -sdk -Xswiftc "$SDK_PATH"
  -Xlinker -platform_version -Xlinker macos -Xlinker "$MIN_MACOS" -Xlinker "$SDK_VERSION")
swift build "${SWIFT_BUILD_ARGS[@]}"
BIN="$(swift build "${SWIFT_BUILD_ARGS[@]}" --show-bin-path)/MacDashboard"
[ -x "$BIN" ] || { echo "binary not found: $BIN" >&2; exit 1; }

echo "== LaunchServices: drop stale registrations =="
# LaunchServices keeps every bundle with this CFBundleIdentifier it has seen, and opening
# the app by bundle ID can launch any of them (APP-ID-DUPLICATES). Clearing them at every
# build keeps test builds from accumulating. Never fails the build.
tools/ls-prune.sh || echo "!! tools/ls-prune.sh exited $? — stale LaunchServices registrations may remain" >&2

echo "== bundle =="
rm -rf "$DIST"
mkdir -p "$DIST/Contents/MacOS" "$DIST/Contents/Resources"
# A Time Machine copy of this bundle is registered with LaunchServices whenever the backup is
# mounted (APP-ID-DUPLICATES). Sticky exclusion on dist.noindex/ itself: survives rebuilds, no sudo.
tmutil addexclusion dist.noindex 2>/dev/null || echo "!! tmutil addexclusion dist.noindex failed — dist.noindex/ stays in Time Machine backups" >&2
cp "$BIN" "$DIST/Contents/MacOS/Moonport"

cat > "$DIST/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleDisplayName</key><string>Moonport</string>
    <key>CFBundleExecutable</key><string>Moonport</string>
    <key>CFBundleIdentifier</key><string>app.moonport</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleLocalizations</key><array><string>en</string><string>ru</string></array>
    <key>CFBundleName</key><string>Moonport</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${SHORT_VERSION}</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key><string>${MIN_MACOS}</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Moonport uses Apple events for two things: it reads your Login Items list via System Events, and — only when you confirm it in the app — it asks Finder to empty the Trash.</string>
    <key>NSDesktopFolderUsageDescription</key>
    <string>Moonport measures how much space your Desktop folder uses, for the "home folders" section of the report. It reads folder sizes only — file contents are never opened.</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>Moonport measures how much space your Documents folder uses, for the "home folders" section of the report. It reads folder sizes only — file contents are never opened.</string>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>Moonport measures how much space your Downloads folder uses, for the "home folders" section of the report. It reads folder sizes only — file contents are never opened.</string>
    <key>NSRemovableVolumesUsageDescription</key>
    <string>Moonport reports free space and Time Machine destinations for connected volumes, including removable disks. It reads volume sizes only — file contents are never opened.</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>The app reads your paired iPhone over the local network when “Connect over Wi-Fi” is on in Settings. Nothing is sent to the internet.</string>
    <key>NSHumanReadableCopyright</key><string>© 2026 rdskcm. MIT License.</string>
</dict>
</plist>
PLIST

# NSAppleEventsUsageDescription is ONE app-wide string: macOS shows the same text for the
# System Events prompt (login items) and the Finder prompt (empty Trash), so it must name
# both — including the destructive one. NSDesktopFolderUsageDescription,
# NSDocumentsFolderUsageDescription, NSDownloadsFolderUsageDescription,
# NSRemovableVolumesUsageDescription, and NSLocalNetworkUsageDescription follow the same
# three-place rule (Info.plist plus en/ru InfoPlist.strings), no shared source: keep all three in sync for each key.
echo "== localized InfoPlist.strings =="
mkdir -p "$DIST/Contents/Resources/en.lproj" "$DIST/Contents/Resources/ru.lproj"

cat > "$DIST/Contents/Resources/en.lproj/InfoPlist.strings" <<'EOSTRINGS'
NSHumanReadableCopyright = "© 2026 rdskcm. MIT License.";
NSAppleEventsUsageDescription = "Moonport uses Apple events for two things: it reads your Login Items list via System Events, and — only when you confirm it in the app — it asks Finder to empty the Trash.";
NSDesktopFolderUsageDescription = "Moonport measures how much space your Desktop folder uses, for the \"home folders\" section of the report. It reads folder sizes only — file contents are never opened.";
NSDocumentsFolderUsageDescription = "Moonport measures how much space your Documents folder uses, for the \"home folders\" section of the report. It reads folder sizes only — file contents are never opened.";
NSDownloadsFolderUsageDescription = "Moonport measures how much space your Downloads folder uses, for the \"home folders\" section of the report. It reads folder sizes only — file contents are never opened.";
NSRemovableVolumesUsageDescription = "Moonport reports free space and Time Machine destinations for connected volumes, including removable disks. It reads volume sizes only — file contents are never opened.";
NSLocalNetworkUsageDescription = "The app reads your paired iPhone over the local network when “Connect over Wi-Fi” is on in Settings. Nothing is sent to the internet.";
EOSTRINGS

cat > "$DIST/Contents/Resources/ru.lproj/InfoPlist.strings" <<'EOSTRINGS'
NSHumanReadableCopyright = "© 2026 rdskcm. Лицензия MIT.";
NSAppleEventsUsageDescription = "Moonport использует Apple events для двух задач: читает список объектов автозагрузки (Login Items) через System Events и — только после вашего подтверждения в приложении — просит Finder очистить Корзину.";
NSDesktopFolderUsageDescription = "Moonport измеряет, сколько места занимает папка «Рабочий стол», для раздела отчёта о папках домашней директории. Читаются только размеры папок — содержимое файлов не открывается.";
NSDocumentsFolderUsageDescription = "Moonport измеряет, сколько места занимает папка «Документы», для раздела отчёта о папках домашней директории. Читаются только размеры папок — содержимое файлов не открывается.";
NSDownloadsFolderUsageDescription = "Moonport измеряет, сколько места занимает папка «Загрузки», для раздела отчёта о папках домашней директории. Читаются только размеры папок — содержимое файлов не открывается.";
NSRemovableVolumesUsageDescription = "Moonport показывает свободное место и адреса резервных копий Time Machine для подключённых томов, включая съёмные диски. Читаются только размеры томов — содержимое файлов не открывается.";
NSLocalNetworkUsageDescription = "Moonport читает ваш сопряжённый iPhone по локальной сети, когда в Настройках включено «Подключение по Wi-Fi». В интернет ничего не отправляется.";
EOSTRINGS

echo "== icon (actool: Icon/AppIcon.icon -> Assets.car + AppIcon.icns) =="
# Icon/AppIcon.icon is an Icon Composer document (macOS 26 layered icon). actool compiles it
# into Assets.car (Default and Dark renditions, which the system picks from the appearance)
# and a flat light AppIcon.icns for Finder/QuickLook fallbacks. Its partial Info.plist carries
# CFBundleIconFile and CFBundleIconName, merged into the bundle's Info.plist below. Needs
# Xcode's actool only (no network); a failure stops the build instead of shipping no icon.
# Every path passed to actool is absolute: actool resolves relative ones against the working
# directory of an earlier actool run, not this one.
ICON_TMP="$(mktemp -d)"
trap 'rm -rf "$ICON_TMP"' EXIT
if ! xcrun actool "$PWD/Icon/AppIcon.icon" --platform macosx --minimum-deployment-target "$MIN_MACOS" \
     --app-icon AppIcon --output-format human-readable-text \
     --output-partial-info-plist "$ICON_TMP/partial.plist" --compile "$PWD/$DIST/Contents/Resources" \
     > "$ICON_TMP/actool.log" 2>&1; then
  cat "$ICON_TMP/actool.log" >&2
  echo "!! actool failed to compile Icon/AppIcon.icon" >&2
  exit 1
fi
/usr/libexec/PlistBuddy -c "Merge $ICON_TMP/partial.plist" "$DIST/Contents/Info.plist"
for f in Assets.car AppIcon.icns; do
  [ -s "$DIST/Contents/Resources/$f" ] || { echo "!! actool did not produce $f" >&2; exit 1; }
done
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$DIST/Contents/Info.plist")" = "AppIcon" ] \
  || { echo "!! CFBundleIconName is not AppIcon after the merge" >&2; exit 1; }
# The Dark rendition must come from the dark layers. If actool ignored the document's dark
# specializations it would still emit a system-generated dark icon, so check the layer images.
ICON_INFO="$(assetutil --info "$DIST/Contents/Resources/Assets.car")"
printf '%s' "$ICON_INFO" | grep -q 'AppIcon_Assets.*dark-' \
  || { echo "!! Assets.car has no dark icon layers — check Icon/AppIcon.icon/icon.json" >&2; exit 1; }
echo "icon OK"

echo "== codesign (hardened runtime) =="
# Signing identity. Local builds sign with the stable self-signed identity that
# tools/signing/make-identity.sh creates once per Mac. Its designated requirement names
# the certificate instead of the build's cdhash, so it is the same for every rebuild and
# macOS keeps this app's Full Disk Access / Automation grants across rebuilds. Without
# that identity (release CI, a fresh clone) the build is signed ad-hoc as before and says
# so loudly: an ad-hoc designated requirement is the cdhash, which changes whenever the
# code does. Release artifacts are ad-hoc by design (release.yml).
SIGN_CN="Moonport Local Signing"   # keep equal to CN in tools/signing/make-identity.sh
# Without -v: -v lists only identities with a TRUSTED certificate, and this one is
# deliberately not trusted (signing and designated-requirement checks do not need trust).
SIGN_HASHES="$({ security find-identity -p codesigning 2>/dev/null || true; } \
  | awk -v cn="\"$SIGN_CN\"" 'index($0, cn) { print $2 }' | sort -u)"
SIGN_COUNT="$(printf '%s' "$SIGN_HASHES" | grep -c . || true)"
if [ "$SIGN_COUNT" -gt 1 ]; then
  echo "!! $SIGN_COUNT code-signing identities named \"$SIGN_CN\" — codesign cannot pick one." >&2
  echo "!! Keep one: delete the others in Keychain Access (login > My Certificates). SHA-1s:" >&2
  printf '%s\n' "$SIGN_HASHES" >&2
  exit 1
elif [ "$SIGN_COUNT" -eq 1 ]; then
  SIGN_ID="$SIGN_HASHES"
  echo "signing identity: \"$SIGN_CN\" ($SIGN_ID)"
else
  SIGN_ID="-"
  echo "!! WARNING: no \"$SIGN_CN\" code-signing identity in the keychain — signing AD-HOC." >&2
  echo "!! macOS treats every ad-hoc rebuild with changed code as a new app: Full Disk Access" >&2
  echo "!! and Automation grants are lost. Fix, once per Mac: tools/signing/make-identity.sh" >&2
fi
# --options runtime: without the hardened runtime DYLD_INSERT_LIBRARIES is honoured
# and library validation is off, so any local process running as this user could
# inject into an app the README asks users to grant Full Disk Access and inherit its
# TCC grants. --entitlements: the hardened runtime blocks in-process Apple events
# (AdviceActionRunner.emptyTrash) unless com.apple.security.automation.apple-events
# is present.
# No --deep: Apple documents it as a testing convenience, and combined with
# --entitlements it would grant these entitlements to any nested code added later.
# Nested code, if ever added, must be signed explicitly.
# --timestamp=none: a self-signed signature gains nothing from a secure timestamp, and
# asking for one would make every build depend on Apple's timestamp server; no-op for ad-hoc.
codesign --force --options runtime --timestamp=none --entitlements Moonport.entitlements \
  --sign "$SIGN_ID" "$DIST"

echo "== result =="
# Fail-loud gate (V27-TOOLCHAIN): the binary must be arm64 only and record the SDK
# compiled against above and the deployment target. Runs before --install, so a
# wrong build is never installed.
FINAL_BIN="$DIST/Contents/MacOS/Moonport"
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
codesign -dvv "$DIST" 2>&1 | grep -E '^(Identifier|CodeDirectory|Signature|Authority)'
codesign -d -r- "$DIST" 2>&1 | grep 'designated =>' || true

if [ "$INSTALL" = "1" ]; then
  echo "== install to ~/Applications =="
  INSTALL_DIR="$HOME/Applications"
  mkdir -p "$INSTALL_DIR"
  # Swap through temporary names so that a failed move never leaves ~/Applications without the
  # app. The temporary names do not end in .app, so LaunchServices does not take them for
  # application bundles; the tools/ls-prune.sh run below drops any record that still names one.
  INSTALLED_APP="$INSTALL_DIR/$APP_NAME.app"
  NEW_APP="$INSTALL_DIR/.$APP_NAME.app.new"
  OLD_APP="$INSTALL_DIR/.$APP_NAME.app.old"
  # An --install interrupted between the two renames below left the previous app only at OLD_APP.
  if [ ! -e "$INSTALLED_APP" ] && [ -d "$OLD_APP" ]; then
    if ! mv "$OLD_APP" "$INSTALLED_APP"; then
      echo "!! could not restore the previous install from $OLD_APP to $INSTALLED_APP — nothing was installed and $OLD_APP was kept; the new build is still at $DIST. Move it back by hand, then run ./build_app.sh --install again" >&2
      exit 1
    fi
    echo "restored the previous install left at $OLD_APP by an interrupted --install"
  fi
  rm -rf "$NEW_APP" "$OLD_APP"
  # Moved, not copied: a second bundle with the same CFBundleIdentifier left in dist.noindex/ stays
  # registered with LaunchServices and can be the copy that opening by bundle ID launches
  # (APP-ID-DUPLICATES). A plain ./build_app.sh still leaves dist.noindex/ populated.
  if ! mv "$DIST" "$NEW_APP"; then
    rm -rf "$NEW_APP"
    echo "!! could not move $DIST into $INSTALL_DIR — the installed app is unchanged" >&2
    exit 1
  fi
  if [ -e "$INSTALLED_APP" ] && ! mv "$INSTALLED_APP" "$OLD_APP"; then
    NEW_BUILD_AT="$NEW_APP"
    if mv "$NEW_APP" "$DIST" 2>/dev/null; then NEW_BUILD_AT="$DIST"; fi
    echo "!! could not move $INSTALLED_APP aside — the installed app is unchanged; the new build is at $NEW_BUILD_AT" >&2
    exit 1
  fi
  if ! mv "$NEW_APP" "$INSTALLED_APP"; then
    PREVIOUS=none
    if [ -e "$OLD_APP" ]; then
      if mv "$OLD_APP" "$INSTALLED_APP"; then PREVIOUS=restored; else PREVIOUS=stranded; fi
    fi
    NEW_BUILD_AT="$NEW_APP"
    if mv "$NEW_APP" "$DIST" 2>/dev/null; then NEW_BUILD_AT="$DIST"; fi
    case "$PREVIOUS" in
      restored) echo "!! could not move the new build to $INSTALLED_APP — the previous install was put back; the new build is at $NEW_BUILD_AT" >&2 ;;
      none) echo "!! could not move the new build to $INSTALLED_APP — there was no previous install, so $INSTALLED_APP does not exist; the new build is at $NEW_BUILD_AT" >&2 ;;
      stranded) echo "!! could not move the new build to $INSTALLED_APP, and the previous install could not be put back: it is still at $OLD_APP and $INSTALLED_APP does not exist — move it back by hand. The new build is at $NEW_BUILD_AT" >&2 ;;
    esac
    exit 1
  fi
  rm -rf "$OLD_APP"
  echo "installed: $INSTALLED_APP"
  echo "== LaunchServices: installed copy only =="
  tools/ls-prune.sh || echo "!! tools/ls-prune.sh exited $? — other copies may still be registered" >&2
fi
echo "DONE"
