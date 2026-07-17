import Foundation

struct MediaSelection: Equatable, Sendable {
    let video: VideoQualityChoice?
    let audio: AudioQualityChoice?

    var isAudioOnly: Bool {
        video == nil
    }

    func ytDLPSelector() throws -> String {
        if let video {
            if video.hasEmbeddedAudio || audio?.isSeparateAudio != true {
                return video.formatID
            }
            return "\(video.formatID)+\(audio!.formatID)"
        }

        guard let audio else {
            throw MediaSelectionError.missingAudio
        }
        return audio.formatID
    }

    var expectedAudioChannels: Int? {
        if video?.hasEmbeddedAudio == true {
            return video?.embeddedAudioChannels
        }
        return audio?.channels
    }

    var audioBitrateKilobits: Int {
        switch expectedAudioChannels {
        case .some(let channels) where channels >= 6:
            min(512, channels * 64)
        case 1:
            128
        default:
            192
        }
    }
}

enum MediaSelectionError: Error, LocalizedError {
    case missingAudio

    var errorDescription: String? {
        "Choose an audio quality before exporting."
    }
}
