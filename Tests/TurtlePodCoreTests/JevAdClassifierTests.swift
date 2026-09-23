import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import TurtlePodCore

final class JevAdClassifierTests: XCTestCase {
    private func classifier(_ route: JevRoute) -> JevAdClassifier {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [JevURLProtocol.self]
        return JevAdClassifier(route: route, session: URLSession(configuration: config))
    }

    func testBothRoutesUseDecisionAPIAndAudioTimestamps() async throws {
        let transcript = [
            TranscriptChunk(start: 0, end: 5, text: "The hosts begin the story."),
            TranscriptChunk(start: 25, end: 30, text: "Use our code for a discount on home security."),
            TranscriptChunk(start: 50, end: 55, text: "Back to the story.")
        ]
        for route in [JevRoute.typeSafe, .openRouter] {
            let ads = try await classifier(route).classify(transcript: transcript, apiKey: "test-key")
            XCTAssertEqual(ads.count, 1)
            XCTAssertEqual(ads.first?.start, 25)
            XCTAssertEqual(ads.first?.end, 30)
            XCTAssertEqual(ads.first?.confidence, 0.91)
            XCTAssertEqual(ads.first?.provider, route.provider)
        }
    }

    func testIncompleteAnswerFailsInsteadOfReturningNoAds() async throws {
        do {
            _ = try await classifier(.typeSafe).classify(
                transcript: [TranscriptChunk(start: 0, end: 2, text: "incomplete")], apiKey: "test-key")
            XCTFail("Missing decisions must fail analysis")
        } catch JevClassifierError.invalidResponse { }
    }

    func testMissingKeyFailsBeforeNetworkCall() async throws {
        do {
            _ = try await classifier(.openRouter).classify(
                transcript: [TranscriptChunk(start: 0, end: 2, text: "hello")], apiKey: " ")
            XCTFail("A key is required")
        } catch JevClassifierError.missingKey(let route) {
            XCTAssertEqual(route, "OpenRouter")
        }
    }

    func testMFMMinisode504TranscriptWhenFixtureAvailable() async throws {
        guard let path = ProcessInfo.processInfo.environment["TURTLEPOD_MFM_ASR"] else {
            throw XCTSkip("Local MFM Minisode 504 audio transcript fixture is unavailable")
        }
        let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as? [[String: Any]])
        let transcript = try rows.map { row in
            TranscriptChunk(start: try XCTUnwrap(row["start"] as? Double),
                            end: try XCTUnwrap(row["end"] as? Double),
                            text: try XCTUnwrap(row["text"] as? String))
        }
        XCTAssertGreaterThan(transcript.count, 500)
        let ads = try await classifier(.openRouter).classify(transcript: transcript, apiKey: "test-key")
        XCTAssertFalse(ads.isEmpty)
        XCTAssertTrue(ads.allSatisfy { $0.start >= transcript[0].start && $0.end <= transcript.last!.end })
    }
}

private final class JevURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let url = try XCTUnwrap(request.url)
            let body = try XCTUnwrap(request.httpBody)
            let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            let model = try XCTUnwrap(payload["model"] as? String)
            if url.path == "/api/alpha/decisions" {
                XCTAssertEqual(model, "typesafe/jev-1.13")
            } else {
                XCTAssertEqual(url.path, "/v1/systemone")
                XCTAssertEqual(model, "jev-1.13.0")
            }
            let state = try XCTUnwrap(payload["state"] as? [String: [String: String]])
            let questions = try XCTUnwrap(payload["questions"] as? [String: [String: Any]])
            XCTAssertEqual(state.count, questions.count)
            for question in questions.values { XCTAssertEqual(question["type"] as? String, "noul") }
            let answers: [String: [String: Any]] = Dictionary(uniqueKeysWithValues: state.map { key, value in
                (key.replacingOccurrences(of: "passage_", with: "ad_"),
                 ["type": "noul", "noul": (value["target"] ?? "").contains("discount") ? 0.91 : 0.08])
            })
            let result: [String: Any] = ["answers": state.values.contains { $0["target"] == "incomplete" } ? [:] : answers]
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: result))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() { }
}
