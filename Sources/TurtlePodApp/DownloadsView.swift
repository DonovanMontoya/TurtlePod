import SwiftUI

struct DownloadsView: View {
    @EnvironmentObject private var model: TurtlePodModel

    var body: some View {
        List {
            ForEach(model.downloadedEpisodes) { episode in
                NavigationLink(value: episode.id) {
                    EpisodeRow(episode: episode)
                }
            }
        }
        .navigationTitle("Downloads")
        .overlay {
            if model.downloadedEpisodes.isEmpty {
                ContentUnavailableView("No Downloads", systemImage: "arrow.down.circle")
            }
        }
        .navigationDestination(for: UUID.self) { id in
            EpisodeDetailView(episodeID: id)
        }
    }
}
