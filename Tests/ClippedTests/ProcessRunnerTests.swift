import XCTest
@testable import Clipped

final class ProcessRunnerTests: XCTestCase {
    func testCapturesOutputAndStreamsLines() async throws {
        let runner = ProcessRunner()
        let recorder = EventRecorder()
        let command = ProcessCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/printf"),
            arguments: ["first\\nsecond\\n"]
        )

        let result = try await runner.run(command) { event in
            recorder.append(event.line)
        }

        XCTAssertEqual(result.terminationStatus, 0)
        XCTAssertEqual(result.standardOutput, "first\nsecond\n")
        XCTAssertEqual(recorder.values, ["first", "second"])
    }

    func testArgumentsAreNeverInterpretedByAShell() async throws {
        let runner = ProcessRunner()
        let payload = "safe; touch /tmp/clipped-process-runner-must-not-create"
        let result = try await runner.run(ProcessCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/printf"),
            arguments: ["%s", payload]
        ))

        XCTAssertEqual(result.standardOutput, payload)
        XCTAssertFalse(FileManager.default.fileExists(atPath: "/tmp/clipped-process-runner-must-not-create"))
    }

    func testPreservesNonzeroExitStatus() async throws {
        let runner = ProcessRunner()
        let result = try await runner.run(ProcessCommand(executableURL: URL(fileURLWithPath: "/usr/bin/false")))
        XCTAssertFalse(result.succeeded)
        XCTAssertNotEqual(result.terminationStatus, 0)
    }

    func testRapidProcessesDoNotLoseTerminationNotifications() async throws {
        let runner = ProcessRunner()
        for _ in 0..<50 {
            let result = try await runner.run(ProcessCommand(
                executableURL: URL(fileURLWithPath: "/usr/bin/true")
            ))
            XCTAssertTrue(result.succeeded)
        }
    }

    func testCancellationInterruptsLongRunningProcess() async throws {
        let runner = ProcessRunner()
        let task = Task {
            try await runner.run(ProcessCommand(
                executableURL: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["10"]
            ))
        }

        try await Task.sleep(for: .milliseconds(150))
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }
    }
}

private final class EventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] {
        lock.withLock { storage }
    }

    func append(_ value: String) {
        lock.withLock { storage.append(value) }
    }
}
