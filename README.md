# Clipped

Clipped is a minimal native macOS app for turning timestamp ranges from an
online video or audio source into separate editing-ready files. The product name
is provisional.

Paste one URL, choose any qualities exposed by that source, select one or more
ranges with the player, timeline, or timecode fields, and download. Video output
is H.264/AAC MP4; audio-only output is AAC M4A. Files are written to Downloads.

## Download and try it

The [v0.1.0 public preview](https://github.com/filip-pilar/clipped/releases/tag/v0.1.0)
runs on **Apple Silicon Macs with macOS 15 or newer**. You do not need Xcode or
developer tools to use the packaged app.

1. [Download Clipped for Apple Silicon](https://github.com/filip-pilar/clipped/releases/download/v0.1.0/Clipped-apple-silicon.zip).
2. Unzip it and move `Clipped.app` to Applications.
3. On first launch, Control-click the app and choose **Open**.

The preview is not notarized by Apple. If macOS blocks it, review the warning
and use **System Settings → Privacy & Security → Open Anyway** only if you trust
the download.

### Make your first clip

1. Paste a video or audio URL.
2. Choose an available quality or audio-only output.
3. Select one or more ranges with the player, timeline, or timecode fields.
4. Download the clips and find the resulting MP4 or M4A files in Downloads.

Want to build or contribute? Continue with the requirements below.

## Requirements

These requirements are for building from source:

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

Run the deterministic unit suite:

```sh
Scripts/test.sh
```

Run the interface smoke tests separately:

```sh
Scripts/test-ui.sh
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
