import Foundation
import XCTest
@testable import TurtlePodCore

final class RSSFeedParserTests: XCTestCase {
    func testParsesFeedAndEpisodesFromFixture() throws {
        let url = Bundle.module.url(forResource: "sample-feed", withExtension: "xml")!
        let data = try Data(contentsOf: url)
        let feed = try RSSFeedParser.parse(data: data, feedURL: URL(string: "https://example.com/feed.xml")!)

        XCTAssertEqual(feed.title, "Turtle Talk")
        XCTAssertEqual(feed.artworkURL?.absoluteString, "https://example.com/artwork.jpg")
        XCTAssertEqual(feed.episodes.count, 1)

        let episode = try XCTUnwrap(feed.episodes.first)
        XCTAssertEqual(episode.title, "Shell Games")
        XCTAssertEqual(episode.audioURL.absoluteString, "https://example.com/episodes/shell-games.mp3")
        XCTAssertEqual(episode.description, "A calm test episode.")
        XCTAssertEqual(episode.duration, 3723)
        XCTAssertEqual(episode.artworkURL?.absoluteString, "https://example.com/artwork.jpg")
    }
}
