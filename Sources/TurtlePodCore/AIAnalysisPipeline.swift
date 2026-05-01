import Foundation

public final class DefaultTranscriptService: TranscriptService {
    private let provider: AIProvider
    private let chunker: AudioChunker
    private let maxChunkDuration: TimeInterval

    public init(provider: AIProvider, chunker: AudioChunker = AVAssetAudioChunker(), maxChunkDuration: TimeInterval = 600) {
        self.provider = provider
        self.chunker = chunker
        self.maxChunkDuration = maxChunkDuration
    }

    public func transcribeDownloadedEpisode(_ episode: PodcastEpisode, apiKey: String) async throws -> [TranscriptChunk] {
        guard let localFileURL = episode.download?.localFileURL, episode.download?.state == .downloaded else {
            throw TurtlePodError.notDownloaded
        }

        let chunks = try await chunker.chunks(for: localFileURL, maxDuration: maxChunkDuration)
        var transcript: [TranscriptChunk] = []

        for chunk in chunks {
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
    private let provider: AIProvider
    private let gapTolerance: TimeInterval

    public init(provider: AIProvider, gapTolerance: TimeInterval = 2) {
        self.provider = provider
        self.gapTolerance = gapTolerance
    }

    public func detectAds(in transcript: [TranscriptChunk], apiKey: String) async throws -> [AdSegment] {
        let rawSegments = try await provider.classify(transcript: transcript, apiKey: apiKey)
        return AdSegmentMerger.merge(rawSegments, gapTolerance: gapTolerance)
    }
}

public actor EpisodeAnalysisPipeline {
    private let transcriptService: TranscriptService
    private let adDetectionService: AdDetectionService
    private let apiKeyStore: APIKeyStore
    private let providerMetadata: AIProviderMetadata

    public init(
        transcriptService: TranscriptService,
        adDetectionService: AdDetectionService,
        apiKeyStore: APIKeyStore,
        providerMetadata: AIProviderMetadata
    ) {
        self.transcriptService = transcriptService
        self.adDetectionService = adDetectionService
        self.apiKeyStore = apiKeyStore
        self.providerMetadata = providerMetadata
    }

    public func analyze(_ episode: PodcastEpisode) async throws -> EpisodeAnalysis {
        guard let apiKey = try apiKeyStore.loadOpenAIKey(), !apiKey.isEmpty else {
            throw TurtlePodError.apiKeyMissing
        }
        guard episode.download?.state == .downloaded else {
            throw TurtlePodError.notDownloaded
        }

        let transcript = try await transcriptService.transcribeDownloadedEpisode(episode, apiKey: apiKey)
        let adSegments = try await adDetectionService.detectAds(in: transcript, apiKey: apiKey)
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
