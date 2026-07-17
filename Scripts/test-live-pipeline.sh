#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

for tool in yt-dlp deno ffmpeg ffprobe; do
    test -x "$ROOT_DIR/Vendor/MediaTools/$tool"
done

xcodegen generate
xcodebuild \
    -project Clipped.xcodeproj \
    -scheme ClippedLivePipeline \
    -destination "platform=macOS,arch=arm64" \
    -derivedDataPath "$ROOT_DIR/build/DerivedData-Live" \
    -parallel-testing-enabled NO \
    -only-testing:ClippedTests/LivePipelineIntegrationTests \
    test
