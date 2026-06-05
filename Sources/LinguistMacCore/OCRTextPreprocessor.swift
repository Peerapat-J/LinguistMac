import Foundation

public enum OCRTextPreprocessor {
    public static func normalize(_ text: String) -> String {
        normalize(lines: text.components(separatedBy: .newlines))
    }

    public static func normalize(lines: [String]) -> String {
        let groups = makeParagraphGroups(from: lines)
        return groups
            .map(normalizeParagraph)
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    private static func makeParagraphGroups(from lines: [String]) -> [[String]] {
        var groups: [[String]] = []
        var current: [String] = []

        for line in lines {
            let cleaned = collapseWhitespace(in: line)
            if cleaned.isEmpty {
                if !current.isEmpty {
                    groups.append(current)
                    current = []
                }
            } else {
                current.append(cleaned)
            }
        }

        if !current.isEmpty {
            groups.append(current)
        }

        return groups
    }

    private static func normalizeParagraph(_ lines: [String]) -> String {
        var output: [String] = []

        for line in lines {
            if isListMarker(line) {
                output.append(line)
            } else if let last = output.last, isListMarker(last), shouldJoinToListItem(line) {
                output[output.count - 1] = last + " " + line
            } else if let last = output.last, !isListMarker(last) {
                output[output.count - 1] = join(last, line)
            } else {
                output.append(line)
            }
        }

        return output.joined(separator: "\n")
    }

    private static func collapseWhitespace(in line: String) -> String {
        line
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func join(_ first: String, _ second: String) -> String {
        if first.hasSuffix("-") {
            return String(first.dropLast()) + second
        }

        return first + " " + second
    }

    private static func isListMarker(_ line: String) -> Bool {
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
            return true
        }

        let prefix = line.prefix { $0.isNumber }
        guard !prefix.isEmpty else {
            return false
        }

        let remainder = line.dropFirst(prefix.count)
        return remainder.hasPrefix(". ") || remainder.hasPrefix(") ")
    }

    private static func shouldJoinToListItem(_ line: String) -> Bool {
        !isListMarker(line)
    }
}
