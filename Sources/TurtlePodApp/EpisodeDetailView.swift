import SwiftUI
import TurtlePodCore

struct EpisodeDetailView: View {
    @EnvironmentObject private var model: TurtlePodModel
    @Environment(\.appTheme) private var theme
    let episodeID: UUID

    private var episode: PodcastEpisode? {
        model.episode(withID: episodeID)
    }

    var body: some View {
        Group {
            if let episode {
                ZStack {
                    theme.backgroundPrimary.ignoresSafeArea()

                    ScrollView {
                        VStack(spacing: 20) {
                            // Header
                            VStack(spacing: 14) {
                                HStack(alignment: .top, spacing: 14) {
                                    ArtworkView(url: episode.artworkURL, size: 100)

                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(episode.title)
                                            .font(.title3.weight(.semibold))
                                            .foregroundStyle(theme.textPrimary)
                                        if let publishedAt = episode.publishedAt {
                                            Text(publishedAt, style: .date)
                                                .font(.subheadline)
                                                .foregroundStyle(theme.textSecondary)
                                        }
                                        if let duration = episode.duration {
                                            HStack(spacing: 4) {
                                                Image(systemName: "clock")
                                                    .font(.caption)
                                                Text(duration.formattedDuration)
                                            }
                                            .font(.subheadline)
                                            .foregroundStyle(theme.amberMuted)
                                        }
                                    }
                                    Spacer()
                                }

                                Text(EpisodeDescriptionCleaner.clean(episode.description))
                                    .font(.subheadline)
                                    .foregroundStyle(theme.textSecondary)
                                    .lineSpacing(3)
                            }
                            .turtleCard()

                            // Playback
                            VStack(alignment: .leading, spacing: 12) {
                                SectionHeader(title: "Playback", icon: "play.circle")

                                Button {
                                    Task { await model.play(episode) }
                                } label: {
                                    HStack {
                                        Image(systemName: "play.fill")
                                        Text("Play Offline")
                                            .font(.subheadline.weight(.semibold))
                                        Spacer()
                                    }
                                    .foregroundStyle(episode.download?.state == .downloaded ? theme.backgroundPrimary : theme.textTertiary)
                                    .padding(12)
                                    .background(episode.download?.state == .downloaded ? theme.amber : theme.backgroundElevated)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                                .disabled(episode.download?.state != .downloaded)

                                HStack {
                                    Text("Auto-skip ads")
                                        .font(.subheadline)
                                        .foregroundStyle(theme.textPrimary)
                                    Spacer()
                                    Toggle("", isOn: Binding(
                                        get: { episode.autoSkipEnabled },
                                        set: { enabled in Task { await model.setEpisodeAutoSkip(enabled, episodeID: episode.id) } }
                                    ))
                                    .tint(theme.teal)
                                }
                                .padding(.horizontal, 4)
                            }
                            .turtleCard()

                            // Download
                            VStack(alignment: .leading, spacing: 12) {
                                SectionHeader(title: "Download", icon: "arrow.down.circle")

                                DownloadStatusRow(episode: episode)

                                if episode.download?.state == .downloaded {
                                    Button(role: .destructive) {
                                        Task { await model.deleteDownload(episode) }
                                    } label: {
                                        HStack {
                                            Image(systemName: "trash")
                                            Text("Delete Download")
                                                .font(.subheadline.weight(.medium))
                                        }
                                        .foregroundStyle(theme.destructive)
                                        .padding(10)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(theme.destructive.opacity(0.1))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(model.busyEpisodeIDs.contains(episode.id))
                                } else {
                                    Button {
                                        Task { await model.download(episode) }
                                    } label: {
                                        HStack {
                                            Image(systemName: "arrow.down.circle")
                                            Text("Download Episode")
                                                .font(.subheadline.weight(.medium))
                                        }
                                        .foregroundStyle(theme.amber)
                                        .padding(10)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(theme.amber.opacity(0.1))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(model.busyEpisodeIDs.contains(episode.id))
                                }
                            }
                            .turtleCard()

                            ReferenceTranscriptView(episode: episode)

                            // AI Analysis
                            VStack(alignment: .leading, spacing: 12) {
                                SectionHeader(title: "AI Analysis", icon: "sparkles")

                                AnalysisStatusRow(
                                    analysis: episode.analysis,
                                    transcriptionLabel: transcriptionStatusLabel(for: episode),
                                    classificationLabel: classificationStatusLabel(for: episode),
                                    transcriptionProgress: model.transcriptionProgress(for: episode.id)
                                )

                                Button {
                                    Task { await model.analyze(episode) }
                                } label: {
                                    HStack {
                                        Image(systemName: "sparkles")
                                        Text("Analyze Download")
                                            .font(.subheadline.weight(.medium))
                                    }
                                    .foregroundStyle(
                                        episode.download?.state == .downloaded && episode.analysis.status != .transcribing && episode.analysis.status != .classifying
                                        ? theme.teal : theme.textTertiary
                                    )
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(theme.teal.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                                .disabled(episode.download?.state != .downloaded || model.busyEpisodeIDs.contains(episode.id))

                                if !episode.analysis.transcript.isEmpty {
                                    Button {
                                        Task { await model.reanalyzeAds(episode) }
                                    } label: {
                                        HStack {
                                            Image(systemName: "arrow.clockwise")
                                            Text("Re-analyze Ads")
                                                .font(.subheadline.weight(.medium))
                                        }
                                        .foregroundStyle(
                                            episode.analysis.status != .transcribing && episode.analysis.status != .classifying
                                            ? theme.amber : theme.textTertiary
                                        )
                                        .padding(10)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(theme.amber.opacity(0.1))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(model.busyEpisodeIDs.contains(episode.id))
                                }

                                if !episode.analysis.adSegments.isEmpty {
                                    VStack(spacing: 8) {
                                        ForEach(episode.analysis.adSegments) { segment in
                                            HStack {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text("\(segment.start.formattedDuration) – \(segment.end.formattedDuration)")
                                                        .font(.subheadline.weight(.medium).monospacedDigit())
                                                        .foregroundStyle(theme.textPrimary)
                                                    Text(segment.reason)
                                                        .font(.caption)
                                                        .foregroundStyle(theme.textSecondary)
                                                }
                                                Spacer()
                                                Text("\(Int(segment.confidence * 100))%")
                                                    .font(.caption.weight(.semibold).monospacedDigit())
                                                    .foregroundStyle(theme.teal)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 3)
                                                    .background(theme.teal.opacity(0.12))
                                                    .clipShape(Capsule())
                                            }
                                            .padding(10)
                                            .background(theme.backgroundElevated)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                        }
                                    }
                                }
                            }
                            .turtleCard()
                        }
                        .padding(16)
                    }
                }
                .background(theme.backgroundPrimary)
                .navigationTitle("Episode")
                .turtleNavBarBackground(theme)
            } else {
                ZStack {
                    theme.backgroundPrimary.ignoresSafeArea()
                    VStack(spacing: 12) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(theme.textTertiary)
                        Text("Episode Not Found")
                            .foregroundStyle(theme.textSecondary)
                    }
                }
            }
        }
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
        }
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
        case "apple-foundation-models":
            "Apple On-Device"
        default:
            provider
        }
    }
}

private struct SectionHeader: View {
    @Environment(\.appTheme) private var theme
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(theme.amberMuted)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.textTertiary)
                .textCase(.uppercase)
                .tracking(0.8)
        }
    }
}

private struct DownloadStatusRow: View {
    @Environment(\.appTheme) private var theme
    let episode: PodcastEpisode

    var body: some View {
        switch episode.download?.state ?? .notDownloaded {
        case .notDownloaded:
            HStack(spacing: 8) {
                Image(systemName: "icloud")
                    .foregroundStyle(theme.textTertiary)
                Text("Not downloaded")
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
            }
        case .downloading:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(theme.amber)
                    Text("Downloading")
                        .font(.subheadline)
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    Text((episode.download?.progress ?? 0).formattedPercentage)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(theme.amber)
                }
                AmberProgressBar(value: episode.download?.progress ?? 0)
            }
        case .downloaded:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(theme.success)
                Text("Available offline")
                    .font(.subheadline)
                    .foregroundStyle(theme.textPrimary)
            }
        case .failed:
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(theme.destructive)
                Text(episode.download?.errorMessage ?? "Download failed")
                    .font(.subheadline)
                    .foregroundStyle(theme.destructive)
            }
        }
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
