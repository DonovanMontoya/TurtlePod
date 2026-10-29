import Foundation

public final class RSSPodcastFeedService: PodcastFeedService {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchFeed(from url: URL) async throws -> PodcastFeed {
        let (data, response) = try await session.data(from: url)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try RSSFeedParser.parse(data: data, feedURL: url)
    }
}

public enum RSSFeedParser {
    public static func parse(data: Data, feedURL: URL) throws -> PodcastFeed {
        let delegate = ParserDelegate(feedURL: feedURL)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        parser.shouldProcessNamespaces = true

        guard parser.parse(), let feed = delegate.feed else {
            throw parser.parserError ?? TurtlePodError.invalidFeed
        }

        return feed
    }
}

private final class ParserDelegate: NSObject, XMLParserDelegate {
    private struct Item {
        var guid: String?
        var transcriptSources: [TranscriptSource] = []
        var title = ""
        var audioURL: URL?
        var artworkURL: URL?
        var duration: TimeInterval?
        var publishedAt: Date?
        var description = ""
        var chaptersURL: URL?
        var episodeNumber: Int?
        var seasonNumber: Int?
        var episodeType: String?
        var websiteURL: URL?
    }

    private static let namespacePrefixes = [
        "http://www.itunes.com/dtds/podcast-1.0.dtd": "itunes",
        "https://podcastindex.org/namespace/1.0": "podcast",
        "http://purl.org/rss/1.0/modules/content/": "content",
        "http://www.w3.org/2005/Atom": "atom"
    ]

    private let feedURL: URL
    private var feedID = UUID()
    private var channelTitle = ""
    private var channelArtworkURL: URL?
    private var channelAuthor: String?
    private var channelFallbackAuthor: String?
    private var channelDescription: String?
    private var channelSummary: String?
    private var channelWebsiteURL: URL?
    private var episodes: [PodcastEpisode] = []
    private var currentItem: Item?
    private var elementStack: [String] = []
    private var textBuffer = ""

    var feed: PodcastFeed?

    init(feedURL: URL) {
        self.feedURL = feedURL
    }

    func parserDidStartDocument(_ parser: XMLParser) {
        feedID = UUID()
    }

    func parserDidEndDocument(_ parser: XMLParser) {
        let title = channelTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        feed = PodcastFeed(
            id: feedID,
            title: title.isEmpty ? feedURL.host(percentEncoded: false) ?? feedURL.absoluteString : title,
            feedURL: feedURL,
            artworkURL: channelArtworkURL,
            episodes: episodes,
            author: channelAuthor ?? channelFallbackAuthor,
            summary: channelDescription ?? channelSummary,
            websiteURL: channelWebsiteURL,
            lastRefreshedAt: Date()
        )
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let element = normalized(elementName, namespaceURI: namespaceURI, qualifiedName: qName)
        elementStack.append(element)
        textBuffer = ""

        if element == "item" {
            currentItem = Item()
        } else if element == "enclosure", currentItem != nil {
            if let urlString = attributeDict["url"], let url = URL(string: urlString) {
                currentItem?.audioURL = url
            }
        } else if element == "podcast:transcript", currentItem != nil,
                  let rawURL = attributeDict["url"],
                  let url = URL(string: rawURL, relativeTo: feedURL)?.absoluteURL,
                  TranscriptSource.isRemoteURL(url) {
            currentItem?.transcriptSources.append(TranscriptSource(
                url: url, type: attributeDict["type"] ?? "",
                language: attributeDict["language"], label: "Publisher"
            ))
        } else if element == "podcast:chapters", currentItem != nil,
                  let rawURL = attributeDict["url"],
                  let url = URL(string: rawURL, relativeTo: feedURL)?.absoluteURL,
                  TranscriptSource.isRemoteURL(url) {
            currentItem?.chaptersURL = url
        } else if element == "image" || element == "itunes:image" {
            if let urlString = attributeDict["href"] ?? attributeDict["url"], let url = URL(string: urlString) {
                if currentItem != nil {
                    currentItem?.artworkURL = url
                } else {
                    channelArtworkURL = url
                }
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard let string = String(data: CDATABlock, encoding: .utf8) else { return }
        textBuffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let element = normalized(elementName, namespaceURI: namespaceURI, qualifiedName: qName)
        let text = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        defer {
            _ = elementStack.popLast()
            textBuffer = ""
        }

        if currentItem != nil {
            applyItemText(element: element, text: text)
            if element == "item", let item = currentItem {
                if let episode = makeEpisode(from: item) {
                    episodes.append(episode)
                }
                currentItem = nil
            }
        } else {
            applyChannelText(element: element, text: text)
        }
    }

    private func applyChannelText(element: String, text: String) {
        guard !text.isEmpty else { return }

        if element == "title", isDirectChild(element: "title", parent: "channel") {
            channelTitle = text
        } else if element == "url", elementStack.contains("image"), channelArtworkURL == nil {
            channelArtworkURL = URL(string: text)
        } else if isDirectChild(element: element, parent: "channel") {
            switch element {
            case "itunes:author":
                channelAuthor = text
            case "managingeditor", "author":
                if channelFallbackAuthor == nil {
                    channelFallbackAuthor = text
                }
            case "description":
                channelDescription = EpisodeDescriptionCleaner.clean(text).nonEmpty
            case "itunes:summary":
                channelSummary = EpisodeDescriptionCleaner.clean(text).nonEmpty
            case "link":
                channelWebsiteURL = webURL(text)
            default:
                break
            }
        }
    }

    private func applyItemText(element: String, text: String) {
        guard !text.isEmpty else { return }

        switch element {
        case "guid":
            currentItem?.guid = text
        case "title":
            currentItem?.title = text
        case "description", "content:encoded":
            if currentItem?.description.isEmpty == true {
                currentItem?.description = EpisodeDescriptionCleaner.clean(text)
            }
        case "itunes:duration":
            currentItem?.duration = DurationParser.parse(text)
        case "pubdate":
            currentItem?.publishedAt = DateParser.parseRSSDate(text)
        case "itunes:episode":
            currentItem?.episodeNumber = Int(text)
        case "itunes:season":
            currentItem?.seasonNumber = Int(text)
        case "itunes:episodetype":
            currentItem?.episodeType = text.lowercased()
        case "link":
            if isDirectChild(element: "link", parent: "item") {
                currentItem?.websiteURL = webURL(text)
            }
        default:
            break
        }
    }

    private func makeEpisode(from item: Item) -> PodcastEpisode? {
        guard let audioURL = item.audioURL else { return nil }
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return PodcastEpisode(
            feedID: feedID,
            title: title.isEmpty ? audioURL.lastPathComponent : title,
            audioURL: audioURL,
            artworkURL: item.artworkURL ?? channelArtworkURL,
            duration: item.duration,
            publishedAt: item.publishedAt,
            description: item.description,
            guid: item.guid,
            transcriptSources: item.transcriptSources,
            chaptersURL: item.chaptersURL,
            episodeNumber: item.episodeNumber,
            seasonNumber: item.seasonNumber,
            episodeType: item.episodeType,
            websiteURL: item.websiteURL
        )
    }

    /// Namespaced elements use a canonical prefix (`itunes:`, `podcast:`, ...) regardless of the
    /// prefix the feed declares; unknown namespaces keep their qualified name.
    private func normalized(_ elementName: String, namespaceURI: String?, qualifiedName qName: String?) -> String {
        if let namespaceURI, let prefix = Self.namespacePrefixes[namespaceURI] {
            return "\(prefix):\(elementName)".lowercased()
        }
        return (qName ?? elementName).lowercased()
    }

    private func webURL(_ text: String) -> URL? {
        guard let url = URL(string: text, relativeTo: feedURL)?.absoluteURL,
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return nil }
        return url
    }

    private func isDirectChild(element: String, parent: String) -> Bool {
        guard elementStack.last == element, elementStack.count >= 2 else { return false }
        return elementStack[elementStack.count - 2] == parent
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

enum DurationParser {
    static func parse(_ rawValue: String) -> TimeInterval? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let seconds = TimeInterval(value) {
            return seconds
        }

        let parts = value.split(separator: ":").compactMap { TimeInterval($0) }
        guard !parts.isEmpty else { return nil }

        switch parts.count {
        case 1:
            return parts[0]
        case 2:
            return parts[0] * 60 + parts[1]
        default:
            return parts.suffix(3).enumerated().reduce(0) { result, entry in
                let multiplier = pow(60.0, Double(2 - entry.offset))
                return result + entry.element * multiplier
            }
        }
    }
}

enum DateParser {
    private static let rssFormatters: [DateFormatter] = {
        let formats = [
            "EEE, d MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "d MMM yyyy HH:mm:ss Z",
            "dd MMM yyyy HH:mm:ss Z"
        ]
        return formats.map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            return formatter
        }
    }()

    static func parseRSSDate(_ rawValue: String) -> Date? {
        for formatter in rssFormatters {
            if let date = formatter.date(from: rawValue) {
                return date
            }
        }
        return ISO8601DateFormatter().date(from: rawValue)
    }
}
