import SwiftUI
import TurtlePodCore

enum EpisodeFilter: String, CaseIterable, Identifiable {
    case newReleases
    case inProgress
    case starred
    case downloaded
    case history

    var id: Self { self }

    var title: String {
        switch self {
        case .newReleases: "New"
        case .inProgress: "In progress"
        case .starred: "Starred"
        case .downloaded: "Downloaded"
        case .history: "History"
        }
    }

    var symbol: String {
        switch self {
        case .newReleases: "sparkle"
        case .inProgress: "circle.lefthalf.filled"
        case .starred: "star"
        case .downloaded: "arrow.down.circle"
        case .history: "clock.arrow.circlepath"
        }
    }

    var emptyMessage: String {
        switch self {
        case .newReleases: "Unplayed episodes from the last two weeks show up here."
        case .inProgress: "Episodes you've started and not finished show up here."
        case .starred: "Star an episode from its page or its menu to save it here."
        case .downloaded: "Downloaded episodes play offline and can be analyzed for ads."
        case .history: "Episodes you play show up here, most recent first."
        }
    }
}

struct EpisodesView: View {
    @EnvironmentObject private var model: TurtlePodModel
    @Environment(\.appTheme) private var theme
    @AppStorage("episodeFilter") private var filter = EpisodeFilter.newReleases
    @State private var isConfirmingClearPlayed = false

    private var episodes: [PodcastEpisode] {
        switch filter {
        case .newReleases: model.newReleases
        case .inProgress: model.inProgressEpisodes
        case .starred: model.starredEpisodes
        case .downloaded: model.downloadedEpisodes + model.allEpisodes.filter { $0.download?.state == .downloading }
        case .history: model.historyEpisodes
        }
    }

    var body: some View {
        let episodes = episodes

        List {
            FilterChips(selection: $filter)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                .turtleRow(theme)
                .listRowSeparator(.hidden)

            if filter == .downloaded, !episodes.isEmpty {
                HStack {
                    Text("\(model.downloadedEpisodes.count) episodes · \(model.downloadsSizeDescription)")
                    Spacer()
                    Button("Remove played") { isConfirmingClearPlayed = true }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(theme.amber)
                        .buttonStyle(.plain)
                }
                .font(.footnote)
                .foregroundStyle(theme.textSecondary)
                .turtleRow(theme)
                .listRowSeparator(.hidden)
            }

            ForEach(episodes) { episode in
                NavigationLink(value: Route.episode(episode.id)) {
                    EpisodeRow(episode: episode, showsPodcastTitle: true)
                }
                .hidesLinkIndicator()
                .turtleRow(theme)
            }
        }
        .turtleList(theme)
        .overlay {
            if episodes.isEmpty, model.hasLoaded {
                EmptyStateView(symbol: filter.symbol, title: "Nothing here yet", message: filter.emptyMessage)
                    .padding(.top, 60)
            }
        }
        .refreshable { await model.refreshAllFeeds() }
        .navigationTitle("Episodes")
        .turtleNavBarBackground(theme)
        .confirmationDialog("Remove downloads of played episodes?", isPresented: $isConfirmingClearPlayed, titleVisibility: .visible) {
            Button("Remove Played Downloads", role: .destructive) {
                Task {
                    let count = await model.deletePlayedDownloads()
                    model.statusMessage = count == 0 ? "No played downloads to remove." : "Removed \(count) downloads."
                }
            }
        }
    }
}

private struct FilterChips: View {
    @Environment(\.appTheme) private var theme
    @Binding var selection: EpisodeFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(EpisodeFilter.allCases) { filter in
                    let isSelected = filter == selection
                    Button {
                        selection = filter
                    } label: {
                        Label(filter.title, systemImage: filter.symbol)
                            .labelStyle(CompactLabelStyle())
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(isSelected ? theme.backgroundPrimary : theme.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(isSelected ? theme.amber : theme.backgroundElevated, in: Capsule())
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
        }
    }
}
