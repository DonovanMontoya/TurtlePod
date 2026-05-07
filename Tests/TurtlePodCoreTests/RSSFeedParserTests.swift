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

    func testDecodesHTMLSpacesAndEntitiesInEpisodeDescription() throws {
        let xml = """
        <rss>
          <channel>
            <title>Turtle Talk</title>
            <item>
              <title>Entity Cleanup</title>
              <description><![CDATA[<p>One&nbsp;two&#160;three&#xA0;&amp;&nbsp;four</p><p>Five&nbsp;&quot;six&quot;</p>]]></description>
              <enclosure url="https://example.com/episodes/entity-cleanup.mp3" type="audio/mpeg" />
            </item>
          </channel>
        </rss>
        """

        let feed = try RSSFeedParser.parse(
            data: Data(xml.utf8),
            feedURL: URL(string: "https://example.com/feed.xml")!
        )

        let episode = try XCTUnwrap(feed.episodes.first)
        XCTAssertEqual(episode.description, "One two three & four\n\nFive \"six\"")
    }
}
