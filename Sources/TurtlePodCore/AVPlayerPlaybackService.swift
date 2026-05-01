import AVFoundation
import Foundation

@MainActor
public final class AVPlayerPlaybackService: PlaybackService, @unchecked Sendable {
    private let player = AVPlayer()
    private var loadedEpisode: PodcastEpisode?

    public init() {}

    public var currentEpisode: PodcastEpisode? {
        get async { loadedEpisode }
    }

    public var currentTime: TimeInterval {
        get async { player.currentTime().seconds }
    }

    public var isPlaying: Bool {
        get async { player.timeControlStatus == .playing }
    }

    public func load(_ episode: PodcastEpisode) async throws {
        guard let localFileURL = episode.download?.localFileURL else {
            throw TurtlePodError.notDownloaded
        }
        loadedEpisode = episode
        player.replaceCurrentItem(with: AVPlayerItem(url: localFileURL))
    }

    public func play() async {
        player.play()
    }

    public func pause() async {
        player.pause()
    }

    public func seek(to time: TimeInterval) async {
        await player.seek(to: CMTime(seconds: time, preferredTimescale: 600))
    }
}

public actor FakePlaybackService: PlaybackService {
    public private(set) var currentEpisode: PodcastEpisode?
    public private(set) var currentTime: TimeInterval
    public private(set) var isPlaying: Bool

    public init(currentTime: TimeInterval = 0, isPlaying: Bool = false) {
        self.currentTime = currentTime
        self.isPlaying = isPlaying
    }

    public func load(_ episode: PodcastEpisode) async throws {
        currentEpisode = episode
        currentTime = 0
    }

    public func play() async {
        isPlaying = true
    }

    public func pause() async {
        isPlaying = false
    }

    public func seek(to time: TimeInterval) async {
        currentTime = time
    }
}
