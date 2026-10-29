import Foundation
import XCTest
@testable import TurtlePodCore

/// Times the real ad pipeline on a local episode. Skipped unless
/// TURTLEPOD_BENCH_AUDIO and TURTLEPOD_BENCH_OUT are set.
///
/// - TURTLEPOD_BENCH_TRANSCRIBER: `apple` (default) or `openai`
/// - TURTLEPOD_BENCH_CLASSIFIER: `openai` (default) or `jev`
/// - TURTLEPOD_BENCH_OPENAI_KEY_FILE: file holding an OpenAI key, for `openai`
final class AdPipelineBenchmarkTests: XCTestCase {
    private var environment: [String: String] { ProcessInfo.processInfo.environment }

    private func outputDirectory() throws -> URL {
        guard let path = environment["TURTLEPOD_BENCH_OUT"] else {
            throw XCTSkip("Set TURTLEPOD_BENCH_OUT to run the pipeline benchmark.")
        }
        let url = URL(filePath: path, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func openAIKey() throws -> String {
        guard let path = environment["TURTLEPOD_BENCH_OPENAI_KEY_FILE"] else {
            throw XCTSkip("Set TURTLEPOD_BENCH_OPENAI_KEY_FILE for OpenAI runs.")
        }
        return try String(contentsOfFile: path, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func testTranscription() async throws {
        guard let path = environment["TURTLEPOD_BENCH_AUDIO"] else {
            throw XCTSkip("Set TURTLEPOD_BENCH_AUDIO to run the pipeline benchmark.")
        }
        let output = try outputDirectory()
        let url = URL(filePath: path)
        let name = environment["TURTLEPOD_BENCH_TRANSCRIBER"] ?? "apple"
        let provider: TranscriptionProvider
        var key = ""
        if name == "openai" {
            provider = OpenAIProvider()
            key = try openAIKey()
        } else if #available(macOS 26.0, iOS 26.0, *) {
            provider = AppleSpeechProvider()
        } else {
            throw XCTSkip("Needs Apple Speech.")
        }
        let episode = PodcastEpisode(
            feedID: UUID(), title: "Benchmark", audioURL: url,
            download: EpisodeDownload(state: .downloaded, localFileURL: url, progress: 1)
        )
        let started = ContinuousClock.now
        let transcript = try await DefaultTranscriptService(provider: provider)
            .transcribeDownloadedEpisode(episode, apiKey: key)
        let elapsed = ContinuousClock.now - started
        print("BENCH transcription[\(name)]: \(elapsed) for \(transcript.count) cues, last cue ends \(transcript.last?.end ?? 0)s")
        XCTAssertFalse(transcript.isEmpty)
        try JSONEncoder().encode(transcript).write(to: output.appending(path: "transcript-\(name).json"))
    }

    func testClassification() async throws {
        let output = try outputDirectory()
        let transcriber = environment["TURTLEPOD_BENCH_TRANSCRIBER"] ?? "apple"
        let transcriptURL = output.appending(path: "transcript-\(transcriber).json")
        guard FileManager.default.fileExists(atPath: transcriptURL.path(percentEncoded: false)) else {
            throw XCTSkip("Run testTranscription first.")
        }
        let transcript = try JSONDecoder().decode([TranscriptChunk].self, from: Data(contentsOf: transcriptURL))
        let name = environment["TURTLEPOD_BENCH_CLASSIFIER"] ?? "openai"
        let service: DefaultAdDetectionService
        switch name {
        case "decisions":
            service = DefaultAdDetectionService(
                provider: OpenAIDecisionsAdClassifier(),
                apiKey: environment["TURTLEPOD_BENCH_OFFLINE"] != nil ? "invalid" : try openAIKey()
            )
        case "apple":
            try AppleFoundationModelsAdClassifier.validateAvailability()
            service = DefaultAdDetectionService(provider: AppleFoundationModelsAdClassifier())
        case "jev":
            let keyPath = try XCTUnwrap(environment["TURTLEPOD_BENCH_OPENROUTER_KEY_FILE"])
            let key = try String(contentsOfFile: keyPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            service = DefaultAdDetectionService(provider: JevAdClassifier(route: .openRouter), apiKey: key)
        default:
            service = DefaultAdDetectionService(provider: OpenAIProvider(), apiKey: try openAIKey())
        }
        var comparison: ReferenceComparison?
        if let referencePath = environment["TURTLEPOD_BENCH_REFERENCE"] {
            let referenceURL = URL(filePath: referencePath)
            let reference = try ReferenceTranscriptParser.parse(
                Data(contentsOf: referenceURL),
                source: TranscriptSource(url: referenceURL, type: "text/vtt", label: "Publisher")
            )
            comparison = ReferenceTranscriptAlignment.compare(transcript, to: reference)
        }
        let started = ContinuousClock.now
        let segments = try await service.detectAds(in: transcript, comparison: comparison)
        let elapsed = ContinuousClock.now - started
        print("BENCH classification[\(name)]: \(elapsed), \(segments.count) segments")
        for segment in segments {
            print(String(format: "BENCH ad %7.1f-%7.1f  %.2f", segment.start, segment.end, segment.confidence))
        }
        try JSONEncoder().encode(segments).write(to: output.appending(path: "segments-\(transcriber)-\(name).json"))
    }

    /// Prints where the downloaded audio departs from the publisher transcript.
    func testReferenceComparison() throws {
        let output = try outputDirectory()
        guard let referencePath = environment["TURTLEPOD_BENCH_REFERENCE"] else {
            throw XCTSkip("Set TURTLEPOD_BENCH_REFERENCE to a publisher transcript file.")
        }
        let transcriber = environment["TURTLEPOD_BENCH_TRANSCRIBER"] ?? "apple"
        let transcript = try JSONDecoder().decode(
            [TranscriptChunk].self,
            from: Data(contentsOf: output.appending(path: "transcript-\(transcriber).json"))
        )
        let referenceURL = URL(filePath: referencePath)
        let reference = try ReferenceTranscriptParser.parse(
            Data(contentsOf: referenceURL),
            source: TranscriptSource(url: referenceURL, type: "text/vtt", label: "Publisher")
        )
        let comparison = ReferenceTranscriptAlignment.compare(transcript, to: reference)
        print(String(format: "BENCH reference matched %.1f%%, reliable %@", comparison.matchedWordFraction * 100, comparison.isReliable ? "yes" : "no"))
        for gap in comparison.candidates {
            print(String(format: "BENCH gap %7.1f-%7.1f (%.0fs)", gap.start, gap.end, gap.end - gap.start))
        }
    }

    /// Dumps each cue's Decisions probability for threshold tuning.
    func testDecisionProbabilities() async throws {
        let output = try outputDirectory()
        guard environment["TURTLEPOD_BENCH_DUMP"] != nil else { throw XCTSkip("Set TURTLEPOD_BENCH_DUMP.") }
        let transcriber = environment["TURTLEPOD_BENCH_TRANSCRIBER"] ?? "apple"
        let transcript = try JSONDecoder().decode(
            [TranscriptChunk].self,
            from: Data(contentsOf: output.appending(path: "transcript-\(transcriber).json"))
        ).sorted { $0.start < $1.start }
        let probabilities = try await OpenAIDecisionsAdClassifier().cueProbabilities(transcript, apiKey: try openAIKey())
        let rows = zip(transcript, probabilities).map { ["start": $0.start, "end": $0.end, "p": $1] }
        try JSONSerialization.data(withJSONObject: rows).write(to: output.appending(path: "probabilities-\(transcriber).json"))
    }
}
