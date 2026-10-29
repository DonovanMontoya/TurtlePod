import Foundation
import XCTest
@testable import TurtlePodCore

final class OPMLTests: XCTestCase {
    func testParsesNestedOutlinesAndDedupesByURL() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head><title>Exported</title></head>
          <body>
            <outline text="Tech">
              <outline type="rss" text="Shell Talk" title="Shell Talk" xmlUrl="https://example.com/shell.xml" />
              <outline text="Folder">
                <outline text="Deep &amp; Nested" xmlUrl="https://example.com/deep.xml" />
              </outline>
            </outline>
            <outline type="rss" text="Duplicate" xmlUrl="https://example.com/shell.xml" />
            <outline type="rss" text="Feed Scheme" xmlURL="feed://example.com/feed-scheme.xml" />
            <outline type="link" text="Not a feed" url="https://example.com" />
          </body>
        </opml>
        """

        let outlines = try OPMLParser.parse(Data(xml.utf8))

        XCTAssertEqual(outlines, [
            OPMLOutline(title: "Shell Talk", feedURL: URL(string: "https://example.com/shell.xml")!),
            OPMLOutline(title: "Deep & Nested", feedURL: URL(string: "https://example.com/deep.xml")!),
            OPMLOutline(title: "Feed Scheme", feedURL: URL(string: "https://example.com/feed-scheme.xml")!)
        ])
    }

    func testThrowsWhenNoFeeds() {
        let xml = "<opml version=\"2.0\"><body><outline text=\"Empty\" /></body></opml>"
        XCTAssertThrowsError(try OPMLParser.parse(Data(xml.utf8))) { error in
            XCTAssertEqual(error as? OPMLError, .noFeeds)
            XCTAssertNotNil((error as? LocalizedError)?.errorDescription)
        }
        XCTAssertThrowsError(try OPMLParser.parse(Data("not xml at all".utf8)))
    }

    func testExportEscapesAndRoundTrips() throws {
        let feeds = [
            PodcastFeed(title: "Rock & Roll <Live> \"Quoted\"", feedURL: URL(string: "https://example.com/feed.xml?a=1&b=2")!),
            PodcastFeed(title: "Turtle's Talk", feedURL: URL(string: "https://example.com/turtle.xml")!, websiteURL: URL(string: "https://example.com")!)
        ]

        let data = OPMLExporter.export(feeds)
        let xml = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(xml.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"))
        XCTAssertTrue(xml.contains("<opml version=\"2.0\">"))
        XCTAssertTrue(xml.contains("<title>TurtlePod Subscriptions</title>"))
        XCTAssertTrue(xml.contains("Rock &amp; Roll &lt;Live&gt; &quot;Quoted&quot;"))
        XCTAssertTrue(xml.contains("xmlUrl=\"https://example.com/feed.xml?a=1&amp;b=2\""))
        XCTAssertTrue(xml.contains("htmlUrl=\"https://example.com\""))

        let outlines = try OPMLParser.parse(data)
        XCTAssertEqual(outlines.map(\.title), feeds.map(\.title))
        XCTAssertEqual(outlines.map(\.feedURL), feeds.map(\.feedURL))
    }
}
