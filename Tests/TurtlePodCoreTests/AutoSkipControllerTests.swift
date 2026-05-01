import XCTest
@testable import TurtlePodCore

final class AutoSkipControllerTests: XCTestCase {
    func testEnteringAdRangeSeeksToEndAndLogsEvent() async throws {
        let segmentID = UUID()
        let episode = makeEpisode(adSegments: [
            AdSegment(id: segmentID, start: 10, end: 25, confidence: 0.91, reason: "sponsor", provider: "test", model: "mock")
        ])
        let playback = FakePlaybackService(currentTime: 12, isPlaying: true)
        let store = InMemoryEpisodeStore()
        let controller = AutoSkipController(playback: playback, store: store)

        let event = try await controller.evaluate(
            episode: episode,
            currentTime: 12,
            globalAutoSkipEnabled: true,
            confidenceThreshold: 0.8
        )

        let currentTime = await playback.currentTime
        let skipEventCount = try await store.loadSkipEvents().count
        XCTAssertEqual(event?.skippedTo, 25)
        XCTAssertEqual(currentTime, 25)
        XCTAssertEqual(skipEventCount, 1)
    }

    func testDoesNotSkipWhenGlobalAutoSkipDisabled() async throws {
        let episode = makeEpisode(adSegments: [
            AdSegment(start: 10, end: 25, confidence: 0.91, reason: "sponsor", provider: "test", model: "mock")
        ])
        let playback = FakePlaybackService(currentTime: 12)
        let controller = AutoSkipController(playback: playback)

        let event = try await controller.evaluate(
            episode: episode,
            currentTime: 12,
            globalAutoSkipEnabled: false,
            confidenceThreshold: 0.8
        )

        let currentTime = await playback.currentTime
        XCTAssertNil(event)
        XCTAssertEqual(currentTime, 12)
    }

    func testUndoAfterSkipSeeksBackToSkippedTime() async throws {
        let episode = makeEpisode(adSegments: [
            AdSegment(start: 10, end: 25, confidence: 0.91, reason: "sponsor", provider: "test", model: "mock")
        ])
        let playback = FakePlaybackService(currentTime: 12)
        let controller = AutoSkipController(playback: playback)

        _ = try await controller.evaluate(
            episode: episode,
            currentTime: 12,
            globalAutoSkipEnabled: true,
            confidenceThreshold: 0.8
        )
        await controller.undoLastSkip()

        let currentTime = await playback.currentTime
        XCTAssertEqual(currentTime, 12)
    }

    func testAlreadyPastAdRangeDoesNotSkip() async throws {
        let episode = makeEpisode(adSegments: [
            AdSegment(start: 10, end: 25, confidence: 0.91, reason: "sponsor", provider: "test", model: "mock")
        ])
        let playback = FakePlaybackService(currentTime: 30)
        let controller = AutoSkipController(playback: playback)

        let event = try await controller.evaluate(
            episode: episode,
            currentTime: 30,
            globalAutoSkipEnabled: true,
            confidenceThreshold: 0.8
        )

        let currentTime = await playback.currentTime
        XCTAssertNil(event)
        XCTAssertEqual(currentTime, 30)
    }

    private func makeEpisode(adSegments: [AdSegment]) -> PodcastEpisode {
        PodcastEpisode(
            feedID: UUID(),
            title: "Episode",
            audioURL: URL(string: "https://example.com/audio.mp3")!,
            analysis: EpisodeAnalysis(status: .complete, adSegments: adSegments)
        )
    }
}
