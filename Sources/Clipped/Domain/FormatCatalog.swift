import Foundation

struct FormatCatalog: Equatable, Sendable {
    let videoChoices: [VideoQualityChoice]
    let audioChoices: [AudioQualityChoice]

    var isAudioOnly: Bool {
        videoChoices.isEmpty
    }

    var defaultVideoChoice: VideoQualityChoice? {
        videoChoices.first
    }

    var defaultAudioChoice: AudioQualityChoice? {
        audioChoices.first
    }

    static func build(from formats: [YTDLPFormat]) -> FormatCatalog {
        let usable = formats.filter { !$0.isStoryboard }
        let videoFormats = usable.filter { $0.containsVideo && $0.height != nil }
        let separateAudioFormats = usable.filter { $0.containsAudio && !$0.containsVideo }

        let groupedVideo = Dictionary(grouping: videoFormats, by: VideoGroupKey.init)
        let videoChoices = groupedVideo.values.compactMap { group -> VideoQualityChoice? in
            let videoOnly = group.filter { !$0.containsAudio }
            let candidates = videoOnly.isEmpty ? group : videoOnly
            guard let selected = candidates.max(by: isLowerQualityVideo) else { return nil }
            return VideoQualityChoice(format: selected)
        }
        .sorted(by: VideoQualityChoice.precedes)

        let audioPool = separateAudioFormats.isEmpty
            ? usable.filter { $0.containsAudio }
            : separateAudioFormats
        let groupedAudio = Dictionary(grouping: audioPool, by: AudioGroupKey.init)
        let audioChoices = groupedAudio.values.compactMap { group -> AudioQualityChoice? in
            guard let selected = group.max(by: isLowerQualityAudio) else { return nil }
            return AudioQualityChoice(format: selected)
        }
        .sorted(by: AudioQualityChoice.precedes)

        return FormatCatalog(videoChoices: videoChoices, audioChoices: audioChoices)
    }

    private static func isLowerQualityVideo(_ lhs: YTDLPFormat, _ rhs: YTDLPFormat) -> Bool {
        let lhsCodec = CodecName.videoPreference(lhs.videoCodec)
        let rhsCodec = CodecName.videoPreference(rhs.videoCodec)
        if lhsCodec != rhsCodec { return lhsCodec < rhsCodec }

        let lhsContainer = lhs.fileExtension?.lowercased() == "mp4" ? 1 : 0
        let rhsContainer = rhs.fileExtension?.lowercased() == "mp4" ? 1 : 0
        if lhsContainer != rhsContainer { return lhsContainer < rhsContainer }

        let lhsQuality = lhs.quality ?? -.infinity
        let rhsQuality = rhs.quality ?? -.infinity
        if lhsQuality != rhsQuality { return lhsQuality < rhsQuality }

        return (lhs.videoBitrate ?? lhs.totalBitrate ?? 0) < (rhs.videoBitrate ?? rhs.totalBitrate ?? 0)
    }

    private static func isLowerQualityAudio(_ lhs: YTDLPFormat, _ rhs: YTDLPFormat) -> Bool {
        let lhsChannels = lhs.audioChannels ?? 0
        let rhsChannels = rhs.audioChannels ?? 0
        if lhsChannels != rhsChannels { return lhsChannels < rhsChannels }

        let lhsBitrate = lhs.audioBitrate ?? lhs.totalBitrate ?? 0
        let rhsBitrate = rhs.audioBitrate ?? rhs.totalBitrate ?? 0
        if lhsBitrate != rhsBitrate { return lhsBitrate < rhsBitrate }

        return CodecName.audioPreference(lhs.audioCodec) < CodecName.audioPreference(rhs.audioCodec)
    }
}

struct VideoQualityChoice: Identifiable, Equatable, Hashable, Sendable {
    let formatID: String
    let width: Int?
    let height: Int
    let framesPerSecond: Double?
    let codec: String
    let container: String
    let dynamicRange: String
    let estimatedBytes: Int64?
    let estimatedKilobitsPerSecond: Double?
    let hasEmbeddedAudio: Bool
    let embeddedAudioChannels: Int?

    var id: String { formatID }

    init(format: YTDLPFormat) {
        formatID = format.formatID
        width = format.width
        height = format.height ?? 0
        framesPerSecond = format.fps
        codec = CodecName.video(format.videoCodec)
        container = (format.fileExtension ?? "unknown").uppercased()
        dynamicRange = FormatText.dynamicRange(format.dynamicRange)
        estimatedBytes = format.estimatedBytes
        estimatedKilobitsPerSecond = format.videoBitrate ?? format.totalBitrate
        hasEmbeddedAudio = format.containsAudio
        embeddedAudioChannels = format.containsAudio ? format.audioChannels : nil
    }

    var primaryLabel: String {
        var components = [FormatText.resolution(height: height)]
        if let framesPerSecond, framesPerSecond > 0 {
            components.append("\(FormatText.number(framesPerSecond)) fps")
        }
        return components.joined(separator: " · ")
    }

    var detailLabel: String {
        var components = [codec, container]
        if dynamicRange != "SDR" {
            components.append(dynamicRange)
        }
        if let estimatedBytes {
            components.append("~\(FormatText.bytes(estimatedBytes))")
        }
        return components.joined(separator: " · ")
    }

    static func precedes(_ lhs: VideoQualityChoice, _ rhs: VideoQualityChoice) -> Bool {
        if lhs.height != rhs.height { return lhs.height > rhs.height }
        let lhsFPS = lhs.framesPerSecond ?? 0
        let rhsFPS = rhs.framesPerSecond ?? 0
        if lhsFPS != rhsFPS { return lhsFPS > rhsFPS }
        if lhs.dynamicRange != rhs.dynamicRange { return lhs.dynamicRange == "SDR" }
        return lhs.formatID.localizedStandardCompare(rhs.formatID) == .orderedAscending
    }
}

struct AudioQualityChoice: Identifiable, Equatable, Hashable, Sendable {
    let formatID: String
    let codec: String
    let container: String
    let bitrate: Double?
    let sampleRate: Int?
    let channels: Int?
    let language: String?
    let estimatedBytes: Int64?
    let isSeparateAudio: Bool

    var id: String { formatID }

    init(format: YTDLPFormat) {
        formatID = format.formatID
        codec = CodecName.audio(format.audioCodec)
        container = (format.fileExtension ?? "unknown").uppercased()
        bitrate = format.audioBitrate ?? format.totalBitrate
        sampleRate = format.audioSampleRate
        channels = format.audioChannels
        language = format.language
        estimatedBytes = format.estimatedBytes
        isSeparateAudio = !format.containsVideo
    }

    var primaryLabel: String {
        var components: [String] = []
        if let language, !language.isEmpty {
            components.append(Locale.current.localizedString(forLanguageCode: language) ?? language.uppercased())
        }
        components.append(FormatText.channels(channels))
        if let bitrate, bitrate > 0 {
            components.append("\(Int(bitrate.rounded())) kbps")
        }
        return components.joined(separator: " · ")
    }

    var detailLabel: String {
        var components = [codec, container]
        if let estimatedBytes {
            components.append("~\(FormatText.bytes(estimatedBytes))")
        }
        return components.joined(separator: " · ")
    }

    static func precedes(_ lhs: AudioQualityChoice, _ rhs: AudioQualityChoice) -> Bool {
        let lhsChannels = lhs.channels ?? 0
        let rhsChannels = rhs.channels ?? 0
        if lhsChannels != rhsChannels { return lhsChannels > rhsChannels }
        let lhsBitrate = lhs.bitrate ?? 0
        let rhsBitrate = rhs.bitrate ?? 0
        if lhsBitrate != rhsBitrate { return lhsBitrate > rhsBitrate }
        return lhs.formatID.localizedStandardCompare(rhs.formatID) == .orderedAscending
    }
}

private struct VideoGroupKey: Hashable {
    let width: Int
    let height: Int
    let fps: Int
    let dynamicRange: String

    init(_ format: YTDLPFormat) {
        width = format.width ?? 0
        height = format.height ?? 0
        fps = Int((format.fps ?? 0).rounded())
        dynamicRange = FormatText.dynamicRange(format.dynamicRange)
    }
}

private struct AudioGroupKey: Hashable {
    let language: String
    let channels: Int
    let codec: String
    let roundedBitrate: Int

    init(_ format: YTDLPFormat) {
        language = format.language?.lowercased() ?? ""
        channels = format.audioChannels ?? 0
        codec = CodecName.audio(format.audioCodec)
        roundedBitrate = Int((format.audioBitrate ?? format.totalBitrate ?? 0).rounded())
    }
}

enum CodecName {
    static func video(_ raw: String?) -> String {
        let value = raw?.lowercased() ?? ""
        if value.hasPrefix("avc1") || value.contains("h264") { return "H.264" }
        if value.hasPrefix("hvc1") || value.hasPrefix("hev1") || value.contains("hevc") { return "HEVC" }
        if value.hasPrefix("vp09") || value.contains("vp9") { return "VP9" }
        if value.hasPrefix("av01") || value == "av1" { return "AV1" }
        return raw?.uppercased() ?? "Unknown video"
    }

    static func audio(_ raw: String?) -> String {
        let value = raw?.lowercased() ?? ""
        if value.hasPrefix("mp4a") || value.contains("aac") { return "AAC" }
        if value.contains("opus") { return "Opus" }
        if value.contains("vorbis") { return "Vorbis" }
        if value.contains("mp3") { return "MP3" }
        return raw?.uppercased() ?? "Unknown audio"
    }

    static func videoPreference(_ raw: String?) -> Int {
        switch video(raw) {
        case "H.264": 4
        case "HEVC": 3
        case "VP9": 2
        case "AV1": 1
        default: 0
        }
    }

    static func audioPreference(_ raw: String?) -> Int {
        switch audio(raw) {
        case "AAC": 3
        case "Opus": 2
        case "Vorbis": 1
        default: 0
        }
    }
}

enum FormatText {
    static func resolution(height: Int) -> String {
        switch height {
        case 2160: "2160p (4K)"
        case 1440: "1440p"
        case 1080: "1080p"
        case 720: "720p"
        case 480: "480p"
        case 360: "360p"
        case 240: "240p"
        case 144: "144p"
        default: "\(height)p"
        }
    }

    static func dynamicRange(_ raw: String?) -> String {
        let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value!.uppercased() : "SDR"
    }

    static func number(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
    }

    static func channels(_ count: Int?) -> String {
        switch count {
        case 1: "Mono"
        case 2: "Stereo"
        case 6: "5.1"
        case 8: "7.1"
        case .some(let count): "\(count) channels"
        case nil: "Audio"
        }
    }

    static func bytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: bytes)
    }
}
