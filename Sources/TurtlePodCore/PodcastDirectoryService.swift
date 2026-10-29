import Foundation

public struct PodcastSearchResult: Identifiable, Equatable, Hashable, Codable, Sendable {
    public var id: Int
    public var title: String
    public var author: String?
    public var feedURL: URL
    public var artworkURL: URL?
    public var genre: String?
    public var episodeCount: Int?

    public init(
        id: Int,
        title: String,
        author: String? = nil,
        feedURL: URL,
        artworkURL: URL? = nil,
        genre: String? = nil,
        episodeCount: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.feedURL = feedURL
        self.artworkURL = artworkURL
        self.genre = genre
        self.episodeCount = episodeCount
    }
}

public protocol PodcastDirectoryService: Sendable {
    func search(_ term: String) async throws -> [PodcastSearchResult]
    func topPodcasts(limit: Int) async throws -> [PodcastSearchResult]
}

public struct ITunesPodcastDirectoryService: PodcastDirectoryService {
    private let session: URLSession
    private let countryCode: String

    public init(session: URLSession = .shared, countryCode: String? = nil) {
        self.session = session
        let code = (countryCode ?? Locale.current.region?.identifier)?.lowercased() ?? ""
        self.countryCode = code.count == 2 ? code : "us"
    }

    public func search(_ term: String) async throws -> [PodcastSearchResult] {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "media", value: "podcast"),
            URLQueryItem(name: "entity", value: "podcast"),
            URLQueryItem(name: "limit", value: "40"),
            URLQueryItem(name: "country", value: countryCode),
            URLQueryItem(name: "term", value: trimmed)
        ]
        return try ITunesDirectoryParser.parseLookup(try await fetch(components))
    }

    public func topPodcasts(limit: Int) async throws -> [PodcastSearchResult] {
        let clampedLimit = min(max(limit, 1), 100)
        let chartURL = URL(string: "https://rss.marketingtools.apple.com/api/v2/\(countryCode)/podcasts/top/\(clampedLimit)/podcasts.json")!
        let ids = try ITunesDirectoryParser.parseTopChartIDs(try await fetch(URLComponents(url: chartURL, resolvingAgainstBaseURL: false)!))
        guard !ids.isEmpty else { return [] }

        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [
            URLQueryItem(name: "id", value: ids.map(String.init).joined(separator: ",")),
            URLQueryItem(name: "entity", value: "podcast"),
            URLQueryItem(name: "country", value: countryCode)
        ]
        let resultsByID = Dictionary(
            try ITunesDirectoryParser.parseLookup(try await fetch(components)).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return ids.compactMap { resultsByID[$0] }
    }

    private func fetch(_ components: URLComponents) async throws -> Data {
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("TurtlePod/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

public enum ITunesDirectoryParser {
    private struct LookupResponse: Decodable {
        var results: [LookupItem]
    }

    private struct LookupItem: Decodable {
        var collectionId: Int?
        var trackId: Int?
        var collectionName: String?
        var trackName: String?
        var artistName: String?
        var feedUrl: String?
        var artworkUrl600: String?
        var artworkUrl100: String?
        var artworkUrl60: String?
        var primaryGenreName: String?
        var trackCount: Int?
    }

    private struct ChartResponse: Decodable {
        struct Feed: Decodable { var results: [Entry] }
        struct Entry: Decodable { var id: String }
        var feed: Feed
    }

    public static func parseLookup(_ data: Data) throws -> [PodcastSearchResult] {
        let response = try JSONDecoder().decode(LookupResponse.self, from: data)
        var seen: Set<Int> = []
        return response.results.compactMap { item in
            guard let id = item.collectionId ?? item.trackId,
                  let rawFeedURL = item.feedUrl, let feedURL = URL(string: rawFeedURL),
                  feedURL.scheme != nil,
                  seen.insert(id).inserted else { return nil }
            let title = (item.collectionName ?? item.trackName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let artwork = [item.artworkUrl600, item.artworkUrl100, item.artworkUrl60]
                .compactMap { $0.flatMap(URL.init(string:)) }
                .first
            return PodcastSearchResult(
                id: id,
                title: title.isEmpty ? feedURL.host(percentEncoded: false) ?? rawFeedURL : title,
                author: item.artistName?.nilIfBlank,
                feedURL: feedURL,
                artworkURL: artwork,
                genre: item.primaryGenreName?.nilIfBlank,
                episodeCount: item.trackCount
            )
        }
    }

    public static func parseTopChartIDs(_ data: Data) throws -> [Int] {
        try JSONDecoder().decode(ChartResponse.self, from: data).feed.results.compactMap { Int($0.id) }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
