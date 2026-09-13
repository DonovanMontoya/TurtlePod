import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import TurtlePodCore

final class ReferenceHTTPTests: XCTestCase {
    private func service() -> HTTPReferenceTranscriptService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TranscriptURLProtocol.self]
        return HTTPReferenceTranscriptService(session: URLSession(configuration: configuration))
    }

    func testFetchesTranscriptAndRetainsAttribution() async throws {
        let source = TranscriptSource(url: URL(string: "https://example.com/ok.vtt")!, label: "Publisher")
        let result = try await service().fetch(source)
        XCTAssertEqual(result.text, "An actual transcript.")
        XCTAssertEqual(result.source.label, "Publisher")
        XCTAssertEqual(result.source.url, source.url)
    }

    func testAccessDeniedIsExplicit() async throws {
        for status in [401, 403, 404, 500] {
            let source = TranscriptSource(url: URL(string: "https://example.com/\(status)")!)
            do {
                _ = try await service().fetch(source)
                XCTFail("HTTP \(status) must not become a reference")
            } catch let error as ReferenceTranscriptError {
                switch error {
                case .accessDenied: XCTAssertTrue([401, 403].contains(status))
                case .http(let code): XCTAssertEqual(code, status)
                default: XCTFail("Unexpected \(error)")
                }
            }
        }
    }

    func testRejectsLocalURLBeforeRequest() async throws {
        do {
            _ = try await service().fetch(TranscriptSource(url: URL(fileURLWithPath: "/etc/passwd")))
            XCTFail("Local URLs require explicit file import")
        } catch ReferenceTranscriptError.invalidURL {} catch { XCTFail("Unexpected \(error)") }
    }
}

private final class TranscriptURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        let status = Int(url.lastPathComponent) ?? 200
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/vtt"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("WEBVTT\n\n00:00.000 --> 00:02.000\nAn actual transcript.\n".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
