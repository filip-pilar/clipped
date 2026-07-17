#!/bin/bash

set -euo pipefail

SOURCE_DIR="$SRCROOT/Vendor/MediaTools"
DESTINATION_DIR="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers/MediaTools"
DOCUMENTATION_DIR="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/ThirdParty/MediaTools"
REQUIRED=(yt-dlp deno ffmpeg ffprobe)

for tool in "${REQUIRED[@]}"; do
    if [[ ! -x "$SOURCE_DIR/$tool" ]]; then
        if [[ "$CONFIGURATION" == "Release" ]]; then
            echo "error: Missing $SOURCE_DIR/$tool. Run Scripts/bootstrap-tools.sh before a Release build." >&2
            exit 1
        fi
        echo "warning: Bundled media tools are absent; Debug builds will use CLIPPED_TOOL_DIR or Homebrew." >&2
        exit 0
    fi
done

case "$DESTINATION_DIR" in
    "$TARGET_BUILD_DIR"/*/Helpers/MediaTools) ;;
    *)
        echo "error: Refusing unexpected media-tools destination: $DESTINATION_DIR" >&2
        exit 1
        ;;
esac

case "$DOCUMENTATION_DIR" in
    "$TARGET_BUILD_DIR"/*/Resources/ThirdParty/MediaTools) ;;
    *)
        echo "error: Refusing unexpected media-tools documentation destination: $DOCUMENTATION_DIR" >&2
        exit 1
        ;;
esac

rm -rf "$DESTINATION_DIR"
mkdir -p "$DESTINATION_DIR"

for tool in "${REQUIRED[@]}"; do
    install -m 755 "$SOURCE_DIR/$tool" "$DESTINATION_DIR/$tool"
    /usr/bin/codesign --force --sign - --timestamp=none "$DESTINATION_DIR/$tool"
done

rm -rf "$DOCUMENTATION_DIR"
mkdir -p "$DOCUMENTATION_DIR"
install -m 644 "$SOURCE_DIR/README.md" "$SOURCE_DIR/VERSIONS.txt" "$DOCUMENTATION_DIR"
/usr/bin/ditto "$SOURCE_DIR/Licenses" "$DOCUMENTATION_DIR/Licenses"
