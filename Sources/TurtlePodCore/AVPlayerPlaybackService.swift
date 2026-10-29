import AVFoundation
import Foundation

@MainActor
public final class AVPlayerPlaybackService: PlaybackService, @unchecked Sendable {
    public enum Source: Equatable, Sendable {
        case local(URL)
        case stream(URL)

        public var url: URL {
            switch self {
            case .local(let url), .stream(let url): url
            }
        }
    }

    private let player = AVPlayer()
    private var loadedEpisode: PodcastEpisode?
    private var timeObserver: Any?
    private var boundaryObserver: Any?
    private var boundaryTimes: [TimeInterval] = []
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var shouldResumeAfterInterruption = false

    public private(set) var source: Source?
    /// Playback speed applied whenever playback starts.
    public private(set) var rate: Float = 1

    /// Called about twice a second while an item is loaded.
    public var onTimeChanged: ((TimeInterval) -> Void)?
    /// Called when playing, paused, or buffering state changes.
    public var onStateChanged: (() -> Void)?
    /// Called when the loaded item plays to its end.
    public var onItemFinished: (() -> Void)?
    /// Called when playback crosses a time set with `setBoundaryTimes`.
    public var onBoundaryCrossed: ((TimeInterval) -> Void)?

    public init() {
        player.automaticallyWaitsToMinimizeStalling = true
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, self.loadedEpisode != nil else { return }
                self.onTimeChanged?(time.seconds.isFinite ? time.seconds : 0)
            }
        }
        statusObservation = Self.observeStatus(of: player) { [weak self] in
            self?.onStateChanged?()
        }
        observeInterruptions()
    }

    public var currentEpisode: PodcastEpisode? {
        get async { loadedEpisode }
    }

    public var currentTime: TimeInterval {
        get async { elapsed }
    }

    public var isPlaying: Bool {
        get async { playing }
    }

    public var loadedEpisodeID: UUID? { loadedEpisode?.id }

    public var elapsed: TimeInterval {
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? max(seconds, 0) : 0
    }

    /// True while the user intends playback, including while a stream buffers.
    public var playing: Bool {
        player.timeControlStatus != .paused
    }

    public var isBuffering: Bool {
        player.timeControlStatus == .waitingToPlayAtSpecifiedRate
    }

    public var itemDuration: TimeInterval? {
        guard let seconds = player.currentItem?.duration.seconds, seconds.isFinite, seconds > 0 else { return nil }
        return seconds
    }

    public func load(_ episode: PodcastEpisode) async throws {
        guard let localFileURL = episode.download?.localFileURL else {
            throw TurtlePodError.notDownloaded
        }
        try await load(episode, source: .local(localFileURL), startAt: 0)
    }

    public func load(_ episode: PodcastEpisode, source: Source, startAt position: TimeInterval) async throws {
        let item = AVPlayerItem(url: source.url)
        item.audioTimePitchAlgorithm = .timeDomain
        // Without this the new item plays from zero until the resume seek lands.
        player.pause()
        loadedEpisode = episode
        self.source = source
        setBoundaryTimes([])
        player.replaceCurrentItem(with: item)
        observeEnd(of: item)
        if position > 0 {
            await player.seek(to: CMTime(seconds: position, preferredTimescale: 600))
        }
        guard player.currentItem === item else { return }
        onTimeChanged?(position)
    }

    /// Keeps the loaded episode's metadata current after analysis or feed refresh.
    public func updateLoadedEpisode(_ episode: PodcastEpisode) {
        guard loadedEpisode?.id == episode.id else { return }
        loadedEpisode = episode
    }

    public func unload() {
        setBoundaryTimes([])
        player.pause()
        player.replaceCurrentItem(with: nil)
        loadedEpisode = nil
        source = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        onStateChanged?()
    }

    public func play() async {
        guard player.currentItem != nil else { return }
        activateAudioSession()
        player.playImmediately(atRate: rate)
    }

    public func pause() async {
        player.pause()
    }

    public func seek(to time: TimeInterval) async {
        var target = max(time, 0)
        if let duration = itemDuration {
            target = min(target, duration)
        }
        // Local files seek exactly for free; a loose seek can land back inside an ad.
        let tolerance: CMTime = if case .local = source { .zero } else { .positiveInfinity }
        await player.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                          toleranceBefore: tolerance, toleranceAfter: tolerance)
        onTimeChanged?(elapsed)
    }

    /// Fires `onBoundaryCrossed` when playback reaches any of these times.
    /// Unlike the periodic tick, iOS delivers these on time with the screen locked.
    public func setBoundaryTimes(_ times: [TimeInterval]) {
        let times = times.filter { $0.isFinite && $0 >= 0 }.sorted()
        guard times != boundaryTimes || (boundaryObserver == nil && !times.isEmpty) else { return }
        boundaryTimes = times
        if let boundaryObserver {
            player.removeTimeObserver(boundaryObserver)
            self.boundaryObserver = nil
        }
        let values = times.map {
            NSValue(time: CMTime(seconds: $0, preferredTimescale: 600))
        }
        guard !values.isEmpty else { return }
        boundaryObserver = player.addBoundaryTimeObserver(forTimes: values, queue: .main) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.loadedEpisode != nil else { return }
                self.onBoundaryCrossed?(self.elapsed)
            }
        }
    }

    public func setRate(_ rate: Float) {
        self.rate = rate
        player.defaultRate = rate
        if player.timeControlStatus != .paused {
            player.rate = rate
        }
    }

    /// KVO can fire on any thread; build the handler outside the main actor.
    nonisolated private static func observeStatus(
        of player: AVPlayer,
        onChange: @escaping @MainActor @Sendable () -> Void
    ) -> NSKeyValueObservation {
        player.observe(\.timeControlStatus, options: [.new]) { _, _ in
            Task { @MainActor in onChange() }
        }
    }

    private func observeEnd(of item: AVPlayerItem) {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onItemFinished?()
            }
        }
    }

    private func activateAudioSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
        try? session.setActive(true)
        #endif
    }

    private func observeInterruptions() {
        #if os(iOS)
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionsValue = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            MainActor.assumeIsolated {
                guard let self, let typeValue, let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
                switch type {
                case .began:
                    self.shouldResumeAfterInterruption = self.player.timeControlStatus != .paused
                case .ended:
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue ?? 0)
                    if self.shouldResumeAfterInterruption, options.contains(.shouldResume) {
                        self.player.playImmediately(atRate: self.rate)
                    }
                    self.shouldResumeAfterInterruption = false
                @unknown default:
                    break
                }
            }
        }
        #endif
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
