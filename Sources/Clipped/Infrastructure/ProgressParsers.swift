import Foundation

struct YTDLPProgress: Equatable, Sendable {
    let downloadedBytes: Int64
    let totalBytes: Int64?
    let etaSeconds: Int?

    var fractionCompleted: Double? {
        guard let totalBytes, totalBytes > 0 else { return nil }
        return min(1, max(0, Double(downloadedBytes) / Double(totalBytes)))
    }

    static func parse(line: String) -> YTDLPProgress? {
        guard line.hasPrefix("CLIPPED_PROGRESS|") else { return nil }
        let parts = line.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 4, let downloaded = Int64(parts[1]) else { return nil }
        return YTDLPProgress(
            downloadedBytes: downloaded,
            totalBytes: Int64(parts[2]),
            etaSeconds: Int(parts[3])
        )
    }
}

struct FFmpegProgressParser: Sendable {
    let durationSeconds: Double

    mutating func consume(line: String) -> Double? {
        if line == "progress=end" { return 1 }
        guard line.hasPrefix("out_time_us="),
              let value = Double(line.dropFirst("out_time_us=".count)),
              durationSeconds > 0 else {
            return nil
        }
        return min(1, max(0, value / 1_000_000 / durationSeconds))
    }
}

final class FFmpegProgressTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var parser: FFmpegProgressParser

    init(durationSeconds: Double) {
        parser = FFmpegProgressParser(durationSeconds: durationSeconds)
    }

    func consume(line: String) -> Double? {
        lock.withLock {
            parser.consume(line: line)
        }
    }
}
