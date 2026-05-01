import SwiftUI
import TurtlePodCore

struct EpisodeDetailView: View {
    @EnvironmentObject private var model: TurtlePodModel
    let episodeID: UUID

    private var episode: PodcastEpisode? {
        model.episode(withID: episodeID)
    }

    var body: some View {
        Group {
            if let episode {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top, spacing: 14) {
                                AsyncImage(url: episode.artworkURL) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    Image(systemName: "waveform")
                                        .font(.largeTitle)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(width: 88, height: 88)
                                .background(.quaternary)
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                                VStack(alignment: .leading, spacing: 6) {
                                    Text(episode.title)
                                        .font(.title3.weight(.semibold))
                                    if let publishedAt = episode.publishedAt {
                                        Text(publishedAt, style: .date)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    if let duration = episode.duration {
                                        Text(duration.formattedDuration)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }

                            Text(episode.description)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("Playback") {
                        Button {
                            Task { await model.play(episode) }
                        } label: {
                            Label("Play Offline", systemImage: "play.fill")
                        }
                        .disabled(episode.download?.state != .downloaded)

                        Toggle("Auto-skip for this episode", isOn: Binding(
                            get: { episode.autoSkipEnabled },
                            set: { enabled in Task { await model.setEpisodeAutoSkip(enabled, episodeID: episode.id) } }
                        ))
                    }

                    Section("Download") {
                        DownloadStatusRow(episode: episode)
                        if episode.download?.state == .downloaded {
                            Button(role: .destructive) {
                                Task { await model.deleteDownload(episode) }
                            } label: {
                                Label("Delete Download", systemImage: "trash")
                            }
                        } else {
                            Button {
                                Task { await model.download(episode) }
                            } label: {
                                Label("Download Episode", systemImage: "arrow.down.circle")
                            }
                            .disabled(episode.download?.state == .downloading)
                        }
                    }

                    Section("AI Analysis") {
                        AnalysisStatusRow(analysis: episode.analysis)
                        Button {
                            Task { await model.analyze(episode) }
                        } label: {
                            Label("Analyze Download", systemImage: "sparkles")
                        }
                        .disabled(episode.download?.state != .downloaded || episode.analysis.status == .transcribing || episode.analysis.status == .classifying)

                        ForEach(episode.analysis.adSegments) { segment in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(segment.start.formattedDuration) - \(segment.end.formattedDuration)")
                                    .font(.callout.weight(.medium))
                                Text("\(Int(segment.confidence * 100))% confidence - \(segment.reason)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .navigationTitle("Episode")
            } else {
                ContentUnavailableView("Episode Not Found", systemImage: "questionmark.circle")
            }
        }
    }
}

private struct DownloadStatusRow: View {
    let episode: PodcastEpisode

    var body: some View {
        switch episode.download?.state ?? .notDownloaded {
        case .notDownloaded:
            Label("Not downloaded", systemImage: "icloud")
        case .downloading:
            ProgressView(value: episode.download?.progress ?? 0) {
                Text("Downloading")
            }
        case .downloaded:
            Label("Available offline", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Label(episode.download?.errorMessage ?? "Download failed", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
    }
}

private struct AnalysisStatusRow: View {
    let analysis: EpisodeAnalysis

    var body: some View {
        switch analysis.status {
        case .notStarted:
            Label("Not analyzed", systemImage: "circle")
        case .queued:
            Label("Queued", systemImage: "clock")
        case .transcribing:
            ProgressView("Transcribing")
        case .classifying:
            ProgressView("Classifying")
        case .complete:
            Label("Complete", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
        case .failed:
            Label(analysis.errorMessage ?? "Analysis failed", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
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
