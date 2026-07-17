import Foundation

enum FileNaming {
    static func sanitizedTitle(_ title: String, maxUTF8Bytes: Int = 180) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\?*\"<>|")
            .union(.controlCharacters)

        var output = ""
        var lastWasSeparator = false

        for scalar in title.precomposedStringWithCanonicalMapping.unicodeScalars {
            if invalidCharacters.contains(scalar) {
                if !lastWasSeparator, !output.isEmpty {
                    output.append("-")
                }
                lastWasSeparator = true
            } else if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                if !lastWasSeparator, !output.isEmpty {
                    output.append(" ")
                }
                lastWasSeparator = true
            } else {
                output.unicodeScalars.append(scalar)
                lastWasSeparator = false
            }
        }

        output = output.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".-")))
        while output.utf8.count > maxUTF8Bytes, !output.isEmpty {
            output.removeLast()
        }
        output = output.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".-")))

        return output.isEmpty ? "Untitled" : output
    }

    static func baseFilename(title: String, range: ClipRange) -> String {
        "\(sanitizedTitle(title))_\(Timecode.filename(range.startSeconds))_to_\(Timecode.filename(range.endSeconds))"
    }

    static func uniqueURL(
        in directory: URL,
        title: String,
        range: ClipRange,
        fileExtension: String,
        fileExists: (String) -> Bool = FileManager.default.fileExists(atPath:)
    ) -> URL {
        let base = baseFilename(title: title, range: range)
        var candidate = directory.appendingPathComponent(base).appendingPathExtension(fileExtension)
        var suffix = 2

        while fileExists(candidate.path) {
            candidate = directory
                .appendingPathComponent("\(base)-\(suffix)")
                .appendingPathExtension(fileExtension)
            suffix += 1
        }

        return candidate
    }
}
