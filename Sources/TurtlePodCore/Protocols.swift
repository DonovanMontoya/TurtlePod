import Foundation

public protocol PodcastFeedService: Sendable {
    func fetchFeed(from url: URL) async throws -> PodcastFeed
}

public protocol EpisodeDownloadService: Sendable {
    func download(_ episode: PodcastEpisode) async throws -> EpisodeDownload
    func deleteDownload(for episode: PodcastEpisode) async throws
    func localFileURL(for episode: PodcastEpisode) -> URL
}

public protocol PlaybackService: AnyObject, Sendable {
    var currentEpisode: PodcastEpisode? { get async }
    var currentTime: TimeInterval { get async }
    var isPlaying: Bool { get async }

    func load(_ episode: PodcastEpisode) async throws
    func play() async
    func pause() async
    func seek(to time: TimeInterval) async
}

public protocol TranscriptService: Sendable {
    func transcribeDownloadedEpisode(
        _ episode: PodcastEpisode,
        apiKey: String,
        progressDidChange: (@MainActor @Sendable (_ currentChunk: Int, _ totalChunks: Int) async -> Void)?
    ) async throws -> [TranscriptChunk]
}

public extension TranscriptService {
    func transcribeDownloadedEpisode(_ episode: PodcastEpisode, apiKey: String) async throws -> [TranscriptChunk] {
        try await transcribeDownloadedEpisode(episode, apiKey: apiKey, progressDidChange: nil)
    }
}

public protocol AdDetectionService: Sendable {
    func detectAds(in transcript: [TranscriptChunk], apiKey: String) async throws -> [AdSegment]
}

public protocol AIProvider: Sendable {
    var providerName: String { get }
    var transcriptionModel: String { get }
    var classificationModel: String { get }

    func transcribe(audioFile: URL, apiKey: String) async throws -> [TranscriptChunk]
    func classify(transcript: [TranscriptChunk], apiKey: String) async throws -> [AdSegment]
}

public protocol EpisodeStore: Sendable {
    func loadFeeds() async throws -> [PodcastFeed]
    func saveFeeds(_ feeds: [PodcastFeed]) async throws
    func loadSettings() async throws -> AppSettings
    func saveSettings(_ settings: AppSettings) async throws
    func appendSkipEvent(_ event: SkipEvent) async throws
    func loadSkipEvents() async throws -> [SkipEvent]
}

public protocol APIKeyStore: Sendable {
    func saveOpenAIKey(_ key: String) throws
    func loadOpenAIKey() throws -> String?
    func deleteOpenAIKey() throws
}

public enum TurtlePodError: Error, LocalizedError, Equatable {
    case missingAudioEnclosure
    case invalidFeed
    case notDownloaded
    case apiKeyMissing
    case unsupportedResponse
    case audioInspectionFailed(String)
    case keychain(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .missingAudioEnclosure:
            "The feed item does not include an audio enclosure."
        case .invalidFeed:
            "The RSS feed could not be parsed."
        case .notDownloaded:
            "AI analysis is only available for downloaded episodes."
        case .apiKeyMissing:
            "Add an OpenAI API key before running AI analysis."
        case .unsupportedResponse:
            "The service returned an unsupported response."
        case .audioInspectionFailed(let message):
            "The downloaded audio file could not be inspected: \(message)"
        case .keychain(let status):
            "Keychain operation failed with status \(status)."
        }
    }
}
