# Clipped

Clipped is a minimal native macOS app for turning timestamp ranges from an
online video or audio source into separate editing-ready files. The product name
is provisional.

Paste one URL, choose any qualities exposed by that source, select one or more
ranges with the player, timeline, or timecode fields, and download. Video output
is H.264/AAC MP4; audio-only output is AAC M4A. Files are written to Downloads.

## Requirements

- Apple Silicon Mac
- macOS 15 or newer
- Xcode 26 or newer
- XcodeGen 2.45 or newer
- Command Line Tools selected in Xcode

## Build

Prepare the pinned, self-contained media toolchain. FFmpeg is compiled locally
with an LGPL configuration and a macOS 15 deployment target:

```sh
Scripts/bootstrap-tools.sh
```

Generate and open the project:

```sh
xcodegen generate
open Clipped.xcodeproj
```

Debug builds can alternatively locate tools through `CLIPPED_TOOL_DIR` or
Homebrew. Release builds require all four binaries in `Vendor/MediaTools`.

## Test

Run the deterministic unit and UI suites:

```sh
Scripts/test.sh
```

Run the opt-in live test against a public source using the bundled toolchain:

```sh
Scripts/test-live-pipeline.sh
```

The live test downloads a three-second range and performs a real VideoToolbox
H.264/AAC conversion and ffprobe validation.

## Package for sharing

```sh
Scripts/package.sh
```

The unsigned Apple Silicon archive and SHA-256 checksum are written to
`build/Distribution`. Recipients can move Clipped to Applications. Because it is
not Developer ID signed or notarized, macOS may require Control-click → Open on
first launch. If Gatekeeper still refuses it, a trusted recipient can remove the
download quarantine attribute:

```sh
xattr -dr com.apple.quarantine /Applications/Clipped.app
```

## Bundled components

- yt-dlp 2026.07.04
- Deno 2.9.3
- FFmpeg / ffprobe 8.1.2, LGPL configuration

`Scripts/bootstrap-tools.sh` verifies pinned SHA-256 values before installation.
Exact source links, build flags, and license texts are included in each packaged app.
