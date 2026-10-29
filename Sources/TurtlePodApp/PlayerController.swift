import Foundation
import Observation
import TurtlePodCore

/// High-frequency playback state, kept apart from `TurtlePodModel` so time
/// ticks only redraw the views that read them.
@MainActor
@Observable
final class PlayerController {
    var episodeID: UUID?
    var currentTime: TimeInterval = 0
    var duration: TimeInterval?
    var isPlaying = false
    var isBuffering = false
    var isStreaming = false
    var rate: Double = 1
    var chapters: [EpisodeChapter] = []
    var sleepTimer: SleepTimer = .off
    var isFullPlayerPresented = false

    var currentChapter: EpisodeChapter? {
        EpisodeChapterLoader.chapter(at: currentTime, in: chapters)
    }

    var remaining: TimeInterval? {
        duration.map { max($0 - currentTime, 0) }
    }

    func reset() {
        episodeID = nil
        currentTime = 0
        duration = nil
        isPlaying = false
        isBuffering = false
        isStreaming = false
        chapters = []
    }
}

enum SleepTimer: Equatable {
    case off
    case until(Date)
    case endOfEpisode
    case endOfChapter

    var isActive: Bool { self != .off }

    static let presetMinutes = [5, 10, 15, 30, 45, 60, 90]
}
