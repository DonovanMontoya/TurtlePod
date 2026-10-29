import Foundation
import MediaPlayer
import TurtlePodCore
#if canImport(UIKit)
import UIKit
#endif

/// Lock screen, Control Center, headphone, and CarPlay transport controls.
@MainActor
final class NowPlayingCenter {
    struct Handlers: Sendable {
        var play: @MainActor @Sendable () -> Void
        var pause: @MainActor @Sendable () -> Void
        var toggle: @MainActor @Sendable () -> Void
        var skipForward: @MainActor @Sendable () -> Void
        var skipBack: @MainActor @Sendable () -> Void
        var seek: @MainActor @Sendable (TimeInterval) -> Void
        var next: @MainActor @Sendable () -> Void
        var previous: @MainActor @Sendable () -> Void
        var changeRate: @MainActor @Sendable (Double) -> Void
    }

    private var artworkURL: URL?
    private var artwork: MPMediaItemArtwork?
    private var info: [String: Any] = [:]
    private var published: (elapsed: TimeInterval, rate: Double, at: Date)?

    func configure(handlers: Handlers, skipForward: Int, skipBack: Int) {
        Self.addTargets(handlers)
        updateSkipIntervals(forward: skipForward, back: skipBack)
    }

    /// MediaPlayer may call these from any queue, so they are built outside
    /// the main actor and hop back to it.
    nonisolated private static func addTargets(_ handlers: Handlers) {
        let center = MPRemoteCommandCenter.shared()
        func simple(_ command: MPRemoteCommand, _ action: @escaping @MainActor @Sendable () -> Void) {
            command.addTarget { _ in
                Task { @MainActor in action() }
                return .success
            }
        }
        simple(center.playCommand, handlers.play)
        simple(center.pauseCommand, handlers.pause)
        simple(center.togglePlayPauseCommand, handlers.toggle)
        simple(center.skipForwardCommand, handlers.skipForward)
        simple(center.skipBackwardCommand, handlers.skipBack)
        simple(center.nextTrackCommand, handlers.next)
        simple(center.previousTrackCommand, handlers.previous)
        center.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let time = event.positionTime
            Task { @MainActor in handlers.seek(time) }
            return .success
        }
        center.changePlaybackRateCommand.supportedPlaybackRates = PlaybackPreferences.speedPresets.map { NSNumber(value: $0) }
        center.changePlaybackRateCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackRateCommandEvent else { return .commandFailed }
            let rate = Double(event.playbackRate)
            Task { @MainActor in handlers.changeRate(rate) }
            return .success
        }
    }

    func updateSkipIntervals(forward: Int, back: Int) {
        let center = MPRemoteCommandCenter.shared()
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: forward)]
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: back)]
    }

    func update(
        episode: PodcastEpisode,
        podcastTitle: String?,
        chapterTitle: String?,
        elapsed: TimeInterval,
        duration: TimeInterval?,
        rate: Double,
        isPlaying: Bool
    ) {
        info[MPMediaItemPropertyTitle] = chapterTitle ?? episode.title
        info[MPMediaItemPropertyArtist] = chapterTitle == nil ? podcastTitle : episode.title
        info[MPMediaItemPropertyAlbumTitle] = podcastTitle
        info[MPMediaItemPropertyMediaType] = MPMediaType.podcast.rawValue
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? rate : 0
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = rate
        if let artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        published = (elapsed, isPlaying ? rate : 0, Date())
        #if os(macOS)
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
        #endif
        loadArtworkIfNeeded(episode.artworkURL)
    }

    /// True when the time the lock screen is showing is more than a second off.
    func hasDrifted(from elapsed: TimeInterval) -> Bool {
        guard let published else { return false }
        let shown = published.elapsed + Date().timeIntervalSince(published.at) * published.rate
        return abs(shown - elapsed) > 1
    }

    func clear() {
        published = nil
        info = [:]
        artwork = nil
        artworkURL = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func loadArtworkIfNeeded(_ url: URL?) {
        guard let url, url != artworkURL else { return }
        artworkURL = url
        artwork = nil
        info[MPMediaItemPropertyArtwork] = nil
        #if canImport(UIKit)
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data),
                  self.artworkURL == url else { return }
            let artwork = Self.makeArtwork(image)
            self.artwork = artwork
            self.info[MPMediaItemPropertyArtwork] = artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = self.info
        }
        #endif
    }

    #if canImport(UIKit)
    /// MediaPlayer calls the image handler off the main thread.
    nonisolated private static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
    #endif
}
