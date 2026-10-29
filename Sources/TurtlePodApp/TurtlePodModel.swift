import Foundation
import SwiftUI
import TurtlePodCore

@MainActor
final class TurtlePodModel: ObservableObject {
    @Published var feeds: [PodcastFeed] = [] {
        didSet { rebuildEpisodeIndex() }
    }
    @Published var library = LibraryState()
    @Published var isRefreshingFeeds = false
    @Published var hasLoaded = false
    @Published var settings = AppSettings()
    @Published var apiKeyDraft = ""
    @Published var typeSafeKeyDraft = ""
    @Published var openRouterKeyDraft = ""
    @Published var statusMessage: String?
    @Published var activeSkipEvent: SkipEvent?
    @Published var selectedWhisperModelIsDownloaded = false
    @Published var appleSpeechAvailabilityMessage = "Checking Apple Speech model…"
    @Published private var transcriptionProgressByEpisodeID: [UUID: Double] = [:]

    @Published private(set) var busyEpisodeIDs: Set<UUID> = []
    @Published private(set) var referenceMessages: [UUID: String] = [:]
    private let referenceService: any ReferenceTranscriptService = HTTPReferenceTranscriptService()

    let player = PlayerController()
    let nowPlaying = NowPlayingCenter()
    let directory: PodcastDirectoryService = ITunesPodcastDirectoryService()
    let libraryStore: LibraryStateStore?
    private(set) var allEpisodes: [PodcastEpisode] = []
    private var episodeIndex: [UUID: PodcastEpisode] = [:]
    private var feedIndex: [UUID: PodcastFeed] = [:]
    var downloadTasks: [UUID: Task<Void, Never>] = [:]
    var lastTickPosition: TimeInterval?
    var lastPositionSave = Date.distantPast
    var lastNowPlayingChapterID: UUID?
    var sleepChapterID: UUID?
    var isLibrarySaveScheduled = false
    var pendingListenedSeconds: TimeInterval = 0
    /// Bumped on every episode load so a slower, older load can't win.
    var playbackGeneration = 0
    var isLoadingEpisode = false
    var pausedAt: Date?
    private var savedKeys: [String] = ["", "", ""]

    let playback: AVPlayerPlaybackService
    let feedService: PodcastFeedService
    let downloadService: EpisodeDownloadService
    private let store: EpisodeStore
    private let keyStore: APIKeyStore
    private let jevKeyStore = KeychainJevKeyStore()
    private let openAIProvider: OpenAIProvider
    let autoSkipController: AutoSkipController

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
            openAIProvider: provider,
            autoSkipController: AutoSkipController(playback: playback, store: store),
            libraryStore: try? LibraryStateStore()
        )
    }

    init(
        feedService: PodcastFeedService,
        downloadService: EpisodeDownloadService,
        playback: AVPlayerPlaybackService,
        store: EpisodeStore,
        keyStore: APIKeyStore,
        openAIProvider: OpenAIProvider,
        autoSkipController: AutoSkipController,
        libraryStore: LibraryStateStore? = nil
    ) {
        self.feedService = feedService
        self.downloadService = downloadService
        self.playback = playback
        self.store = store
        self.keyStore = keyStore
        self.openAIProvider = openAIProvider
        self.autoSkipController = autoSkipController
        self.libraryStore = libraryStore
        configurePlayback()
    }

    private func rebuildEpisodeIndex() {
        var episodes: [UUID: PodcastEpisode] = [:]
        var feedsByID: [UUID: PodcastFeed] = [:]
        for feed in feeds {
            feedsByID[feed.id] = feed
            for episode in feed.episodes {
                episodes[episode.id] = episode
            }
        }
        episodeIndex = episodes
        feedIndex = feedsByID
        allEpisodes = episodes.values.sorted { lhs, rhs in
            (lhs.publishedAt ?? .distantPast) > (rhs.publishedAt ?? .distantPast)
        }
        if let loaded = playback.loadedEpisodeID, let episode = episodes[loaded] {
            playback.updateLoadedEpisode(episode)
        }
    }

    var downloadedEpisodes: [PodcastEpisode] {
        allEpisodes.filter { $0.download?.state == .downloaded }
    }

    func feed(withID id: UUID) -> PodcastFeed? {
        feedIndex[id]
    }

    func load() async {
        do {
            feeds = try await store.loadFeeds()
            let cleanedSavedDescriptions = cleanSavedEpisodeDescriptions()
            let removedStaleDownloads = clearStaleDownloads()
            if cleanedSavedDescriptions || removedStaleDownloads {
                try await persistFeeds()
            }
            settings = try await store.loadSettings()
            if let libraryStore {
                library = (try? await libraryStore.load()) ?? LibraryState()
            }
            hasLoaded = true
            await restoreNowPlaying()
            apiKeyDraft = (try? keyStore.loadOpenAIKey()) ?? ""
            typeSafeKeyDraft = (try? jevKeyStore.loadKey(for: .typeSafe)) ?? ""
            openRouterKeyDraft = (try? jevKeyStore.loadKey(for: .openRouter)) ?? ""
            savedKeys = currentKeys
            await refreshSelectedWhisperModelStatus()
        } catch {
            hasLoaded = true
            statusMessage = error.localizedDescription
        }
        if library.playback.refreshOnLaunch, !feeds.isEmpty {
            await refreshAllFeeds()
        }
    }

    @discardableResult
    private func cleanSavedEpisodeDescriptions() -> Bool {
        var didChange = false

        for feedIndex in feeds.indices {
            for episodeIndex in feeds[feedIndex].episodes.indices {
                let cleaned = EpisodeDescriptionCleaner.clean(feeds[feedIndex].episodes[episodeIndex].description)
                if cleaned != feeds[feedIndex].episodes[episodeIndex].description {
                    feeds[feedIndex].episodes[episodeIndex].description = cleaned
                    didChange = true
                }
            }
        }

        return didChange
    }

    func refreshSelectedWhisperModelStatus() async {
        selectedWhisperModelIsDownloaded = await WhisperModelManager.shared.isModelDownloaded(size: settings.whisperModelSize)
    }

    @discardableResult
    func addFeed(urlString: String) async -> UUID? {
        var trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("feed://") {
            trimmed = "https://" + trimmed.dropFirst("feed://".count)
        } else if !trimmed.contains("://") {
            trimmed = "https://" + trimmed
        }
        guard let url = URL(string: trimmed),
              TranscriptSource.isRemoteURL(url) else {
            statusMessage = "Enter a valid RSS feed URL."
            return nil
        }

        do {
            statusMessage = "Fetching feed…"
            let feed = try await feedService.fetchFeed(from: url)
            let feedID: UUID
            if let index = feeds.firstIndex(where: { $0.feedURL == feed.feedURL }) {
                feeds[index] = PodcastFeedMerger.merge(feed, into: feeds[index])
                feedID = feeds[index].id
            } else {
                feeds.append(feed)
                feedID = feed.id
                var preferences = library.preferences(for: feed.id)
                preferences.addedAt = Date()
                library.podcasts[feed.id] = preferences
                saveLibrary()
            }
            try await persistFeeds()
            statusMessage = "Subscribed to \(feed.title)."
            return feedID
        } catch {
            statusMessage = "Couldn't add that feed: \(error.localizedDescription)"
            return nil
        }
    }

    func download(_ episode: PodcastEpisode) async {
        guard !busyEpisodeIDs.contains(episode.id), let latest = self.episode(withID: episode.id) else { return }
        let episode = latest
        busyEpisodeIDs.insert(episode.id)
        defer { busyEpisodeIDs.remove(episode.id) }
        guard episode.download?.state != .downloaded else { return }
        await updateEpisode(episode.id) { episode in
            // A fresh download may contain different ads and timing.
            episode.analysis = EpisodeAnalysis()
            episode.download = EpisodeDownload(state: .downloading, progress: 0)
        }

        do {
            let result = try await downloadService.download(
                episode,
                progressDidChange: { progress in
                    // Each update rewrites the feed list, so skip sub-percent changes.
                    let shown = self.episode(withID: episode.id)?.download?.progress ?? 0
                    guard progress - shown >= 0.01 || progress >= 1 else { return }
                    await self.updateEpisode(episode.id, persist: false) { episode in
                        episode.download?.progress = min(max(progress, 0), 1)
                    }
                }
            )
            await updateEpisode(episode.id) { episode in
                episode.download = result
            }
            statusMessage = "Downloaded \(episode.title)."
            if settings.analyzeAfterDownload, settings.aiAnalysisEnabled {
                Task { await self.analyze(episode) }
            }
        } catch is CancellationError {
            await updateEpisode(episode.id) { episode in
                episode.download = nil
            }
        } catch let error as URLError where error.code == .cancelled {
            await updateEpisode(episode.id) { episode in
                episode.download = nil
            }
        } catch {
            await updateEpisode(episode.id) { episode in
                episode.download = EpisodeDownload(state: .failed, progress: 0, errorMessage: error.localizedDescription)
            }
            statusMessage = error.localizedDescription
        }
    }

    func deleteDownload(_ episode: PodcastEpisode) async {
        guard !busyEpisodeIDs.contains(episode.id), let latest = self.episode(withID: episode.id) else { return }
        let episode = latest
        busyEpisodeIDs.insert(episode.id)
        defer { busyEpisodeIDs.remove(episode.id) }
        do {
            let wasLoaded = playback.loadedEpisodeID == episode.id
            let wasPlaying = playback.playing
            try await downloadService.deleteDownload(for: episode)
            await updateEpisode(episode.id) { episode in
                episode.download = nil
                episode.analysis = EpisodeAnalysis()
            }
            if wasLoaded {
                // Keep listening from the stream instead of stopping playback.
                activeSkipEvent = nil
                await autoSkipController.resetForNewEpisode()
                if let refreshed = self.episode(withID: episode.id) {
                    await startPlayback(refreshed, resumeAt: player.currentTime, autoplay: wasPlaying)
                }
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func analyze(_ episode: PodcastEpisode) async {
        guard !busyEpisodeIDs.contains(episode.id), let latest = self.episode(withID: episode.id) else { return }
        let episode = latest
        busyEpisodeIDs.insert(episode.id)
        defer { busyEpisodeIDs.remove(episode.id) }
        guard settings.aiAnalysisEnabled else {
            statusMessage = "Enable AI analysis in Settings first."
            return
        }
        guard await ensureDownloadFileExists(for: episode.id) else {
            return
        }

        await fetchPublisherReferenceIfNeeded(episode)
        guard let analysisEpisode = self.episode(withID: episode.id) else { return }

        await updateEpisode(episode.id) { episode in
            episode.analysis.status = .transcribing
            episode.analysis.errorMessage = nil
        }
        setTranscriptionProgress(0, for: episode.id)

        do {
            let analysisPipeline = try makeAnalysisPipeline()
            let providerMetadata = await analysisPipeline.metadata
            let transcriptionLabel = analysisStatusLabel(
                provider: providerMetadata.transcriptionProvider,
                model: providerMetadata.transcriptionModel
            )
            let classificationLabel = analysisStatusLabel(
                provider: providerMetadata.classificationProvider,
                model: providerMetadata.classificationModel
            )
            statusMessage = "Transcribing with \(transcriptionLabel)…"
            let analysis = try await analysisPipeline.analyze(
                analysisEpisode,
                statusDidChange: { status in
                    await self.updateEpisode(episode.id) { episode in
                        episode.analysis.status = status
                    }
                    if status == .classifying {
                        self.statusMessage = "Classifying ads with \(classificationLabel)…"
                    }
                },
                transcriptionProgressDidChange: { currentChunk, totalChunks in
                    let progress = totalChunks > 0 ? Double(currentChunk) / Double(totalChunks) : 0
                    self.setTranscriptionProgress(progress, for: episode.id)
                    self.statusMessage = "Transcribing with \(transcriptionLabel): \(Int((progress * 100).rounded()))%…"
                }
            )
            await updateEpisode(episode.id) { episode in
                episode.analysis = analysis
            }
            if settings.aiTranscriptionProvider == .localWhisper {
                await refreshSelectedWhisperModelStatus()
            } else if settings.aiTranscriptionProvider == .appleSpeech {
                await refreshAppleSpeechModelStatus()
            }
            setTranscriptionProgress(nil, for: episode.id)
            statusMessage = "Analysis complete."
        } catch {
            if settings.aiTranscriptionProvider == .localWhisper {
                await refreshSelectedWhisperModelStatus()
            } else if settings.aiTranscriptionProvider == .appleSpeech {
                await refreshAppleSpeechModelStatus()
            }
            await updateEpisode(episode.id) { episode in
                episode.analysis.status = .failed
                episode.analysis.errorMessage = error.localizedDescription
            }
            setTranscriptionProgress(nil, for: episode.id)
            statusMessage = error.localizedDescription
        }
    }

    func reanalyzeAds(_ episode: PodcastEpisode) async {
        guard !busyEpisodeIDs.contains(episode.id), let latest = self.episode(withID: episode.id) else { return }
        let episode = latest
        busyEpisodeIDs.insert(episode.id)
        defer { busyEpisodeIDs.remove(episode.id) }
        guard settings.aiAnalysisEnabled else {
            statusMessage = "Enable AI analysis in Settings first."
            return
        }
        guard !episode.analysis.transcript.isEmpty else {
            statusMessage = "Analyze the download once before re-analyzing ads."
            return
        }

        do {
            let context = try makeAdDetectionContext(existingMetadata: episode.analysis.providerMetadata)
            let classificationLabel = analysisStatusLabel(
                provider: context.providerMetadata.classificationProvider,
                model: context.providerMetadata.classificationModel
            )
            await updateEpisode(episode.id) { episode in
                episode.analysis.status = .classifying
                episode.analysis.errorMessage = nil
            }
            statusMessage = "Classifying ads with \(classificationLabel)…"

            let comparison = episode.referenceTranscript.map {
                ReferenceTranscriptAlignment.compare(episode.analysis.transcript, to: $0)
            }
            let adSegments = try await context.adDetectionService.detectAds(in: episode.analysis.transcript, comparison: comparison)
            await updateEpisode(episode.id) { episode in
                episode.analysis.status = .complete
                episode.analysis.adSegments = adSegments
                episode.analysis.referenceComparison = comparison
                episode.analysis.providerMetadata = context.providerMetadata
                episode.analysis.errorMessage = nil
            }
            statusMessage = "Ad analysis updated."
        } catch {
            await updateEpisode(episode.id) { episode in
                episode.analysis.status = .failed
                episode.analysis.errorMessage = error.localizedDescription
            }
            statusMessage = error.localizedDescription
        }
    }

    var needsOpenAIKey: Bool {
        settings.aiTranscriptionProvider == .openAI
            || settings.aiClassificationProvider == .openAI
    }

    var needsTypeSafeKey: Bool { settings.aiClassificationProvider == .jevTypeSafe }
    var needsOpenRouterKey: Bool { settings.aiClassificationProvider == .jevOpenRouter }

    var appleFoundationModelsAvailabilityMessage: String {
        AppleFoundationModelsAdClassifier.availabilityStatusMessage
    }

    func refreshAppleSpeechModelStatus() async {
        if #available(iOS 26.0, macOS 26.0, *) {
            appleSpeechAvailabilityMessage = await AppleSpeechProvider.modelStatusMessage()
        } else {
            appleSpeechAvailabilityMessage = "Requires iOS 26 or later."
        }
    }

    func evaluateAutoSkip(at time: TimeInterval) async {
        guard let playingID = playback.loadedEpisodeID,
              let episode = self.episode(withID: playingID),
              case .local = playback.source,
              !isLoadingEpisode,
              !busyEpisodeIDs.contains(episode.id) else { return }

        do {
            if let event = try await autoSkipController.evaluate(
                episode: episode,
                currentTime: time,
                globalAutoSkipEnabled: settings.autoSkipEnabled,
                confidenceThreshold: settings.adSkipConfidenceThreshold
            ) {
                activeSkipEvent = event
                library.stats.adsSkipped += 1
                library.stats.secondsSkippedAds += max(event.skippedTo - event.skippedFrom, 0)
                syncAfterJump()
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
        if let event = activeSkipEvent {
            library.stats.adsSkipped = max(library.stats.adsSkipped - 1, 0)
            library.stats.secondsSkippedAds = max(library.stats.secondsSkippedAds - (event.skippedTo - event.skippedFrom), 0)
        }
        activeSkipEvent = nil
        syncAfterJump()
    }

    func setEpisodeAutoSkip(_ enabled: Bool, episodeID: UUID) async {
        await updateEpisode(episodeID) { episode in
            episode.autoSkipEnabled = enabled
        }
    }

    func saveSettings(includingKeys: Bool = true) async {
        do {
            try await store.saveSettings(settings)
            guard includingKeys, currentKeys != savedKeys else { return }
            if apiKeyDraft.isEmpty {
                try keyStore.deleteOpenAIKey()
            } else {
                try keyStore.saveOpenAIKey(apiKeyDraft)
            }
            if typeSafeKeyDraft.isEmpty {
                try jevKeyStore.deleteKey(for: .typeSafe)
            } else {
                try jevKeyStore.saveKey(typeSafeKeyDraft, for: .typeSafe)
            }
            if openRouterKeyDraft.isEmpty {
                try jevKeyStore.deleteKey(for: .openRouter)
            } else {
                try jevKeyStore.saveKey(openRouterKeyDraft, for: .openRouter)
            }
            savedKeys = currentKeys
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private var currentKeys: [String] {
        [apiKeyDraft, typeSafeKeyDraft, openRouterKeyDraft]
    }

    func episode(withID id: UUID) -> PodcastEpisode? {
        episodeIndex[id]
    }

    func transcriptionProgress(for episodeID: UUID) -> Double? {
        transcriptionProgressByEpisodeID[episodeID]
    }

    func updateEpisode(_ episodeID: UUID, persist: Bool = true, mutate: (inout PodcastEpisode) -> Void) async {
        for feedIndex in feeds.indices {
            guard let episodeIndex = feeds[feedIndex].episodes.firstIndex(where: { $0.id == episodeID }) else {
                continue
            }
            mutate(&feeds[feedIndex].episodes[episodeIndex])
            break
        }
        if persist {
            do { try await persistFeeds() } catch { statusMessage = error.localizedDescription }
        }
    }

    private func setTranscriptionProgress(_ progress: Double?, for episodeID: UUID) {
        var nextProgress = transcriptionProgressByEpisodeID
        if let progress {
            nextProgress[episodeID] = min(max(progress, 0), 1)
        } else {
            nextProgress.removeValue(forKey: episodeID)
        }
        transcriptionProgressByEpisodeID = nextProgress
    }

    private func analysisStatusLabel(provider: String, model: String) -> String {
        "\(analysisProviderDisplayName(provider)) (\(model))"
    }

    private func analysisProviderDisplayName(_ provider: String) -> String {
        switch provider {
        case "openai":
            "OpenAI"
        case "openai-decisions":
            "OpenAI Decisions"
        case "publisher-transcript":
            "Publisher Transcript"
        case "local-whisper":
            "Local Whisper"
        case "apple-speech":
            "Apple Speech"
        case "apple-foundation-models":
            "Apple On-Device"
        case "jev-typesafe":
            "Jev via TypeSafe"
        case "jev-openrouter":
            "Jev via OpenRouter"
        default:
            provider
        }
    }

    private func makeAnalysisPipeline() throws -> EpisodeAnalysisPipeline {
        let transcriptionProvider: TranscriptionProvider
        let apiKey: String

        let needsOpenAIKey = settings.aiTranscriptionProvider == .openAI
            || settings.aiClassificationProvider == .openAI

        if needsOpenAIKey {
            guard let openAIAPIKey = try keyStore.loadOpenAIKey(), !openAIAPIKey.isEmpty else {
                throw TurtlePodError.apiKeyMissing
            }
            apiKey = openAIAPIKey
        } else {
            apiKey = ""
        }

        switch settings.aiTranscriptionProvider {
        case .openAI:
            transcriptionProvider = openAIProvider
        case .localWhisper:
            transcriptionProvider = LocalWhisperProvider(modelSize: settings.whisperModelSize)
        case .appleSpeech:
            if #available(iOS 26.0, macOS 26.0, *) {
                transcriptionProvider = AppleSpeechProvider()
            } else {
                throw TurtlePodError.localModelUnavailable("Apple Speech transcription requires iOS 26 or later.")
            }
        }

        let context = try makeAdDetectionContext(
            openAIAPIKey: apiKey.isEmpty ? nil : apiKey,
            existingMetadata: nil
        )

        return EpisodeAnalysisPipeline(
            transcriptService: DefaultTranscriptService(provider: transcriptionProvider),
            adDetectionService: context.adDetectionService,
            transcriptionAPIKey: apiKey,
            requiresTranscriptionAPIKey: settings.aiTranscriptionProvider == .openAI,
            providerMetadata: AIProviderMetadata(
                provider: transcriptionProvider.providerName,
                transcriptionProvider: transcriptionProvider.providerName,
                transcriptionModel: transcriptionProvider.transcriptionModel,
                classificationProvider: context.providerMetadata.classificationProvider,
                classificationModel: context.providerMetadata.classificationModel
            )
        )
    }

    private func makeAdDetectionContext(
        openAIAPIKey providedOpenAIAPIKey: String? = nil,
        existingMetadata: AIProviderMetadata?
    ) throws -> AdDetectionContext {
        let classificationProvider: AdClassificationProvider
        let classificationAPIKey: String

        switch settings.aiClassificationProvider {
        case .openAI:
            let openAIAPIKey = try providedOpenAIAPIKey ?? keyStore.loadOpenAIKey()
            guard let openAIAPIKey, !openAIAPIKey.isEmpty else {
                throw TurtlePodError.apiKeyMissing
            }
            classificationProvider = OpenAIDecisionsAdClassifier()
            classificationAPIKey = openAIAPIKey
        case .appleFoundationModels:
            try AppleFoundationModelsAdClassifier.validateAvailability()
            classificationProvider = AppleFoundationModelsAdClassifier()
            classificationAPIKey = ""
        case .jevTypeSafe:
            guard let key = try jevKeyStore.loadKey(for: .typeSafe), !key.isEmpty else {
                throw JevClassifierError.missingKey("TypeSafe")
            }
            classificationProvider = JevAdClassifier(route: .typeSafe)
            classificationAPIKey = key
        case .jevOpenRouter:
            guard let key = try jevKeyStore.loadKey(for: .openRouter), !key.isEmpty else {
                throw JevClassifierError.missingKey("OpenRouter")
            }
            classificationProvider = JevAdClassifier(route: .openRouter)
            classificationAPIKey = key
        }

        return AdDetectionContext(
            adDetectionService: DefaultAdDetectionService(
                provider: classificationProvider,
                apiKey: classificationAPIKey
            ),
            providerMetadata: AIProviderMetadata(
                provider: classificationProvider.providerName,
                transcriptionProvider: existingMetadata?.transcriptionProvider ?? openAIProvider.providerName,
                transcriptionModel: existingMetadata?.transcriptionModel ?? openAIProvider.transcriptionModel,
                classificationProvider: classificationProvider.providerName,
                classificationModel: classificationProvider.classificationModel
            )
        )
    }

    func ensureDownloadFileExists(for episodeID: UUID) async -> Bool {
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
                if download?.state == .downloading {
                    feeds[feedIndex].episodes[episodeIndex].download = EpisodeDownload(state: .failed, errorMessage: "Download interrupted. Try again.")
                    changed = true
                }
                if [.queued, .transcribing, .classifying].contains(feeds[feedIndex].episodes[episodeIndex].analysis.status) {
                    feeds[feedIndex].episodes[episodeIndex].analysis.status = .failed
                    feeds[feedIndex].episodes[episodeIndex].analysis.errorMessage = "Analysis interrupted. Try again."
                    changed = true
                }
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

    func fetchReference(_ episodeID: UUID, urlString: String? = nil) async {
        guard !busyEpisodeIDs.contains(episodeID), let episode = episode(withID: episodeID) else { return }
        busyEpisodeIDs.insert(episodeID)
        defer { busyEpisodeIDs.remove(episodeID) }
        if let urlString {
            guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
                  TranscriptSource.isRemoteURL(url) else {
                referenceMessages[episodeID] = ReferenceTranscriptError.invalidURL.localizedDescription
                return
            }
            let source = TranscriptSource(url: url, label: url.host == "shownotes.pocketcasts.com" ? "Pocket Casts" : "Imported URL")
            do {
                referenceMessages[episodeID] = "Fetching transcript…"
                let reference = try await referenceService.fetch(source)
                await saveReference(reference, episodeID: episodeID)
            } catch { referenceMessages[episodeID] = error.localizedDescription }
        } else {
            await fetchPublisherReferenceIfNeeded(episode, force: true)
        }
    }

    func importReference(_ data: Data, fileURL: URL, episodeID: UUID) async {
        guard !busyEpisodeIDs.contains(episodeID) else { return }
        busyEpisodeIDs.insert(episodeID)
        defer { busyEpisodeIDs.remove(episodeID) }
        do {
            let source = TranscriptSource(url: fileURL, label: "Imported file")
            let reference = try ReferenceTranscriptParser.parse(data, source: source)
            await saveReference(reference, episodeID: episodeID)
        } catch { referenceMessages[episodeID] = error.localizedDescription }
    }

    func removeReference(episodeID: UUID) async {
        guard !busyEpisodeIDs.contains(episodeID) else { return }
        await updateEpisode(episodeID) { episode in
            episode.referenceTranscript = nil
            episode.analysis.referenceComparison = nil
        }
        referenceMessages[episodeID] = nil
    }

    private func saveReference(_ reference: ReferenceTranscript, episodeID: UUID) async {
        await updateEpisode(episodeID) { episode in
            episode.referenceTranscript = reference
            episode.analysis.referenceComparison = nil
        }
        referenceMessages[episodeID] = "Transcript saved. Analyze or re-analyze ads to compare it with this download."
    }

    private func fetchPublisherReferenceIfNeeded(_ episode: PodcastEpisode, force: Bool = false) async {
        var replacedMismatchedReference = false
        if let cached = episode.referenceTranscript {
            let conflictsWithAppleSpeech = settings.aiTranscriptionProvider == .appleSpeech
                && cached.source.label == "Publisher"
                && cached.source.hasConflictingLanguage(with: "en")
            if conflictsWithAppleSpeech {
                replacedMismatchedReference = true
                await updateEpisode(episode.id) { episode in
                    episode.referenceTranscript = nil
                    episode.analysis.referenceComparison = nil
                }
            } else if !force {
                return
            }
        }
        if episode.transcriptSources == nil || force || replacedMismatchedReference,
           let savedFeed = feeds.first(where: { $0.id == episode.feedID }) {
            do {
                let fresh = try await feedService.fetchFeed(from: savedFeed.feedURL)
                if let index = feeds.firstIndex(where: { $0.id == savedFeed.id }) {
                    feeds[index] = PodcastFeedMerger.merge(fresh, into: feeds[index])
                    try await persistFeeds()
                }
            } catch {
                referenceMessages[episode.id] = "Could not refresh transcript links: \(error.localizedDescription)"
            }
        }
        let preferredLanguage = settings.aiTranscriptionProvider == .appleSpeech ? "en" : nil
        let sources = TranscriptSource.preferredSources(
            from: self.episode(withID: episode.id)?.transcriptSources ?? [],
            preferredLanguage: preferredLanguage
        ).filter { source in
            preferredLanguage.map { !source.hasConflictingLanguage(with: $0) } ?? true
        }
        guard !sources.isEmpty else {
            if force { referenceMessages[episode.id] = "This feed has no transcript links. Import a transcript file or direct URL." }
            return
        }
        referenceMessages[episode.id] = "Fetching publisher transcript…"
        for source in sources.prefix(4) {
            do {
                let reference = try await referenceService.fetch(source)
                await saveReference(reference, episodeID: episode.id)
                return
            } catch is CancellationError {
                return
            } catch {
                referenceMessages[episode.id] = "Publisher transcript unavailable: \(error.localizedDescription) Audio analysis can still run."
            }
        }
    }

    func persistFeeds() async throws {
        try await store.saveFeeds(feeds)
    }
}

private struct AdDetectionContext {
    var adDetectionService: AdDetectionService
    var providerMetadata: AIProviderMetadata
}
