import Foundation

enum PreviewState: Equatable, Sendable {
    case idle
    case downloading(fractionCompleted: Double?)
    case preparing
    case ready(URL)
    case failed(MediaFailurePresentation)

    var isWorking: Bool {
        switch self {
        case .downloading, .preparing: true
        case .idle, .ready, .failed: false
        }
    }

    var readyURL: URL? {
        guard case .ready(let url) = self else { return nil }
        return url
    }

    static func progress(_ progress: PreviewPreparationProgress) -> PreviewState {
        switch progress.stage {
        case .downloading:
            .downloading(fractionCompleted: progress.fractionCompleted)
        case .normalizing:
            .preparing
        case .ready:
            // The service emits ready immediately before returning the final URL.
            // Keep the preparation state until AppModel receives that URL.
            .preparing
        }
    }
}
