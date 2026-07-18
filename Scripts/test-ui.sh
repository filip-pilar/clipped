#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

xcodegen generate
xcodebuild \
    -project Clipped.xcodeproj \
    -scheme Clipped \
    -destination "platform=macOS,arch=arm64" \
    -derivedDataPath "$ROOT_DIR/build/DerivedData" \
    -parallel-testing-enabled NO \
    -only-testing:ClippedUITests \
    test
