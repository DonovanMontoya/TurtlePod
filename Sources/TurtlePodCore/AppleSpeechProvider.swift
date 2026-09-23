import AVFoundation
import CoreMedia
import Foundation
import Speech

@available(iOS 26.0, macOS 26.0, *)
public struct AppleSpeechProvider: TranscriptionProvider, Sendable {
    public let providerName = "apple-speech"
    public let transcriptionModel = "speech-transcriber"

    public init() {}

    public static var availabilityStatusMessage: String {
        SpeechTranscriber.isAvailable
            ? "On-device transcription in English. Apple's language model downloads on first use."
            : "Apple Speech transcription is not available on this device."
    }

    public func transcribe(audioFile: URL, apiKey: String) async throws -> [TranscriptChunk] {
        guard SpeechTranscriber.isAvailable else {
            throw TurtlePodError.localModelUnavailable("Apple Speech transcription is unavailable on this device.")
        }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")) else {
            throw TurtlePodError.localModelUnavailable("Apple Speech does not support English transcription on this device.")
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange]
        )
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }

        let file = try AVAudioFile(forReading: audioFile)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        async let results = Self.collectFinalResults(from: transcriber)
        do {
            if let lastSample = try await analyzer.analyzeSequence(from: file) {
                try await analyzer.finalizeAndFinish(through: lastSample)
            } else {
                await analyzer.cancelAndFinishNow()
            }
            let transcript = try await results
            guard !transcript.isEmpty else { throw TurtlePodError.unsupportedResponse }
            return transcript
        } catch {
            await analyzer.cancelAndFinishNow()
            throw error
        }
    }

    private static func collectFinalResults(from transcriber: SpeechTranscriber) async throws -> [TranscriptChunk] {
        var chunks: [TranscriptChunk] = []
        for try await result in transcriber.results where result.isFinal {
            let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
            let start = CMTimeGetSeconds(result.range.start)
            let end = CMTimeGetSeconds(CMTimeRangeGetEnd(result.range))
            guard !text.isEmpty, start.isFinite, end.isFinite, start >= 0, end > start else { continue }
            chunks.append(TranscriptChunk(start: start, end: end, text: text))
        }
        return chunks
    }
}
