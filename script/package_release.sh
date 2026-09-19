#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-0.1.0}"
BUILD_NUMBER="${2:-1}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid version" >&2; exit 1; }
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || { echo "Invalid build number" >&2; exit 1; }
[[ "$(uname -m)" == arm64 ]] || { echo "This script packages the arm64 release." >&2; exit 1; }

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
OUTPUT_DIR="$ROOT_DIR/dist/releases/v$VERSION"
APP_BUNDLE="$OUTPUT_DIR/ClipStack.app"
ASSET_NAME="ClipStack-$VERSION-macos-arm64"
mkdir -p "$OUTPUT_DIR"

swift build -c release --product ClipStack --force-resolved-versions
BUILD_DIR="$(swift build -c release --show-bin-path)"

# SwiftPM's native build system looks beside Bundle.main.bundleURL. A signed
# macOS app must instead keep resources under Contents/Resources. Adjust only
# generated build files, then rebuild the affected dependencies and executable.
python3 - "$BUILD_DIR" <<'PY'
from pathlib import Path
import sys
build = Path(sys.argv[1])
accessors = list(build.glob('*.build/DerivedSources/resource_bundle_accessor.swift'))
if not accessors:
    raise SystemExit('Missing SwiftPM resource accessors')
for path in accessors:
    source = path.read_text()
    old = 'Bundle.main.bundleURL.appendingPathComponent('
    new = '(Bundle.main.resourceURL ?? Bundle.main.bundleURL).appendingPathComponent('
    if old not in source and new not in source:
        raise SystemExit(f'Unexpected SwiftPM resource accessor: {path.name}')
    if old in source:
        path.write_text(source.replace(old, new))
PY
swift build -c release --product ClipStack --force-resolved-versions
if grep -R -F 'Bundle.main.bundleURL.appendingPathComponent(' "$BUILD_DIR"/*.build/DerivedSources/resource_bundle_accessor.swift; then
    echo "SwiftPM regenerated incompatible resource paths; refusing to package." >&2
    exit 1
fi

# Only replace the generated bundle inside this version's output directory.
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BUILD_DIR/ClipStack" "$APP_BUNDLE/Contents/MacOS/ClipStack"
chmod +x "$APP_BUNDLE/Contents/MacOS/ClipStack"
cp Resources/AppIcon.icns "$APP_BUNDLE/Contents/Resources/"
for resource in "$BUILD_DIR"/*.bundle; do
    ditto "$resource" "$APP_BUNDLE/Contents/Resources/$(basename "$resource")"
done

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>ClipStack</string>
  <key>CFBundleIdentifier</key><string>com.clipstack.ClipStack</string>
  <key>CFBundleName</key><string>ClipStack</string>
  <key>CFBundleDisplayName</key><string>ClipStack</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSAccessibilityUsageDescription</key><string>ClipStack 需要辅助功能权限来粘贴到其他应用。</string>
</dict>
</plist>
PLIST

plutil -lint "$APP_BUNDLE/Contents/Info.plist"
codesign --force --sign - --options runtime --timestamp=none "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$OUTPUT_DIR/$ASSET_NAME.zip"
DMG_STAGE="$(mktemp -d "$OUTPUT_DIR/.dmg-stage.XXXXXX")"
trap 'rm -rf "$DMG_STAGE"' EXIT
ditto "$APP_BUNDLE" "$DMG_STAGE/ClipStack.app"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create -volname "ClipStack $VERSION" -srcfolder "$DMG_STAGE" \
    -format UDZO -ov "$OUTPUT_DIR/$ASSET_NAME.dmg"
(
    cd "$OUTPUT_DIR"
    shasum -a 256 "$ASSET_NAME.dmg" "$ASSET_NAME.zip" > SHA256SUMS.txt
)
echo "Release assets: $OUTPUT_DIR"
