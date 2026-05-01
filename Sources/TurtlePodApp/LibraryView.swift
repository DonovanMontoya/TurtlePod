import SwiftUI
import TurtlePodCore

struct LibraryView: View {
    @EnvironmentObject private var model: TurtlePodModel
    @State private var feedURL = ""

    var body: some View {
        List {
            Section("Add RSS Feed") {
                HStack {
                    TextField("https://example.com/feed.xml", text: $feedURL)
                        .urlEntryStyle()
                    Button {
                        let value = feedURL
                        feedURL = ""
                        Task { await model.addFeed(urlString: value) }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(feedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            ForEach(model.feeds) { feed in
                Section(feed.title) {
                    ForEach(feed.episodes) { episode in
                        NavigationLink(value: episode.id) {
                            EpisodeRow(episode: episode)
                        }
                    }
                }
            }
        }
        .navigationTitle("Library")
        .navigationDestination(for: UUID.self) { id in
            if let episode = model.episode(withID: id) {
                EpisodeDetailView(episodeID: episode.id)
            }
        }
        .toolbar {
            if let status = model.statusMessage {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct EpisodeRow: View {
    let episode: PodcastEpisode

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: episode.artworkURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "waveform")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 48, height: 48)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(episode.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                HStack(spacing: 8) {
                    if episode.download?.state == .downloaded {
                        Label("Offline", systemImage: "checkmark.circle")
                    }
                    if episode.analysis.status == .complete {
                        Label("\(episode.analysis.adSegments.count) markers", systemImage: "forward.end")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
