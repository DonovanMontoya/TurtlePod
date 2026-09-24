import Foundation
import SwiftUI
import TurtlePodCore

@MainActor
final class TurtlePodModel: ObservableObject {
    @Published var feeds: [PodcastFeed] = []
    @Published var settings = AppSettings()
    @Published var apiKeyDraft = ""
    @Published var typeSafeKeyDraft = ""
    @Published var openRouterKeyDraft = ""
    @Published var statusMessage: String?
    @Published var activeSkipEvent: SkipEvent?
    @Published var selectedWhisperModelIsDownloaded = false
    @Published var appleSpeechAvailabilityMessage = "Checking Apple Speech model..."
    @Published private var transcriptionProgressByEpisodeID: [UUID: Double] = [:]

    @Published private(set) var busyEpisodeIDs: Set<UUID> = []
    @Published private(set) var referenceMessages: [UUID: String] = [:]
    private let referenceService: any ReferenceTranscriptService = HTTPReferenceTranscriptService()

    let playback: AVPlayerPlaybackService
    private let feedService: PodcastFeedService
    private let downloadService: EpisodeDownloadService
    private let store: EpisodeStore
    private let keyStore: APIKeyStore
    private let jevKeyStore = KeychainJevKeyStore()
    private let openAIProvider: OpenAIProvider
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
            openAIProvider: provider,
            autoSkipController: AutoSkipController(playback: playback, store: store)
        )
    }

    init(
        feedService: PodcastFeedService,
        downloadService: EpisodeDownloadService,
        playback: AVPlayerPlaybackService,
        store: EpisodeStore,
        keyStore: APIKeyStore,
        openAIProvider: OpenAIProvider,
        autoSkipController: AutoSkipController
    ) {
        self.feedService = feedService
        self.downloadService = downloadService
        self.playback = playback
        self.store = store
        self.keyStore = keyStore
        self.openAIProvider = openAIProvider
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
            let cleanedSavedDescriptions = cleanSavedEpisodeDescriptions()
            let removedStaleDownloads = clearStaleDownloads()
            if cleanedSavedDescriptions || removedStaleDownloads {
                try await persistFeeds()
            }
            settings = try await store.loadSettings()
            apiKeyDraft = (try keyStore.loadOpenAIKey()) ?? ""
            typeSafeKeyDraft = (try jevKeyStore.loadKey(for: .typeSafe)) ?? ""
            openRouterKeyDraft = (try jevKeyStore.loadKey(for: .openRouter)) ?? ""
            await refreshSelectedWhisperModelStatus()
        } catch {
            statusMessage = error.localizedDescription
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

    func addFeed(urlString: String) async {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              TranscriptSource.isRemoteURL(url) else {
            statusMessage = "Enter a valid RSS URL."
            return
        }

        do {
            statusMessage = "Fetching feed..."
            let feed = try await feedService.fetchFeed(from: url)
            if let index = feeds.firstIndex(where: { $0.feedURL == feed.feedURL }) {
                feeds[index] = PodcastFeedMerger.merge(feed, into: feeds[index])
            } else {
                feeds.append(feed)
            }
            try await persistFeeds()
            statusMessage = "Added \(feed.title)."
        } catch {
            statusMessage = error.localizedDescription
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
                    await self.updateEpisode(episode.id, persist: false) { episode in
                        episode.download?.progress = min(max(progress, 0), 1)
                    }
                }
            )
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
        guard !busyEpisodeIDs.contains(episode.id), let latest = self.episode(withID: episode.id) else { return }
        let episode = latest
        busyEpisodeIDs.insert(episode.id)
        defer { busyEpisodeIDs.remove(episode.id) }
        do {
            if await playback.currentEpisode?.id == episode.id {
                playback.unload()
                activeSkipEvent = nil
                await autoSkipController.resetForNewEpisode()
            }
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
            statusMessage = "Transcribing with \(transcriptionLabel)..."
            let analysis = try await analysisPipeline.analyze(
                analysisEpisode,
                statusDidChange: { status in
                    await self.updateEpisode(episode.id) { episode in
                        episode.analysis.status = status
                    }
                    if status == .classifying {
                        self.statusMessage = "Classifying ads with \(classificationLabel)..."
                    }
                },
                transcriptionProgressDidChange: { currentChunk, totalChunks in
                    let progress = totalChunks > 0 ? Double(currentChunk) / Double(totalChunks) : 0
                    self.setTranscriptionProgress(progress, for: episode.id)
                    self.statusMessage = "Transcribing with \(transcriptionLabel): chunk \(currentChunk) of \(totalChunks)..."
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
            statusMessage = "Classifying ads with \(classificationLabel)..."

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
        guard let playing = await playback.currentEpisode,
              let episode = self.episode(withID: playing.id),
              episode.download?.state == .downloaded,
              !busyEpisodeIDs.contains(episode.id) else { return }
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
            statusMessage = "Settings saved."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func episode(withID id: UUID) -> PodcastEpisode? {
        allEpisodes.first { $0.id == id }
    }

    func transcriptionProgress(for episodeID: UUID) -> Double? {
        transcriptionProgressByEpisodeID[episodeID]
    }

    private func updateEpisode(_ episodeID: UUID, persist: Bool = true, mutate: (inout PodcastEpisode) -> Void) async {
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
            classificationProvider = openAIProvider
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
        if !force, episode.referenceTranscript != nil { return }
        if episode.transcriptSources == nil || force,
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
        let sources = TranscriptSource.preferredSources(from: self.episode(withID: episode.id)?.transcriptSources ?? [])
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

    private func persistFeeds() async throws {
        try await store.saveFeeds(feeds)
    }
}

private struct AdDetectionContext {
    var adDetectionService: AdDetectionService
    var providerMetadata: AIProviderMetadata
}
