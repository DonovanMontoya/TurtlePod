import Foundation
import XCTest
@testable import TurtlePodCore

final class OpenAIProviderParsingTests: XCTestCase {
    func testParsesVerboseTranscriptionSegments() throws {
        let data = """
        {
          "segments": [
            { "start": 0.0, "end": 3.4, "text": "Welcome back." },
            { "start": 3.4, "end": 7.2, "text": "Use code TURTLE." }
          ]
        }
        """.data(using: .utf8)!

        let chunks = try OpenAIProvider.parseTranscriptionResponse(data)

        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].start, 0)
        XCTAssertEqual(chunks[1].text, "Use code TURTLE.")
    }

    func testParsesResponsesOutputTextClassification() throws {
        let data = """
        {
          "output_text": "{\\"ad_segments\\":[{\\"start\\":12.0,\\"end\\":30.0,\\"confidence\\":0.88,\\"reason\\":\\"host-read sponsor\\"}]}"
        }
        """.data(using: .utf8)!

        let segments = try OpenAIProvider.parseClassificationResponse(data, provider: "openai", model: "mock")

        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].start, 12)
        XCTAssertEqual(segments[0].end, 30)
        XCTAssertEqual(segments[0].confidence, 0.88)
        XCTAssertEqual(segments[0].provider, "openai")
    }
}
