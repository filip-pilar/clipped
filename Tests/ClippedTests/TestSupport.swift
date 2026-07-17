import Foundation
@testable import Clipped

actor TestProcessExecutor: ProcessExecuting {
    typealias Handler = @Sendable (
        ProcessCommand,
        @Sendable (ProcessOutputEvent) -> Void
    ) async throws -> ProcessResult

    private let handler: Handler
    private var commands: [ProcessCommand] = []

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func run(
        _ command: ProcessCommand,
        onEvent: @escaping @Sendable (ProcessOutputEvent) -> Void
    ) async throws -> ProcessResult {
        commands.append(command)
        return try await handler(command, onEvent)
    }

    func cancelAll() {}

    func recordedCommands() -> [ProcessCommand] {
        commands
    }
}

final class LockedRecorder<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Value] = []

    var values: [Value] {
        lock.withLock { storage }
    }

    func append(_ value: Value) {
        lock.withLock { storage.append(value) }
    }
}

enum TestFixtures {
    static let tools = ToolPaths(
        ytDLP: URL(fileURLWithPath: "/tools/yt-dlp"),
        deno: URL(fileURLWithPath: "/tools/deno"),
        ffmpeg: URL(fileURLWithPath: "/tools/ffmpeg"),
        ffprobe: URL(fileURLWithPath: "/tools/ffprobe")
    )

    static func loadedVideo(url: String = "https://example.com/video") throws -> LoadedMedia {
        let metadata = try JSONDecoder().decode(YTDLPMetadata.self, from: Data(videoMetadataJSON.utf8))
        return LoadedMedia(
            requestedURL: URL(string: url)!,
            metadata: metadata,
            catalog: FormatCatalog.build(from: metadata.formats)
        )
    }

    static let videoMetadataJSON = #"""
    {
      "id": "video-id",
      "title": "A / Source: Title",
      "duration": 100,
      "extractor_key": "Example",
      "formats": [
        {"format_id":"18","ext":"mp4","vcodec":"avc1.42001E","acodec":"mp4a.40.2","width":640,"height":360,"fps":30,"tbr":360,"audio_channels":2,"dynamic_range":"SDR"},
        {"format_id":"299","ext":"mp4","vcodec":"avc1.64002a","acodec":"none","width":1920,"height":1080,"fps":60,"vbr":3248,"dynamic_range":"SDR"},
        {"format_id":"258","ext":"m4a","vcodec":"none","acodec":"mp4a.40.2","abr":388,"asr":48000,"audio_channels":6}
      ]
    }
    """#

    static let acquisitionProbeJSON = #"""
    {
      "streams": [
        {"index":0,"codec_type":"video","codec_name":"h264","codec_tag_string":"avc1","width":1920,"height":1080,"pix_fmt":"yuv420p","r_frame_rate":"60/1"},
        {"index":1,"codec_type":"audio","codec_name":"aac","codec_tag_string":"mp4a","sample_rate":"48000","channels":6,"channel_layout":"5.1"}
      ],
      "format": {"duration":"3.05","format_name":"mov,mp4,m4a,3gp,3g2,mj2"}
    }
    """#

    static let normalizedProbeJSON = #"""
    {
      "streams": [
        {"index":0,"codec_type":"video","codec_name":"h264","codec_tag_string":"avc1","width":1920,"height":1080,"pix_fmt":"yuv420p","r_frame_rate":"60/1"},
        {"index":1,"codec_type":"audio","codec_name":"aac","codec_tag_string":"mp4a","sample_rate":"48000","channels":6,"channel_layout":"5.1"}
      ],
      "format": {"duration":"3.000000","format_name":"mov,mp4,m4a,3gp,3g2,mj2"}
    }
    """#
}
