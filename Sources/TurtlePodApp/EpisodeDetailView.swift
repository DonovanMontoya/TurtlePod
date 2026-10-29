import SwiftUI
import TurtlePodCore

struct EpisodeDetailView: View {
    @EnvironmentObject private var model: TurtlePodModel
    @Environment(\.appTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let episodeID: UUID
    @State private var isShowingReference = false

    private var episode: PodcastEpisode? {
        model.episode(withID: episodeID)
    }

    var body: some View {
        if let episode {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header(episode)
                    actionBar(episode)
                    if !episode.description.isEmpty {
                        ShowNotesView(episode: episode)
                    }
                    adSkipping(episode)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .background(theme.backgroundPrimary)
            .navigationTitle("")
            .inlineNavigationTitle()
            .turtleNavBarBackground(theme)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        EpisodeMenuItems(episode: episode)
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
        } else {
            EmptyStateView(symbol: "questionmark.circle", title: "Episode not found", message: "It may have been removed from the feed.")
                .frame(maxHeight: .infinity)
                .background(theme.backgroundPrimary)
        }
    }

    // MARK: Header

    private func header(_ episode: PodcastEpisode) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
        return layout {
            ArtworkView(url: episode.artworkURL, size: 104)
                .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
            VStack(alignment: .leading, spacing: 6) {
                if let podcast = model.feed(withID: episode.feedID) {
                    NavigationLink(value: Route.podcast(podcast.id)) {
                        Text(podcast.title)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(theme.amber)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                    }
                    .buttonStyle(.plain)
                }
                Text(episode.title)
                    .font(.title3.weight(.bold))
                    .fontDesign(.rounded)
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Text(metadataLine(episode))
                    .font(.footnote)
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }

    private func metadataLine(_ episode: PodcastEpisode) -> String {
        var parts: [String] = []
        if let date = episode.publishedAt {
            parts.append(date.formatted(date: .abbreviated, time: .omitted))
        }
        if let duration = model.duration(for: episode) {
            parts.append(duration.shortDuration)
        }
        if let season = episode.seasonNumber, let number = episode.episodeNumber {
            parts.append("S\(season) E\(number)")
        } else if let number = episode.episodeNumber {
            parts.append("Episode \(number)")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: Actions

    private func actionBar(_ episode: PodcastEpisode) -> some View {
        let state = model.state(for: episode.id)
        let isCurrent = model.player.episodeID == episode.id
        let isPlaying = isCurrent && model.player.isPlaying
        let queued = model.library.upNext.contains(episode.id)

        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
        return VStack(alignment: .leading, spacing: 12) {
            layout {
                Button {
                    Task {
                        if isPlaying { await model.pause() } else { await model.play(episode) }
                    }
                } label: {
                    Label(playLabel(episode, state: state, isCurrent: isCurrent, isPlaying: isPlaying),
                          systemImage: isPlaying ? "pause.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())

                HStack(spacing: 10) {
                DownloadControl(episode: episode)

                Menu {
                    if queued {
                        Button {
                            model.removeFromUpNext(episode.id)
                        } label: {
                            Label("Remove from Up Next", systemImage: "text.badge.minus")
                        }
                    } else {
                        Button {
                            model.playNext(episode)
                        } label: {
                            Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                        }
                        Button {
                            model.playLast(episode)
                        } label: {
                            Label("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward")
                        }
                    }
                } label: {
                    Image(systemName: queued ? "text.badge.checkmark" : "text.badge.plus")
                        .font(.title3)
                        .foregroundStyle(queued ? theme.amber : theme.textSecondary)
                        .frame(width: 44, height: 44)
                }
                .disabled(isCurrent)
                .accessibilityLabel(queued ? "In Up Next" : "Add to Up Next")

                Button {
                    model.toggleStar(episode)
                } label: {
                    Image(systemName: state.isStarred ? "star.fill" : "star")
                        .font(.title3)
                        .foregroundStyle(state.isStarred ? theme.amber : theme.textSecondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(state.isStarred ? "Unstar" : "Star")
                }
            }

            if let progress = model.progress(for: episode), !state.isPlayed {
                ProgressView(value: progress)
                    .tint(theme.amber)
                    .accessibilityLabel("Listened")
            }
            if episode.download?.state == .failed, let message = episode.download?.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(theme.destructive)
            }
        }
    }

    private func playLabel(_ episode: PodcastEpisode, state: EpisodeUserState, isCurrent: Bool, isPlaying: Bool) -> String {
        if isPlaying { return "Pause" }
        if state.isPlayed { return "Play Again" }
        let position = model.position(for: episode)
        if position >= 1, let duration = model.duration(for: episode) {
            return "Resume, \(max(duration - position, 0).shortDuration) left"
        }
        if let duration = model.duration(for: episode) {
            return "Play, \(duration.shortDuration)"
        }
        return "Play"
    }

    // MARK: Ad skipping

    private func adSkipping(_ episode: PodcastEpisode) -> some View {
        let isDownloaded = episode.download?.state == .downloaded
        let isBusy = model.busyEpisodeIDs.contains(episode.id)
        let isRunning = episode.analysis.status == .transcribing || episode.analysis.status == .classifying

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Ad skipping")
                    .font(.headline)
                    .fontDesign(.rounded)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
            }

            if !episode.analysis.adSegments.isEmpty {
                Toggle(isOn: Binding(
                    get: { episode.autoSkipEnabled },
                    set: { enabled in Task { await model.setEpisodeAutoSkip(enabled, episodeID: episode.id) } }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Skip ads in this episode")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(theme.textPrimary)
                        if !model.settings.autoSkipEnabled {
                            Text("Ad skipping is off in Settings.")
                                .font(.caption)
                                .foregroundStyle(theme.textSecondary)
                        }
                    }
                }
                .tint(theme.teal)
                .disabled(!model.settings.autoSkipEnabled)
            }

            if !model.settings.aiAnalysisEnabled {
                Text("Turn on ad analysis in Settings to find and skip ads in downloaded episodes.")
                    .font(.footnote)
                    .foregroundStyle(theme.textSecondary)
            } else if !isDownloaded {
                Text("Download this episode to analyze it for ads.")
                    .font(.footnote)
                    .foregroundStyle(theme.textSecondary)
            } else {
                AnalysisStatusRow(
                    analysis: episode.analysis,
                    transcriptionLabel: transcriptionStatusLabel(for: episode),
                    classificationLabel: classificationStatusLabel(for: episode),
                    transcriptionProgress: model.transcriptionProgress(for: episode.id)
                )
            }

            if model.settings.aiAnalysisEnabled, isDownloaded {
                HStack(spacing: 10) {
                    Button {
                        Task { await model.analyze(episode) }
                    } label: {
                        Label(episode.analysis.status == .complete ? "Analyze Again" : "Find Ads", systemImage: "sparkles")
                    }
                    .buttonStyle(SecondaryButtonStyle(tint: theme.teal))
                    .disabled(isBusy || isRunning)

                    if !episode.analysis.transcript.isEmpty {
                        Button {
                            Task { await model.reanalyzeAds(episode) }
                        } label: {
                            Label("Re-check Ads", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(SecondaryButtonStyle(tint: theme.textSecondary))
                        .disabled(isBusy || isRunning)
                    }
                }
            }

            if !episode.analysis.adSegments.isEmpty {
                VStack(spacing: 0) {
                    ForEach(episode.analysis.adSegments) { segment in
                        AdSegmentRow(episode: episode, segment: segment, threshold: model.settings.adSkipConfidenceThreshold)
                        if segment.id != episode.analysis.adSegments.last?.id {
                            Divider().overlay(theme.textTertiary.opacity(0.25))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .background(theme.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            DisclosureGroup(isExpanded: $isShowingReference) {
                ReferenceTranscriptView(episode: episode)
                    .padding(.top, 8)
            } label: {
                Label(episode.referenceTranscript == nil ? "Reference transcript" : "Reference transcript saved",
                      systemImage: "text.alignleft")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.textSecondary)
            }
            .tint(theme.textSecondary)
        }
        .padding(16)
        .background(theme.backgroundCard, in: RoundedRectangle(cornerRadius: TurtleTheme.cardCornerRadius, style: .continuous))
    }

    private func transcriptionStatusLabel(for episode: PodcastEpisode) -> String {
        if let metadata = episode.analysis.providerMetadata {
            return analysisStatusLabel(provider: metadata.transcriptionProvider, model: metadata.transcriptionModel)
        }

        switch model.settings.aiTranscriptionProvider {
        case .openAI:
            return analysisStatusLabel(provider: "openai", model: "whisper-1")
        case .localWhisper:
            return analysisStatusLabel(provider: "local-whisper", model: "whisper-\(model.settings.whisperModelSize.rawValue)")
        case .appleSpeech:
            return analysisStatusLabel(provider: "apple-speech", model: "speech-transcriber")
        }
    }

    private func classificationStatusLabel(for episode: PodcastEpisode) -> String {
        if let metadata = episode.analysis.providerMetadata {
            return analysisStatusLabel(provider: metadata.classificationProvider, model: metadata.classificationModel)
        }

        switch model.settings.aiClassificationProvider {
        case .openAI:
            return analysisStatusLabel(provider: "openai", model: "gpt-4o-mini")
        case .appleFoundationModels:
            return analysisStatusLabel(provider: "apple-foundation-models", model: "system-language-model")
        case .jevTypeSafe:
            return analysisStatusLabel(provider: "jev-typesafe", model: "jev-1.13.0")
        case .jevOpenRouter:
            return analysisStatusLabel(provider: "jev-openrouter", model: "typesafe/jev-1.13")
        }
    }

    /// Model identifiers mean little to listeners; Settings shows them for anyone who cares.
    private func analysisStatusLabel(provider: String, model: String) -> String {
        analysisProviderDisplayName(provider)
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
}

private struct AdSegmentRow: View {
    @EnvironmentObject private var model: TurtlePodModel
    @Environment(\.appTheme) private var theme
    let episode: PodcastEpisode
    let segment: AdSegment
    let threshold: Double

    var body: some View {
        let willSkip = segment.confidence >= threshold
        Button {
            Task {
                if model.player.episodeID == episode.id {
                    await model.seek(to: segment.start)
                } else {
                    await model.startPlayback(episode, resumeAt: segment.start, autoplay: true)
                }
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(willSkip ? theme.teal : .clear)
                    .strokeBorder(theme.teal, lineWidth: willSkip ? 0 : 1)
                    .frame(width: 4, height: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(segment.start.formattedDuration) to \(segment.end.formattedDuration)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(theme.textPrimary)
                    if !segment.reason.isEmpty {
                        Text(segment.reason)
                            .font(.caption)
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(segment.confidence.formatted(.percent.precision(.fractionLength(0))))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(willSkip ? theme.teal : theme.textSecondary)
                    Text(willSkip ? "Skips" : "Plays")
                        .font(.caption2)
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Plays from the start of this ad")
    }
}

/// Episode notes with tappable links and timestamps.
private struct ShowNotesView: View {
    @EnvironmentObject private var model: TurtlePodModel
    @Environment(\.appTheme) private var theme
    let episode: PodcastEpisode
    @State private var isExpanded = false

    var body: some View {
        let notes = ShowNotesFormatter.attributed(episode.description, linkColor: theme.amber)
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.headline)
                .fontDesign(.rounded)
                .foregroundStyle(theme.textPrimary)
            Text(notes)
                .font(.subheadline)
                .foregroundStyle(theme.textSecondary)
                .lineSpacing(3)
                .lineLimit(isExpanded ? nil : 8)
                .textSelection(.enabled)
                .environment(\.openURL, OpenURLAction { url in
                    guard let seconds = ShowNotesFormatter.seconds(fromSeekURL: url) else { return .systemAction }
                    Task {
                        if model.player.episodeID == episode.id {
                            await model.seek(to: seconds)
                        } else {
                            await model.startPlayback(episode, resumeAt: seconds, autoplay: true)
                        }
                    }
                    return .handled
                })
            if episode.description.count > 400 {
                Button(isExpanded ? "Show less" : "Show more") {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(theme.amber)
                .buttonStyle(.plain)
            }
        }
    }
}

enum ShowNotesFormatter {
    static let seekScheme = "turtlepod-seek"

    static func attributed(_ text: String, linkColor: Color) -> AttributedString {
        var result = AttributedString(text)
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            for match in detector.matches(in: text, range: fullRange) {
                guard let url = match.url, let range = Range(match.range, in: result) else { continue }
                result[range].link = url
                result[range].foregroundColor = linkColor
            }
        }

        let pattern = #"(?<![\d:])(?:(\d{1,2}):)?([0-5]?\d):([0-5]\d)(?![\d:])"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            for match in regex.matches(in: text, range: fullRange) {
                guard let range = Range(match.range, in: result), result[range].link == nil else { continue }
                let hours = match.range(at: 1).location == NSNotFound ? 0 : Int(nsText.substring(with: match.range(at: 1))) ?? 0
                let minutes = Int(nsText.substring(with: match.range(at: 2))) ?? 0
                let seconds = Int(nsText.substring(with: match.range(at: 3))) ?? 0
                let total = hours * 3600 + minutes * 60 + seconds
                result[range].link = URL(string: "\(seekScheme)://\(total)")
                result[range].foregroundColor = linkColor
            }
        }
        return result
    }

    static func seconds(fromSeekURL url: URL) -> TimeInterval? {
        guard url.scheme == seekScheme, let host = url.host(), let value = Int(host) else { return nil }
        return TimeInterval(value)
    }
}

private struct AnalysisStatusRow: View {
    @Environment(\.appTheme) private var theme
    let analysis: EpisodeAnalysis
    let transcriptionLabel: String
    let classificationLabel: String
    let transcriptionProgress: Double?

    var body: some View {
        switch analysis.status {
        case .notStarted:
            HStack(spacing: 8) {
                Image(systemName: "circle")
                    .foregroundStyle(theme.textTertiary)
                Text("Not analyzed")
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
            }
        case .queued:
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .foregroundStyle(theme.amberMuted)
                Text("Queued")
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
            }
        case .transcribing:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "waveform")
                        .foregroundStyle(theme.teal)
                    Text("Transcribing with \(transcriptionLabel)")
                        .font(.subheadline)
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(2)
                    Spacer()
                    Text((transcriptionProgress ?? 0).formattedPercentage)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(theme.teal)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(theme.backgroundElevated)
                            .frame(height: 4)
                        Capsule()
                            .fill(theme.teal)
                            .frame(width: proxy.size.width * min(max(transcriptionProgress ?? 0, 0), 1), height: 4)
                            .shadow(color: theme.teal.opacity(0.3), radius: 4, y: 0)
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                }
                .frame(height: 4)
            }
        case .classifying:
            HStack(spacing: 8) {
                ProgressView()
                    .tint(theme.teal)
                    .scaleEffect(0.8)
                Text("Classifying with \(classificationLabel)")
                    .font(.subheadline)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(2)
            }
        case .complete:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(theme.teal)
                Text("Complete")
                    .font(.subheadline)
                    .foregroundStyle(theme.textPrimary)
            }
        case .failed:
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(theme.destructive)
                Text(analysis.errorMessage ?? "Analysis failed")
                    .font(.subheadline)
                    .foregroundStyle(theme.destructive)
            }
        }
    }
}

private extension Double {
    var formattedPercentage: String {
        "\(Int((self * 100).rounded()))%"
    }
}

extension TimeInterval {
    var formattedDuration: String {
        let totalSeconds = max(0, Int(self.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
