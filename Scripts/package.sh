#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/build/DerivedData-Release"
PRODUCTS_DIR="$DERIVED_DATA/Build/Products/Release"
APP_PATH="$PRODUCTS_DIR/Clipped.app"
DIST_DIR="$ROOT_DIR/build/Distribution"
ZIP_PATH="$DIST_DIR/Clipped-apple-silicon.zip"

for tool in yt-dlp deno ffmpeg ffprobe; do
    if [[ ! -x "$ROOT_DIR/Vendor/MediaTools/$tool" ]]; then
        echo "Missing bundled tool $tool. Run Scripts/bootstrap-tools.sh first." >&2
        exit 1
    fi
done

cd "$ROOT_DIR"
xcodegen generate
xcodebuild \
    -project Clipped.xcodeproj \
    -scheme Clipped \
    -configuration Release \
    -destination "platform=macOS,arch=arm64" \
    -derivedDataPath "$DERIVED_DATA" \
    build

for tool in yt-dlp deno ffmpeg ffprobe; do
    test -x "$APP_PATH/Contents/Helpers/MediaTools/$tool"
done

test -f "$APP_PATH/Contents/Resources/AppIcon.icns"
test -f "$APP_PATH/Contents/Resources/Assets.car"
test -f "$APP_PATH/Contents/Resources/ThirdPartyNotices.md"
test -f "$APP_PATH/Contents/Resources/ThirdParty/MediaTools/VERSIONS.txt"
test "$(find "$APP_PATH/Contents/Helpers/MediaTools" -maxdepth 1 -type f | wc -l | tr -d ' ')" = "4"
test "$(lipo -archs "$APP_PATH/Contents/MacOS/Clipped")" = "arm64"
test "$(plutil -extract LSMinimumSystemVersion raw -o - "$APP_PATH/Contents/Info.plist")" = "15.0"
test "$(plutil -extract CFBundleIconFile raw -o - "$APP_PATH/Contents/Info.plist")" = "AppIcon"
if /usr/bin/codesign -d --entitlements - "$APP_PATH" 2>&1 | grep -q "get-task-allow"; then
    echo "Release app unexpectedly contains get-task-allow." >&2
    exit 1
fi

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"
mkdir -p "$DIST_DIR"
rm -f "$ZIP_PATH" "$ZIP_PATH.sha256"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
shasum -a 256 "$ZIP_PATH" > "$ZIP_PATH.sha256"
unzip -tq "$ZIP_PATH"

echo "Package: $ZIP_PATH"
echo "Checksum: $(cat "$ZIP_PATH.sha256")"
