import Foundation

public final class DefaultTranscriptService: TranscriptService {
    private let provider: TranscriptionProvider
    private let chunker: AudioChunker
    private let maxChunkDuration: TimeInterval

    public init(provider: TranscriptionProvider, chunker: AudioChunker = AVAssetAudioChunker(), maxChunkDuration: TimeInterval = 600) {
        self.provider = provider
        self.chunker = chunker
        self.maxChunkDuration = maxChunkDuration
    }

    public func transcribeDownloadedEpisode(
        _ episode: PodcastEpisode,
        apiKey: String,
        progressDidChange: (@MainActor @Sendable (_ currentChunk: Int, _ totalChunks: Int) async -> Void)? = nil
    ) async throws -> [TranscriptChunk] {
        guard let localFileURL = episode.download?.localFileURL, episode.download?.state == .downloaded else {
            throw TurtlePodError.notDownloaded
        }

        let chunks = try await chunker.chunks(for: localFileURL, maxDuration: maxChunkDuration)
        var transcript: [TranscriptChunk] = []

        for (index, chunk) in chunks.enumerated() {
            await progressDidChange?(index + 1, chunks.count)
            let chunkTranscript = try await provider.transcribe(audioFile: chunk.fileURL, apiKey: apiKey)
                .map { item in
                    TranscriptChunk(
                        start: item.start + chunk.startOffset,
                        end: item.end + chunk.startOffset,
                        text: item.text
                    )
                }
            transcript.append(contentsOf: chunkTranscript)

            if chunk.isTemporary {
                try? FileManager.default.removeItem(at: chunk.fileURL)
            }
        }

        return transcript
    }
}

public final class DefaultAdDetectionService: AdDetectionService {
    private let provider: AdClassificationProvider
    private let apiKey: String
    private let gapTolerance: TimeInterval

    public init(provider: AdClassificationProvider, apiKey: String = "", gapTolerance: TimeInterval = 2) {
        self.provider = provider
        self.apiKey = apiKey
        self.gapTolerance = gapTolerance
    }

    public func detectAds(in transcript: [TranscriptChunk]) async throws -> [AdSegment] {
        let rawSegments = try await provider.classify(transcript: transcript, apiKey: apiKey)
        return AdSegmentMerger.merge(rawSegments, gapTolerance: gapTolerance)
    }
}

public actor EpisodeAnalysisPipeline {
    private let transcriptService: TranscriptService
    private let adDetectionService: AdDetectionService
    private let transcriptionAPIKey: String
    private let requiresTranscriptionAPIKey: Bool
    private let providerMetadata: AIProviderMetadata

    public var metadata: AIProviderMetadata {
        providerMetadata
    }

    public init(
        transcriptService: TranscriptService,
        adDetectionService: AdDetectionService,
        transcriptionAPIKey: String,
        requiresTranscriptionAPIKey: Bool = true,
        providerMetadata: AIProviderMetadata
    ) {
        self.transcriptService = transcriptService
        self.adDetectionService = adDetectionService
        self.transcriptionAPIKey = transcriptionAPIKey
        self.requiresTranscriptionAPIKey = requiresTranscriptionAPIKey
        self.providerMetadata = providerMetadata
    }

    public func analyze(
        _ episode: PodcastEpisode,
        statusDidChange: (@MainActor @Sendable (AnalysisStatus) async -> Void)? = nil,
        transcriptionProgressDidChange: (@MainActor @Sendable (_ currentChunk: Int, _ totalChunks: Int) async -> Void)? = nil
    ) async throws -> EpisodeAnalysis {
        guard !requiresTranscriptionAPIKey || !transcriptionAPIKey.isEmpty else {
            throw TurtlePodError.apiKeyMissing
        }
        guard episode.download?.state == .downloaded else {
            throw TurtlePodError.notDownloaded
        }

        await statusDidChange?(.transcribing)
        let transcript = try await transcriptService.transcribeDownloadedEpisode(
            episode,
            apiKey: transcriptionAPIKey,
            progressDidChange: transcriptionProgressDidChange
        )
        await statusDidChange?(.classifying)
        let adSegments = try await adDetectionService.detectAds(in: transcript)
        return EpisodeAnalysis(
            status: .complete,
            transcript: transcript,
            adSegments: adSegments,
            providerMetadata: providerMetadata
        )
    }
}

public struct InMemoryAPIKeyStore: APIKeyStore {
    private let key: String?

    public init(key: String?) {
        self.key = key
    }

    public func saveOpenAIKey(_ key: String) throws {}
    public func loadOpenAIKey() throws -> String? { key }
    public func deleteOpenAIKey() throws {}
}
