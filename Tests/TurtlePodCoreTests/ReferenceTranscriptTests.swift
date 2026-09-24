import Foundation
import XCTest
@testable import TurtlePodCore

final class ReferenceTranscriptTests: XCTestCase {
    private func source(_ ext: String) -> TranscriptSource {
        TranscriptSource(url: URL(string: "https://example.com/transcript.\(ext)")!, label: "Publisher")
    }

    func testVTTDiscardsTimestampsHeadersAndCueLabels() throws {
        let data = Data("\u{FEFF}WEBVTT\r\n\r\nNOTE metadata\r\nignored\r\n\r\ncue-1\r\n00:01.000 --> 00:03.000 align:start\r\n<v Alice>Hello &amp; welcome.</v>\r\n\r\ncue-2\r\n00:05.000 --> 00:08.000\r\nThe actual show.\r\n".utf8)
        let parsed = try ReferenceTranscriptParser.parse(data, source: source("vtt"))
        XCTAssertEqual(parsed.text, "Hello & welcome.\nThe actual show.")
    }

    func testSRTAndPodcastIndexJSON() throws {
        let srt = Data("1\n00:00:01,000 --> 00:00:02,000\nHello world.\n".utf8)
        XCTAssertEqual(try ReferenceTranscriptParser.parse(srt, source: source("srt")).text, "Hello world.")
        let json = Data(#"{"segments":[{"startTime":5,"endTime":8,"body":"One."},{"startTime":9,"endTime":10,"body":"Two."}]}"#.utf8)
        XCTAssertEqual(try ReferenceTranscriptParser.parse(json, source: source("json")).text, "One.\nTwo.")
    }

    func testPrefersVTTAndKeepsFallbackOrder() {
        let srt = TranscriptSource(url: URL(string: "https://example.com/transcript?format=SubRip")!, type: "application/srt")
        let vtt = TranscriptSource(url: URL(string: "https://example.com/transcript?format=WebVTT")!, type: "text/vtt")
        let text = TranscriptSource(url: URL(string: "https://example.com/transcript?format=Text")!, type: "text/plain")
        XCTAssertEqual(TranscriptSource.preferredSources(from: [srt, vtt, text]), [vtt, srt, text])
        XCTAssertEqual(TranscriptSource.preferredSources(from: [srt, text]), [srt, text])
    }

    func testOmnyExtensionlessSRTWithFeedAndResponseMIMETypes() throws {
        // My Favorite Murder publishes application/srt in RSS, but Omny responds
        // text/plain at /transcript?format=SubRip. Neither URL has an extension.
        let url = URL(string: "https://api.omny.fm/orgs/test/clips/test/transcript?format=SubRip")!
        let data = Data("1\n00:00:16,550 --> 00:00:22,360\nSpeaker 1: A synthetic test sentence.\n\n2\n00:00:22,360 --> 00:00:25,000\nSpeaker 2: A second test sentence.\n".utf8)
        for type in ["application/srt", "text/srt", "text/plain", ""] {
            let parsed = try ReferenceTranscriptParser.parse(data, source: TranscriptSource(url: url, type: type))
            XCTAssertEqual(parsed.text, "Speaker 1: A synthetic test sentence.\nSpeaker 2: A second test sentence.")
            XCTAssertFalse(parsed.text.contains("-->"))
        }
    }

    func testHTMLRemovesScriptsAndPreservesText() throws {
        let html = Data("<style>hidden</style><script>bad()</script><p>Actual &amp; useful</p>".utf8)
        XCTAssertEqual(try ReferenceTranscriptParser.parse(html, source: source("html")).text, "Actual & useful")
    }

    func testRejectsEmptyUnsupportedAndOversizedDocuments() {
        XCTAssertThrowsError(try ReferenceTranscriptParser.parse(Data("WEBVTT\n\n".utf8), source: source("vtt")))
        XCTAssertThrowsError(try ReferenceTranscriptParser.parse(Data(#"{"error":"denied"}"#.utf8), source: source("json")))
        XCTAssertThrowsError(try ReferenceTranscriptParser.parse(Data(repeating: 65, count: ReferenceTranscriptParser.maximumBytes + 1), source: source("txt")))
        XCTAssertFalse(TranscriptSource.isRemoteURL(URL(string: "file:///tmp/transcript.txt")!))
    }

    func testOldEpisodeDecodesWithoutReferenceFields() throws {
        let episode = PodcastEpisode(feedID: UUID(), title: "Saved", audioURL: URL(string: "https://example.com/audio.mp3")!)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(episode)) as? [String: Any])
        for key in ["guid", "transcriptSources", "referenceTranscript"] { object.removeValue(forKey: key) }
        let decoded = try JSONDecoder().decode(PodcastEpisode.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(decoded.referenceTranscript)
        XCTAssertNil(decoded.transcriptSources)
        XCTAssertNil(decoded.analysis.referenceComparison)
    }

    func testReferencePersistsWithoutChangingLocalTranscriptTimes() throws {
        var episode = PodcastEpisode(feedID: UUID(), title: "Saved", audioURL: URL(string: "https://example.com/audio.mp3")!)
        episode.referenceTranscript = try ReferenceTranscriptParser.parse(Data("Hello world".utf8), source: source("txt"))
        episode.analysis.transcript = [TranscriptChunk(start: 60, end: 65, text: "Hello world")]
        let decoded = try JSONDecoder().decode(PodcastEpisode.self, from: JSONEncoder().encode(episode))
        XCTAssertEqual(decoded, episode)
        XCTAssertEqual(decoded.analysis.transcript[0].start, 60)
    }

    func testRSSDiscoversRelativeTranscriptURLsAndGUID() throws {
        let xml = """
        <rss xmlns:p="https://podcastindex.org/namespace/1.0"><channel><title>Show</title><item>
        <guid isPermaLink="false">stable-episode</guid><title>Title</title>
        <enclosure url="https://example.com/a.mp3"/>
        <p:transcript url="transcripts/a.vtt" type="text/vtt" language="en"/>
        <p:transcript url="https://example.com/a.json" type="application/json"/>
        <p:transcript url="file:///etc/passwd" type="text/plain"/>
        </item></channel></rss>
        """
        let feed = try RSSFeedParser.parse(data: Data(xml.utf8), feedURL: URL(string: "https://example.com/feed.xml")!)
        XCTAssertEqual(feed.episodes[0].guid, "stable-episode")
        XCTAssertEqual(feed.episodes[0].transcriptSources?.count, 2)
        XCTAssertEqual(feed.episodes[0].transcriptSources?.first?.url.absoluteString, "https://example.com/transcripts/a.vtt")
        XCTAssertEqual(feed.episodes[0].transcriptSources?.first?.language, "en")
    }

    func testFeedRefreshPreservesDownloadedEpisodeWhenEnclosureChanges() {
        let url = URL(string: "https://example.com/feed")!
        var saved = PodcastFeed(title: "Old", feedURL: url)
        var episode = PodcastEpisode(feedID: saved.id, title: "Old title", audioURL: url.appending(path: "old.mp3"), guid: "guid")
        episode.download = EpisodeDownload(state: .downloaded, localFileURL: URL(fileURLWithPath: "/tmp/saved.mp3"))
        episode.analysis.status = .complete
        saved.episodes = [episode]
        var fresh = PodcastFeed(title: "Updated", feedURL: url)
        fresh.episodes = [PodcastEpisode(feedID: fresh.id, title: "New title", audioURL: url.appending(path: "new.mp3"), guid: "guid")]
        let merged = PodcastFeedMerger.merge(fresh, into: saved)
        XCTAssertEqual(merged.id, saved.id)
        XCTAssertEqual(merged.episodes[0].id, episode.id)
        XCTAssertEqual(merged.episodes[0].feedID, saved.id)
        XCTAssertEqual(merged.episodes[0].download, episode.download)
        XCTAssertEqual(merged.episodes[0].analysis.status, .complete)
        XCTAssertEqual(merged.episodes[0].title, "New title")
    }
}
