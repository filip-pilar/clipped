import Foundation

struct ProcessCommand: Equatable, Sendable {
    let executableURL: URL
    let arguments: [String]
    let environment: [String: String]?
    let currentDirectoryURL: URL?

    init(
        executableURL: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectoryURL: URL? = nil
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.environment = environment
        self.currentDirectoryURL = currentDirectoryURL
    }
}

enum ProcessOutputStream: Sendable {
    case standardOutput
    case standardError
}

struct ProcessOutputEvent: Sendable {
    let stream: ProcessOutputStream
    let line: String
}

struct ProcessResult: Equatable, Sendable {
    let terminationStatus: Int32
    let standardOutput: String
    let standardError: String

    var succeeded: Bool {
        terminationStatus == 0
    }
}

protocol ProcessExecuting: Sendable {
    func run(
        _ command: ProcessCommand,
        onEvent: @escaping @Sendable (ProcessOutputEvent) -> Void
    ) async throws -> ProcessResult

    func cancelAll() async
}

extension ProcessExecuting {
    func run(_ command: ProcessCommand) async throws -> ProcessResult {
        try await run(command, onEvent: { _ in })
    }
}

actor ProcessRunner: ProcessExecuting {
    private var activeProcesses: [UUID: RunningProcess] = [:]

    func run(
        _ command: ProcessCommand,
        onEvent: @escaping @Sendable (ProcessOutputEvent) -> Void
    ) async throws -> ProcessResult {
        try Task.checkCancellation()

        let process = Process()
        process.executableURL = command.executableURL
        process.arguments = command.arguments
        process.environment = command.environment
        process.currentDirectoryURL = command.currentDirectoryURL

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.standardInput = FileHandle.nullDevice

        let identifier = UUID()
        let runningProcess = RunningProcess(process)
        let exitAwaiter = ProcessExitAwaiter()
        process.terminationHandler = { terminatedProcess in
            exitAwaiter.finish(with: terminatedProcess.terminationStatus)
        }
        activeProcesses[identifier] = runningProcess
        defer { activeProcesses.removeValue(forKey: identifier) }

        do {
            try process.run()
        } catch {
            throw ProcessRunnerError.couldNotLaunch(command.executableURL, error)
        }

        let outputTask = Task.detached(priority: .utility) {
            try StreamCollector.collect(
                from: outputPipe.fileHandleForReading,
                stream: .standardOutput,
                onEvent: onEvent
            )
        }
        let errorTask = Task.detached(priority: .utility) {
            try StreamCollector.collect(
                from: errorPipe.fileHandleForReading,
                stream: .standardError,
                onEvent: onEvent
            )
        }

        return try await withTaskCancellationHandler {
            let status = await exitAwaiter.value()
            let output = try await outputTask.value
            let error = try await errorTask.value
            try Task.checkCancellation()
            return ProcessResult(
                terminationStatus: status,
                standardOutput: output,
                standardError: error
            )
        } onCancel: {
            runningProcess.cancel()
        }
    }

    func cancelAll() {
        activeProcesses.values.forEach { $0.cancel() }
    }
}

enum ProcessRunnerError: Error, LocalizedError {
    case couldNotLaunch(URL, Error)
    case couldNotReadOutput(Error)

    var errorDescription: String? {
        switch self {
        case .couldNotLaunch(let url, let error):
            "Could not launch \(url.lastPathComponent): \(error.localizedDescription)"
        case .couldNotReadOutput(let error):
            "Could not read tool output: \(error.localizedDescription)"
        }
    }
}

private final class RunningProcess: @unchecked Sendable {
    private let process: Process
    private let lock = NSLock()

    init(_ process: Process) {
        self.process = process
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        guard process.isRunning else { return }
        process.interrupt()

        let process = process
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
            guard process.isRunning else { return }
            process.terminate()
        }
    }
}

private final class ProcessExitAwaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var status: Int32?
    private var continuation: CheckedContinuation<Int32, Never>?

    func value() async -> Int32 {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let status {
                lock.unlock()
                continuation.resume(returning: status)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }

    func finish(with status: Int32) {
        lock.lock()
        guard self.status == nil else {
            lock.unlock()
            return
        }
        self.status = status
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: status)
    }
}

private enum StreamCollector {
    static func collect(
        from handle: FileHandle,
        stream: ProcessOutputStream,
        onEvent: @escaping @Sendable (ProcessOutputEvent) -> Void
    ) throws -> String {
        var collected = Data()
        var pending = Data()

        do {
            while let chunk = try handle.read(upToCount: 64 * 1_024), !chunk.isEmpty {
                collected.append(chunk)
                pending.append(chunk)
                emitCompleteLines(from: &pending, stream: stream, onEvent: onEvent)
            }
        } catch {
            throw ProcessRunnerError.couldNotReadOutput(error)
        }

        if !pending.isEmpty, let line = String(data: pending, encoding: .utf8) {
            onEvent(ProcessOutputEvent(stream: stream, line: line))
        }

        return String(decoding: collected, as: UTF8.self)
    }

    private static func emitCompleteLines(
        from data: inout Data,
        stream: ProcessOutputStream,
        onEvent: @escaping @Sendable (ProcessOutputEvent) -> Void
    ) {
        while let newline = data.firstIndex(of: 0x0A) {
            let lineData = data[..<newline]
            var line = String(decoding: lineData, as: UTF8.self)
            if line.last == "\r" { line.removeLast() }
            onEvent(ProcessOutputEvent(stream: stream, line: line))
            data.removeSubrange(...newline)
        }
    }
}
