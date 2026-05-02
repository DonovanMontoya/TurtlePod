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
                await model.evaluateAutoSkip()
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
        max(episode.duration ?? max(episode.analysis.adSegments.map(\.end).max() ?? 1, currentTime + 1), 1)
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

                PlaybackScrubber(
                    currentTime: currentTime,
                    duration: duration,
                    adSegments: episode.analysis.adSegments,
                    trackHeight: 5,
                    markerHeight: 5,
                    thumbSize: 12
                ) { seekTime in
                    Task { await model.seek(to: seekTime) }
                }
                .frame(height: 14)
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

struct PlaybackScrubber: View {
    let currentTime: TimeInterval
    let duration: TimeInterval
    var adSegments: [AdSegment] = []
    var trackHeight: CGFloat = 8
    var markerHeight: CGFloat = 18
    var thumbSize: CGFloat = 16
    var onSeek: (TimeInterval) -> Void

    @State private var scrubTime: TimeInterval?

    private var effectiveDuration: TimeInterval {
        max(duration, 1)
    }

    private var displayTime: TimeInterval {
        scrubTime ?? currentTime
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let progress = clampedProgress(for: displayTime)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                    .frame(height: trackHeight)

                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: width * progress, height: trackHeight)

                ForEach(adSegments) { segment in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.orange)
                        .frame(
                            width: max(3, width * clampedSegmentProgress(segment)),
                            height: markerHeight
                        )
                        .offset(x: width * clampedProgress(for: segment.start))
                }

                Circle()
                    .fill(Color.accentColor)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(radius: 2, y: 1)
                    .offset(x: min(max(width * progress - thumbSize / 2, 0), width - thumbSize))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        scrubTime = time(for: value.location.x, width: width)
                    }
                    .onEnded { value in
                        let seekTime = time(for: value.location.x, width: width)
                        scrubTime = nil
                        onSeek(seekTime)
                    }
            )
        }
        .accessibilityLabel("Playback timeline")
        .accessibilityValue("\(displayTime.formattedDuration) of \(effectiveDuration.formattedDuration)")
    }

    private func time(for xPosition: CGFloat, width: CGFloat) -> TimeInterval {
        let progress = min(max(xPosition / max(width, 1), 0), 1)
        return TimeInterval(progress) * effectiveDuration
    }

    private func clampedProgress(for time: TimeInterval) -> CGFloat {
        CGFloat(min(max(time / effectiveDuration, 0), 1))
    }

    private func clampedSegmentProgress(_ segment: AdSegment) -> CGFloat {
        let start = min(max(segment.start, 0), effectiveDuration)
        let end = min(max(segment.end, start), effectiveDuration)
        return CGFloat((end - start) / effectiveDuration)
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
