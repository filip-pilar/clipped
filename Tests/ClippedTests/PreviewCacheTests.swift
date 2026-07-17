import XCTest
@testable import Clipped

final class PreviewCacheTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClippedPreviewCacheTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    func testStableCacheKeyUsesSourceIdentity() throws {
        let first = try TestFixtures.loadedVideo(url: "https://example.com/video")
        let same = try TestFixtures.loadedVideo(url: "https://example.com/video")
        let other = try TestFixtures.loadedVideo(url: "https://example.com/other")
        XCTAssertEqual(PreviewCache.key(for: first), PreviewCache.key(for: same))
        XCTAssertNotEqual(PreviewCache.key(for: first), PreviewCache.key(for: other))
    }

    func testCommitAndLookup() async throws {
        let cache = PreviewCache(rootDirectory: root, maximumBytes: 1_024)
        let work = try await cache.makeWorkingDirectory(for: "key")
        let source = work.appendingPathComponent("preview.mp4")
        try Data(repeating: 1, count: 20).write(to: source)

        let committed = try await cache.commit(source, key: "key", audioOnly: false)
        let cached = await cache.cachedURL(for: "key", audioOnly: false)
        XCTAssertEqual(cached, committed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: committed.path))
    }

    func testPrunesOldestEntryWhenLimitIsExceeded() async throws {
        let cache = PreviewCache(rootDirectory: root, maximumBytes: 12)

        let firstWork = try await cache.makeWorkingDirectory(for: "first")
        let firstSource = firstWork.appendingPathComponent("preview.mp4")
        try Data(repeating: 1, count: 8).write(to: firstSource)
        let first = try await cache.commit(firstSource, key: "first", audioOnly: false)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: first.path)

        let secondWork = try await cache.makeWorkingDirectory(for: "second")
        let secondSource = secondWork.appendingPathComponent("preview.mp4")
        try Data(repeating: 2, count: 8).write(to: secondSource)
        let second = try await cache.commit(secondSource, key: "second", audioOnly: false)

        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }
}
