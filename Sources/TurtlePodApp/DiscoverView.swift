import SwiftUI
import TurtlePodCore

struct DiscoverView: View {
    @EnvironmentObject private var model: TurtlePodModel
    @Environment(\.appTheme) private var theme
    @State private var query = ""
    @State private var results: [PodcastSearchResult] = []
    @State private var topPodcasts: [PodcastSearchResult] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var retryToken = 0

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var queryLooksLikeFeedURL: Bool {
        let lower = trimmedQuery.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("feed://")
    }

    var body: some View {
        List {
            if queryLooksLikeFeedURL {
                Section {
                    Button {
                        Task { await model.addFeed(urlString: trimmedQuery) }
                    } label: {
                        Label("Subscribe to this feed", systemImage: "dot.radiowaves.up.forward")
                            .foregroundStyle(theme.amber)
                    }
                    .turtleRow(theme)
                }
            } else if trimmedQuery.isEmpty {
                Section {
                    ForEach(Array(topPodcasts.enumerated()), id: \.element.id) { index, result in
                        DirectoryRow(result: result, rank: index + 1)
                            .turtleRow(theme)
                    }
                    if topPodcasts.isEmpty, errorMessage == nil {
                        ProgressView().frame(maxWidth: .infinity).turtleRow(theme)
                    }
                } header: {
                    Text("Top shows")
                        .font(.title3.weight(.bold))
                        .fontDesign(.rounded)
                        .foregroundStyle(theme.textPrimary)
                        .textCase(nil)
                }
            } else {
                Section {
                    ForEach(results) { result in
                        DirectoryRow(result: result, rank: nil)
                            .turtleRow(theme)
                    }
                    if results.isEmpty, !isSearching, errorMessage == nil {
                        Text("No shows match \u{201C}\(trimmedQuery)\u{201D}. Try the show's name or host, or paste its RSS link.")
                            .font(.subheadline)
                            .foregroundStyle(theme.textSecondary)
                            .turtleRow(theme)
                    }
                }
            }
            if let errorMessage {
                VStack(alignment: .leading, spacing: 10) {
                    Label(errorMessage, systemImage: "wifi.exclamationmark")
                        .font(.subheadline)
                        .foregroundStyle(theme.textSecondary)
                    Button("Try Again") { retryToken += 1 }
                        .buttonStyle(SecondaryButtonStyle())
                }
                .padding(.vertical, 4)
                .turtleRow(theme)
            }
        }
        .turtleList(theme)
        .overlay {
            if isSearching, results.isEmpty { ProgressView() }
        }
        .navigationTitle("Discover")
        .turtleNavBarBackground(theme)
        .searchable(text: $query, placement: .discoverSearchPlacement, prompt: "Shows, hosts, or an RSS link")
        .task(id: "\(trimmedQuery)#\(retryToken)") {
            guard !trimmedQuery.isEmpty, !queryLooksLikeFeedURL else {
                results = []
                errorMessage = nil
                return
            }
            // Debounce typing.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            isSearching = true
            defer { isSearching = false }
            do {
                let found = try await model.directory.search(trimmedQuery)
                guard !Task.isCancelled else { return }
                results = found
                errorMessage = nil
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = "Search isn't available right now. Check your connection."
            }
        }
        .task(id: retryToken) {
            guard topPodcasts.isEmpty else { return }
            do {
                topPodcasts = try await model.directory.topPodcasts(limit: 50)
                if trimmedQuery.isEmpty { errorMessage = nil }
            } catch {
                errorMessage = "Top shows couldn't load. You can still search."
            }
        }
    }
}

private struct DirectoryRow: View {
    @EnvironmentObject private var model: TurtlePodModel
    @Environment(\.appTheme) private var theme
    let result: PodcastSearchResult
    let rank: Int?
    @State private var isSubscribing = false

    var body: some View {
        let subscribed = model.isSubscribed(feedURL: result.feedURL)

        NavigationLink(value: Route.preview(result)) {
            HStack(spacing: 12) {
                if let rank {
                    Text("\(rank)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .fontDesign(.rounded)
                        .foregroundStyle(theme.textTertiary)
                        .frame(minWidth: 22, alignment: .trailing)
                }
                ArtworkView(url: result.artworkURL, size: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(result.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(2)
                    if let author = result.author {
                        Text(author)
                            .font(.caption)
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(1)
                    }
                    if let genre = result.genre {
                        Text(genre)
                            .font(.caption)
                            .foregroundStyle(theme.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    guard !subscribed else { return }
                    isSubscribing = true
                    Task {
                        await model.addFeed(urlString: result.feedURL.absoluteString)
                        isSubscribing = false
                    }
                } label: {
                    Group {
                        if isSubscribing {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: subscribed ? "checkmark" : "plus")
                                .font(.body.weight(.semibold))
                        }
                    }
                    .foregroundStyle(subscribed ? theme.success : theme.amber)
                    .frame(width: 36, height: 36)
                    .background((subscribed ? theme.success : theme.amber).opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(subscribed ? "Subscribed" : "Subscribe to \(result.title)")
            }
            .padding(.vertical, 4)
        }
    }
}

private extension SearchFieldPlacement {
    static var discoverSearchPlacement: SearchFieldPlacement {
        #if os(iOS)
        .navigationBarDrawer(displayMode: .always)
        #else
        .automatic
        #endif
    }
}
