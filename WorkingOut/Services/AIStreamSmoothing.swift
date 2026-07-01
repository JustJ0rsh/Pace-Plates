import Foundation

enum AIStreamSmoothing {
    static func commonPrefixLength(previous: String, current: String) -> Int {
        var previousIndex = previous.startIndex
        var currentIndex = current.startIndex
        var count = 0

        while previousIndex < previous.endIndex,
              currentIndex < current.endIndex,
              previous[previousIndex] == current[currentIndex] {
            count += 1
            previous.formIndex(after: &previousIndex)
            current.formIndex(after: &currentIndex)
        }

        return count
    }

    static func appendableDelta(previous: String, current: String) -> String {
        guard !current.isEmpty else { return "" }
        guard !previous.isEmpty else { return current }

        if current.hasPrefix(previous) {
            return String(current.dropFirst(previous.count))
        }

        if previous.hasPrefix(current) {
            // Model corrected by backtracking; caller can't delete already-rendered text safely.
            return ""
        }

        let prefixLength = commonPrefixLength(previous: previous, current: current)
        if prefixLength > 0 {
            return String(current.dropFirst(prefixLength))
        }

        let overlap = overlapLength(previous: previous, current: current)
        if overlap > 0 {
            return String(current.dropFirst(overlap))
        }

        return ""
    }

    static func wordChunked(_ text: String, maxChunkChars: Int = 42) -> [String] {
        guard !text.isEmpty else { return [] }
        let chunkLimit = max(8, maxChunkChars)

        var chunks: [String] = []
        var buffer = ""

        func flush() {
            guard !buffer.isEmpty else { return }
            chunks.append(buffer)
            buffer.removeAll(keepingCapacity: true)
        }

        for character in text {
            buffer.append(character)

            if character == "\n" {
                flush()
                continue
            }

            if buffer.count < chunkLimit {
                continue
            }

            if character.isWhitespace || ",.;:!?".contains(character) {
                flush()
                continue
            }

            if let splitIndex = buffer.lastIndex(where: { $0.isWhitespace }) {
                let cut = buffer.index(after: splitIndex)
                let head = String(buffer[..<cut])
                let tail = String(buffer[cut...])
                if !head.isEmpty {
                    chunks.append(head)
                    buffer = tail
                } else {
                    flush()
                }
            } else {
                flush()
            }
        }

        flush()
        return chunks
    }

    private static func overlapLength(previous: String, current: String) -> Int {
        let maxOverlap = min(previous.count, current.count)
        guard maxOverlap > 0 else { return 0 }

        for overlap in stride(from: maxOverlap, through: 1, by: -1) {
            if previous.suffix(overlap) == current.prefix(overlap) {
                return overlap
            }
        }

        return 0
    }
}
