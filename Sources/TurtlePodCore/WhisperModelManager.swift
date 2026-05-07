import Foundation
import WhisperKit

public actor WhisperModelManager {
    public static let shared = WhisperModelManager()

    private var whisperKit: WhisperKit?
    private var loadedModelSize: WhisperModelSize?

    private init() {}

    public var modelFolder: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("TurtlePod/WhisperModels", isDirectory: true)
    }

    public func transcribe(audioPath: String, modelSize: WhisperModelSize) async throws -> [TranscriptChunk] {
        let kit = try await ensureReady(size: modelSize)
        let results = try await kit.transcribe(audioPath: audioPath)

        guard let result = results.first else {
            return []
        }

        return result.segments.map { segment in
            TranscriptChunk(
                start: TimeInterval(segment.start),
                end: TimeInterval(segment.end),
                text: segment.text.trimmingCharacters(in: .whitespaces)
            )
        }
    }

    private func ensureReady(size: WhisperModelSize) async throws -> WhisperKit {
        if let kit = whisperKit, loadedModelSize == size {
            return kit
        }

        whisperKit = nil
        loadedModelSize = nil

        try FileManager.default.createDirectory(at: modelFolder, withIntermediateDirectories: true)
        let config = WhisperKitConfig(
            model: "openai_whisper-\(size.rawValue)",
            downloadBase: modelFolder
        )
        let kit = try await WhisperKit(config)
        whisperKit = kit
        loadedModelSize = size
        return kit
    }

    public func deleteModel(size: WhisperModelSize) throws {
        for folder in modelFolders(for: size) where FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: folder)
        }
        if loadedModelSize == size {
            whisperKit = nil
            loadedModelSize = nil
        }
    }

    public func isModelDownloaded(size: WhisperModelSize) -> Bool {
        modelFolders(for: size).contains { folder in
            FileManager.default.fileExists(atPath: folder.path(percentEncoded: false))
        }
    }

    private func modelFolders(for size: WhisperModelSize) -> [URL] {
        let modelName = "openai_whisper-\(size.rawValue)"
        return [
            modelFolder.appendingPathComponent(modelName, isDirectory: true),
            modelFolder
                .appendingPathComponent("models", isDirectory: true)
                .appendingPathComponent("argmaxinc", isDirectory: true)
                .appendingPathComponent("whisperkit-coreml", isDirectory: true)
                .appendingPathComponent(modelName, isDirectory: true)
        ]
    }

    public static func recommendedModelSize() -> WhisperModelSize {
        let memoryGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        if memoryGB < 4 {
            return .tiny
        } else if memoryGB < 6 {
            return .base
        } else {
            return .small
        }
    }
}
