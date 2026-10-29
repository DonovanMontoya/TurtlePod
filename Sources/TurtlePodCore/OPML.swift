import Foundation

public struct OPMLOutline: Equatable, Sendable {
    public var title: String
    public var feedURL: URL

    public init(title: String, feedURL: URL) {
        self.title = title
        self.feedURL = feedURL
    }
}

public enum OPMLError: Error, LocalizedError, Equatable {
    case invalidDocument
    case noFeeds

    public var errorDescription: String? {
        switch self {
        case .invalidDocument:
            "The file is not a valid OPML document."
        case .noFeeds:
            "The OPML file does not contain any podcast feeds."
        }
    }
}

public enum OPMLParser {
    public static func parse(_ data: Data) throws -> [OPMLOutline] {
        let delegate = OPMLParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false

        guard parser.parse() || !delegate.outlines.isEmpty else {
            throw OPMLError.invalidDocument
        }
        guard !delegate.outlines.isEmpty else {
            throw OPMLError.noFeeds
        }
        return delegate.outlines
    }
}

private final class OPMLParserDelegate: NSObject, XMLParserDelegate {
    private(set) var outlines: [OPMLOutline] = []
    private var seenURLs: Set<String> = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName.lowercased() == "outline" else { return }
        let attributes = Dictionary(
            attributeDict.map { ($0.key.lowercased(), $0.value) },
            uniquingKeysWith: { first, _ in first }
        )
        guard let rawURL = attributes["xmlurl"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: rawURL),
              let scheme = url.scheme?.lowercased(),
              ["http", "https", "feed"].contains(scheme) else { return }

        guard let feedURL = scheme == "feed" ? Self.resolvingFeedScheme(rawURL) : url else { return }
        let key = feedURL.absoluteString.lowercased()
        guard seenURLs.insert(key).inserted else { return }

        let title = [attributes["title"], attributes["text"]]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        outlines.append(OPMLOutline(title: title ?? feedURL.host(percentEncoded: false) ?? rawURL, feedURL: feedURL))
    }

    /// `feed://host/path` → `https://host/path`; `feed:https://host/path` → `https://host/path`.
    private static func resolvingFeedScheme(_ rawURL: String) -> URL? {
        let remainder = rawURL.dropFirst("feed:".count)
        if remainder.hasPrefix("//") {
            return URL(string: "https:" + remainder)
        }
        return URL(string: String(remainder))
    }
}

public enum OPMLExporter {
    public static func export(_ feeds: [PodcastFeed], title: String = "TurtlePod Subscriptions") -> Data {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"

        var lines = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<opml version=\"2.0\">",
            "  <head>",
            "    <title>\(escape(title))</title>",
            "    <dateCreated>\(formatter.string(from: Date()))</dateCreated>",
            "  </head>",
            "  <body>"
        ]
        for feed in feeds {
            var attributes = "type=\"rss\" text=\"\(escape(feed.title))\" title=\"\(escape(feed.title))\" xmlUrl=\"\(escape(feed.feedURL.absoluteString))\""
            if let websiteURL = feed.websiteURL {
                attributes += " htmlUrl=\"\(escape(websiteURL.absoluteString))\""
            }
            lines.append("    <outline \(attributes) />")
        }
        lines += ["  </body>", "</opml>", ""]
        return Data(lines.joined(separator: "\n").utf8)
    }

    static func escape(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.count)
        for scalar in value.unicodeScalars {
            switch scalar {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&apos;"
            case "\n": result += "&#10;"
            case "\r": result += "&#13;"
            case "\t": result += "&#9;"
            default:
                // Drop control characters that are invalid in XML 1.0.
                if scalar.value < 0x20 { continue }
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }
}
