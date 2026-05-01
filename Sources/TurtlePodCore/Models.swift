import Foundation

public struct PodcastFeed: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var feedURL: URL
    public var artworkURL: URL?
    public var episodes: [PodcastEpisode]

    public init(id: UUID = UUID(), title: String, feedURL: URL, artworkURL: URL? = nil, episodes: [PodcastEpisode] = []) {
        self.id = id
        self.title = title
        self.feedURL = feedURL
        self.artworkURL = artworkURL
        self.episodes = episodes
    }
}

public struct PodcastEpisode: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var feedID: UUID
    public var title: String
    public var audioURL: URL
    public var artworkURL: URL?
    public var duration: TimeInterval?
    public var publishedAt: Date?
    public var description: String
    public var download: EpisodeDownload?
    public var analysis: EpisodeAnalysis
    public var autoSkipEnabled: Bool

    public init(
        id: UUID = UUID(),
        feedID: UUID,
        title: String,
        audioURL: URL,
        artworkURL: URL? = nil,
        duration: TimeInterval? = nil,
        publishedAt: Date? = nil,
        description: String = "",
        download: EpisodeDownload? = nil,
        analysis: EpisodeAnalysis = EpisodeAnalysis(),
        autoSkipEnabled: Bool = true
    ) {
        self.id = id
        self.feedID = feedID
        self.title = title
        self.audioURL = audioURL
        self.artworkURL = artworkURL
        self.duration = duration
        self.publishedAt = publishedAt
        self.description = description
        self.download = download
        self.analysis = analysis
        self.autoSkipEnabled = autoSkipEnabled
    }
}

public struct EpisodeDownload: Codable, Equatable, Sendable {
    public var state: DownloadState
    public var localFileURL: URL?
    public var progress: Double
    public var errorMessage: String?

    public init(state: DownloadState = .notDownloaded, localFileURL: URL? = nil, progress: Double = 0, errorMessage: String? = nil) {
        self.state = state
        self.localFileURL = localFileURL
        self.progress = progress
        self.errorMessage = errorMessage
    }
}

public enum DownloadState: String, Codable, Equatable, Sendable {
    case notDownloaded
    case downloading
    case downloaded
    case failed
}

public struct EpisodeAnalysis: Codable, Equatable, Sendable {
    public var status: AnalysisStatus
    public var transcript: [TranscriptChunk]
    public var adSegments: [AdSegment]
    public var providerMetadata: AIProviderMetadata?
    public var errorMessage: String?

    public init(
        status: AnalysisStatus = .notStarted,
        transcript: [TranscriptChunk] = [],
        adSegments: [AdSegment] = [],
        providerMetadata: AIProviderMetadata? = nil,
        errorMessage: String? = nil
    ) {
        self.status = status
        self.transcript = transcript
        self.adSegments = adSegments
        self.providerMetadata = providerMetadata
        self.errorMessage = errorMessage
    }
}

public enum AnalysisStatus: String, Codable, Equatable, Sendable {
    case notStarted
    case queued
    case transcribing
    case classifying
    case complete
    case failed
}

public struct TranscriptChunk: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var start: TimeInterval
    public var end: TimeInterval
    public var text: String

    public init(id: UUID = UUID(), start: TimeInterval, end: TimeInterval, text: String) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
    }
}

public struct AdSegment: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var start: TimeInterval
    public var end: TimeInterval
    public var confidence: Double
    public var reason: String
    public var provider: String
    public var model: String

    public init(
        id: UUID = UUID(),
        start: TimeInterval,
        end: TimeInterval,
        confidence: Double,
        reason: String,
        provider: String,
        model: String
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.confidence = confidence
        self.reason = reason
        self.provider = provider
        self.model = model
    }
}

public struct AIProviderMetadata: Codable, Equatable, Sendable {
    public var provider: String
    public var transcriptionModel: String
    public var classificationModel: String
    public var createdAt: Date

    public init(provider: String, transcriptionModel: String, classificationModel: String, createdAt: Date = Date()) {
        self.provider = provider
        self.transcriptionModel = transcriptionModel
        self.classificationModel = classificationModel
        self.createdAt = createdAt
    }
}

public struct SkipEvent: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var episodeID: UUID
    public var skippedFrom: TimeInterval
    public var skippedTo: TimeInterval
    public var segmentID: UUID
    public var occurredAt: Date

    public init(id: UUID = UUID(), episodeID: UUID, skippedFrom: TimeInterval, skippedTo: TimeInterval, segmentID: UUID, occurredAt: Date = Date()) {
        self.id = id
        self.episodeID = episodeID
        self.skippedFrom = skippedFrom
        self.skippedTo = skippedTo
        self.segmentID = segmentID
        self.occurredAt = occurredAt
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var aiAnalysisEnabled: Bool
    public var autoSkipEnabled: Bool
    public var adSkipConfidenceThreshold: Double

    public init(aiAnalysisEnabled: Bool = false, autoSkipEnabled: Bool = true, adSkipConfidenceThreshold: Double = 0.72) {
        self.aiAnalysisEnabled = aiAnalysisEnabled
        self.autoSkipEnabled = autoSkipEnabled
        self.adSkipConfidenceThreshold = adSkipConfidenceThreshold
    }
}
