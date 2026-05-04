import SwiftUI
import TurtlePodCore

struct PlayerView: View {
    @EnvironmentObject private var model: TurtlePodModel
    @Environment(\.appTheme) private var theme
    @State private var currentEpisode: PodcastEpisode?
    @State private var currentTime: TimeInterval = 0
    @State private var isPlaying = false

    var body: some View {
        ZStack {
            theme.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 32) {
                if let episode = currentEpisode {
                    Spacer()

                    ArtworkView(url: episode.artworkURL, size: 260)
                        .shadow(color: theme.amber.opacity(0.08), radius: 40, y: 10)

                    VStack(spacing: 8) {
                        Text(episode.title)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(theme.textPrimary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                        Text(currentTime.formattedDuration)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(theme.textSecondary)
                    }
                    .padding(.horizontal, 24)

                    PlaybackScrubber(
                        currentTime: currentTime,
                        duration: max(episode.duration ?? max(episode.analysis.adSegments.map(\.end).max() ?? 1, currentTime + 1), 1),
                        adSegments: episode.analysis.adSegments,
                        trackHeight: 6,
                        markerHeight: 20,
                        thumbSize: 14,
                        trackColor: theme.backgroundElevated,
                        fillColor: theme.amber,
                        markerColor: theme.teal.opacity(0.7)
                    ) { seekTime in
                        Task { await model.seek(to: seekTime) }
                    }
                    .frame(height: 40)
                    .padding(.horizontal, 24)

                    HStack(spacing: 36) {
                        Button {
                            Task { await model.seek(to: max(0, currentTime - 15)) }
                        } label: {
                            Image(systemName: "gobackward.15")
                                .font(.title2)
                                .foregroundStyle(theme.textSecondary)
                        }

                        Button {
                            Task { await model.togglePlayback() }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(theme.amber)
                                    .frame(width: 72, height: 72)
                                    .shadow(color: theme.amber.opacity(0.3), radius: 12, y: 4)
                                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                    .font(.title)
                                    .foregroundStyle(theme.backgroundPrimary)
                            }
                        }

                        Button {
                            Task { await model.seek(to: currentTime + 30) }
                        } label: {
                            Image(systemName: "goforward.30")
                                .font(.title2)
                                .foregroundStyle(theme.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer()
                } else {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "waveform")
                            .font(.system(size: 48, weight: .light))
                            .foregroundStyle(theme.textTertiary)
                        Text("Nothing Playing")
                            .font(.title3)
                            .foregroundStyle(theme.textSecondary)
                    }
                    Spacer()
                }
            }
            .padding()
        }
        .navigationTitle("Player")
        .turtleNavBarBackground(theme)
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
