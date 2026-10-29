import Foundation
import Synchronization

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

        var request = URLRequest(url: episode.audioURL)
        request.setValue("TurtlePod/1.0", forHTTPHeaderField: "User-Agent")

        await progressDidChange?(0)

        let (progressUpdates, continuation) = AsyncStream.makeStream(of: Double.self, bufferingPolicy: .bufferingNewest(1))
        let reporter = Task {
            for await progress in progressUpdates {
                await progressDidChange?(progress)
            }
        }
        let delegate = DownloadProgressDelegate(continuation: continuation)

        let downloadedURL: URL
        let response: URLResponse
        do {
            (downloadedURL, response) = try await session.download(for: request, delegate: delegate)
            delegate.finish()
            await reporter.value
        } catch {
            delegate.finish()
            reporter.cancel()
            throw error
        }

        defer {
            try? FileManager.default.removeItem(at: downloadedURL)
            try? FileManager.default.removeItem(at: temporaryURL)
        }
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }
        try Task.checkCancellation()

        // Stage next to the destination first so the final rename stays on one volume.
        if FileManager.default.fileExists(atPath: temporaryURL.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: temporaryURL)
        }
        try FileManager.default.moveItem(at: downloadedURL, to: temporaryURL)
        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporaryURL)
        } else {
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
        }

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

/// Async `URLSession.download(for:delegate:)` does not deliver `didWriteData` to task delegates,
/// so progress comes from observing the created task's `Progress`.
private final class DownloadProgressDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    private struct State {
        var lastReported = 0.0
        var observation: NSKeyValueObservation?
        var isFinished = false
    }

    private let continuation: AsyncStream<Double>.Continuation
    private let state = Mutex(State())

    init(continuation: AsyncStream<Double>.Continuation) {
        self.continuation = continuation
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        let observation = task.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] progress, _ in
            self?.report(progress.fractionCompleted)
        }
        let shouldKeep = state.withLock { state in
            guard !state.isFinished else { return false }
            state.observation = observation
            return true
        }
        if !shouldKeep {
            observation.invalidate()
        }
    }

    func finish() {
        let observation = state.withLock { state in
            state.isFinished = true
            defer { state.observation = nil }
            return state.observation
        }
        observation?.invalidate()
        continuation.finish()
    }

    private func report(_ fraction: Double) {
        guard fraction.isFinite, fraction > 0 else { return }
        let progress = min(fraction, 0.99)
        let shouldReport = state.withLock { state in
            guard !state.isFinished, progress - state.lastReported >= 0.01 else { return false }
            state.lastReported = progress
            return true
        }
        if shouldReport {
            continuation.yield(progress)
        }
    }
}
