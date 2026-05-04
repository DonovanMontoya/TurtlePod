import SwiftUI
import TurtlePodCore

struct RootView: View {
    @EnvironmentObject private var model: TurtlePodModel
    @Environment(\.appTheme) private var theme
    @State private var selectedTab: RootTab = .library
    @State private var currentEpisode: PodcastEpisode?
    @State private var currentTime: TimeInterval = 0
    @State private var isPlaying = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                LibraryView()
            }
            .tabItem {
                Label("Library", systemImage: "books.vertical")
            }
            .tag(RootTab.library)

            NavigationStack {
                DownloadsView()
            }
            .tabItem {
                Label("Downloads", systemImage: "arrow.down.circle")
            }
            .tag(RootTab.downloads)

            NavigationStack {
                PlayerView()
            }
            .tabItem {
                Label("Player", systemImage: "play.circle")
            }
            .tag(RootTab.player)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(RootTab.settings)
        }
        .tint(theme.amber)
        .safeAreaInset(edge: .bottom) {
            let shouldShowMiniPlayer = selectedTab != .player && currentEpisode != nil

            if model.activeSkipEvent != nil || shouldShowMiniPlayer {
                VStack(spacing: 8) {
                    if let event = model.activeSkipEvent {
                        UndoSkipBanner(event: event)
                    }
                    if shouldShowMiniPlayer, let currentEpisode {
                        MiniPlayerBar(
                            episode: currentEpisode,
                            currentTime: currentTime,
                            isPlaying: isPlaying
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, shouldShowMiniPlayer ? 64 : 8)
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

private enum RootTab: Hashable {
    case library
    case downloads
    case player
    case settings
}

private struct MiniPlayerBar: View {
    @EnvironmentObject private var model: TurtlePodModel
    @Environment(\.appTheme) private var theme
    let episode: PodcastEpisode
    let currentTime: TimeInterval
    let isPlaying: Bool

    private var duration: TimeInterval {
        max(episode.duration ?? max(episode.analysis.adSegments.map(\.end).max() ?? 1, currentTime + 1), 1)
    }

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(url: episode.artworkURL, size: 44)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(episode.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text(currentTime.formattedDuration)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(theme.textSecondary)
                }

                PlaybackScrubber(
                    currentTime: currentTime,
                    duration: duration,
                    adSegments: episode.analysis.adSegments,
                    trackHeight: 4,
                    markerHeight: 4,
                    thumbSize: 10,
                    trackColor: theme.backgroundElevated,
                    fillColor: theme.amber,
                    markerColor: theme.teal
                ) { seekTime in
                    Task { await model.seek(to: seekTime) }
                }
                .frame(height: 14)
            }

            Button {
                Task { await model.togglePlayback() }
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .foregroundStyle(theme.amber)
                    .frame(width: 38, height: 38)
                    .background(theme.amber.opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
        }
        .padding(12)
        .background(theme.backgroundCard.opacity(0.95))
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: TurtleTheme.miniPlayerCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: TurtleTheme.miniPlayerCornerRadius)
                .strokeBorder(theme.amberMuted.opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.4), radius: 12, y: 5)
    }
}

struct PlaybackScrubber: View {
    let currentTime: TimeInterval
    let duration: TimeInterval
    var adSegments: [AdSegment] = []
    var trackHeight: CGFloat = 8
    var markerHeight: CGFloat = 18
    var thumbSize: CGFloat = 16
    var trackColor: Color = Color(white: 0.3, opacity: 0.4)
    var fillColor: Color = .accentColor
    var markerColor: Color = .orange
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
                    .fill(trackColor)
                    .frame(height: trackHeight)

                Capsule()
                    .fill(fillColor)
                    .frame(width: width * progress, height: trackHeight)

                ForEach(adSegments) { segment in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(markerColor)
                        .frame(
                            width: max(3, width * clampedSegmentProgress(segment)),
                            height: markerHeight
                        )
                        .offset(x: width * clampedProgress(for: segment.start))
                }

                Circle()
                    .fill(fillColor)
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
    @Environment(\.appTheme) private var theme
    let event: SkipEvent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "forward.end")
                .foregroundStyle(theme.teal)
            Text("Skipped ad")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.textPrimary)
            Spacer()
            Button("Undo") {
                Task { await model.undoLastSkip() }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(theme.backgroundPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(theme.teal)
            .clipShape(Capsule())
        }
        .padding(12)
        .background(theme.backgroundCard.opacity(0.95))
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: TurtleTheme.miniPlayerCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: TurtleTheme.miniPlayerCornerRadius)
                .strokeBorder(theme.tealMuted.opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.4), radius: 12, y: 5)
    }
}
