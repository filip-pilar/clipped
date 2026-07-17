import CryptoKit
import Foundation

actor PreviewCache {
    private let rootDirectory: URL
    private let maximumBytes: Int64

    init(
        rootDirectory: URL = URL.cachesDirectory
            .appendingPathComponent("com.clipped.Clipped", isDirectory: true)
            .appendingPathComponent("Previews", isDirectory: true),
        maximumBytes: Int64 = 2 * 1_024 * 1_024 * 1_024
    ) {
        self.rootDirectory = rootDirectory
        self.maximumBytes = maximumBytes
    }

    static func key(for media: LoadedMedia) -> String {
        let identity = [
            media.metadata.extractorKey ?? media.metadata.extractor ?? "source",
            media.metadata.id,
            media.requestedURL.absoluteString
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(identity.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func cachedURL(for key: String, audioOnly: Bool) -> URL? {
        let candidate = finalURL(for: key, audioOnly: audioOnly)
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    func makeWorkingDirectory(for key: String) throws -> URL {
        try ensureRootExists()
        let directory = rootDirectory.appendingPathComponent("work-\(key.prefix(12))-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func commit(_ source: URL, key: String, audioOnly: Bool) throws -> URL {
        try ensureRootExists()
        let destination = finalURL(for: key, audioOnly: audioOnly)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: source, to: destination)
        try prune(excluding: destination)
        return destination
    }

    func discardWorkingDirectory(_ directory: URL) {
        guard directory.deletingLastPathComponent().standardizedFileURL == rootDirectory.standardizedFileURL,
              directory.lastPathComponent.hasPrefix("work-") else {
            return
        }
        try? FileManager.default.removeItem(at: directory)
    }

    private func finalURL(for key: String, audioOnly: Bool) -> URL {
        rootDirectory
            .appendingPathComponent(key)
            .appendingPathExtension(audioOnly ? "m4a" : "mp4")
    }

    private func ensureRootExists() throws {
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    private func prune(excluding protectedURL: URL) throws {
        let fileManager = FileManager.default
        let files = try fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        .compactMap { url -> CacheEntry? in
            guard url.standardizedFileURL.path != protectedURL.standardizedFileURL.path,
                  !url.lastPathComponent.hasPrefix("work-"),
                  let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true else {
                return nil
            }
            return CacheEntry(
                url: url,
                bytes: Int64(values.fileSize ?? 0),
                modified: values.contentModificationDate ?? .distantPast
            )
        }

        let protectedSize = Int64((try? protectedURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        var total = files.reduce(protectedSize) { $0 + $1.bytes }
        for entry in files.sorted(by: { $0.modified < $1.modified }) where total > maximumBytes {
            try fileManager.removeItem(at: entry.url)
            total -= entry.bytes
        }
    }
}

private struct CacheEntry {
    let url: URL
    let bytes: Int64
    let modified: Date
}
