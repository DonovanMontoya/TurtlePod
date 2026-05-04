import SwiftUI
import TurtlePodCore

struct LibraryView: View {
    @EnvironmentObject private var model: TurtlePodModel
    @Environment(\.appTheme) private var theme
    @State private var feedURL = ""

    var body: some View {
        List {
                Section {
                    HStack(spacing: 10) {
                        TextField("https://example.com/feed.xml", text: $feedURL)
                            .urlEntryStyle()
                            .font(.subheadline)
                            .foregroundStyle(theme.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(theme.backgroundElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(theme.textTertiary.opacity(0.3), lineWidth: 0.5)
                            )

                        Button {
                            let value = feedURL
                            feedURL = ""
                            Task { await model.addFeed(urlString: value) }
                        } label: {
                            Image(systemName: "plus")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(theme.backgroundPrimary)
                                .frame(width: 36, height: 36)
                                .background(theme.amber)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .disabled(feedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                } header: {
                    Text("Add Feed")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.textTertiary)
                        .textCase(.uppercase)
                        .tracking(0.8)
                }

                ForEach(model.feeds) { feed in
                    Section {
                        ForEach(feed.episodes) { episode in
                            NavigationLink(value: episode.id) {
                                EpisodeRow(episode: episode)
                            }
                            .listRowBackground(theme.backgroundSecondary)
                        }
                    } header: {
                        Text(feed.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.textPrimary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.backgroundPrimary)
        .navigationTitle("Library")
        .turtleNavBarBackground(theme)
        .navigationDestination(for: UUID.self) { id in
            if let episode = model.episode(withID: id) {
                EpisodeDetailView(episodeID: episode.id)
            }
        }
        .toolbar {
            if let status = model.statusMessage {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }
}

struct EpisodeRow: View {
    @Environment(\.appTheme) private var theme
    let episode: PodcastEpisode

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(url: episode.artworkURL, size: 52)

            VStack(alignment: .leading, spacing: 5) {
                Text(episode.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    if episode.download?.state == .downloaded {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(theme.success)
                            Text("Offline")
                        }
                    }
                    if episode.analysis.status == .complete {
                        HStack(spacing: 3) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(theme.teal)
                            Text("\(episode.analysis.adSegments.count) ads")
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
            }
        }
        .padding(.vertical, 4)
    }
}
