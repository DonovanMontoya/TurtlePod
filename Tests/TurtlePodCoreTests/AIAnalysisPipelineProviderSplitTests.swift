import Foundation
import XCTest
@testable import TurtlePodCore

final class AIAnalysisPipelineProviderSplitTests: XCTestCase {
    func testPipelineCombinesOpenAITranscriptionWithLocalClassification() async throws {
        let audioURL = FileManager.default.temporaryDirectory
            .appending(path: "turtlepod-provider-split-test.m4a")
        try Data("audio".utf8).write(to: audioURL, options: [.atomic])
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let episode = PodcastEpisode(
            feedID: UUID(),
            title: "Episode",
            audioURL: URL(string: "https://example.com/episode.mp3")!,
            download: EpisodeDownload(state: .downloaded, localFileURL: audioURL)
        )
        let transcriber = FakeTranscriptionProvider(
            chunks: [
                TranscriptChunk(start: 1, end: 5, text: "Use code TURTLE."),
                TranscriptChunk(start: 5, end: 9, text: "Back to the show.")
            ]
        )
        let classifier = FakeAdClassificationProvider(
            providerName: "local-test",
            classificationModel: "fixture-classifier",
            expectedFirstTranscriptStart: 121,
            segments: [
                AdSegment(start: 121, end: 125, confidence: 0.9, reason: "sponsor", provider: "local-test", model: "fixture-classifier")
            ]
        )
        let pipeline = EpisodeAnalysisPipeline(
            transcriptService: DefaultTranscriptService(
                provider: transcriber,
                chunker: FakeAudioChunker(startOffset: 120)
            ),
            adDetectionService: DefaultAdDetectionService(provider: classifier),
            transcriptionAPIKey: "test-key",
            providerMetadata: AIProviderMetadata(
                provider: classifier.providerName,
                transcriptionProvider: transcriber.providerName,
                transcriptionModel: transcriber.transcriptionModel,
                classificationProvider: classifier.providerName,
                classificationModel: classifier.classificationModel
            )
        )

        let analysis = try await pipeline.analyze(episode)

        XCTAssertEqual(analysis.status, .complete)
        XCTAssertEqual(analysis.transcript[0].start, 121)
        XCTAssertEqual(analysis.adSegments.count, 1)
        XCTAssertEqual(analysis.providerMetadata?.transcriptionProvider, "openai-test")
        XCTAssertEqual(analysis.providerMetadata?.classificationProvider, "local-test")
    }

    func testPipelineAllowsLocalTranscriptionWithoutAPIKey() async throws {
        let audioURL = FileManager.default.temporaryDirectory
            .appending(path: "turtlepod-local-transcription-test.m4a")
        try Data("audio".utf8).write(to: audioURL, options: [.atomic])
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let episode = PodcastEpisode(
            feedID: UUID(),
            title: "Episode",
            audioURL: URL(string: "https://example.com/episode.mp3")!,
            download: EpisodeDownload(state: .downloaded, localFileURL: audioURL)
        )
        let transcriber = FakeTranscriptionProvider(
            providerName: "local-whisper-test",
            transcriptionModel: "whisper-base",
            expectedAPIKey: "",
            chunks: [
                TranscriptChunk(start: 0, end: 4, text: "Local transcript.")
            ]
        )
        let classifier = FakeAdClassificationProvider(
            providerName: "local-classifier-test",
            classificationModel: "fixture-classifier",
            expectedFirstTranscriptStart: 0,
            segments: []
        )
        let pipeline = EpisodeAnalysisPipeline(
            transcriptService: DefaultTranscriptService(
                provider: transcriber,
                chunker: FakeAudioChunker(startOffset: 0)
            ),
            adDetectionService: DefaultAdDetectionService(provider: classifier),
            transcriptionAPIKey: "",
            requiresTranscriptionAPIKey: false,
            providerMetadata: AIProviderMetadata(
                provider: transcriber.providerName,
                transcriptionProvider: transcriber.providerName,
                transcriptionModel: transcriber.transcriptionModel,
                classificationProvider: classifier.providerName,
                classificationModel: classifier.classificationModel
            )
        )

        let analysis = try await pipeline.analyze(episode)

        XCTAssertEqual(analysis.status, .complete)
        XCTAssertEqual(analysis.transcript.first?.text, "Local transcript.")
        XCTAssertEqual(analysis.providerMetadata?.transcriptionProvider, "local-whisper-test")
    }

    func testLocalWhisperAudioPreparerReportsBadAudioFormat() async throws {
        let audioURL = FileManager.default.temporaryDirectory
            .appending(path: "turtlepod-invalid-whisper-audio.mp3")
        try Data("not audio".utf8).write(to: audioURL, options: [.atomic])
        defer { try? FileManager.default.removeItem(at: audioURL) }

        do {
            _ = try await LocalWhisperAudioPreparer.prepare(audioURL)
            XCTFail("Expected localModelGenerationFailed")
        } catch {
            guard case TurtlePodError.localModelGenerationFailed(let message) = error else {
                return XCTFail("Expected localModelGenerationFailed, got \(error)")
            }
            XCTAssertTrue(message.contains("could not read this audio file"))
        }
    }
}

private struct FakeTranscriptionProvider: TranscriptionProvider {
    var providerName = "openai-test"
    var transcriptionModel = "fixture-transcriber"
    var expectedAPIKey = "test-key"
    let chunks: [TranscriptChunk]

    func transcribe(audioFile: URL, apiKey: String) async throws -> [TranscriptChunk] {
        XCTAssertEqual(apiKey, expectedAPIKey)
        return chunks
    }
}

private struct FakeAdClassificationProvider: AdClassificationProvider {
    let providerName: String
    let classificationModel: String
    let expectedFirstTranscriptStart: TimeInterval
    let segments: [AdSegment]

    func classify(transcript: [TranscriptChunk], apiKey: String) async throws -> [AdSegment] {
        XCTAssertTrue(apiKey.isEmpty)
        XCTAssertEqual(transcript[0].start, expectedFirstTranscriptStart)
        return segments
    }
}

private struct FakeAudioChunker: AudioChunker {
    let startOffset: TimeInterval

    func chunks(for audioFile: URL, maxDuration: TimeInterval) async throws -> [AudioChunk] {
        [
            AudioChunk(
                fileURL: audioFile,
                startOffset: startOffset,
                duration: 30,
                isTemporary: false
            )
        ]
    }
}
