import Foundation
import SwiftUI
import TurtlePodCore

@MainActor
final class TurtlePodModel: ObservableObject {
    @Published var feeds: [PodcastFeed] = []
    @Published var settings = AppSettings()
    @Published var apiKeyDraft = ""
    @Published var statusMessage: String?
    @Published var activeSkipEvent: SkipEvent?

    let playback: AVPlayerPlaybackService
    private let feedService: PodcastFeedService
    private let downloadService: EpisodeDownloadService
    private let store: EpisodeStore
    private let keyStore: APIKeyStore
    private let analysisPipeline: EpisodeAnalysisPipeline
    private let autoSkipController: AutoSkipController

    static func makeDefault() -> TurtlePodModel {
        let provider = OpenAIProvider()
        let playback = AVPlayerPlaybackService()
        let store = try! JSONEpisodeStore()
        let keyStore = KeychainOpenAIKeyStore()
        return TurtlePodModel(
            feedService: RSSPodcastFeedService(),
            downloadService: try! FileEpisodeDownloadService(),
            playback: playback,
            store: store,
            keyStore: keyStore,
            analysisPipeline: EpisodeAnalysisPipeline(
                transcriptService: DefaultTranscriptService(provider: provider),
                adDetectionService: DefaultAdDetectionService(provider: provider),
                apiKeyStore: keyStore,
                providerMetadata: AIProviderMetadata(
                    provider: provider.providerName,
                    transcriptionModel: provider.transcriptionModel,
                    classificationModel: provider.classificationModel
                )
            ),
            autoSkipController: AutoSkipController(playback: playback, store: store)
        )
    }

    init(
        feedService: PodcastFeedService,
        downloadService: EpisodeDownloadService,
        playback: AVPlayerPlaybackService,
        store: EpisodeStore,
        keyStore: APIKeyStore,
        analysisPipeline: EpisodeAnalysisPipeline,
        autoSkipController: AutoSkipController
    ) {
        self.feedService = feedService
        self.downloadService = downloadService
        self.playback = playback
        self.store = store
        self.keyStore = keyStore
        self.analysisPipeline = analysisPipeline
        self.autoSkipController = autoSkipController
    }

    var allEpisodes: [PodcastEpisode] {
        feeds.flatMap(\.episodes).sorted { lhs, rhs in
            (lhs.publishedAt ?? .distantPast) > (rhs.publishedAt ?? .distantPast)
        }
    }

    var downloadedEpisodes: [PodcastEpisode] {
        allEpisodes.filter { $0.download?.state == .downloaded }
    }

    var currentEpisode: PodcastEpisode? {
        get async { await playback.currentEpisode }
    }

    func load() async {
        do {
            feeds = try await store.loadFeeds()
            let removedStaleDownloads = clearStaleDownloads()
            if removedStaleDownloads {
                try await persistFeeds()
            }
            settings = try await store.loadSettings()
            apiKeyDraft = (try keyStore.loadOpenAIKey()) ?? ""
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func addFeed(urlString: String) async {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            statusMessage = "Enter a valid RSS URL."
            return
        }

        do {
            statusMessage = "Fetching feed..."
            let feed = try await feedService.fetchFeed(from: url)
            feeds.removeAll { $0.feedURL == feed.feedURL }
            feeds.append(feed)
            try await persistFeeds()
            statusMessage = "Added \(feed.title)."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func download(_ episode: PodcastEpisode) async {
        await updateEpisode(episode.id) { episode in
            episode.download = EpisodeDownload(state: .downloading, progress: 0)
        }

        do {
            let result = try await downloadService.download(episode)
            await updateEpisode(episode.id) { episode in
                episode.download = result
            }
            statusMessage = "Downloaded \(episode.title)."
        } catch {
            await updateEpisode(episode.id) { episode in
                episode.download = EpisodeDownload(state: .failed, progress: 0, errorMessage: error.localizedDescription)
            }
            statusMessage = error.localizedDescription
        }
    }

    func deleteDownload(_ episode: PodcastEpisode) async {
        do {
            try await downloadService.deleteDownload(for: episode)
            await updateEpisode(episode.id) { episode in
                episode.download = nil
                episode.analysis = EpisodeAnalysis()
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func analyze(_ episode: PodcastEpisode) async {
        guard settings.aiAnalysisEnabled else {
            statusMessage = "Enable AI analysis in Settings first."
            return
        }
        guard await ensureDownloadFileExists(for: episode.id) else {
            return
        }

        await updateEpisode(episode.id) { episode in
            episode.analysis.status = .transcribing
            episode.analysis.errorMessage = nil
        }

        do {
            let analysis = try await analysisPipeline.analyze(
                episode,
                statusDidChange: { status in
                    await self.updateEpisode(episode.id) { episode in
                        episode.analysis.status = status
                    }
                    if status == .classifying {
                        self.statusMessage = "Classifying transcript for ads..."
                    }
                },
                transcriptionProgressDidChange: { currentChunk, totalChunks in
                    self.statusMessage = "Transcribing audio chunk \(currentChunk) of \(totalChunks)..."
                }
            )
            await updateEpisode(episode.id) { episode in
                episode.analysis = analysis
            }
            statusMessage = "Analysis complete."
        } catch {
            await updateEpisode(episode.id) { episode in
                episode.analysis.status = .failed
                episode.analysis.errorMessage = error.localizedDescription
            }
            statusMessage = error.localizedDescription
        }
    }

    func play(_ episode: PodcastEpisode) async {
        guard await ensureDownloadFileExists(for: episode.id) else {
            return
        }

        do {
            guard let currentEpisode = self.episode(withID: episode.id) else {
                throw TurtlePodError.notDownloaded
            }
            try await playback.load(currentEpisode)
            await autoSkipController.resetForNewEpisode()
            await playback.play()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func togglePlayback() async {
        if await playback.isPlaying {
            await playback.pause()
        } else {
            await playback.play()
        }
    }

    func seek(to time: TimeInterval) async {
        await playback.seek(to: time)
    }

    func evaluateAutoSkip() async {
        guard let episode = await playback.currentEpisode else { return }
        let time = await playback.currentTime

        do {
            if let event = try await autoSkipController.evaluate(
                episode: episode,
                currentTime: time,
                globalAutoSkipEnabled: settings.autoSkipEnabled,
                confidenceThreshold: settings.adSkipConfidenceThreshold
            ) {
                activeSkipEvent = event
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(8))
                    if activeSkipEvent?.id == event.id {
                        activeSkipEvent = nil
                    }
                }
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func undoLastSkip() async {
        await autoSkipController.undoLastSkip()
        activeSkipEvent = nil
    }

    func setEpisodeAutoSkip(_ enabled: Bool, episodeID: UUID) async {
        await updateEpisode(episodeID) { episode in
            episode.autoSkipEnabled = enabled
        }
    }

    func saveSettings() async {
        do {
            try await store.saveSettings(settings)
            if apiKeyDraft.isEmpty {
                try keyStore.deleteOpenAIKey()
            } else {
                try keyStore.saveOpenAIKey(apiKeyDraft)
            }
            statusMessage = "Settings saved."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func episode(withID id: UUID) -> PodcastEpisode? {
        allEpisodes.first { $0.id == id }
    }

    private func updateEpisode(_ episodeID: UUID, mutate: (inout PodcastEpisode) -> Void) async {
        for feedIndex in feeds.indices {
            guard let episodeIndex = feeds[feedIndex].episodes.firstIndex(where: { $0.id == episodeID }) else {
                continue
            }
            mutate(&feeds[feedIndex].episodes[episodeIndex])
            break
        }
        try? await persistFeeds()
    }

    private func ensureDownloadFileExists(for episodeID: UUID) async -> Bool {
        guard let episode = episode(withID: episodeID),
              episode.download?.state == .downloaded else {
            await markDownloadMissing(episodeID)
            return false
        }

        if let localFileURL = episode.download?.localFileURL,
           FileManager.default.fileExists(atPath: localFileURL.path(percentEncoded: false)) {
            return true
        }

        let recoveredURL = downloadService.localFileURL(for: episode)
        guard FileManager.default.fileExists(atPath: recoveredURL.path(percentEncoded: false)) else {
            await markDownloadMissing(episodeID)
            return false
        }

        await updateEpisode(episodeID) { episode in
            episode.download?.localFileURL = recoveredURL
        }
        return true
    }

    private func markDownloadMissing(_ episodeID: UUID) async {
        await updateEpisode(episodeID) { episode in
            episode.download = EpisodeDownload(
                state: .failed,
                progress: 0,
                errorMessage: "The downloaded file is missing. Download the episode again."
            )
            episode.analysis = EpisodeAnalysis()
        }
        statusMessage = "The downloaded file is missing. Download the episode again."
    }

    private func clearStaleDownloads() -> Bool {
        var changed = false
        for feedIndex in feeds.indices {
            for episodeIndex in feeds[feedIndex].episodes.indices {
                let download = feeds[feedIndex].episodes[episodeIndex].download
                guard download?.state == .downloaded else {
                    continue
                }
                guard let localFileURL = download?.localFileURL,
                      FileManager.default.fileExists(atPath: localFileURL.path(percentEncoded: false)) else {
                    let episode = feeds[feedIndex].episodes[episodeIndex]
                    let recoveredURL = downloadService.localFileURL(for: episode)
                    if FileManager.default.fileExists(atPath: recoveredURL.path(percentEncoded: false)) {
                        feeds[feedIndex].episodes[episodeIndex].download?.localFileURL = recoveredURL
                        changed = true
                        continue
                    }

                    feeds[feedIndex].episodes[episodeIndex].download = EpisodeDownload(
                        state: .failed,
                        progress: 0,
                        errorMessage: "The downloaded file is missing. Download the episode again."
                    )
                    feeds[feedIndex].episodes[episodeIndex].analysis = EpisodeAnalysis()
                    changed = true
                    continue
                }
            }
        }
        return changed
    }

    private func persistFeeds() async throws {
        try await store.saveFeeds(feeds)
    }
}
