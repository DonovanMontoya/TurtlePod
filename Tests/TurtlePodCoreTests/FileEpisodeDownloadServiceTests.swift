import Foundation
import XCTest
@testable import TurtlePodCore

final class FileEpisodeDownloadServiceTests: XCTestCase {
    func testBuildsDownloadPathFromCurrentDownloadsDirectory() throws {
        let directory = temporaryDirectory()
        let service = try FileEpisodeDownloadService(downloadsDirectory: directory)
        let episodeID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let episode = PodcastEpisode(
            id: episodeID,
            feedID: UUID(),
            title: "Episode",
            audioURL: URL(string: "https://example.com/audio.m4a")!
        )

        let url = service.localFileURL(for: episode)

        XCTAssertEqual(url.lastPathComponent, "\(episodeID.uuidString).m4a")
        XCTAssertEqual(url.deletingLastPathComponent(), directory)
    }

    func testDeleteRemovesCurrentPathWhenStoredPathIsStale() async throws {
        let directory = temporaryDirectory()
        let service = try FileEpisodeDownloadService(downloadsDirectory: directory)
        let episodeID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let currentURL = directory.appending(path: "\(episodeID.uuidString).mp3")
        FileManager.default.createFile(atPath: currentURL.path(percentEncoded: false), contents: Data("audio".utf8))

        let staleURL = temporaryDirectory().appending(path: "stale.mp3")
        let episode = PodcastEpisode(
            id: episodeID,
            feedID: UUID(),
            title: "Episode",
            audioURL: URL(string: "https://example.com/audio")!,
            download: EpisodeDownload(state: .downloaded, localFileURL: staleURL, progress: 1)
        )

        try await service.deleteDownload(for: episode)

        XCTAssertFalse(FileManager.default.fileExists(atPath: currentURL.path(percentEncoded: false)))
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "TurtlePodTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }
}
