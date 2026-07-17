import XCTest
@testable import Clipped

final class OutputValidatorTests: XCTestCase {
    func testAcceptsExactCompatibleVideo() throws {
        let media = try TestFixtures.loadedVideo()
        let selection = MediaSelection(
            video: media.catalog.videoChoices.first(where: { $0.formatID == "299" }),
            audio: media.catalog.audioChoices.first
        )
        let probe = try probe(from: TestFixtures.normalizedProbeJSON)
        XCTAssertNoThrow(try OutputValidator.validate(probe, expectedDuration: 3, selection: selection))
    }

    func testRejectsUnexpectedUpscaling() throws {
        let media = try TestFixtures.loadedVideo()
        let selection = MediaSelection(
            video: media.catalog.videoChoices.first(where: { $0.formatID == "18" }),
            audio: nil
        )
        let probe = try probe(from: TestFixtures.normalizedProbeJSON)
        XCTAssertThrowsError(try OutputValidator.validate(probe, expectedDuration: 3, selection: selection)) {
            guard case OutputValidationError.upscaled = $0 else {
                return XCTFail("Expected upscaled error, got \($0)")
            }
        }
    }

    func testRejectsDurationDrift() throws {
        let media = try TestFixtures.loadedVideo()
        let selection = MediaSelection(video: media.catalog.defaultVideoChoice, audio: media.catalog.defaultAudioChoice)
        let probe = try probe(from: TestFixtures.normalizedProbeJSON)
        XCTAssertThrowsError(try OutputValidator.validate(probe, expectedDuration: 4, selection: selection))
    }

    private func probe(from json: String) throws -> ProbedMedia {
        let runner = TestProcessExecutor { _, _ in
            ProcessResult(terminationStatus: 0, standardOutput: json, standardError: "")
        }
        let service = MediaProbeService(tools: TestFixtures.tools, processRunner: runner)
        return try synchronousValue { try await service.inspect(URL(fileURLWithPath: "/tmp/output.mp4")) }
    }

    private func synchronousValue<T: Sendable>(
        _ operation: @escaping @Sendable () async throws -> T
    ) throws -> T {
        let expectation = expectation(description: "async value")
        let result = LockedResult<T>()
        Task {
            do { result.set(.success(try await operation())) }
            catch { result.set(.failure(error)) }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)
        return try result.value!.get()
    }
}

private final class LockedResult<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Result<Value, Error>?
    var value: Result<Value, Error>? { lock.withLock { storage } }
    func set(_ value: Result<Value, Error>) { lock.withLock { storage = value } }
}
