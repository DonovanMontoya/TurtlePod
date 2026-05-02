import SwiftUI
import TurtlePodCore

struct RootView: View {
    @EnvironmentObject private var model: TurtlePodModel
    @State private var currentEpisode: PodcastEpisode?
    @State private var currentTime: TimeInterval = 0
    @State private var isPlaying = false

    var body: some View {
        TabView {
            NavigationStack {
                LibraryView()
            }
            .tabItem {
                Label("Library", systemImage: "books.vertical")
            }

            NavigationStack {
                DownloadsView()
            }
            .tabItem {
                Label("Downloads", systemImage: "arrow.down.circle")
            }

            NavigationStack {
                PlayerView()
            }
            .tabItem {
                Label("Player", systemImage: "play.circle")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if model.activeSkipEvent != nil || currentEpisode != nil {
                VStack(spacing: 8) {
                    if let event = model.activeSkipEvent {
                        UndoSkipBanner(event: event)
                    }
                    if let currentEpisode {
                        MiniPlayerBar(
                            episode: currentEpisode,
                            currentTime: currentTime,
                            isPlaying: isPlaying
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, currentEpisode == nil ? 8 : 64)
            }
        }
        .task {
            while !Task.isCancelled {
                currentEpisode = await model.playback.currentEpisode
                currentTime = await model.playback.currentTime
                isPlaying = await model.playback.isPlaying
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }
}

private struct MiniPlayerBar: View {
    @EnvironmentObject private var model: TurtlePodModel
    let episode: PodcastEpisode
    let currentTime: TimeInterval
    let isPlaying: Bool

    private var duration: TimeInterval {
        max(episode.duration ?? currentTime, 1)
    }

    var body: some View {
        HStack(spacing: 10) {
            AsyncImage(url: episode.artworkURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "waveform")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 38, height: 38)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(episode.title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(currentTime.formattedDuration)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: min(currentTime / duration, 1))
                    .progressViewStyle(.linear)
            }

            Button {
                Task { await model.togglePlayback() }
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.headline)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
        }
        .padding(10)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 8, y: 3)
    }
}

private struct UndoSkipBanner: View {
    @EnvironmentObject private var model: TurtlePodModel
    let event: SkipEvent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "forward.end")
            Text("Skipped ad")
                .font(.callout.weight(.semibold))
            Spacer()
            Button("Undo") {
                Task { await model.undoLastSkip() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 8, y: 3)
    }
}
