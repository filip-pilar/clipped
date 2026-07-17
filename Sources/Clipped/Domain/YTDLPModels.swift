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
        case formats
    }

    var isLive: Bool {
        liveStatus == "is_live" || liveStatus == "is_upcoming"
    }

    var isAudioOnly: Bool {
        !formats.contains(where: \.containsVideo)
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
