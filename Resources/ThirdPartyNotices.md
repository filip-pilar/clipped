# Third-party components

Clipped invokes the following bundled executables as separate processes:

- **yt-dlp 2026.07.04**, distributed under the Unlicense, with bundled
  dependencies covered by the notices in `yt-dlp-Third-Party.txt`.
- **Deno 2.9.3**, distributed under the MIT License.
- **FFmpeg 8.1.2**, built without GPL or non-free components and distributed
  under the GNU Lesser General Public License. Clipped does not link to FFmpeg;
  it invokes the `ffmpeg` and `ffprobe` command-line executables.

Exact source URLs, SHA-256 checksums, license texts, and the FFmpeg configure
flags are included in
`Clipped.app/Contents/Resources/ThirdParty/MediaTools`.
