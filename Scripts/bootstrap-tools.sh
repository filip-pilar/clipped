#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$ROOT_DIR/build/ToolchainWork"
DOWNLOAD_DIR="$WORK_DIR/downloads"
VENDOR_DIR="$ROOT_DIR/Vendor/MediaTools"
LICENSE_DIR="$VENDOR_DIR/Licenses"

YT_DLP_VERSION="2026.07.04"
YT_DLP_SHA256="498bd0dae17855c599d371d68ec5bafc439a9d8640e838be25c765a9792f261b"
DENO_VERSION="2.9.3"
DENO_SHA256="1b2972f7ceb6df28d9600eab18d423bebb9aa18db02f01d7eb37a5b501482203"
FFMPEG_VERSION="8.1.2"
FFMPEG_SHA256="464beb5e7bf0c311e68b45ae2f04e9cc2af88851abb4082231742a74d97b524c"

FORCE_BUILD=0
if [[ "${1:-}" == "--force" ]]; then
    FORCE_BUILD=1
elif [[ $# -gt 0 ]]; then
    echo "Usage: $0 [--force]" >&2
    exit 2
fi

if [[ "$(uname -m)" != "arm64" ]]; then
    echo "Clipped's media tools must be built on an Apple Silicon Mac." >&2
    exit 1
fi

for command in curl shasum tar unzip make xcrun lipo otool codesign install strip; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "Missing required command: $command" >&2
        exit 1
    fi
done

mkdir -p "$DOWNLOAD_DIR" "$VENDOR_DIR" "$LICENSE_DIR"

download_verified() {
    local url="$1"
    local expected="$2"
    local destination="$3"

    if [[ -f "$destination" ]] && [[ "$(shasum -a 256 "$destination" | awk '{print $1}')" == "$expected" ]]; then
        return
    fi

    local temporary="$destination.part"
    rm -f "$temporary"
    curl -fL --retry 3 --retry-delay 2 "$url" -o "$temporary"
    local actual
    actual="$(shasum -a 256 "$temporary" | awk '{print $1}')"
    if [[ "$actual" != "$expected" ]]; then
        rm -f "$temporary"
        echo "Checksum mismatch for $(basename "$destination"): expected $expected, got $actual" >&2
        exit 1
    fi
    mv "$temporary" "$destination"
}

YT_DLP_DOWNLOAD="$DOWNLOAD_DIR/yt-dlp_macos-$YT_DLP_VERSION"
DENO_DOWNLOAD="$DOWNLOAD_DIR/deno-aarch64-apple-darwin-$DENO_VERSION.zip"
FFMPEG_DOWNLOAD="$DOWNLOAD_DIR/ffmpeg-$FFMPEG_VERSION.tar.xz"

download_verified \
    "https://github.com/yt-dlp/yt-dlp/releases/download/$YT_DLP_VERSION/yt-dlp_macos" \
    "$YT_DLP_SHA256" \
    "$YT_DLP_DOWNLOAD"
download_verified \
    "https://github.com/denoland/deno/releases/download/v$DENO_VERSION/deno-aarch64-apple-darwin.zip" \
    "$DENO_SHA256" \
    "$DENO_DOWNLOAD"
download_verified \
    "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz" \
    "$FFMPEG_SHA256" \
    "$FFMPEG_DOWNLOAD"

YT_DLP_UNIVERSAL="$WORK_DIR/yt-dlp-universal-$YT_DLP_VERSION"
install -m 755 "$YT_DLP_DOWNLOAD" "$YT_DLP_UNIVERSAL"
lipo -thin arm64 "$YT_DLP_UNIVERSAL" -output "$VENDOR_DIR/yt-dlp"
chmod 755 "$VENDOR_DIR/yt-dlp"

DENO_EXTRACT_DIR="$WORK_DIR/deno-$DENO_VERSION"
rm -rf "$DENO_EXTRACT_DIR"
mkdir -p "$DENO_EXTRACT_DIR"
unzip -q "$DENO_DOWNLOAD" -d "$DENO_EXTRACT_DIR"
install -m 755 "$DENO_EXTRACT_DIR/deno" "$VENDOR_DIR/deno"

FFMPEG_SOURCE_DIR="$WORK_DIR/ffmpeg-$FFMPEG_VERSION"
FFMPEG_INSTALL_DIR="$WORK_DIR/ffmpeg-install-$FFMPEG_VERSION"
REBUILD_FFMPEG=$FORCE_BUILD
if [[ ! -x "$VENDOR_DIR/ffmpeg" ]] || [[ ! -x "$VENDOR_DIR/ffprobe" ]]; then
    REBUILD_FFMPEG=1
elif ! "$VENDOR_DIR/ffmpeg" -version 2>/dev/null | head -1 | grep -q "ffmpeg version $FFMPEG_VERSION"; then
    REBUILD_FFMPEG=1
fi

if [[ $REBUILD_FFMPEG -eq 1 ]]; then
    rm -rf "$FFMPEG_SOURCE_DIR" "$FFMPEG_INSTALL_DIR"
    tar -xf "$FFMPEG_DOWNLOAD" -C "$WORK_DIR"
    mkdir -p "$FFMPEG_INSTALL_DIR"

    export MACOSX_DEPLOYMENT_TARGET=15.0
    SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
    pushd "$FFMPEG_SOURCE_DIR" >/dev/null
    ./configure \
        --prefix="$FFMPEG_INSTALL_DIR" \
        --arch=arm64 \
        --target-os=darwin \
        --sysroot="$SDK_PATH" \
        --cc="$(xcrun --find clang)" \
        --host-cc="$(xcrun --find clang)" \
        --host-cflags="--sysroot=$SDK_PATH" \
        --host-ldflags="--sysroot=$SDK_PATH" \
        --extra-cflags="-mmacosx-version-min=15.0" \
        --extra-ldflags="-mmacosx-version-min=15.0 -liconv" \
        --disable-debug \
        --disable-doc \
        --disable-ffplay \
        --disable-shared \
        --enable-static \
        --disable-autodetect \
        --enable-zlib \
        --enable-bzlib \
        --enable-iconv \
        --enable-videotoolbox \
        --enable-audiotoolbox \
        --enable-securetransport \
        --disable-gpl \
        --disable-nonfree
    JOBS="$(sysctl -n hw.logicalcpu 2>/dev/null || echo 4)"
    make -j "$JOBS"
    make install
    popd >/dev/null

    install -m 755 "$FFMPEG_INSTALL_DIR/bin/ffmpeg" "$VENDOR_DIR/ffmpeg"
    install -m 755 "$FFMPEG_INSTALL_DIR/bin/ffprobe" "$VENDOR_DIR/ffprobe"
    strip -x "$VENDOR_DIR/ffmpeg" "$VENDOR_DIR/ffprobe"
fi

if [[ ! -d "$FFMPEG_SOURCE_DIR" ]]; then
    tar -xf "$FFMPEG_DOWNLOAD" -C "$WORK_DIR"
fi

cp "$FFMPEG_SOURCE_DIR/COPYING.LGPLv2.1" "$LICENSE_DIR/FFmpeg-LGPL-2.1.txt"
cp "$FFMPEG_SOURCE_DIR/COPYING.LGPLv3" "$LICENSE_DIR/FFmpeg-LGPL-3.0.txt"
curl -fL --retry 3 "https://raw.githubusercontent.com/denoland/deno/v$DENO_VERSION/LICENSE.md" -o "$LICENSE_DIR/Deno-MIT.md"
curl -fL --retry 3 "https://raw.githubusercontent.com/yt-dlp/yt-dlp/$YT_DLP_VERSION/LICENSE" -o "$LICENSE_DIR/yt-dlp-Unlicense.txt"
curl -fL --retry 3 "https://raw.githubusercontent.com/yt-dlp/yt-dlp/$YT_DLP_VERSION/THIRD_PARTY_LICENSES.txt" -o "$LICENSE_DIR/yt-dlp-Third-Party.txt"

for tool in yt-dlp deno ffmpeg ffprobe; do
    if ! lipo -archs "$VENDOR_DIR/$tool" | grep -qw arm64; then
        echo "$tool does not contain an arm64 executable." >&2
        exit 1
    fi
    if otool -L "$VENDOR_DIR/$tool" | awk '/^\t/ { print $1 }' | grep -Ev '^(/usr/lib/|/System/Library/)' >/dev/null; then
        echo "$tool has a non-system dynamic dependency:" >&2
        otool -L "$VENDOR_DIR/$tool" >&2
        exit 1
    fi
    codesign --force --sign - --timestamp=none "$VENDOR_DIR/$tool"
done

cat > "$VENDOR_DIR/VERSIONS.txt" <<EOF
Clipped media toolchain

yt-dlp $YT_DLP_VERSION
SHA-256: $YT_DLP_SHA256
Source: https://github.com/yt-dlp/yt-dlp/releases/tag/$YT_DLP_VERSION

Deno $DENO_VERSION (aarch64-apple-darwin)
SHA-256: $DENO_SHA256
Source: https://github.com/denoland/deno/releases/tag/v$DENO_VERSION

FFmpeg $FFMPEG_VERSION (arm64, macOS 15 deployment target, LGPL configuration)
SHA-256: $FFMPEG_SHA256
Source: https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz
Configure: --disable-debug --disable-doc --disable-ffplay --disable-shared --enable-static --disable-autodetect --enable-zlib --enable-bzlib --enable-iconv --enable-videotoolbox --enable-audiotoolbox --enable-securetransport --disable-gpl --disable-nonfree
EOF

echo "Media tools are ready in $VENDOR_DIR"
