import Foundation

enum Timecode {
    static func display(_ totalSeconds: Int) -> String {
        let clamped = max(0, totalSeconds)
        let hours = clamped / 3_600
        let minutes = (clamped % 3_600) / 60
        let seconds = clamped % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    static func filename(_ totalSeconds: Int) -> String {
        display(totalSeconds).replacingOccurrences(of: ":", with: "-")
    }

    static func parse(_ input: String) throws -> Int {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TimecodeParseError.empty
        }

        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else {
            throw TimecodeParseError.invalidFormat
        }

        let values = try parts.map { part -> Int in
            guard !part.isEmpty,
                  part.allSatisfy(\.isNumber),
                  let value = Int(part) else {
                throw TimecodeParseError.invalidFormat
            }
            return value
        }

        switch values.count {
        case 1:
            return values[0]
        case 2:
            guard values[1] < 60 else {
                throw TimecodeParseError.invalidComponent
            }
            return values[0] * 60 + values[1]
        case 3:
            guard values[1] < 60, values[2] < 60 else {
                throw TimecodeParseError.invalidComponent
            }
            return values[0] * 3_600 + values[1] * 60 + values[2]
        default:
            throw TimecodeParseError.invalidFormat
        }
    }
}

enum TimecodeParseError: Error, Equatable, LocalizedError {
    case empty
    case invalidFormat
    case invalidComponent

    var errorDescription: String? {
        switch self {
        case .empty:
            "Enter a timestamp."
        case .invalidFormat, .invalidComponent:
            "Use seconds, MM:SS, or HH:MM:SS."
        }
    }
}
