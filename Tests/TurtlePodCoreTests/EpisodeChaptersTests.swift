import Foundation
import XCTest
@testable import TurtlePodCore

final class EpisodeChaptersTests: XCTestCase {
    func testParsesPodcastingChaptersJSON() throws {
        let json = """
        {"version":"1.2.0","chapters":[
          {"startTime":120.5,"title":"Main Topic","img":"https://example.com/main.jpg","url":"https://example.com/link"},
          {"startTime":0,"title":"Intro"},
          {"startTime":60,"title":"Hidden Marker","toc":false},
          {"startTime":"300","endTime":360,"title":"Outro","url":"javascript:alert(1)"}
        ]}
        """

        let chapters = try PodcastChaptersParser.parse(Data(json.utf8))

        XCTAssertEqual(chapters.map(\.title), ["Intro", "Main Topic", "Outro"])
        XCTAssertEqual(chapters.map(\.start), [0, 120.5, 300])
        XCTAssertEqual(chapters.map(\.end), [120.5, 300, 360])
        XCTAssertEqual(chapters[1].imageURL?.absoluteString, "https://example.com/main.jpg")
        XCTAssertEqual(chapters[1].linkURL?.absoluteString, "https://example.com/link")
        XCTAssertNil(chapters[2].linkURL)
    }

    func testRejectsMalformedChapters() {
        XCTAssertThrowsError(try PodcastChaptersParser.parse(Data("{\"version\":\"1.2.0\"}".utf8)))
    }

    func testFindsChapterAtTime() {
        let chapters = [
            EpisodeChapter(start: 0, end: 10, title: "A"),
            EpisodeChapter(start: 10, end: 20, title: "B"),
            EpisodeChapter(start: 20, title: "C")
        ]

        XCTAssertNil(EpisodeChapterLoader.chapter(at: -1, in: chapters))
        XCTAssertEqual(EpisodeChapterLoader.chapter(at: 0, in: chapters)?.title, "A")
        XCTAssertEqual(EpisodeChapterLoader.chapter(at: 10, in: chapters)?.title, "B")
        XCTAssertEqual(EpisodeChapterLoader.chapter(at: 999, in: chapters)?.title, "C")
        XCTAssertNil(EpisodeChapterLoader.chapter(at: 5, in: []))
    }

    func testEmbeddedChaptersReturnsEmptyForMissingFile() async {
        let url = FileManager.default.temporaryDirectory.appending(path: "missing-\(UUID().uuidString).mp3")
        let chapters = await EpisodeChapterLoader.embeddedChapters(in: url)
        XCTAssertTrue(chapters.isEmpty)
    }
}
