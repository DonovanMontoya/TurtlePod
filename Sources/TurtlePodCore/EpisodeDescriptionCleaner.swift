import Foundation

public enum EpisodeDescriptionCleaner {
    public static func clean(_ value: String) -> String {
        value.strippingPodcastHTML().strippingPodcastHTML()
    }
}

private let namedEntities: [String: String] = [
    "rsquo": "\u{2019}", "lsquo": "\u{2018}", "rdquo": "\u{201D}", "ldquo": "\u{201C}",
    "sbquo": "\u{201A}", "bdquo": "\u{201E}", "ndash": "\u{2013}", "mdash": "\u{2014}",
    "hellip": "\u{2026}", "bull": "\u{2022}", "middot": "\u{00B7}", "copy": "\u{00A9}",
    "reg": "\u{00AE}", "trade": "\u{2122}", "deg": "\u{00B0}", "eacute": "\u{00E9}",
    "egrave": "\u{00E8}", "aacute": "\u{00E1}", "agrave": "\u{00E0}", "iacute": "\u{00ED}",
    "oacute": "\u{00F3}", "uacute": "\u{00FA}", "ntilde": "\u{00F1}", "ccedil": "\u{00E7}",
    "uuml": "\u{00FC}", "ouml": "\u{00F6}", "auml": "\u{00E4}", "szlig": "\u{00DF}",
    "Eacute": "\u{00C9}", "pound": "\u{00A3}", "euro": "\u{20AC}", "cent": "\u{00A2}",
    "times": "\u{00D7}", "frac12": "\u{00BD}", "laquo": "\u{00AB}", "raquo": "\u{00BB}",
    "thinsp": " ", "ensp": " ", "emsp": " ", "zwnj": "", "zwj": "",
]

private extension String {
    func strippingPodcastHTML() -> String {
        replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "(?i)</p\\s*>", with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .decodingHTMLEntities()
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " ?\\n ?", with: "\n", options: .regularExpression)
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
            return namedEntities[entity]
        }
    }
}
