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

    func testParsesChannelAndEpisodeMetadata() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0"
             xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"
             xmlns:atom="http://www.w3.org/2005/Atom"
             xmlns:podcast="https://podcastindex.org/namespace/1.0">
          <channel>
            <atom:link href="https://example.com/feed.xml" rel="self" type="application/rss+xml" />
            <title>Turtle Talk</title>
            <link>https://example.com/show</link>
            <description><![CDATA[<p>All about&nbsp;turtles.</p>]]></description>
            <itunes:summary>Summary fallback.</itunes:summary>
            <managingEditor>editor@example.com (Editor)</managingEditor>
            <itunes:author>Shelly Turtle</itunes:author>
            <image>
              <url>https://example.com/rss-image.jpg</url>
              <title>Image Title</title>
              <link>https://example.com/image-link</link>
            </image>
            <itunes:image href="https://example.com/artwork.jpg" />
            <item>
              <title>Shell Games</title>
              <link>https://example.com/episodes/1</link>
              <itunes:episode>12</itunes:episode>
              <itunes:season>3</itunes:season>
              <itunes:episodeType>Bonus</itunes:episodeType>
              <itunes:image href="https://example.com/episode.jpg" />
              <podcast:chapters url="chapters/1.json" type="application/json+chapters" />
              <enclosure url="https://example.com/episodes/1.mp3" type="audio/mpeg" />
            </item>
            <item>
              <title>Plain</title>
              <enclosure url="https://example.com/episodes/2.mp3" type="audio/mpeg" />
            </item>
          </channel>
        </rss>
        """

        let before = Date()
        let feed = try RSSFeedParser.parse(data: Data(xml.utf8), feedURL: URL(string: "https://example.com/feed.xml")!)

        XCTAssertEqual(feed.title, "Turtle Talk")
        XCTAssertEqual(feed.author, "Shelly Turtle")
        XCTAssertEqual(feed.summary, "All about turtles.")
        XCTAssertEqual(feed.websiteURL?.absoluteString, "https://example.com/show")
        XCTAssertEqual(feed.artworkURL?.absoluteString, "https://example.com/artwork.jpg")
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(feed.lastRefreshedAt), before)

        let first = feed.episodes[0]
        XCTAssertEqual(first.title, "Shell Games")
        XCTAssertEqual(first.websiteURL?.absoluteString, "https://example.com/episodes/1")
        XCTAssertEqual(first.episodeNumber, 12)
        XCTAssertEqual(first.seasonNumber, 3)
        XCTAssertEqual(first.episodeType, "bonus")
        XCTAssertEqual(first.artworkURL?.absoluteString, "https://example.com/episode.jpg")
        XCTAssertEqual(first.chaptersURL?.absoluteString, "https://example.com/chapters/1.json")

        let second = feed.episodes[1]
        XCTAssertNil(second.websiteURL)
        XCTAssertNil(second.episodeNumber)
        XCTAssertNil(second.chaptersURL)
        XCTAssertEqual(second.artworkURL?.absoluteString, "https://example.com/artwork.jpg")
    }

    func testChannelMetadataFallbacksAndAlternatePrefixes() throws {
        let xml = """
        <rss xmlns:i="http://www.itunes.com/dtds/podcast-1.0.dtd" xmlns:pi="https://podcastindex.org/namespace/1.0">
          <channel>
            <title>Fallbacks</title>
            <managingEditor>editor@example.com</managingEditor>
            <i:summary>Only a summary.</i:summary>
            <i:image href="https://example.com/art.jpg" />
            <item>
              <title>One</title>
              <i:episode>4</i:episode>
              <pi:chapters url="https://example.com/c.json" type="application/json+chapters" />
              <enclosure url="https://example.com/1.mp3" />
            </item>
          </channel>
        </rss>
        """

        let feed = try RSSFeedParser.parse(data: Data(xml.utf8), feedURL: URL(string: "https://example.com/feed.xml")!)

        XCTAssertEqual(feed.title, "Fallbacks")
        XCTAssertEqual(feed.author, "editor@example.com")
        XCTAssertEqual(feed.summary, "Only a summary.")
        XCTAssertNil(feed.websiteURL)
        XCTAssertEqual(feed.artworkURL?.absoluteString, "https://example.com/art.jpg")
        XCTAssertEqual(feed.episodes.first?.episodeNumber, 4)
        XCTAssertEqual(feed.episodes.first?.chaptersURL?.absoluteString, "https://example.com/c.json")
    }
}
