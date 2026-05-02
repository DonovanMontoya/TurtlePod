import AVFoundation
import Foundation

public struct AudioChunk: Sendable {
    public var fileURL: URL
    public var startOffset: TimeInterval
    public var duration: TimeInterval
    public var isTemporary: Bool

    public init(fileURL: URL, startOffset: TimeInterval, duration: TimeInterval, isTemporary: Bool) {
        self.fileURL = fileURL
        self.startOffset = startOffset
        self.duration = duration
        self.isTemporary = isTemporary
    }
}

public protocol AudioChunker: Sendable {
    func chunks(for audioFile: URL, maxDuration: TimeInterval) async throws -> [AudioChunk]
}

public struct AVAssetAudioChunker: AudioChunker {
    private let outputDirectory: URL

    public init(outputDirectory: URL? = nil) {
        self.outputDirectory = outputDirectory ?? FileManager.default.temporaryDirectory
            .appending(path: "TurtlePodAudioChunks", directoryHint: .isDirectory)
    }

    public func chunks(for audioFile: URL, maxDuration: TimeInterval = 600) async throws -> [AudioChunk] {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let asset = AVURLAsset(url: audioFile)
        let duration: TimeInterval
        do {
            duration = try await asset.load(.duration).seconds
        } catch {
            let fileSize = try FileManager.default.attributesOfItem(atPath: audioFile.path(percentEncoded: false))[.size] as? NSNumber
            if let fileSize, fileSize.int64Value <= 25 * 1024 * 1024 {
                return [AudioChunk(fileURL: audioFile, startOffset: 0, duration: 0, isTemporary: false)]
            }
            throw TurtlePodError.audioInspectionFailed(error.localizedDescription)
        }

        guard duration.isFinite, duration > maxDuration else {
            return [AudioChunk(fileURL: audioFile, startOffset: 0, duration: max(duration, 0), isTemporary: false)]
        }

        var chunks: [AudioChunk] = []
        var offset: TimeInterval = 0
        while offset < duration {
            let chunkDuration = min(maxDuration, duration - offset)
            let outputURL = outputDirectory
                .appending(path: "\(audioFile.deletingPathExtension().lastPathComponent)-\(Int(offset)).m4a")
            if FileManager.default.fileExists(atPath: outputURL.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: outputURL)
            }

            try await export(asset: asset, start: offset, duration: chunkDuration, outputURL: outputURL)
            chunks.append(AudioChunk(fileURL: outputURL, startOffset: offset, duration: chunkDuration, isTemporary: true))
            offset += chunkDuration
        }

        return chunks
    }

    private func export(asset: AVURLAsset, start: TimeInterval, duration: TimeInterval, outputURL: URL) async throws {
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw TurtlePodError.unsupportedResponse
        }

        exportSession.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: duration, preferredTimescale: 600)
        )

        try await exportSession.export(to: outputURL, as: .m4a)
    }
}
