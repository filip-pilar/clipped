import Foundation

struct ToolPaths: Equatable, Sendable {
    let ytDLP: URL
    let deno: URL
    let ffmpeg: URL
    let ffprobe: URL

    var directory: URL {
        ffmpeg.deletingLastPathComponent()
    }

    var commonYTDLPArguments: [String] {
        [
            "--ignore-config",
            "--no-playlist",
            "--no-colors",
            "--retries", "3",
            "--fragment-retries", "3",
            "--js-runtimes", "deno:\(deno.path)",
            "--ffmpeg-location", directory.path
        ]
    }
}

enum Toolchain {
    static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleURL: URL = Bundle.main.bundleURL,
        fileManager: FileManager = .default
    ) throws -> ToolPaths {
        var candidates: [URL] = []

        if let override = environment["CLIPPED_TOOL_DIR"], !override.isEmpty {
            candidates.append(URL(fileURLWithPath: override, isDirectory: true))
        }

        candidates.append(
            bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Helpers", isDirectory: true)
                .appendingPathComponent("MediaTools", isDirectory: true)
        )

        #if DEBUG
        candidates.append(URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true))
        #endif

        for directory in candidates {
            let tools = ToolPaths(
                ytDLP: directory.appendingPathComponent("yt-dlp"),
                deno: directory.appendingPathComponent("deno"),
                ffmpeg: directory.appendingPathComponent("ffmpeg"),
                ffprobe: directory.appendingPathComponent("ffprobe")
            )
            if [tools.ytDLP, tools.deno, tools.ffmpeg, tools.ffprobe]
                .allSatisfy({ fileManager.isExecutableFile(atPath: $0.path) }) {
                return tools
            }
        }

        throw ToolchainError.missingTools(candidates)
    }
}

enum ToolchainError: Error, LocalizedError {
    case missingTools([URL])

    var errorDescription: String? {
        switch self {
        case .missingTools:
            "Clipped's media tools are missing. Reinstall the application."
        }
    }
}
