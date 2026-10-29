import Foundation
import SwiftUI
import TurtlePodCore

// Playback, Up Next, listening state, subscriptions, and feed refresh.
extension TurtlePodModel {
    // MARK: Setup

    func configurePlayback() {
        playback.onTimeChanged = { [weak self] time in
            self?.handleTick(time)
        }
        playback.onStateChanged = { [weak self] in
            self?.syncPlayerState()
        }
        playback.onItemFinished = { [weak self] in
            Task { await self?.handleEpisodeFinished() }
        }
        nowPlaying.configure(
            handlers: .init(
                play: { [weak self] in Task { await self?.resume() } },
                pause: { [weak self] in Task { await self?.pause() } },
                toggle: { [weak self] in Task { await self?.togglePlayback() } },
                skipForward: { [weak self] in Task { await self?.skipForward() } },
                skipBack: { [weak self] in Task { await self?.skipBack() } },
                seek: { [weak self] time in Task { await self?.seek(to: time) } },
                // Headphone and car double/triple taps send next/previous; podcast apps treat them as skips.
                next: { [weak self] in Task { await self?.skipForward() } },
                previous: { [weak self] in Task { await self?.skipBack() } },
                changeRate: { [weak self] rate in self?.setSpeed(rate) }
            ),
            skipForward: library.playback.skipForwardSeconds,
            skipBack: library.playback.skipBackSeconds
        )
    }

    // MARK: Lookups

    var nowPlayingEpisode: PodcastEpisode? {
        player.episodeID.flatMap { episode(withID: $0) }
    }

    func state(for episodeID: UUID) -> EpisodeUserState {
        library.state(for: episodeID)
    }

    func preferences(for feedID: UUID) -> PodcastPreferences {
        library.preferences(for: feedID)
    }

    func podcastTitle(for episode: PodcastEpisode) -> String? {
        feed(withID: episode.feedID)?.title
    }

    func duration(for episode: PodcastEpisode) -> TimeInterval? {
        if player.episodeID == episode.id, let duration = player.duration {
            return duration
        }
        if let known = library.episodes[episode.id]?.knownDuration { return known }
        if let duration = episode.duration, duration > 0 { return duration }
        return nil
    }

    func position(for episode: PodcastEpisode) -> TimeInterval {
        player.episodeID == episode.id ? player.currentTime : state(for: episode.id).playbackPosition
    }

    /// Fraction listened, or nil when there is no meaningful progress to show.
    func progress(for episode: PodcastEpisode) -> Double? {
        let position = position(for: episode)
        guard position >= 1, let duration = duration(for: episode), duration > 0 else { return nil }
        return min(position / duration, 1)
    }

    func isSubscribed(feedURL: URL) -> Bool {
        feeds.contains { $0.feedURL == feedURL }
    }

    func feedID(for feedURL: URL) -> UUID? {
        feeds.first { $0.feedURL == feedURL }?.id
    }

    func episodes(in feed: PodcastFeed) -> [PodcastEpisode] {
        let preferences = preferences(for: feed.id)
        let sorted = feed.episodes.sorted { lhs, rhs in
            let left = lhs.publishedAt ?? .distantPast
            let right = rhs.publishedAt ?? .distantPast
            return preferences.sortOrder == .newestFirst ? left > right : left < right
        }
        guard preferences.hidePlayed else { return sorted }
        return sorted.filter { !state(for: $0.id).isPlayed }
    }

    /// Unplayed episodes from the last two weeks, for the grid badge.
    func newEpisodeCount(in feed: PodcastFeed) -> Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? .distantPast
        return feed.episodes.reduce(0) { count, episode in
            (episode.publishedAt ?? .distantPast) >= cutoff && !state(for: episode.id).isPlayed ? count + 1 : count
        }
    }

    func latestEpisodeDate(in feed: PodcastFeed) -> Date {
        feed.episodes.compactMap(\.publishedAt).max() ?? .distantPast
    }

    // MARK: Filters

    var newReleases: [PodcastEpisode] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? .distantPast
        return allEpisodes.filter { episode in
            (episode.publishedAt ?? .distantPast) >= cutoff && !state(for: episode.id).isPlayed
        }
    }

    var inProgressEpisodes: [PodcastEpisode] {
        allEpisodes
            .filter { state(for: $0.id).isInProgress }
            .sorted { (state(for: $0.id).lastPlayedAt ?? .distantPast) > (state(for: $1.id).lastPlayedAt ?? .distantPast) }
    }

    var starredEpisodes: [PodcastEpisode] {
        allEpisodes.filter { state(for: $0.id).isStarred }
    }

    var historyEpisodes: [PodcastEpisode] {
        library.history.compactMap { episode(withID: $0) }
    }

    var upNextEpisodes: [PodcastEpisode] {
        library.upNext.items.compactMap { episode(withID: $0) }
    }

    var upNextRemainingTime: TimeInterval {
        upNextEpisodes.reduce(0) { total, episode in
            total + max((duration(for: episode) ?? 0) - state(for: episode.id).playbackPosition, 0)
        }
    }

    // MARK: Playback

    func play(_ episode: PodcastEpisode) async {
        if player.episodeID == episode.id {
            if !player.isPlaying { await resume() }
            return
        }
        await startPlayback(episode, resumeAt: nil, autoplay: true)
    }

    func startPlayback(_ episode: PodcastEpisode, resumeAt explicitPosition: TimeInterval?, autoplay: Bool) async {
        guard let latest = self.episode(withID: episode.id) else { return }
        playbackGeneration += 1
        let generation = playbackGeneration
        let interruptedID = player.episodeID != latest.id ? player.episodeID : nil
        // An episode that just finished (an outro skip can end it early) is played, not interrupted.
        let interruptedWasInProgress = interruptedID != nil && player.currentTime > 60
            && !PlaybackProgress.isFinished(position: player.currentTime, duration: player.duration)
            && !(interruptedID.map { state(for: $0).isPlayed } ?? true)
        saveCurrentPosition(force: true)

        let source: AVPlayerPlaybackService.Source
        if latest.download?.state == .downloaded, await ensureDownloadFileExists(for: latest.id),
           let fileURL = self.episode(withID: latest.id)?.download?.localFileURL {
            source = .local(fileURL)
        } else if TranscriptSource.isRemoteURL(latest.audioURL) {
            source = .stream(latest.audioURL)
        } else {
            statusMessage = "This episode has no playable audio."
            return
        }
        guard generation == playbackGeneration else { return }

        let preferences = preferences(for: latest.feedID)
        var userState = state(for: latest.id)
        if userState.isPlayed, explicitPosition == nil {
            userState.isPlayed = false
            userState.playedAt = nil
            userState.playbackPosition = 0
        }
        let start = explicitPosition ?? PlaybackProgress.resumePosition(
            saved: userState.playbackPosition,
            duration: duration(for: latest),
            introSkip: TimeInterval(preferences.skipIntroSeconds)
        )

        isLoadingEpisode = true
        defer { if generation == playbackGeneration { isLoadingEpisode = false } }
        do {
            activeSkipEvent = nil
            player.reset()
            player.episodeID = latest.id
            player.currentTime = start
            player.duration = duration(for: latest)
            if case .stream = source { player.isStreaming = true }
            pausedAt = nil
            // Closing the player mid-load leaves nothing to take over the loaded item.
            func superseded() -> Bool {
                guard generation != playbackGeneration else { return false }
                if player.episodeID == nil { playback.unload() }
                return true
            }
            try await playback.load(latest, source: source, startAt: start)
            if superseded() { return }
            await autoSkipController.resetForNewEpisode()
            if superseded() { return }
            setSpeed(preferences.playbackSpeed ?? library.playback.speed, persist: false)

            if autoplay {
                userState.lastPlayedAt = Date()
                library.recordHistory(latest.id)
            }
            library.episodes[latest.id] = userState
            library.nowPlayingEpisodeID = latest.id
            library.upNext.remove(latest.id)
            // Starting something else mid-episode keeps the old one first in line, like Pocket Casts.
            if let interruptedID, interruptedWasInProgress, autoplay {
                library.upNext.playNext(interruptedID)
            }
            lastTickPosition = start
            saveLibrary()

            isLoadingEpisode = false
            if autoplay { await playback.play() }
            syncPlayerState()
            updateNowPlayingInfo()
            loadChapters(for: latest, source: source)
        } catch {
            guard generation == playbackGeneration else { return }
            player.reset()
            statusMessage = error.localizedDescription
        }
    }

    func togglePlayback() async {
        if player.isPlaying {
            await pause()
        } else {
            await resume()
        }
    }

    func pause() async {
        await playback.pause()
        pausedAt = Date()
        // Stopping in the last few seconds counts as finishing.
        if let duration = player.duration, PlaybackProgress.isFinished(position: player.currentTime, duration: duration),
           let id = player.episodeID {
            library.markPlayed(id)
            saveLibrary()
        } else {
            saveCurrentPosition(force: true)
        }
        syncPlayerState()
    }

    func resume() async {
        if playback.loadedEpisodeID == nil, let episode = nowPlayingEpisode {
            await startPlayback(episode, resumeAt: nil, autoplay: true)
            return
        }
        if let pausedAt {
            let rewind = PlaybackProgress.catchUpRewind(pausedFor: Date().timeIntervalSince(pausedAt))
            self.pausedAt = nil
            if rewind > 0 {
                await seek(to: max(player.currentTime - rewind, 0))
            }
        }
        if let id = player.episodeID {
            library.episodes[id, default: EpisodeUserState()].lastPlayedAt = Date()
            library.recordHistory(id)
        }
        await playback.play()
        syncPlayerState()
    }

    func seek(to time: TimeInterval) async {
        await playback.seek(to: time)
        lastTickPosition = playback.elapsed
        player.currentTime = playback.elapsed
        if player.sleepTimer == .endOfChapter {
            sleepChapterID = player.currentChapter?.id
        }
        saveCurrentPosition(force: true)
        updateNowPlayingInfo()
    }

    /// Keeps the lock screen and saved position in step after an ad skip or undo.
    func syncAfterJump() {
        player.currentTime = playback.elapsed
        lastTickPosition = player.currentTime
        saveCurrentPosition(force: true)
        updateNowPlayingInfo()
    }

    func skipForward() async {
        await seek(to: player.currentTime + TimeInterval(library.playback.skipForwardSeconds))
    }

    func skipBack() async {
        await seek(to: max(player.currentTime - TimeInterval(library.playback.skipBackSeconds), 0))
    }

    func setSpeed(_ speed: Double, persist: Bool = true) {
        let clamped = min(max((speed * 10).rounded() / 10, PlaybackPreferences.speedRange.lowerBound), PlaybackPreferences.speedRange.upperBound)
        playback.setRate(Float(clamped))
        player.rate = clamped
        if persist {
            if let feedID = nowPlayingEpisode?.feedID, preferences(for: feedID).playbackSpeed != nil {
                library.podcasts[feedID]?.playbackSpeed = clamped
            } else {
                library.playback.speed = clamped
            }
            saveLibrary()
        }
        updateNowPlayingInfo()
    }

    /// The app-wide speed; shows with their own speed keep it.
    func setDefaultSpeed(_ speed: Double) {
        let clamped = min(max((speed * 10).rounded() / 10, PlaybackPreferences.speedRange.lowerBound), PlaybackPreferences.speedRange.upperBound)
        library.playback.speed = clamped
        saveLibrary()
        if let feedID = nowPlayingEpisode?.feedID, preferences(for: feedID).playbackSpeed == nil {
            setSpeed(clamped, persist: false)
        }
    }

    func seekToChapter(_ chapter: EpisodeChapter) async {
        await seek(to: chapter.start)
    }

    func skipChapter(forward: Bool) async {
        let chapters = player.chapters
        guard !chapters.isEmpty else { return }
        let time = player.currentTime
        if forward {
            if let next = chapters.first(where: { $0.start > time + 0.5 }) {
                await seek(to: next.start)
            }
        } else if let current = player.currentChapter {
            // Within the first few seconds of a chapter, go to the previous one.
            if time - current.start < 3, let index = chapters.firstIndex(of: current), index > 0 {
                await seek(to: chapters[index - 1].start)
            } else {
                await seek(to: current.start)
            }
        }
    }

    func playNextInQueue() async {
        let currentID = player.episodeID
        if let currentID {
            library.markPlayed(currentID)
        }
        guard let nextID = library.upNext.popNext(after: currentID),
              let next = episode(withID: nextID) else {
            closePlayer()
            return
        }
        saveLibrary()
        await startPlayback(next, resumeAt: nil, autoplay: true)
    }

    func closePlayer() {
        // Any start still in flight must not bring the closed episode back.
        playbackGeneration += 1
        isLoadingEpisode = false
        saveCurrentPosition(force: true)
        playback.unload()
        player.reset()
        player.isFullPlayerPresented = false
        player.sleepTimer = .off
        activeSkipEvent = nil
        library.nowPlayingEpisodeID = nil
        saveLibrary()
        nowPlaying.clear()
    }

    func setSleepTimer(_ timer: SleepTimer) {
        player.sleepTimer = timer
        sleepChapterID = timer == .endOfChapter ? player.currentChapter?.id : nil
    }

    func restoreNowPlaying() async {
        guard let id = library.nowPlayingEpisodeID, let episode = episode(withID: id) else { return }
        await startPlayback(episode, resumeAt: state(for: id).playbackPosition, autoplay: false)
        // A relaunch counts as a long break for catch-up rewind.
        pausedAt = library.episodes[id]?.lastPlayedAt
    }

    // MARK: Player events

    func handleTick(_ time: TimeInterval) {
        guard let episodeID = player.episodeID else { return }
        player.currentTime = time
        // The file's real length beats the feed's, which is often rounded or wrong.
        if let duration = playback.itemDuration, player.duration.map({ abs($0 - duration) > 1 }) ?? true {
            player.duration = duration
            library.episodes[episodeID, default: EpisodeUserState()].knownDuration = duration
            updateNowPlayingInfo()
        }

        if let last = lastTickPosition, player.isPlaying {
            let delta = time - last
            if delta > 0, delta < 3 * max(player.rate, 1) {
                pendingListenedSeconds += delta
            }
        }
        lastTickPosition = time

        if player.isPlaying, !isLoadingEpisode {
            Task { await evaluateAutoSkip(at: time) }
            checkSleepTimer()
            if let episode = episode(withID: episodeID) {
                let outro = TimeInterval(preferences(for: episode.feedID).skipOutroSeconds)
                if outro > 0, let duration = player.duration, duration > outro, time >= duration - outro {
                    Task { await handleEpisodeFinished() }
                    return
                }
            }
        }

        if player.currentChapter?.id != lastNowPlayingChapterID {
            lastNowPlayingChapterID = player.currentChapter?.id
            updateNowPlayingInfo()
        }
        saveCurrentPosition(force: false)
    }

    func syncPlayerState() {
        let wasPlaying = player.isPlaying
        player.isPlaying = playback.playing
        player.isBuffering = playback.isBuffering
        if wasPlaying != player.isPlaying {
            updateNowPlayingInfo()
        }
    }

    func handleEpisodeFinished() async {
        guard let finishedID = player.episodeID else { return }
        library.markPlayed(finishedID)
        saveLibrary()
        if library.playback.removeDownloadsWhenPlayed,
           let finished = episode(withID: finishedID), finished.download?.state == .downloaded {
            Task { try? await downloadService.deleteDownload(for: finished); await updateEpisode(finishedID) { $0.download = nil } }
        }
        if player.sleepTimer == .endOfEpisode || player.sleepTimer == .endOfChapter {
            player.sleepTimer = .off
            await playback.pause()
            syncPlayerState()
            if let next = library.upNext.items.first.flatMap({ episode(withID: $0) }) {
                await startPlayback(next, resumeAt: nil, autoplay: false)
            }
            return
        }
        if library.playback.autoPlayNext, !library.upNext.items.isEmpty {
            await playNextInQueue()
        } else {
            closePlayer()
        }
    }

    private func checkSleepTimer() {
        switch player.sleepTimer {
        case .until(let date) where Date() >= date:
            player.sleepTimer = .off
            Task { await pause() }
        case .endOfChapter where player.currentChapter?.id != sleepChapterID:
            player.sleepTimer = .off
            Task { await pause() }
        default:
            break
        }
    }

    func saveCurrentPosition(force: Bool) {
        guard let episodeID = player.episodeID else { return }
        guard force || Date().timeIntervalSince(lastPositionSave) > 10 else { return }
        lastPositionSave = Date()
        if pendingListenedSeconds > 0 {
            library.stats.secondsListened += pendingListenedSeconds
            pendingListenedSeconds = 0
        }
        var state = state(for: episodeID)
        let time = player.currentTime
        if state.isPlayed || PlaybackProgress.isFinished(position: time, duration: player.duration) {
            return
        }
        state.playbackPosition = time
        state.lastPlayedAt = Date()
        library.episodes[episodeID] = state
        saveLibrary()
    }

    func updateNowPlayingInfo() {
        guard let episode = nowPlayingEpisode else { return }
        nowPlaying.update(
            episode: episode,
            podcastTitle: podcastTitle(for: episode),
            chapterTitle: player.currentChapter?.title,
            elapsed: player.currentTime,
            duration: player.duration,
            rate: player.rate,
            isPlaying: player.isPlaying
        )
    }

    private func loadChapters(for episode: PodcastEpisode, source: AVPlayerPlaybackService.Source) {
        let localFile: URL? = if case .local(let url) = source { url } else { nil }
        Task {
            let chapters = await EpisodeChapterLoader.chapters(for: episode, preferLocalFile: localFile)
            guard player.episodeID == episode.id else { return }
            player.chapters = chapters
            updateNowPlayingInfo()
        }
    }

    // MARK: Up Next

    func playNext(_ episode: PodcastEpisode) {
        guard player.episodeID != episode.id else { return }
        library.upNext.playNext(episode.id)
        saveLibrary()
    }

    func playLast(_ episode: PodcastEpisode) {
        guard player.episodeID != episode.id else { return }
        library.upNext.playLast(episode.id)
        saveLibrary()
    }

    func removeFromUpNext(_ episodeID: UUID) {
        library.upNext.remove(episodeID)
        saveLibrary()
    }

    func moveUpNext(fromOffsets source: IndexSet, toOffset destination: Int) {
        library.upNext.move(fromOffsets: source, toOffset: destination)
        saveLibrary()
    }

    func clearUpNext() {
        library.upNext.clear()
        saveLibrary()
    }

    // MARK: Episode state

    func markPlayed(_ episode: PodcastEpisode) async {
        if player.episodeID == episode.id {
            await handleEpisodeFinished()
            return
        }
        library.markPlayed(episode.id)
        saveLibrary()
    }

    func markUnplayed(_ episode: PodcastEpisode) {
        library.markUnplayed(episode.id)
        saveLibrary()
    }

    func toggleStar(_ episode: PodcastEpisode) {
        library.episodes[episode.id, default: EpisodeUserState()].isStarred.toggle()
        saveLibrary()
    }

    func markAllPlayed(in feed: PodcastFeed) {
        for episode in feed.episodes where player.episodeID != episode.id {
            library.markPlayed(episode.id)
        }
        saveLibrary()
    }

    // MARK: Downloads

    func startDownload(_ episode: PodcastEpisode) {
        guard downloadTasks[episode.id] == nil else { return }
        downloadTasks[episode.id] = Task {
            await download(episode)
            downloadTasks[episode.id] = nil
        }
    }

    func cancelDownload(_ episodeID: UUID) {
        downloadTasks[episodeID]?.cancel()
    }

    func isDownloadActive(_ episodeID: UUID) -> Bool {
        downloadTasks[episodeID] != nil || episode(withID: episodeID)?.download?.state == .downloading
    }

    var downloadsSizeDescription: String {
        let bytes = downloadedEpisodes.reduce(Int64(0)) { total, episode in
            guard let url = episode.download?.localFileURL,
                  let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return total }
            return total + Int64(size)
        }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    func deletePlayedDownloads() async -> Int {
        let played = downloadedEpisodes.filter { state(for: $0.id).isPlayed && player.episodeID != $0.id }
        for episode in played {
            await deleteDownload(episode)
        }
        return played.count
    }

    // MARK: Subscriptions

    func setPreferences(_ preferences: PodcastPreferences, for feedID: UUID) {
        library.podcasts[feedID] = preferences
        saveLibrary()
        if let episode = nowPlayingEpisode, episode.feedID == feedID {
            setSpeed(preferences.playbackSpeed ?? library.playback.speed, persist: false)
        }
    }

    func unsubscribe(_ feedID: UUID) async {
        guard let feed = feed(withID: feedID) else { return }
        if let playing = player.episodeID, feed.episodes.contains(where: { $0.id == playing }) {
            closePlayer()
        }
        for episode in feed.episodes {
            downloadTasks[episode.id]?.cancel()
            if episode.download?.state == .downloaded {
                try? await downloadService.deleteDownload(for: episode)
            }
        }
        feeds.removeAll { $0.id == feedID }
        library.prune(
            keeping: Set(feeds.flatMap { $0.episodes.map(\.id) }),
            podcastIDs: Set(feeds.map(\.id))
        )
        saveLibrary()
        do { try await persistFeeds() } catch { statusMessage = error.localizedDescription }
        statusMessage = "Unsubscribed from \(feed.title)."
    }

    func refreshAllFeeds() async {
        await refreshFeeds(feeds.map(\.id))
    }

    func refreshFeed(_ feedID: UUID) async {
        await refreshFeeds([feedID])
    }

    private func refreshFeeds(_ feedIDs: [UUID]) async {
        guard !isRefreshingFeeds, !feedIDs.isEmpty else { return }
        isRefreshingFeeds = true
        defer { isRefreshingFeeds = false }

        let targets = feedIDs.compactMap { id in feed(withID: id).map { (id, $0.feedURL) } }
        let service = feedService
        let results = await withTaskGroup(of: (UUID, PodcastFeed?).self) { group in
            for (id, url) in targets {
                group.addTask { (id, try? await service.fetchFeed(from: url)) }
            }
            var collected: [(UUID, PodcastFeed?)] = []
            for await result in group { collected.append(result) }
            return collected
        }

        var failures: [String] = []
        var autoDownloads: [PodcastEpisode] = []
        for (id, fresh) in results {
            guard let index = feeds.firstIndex(where: { $0.id == id }) else { continue }
            guard let fresh else {
                failures.append(feeds[index].title)
                continue
            }
            let knownIDs = Set(feeds[index].episodes.map(\.id))
            feeds[index] = PodcastFeedMerger.merge(fresh, into: feeds[index])
            if preferences(for: id).autoDownloadNewEpisodes {
                let added = feeds[index].episodes
                    .filter { !knownIDs.contains($0.id) && $0.download == nil }
                    .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
                autoDownloads += added.prefix(3)
            }
        }
        do { try await persistFeeds() } catch { statusMessage = error.localizedDescription }
        if !failures.isEmpty {
            statusMessage = "Couldn't refresh \(failures.formatted(.list(type: .and)))."
        }
        for episode in autoDownloads {
            startDownload(episode)
        }
    }

    // MARK: OPML

    func importOPML(_ data: Data) async -> (added: Int, failed: Int) {
        let outlines: [OPMLOutline]
        do {
            outlines = try OPMLParser.parse(data)
        } catch {
            statusMessage = error.localizedDescription
            return (0, 0)
        }
        let pending = outlines.filter { !isSubscribed(feedURL: $0.feedURL) }
        var added = 0
        var failed = 0
        let service = feedService
        // Fetch a few feeds at a time to stay friendly to podcast hosts.
        for batch in stride(from: 0, to: pending.count, by: 6).map({ Array(pending[$0..<min($0 + 6, pending.count)]) }) {
            let fetched = await withTaskGroup(of: PodcastFeed?.self) { group in
                for outline in batch {
                    group.addTask { try? await service.fetchFeed(from: outline.feedURL) }
                }
                var collected: [PodcastFeed?] = []
                for await feed in group { collected.append(feed) }
                return collected
            }
            for feed in fetched {
                guard let feed else {
                    failed += 1
                    continue
                }
                guard !isSubscribed(feedURL: feed.feedURL) else { continue }
                feeds.append(feed)
                library.podcasts[feed.id] = PodcastPreferences(addedAt: Date())
                added += 1
            }
        }
        saveLibrary()
        do { try await persistFeeds() } catch { statusMessage = error.localizedDescription }
        statusMessage = failed == 0 ? "Imported \(added) podcasts." : "Imported \(added) podcasts. \(failed) feeds couldn't be loaded."
        return (added, failed)
    }

    func exportOPMLFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "TurtlePod Subscriptions.opml")
        try OPMLExporter.export(feeds).write(to: url, options: [.atomic])
        return url
    }

    // MARK: Persistence

    func saveLibrary() {
        guard libraryStore != nil, !isLibrarySaveScheduled else { return }
        isLibrarySaveScheduled = true
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            isLibrarySaveScheduled = false
            try? await libraryStore?.save(library)
        }
    }

    func saveLibraryNow() async {
        try? await libraryStore?.save(library)
    }
}
