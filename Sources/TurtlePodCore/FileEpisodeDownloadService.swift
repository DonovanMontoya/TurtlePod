import Foundation

public final class FileEpisodeDownloadService: EpisodeDownloadService {
    private let session: URLSession
    private let downloadsDirectory: URL

    public init(session: URLSession = .shared, downloadsDirectory: URL? = nil) throws {
        self.session = session
        let baseDirectory = try downloadsDirectory ?? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appending(path: "TurtlePod/Downloads", directoryHint: .isDirectory)
        self.downloadsDirectory = baseDirectory
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }

    public func download(
        _ episode: PodcastEpisode,
        progressDidChange: (@MainActor @Sendable (_ progress: Double) async -> Void)? = nil
    ) async throws -> EpisodeDownload {
        let destination = localFileURL(for: episode)
        let temporaryURL = destination
            .deletingPathExtension()
            .appendingPathExtension("download")

        if FileManager.default.fileExists(atPath: temporaryURL.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: temporaryURL)
        }
        FileManager.default.createFile(atPath: temporaryURL.path(percentEncoded: false), contents: nil)

        var didFinish = false
        defer {
            if !didFinish {
                try? FileManager.default.removeItem(at: temporaryURL)
            }
        }

        let (bytes, response) = try await session.bytes(from: episode.audioURL)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }

        await progressDidChange?(0)

        let expectedLength = response.expectedContentLength
        var downloadedBytes: Int64 = 0
        var lastReportedProgress = 0.0
        var buffer = Data()
        buffer.reserveCapacity(64 * 1024)
        let handle = try FileHandle(forWritingTo: temporaryURL)

        do {
            for try await byte in bytes {
                buffer.append(byte)
                downloadedBytes += 1

                if buffer.count >= 64 * 1024 {
                    try handle.write(contentsOf: buffer)
                    buffer.removeAll(keepingCapacity: true)
                }

                guard expectedLength > 0 else { continue }
                let progress = min(Double(downloadedBytes) / Double(expectedLength), 0.99)
                if progress - lastReportedProgress >= 0.01 {
                    lastReportedProgress = progress
                    await progressDidChange?(progress)
                }
            }

            if !buffer.isEmpty {
                try handle.write(contentsOf: buffer)
            }
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }

        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)

        didFinish = true
        await progressDidChange?(1)
        return EpisodeDownload(state: .downloaded, localFileURL: destination, progress: 1)
    }

    public func deleteDownload(for episode: PodcastEpisode) async throws {
        let candidates = [episode.download?.localFileURL, localFileURL(for: episode)]
            .compactMap(\.self)
            .reduce(into: [String: URL]()) { urlsByPath, url in
                urlsByPath[url.path(percentEncoded: false)] = url
            }
            .values

        for localFileURL in candidates where FileManager.default.fileExists(atPath: localFileURL.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: localFileURL)
        }
    }

    public func localFileURL(for episode: PodcastEpisode) -> URL {
        downloadsDirectory
            .appending(path: episode.id.uuidString, directoryHint: .notDirectory)
            .appendingPathExtension(episode.audioURL.pathExtension.isEmpty ? "mp3" : episode.audioURL.pathExtension)
    }
}
