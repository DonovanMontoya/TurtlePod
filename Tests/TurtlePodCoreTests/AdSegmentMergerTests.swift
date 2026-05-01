import XCTest
@testable import TurtlePodCore

final class AdSegmentMergerTests: XCTestCase {
    func testMergesOverlappingAndAdjacentSegments() {
        let segments = [
            AdSegment(start: 30, end: 45, confidence: 0.7, reason: "promo", provider: "test", model: "mock"),
            AdSegment(start: 44, end: 60, confidence: 0.9, reason: "sponsor", provider: "test", model: "mock"),
            AdSegment(start: 61, end: 75, confidence: 0.8, reason: "code", provider: "test", model: "mock"),
            AdSegment(start: 120, end: 130, confidence: 0.8, reason: "midroll", provider: "test", model: "mock")
        ]

        let merged = AdSegmentMerger.merge(segments, gapTolerance: 2)

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged[0].start, 30)
        XCTAssertEqual(merged[0].end, 75)
        XCTAssertEqual(merged[0].confidence, 0.9)
        XCTAssertEqual(merged[1].start, 120)
    }
}
