import Foundation
import XCTest
@testable import TurtlePodCore

final class PodcastDirectoryServiceTests: XCTestCase {
    func testParsesLookupAndDropsResultsWithoutFeed() throws {
        let results = try ITunesDirectoryParser.parseLookup(Data(Self.lookupJSON.utf8))

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0], PodcastSearchResult(
            id: 1528594034,
            title: "Hard Fork",
            author: "The New York Times",
            feedURL: URL(string: "https://feeds.simplecast.com/6HKOhNgS")!,
            artworkURL: URL(string: "https://example.com/600x600bb.jpg")!,
            genre: "Technology",
            episodeCount: 221
        ))
        XCTAssertEqual(results[1].id, 1200361736)
        XCTAssertEqual(results[1].artworkURL?.absoluteString, "https://example.com/100x100bb.jpg")
        XCTAssertNil(results[1].genre)
    }

    func testParsesTopChartIDsInOrder() throws {
        let json = """
        {"feed":{"title":"Top Shows","results":[
          {"artistName":"The New York Times","id":"1200361736","name":"The Daily","kind":"podcasts"},
          {"id":"1528594034","name":"Hard Fork","kind":"podcasts"},
          {"id":"not-a-number","name":"Broken","kind":"podcasts"}
        ]}}
        """
        XCTAssertEqual(try ITunesDirectoryParser.parseTopChartIDs(Data(json.utf8)), [1200361736, 1528594034])
    }

    func testTopPodcastsReturnsChartOrderAndSearchEncodesTerm() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DirectoryURLProtocol.self]
        let service = ITunesPodcastDirectoryService(session: URLSession(configuration: configuration), countryCode: "GB")

        let top = try await service.topPodcasts(limit: 2)
        XCTAssertEqual(top.map(\.id), [1200361736, 1528594034])

        let search = try await service.search("hard fork & friends")
        XCTAssertEqual(search.count, 2)

        let empty = try await service.search("   ")
        XCTAssertTrue(empty.isEmpty)
    }

    func testThrowsOnHTTPError() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DirectoryURLProtocol.self]
        let service = ITunesPodcastDirectoryService(session: URLSession(configuration: configuration), countryCode: "zz")
        do {
            _ = try await service.topPodcasts(limit: 5)
            XCTFail("Expected HTTP failure")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .badServerResponse)
        } catch {
            XCTFail("Unexpected \(error)")
        }
    }

    static let lookupJSON = """
    {"resultCount":3,"results":[
      {"wrapperType":"track","kind":"podcast","collectionId":1528594034,"trackId":1528594034,
       "artistName":"The New York Times","collectionName":"Hard Fork","trackName":"Hard Fork",
       "feedUrl":"https://feeds.simplecast.com/6HKOhNgS",
       "artworkUrl100":"https://example.com/100x100bb.jpg","artworkUrl600":"https://example.com/600x600bb.jpg",
       "trackCount":221,"primaryGenreName":"Technology"},
      {"wrapperType":"track","kind":"podcast","collectionId":999,"collectionName":"No Feed"},
      {"wrapperType":"track","kind":"podcast","collectionId":1200361736,
       "artistName":"The New York Times","collectionName":"The Daily",
       "feedUrl":"https://feeds.simplecast.com/54nAGcIl",
       "artworkUrl100":"https://example.com/100x100bb.jpg"}
    ]}
    """
}

private final class DirectoryURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        var status = 200
        var body = Data()

        switch (url.host(), url.path()) {
        case ("rss.marketingtools.apple.com", "/api/v2/gb/podcasts/top/2/podcasts.json"):
            body = Data(#"{"feed":{"results":[{"id":"1200361736"},{"id":"1528594034"}]}}"#.utf8)
        case ("itunes.apple.com", "/lookup") where query["id"] == "1200361736,1528594034" && query["entity"] == "podcast":
            body = Data(PodcastDirectoryServiceTests.lookupJSON.utf8)
        case ("itunes.apple.com", "/search")
            where query["term"] == "hard fork & friends" && query["media"] == "podcast"
            && query["entity"] == "podcast" && query["limit"] == "40"
            && url.absoluteString.contains("term=hard%20fork%20%26%20friends"):
            body = Data(PodcastDirectoryServiceTests.lookupJSON.utf8)
        default:
            status = 404
        }

        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
