import Foundation

struct DraftRange: Equatable, Sendable {
    var inSeconds: Int
    var outSeconds: Int?

    var committedRange: ClipRange? {
        guard let outSeconds, outSeconds > inSeconds else { return nil }
        return ClipRange(startSeconds: inSeconds, endSeconds: outSeconds)
    }
}

enum ClipEdge: Equatable, Sendable {
    case start
    case end
}

struct TrimSession: Equatable, Sendable {
    let clipID: UUID
    let edge: ClipEdge
    let originalRange: ClipRange
    let savedPlayhead: Double
    let wasPlaying: Bool
    var boundarySeconds: Int
}

struct EditorSnapshot: Equatable, Sendable {
    var ranges: [ClipRange]
    var selectedRangeID: UUID?
    var draftRange: DraftRange?
}

enum YouTubeTimestamp {
    static func initialSeconds(metadataStartTime: Double?, url: URL, maximumSeconds: Int) -> Int {
        let candidate = metadataStartTime.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
            ?? timestampValue(from: url).map(Double.init)
            ?? 0
        return min(maximumSeconds, max(0, Int(candidate.rounded())))
    }

    static func timestampValue(from url: URL) -> Int? {
        guard isYouTubeHost(url.host) else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }

        let queryValue = components.queryItems?.first(where: { $0.name.lowercased() == "t" })?.value
        if let queryValue, let seconds = parse(queryValue) { return seconds }

        if let fragment = components.fragment {
            let fragmentItems = URLComponents(string: "https://local.invalid/?\(fragment)")?.queryItems
            if let value = fragmentItems?.first(where: { $0.name.lowercased() == "t" })?.value,
               let seconds = parse(value) {
                return seconds
            }
        }
        return nil
    }

    static func parse(_ value: String) -> Int? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        if let seconds = Int(normalized), seconds >= 0 { return seconds }

        var total = 0
        var digits = ""
        var consumedUnit = false
        for character in normalized {
            if character.isNumber {
                digits.append(character)
                continue
            }
            guard let amount = Int(digits) else { return nil }
            digits = ""
            switch character {
            case "h": total += amount * 3_600
            case "m": total += amount * 60
            case "s": total += amount
            default: return nil
            }
            consumedUnit = true
        }
        guard consumedUnit, digits.isEmpty else { return nil }
        return total
    }

    private static func isYouTubeHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com")
    }
}
