import SwiftUI
import TurtlePodCore

struct DownloadsView: View {
    @EnvironmentObject private var model: TurtlePodModel
    @Environment(\.appTheme) private var theme

    var body: some View {
        List {
            ForEach(model.downloadedEpisodes) { episode in
                NavigationLink(value: episode.id) {
                    EpisodeRow(episode: episode)
                }
                .listRowBackground(theme.backgroundSecondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.backgroundPrimary)
        .overlay {
            if model.downloadedEpisodes.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(theme.textTertiary)
                    Text("No Downloads")
                        .font(.title3)
                        .foregroundStyle(theme.textSecondary)
                    Text("Downloaded episodes appear here")
                        .font(.subheadline)
                        .foregroundStyle(theme.textTertiary)
                }
            }
        }
        .navigationTitle("Downloads")
        .turtleNavBarBackground(theme)
        .navigationDestination(for: UUID.self) { id in
            EpisodeDetailView(episodeID: id)
        }
    }
}
