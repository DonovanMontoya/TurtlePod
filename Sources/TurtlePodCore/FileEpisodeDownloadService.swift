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

    public func download(_ episode: PodcastEpisode) async throws -> EpisodeDownload {
        let (temporaryURL, response) = try await session.download(from: episode.audioURL)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }

        let destination = downloadsDirectory
            .appending(path: episode.id.uuidString, directoryHint: .notDirectory)
            .appendingPathExtension(episode.audioURL.pathExtension.isEmpty ? "mp3" : episode.audioURL.pathExtension)

        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)

        return EpisodeDownload(state: .downloaded, localFileURL: destination, progress: 1)
    }

    public func deleteDownload(for episode: PodcastEpisode) async throws {
        guard let localFileURL = episode.download?.localFileURL else { return }
        if FileManager.default.fileExists(atPath: localFileURL.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: localFileURL)
        }
    }
}
