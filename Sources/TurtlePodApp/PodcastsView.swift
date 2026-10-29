import SwiftUI
import UniformTypeIdentifiers
import TurtlePodCore

enum PodcastGridSort: String, CaseIterable {
    case recentlyUpdated
    case title
    case dateAdded

    var label: String {
        switch self {
        case .recentlyUpdated: "Latest episode"
        case .title: "Name"
        case .dateAdded: "Date added"
        }
    }
}

struct PodcastsView: View {
    @EnvironmentObject private var model: TurtlePodModel
    @Environment(\.appTheme) private var theme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var selectedTab: RootTab
    @AppStorage("podcastGridSort") private var sort = PodcastGridSort.recentlyUpdated
    @State private var isAddingPodcast = false

    private var sortedFeeds: [PodcastFeed] {
        switch sort {
        case .recentlyUpdated:
            model.feeds.sorted { model.latestEpisodeDate(in: $0) > model.latestEpisodeDate(in: $1) }
        case .title:
            model.feeds.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .dateAdded:
            model.feeds.sorted {
                (model.preferences(for: $0.id).addedAt ?? .distantPast) > (model.preferences(for: $1.id).addedAt ?? .distantPast)
            }
        }
    }

    var body: some View {
        ScrollView {
            if model.feeds.isEmpty {
                if model.hasLoaded {
                    EmptyStateView(
                        symbol: "square.grid.2x2",
                        title: "No podcasts yet",
                        message: "Search for a show or add one by its RSS feed link."
                    ) {
                        HStack(spacing: 10) {
                            Button("Find Podcasts") { selectedTab = .discover }
                                .buttonStyle(PrimaryButtonStyle())
                            Button("Add by Link") { isAddingPodcast = true }
                                .buttonStyle(SecondaryButtonStyle())
                        }
                    }
                    .padding(.top, 80)
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: horizontalSizeClass == .regular ? 150 : 104, maximum: 220), spacing: horizontalSizeClass == .regular ? 18 : 12)], spacing: 12) {
                    ForEach(sortedFeeds) { feed in
                        NavigationLink(value: Route.podcast(feed.id)) {
                            PodcastTile(feed: feed, unplayed: model.newEpisodeCount(in: feed))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                Task { await model.refreshFeed(feed.id) }
                            } label: {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                            Button {
                                model.markAllPlayed(in: feed)
                            } label: {
                                Label("Mark All as Played", systemImage: "checkmark.circle")
                            }
                            Button(role: .destructive) {
                                Task { await model.unsubscribe(feed.id) }
                            } label: {
                                Label("Unsubscribe", systemImage: "minus.circle")
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .background(theme.backgroundPrimary)
        .refreshable { await model.refreshAllFeeds() }
        .navigationTitle("Podcasts")
        .turtleNavBarBackground(theme)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isAddingPodcast = true
                } label: {
                    Label("Add Podcast", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    Picker("Sort by", selection: $sort) {
                        ForEach(PodcastGridSort.allCases, id: \.self) { option in
                            Text(option.label).tag(option)
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
            }
        }
        .sheet(isPresented: $isAddingPodcast) {
            AddPodcastSheet(selectedTab: $selectedTab)
        }
    }
}

private struct PodcastTile: View {
    @Environment(\.appTheme) private var theme
    let feed: PodcastFeed
    let unplayed: Int

    var body: some View {
        FlexibleArtworkView(url: feed.artworkURL)
            .overlay(alignment: .topTrailing) {
                if unplayed > 0 {
                    Text(unplayed > 99 ? "99+" : "\(unplayed)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(theme.backgroundPrimary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(theme.amber, in: Capsule())
                        .padding(6)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(feed.title)
            .accessibilityValue(unplayed > 0 ? "\(unplayed) new" : "")
            .accessibilityAddTraits(.isButton)
    }
}

/// Add by RSS link or import an OPML file from another app.
struct AddPodcastSheet: View {
    @EnvironmentObject private var model: TurtlePodModel
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedTab: RootTab
    @State private var feedURL = ""
    @State private var isWorking = false
    @State private var isImportingOPML = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Feed link", text: $feedURL, prompt: Text("https://example.com/feed.xml"))
                        .urlEntryStyle()
                        .submitLabel(.go)
                        .onSubmit(add)
                    Button(action: add) {
                        HStack {
                            Text("Subscribe")
                            if isWorking {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(feedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)
                } header: {
                    Text("RSS feed")
                } footer: {
                    if let error {
                        Text(error).foregroundStyle(theme.destructive)
                    } else {
                        Text("Private and premium feeds work too: paste the link your host gave you.")
                    }
                }
                .listRowBackground(theme.backgroundCard)

                Section {
                    Button {
                        dismiss()
                        selectedTab = .discover
                    } label: {
                        Label("Search the podcast directory", systemImage: "magnifyingglass")
                    }
                    Button {
                        isImportingOPML = true
                    } label: {
                        Label("Import OPML from another app", systemImage: "square.and.arrow.down")
                    }
                    .disabled(isWorking)
                } footer: {
                    Text("Most podcast apps, including Pocket Casts, can export your subscriptions as an OPML file.")
                }
                .listRowBackground(theme.backgroundCard)
            }
            .scrollContentBackground(.hidden)
            .background(theme.backgroundPrimary)
            .navigationTitle("Add Podcast")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .fileImporter(isPresented: $isImportingOPML, allowedContentTypes: OPMLDocument.contentTypes) { result in
                guard case .success(let url) = result else { return }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else {
                    error = "That file couldn't be opened."
                    return
                }
                isWorking = true
                Task {
                    let result = await model.importOPML(data)
                    isWorking = false
                    if result.added > 0 { dismiss() }
                }
            }
        }
        .tint(theme.amber)
        .presentationDetents([.medium, .large])
    }

    private func add() {
        let value = feedURL
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isWorking = true
        error = nil
        Task {
            let id = await model.addFeed(urlString: value)
            isWorking = false
            if id != nil {
                dismiss()
            } else {
                error = model.statusMessage
            }
        }
    }
}

enum OPMLDocument {
    static var contentTypes: [UTType] {
        [UTType(filenameExtension: "opml"), .xml, .data].compactMap(\.self)
    }
}

extension View {
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
