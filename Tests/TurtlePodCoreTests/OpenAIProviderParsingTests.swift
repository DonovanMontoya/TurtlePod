import Foundation
import XCTest
@testable import TurtlePodCore

final class OpenAIProviderParsingTests: XCTestCase {
    func testUsesLowCostDefaultModels() {
        let provider = OpenAIProvider()

        XCTAssertEqual(provider.transcriptionModel, "whisper-1")
        XCTAssertEqual(provider.classificationModel, "gpt-4o-mini")
    }

    func testUsesSupportedTranscriptionResponseFormatForModel() {
        XCTAssertEqual(OpenAIProvider.transcriptionResponseFormat(for: "gpt-4o-mini-transcribe"), "json")
        XCTAssertEqual(OpenAIProvider.transcriptionResponseFormat(for: "gpt-4o-transcribe"), "json")
        XCTAssertEqual(OpenAIProvider.transcriptionResponseFormat(for: "whisper-1"), "verbose_json")
    }

    func testRequestsSegmentTimestampsForTimestampCapableModel() {
        XCTAssertEqual(OpenAIProvider.transcriptionTimestampGranularities(for: "whisper-1"), ["segment"])
        XCTAssertEqual(OpenAIProvider.transcriptionTimestampGranularities(for: "gpt-4o-mini-transcribe"), [])
    }

    func testFormatsTranscriptWindowsWithSubsecondTimestamps() {
        let transcript = [
            TranscriptChunk(start: 12.34, end: 16.98, text: "Use code TURTLE."),
            TranscriptChunk(start: 16.98, end: 19.41, text: "Now back to the show.")
        ]

        XCTAssertEqual(
            OpenAIProvider.transcriptWindowText(transcript),
            """
            [12.3-17.0] Use code TURTLE.
            [17.0-19.4] Now back to the show.
            """
        )
    }

    func testBuildsResponsesClassificationPayloadWithTypedInputAndJSONSchema() throws {
        let payload = OpenAIProvider.classificationRequestPayload(
            model: "gpt-4o-mini",
            schemaInstruction: "Return ad JSON.",
            transcriptWindowText: "[0.0-4.0] Use code TURTLE."
        )

        let data = try JSONSerialization.data(withJSONObject: payload)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertNil(object["temperature"])
        let input = try XCTUnwrap(object["input"] as? [[String: Any]])
        XCTAssertEqual(input.count, 2)
        XCTAssertEqual(input[0]["type"] as? String, "message")
        XCTAssertEqual(input[0]["role"] as? String, "system")

        let systemContent = try XCTUnwrap(input[0]["content"] as? [[String: Any]])
        XCTAssertEqual(systemContent[0]["type"] as? String, "input_text")
        XCTAssertEqual(systemContent[0]["text"] as? String, "Return ad JSON.")

        let text = try XCTUnwrap(object["text"] as? [String: Any])
        let format = try XCTUnwrap(text["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        XCTAssertEqual(format["strict"] as? Bool, true)

        let schema = try XCTUnwrap(format["schema"] as? [String: Any])
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
        XCTAssertEqual(schema["required"] as? [String], ["ad_segments"])
    }

    func testUsesAudioContentTypeForFileExtension() {
        XCTAssertEqual(OpenAIProvider.audioContentType(for: URL(fileURLWithPath: "/tmp/audio.m4a")), "audio/mp4")
        XCTAssertEqual(OpenAIProvider.audioContentType(for: URL(fileURLWithPath: "/tmp/audio.wav")), "audio/wav")
        XCTAssertEqual(OpenAIProvider.audioContentType(for: URL(fileURLWithPath: "/tmp/audio.mp3")), "audio/mpeg")
    }

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
