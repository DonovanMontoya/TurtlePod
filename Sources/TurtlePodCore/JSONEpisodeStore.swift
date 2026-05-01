import Foundation

public actor JSONEpisodeStore: EpisodeStore {
    private let feedsURL: URL
    private let settingsURL: URL
    private let skipEventsURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directory: URL? = nil) throws {
        let baseDirectory = try directory ?? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appending(path: "TurtlePod", directoryHint: .isDirectory)

        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        feedsURL = baseDirectory.appending(path: "feeds.json")
        settingsURL = baseDirectory.appending(path: "settings.json")
        skipEventsURL = baseDirectory.appending(path: "skip-events.json")

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public func loadFeeds() async throws -> [PodcastFeed] {
        try load([PodcastFeed].self, from: feedsURL, defaultValue: [])
    }

    public func saveFeeds(_ feeds: [PodcastFeed]) async throws {
        try save(feeds, to: feedsURL)
    }

    public func loadSettings() async throws -> AppSettings {
        try load(AppSettings.self, from: settingsURL, defaultValue: AppSettings())
    }

    public func saveSettings(_ settings: AppSettings) async throws {
        try save(settings, to: settingsURL)
    }

    public func appendSkipEvent(_ event: SkipEvent) async throws {
        var events = try await loadSkipEvents()
        events.append(event)
        try save(events, to: skipEventsURL)
    }

    public func loadSkipEvents() async throws -> [SkipEvent] {
        try load([SkipEvent].self, from: skipEventsURL, defaultValue: [])
    }

    private func load<T: Decodable>(_ type: T.Type, from url: URL, defaultValue: T) throws -> T {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return defaultValue
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode(type, from: data)
    }

    private func save<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try encoder.encode(value)
        try data.write(to: url, options: [.atomic])
    }
}

public actor InMemoryEpisodeStore: EpisodeStore {
    private var feeds: [PodcastFeed]
    private var settings: AppSettings
    private var skipEvents: [SkipEvent]

    public init(feeds: [PodcastFeed] = [], settings: AppSettings = AppSettings(), skipEvents: [SkipEvent] = []) {
        self.feeds = feeds
        self.settings = settings
        self.skipEvents = skipEvents
    }

    public func loadFeeds() async throws -> [PodcastFeed] {
        feeds
    }

    public func saveFeeds(_ feeds: [PodcastFeed]) async throws {
        self.feeds = feeds
    }

    public func loadSettings() async throws -> AppSettings {
        settings
    }

    public func saveSettings(_ settings: AppSettings) async throws {
        self.settings = settings
    }

    public func appendSkipEvent(_ event: SkipEvent) async throws {
        skipEvents.append(event)
    }

    public func loadSkipEvents() async throws -> [SkipEvent] {
        skipEvents
    }
}
