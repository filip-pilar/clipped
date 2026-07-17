import Foundation

struct LoadedMedia: Equatable, Sendable {
    let requestedURL: URL
    let metadata: YTDLPMetadata
    let catalog: FormatCatalog

    var maximumWholeSecond: Int {
        max(1, Int((metadata.duration ?? 0).rounded(.down)))
    }
}

struct MetadataService: Sendable {
    let tools: ToolPaths
    let processRunner: any ProcessExecuting

    func load(sourceText: String) async throws -> LoadedMedia {
        let url = try SourceURLValidator.validate(sourceText)
        let result = try await processRunner.run(MediaCommands.metadata(sourceURL: url, tools: tools))

        guard result.succeeded else {
            throw MetadataServiceError.extractionFailed(Self.conciseError(from: result.standardError))
        }

        let metadata: YTDLPMetadata
        do {
            metadata = try JSONDecoder().decode(YTDLPMetadata.self, from: Data(result.standardOutput.utf8))
        } catch {
            throw MetadataServiceError.invalidResponse(error)
        }

        guard !metadata.isLive else {
            throw MetadataServiceError.liveSourceUnsupported
        }
        guard let duration = metadata.duration, duration >= 1 else {
            throw MetadataServiceError.missingDuration
        }

        let catalog = FormatCatalog.build(from: metadata.formats)
        guard !catalog.videoChoices.isEmpty || !catalog.audioChoices.isEmpty else {
            throw MetadataServiceError.noUsableFormats
        }

        return LoadedMedia(requestedURL: url, metadata: metadata, catalog: catalog)
    }

    private static func conciseError(from errorOutput: String) -> String {
        let lines = errorOutput
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return lines.last?.replacingOccurrences(of: "ERROR: ", with: "")
            ?? "The source could not be inspected."
    }
}

enum SourceURLValidator {
    static func validate(_ input: String) throws -> URL {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              components.host?.isEmpty == false,
              let url = components.url else {
            throw MetadataServiceError.invalidURL
        }
        return url
    }
}

enum MetadataServiceError: Error, LocalizedError {
    case invalidURL
    case extractionFailed(String)
    case invalidResponse(Error)
    case liveSourceUnsupported
    case missingDuration
    case noUsableFormats

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Enter a valid http or https URL."
        case .extractionFailed(let message):
            message
        case .invalidResponse:
            "The source returned metadata Clipped could not read."
        case .liveSourceUnsupported:
            "Live streams need a finished duration before they can be clipped."
        case .missingDuration:
            "This source does not report a usable duration."
        case .noUsableFormats:
            "No downloadable video or audio formats were found."
        }
    }
}
