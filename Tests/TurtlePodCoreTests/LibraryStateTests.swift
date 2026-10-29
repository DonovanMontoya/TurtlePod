import Foundation
import XCTest
@testable import TurtlePodCore

final class LibraryStateTests: XCTestCase {
    private let a = UUID()
    private let b = UUID()
    private let c = UUID()

    func testPlayNextMovesExistingItemToFront() {
        var queue = UpNextQueue(items: [a, b, c])
        queue.playNext(c)
        XCTAssertEqual(queue.items, [c, a, b])
    }

    func testPlayLastMovesExistingItemToEnd() {
        var queue = UpNextQueue(items: [a, b, c])
        queue.playLast(a)
        XCTAssertEqual(queue.items, [b, c, a])
    }

    func testMoveMatchesListOnMoveSemantics() {
        var queue = UpNextQueue(items: [a, b, c])
        queue.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        XCTAssertEqual(queue.items, [b, c, a])

        queue.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(queue.items, [a, b, c])

        // Same result SwiftUI's Array.move(fromOffsets:toOffset:) gives.
        queue.move(fromOffsets: IndexSet([0, 2]), toOffset: 2)
        XCTAssertEqual(queue.items, [b, a, c])
    }

    func testPopNextSkipsTheEpisodeThatJustEnded() {
        var queue = UpNextQueue(items: [a, b])
        XCTAssertEqual(queue.popNext(after: a), b)
        XCTAssertTrue(queue.items.isEmpty)
        XCTAssertNil(queue.popNext(after: nil))
    }

    func testMarkPlayedResetsPositionAndLeavesQueue() {
        var state = LibraryState(upNext: UpNextQueue(items: [a, b]))
        state.episodes[a] = EpisodeUserState(playbackPosition: 120, isStarred: true)
        state.markPlayed(a)
        XCTAssertTrue(state.state(for: a).isPlayed)
        XCTAssertEqual(state.state(for: a).playbackPosition, 0)
        XCTAssertTrue(state.state(for: a).isStarred)
        XCTAssertEqual(state.upNext.items, [b])

        state.markUnplayed(a)
        XCTAssertFalse(state.state(for: a).isPlayed)
    }

    func testHistoryIsMostRecentFirstWithoutDuplicates() {
        var state = LibraryState()
        state.recordHistory(a)
        state.recordHistory(b)
        state.recordHistory(a)
        XCTAssertEqual(state.history, [a, b])
    }

    func testPruneDropsRemovedEpisodes() {
        var state = LibraryState(upNext: UpNextQueue(items: [a, b]), history: [b, a], nowPlayingEpisodeID: b)
        state.episodes[b] = EpisodeUserState(playbackPosition: 10)
        state.prune(keeping: [a], podcastIDs: [])
        XCTAssertEqual(state.upNext.items, [a])
        XCTAssertEqual(state.history, [a])
        XCTAssertNil(state.episodes[b])
        XCTAssertNil(state.nowPlayingEpisodeID)
    }

    func testDecodesEmptyAndPartialDocuments() throws {
        let decoder = JSONDecoder()
        let empty = try decoder.decode(LibraryState.self, from: Data("{}".utf8))
        XCTAssertEqual(empty, LibraryState())

        let partial = try decoder.decode(LibraryState.self, from: Data(#"{"playback":{"speed":1.5}}"#.utf8))
        XCTAssertEqual(partial.playback.speed, 1.5)
        XCTAssertEqual(partial.playback.skipForwardSeconds, 30)
    }

    func testStoreRoundTrip() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "LibraryStateTests-\(UUID().uuidString)")
        let store = try LibraryStateStore(directory: directory)
        var state = LibraryState(upNext: UpNextQueue(items: [a]))
        state.episodes[a] = EpisodeUserState(playbackPosition: 42, lastPlayedAt: Date(timeIntervalSince1970: 1_000))
        state.podcasts[b] = PodcastPreferences(skipIntroSeconds: 30, playbackSpeed: 1.2)
        try await store.save(state)
        let loaded = try await store.load()
        XCTAssertEqual(loaded, state)
    }

    func testResumePosition() {
        XCTAssertEqual(PlaybackProgress.resumePosition(saved: 0, duration: 600, introSkip: 30), 30)
        XCTAssertEqual(PlaybackProgress.resumePosition(saved: 300, duration: 600), 298)
        XCTAssertEqual(PlaybackProgress.resumePosition(saved: 595, duration: 600, introSkip: 10), 10)
        XCTAssertEqual(PlaybackProgress.resumePosition(saved: 300, duration: nil), 298)
    }

    func testCatchUpRewindGrowsWithPauseLength() {
        XCTAssertEqual(PlaybackProgress.catchUpRewind(pausedFor: 30), 0)
        XCTAssertEqual(PlaybackProgress.catchUpRewind(pausedFor: 10 * 60), 10)
        XCTAssertEqual(PlaybackProgress.catchUpRewind(pausedFor: 3 * 60 * 60), 20)
        XCTAssertEqual(PlaybackProgress.catchUpRewind(pausedFor: 3 * 24 * 60 * 60), 30)
    }

    func testIsFinished() {
        XCTAssertTrue(PlaybackProgress.isFinished(position: 590, duration: 600))
        XCTAssertFalse(PlaybackProgress.isFinished(position: 500, duration: 600))
        XCTAssertFalse(PlaybackProgress.isFinished(position: 5, duration: nil))
    }
}
