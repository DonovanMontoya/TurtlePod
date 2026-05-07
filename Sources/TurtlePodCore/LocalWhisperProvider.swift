import AVFoundation
import Foundation

public struct LocalWhisperProvider: TranscriptionProvider, Sendable {
    public let providerName = "local-whisper"
    private let modelSize: WhisperModelSize

    public var transcriptionModel: String {
        "whisper-\(modelSize.rawValue)"
    }

    public init(modelSize: WhisperModelSize = .base) {
        self.modelSize = modelSize
    }

    public func transcribe(audioFile: URL, apiKey: String) async throws -> [TranscriptChunk] {
        let preparedAudio = try await LocalWhisperAudioPreparer.prepare(audioFile)
        defer { preparedAudio.cleanup() }

        do {
            return try await WhisperModelManager.shared.transcribe(
                audioPath: preparedAudio.url.path(percentEncoded: false),
                modelSize: modelSize
            )
        } catch {
            throw TurtlePodError.localModelGenerationFailed(
                "Local Whisper could not transcribe the downloaded audio. \(error.localizedDescription)"
            )
        }
    }
}

struct PreparedLocalWhisperAudio {
    var url: URL
    var cleanup: @Sendable () -> Void
}

enum LocalWhisperAudioPreparer {
    static func prepare(_ audioFile: URL) async throws -> PreparedLocalWhisperAudio {
        do {
            guard FileManager.default.fileExists(atPath: audioFile.path(percentEncoded: false)) else {
                throw TurtlePodError.localModelGenerationFailed(
                    "Local Whisper could not read this audio file. The downloaded audio is missing."
                )
            }

            let asset = AVURLAsset(url: audioFile)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            guard !audioTracks.isEmpty else {
                throw TurtlePodError.localModelGenerationFailed(
                    "Local Whisper could not read this audio file. The downloaded audio may be incomplete or in an unsupported format."
                )
            }

            return PreparedLocalWhisperAudio(
                url: audioFile,
                cleanup: {}
            )
        } catch {
            throw TurtlePodError.localModelGenerationFailed(
                "Local Whisper could not read this audio file. The downloaded audio may be incomplete or in an unsupported format. \(error.localizedDescription)"
            )
        }
    }
}
