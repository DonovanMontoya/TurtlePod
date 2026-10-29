import SwiftUI
import TurtlePodCore

struct PodcastDetailView: View {
    @EnvironmentObject private var model: TurtlePodModel
    @Environment(\.appTheme) private var theme
    let feedID: UUID
    @State private var isShowingSettings = false
    @State private var searchText = ""

    var body: some View {
        if let feed = model.feed(withID: feedID) {
            let preferences = model.preferences(for: feed.id)
            let episodes = filtered(model.episodes(in: feed))

            List {
                PodcastHeader(
                    title: feed.title,
                    author: feed.author,
                    summary: feed.summary,
                    artworkURL: feed.artworkURL,
                    websiteURL: feed.websiteURL
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
                .turtleRow(theme)
                .listRowSeparator(.hidden)

                Section {
                    ForEach(episodes) { episode in
                        NavigationLink(value: Route.episode(episode.id)) {
                            EpisodeRow(episode: episode, showsArtwork: false)
                        }
                        .hidesLinkIndicator()
                        .turtleRow(theme)
                    }
                    if episodes.isEmpty {
                        Text(searchText.isEmpty ? "All episodes are played." : "No episodes match \u{201C}\(searchText)\u{201D}.")
                            .font(.subheadline)
                            .foregroundStyle(theme.textSecondary)
                            .turtleRow(theme)
                    }
                } header: {
                    HStack {
                        Text("\(feed.episodes.count) episodes")
                        Spacer()
                        Menu {
                            Picker("Order", selection: Binding(
                                get: { preferences.sortOrder },
                                set: { order in
                                    var updated = preferences
                                    updated.sortOrder = order
                                    model.setPreferences(updated, for: feed.id)
                                }
                            )) {
                                Text("Newest first").tag(EpisodeSortOrder.newestFirst)
                                Text("Oldest first").tag(EpisodeSortOrder.oldestFirst)
                            }
                            Toggle("Hide played", isOn: Binding(
                                get: { preferences.hidePlayed },
                                set: { hide in
                                    var updated = preferences
                                    updated.hidePlayed = hide
                                    model.setPreferences(updated, for: feed.id)
                                }
                            ))
                            Divider()
                            Button {
                                model.markAllPlayed(in: feed)
                            } label: {
                                Label("Mark All as Played", systemImage: "checkmark.circle")
                            }
                        } label: {
                            Label(preferences.sortOrder == .newestFirst ? "Newest" : "Oldest", systemImage: "line.3.horizontal.decrease")
                                .font(.footnote.weight(.semibold))
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(theme.textSecondary)
                    .textCase(nil)
                }
            }
            .turtleList(theme)
            .searchable(text: $searchText, placement: .toolbar, prompt: "Search episodes")
            .refreshable { await model.refreshFeed(feed.id) }
            .navigationTitle(feed.title)
            .inlineNavigationTitle()
            .turtleNavBarBackground(theme)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Label("Podcast Settings", systemImage: "slider.horizontal.3")
                    }
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                PodcastSettingsSheet(feed: feed)
            }
        } else {
            EmptyStateView(symbol: "questionmark.square.dashed", title: "Podcast not found", message: "It may have been removed.")
                .frame(maxHeight: .infinity)
                .background(theme.backgroundPrimary)
        }
    }

    private func filtered(_ episodes: [PodcastEpisode]) -> [PodcastEpisode] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return episodes }
        return episodes.filter {
            $0.title.localizedStandardContains(query) || $0.description.localizedStandardContains(query)
        }
    }
}

struct PodcastHeader: View {
    @Environment(\.appTheme) private var theme
    let title: String
    let author: String?
    let summary: String?
    let artworkURL: URL?
    let websiteURL: URL?
    @State private var isSummaryExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom, spacing: 16) {
                ArtworkView(url: artworkURL, size: 128)
                    .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .fontDesign(.rounded)
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                    if let author, !author.isEmpty {
                        Text(author)
                            .font(.subheadline)
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(2)
                    }
                    if let websiteURL {
                        Link(destination: websiteURL) {
                            Label(websiteURL.host(percentEncoded: false) ?? "Website", systemImage: "safari")
                                .labelStyle(CompactLabelStyle())
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(theme.amber)
                    }
                }
            }
            if let summary, !summary.isEmpty {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(isSummaryExpanded ? nil : 3)
                    .lineSpacing(2)
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { isSummaryExpanded.toggle() } }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(isSummaryExpanded ? "Collapses the description" : "Shows the full description")
            }
        }
    }
}

struct PodcastSettingsSheet: View {
    @EnvironmentObject private var model: TurtlePodModel
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    let feed: PodcastFeed
    @State private var preferences = PodcastPreferences()
    @State private var isConfirmingUnsubscribe = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Download new episodes", isOn: $preferences.autoDownloadNewEpisodes)
                } footer: {
                    Text("When the feed refreshes, the three newest new episodes download automatically.")
                }
                .listRowBackground(theme.backgroundCard)

                Section("Playback") {
                    Toggle("Custom speed for this show", isOn: Binding(
                        get: { preferences.playbackSpeed != nil },
                        set: { preferences.playbackSpeed = $0 ? model.library.playback.speed : nil }
                    ))
                    if let speed = preferences.playbackSpeed {
                        Stepper(value: Binding(
                            get: { speed },
                            set: { preferences.playbackSpeed = min(max($0, 0.5), 3) }
                        ), in: PlaybackPreferences.speedRange, step: 0.1) {
                            LabeledContent("Speed", value: speed.speedLabel)
                        }
                    }
                    Stepper(value: $preferences.skipIntroSeconds, in: 0...300, step: 5) {
                        LabeledContent("Skip first", value: preferences.skipIntroSeconds == 0 ? "Off" : "\(preferences.skipIntroSeconds)s")
                    }
                    Stepper(value: $preferences.skipOutroSeconds, in: 0...300, step: 5) {
                        LabeledContent("Skip last", value: preferences.skipOutroSeconds == 0 ? "Off" : "\(preferences.skipOutroSeconds)s")
                    }
                }
                .listRowBackground(theme.backgroundCard)

                Section {
                    Button("Unsubscribe", role: .destructive) {
                        isConfirmingUnsubscribe = true
                    }
                } footer: {
                    Text("Unsubscribing removes this show's downloads and listening history.")
                }
                .listRowBackground(theme.backgroundCard)
            }
            .scrollContentBackground(.hidden)
            .background(theme.backgroundPrimary)
            .navigationTitle(feed.title)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
            .confirmationDialog("Unsubscribe from \(feed.title)?", isPresented: $isConfirmingUnsubscribe, titleVisibility: .visible) {
                Button("Unsubscribe", role: .destructive) {
                    dismiss()
                    Task { await model.unsubscribe(feed.id) }
                }
            }
        }
        .tint(theme.amber)
        .onAppear { preferences = model.preferences(for: feed.id) }
        .onChange(of: preferences) { _, updated in
            model.setPreferences(updated, for: feed.id)
        }
    }
}

/// A directory result shown before subscribing.
struct PodcastPreviewView: View {
    @EnvironmentObject private var model: TurtlePodModel
    @Environment(\.appTheme) private var theme
    let result: PodcastSearchResult
    @State private var feed: PodcastFeed?
    @State private var loadError: String?
    @State private var isSubscribing = false

    var body: some View {
        if let subscribedID = model.feedID(for: result.feedURL) {
            PodcastDetailView(feedID: subscribedID)
        } else {
            List {
                PodcastHeader(
                    title: feed?.title ?? result.title,
                    author: feed?.author ?? result.author,
                    summary: feed?.summary,
                    artworkURL: result.artworkURL ?? feed?.artworkURL,
                    websiteURL: feed?.websiteURL
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
                .turtleRow(theme)
                .listRowSeparator(.hidden)

                Button {
                    isSubscribing = true
                    Task {
                        await model.addFeed(urlString: result.feedURL.absoluteString)
                        isSubscribing = false
                    }
                } label: {
                    Label(isSubscribing ? "Subscribing…" : "Subscribe", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .frame(minHeight: 44)
                .disabled(isSubscribing)
                .turtleRow(theme)
                .listRowSeparator(.hidden)

                Section {
                    if let feed {
                        ForEach(feed.episodes.prefix(50)) { episode in
                            VStack(alignment: .leading, spacing: 4) {
                                if let date = episode.publishedAt {
                                    Text(date.episodeDateLabel)
                                        .font(.caption)
                                        .foregroundStyle(theme.textSecondary)
                                }
                                Text(episode.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(theme.textPrimary)
                                    .lineLimit(2)
                                if let duration = episode.duration {
                                    Text(duration.shortDuration)
                                        .font(.caption)
                                        .foregroundStyle(theme.textSecondary)
                                }
                            }
                            .padding(.vertical, 4)
                            .turtleRow(theme)
                        }
                    } else if let loadError {
                        Text(loadError)
                            .font(.subheadline)
                            .foregroundStyle(theme.destructive)
                            .turtleRow(theme)
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .turtleRow(theme)
                    }
                } header: {
                    Text(feed.map { "\($0.episodes.count) episodes" } ?? "Episodes")
                        .font(.footnote)
                        .foregroundStyle(theme.textSecondary)
                        .textCase(nil)
                }
            }
            .turtleList(theme)
            .navigationTitle(result.title)
            .inlineNavigationTitle()
            .turtleNavBarBackground(theme)
            .task {
                do {
                    feed = try await model.feedService.fetchFeed(from: result.feedURL)
                } catch {
                    loadError = "Couldn't load this feed: \(error.localizedDescription)"
                }
            }
        }
    }
}
