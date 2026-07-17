import Foundation

struct ClipRange: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: UUID
    var startSeconds: Int
    var endSeconds: Int

    init(id: UUID = UUID(), startSeconds: Int, endSeconds: Int) {
        self.id = id
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
    }

    var durationSeconds: Int {
        endSeconds - startSeconds
    }

    func validated(maximumSeconds: Int) throws -> ClipRange {
        guard startSeconds >= 0 else {
            throw ClipRangeValidationError.negativeStart
        }
        guard endSeconds > startSeconds else {
            throw ClipRangeValidationError.nonPositiveDuration
        }
        guard endSeconds <= maximumSeconds else {
            throw ClipRangeValidationError.exceedsSourceDuration
        }
        return self
    }
}

enum ClipRangeValidationError: Error, Equatable, LocalizedError {
    case negativeStart
    case nonPositiveDuration
    case exceedsSourceDuration

    var errorDescription: String? {
        switch self {
        case .negativeStart:
            "The start time cannot be negative."
        case .nonPositiveDuration:
            "The end time must be after the start time."
        case .exceedsSourceDuration:
            "The selected range extends beyond the source."
        }
    }
}
