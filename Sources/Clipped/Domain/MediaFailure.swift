import Foundation

enum MediaFailureKind: Equatable, Sendable {
    case invalidURL
    case unavailable
    case authenticationRequired
    case rateLimited
    case geoRestricted
    case liveUnsupported
    case unsupported
    case network
    case download
    case conversion
    case unknown
}

enum MediaFailureContext: Sendable {
    case source
    case preview
    case export
}

struct MediaFailurePresentation: Equatable, Sendable {
    let kind: MediaFailureKind
    let title: String
    let message: String
    let diagnostic: String?

    var alertMessage: String {
        guard let diagnostic, !diagnostic.isEmpty else { return message }
        return "\(message)\n\n\(diagnostic)"
    }

    static func classify(_ error: Error, context: MediaFailureContext) -> MediaFailurePresentation {
        if let metadataError = error as? MetadataServiceError {
            switch metadataError {
            case .invalidURL:
                return presentation(for: .invalidURL, context: context)
            case .liveSourceUnsupported:
                return presentation(for: .liveUnsupported, context: context)
            case .missingDuration, .noUsableFormats:
                return presentation(for: .unsupported, context: context)
            case .extractionFailed(let diagnostic):
                return classify(diagnostic: diagnostic, context: context)
            case .invalidResponse:
                return presentation(for: .unsupported, context: context)
            }
        }

        if let previewError = error as? PreviewServiceError {
            switch previewError {
            case .noPreviewFormat:
                return presentation(for: .unsupported, context: context)
            case .downloadFailed(let diagnostic):
                let classified = classify(diagnostic: diagnostic, context: context)
                return classified.kind == .unknown
                    ? presentation(for: .download, context: context, diagnostic: diagnostic)
                    : classified
            case .normalizationFailed(let diagnostic):
                return presentation(for: .conversion, context: context, diagnostic: diagnostic)
            }
        }

        if let exportError = error as? ExportServiceError {
            switch exportError {
            case .noRanges:
                return presentation(for: .unsupported, context: context)
            case .downloadFailed(let diagnostic):
                let classified = classify(diagnostic: diagnostic, context: context)
                return classified.kind == .unknown
                    ? presentation(for: .download, context: context, diagnostic: diagnostic)
                    : classified
            case .normalizationFailed(let diagnostic):
                return presentation(for: .conversion, context: context, diagnostic: diagnostic)
            }
        }

        if let urlError = error as? URLError {
            return presentation(
                for: .network,
                context: context,
                diagnostic: urlError.localizedDescription
            )
        }

        return classify(diagnostic: error.localizedDescription, context: context)
    }

    static func classify(diagnostic: String, context: MediaFailureContext) -> MediaFailurePresentation {
        let normalized = diagnostic.lowercased()

        if containsAny(normalized, [
            "geo-restricted", "geo restricted", "not available in your country",
            "not available in your region", "geographic restriction"
        ]) {
            return presentation(for: .geoRestricted, context: context)
        }
        if containsAny(normalized, [
            "rate-limit", "rate limit", "too many requests", "http error 429",
            "temporarily blocked"
        ]) {
            return presentation(for: .rateLimited, context: context)
        }
        if containsAny(normalized, [
            "login required", "log in to", "sign in to", "authentication required",
            "private video", "private account", "members-only", "age-restricted",
            "cookies are needed", "use --cookies"
        ]) {
            return presentation(for: .authenticationRequired, context: context)
        }
        if containsAny(normalized, [
            "video unavailable", "this video is unavailable", "content is unavailable", "content isn't available",
            "has been removed", "deleted video", "tweet has been deleted",
            "requested content is not available", "not found", "http error 404"
        ]) {
            return presentation(for: .unavailable, context: context)
        }
        if containsAny(normalized, [
            "network is unreachable", "not connected to the internet", "timed out",
            "timeout", "could not resolve host", "name or service not known",
            "temporary failure in name resolution", "connection refused",
            "connection reset", "http error 502", "http error 503"
        ]) {
            return presentation(for: .network, context: context)
        }
        if containsAny(normalized, [
            "unsupported url", "no suitable extractor", "no video formats found",
            "no downloadable video", "unable to extract", "signature extraction failed",
            "no media found", "not a video"
        ]) {
            return presentation(for: .unsupported, context: context)
        }

        return presentation(for: .unknown, context: context, diagnostic: diagnostic)
    }

    private static func presentation(
        for kind: MediaFailureKind,
        context: MediaFailureContext,
        diagnostic: String? = nil
    ) -> MediaFailurePresentation {
        let fallbackTitle: String
        switch context {
        case .source: fallbackTitle = "Couldn’t load source"
        case .preview: fallbackTitle = "Preview unavailable"
        case .export: fallbackTitle = "Download stopped"
        }

        let title: String
        let message: String
        switch kind {
        case .invalidURL:
            title = "Check the URL"
            message = "Enter a complete public http or https link."
        case .unavailable:
            title = "Source unavailable"
            message = "This source may have been removed, made private, or expired."
        case .authenticationRequired:
            title = "Public access required"
            message = "This source requires an account, cookies, or permission. Clipped currently supports public links only."
        case .rateLimited:
            title = "Platform temporarily limiting requests"
            message = "Wait a little, then try loading the link again."
        case .geoRestricted:
            title = "Source unavailable in this region"
            message = "The platform is not making this media available from your current location."
        case .liveUnsupported:
            title = "Live source unsupported"
            message = "Clipped needs a finished video or audio source with a fixed duration."
        case .unsupported:
            title = context == .preview ? "Preview unavailable" : "Source not supported"
            message = context == .preview
                ? "Clipped couldn’t find a playable preview for this source. You can still enter clip times manually."
                : "Clipped couldn’t find downloadable video or audio in this link."
        case .network:
            title = "Connection problem"
            message = "Clipped couldn’t reach the platform. Check your connection and try again."
        case .download:
            title = context == .preview ? "Preview download failed" : fallbackTitle
            message = context == .preview
                ? "The source loaded, but its preview media could not be downloaded. You can still enter clip times manually."
                : "The media could not be downloaded."
        case .conversion:
            title = context == .preview ? "Preview preparation failed" : fallbackTitle
            message = context == .preview
                ? "The preview downloaded but could not be prepared for playback. You can still enter clip times manually."
                : "The downloaded media could not be prepared as an editing-ready file."
        case .unknown:
            title = fallbackTitle
            message = "The platform did not provide media Clipped could use."
        }

        return MediaFailurePresentation(
            kind: kind,
            title: title,
            message: message,
            diagnostic: conciseDiagnostic(diagnostic)
        )
    }

    private static func containsAny(_ text: String, _ patterns: [String]) -> Bool {
        patterns.contains(where: text.contains)
    }

    private static func conciseDiagnostic(_ diagnostic: String?) -> String? {
        guard let diagnostic else { return nil }
        let line = diagnostic
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .last(where: { !$0.isEmpty })?
            .replacingOccurrences(of: "ERROR: ", with: "")
        guard let line, !line.isEmpty else { return nil }
        let maximumLength = 180
        if line.count <= maximumLength { return line }
        return String(line.prefix(maximumLength - 1)) + "…"
    }
}
