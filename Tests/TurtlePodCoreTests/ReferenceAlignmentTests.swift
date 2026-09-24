import Foundation
import XCTest
@testable import TurtlePodCore

final class ReferenceAlignmentTests: XCTestCase {
    private let introduction = "Welcome to our long conversation about the history of computers and how people learned to program these machines in the early days of electronic engineering."
    private let conclusion = "Today our guest explains several surprising discoveries about memory circuits and their connections to mathematical logic before we answer a thoughtful question from the audience."
    private var reference: ReferenceTranscript {
        ReferenceTranscript(source: TranscriptSource(url: URL(string: "https://example.com/t.txt")!), text: introduction + " " + conclusion)
    }

    func testFindsInsertionUsingDownloadTimesAfterPrerollOffset() {
        let transcript = [
            TranscriptChunk(start: 30, end: 50, text: introduction),
            TranscriptChunk(start: 50, end: 80, text: "Our sponsor sells wonderful shoes use coupon turtle to save twenty percent today"),
            TranscriptChunk(start: 80, end: 110, text: conclusion)
        ]
        let result = ReferenceTranscriptAlignment.compare(transcript, to: reference)
        XCTAssertTrue(result.isReliable)
        XCTAssertEqual(result.candidates, [TranscriptGap(start: 50, end: 80)])
    }

    func testWrongEpisodeCannotGenerateCandidates() {
        let result = ReferenceTranscriptAlignment.compare([
            TranscriptChunk(start: 0, end: 60, text: "This other show covers cooking baking flour ovens and recipes for dinner tonight")
        ], to: reference)
        XCTAssertFalse(result.isReliable)
        XCTAssertTrue(result.candidates.isEmpty)
    }

    func testPunctuationAndCaseDoNotCreateGaps() {
        let result = ReferenceTranscriptAlignment.compare([
            TranscriptChunk(start: 5, end: 30, text: introduction.uppercased()),
            TranscriptChunk(start: 35, end: 65, text: conclusion.replacingOccurrences(of: ".", with: "!"))
        ], to: reference)
        XCTAssertTrue(result.isReliable)
        XCTAssertTrue(result.candidates.isEmpty)
    }

    func testEmptyAndRepeatedTextAreNotTrusted() {
        XCTAssertFalse(ReferenceTranscriptAlignment.compare([], to: reference).isReliable)
        let repeated = String(repeating: "buy these wonderful shoes today ", count: 100)
        let ref = ReferenceTranscript(source: reference.source, text: repeated)
        XCTAssertFalse(ReferenceTranscriptAlignment.compare([TranscriptChunk(start: 0, end: 60, text: repeated)], to: ref).isReliable)
    }

    func testReferenceOnlyPipelineDoesNotInventAdSegments() async throws {
        let chunks = [TranscriptChunk(start: 0, end: 30, text: introduction),
                      TranscriptChunk(start: 30, end: 45, text: "A bonus discussion absent from the published transcript goes here"),
                      TranscriptChunk(start: 45, end: 80, text: conclusion)]
        var episode = PodcastEpisode(feedID: UUID(), title: "Test", audioURL: reference.source.url,
            download: EpisodeDownload(state: .downloaded), referenceTranscript: reference)
        episode.analysis.status = .notStarted
        let pipeline = EpisodeAnalysisPipeline(transcriptService: FixedTranscript(chunks: chunks),
            adDetectionService: DefaultAdDetectionService(provider: NoAdsClassifier()),
            transcriptionAPIKey: "", requiresTranscriptionAPIKey: false,
            providerMetadata: AIProviderMetadata(provider: "test", transcriptionModel: "test", classificationModel: "test"))
        let result = try await pipeline.analyze(episode)
        XCTAssertTrue(result.referenceComparison?.isReliable == true)
        XCTAssertEqual(result.referenceComparison?.candidates.count, 1)
        XCTAssertTrue(result.adSegments.isEmpty)
        XCTAssertEqual(result.transcript, chunks)
    }

    func testClassifierChecksMatchingContentAndRejectsInvalidRanges() async throws {
        let chunks = [TranscriptChunk(start: 30, end: 40, text: "Host read sponsor also present in publisher transcript")]
        let service = DefaultAdDetectionService(provider: InvalidRangesClassifier())
        let result = try await service.detectAds(in: chunks, comparison: ReferenceComparison(sourceLabel: "test", matchedWordFraction: 1, isReliable: true, candidates: []))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.start, 30)
    }

    func testPrioritizesCandidateWindowsWithoutDroppingMatchingContent() async throws {
        let classifier = RecordingClassifier()
        let chunks = (0..<8).map { index in
            TranscriptChunk(start: Double(index * 100), end: Double(index * 100 + 30), text: "Chunk \(index)")
        }
        let comparison = ReferenceComparison(sourceLabel: "test", matchedWordFraction: 0.8, isReliable: true,
            candidates: [TranscriptGap(start: 500, end: 530)])
        _ = try await DefaultAdDetectionService(provider: classifier).detectAds(in: chunks, comparison: comparison)
        let windows = await classifier.windows
        XCTAssertTrue(windows.first?.contains(where: { $0.start == 500 }) == true)
        XCTAssertEqual(Set(windows.flatMap { $0.map(\.id) }), Set(chunks.map(\.id)))
        XCTAssertTrue(windows.allSatisfy { ($0.last!.end - $0.first!.start) <= 300 })
    }

    func testTranscriptionFailureCleansAllExportedChunks() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = [directory.appending(path: "one.m4a"), directory.appending(path: "two.m4a")]
        for url in urls { try Data("fixture".utf8).write(to: url) }
        let episode = PodcastEpisode(feedID: UUID(), title: "Test", audioURL: reference.source.url,
            download: EpisodeDownload(state: .downloaded, localFileURL: directory.appending(path: "original.mp3")))
        let service = DefaultTranscriptService(provider: FailingTranscriber(), chunker: ExportedChunks(urls: urls))
        do {
            _ = try await service.transcribeDownloadedEpisode(episode, apiKey: "")
            XCTFail("Expected provider failure")
        } catch {}
        XCTAssertTrue(urls.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    func testUntimedAudioTranscriptFailsRatherThanProducingUnsafeSkips() async {
        do {
            _ = try await DefaultAdDetectionService(provider: NoAdsClassifier()).detectAds(in: [TranscriptChunk(start: 0, end: 0, text: "No timing")])
            XCTFail("Untimed transcription must not produce skip markers")
        } catch {}
    }
}

private struct FixedTranscript: TranscriptService {
    let chunks: [TranscriptChunk]
    func transcribeDownloadedEpisode(_ episode: PodcastEpisode, apiKey: String,
        progressDidChange: (@MainActor @Sendable (Int, Int) async -> Void)?) async throws -> [TranscriptChunk] { chunks }
}
private struct NoAdsClassifier: AdClassificationProvider {
    let providerName = "test"
    let classificationModel = "test"
    func classify(transcript: [TranscriptChunk], apiKey: String) async throws -> [AdSegment] { [] }
}
private struct InvalidRangesClassifier: AdClassificationProvider {
    let providerName = "test"
    let classificationModel = "test"
    func classify(transcript: [TranscriptChunk], apiKey: String) async throws -> [AdSegment] {
        [AdSegment(start: 30, end: 40, confidence: 0.9, reason: "sponsor", provider: "test", model: "test"),
         AdSegment(start: 0, end: 10000, confidence: 1, reason: "wrong timeline", provider: "test", model: "test"),
         AdSegment(start: 30, end: 35, confidence: 2, reason: "invalid", provider: "test", model: "test")]
    }
}

private actor RecordingClassifier: AdClassificationProvider {
    let providerName = "test"
    let classificationModel = "test"
    var windows: [[TranscriptChunk]] = []
    func classify(transcript: [TranscriptChunk], apiKey: String) async throws -> [AdSegment] {
        windows.append(transcript)
        return []
    }
}
private struct FailingTranscriber: TranscriptionProvider {
    let providerName = "test"
    let transcriptionModel = "test"
    func transcribe(audioFile: URL, apiKey: String) async throws -> [TranscriptChunk] { throw TurtlePodError.unsupportedResponse }
}
private struct ExportedChunks: AudioChunker {
    let urls: [URL]
    func chunks(for audioFile: URL, maxDuration: TimeInterval) async throws -> [AudioChunk] {
        urls.map { AudioChunk(fileURL: $0, startOffset: 0, duration: 60, isTemporary: true) }
    }
}
