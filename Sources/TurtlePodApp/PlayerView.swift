import SwiftUI
import TurtlePodCore

struct PlayerView: View {
    @EnvironmentObject private var model: TurtlePodModel
    @State private var currentEpisode: PodcastEpisode?
    @State private var currentTime: TimeInterval = 0
    @State private var isPlaying = false

    var body: some View {
        VStack(spacing: 24) {
            if let episode = currentEpisode {
                AsyncImage(url: episode.artworkURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "waveform")
                        .font(.system(size: 72))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 220, height: 220)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(spacing: 8) {
                    Text(episode.title)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text(currentTime.formattedDuration)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                PlaybackScrubber(
                    currentTime: currentTime,
                    duration: max(episode.duration ?? max(episode.analysis.adSegments.map(\.end).max() ?? 1, currentTime + 1), 1),
                    adSegments: episode.analysis.adSegments
                ) { seekTime in
                    Task { await model.seek(to: seekTime) }
                }
                    .frame(height: 34)
                    .padding(.horizontal)

                HStack(spacing: 28) {
                    Button {
                        Task { await model.seek(to: max(0, currentTime - 15)) }
                    } label: {
                        Image(systemName: "gobackward.15")
                            .font(.title)
                    }

                    Button {
                        Task { await model.togglePlayback() }
                    } label: {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 64))
                    }

                    Button {
                        Task { await model.seek(to: currentTime + 30) }
                    } label: {
                        Image(systemName: "goforward.30")
                            .font(.title)
                    }
                }
                .buttonStyle(.plain)
            } else {
                ContentUnavailableView("Nothing Playing", systemImage: "play.circle")
            }
        }
        .padding()
        .navigationTitle("Player")
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
