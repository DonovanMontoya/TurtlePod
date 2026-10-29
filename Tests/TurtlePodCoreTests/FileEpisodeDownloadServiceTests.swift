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

    func testDownloadsToLocalFileAndReportsProgress() async throws {
        let directory = temporaryDirectory()
        let service = try FileEpisodeDownloadService(session: stubSession(), downloadsDirectory: directory)
        let episode = PodcastEpisode(feedID: UUID(), title: "Episode", audioURL: URL(string: "https://example.com/ok/audio.mp3")!)
        let recorder = ProgressRecorder()

        let download = try await service.download(episode) { progress in
            recorder.values.append(progress)
        }

        XCTAssertEqual(download.state, .downloaded)
        XCTAssertEqual(download.localFileURL, service.localFileURL(for: episode))
        let data = try Data(contentsOf: try XCTUnwrap(download.localFileURL))
        XCTAssertEqual(data, DownloadURLProtocol.payload)

        let values = await MainActor.run { recorder.values }
        XCTAssertEqual(values.first, 0)
        XCTAssertEqual(values.last, 1)
        XCTAssertEqual(values, values.sorted())
        XCTAssertTrue(values.allSatisfy { (0...1).contains($0) })
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appending(path: "\(episode.id.uuidString).download").path(percentEncoded: false)
        ))

        // A second download replaces the existing file in place.
        let again = try await service.download(episode)
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(again.localFileURL)), DownloadURLProtocol.payload)
    }

    func testDownloadRejectsNonSuccessStatus() async throws {
        let directory = temporaryDirectory()
        let service = try FileEpisodeDownloadService(session: stubSession(), downloadsDirectory: directory)
        let episode = PodcastEpisode(feedID: UUID(), title: "Episode", audioURL: URL(string: "https://example.com/missing/audio.mp3")!)

        do {
            _ = try await service.download(episode)
            XCTFail("Expected bad server response")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .badServerResponse)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: service.localFileURL(for: episode).path(percentEncoded: false)))
    }

    private func stubSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DownloadURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "TurtlePodTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }
}

@MainActor
private final class ProgressRecorder: Sendable {
    var values: [Double] = []
}

private final class DownloadURLProtocol: URLProtocol, @unchecked Sendable {
    static let payload = Data((0..<400_000).map { UInt8($0 % 251) })

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        guard request.value(forHTTPHeaderField: "User-Agent") == "TurtlePod/1.0", url.path().hasPrefix("/ok/") else {
            let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: [:])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("not found".utf8))
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let payload = Self.payload
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
            "Content-Type": "audio/mpeg",
            "Content-Length": "\(payload.count)"
        ])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        var offset = 0
        while offset < payload.count {
            let end = min(offset + 16_384, payload.count)
            client?.urlProtocol(self, didLoad: payload.subdata(in: offset..<end))
            offset = end
        }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
