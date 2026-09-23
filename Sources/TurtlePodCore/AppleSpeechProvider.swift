import AVFoundation
import CoreMedia
import Foundation
import Speech

@available(iOS 26.0, macOS 26.0, *)
public struct AppleSpeechProvider: TranscriptionProvider, Sendable {
    public let providerName = "apple-speech"
    public let transcriptionModel = "speech-transcriber"

    public init() {}

    public static func modelStatusMessage() async -> String {
        guard SpeechTranscriber.isAvailable else {
            return "Apple Speech transcription is not available on this device."
        }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")) else {
            return "Apple Speech does not support English transcription on this device."
        }
        let transcriber = makeTranscriber(locale: locale)
        switch await AssetInventory.status(forModules: [transcriber]) {
        case .installed:
            return "Ready on this device. English transcription runs on device."
        case .supported:
            return "English model will download when you first analyze an episode."
        case .downloading:
            return "English model is downloading. Transcription will start when it is ready."
        case .unsupported:
            return "Apple Speech cannot use the English model on this device."
        @unknown default:
            return "Apple Speech model status is unavailable."
        }
    }

    public func transcribe(audioFile: URL, apiKey: String) async throws -> [TranscriptChunk] {
        guard SpeechTranscriber.isAvailable else {
            throw TurtlePodError.localModelUnavailable("Apple Speech transcription is unavailable on this device.")
        }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")) else {
            throw TurtlePodError.localModelUnavailable("Apple Speech does not support English transcription on this device.")
        }

        let transcriber = Self.makeTranscriber(locale: locale)
        let status = await AssetInventory.status(forModules: [transcriber])
        guard status != .unsupported else {
            throw TurtlePodError.localModelUnavailable("Apple Speech cannot use the English model on this device.")
        }
        if status != .installed,
           let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
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

    private static func makeTranscriber(locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [],
                          attributeOptions: [.audioTimeRange])
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
