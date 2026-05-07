import XCTest
@testable import TurtlePodCore

final class EpisodeDescriptionCleanerTests: XCTestCase {
    func testCleansLiteralAndEncodedNonBreakingSpaces() {
        let raw = "One&nbsp;two&#160;three&#xA0;four\u{00A0}five"

        XCTAssertEqual(EpisodeDescriptionCleaner.clean(raw), "One two three four five")
    }

    func testCleansDoubleEscapedNonBreakingSpacesFromStoredDescriptions() {
        let raw = "One&amp;nbsp;two &amp;amp; three"

        XCTAssertEqual(EpisodeDescriptionCleaner.clean(raw), "One two & three")
    }

    func testStripsHTMLWhilePreservingParagraphBreaks() {
        let raw = "<p>One&nbsp;two</p><p>Three&nbsp;four</p>"

        XCTAssertEqual(EpisodeDescriptionCleaner.clean(raw), "One two\n\nThree four")
    }
}
