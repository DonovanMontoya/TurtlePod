import Foundation

public enum EpisodeDescriptionCleaner {
    public static func clean(_ value: String) -> String {
        value.strippingPodcastHTML().strippingPodcastHTML()
    }
}

private extension String {
    func strippingPodcastHTML() -> String {
        replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "(?i)</p\\s*>", with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .decodingHTMLEntities()
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func decodingHTMLEntities() -> String {
        var output = ""
        var index = startIndex

        while index < endIndex {
            guard self[index] == "&",
                  let semicolon = self[index...].firstIndex(of: ";") else {
                output.append(self[index])
                index = self.index(after: index)
                continue
            }

            let entityStart = self.index(after: index)
            let entity = String(self[entityStart..<semicolon])
            if let decoded = Self.decodedHTMLEntity(entity) {
                output.append(decoded)
                index = self.index(after: semicolon)
            } else {
                output.append(self[index])
                index = self.index(after: index)
            }
        }

        return output
    }

    private static func decodedHTMLEntity(_ entity: String) -> String? {
        if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
            return UInt32(entity.dropFirst(2), radix: 16)
                .flatMap(UnicodeScalar.init)
                .map(String.init)
        }

        if entity.hasPrefix("#") {
            return UInt32(entity.dropFirst(), radix: 10)
                .flatMap(UnicodeScalar.init)
                .map(String.init)
        }

        switch entity.lowercased() {
        case "amp":
            return "&"
        case "apos":
            return "'"
        case "gt":
            return ">"
        case "lt":
            return "<"
        case "nbsp":
            return " "
        case "quot":
            return "\""
        default:
            return nil
        }
    }
}
