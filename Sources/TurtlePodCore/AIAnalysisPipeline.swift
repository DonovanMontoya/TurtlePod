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
        defer {
            for chunk in chunks where chunk.isTemporary {
                try? FileManager.default.removeItem(at: chunk.fileURL)
            }
        }
        var transcript: [TranscriptChunk] = []

        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            let chunkTranscript = try await provider.transcribe(audioFile: chunk.fileURL, apiKey: apiKey)
                .map { item in
                    TranscriptChunk(
                        start: item.start + chunk.startOffset,
                        end: item.end + chunk.startOffset,
                        text: item.text
                    )
                }
            transcript.append(contentsOf: chunkTranscript)

            await progressDidChange?(index + 1, chunks.count)
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
        try await detectAds(in: transcript, comparison: nil)
    }

    public func detectAds(in transcript: [TranscriptChunk], comparison: ReferenceComparison?) async throws -> [AdSegment] {
        guard !transcript.isEmpty else { throw TurtlePodError.unsupportedResponse }
        guard transcript.allSatisfy({ $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end > $0.start }) else {
            throw TurtlePodError.unsupportedResponse
        }
        let sorted = transcript.sorted { $0.start < $1.start }
        // Bounded requests with one cue of overlap. Every cue is checked, even
        // when it matches the reference (which may contain host-read sponsors).
        var windows: [[TranscriptChunk]] = []
        var current: [TranscriptChunk] = []
        var characters = 0
        for chunk in sorted {
            if let first = current.first, current.count > 1,
               chunk.end - first.start > 300 || characters + chunk.text.count > 12_000 {
                windows.append(current)
                current = Array(current.suffix(1))
                characters = current.reduce(0) { $0 + $1.text.count }
            }
            current.append(chunk)
            characters += chunk.text.count
        }
        if !current.isEmpty { windows.append(current) }
        let candidates = comparison?.isReliable == true ? comparison?.candidates ?? [] : []
        let ordered = windows.enumerated().sorted { lhs, rhs in
            func containsCandidate(_ window: [TranscriptChunk]) -> Bool {
                guard let start = window.first?.start, let end = window.last?.end else { return false }
                return candidates.contains { $0.start < end && $0.end > start }
            }
            let left = containsCandidate(lhs.element)
            let right = containsCandidate(rhs.element)
            return left == right ? lhs.offset < rhs.offset : left
        }
        var segments: [AdSegment] = []
        for (_, window) in ordered {
            try Task.checkCancellation()
            let detected = try await provider.classify(transcript: window, apiKey: apiKey)
            let start = window.map(\.start).min() ?? 0
            let end = window.map(\.end).max() ?? 0
            segments += detected.filter {
                $0.start.isFinite && $0.end.isFinite && $0.confidence.isFinite &&
                $0.start >= start && $0.end <= end && $0.end > $0.start && (0...1).contains($0.confidence)
            }
        }
        return AdSegmentMerger.merge(segments, gapTolerance: gapTolerance)
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
        let comparison = episode.referenceTranscript.map { ReferenceTranscriptAlignment.compare(transcript, to: $0) }
        let adSegments = try await adDetectionService.detectAds(in: transcript, comparison: comparison)
        return EpisodeAnalysis(
            status: .complete,
            transcript: transcript,
            adSegments: adSegments,
            providerMetadata: providerMetadata,
            referenceComparison: comparison
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
