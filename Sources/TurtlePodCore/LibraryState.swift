import Foundation

/// Per-episode listening state. Stored apart from feeds so frequent position
/// saves do not rewrite transcripts and analysis.
public struct EpisodeUserState: Codable, Equatable, Sendable {
    public var playbackPosition: TimeInterval
    public var isPlayed: Bool
    public var isStarred: Bool
    public var lastPlayedAt: Date?
    public var playedAt: Date?
    /// Duration reported by the player, used when the feed omits one.
    public var knownDuration: TimeInterval?

    public init(
        playbackPosition: TimeInterval = 0,
        isPlayed: Bool = false,
        isStarred: Bool = false,
        lastPlayedAt: Date? = nil,
        playedAt: Date? = nil,
        knownDuration: TimeInterval? = nil
    ) {
        self.playbackPosition = playbackPosition
        self.isPlayed = isPlayed
        self.isStarred = isStarred
        self.lastPlayedAt = lastPlayedAt
        self.playedAt = playedAt
        self.knownDuration = knownDuration
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        playbackPosition = try container.decodeIfPresent(TimeInterval.self, forKey: .playbackPosition) ?? 0
        isPlayed = try container.decodeIfPresent(Bool.self, forKey: .isPlayed) ?? false
        isStarred = try container.decodeIfPresent(Bool.self, forKey: .isStarred) ?? false
        lastPlayedAt = try container.decodeIfPresent(Date.self, forKey: .lastPlayedAt)
        playedAt = try container.decodeIfPresent(Date.self, forKey: .playedAt)
        knownDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .knownDuration)
    }

    public var isInProgress: Bool {
        !isPlayed && playbackPosition >= 1
    }
}

public enum EpisodeSortOrder: String, Codable, CaseIterable, Sendable {
    case newestFirst
    case oldestFirst
}

public struct PodcastPreferences: Codable, Equatable, Sendable {
    public var skipIntroSeconds: Int
    public var skipOutroSeconds: Int
    public var autoDownloadNewEpisodes: Bool
    public var sortOrder: EpisodeSortOrder
    public var hidePlayed: Bool
    /// Overrides the global speed for this show when set.
    public var playbackSpeed: Double?
    public var addedAt: Date?

    public init(
        skipIntroSeconds: Int = 0,
        skipOutroSeconds: Int = 0,
        autoDownloadNewEpisodes: Bool = false,
        sortOrder: EpisodeSortOrder = .newestFirst,
        hidePlayed: Bool = false,
        playbackSpeed: Double? = nil,
        addedAt: Date? = nil
    ) {
        self.skipIntroSeconds = skipIntroSeconds
        self.skipOutroSeconds = skipOutroSeconds
        self.autoDownloadNewEpisodes = autoDownloadNewEpisodes
        self.sortOrder = sortOrder
        self.hidePlayed = hidePlayed
        self.playbackSpeed = playbackSpeed
        self.addedAt = addedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        skipIntroSeconds = try container.decodeIfPresent(Int.self, forKey: .skipIntroSeconds) ?? 0
        skipOutroSeconds = try container.decodeIfPresent(Int.self, forKey: .skipOutroSeconds) ?? 0
        autoDownloadNewEpisodes = try container.decodeIfPresent(Bool.self, forKey: .autoDownloadNewEpisodes) ?? false
        sortOrder = try container.decodeIfPresent(EpisodeSortOrder.self, forKey: .sortOrder) ?? .newestFirst
        hidePlayed = try container.decodeIfPresent(Bool.self, forKey: .hidePlayed) ?? false
        playbackSpeed = try container.decodeIfPresent(Double.self, forKey: .playbackSpeed)
        addedAt = try container.decodeIfPresent(Date.self, forKey: .addedAt)
    }
}

public struct PlaybackPreferences: Codable, Equatable, Sendable {
    public static let speedRange: ClosedRange<Double> = 0.5...3.0
    public static let speedPresets: [Double] = [0.8, 1.0, 1.2, 1.4, 1.5, 1.7, 2.0, 2.5, 3.0]

    public var speed: Double
    public var skipForwardSeconds: Int
    public var skipBackSeconds: Int
    /// Start the next Up Next episode when one finishes.
    public var autoPlayNext: Bool
    public var refreshOnLaunch: Bool
    /// Delete an episode's download once it has been played.
    public var removeDownloadsWhenPlayed: Bool

    public init(
        speed: Double = 1,
        skipForwardSeconds: Int = 30,
        skipBackSeconds: Int = 15,
        autoPlayNext: Bool = true,
        refreshOnLaunch: Bool = true,
        removeDownloadsWhenPlayed: Bool = false
    ) {
        self.speed = speed
        self.skipForwardSeconds = skipForwardSeconds
        self.skipBackSeconds = skipBackSeconds
        self.autoPlayNext = autoPlayNext
        self.refreshOnLaunch = refreshOnLaunch
        self.removeDownloadsWhenPlayed = removeDownloadsWhenPlayed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        speed = try container.decodeIfPresent(Double.self, forKey: .speed) ?? 1
        skipForwardSeconds = try container.decodeIfPresent(Int.self, forKey: .skipForwardSeconds) ?? 30
        skipBackSeconds = try container.decodeIfPresent(Int.self, forKey: .skipBackSeconds) ?? 15
        autoPlayNext = try container.decodeIfPresent(Bool.self, forKey: .autoPlayNext) ?? true
        refreshOnLaunch = try container.decodeIfPresent(Bool.self, forKey: .refreshOnLaunch) ?? true
        removeDownloadsWhenPlayed = try container.decodeIfPresent(Bool.self, forKey: .removeDownloadsWhenPlayed) ?? false
    }
}

public struct ListeningStats: Codable, Equatable, Sendable {
    public var secondsListened: TimeInterval
    public var secondsSkippedAds: TimeInterval
    public var adsSkipped: Int

    public init(secondsListened: TimeInterval = 0, secondsSkippedAds: TimeInterval = 0, adsSkipped: Int = 0) {
        self.secondsListened = secondsListened
        self.secondsSkippedAds = secondsSkippedAds
        self.adsSkipped = adsSkipped
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        secondsListened = try container.decodeIfPresent(TimeInterval.self, forKey: .secondsListened) ?? 0
        secondsSkippedAds = try container.decodeIfPresent(TimeInterval.self, forKey: .secondsSkippedAds) ?? 0
        adsSkipped = try container.decodeIfPresent(Int.self, forKey: .adsSkipped) ?? 0
    }
}

public struct LibraryState: Codable, Equatable, Sendable {
    public static let historyLimit = 200

    public var upNext: UpNextQueue
    public var episodes: [UUID: EpisodeUserState]
    public var podcasts: [UUID: PodcastPreferences]
    public var playback: PlaybackPreferences
    /// Most recent first.
    public var history: [UUID]
    public var nowPlayingEpisodeID: UUID?
    public var stats: ListeningStats

    public init(
        upNext: UpNextQueue = UpNextQueue(),
        episodes: [UUID: EpisodeUserState] = [:],
        podcasts: [UUID: PodcastPreferences] = [:],
        playback: PlaybackPreferences = PlaybackPreferences(),
        history: [UUID] = [],
        nowPlayingEpisodeID: UUID? = nil,
        stats: ListeningStats = ListeningStats()
    ) {
        self.upNext = upNext
        self.episodes = episodes
        self.podcasts = podcasts
        self.playback = playback
        self.history = history
        self.nowPlayingEpisodeID = nowPlayingEpisodeID
        self.stats = stats
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        upNext = try container.decodeIfPresent(UpNextQueue.self, forKey: .upNext) ?? UpNextQueue()
        episodes = try container.decodeIfPresent([UUID: EpisodeUserState].self, forKey: .episodes) ?? [:]
        podcasts = try container.decodeIfPresent([UUID: PodcastPreferences].self, forKey: .podcasts) ?? [:]
        playback = try container.decodeIfPresent(PlaybackPreferences.self, forKey: .playback) ?? PlaybackPreferences()
        history = try container.decodeIfPresent([UUID].self, forKey: .history) ?? []
        nowPlayingEpisodeID = try container.decodeIfPresent(UUID.self, forKey: .nowPlayingEpisodeID)
        stats = try container.decodeIfPresent(ListeningStats.self, forKey: .stats) ?? ListeningStats()
    }

    public func state(for episodeID: UUID) -> EpisodeUserState {
        episodes[episodeID] ?? EpisodeUserState()
    }

    public func preferences(for podcastID: UUID) -> PodcastPreferences {
        podcasts[podcastID] ?? PodcastPreferences()
    }

    public mutating func recordHistory(_ episodeID: UUID) {
        history.removeAll { $0 == episodeID }
        history.insert(episodeID, at: 0)
        if history.count > Self.historyLimit {
            history.removeLast(history.count - Self.historyLimit)
        }
    }

    public mutating func markPlayed(_ episodeID: UUID, at date: Date = Date()) {
        var state = state(for: episodeID)
        state.isPlayed = true
        state.playedAt = date
        state.playbackPosition = 0
        episodes[episodeID] = state
        upNext.remove(episodeID)
    }

    public mutating func markUnplayed(_ episodeID: UUID) {
        var state = state(for: episodeID)
        state.isPlayed = false
        state.playedAt = nil
        state.playbackPosition = 0
        episodes[episodeID] = state
    }

    /// Drop state for episodes that no longer exist in any feed.
    public mutating func prune(keeping episodeIDs: Set<UUID>, podcastIDs: Set<UUID>) {
        episodes = episodes.filter { episodeIDs.contains($0.key) }
        podcasts = podcasts.filter { podcastIDs.contains($0.key) }
        history.removeAll { !episodeIDs.contains($0) }
        upNext.items.removeAll { !episodeIDs.contains($0) }
        if let nowPlayingEpisodeID, !episodeIDs.contains(nowPlayingEpisodeID) {
            self.nowPlayingEpisodeID = nil
        }
    }
}

/// Ordered list of episodes to play after the current one.
public struct UpNextQueue: Codable, Equatable, Sendable {
    public var items: [UUID]

    public init(items: [UUID] = []) {
        self.items = items
    }

    public func contains(_ episodeID: UUID) -> Bool {
        items.contains(episodeID)
    }

    public mutating func playNext(_ episodeID: UUID) {
        items.removeAll { $0 == episodeID }
        items.insert(episodeID, at: 0)
    }

    public mutating func playLast(_ episodeID: UUID) {
        items.removeAll { $0 == episodeID }
        items.append(episodeID)
    }

    public mutating func remove(_ episodeID: UUID) {
        items.removeAll { $0 == episodeID }
    }

    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.sorted().map { items[$0] }
        var remaining = items.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertAt = destination - source.filter { $0 < destination }.count
        remaining.insert(contentsOf: moving, at: min(max(insertAt, 0), remaining.count))
        items = remaining
    }

    /// Removes and returns the next episode, skipping the one that just ended.
    public mutating func popNext(after currentID: UUID?) -> UUID? {
        if let currentID { remove(currentID) }
        guard !items.isEmpty else { return nil }
        return items.removeFirst()
    }

    public mutating func clear() {
        items.removeAll()
    }
}

public actor LibraryStateStore {
    private let url: URL
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
        url = baseDirectory.appending(path: "library-state.json")
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public func load() throws -> LibraryState {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return LibraryState()
        }
        return try decoder.decode(LibraryState.self, from: Data(contentsOf: url))
    }

    public func save(_ state: LibraryState) throws {
        try encoder.encode(state).write(to: url, options: [.atomic])
    }
}

public enum PlaybackProgress {
    /// Seconds from the end at which an episode counts as finished.
    public static let finishedThreshold: TimeInterval = 15

    /// Where to resume: restart near-finished episodes, otherwise back up a few seconds for context.
    public static func resumePosition(saved: TimeInterval, duration: TimeInterval?, introSkip: TimeInterval = 0) -> TimeInterval {
        if let duration, duration > 0, saved >= duration - finishedThreshold {
            return introSkip
        }
        if saved < 1 {
            return introSkip
        }
        return max(saved - 2, 0)
    }

    /// How far to rewind on resume so the listener regains context after a break.
    public static func catchUpRewind(pausedFor interval: TimeInterval) -> TimeInterval {
        switch interval {
        case ..<(5 * 60): 0
        case ..<(60 * 60): 10
        case ..<(24 * 60 * 60): 20
        default: 30
        }
    }

    public static func isFinished(position: TimeInterval, duration: TimeInterval?) -> Bool {
        guard let duration, duration > finishedThreshold else { return false }
        return position >= duration - finishedThreshold
    }
}
