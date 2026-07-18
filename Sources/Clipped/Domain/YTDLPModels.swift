import Foundation

struct YTDLPMetadata: Decodable, Equatable, Sendable {
    let id: String
    let title: String
    let duration: Double?
    let webpageURL: String?
    let originalURL: String?
    let extractor: String?
    let extractorKey: String?
    let thumbnail: String?
    let liveStatus: String?
    let startTime: Double?
    let chapters: [YTDLPChapter]
    let formats: [YTDLPFormat]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case duration
        case webpageURL = "webpage_url"
        case originalURL = "original_url"
        case extractor
        case extractorKey = "extractor_key"
        case thumbnail
        case liveStatus = "live_status"
        case startTime = "start_time"
        case chapters
        case formats
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        webpageURL = try container.decodeIfPresent(String.self, forKey: .webpageURL)
        originalURL = try container.decodeIfPresent(String.self, forKey: .originalURL)
        extractor = try container.decodeIfPresent(String.self, forKey: .extractor)
        extractorKey = try container.decodeIfPresent(String.self, forKey: .extractorKey)
        thumbnail = try container.decodeIfPresent(String.self, forKey: .thumbnail)
        liveStatus = try container.decodeIfPresent(String.self, forKey: .liveStatus)
        startTime = try container.decodeIfPresent(Double.self, forKey: .startTime)
        chapters = try container.decodeIfPresent([YTDLPChapter].self, forKey: .chapters) ?? []
        formats = try container.decodeIfPresent([YTDLPFormat].self, forKey: .formats) ?? []
    }

    var isLive: Bool {
        liveStatus == "is_live" || liveStatus == "is_upcoming"
    }

    var isAudioOnly: Bool {
        !formats.contains(where: \.containsVideo)
    }

    func normalizedChapters(maximumSeconds: Int) -> [YTDLPChapter] {
        chapters.compactMap { chapter in
            guard chapter.startTime.isFinite,
                  chapter.startTime >= 0,
                  chapter.endTime?.isFinite != false else { return nil }
            let start = min(maximumSeconds, max(0, Int(chapter.startTime.rounded())))
            let rawEnd = chapter.endTime.map { Int($0.rounded()) }
            let end = rawEnd.map { min(maximumSeconds, max(start, $0)) }
            guard start < maximumSeconds else { return nil }
            return YTDLPChapter(title: chapter.title, startTime: Double(start), endTime: end.map(Double.init))
        }
        .sorted { $0.startTime < $1.startTime }
    }
}

struct YTDLPChapter: Decodable, Equatable, Sendable, Identifiable {
    let title: String?
    let startTime: Double
    let endTime: Double?

    var id: String { "\(startTime)-\(title ?? "")" }

    enum CodingKeys: String, CodingKey {
        case title
        case startTime = "start_time"
        case endTime = "end_time"
    }
}

struct YTDLPFormat: Decodable, Equatable, Hashable, Sendable, Identifiable {
    let formatID: String
    let format: String?
    let fileExtension: String?
    let protocolName: String?
    let videoCodec: String?
    let audioCodec: String?
    let width: Int?
    let height: Int?
    let fps: Double?
    let filesize: Int64?
    let filesizeApprox: Int64?
    let totalBitrate: Double?
    let videoBitrate: Double?
    let audioBitrate: Double?
    let audioSampleRate: Int?
    let audioChannels: Int?
    let language: String?
    let dynamicRange: String?
    let formatNote: String?
    let quality: Double?
    let preference: Double?
    let sourcePreference: Double?

    var id: String { formatID }

    enum CodingKeys: String, CodingKey {
        case formatID = "format_id"
        case format
        case fileExtension = "ext"
        case protocolName = "protocol"
        case videoCodec = "vcodec"
        case audioCodec = "acodec"
        case width
        case height
        case fps
        case filesize
        case filesizeApprox = "filesize_approx"
        case totalBitrate = "tbr"
        case videoBitrate = "vbr"
        case audioBitrate = "abr"
        case audioSampleRate = "asr"
        case audioChannels = "audio_channels"
        case language
        case dynamicRange = "dynamic_range"
        case formatNote = "format_note"
        case quality
        case preference
        case sourcePreference = "source_preference"
    }

    var containsVideo: Bool {
        guard let videoCodec else { return false }
        return videoCodec.lowercased() != "none"
    }

    var containsAudio: Bool {
        guard let audioCodec else { return false }
        return audioCodec.lowercased() != "none"
    }

    var estimatedBytes: Int64? {
        filesize ?? filesizeApprox
    }

    var isStoryboard: Bool {
        let note = formatNote?.lowercased() ?? ""
        let formatDescription = format?.lowercased() ?? ""
        let protocolDescription = protocolName?.lowercased() ?? ""
        return note.contains("storyboard")
            || formatDescription.contains("storyboard")
            || protocolDescription.contains("mhtml")
            || fileExtension?.lowercased() == "mhtml"
    }
}
