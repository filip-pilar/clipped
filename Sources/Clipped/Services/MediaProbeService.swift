import Foundation

struct ProbedMedia: Equatable, Sendable {
    let duration: Double?
    let formatNames: [String]
    let streams: [ProbedStream]

    var videoStream: ProbedStream? {
        streams.first(where: { $0.codecType == "video" })
    }

    var audioStream: ProbedStream? {
        streams.first(where: { $0.codecType == "audio" })
    }
}

struct ProbedStream: Equatable, Sendable {
    let index: Int
    let codecType: String
    let codecName: String?
    let codecTag: String?
    let width: Int?
    let height: Int?
    let pixelFormat: String?
    let frameRate: String?
    let sampleRate: Int?
    let channels: Int?
    let channelLayout: String?
}

struct MediaProbeService: Sendable {
    let tools: ToolPaths
    let processRunner: any ProcessExecuting

    func inspect(_ url: URL) async throws -> ProbedMedia {
        let result = try await processRunner.run(MediaCommands.probe(input: url, tools: tools))
        guard result.succeeded else {
            throw MediaProbeError.probeFailed(result.standardError)
        }

        do {
            let response = try JSONDecoder().decode(FFProbeResponse.self, from: Data(result.standardOutput.utf8))
            return ProbedMedia(
                duration: response.format?.duration.flatMap(Double.init),
                formatNames: response.format?.formatName?.split(separator: ",").map(String.init) ?? [],
                streams: response.streams.map(\.probed)
            )
        } catch {
            throw MediaProbeError.invalidResponse(error)
        }
    }
}

enum MediaProbeError: Error, LocalizedError {
    case probeFailed(String)
    case invalidResponse(Error)

    var errorDescription: String? {
        switch self {
        case .probeFailed:
            "The downloaded media could not be inspected."
        case .invalidResponse:
            "The media inspector returned an unreadable response."
        }
    }
}

private struct FFProbeResponse: Decodable {
    let streams: [FFProbeStream]
    let format: FFProbeFormat?
}

private struct FFProbeFormat: Decodable {
    let duration: String?
    let formatName: String?

    enum CodingKeys: String, CodingKey {
        case duration
        case formatName = "format_name"
    }
}

private struct FFProbeStream: Decodable {
    let index: Int
    let codecType: String
    let codecName: String?
    let codecTag: String?
    let width: Int?
    let height: Int?
    let pixelFormat: String?
    let frameRate: String?
    let sampleRate: String?
    let channels: Int?
    let channelLayout: String?

    enum CodingKeys: String, CodingKey {
        case index
        case codecType = "codec_type"
        case codecName = "codec_name"
        case codecTag = "codec_tag_string"
        case width
        case height
        case pixelFormat = "pix_fmt"
        case frameRate = "r_frame_rate"
        case sampleRate = "sample_rate"
        case channels
        case channelLayout = "channel_layout"
    }

    var probed: ProbedStream {
        ProbedStream(
            index: index,
            codecType: codecType,
            codecName: codecName,
            codecTag: codecTag,
            width: width,
            height: height,
            pixelFormat: pixelFormat,
            frameRate: frameRate,
            sampleRate: sampleRate.flatMap(Int.init),
            channels: channels,
            channelLayout: channelLayout
        )
    }
}
