import SwiftUI
import TurtlePodCore

struct UpNextView: View {
    @EnvironmentObject private var model: TurtlePodModel
    @Environment(\.appTheme) private var theme
    @State private var isConfirmingClear = false
    #if os(iOS)
    @State private var editMode = EditMode.inactive
    #endif

    var body: some View {
        let queue = model.upNextEpisodes

        List {
            if let current = model.nowPlayingEpisode {
                Section {
                    Button {
                        model.player.isFullPlayerPresented = true
                    } label: {
                        EpisodeRow(episode: current, showsPodcastTitle: true)
                    }
                    .buttonStyle(.plain)
                    .turtleRow(theme)
                } header: {
                    sectionTitle("Now playing")
                }
            }

            Section {
                ForEach(queue) { episode in
                    NavigationLink(value: Route.episode(episode.id)) {
                        EpisodeRow(episode: episode, showsPodcastTitle: true)
                    }
                    .hidesLinkIndicator()
                    .turtleRow(theme)
                }
                .onMove { source, destination in
                    model.moveUpNext(fromOffsets: source, toOffset: destination)
                }
                .onDelete { offsets in
                    for index in offsets {
                        model.removeFromUpNext(queue[index].id)
                    }
                }
            } header: {
                if !queue.isEmpty {
                    HStack {
                        sectionTitle("Next")
                        Spacer()
                        Text("\(queue.count) episodes · \(model.upNextRemainingTime.shortDuration)")
                            .font(.footnote)
                            .foregroundStyle(theme.textSecondary)
                            .textCase(nil)
                    }
                }
            }
        }
        .turtleList(theme)
        #if os(iOS)
        .environment(\.editMode, $editMode)
        #endif
        .overlay {
            if queue.isEmpty, model.nowPlayingEpisode == nil {
                EmptyStateView(
                    symbol: "text.line.first.and.arrowtriangle.forward",
                    title: "Up Next is empty",
                    message: "Choose Play Next or Play Last on any episode to line it up here."
                )
            }
        }
        .navigationTitle("Up Next")
        .turtleNavBarBackground(theme)
        .toolbar {
            if !queue.isEmpty {
                #if os(iOS)
                // A titled icon, unlike EditButton, can sit in iPhone Duo's vertical bar.
                ToolbarItem(placement: .primaryAction) {
                    let isEditing = editMode.isEditing
                    Button(isEditing ? "Done" : "Reorder", systemImage: isEditing ? "checkmark" : "arrow.up.arrow.down") {
                        withAnimation { editMode = isEditing ? .inactive : .active }
                    }
                }
                #endif
                ToolbarItem(placement: .secondaryAction) {
                    Button(role: .destructive) {
                        isConfirmingClear = true
                    } label: {
                        Label("Clear Up Next", systemImage: "xmark.circle")
                    }
                }
            }
        }
        .confirmationDialog("Clear all \(queue.count) episodes from Up Next?", isPresented: $isConfirmingClear, titleVisibility: .visible) {
            Button("Clear Up Next", role: .destructive) { model.clearUpNext() }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .fontDesign(.rounded)
            .foregroundStyle(theme.textPrimary)
            .textCase(nil)
    }
}
