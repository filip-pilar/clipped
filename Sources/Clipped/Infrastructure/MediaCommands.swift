import Foundation

enum MediaCommands {
    static func metadata(sourceURL: URL, tools: ToolPaths) -> ProcessCommand {
        ProcessCommand(
            executableURL: tools.ytDLP,
            arguments: tools.commonYTDLPArguments + [
                "--skip-download",
                "--dump-single-json",
                "--",
                sourceURL.absoluteString
            ]
        )
    }

    static func previewDownload(
        sourceURL: URL,
        selector: String,
        outputTemplate: URL,
        tools: ToolPaths
    ) -> ProcessCommand {
        ProcessCommand(
            executableURL: tools.ytDLP,
            arguments: tools.commonYTDLPArguments + [
                "--force-overwrites",
                "--newline",
                "--progress-template",
                "download:CLIPPED_PROGRESS|%(progress.downloaded_bytes)s|%(progress.total_bytes,progress.total_bytes_estimate)s|%(progress.eta)s",
                "--print", "after_move:CLIPPED_FILE:%(filepath)s",
                "--format", selector,
                "--output", outputTemplate.path,
                "--",
                sourceURL.absoluteString
            ]
        )
    }

    static func rangedDownload(
        sourceURL: URL,
        selector: String,
        range: ClipRange,
        outputTemplate: URL,
        tools: ToolPaths
    ) -> ProcessCommand {
        ProcessCommand(
            executableURL: tools.ytDLP,
            arguments: tools.commonYTDLPArguments + [
                "--force-overwrites",
                "--newline",
                "--progress-template",
                "download:CLIPPED_PROGRESS|%(progress.downloaded_bytes)s|%(progress.total_bytes,progress.total_bytes_estimate)s|%(progress.eta)s",
                "--format", selector,
                "--download-sections", "*\(range.startSeconds)-\(range.endSeconds)",
                "--output", outputTemplate.path,
                "--",
                sourceURL.absoluteString
            ]
        )
    }

    static func normalizedVideo(
        input: URL,
        output: URL,
        durationSeconds: Int,
        audioBitrateKilobits: Int = 192,
        quality: Int = 75,
        tools: ToolPaths
    ) -> ProcessCommand {
        ProcessCommand(
            executableURL: tools.ffmpeg,
            arguments: [
                "-hide_banner", "-nostdin", "-y",
                "-i", input.path,
                "-t", String(durationSeconds),
                "-map", "0:v:0",
                "-map", "0:a:0?",
                "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2",
                "-c:v", "h264_videotoolbox",
                "-allow_sw", "1",
                "-profile:v", "high",
                "-q:v", String(quality),
                "-pix_fmt", "yuv420p",
                "-fps_mode", "passthrough",
                "-c:a", "aac",
                "-b:a", "\(audioBitrateKilobits)k",
                "-movflags", "+faststart",
                "-avoid_negative_ts", "make_zero",
                "-progress", "pipe:1",
                "-nostats",
                output.path
            ]
        )
    }

    static func normalizedAudio(
        input: URL,
        output: URL,
        durationSeconds: Int,
        audioBitrateKilobits: Int = 192,
        tools: ToolPaths
    ) -> ProcessCommand {
        ProcessCommand(
            executableURL: tools.ffmpeg,
            arguments: [
                "-hide_banner", "-nostdin", "-y",
                "-i", input.path,
                "-t", String(durationSeconds),
                "-vn",
                "-map", "0:a:0",
                "-c:a", "aac",
                "-b:a", "\(audioBitrateKilobits)k",
                "-movflags", "+faststart",
                "-avoid_negative_ts", "make_zero",
                "-progress", "pipe:1",
                "-nostats",
                output.path
            ]
        )
    }

    static func normalizedPreviewVideo(
        input: URL,
        output: URL,
        audioBitrateKilobits: Int = 128,
        quality: Int = 55,
        tools: ToolPaths
    ) -> ProcessCommand {
        ProcessCommand(
            executableURL: tools.ffmpeg,
            arguments: [
                "-hide_banner", "-nostdin", "-y",
                "-i", input.path,
                "-map", "0:v:0",
                "-map", "0:a:0?",
                "-vf", "scale=w='min(854,iw)':h=-2",
                "-c:v", "h264_videotoolbox",
                "-allow_sw", "1",
                "-profile:v", "high",
                "-q:v", String(quality),
                "-pix_fmt", "yuv420p",
                "-c:a", "aac",
                "-b:a", "\(audioBitrateKilobits)k",
                "-movflags", "+faststart",
                "-avoid_negative_ts", "make_zero",
                "-progress", "pipe:1",
                "-nostats",
                output.path
            ]
        )
    }

    static func normalizedPreviewAudio(
        input: URL,
        output: URL,
        audioBitrateKilobits: Int = 128,
        tools: ToolPaths
    ) -> ProcessCommand {
        ProcessCommand(
            executableURL: tools.ffmpeg,
            arguments: [
                "-hide_banner", "-nostdin", "-y",
                "-i", input.path,
                "-vn",
                "-map", "0:a:0",
                "-c:a", "aac",
                "-b:a", "\(audioBitrateKilobits)k",
                "-movflags", "+faststart",
                "-avoid_negative_ts", "make_zero",
                "-progress", "pipe:1",
                "-nostats",
                output.path
            ]
        )
    }

    static func probe(input: URL, tools: ToolPaths) -> ProcessCommand {
        ProcessCommand(
            executableURL: tools.ffprobe,
            arguments: [
                "-v", "error",
                "-show_entries", "format=duration,format_name:stream=index,codec_type,codec_name,codec_tag_string,width,height,pix_fmt,r_frame_rate,sample_rate,channels,channel_layout",
                "-of", "json",
                input.path
            ]
        )
    }
}
