import SwiftUI
import TurtlePodCore

enum Route: Hashable {
    case episode(UUID)
    case podcast(UUID)
    case preview(PodcastSearchResult)
}

enum RootTab: String, Hashable {
    case podcasts
    case episodes
    case upNext
    case discover
    case settings
}

struct RootView: View {
    @EnvironmentObject private var model: TurtlePodModel
    @Environment(\.appTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    // Scene storage keeps the tab when the app moves between iPhone Duo's displays.
    @SceneStorage("selectedTab") private var selectedTab: RootTab = .podcasts

    var body: some View {
        let player = model.player

        TabView(selection: $selectedTab) {
            Tab("Podcasts", systemImage: "square.grid.2x2", value: RootTab.podcasts) {
                RoutedStack { PodcastsView(selectedTab: $selectedTab) }
            }
            Tab("Episodes", systemImage: "list.bullet.below.rectangle", value: RootTab.episodes) {
                RoutedStack { EpisodesView() }
            }
            Tab("Up Next", systemImage: "text.line.first.and.arrowtriangle.forward", value: RootTab.upNext) {
                RoutedStack { UpNextView() }
            }
            .badge(model.library.upNext.items.count)
            Tab("Settings", systemImage: "gearshape", value: RootTab.settings) {
                RoutedStack { SettingsView() }
            }
            Tab("Discover", systemImage: "magnifyingglass", value: RootTab.discover, role: .search) {
                RoutedStack { DiscoverView() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(theme.amber)
        .miniPlayerAccessory(isVisible: player.episodeID != nil)
        .sheet(isPresented: Binding(
            get: { player.isFullPlayerPresented },
            set: { player.isFullPlayerPresented = $0 }
        )) {
            NowPlayingView()
                .presentationDragIndicator(.visible)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                model.saveCurrentPosition(force: true)
                Task { await model.saveLibraryNow() }
            }
        }
    }
}

/// A navigation stack that resolves every app route.
struct RoutedStack<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        NavigationStack {
            content
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .episode(let id):
                        EpisodeDetailView(episodeID: id)
                    case .podcast(let id):
                        PodcastDetailView(feedID: id)
                    case .preview(let result):
                        PodcastPreviewView(result: result)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    ToastStack()
                        .padding(.bottom, 8)
                }
                .miniPlayerInsetIfNeeded()
        }
    }
}

// MARK: - Mini player placement

private extension View {
    @ViewBuilder
    func miniPlayerAccessory(isVisible: Bool) -> some View {
        if #available(iOS 26.1, *) {
            #if os(iOS)
            self.tabViewBottomAccessory(isEnabled: isVisible) {
                AccessoryMiniPlayer()
            }
            #else
            self
            #endif
        } else {
            self
        }
    }

    @ViewBuilder
    func miniPlayerInsetIfNeeded() -> some View {
        if #available(iOS 26.1, *) {
            #if os(iOS)
            self
            #else
            modifier(MiniPlayerInset())
            #endif
        } else {
            modifier(MiniPlayerInset())
        }
    }
}

#if os(iOS)
/// Drops the skip button when the tab bar collapses and the accessory goes inline.
@available(iOS 26.1, *)
private struct AccessoryMiniPlayer: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        MiniPlayerBar(style: .accessory, isCompact: placement == .inline)
    }
}
#endif

/// Floats the mini player above the tab bar on systems without a tab accessory.
private struct MiniPlayerInset: ViewModifier {
    @EnvironmentObject private var model: TurtlePodModel

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom) {
            if model.player.episodeID != nil {
                MiniPlayerBar(style: .floating)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
            }
        }
    }
}

struct MiniPlayerBar: View {
    enum Style { case accessory, floating }

    @EnvironmentObject private var model: TurtlePodModel
    @Environment(\.appTheme) private var theme
    let style: Style
    var isCompact = false

    var body: some View {
        let player = model.player
        if let episode = model.nowPlayingEpisode {
            HStack(spacing: 8) {
                Button {
                    player.isFullPlayerPresented = true
                } label: {
                    HStack(spacing: 12) {
                        ArtworkView(url: episode.artworkURL, size: style == .accessory ? 30 : 42)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(player.currentChapter?.title ?? episode.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(theme.textPrimary)
                                .lineLimit(1)
                            if !isCompact, let remaining = player.remaining {
                                Text("\(remaining.shortDuration) left")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(theme.textSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("Now playing: \(episode.title)")
                .accessibilityHint("Opens the player")

                Button {
                    Task { await model.togglePlayback() }
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .foregroundStyle(theme.textPrimary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

                if !isCompact {
                    Button {
                        Task { await model.skipForward() }
                    } label: {
                        Image(systemName: NowPlayingView.skipSymbol("goforward", seconds: model.library.playback.skipForwardSeconds))
                            .font(.title3)
                            .foregroundStyle(theme.textPrimary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Skip forward \(model.library.playback.skipForwardSeconds) seconds")
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, style == .accessory ? 12 : 10)
            .padding(.vertical, style == .accessory ? 0 : 8)
            .background {
                if style == .floating {
                    RoundedRectangle(cornerRadius: TurtleTheme.miniPlayerCornerRadius, style: .continuous)
                        .fill(theme.backgroundCard)
                        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
                }
            }
            .overlay(alignment: .bottom) {
                if let duration = player.duration, duration > 0 {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(theme.amber)
                            .frame(width: proxy.size.width * min(player.currentTime / duration, 1), height: 2)
                    }
                    .frame(height: 2)
                    .padding(.horizontal, style == .accessory ? 18 : 14)
                    .offset(y: style == .accessory ? 1 : 0)
                    .accessibilityHidden(true)
                }
            }
        }
    }
}

// MARK: - Toasts

private struct ToastStack: View {
    @EnvironmentObject private var model: TurtlePodModel
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            if let event = model.activeSkipEvent, !model.player.isFullPlayerPresented {
                UndoSkipBanner(event: event)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if let message = model.statusMessage {
                StatusToast(message: message)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: message) {
                        AccessibilityNotification.Announcement(message).post()
                        try? await Task.sleep(for: .seconds(voiceOverEnabled ? 10 : 4))
                        if model.statusMessage == message {
                            withAnimation { model.statusMessage = nil }
                        }
                    }
            }
        }
        .padding(.horizontal, 16)
        .animation(reduceMotion ? nil : .spring(duration: 0.35), value: model.activeSkipEvent?.id)
        .animation(reduceMotion ? nil : .spring(duration: 0.35), value: model.statusMessage)
    }
}

private struct StatusToast: View {
    @EnvironmentObject private var model: TurtlePodModel
    @Environment(\.appTheme) private var theme
    let message: String

    var body: some View {
        Text(message)
            .font(.footnote.weight(.medium))
            .foregroundStyle(theme.textPrimary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .turtleFloatingCapsule(theme.backgroundElevated)
            .onTapGesture { model.statusMessage = nil }
            .accessibilityAddTraits(.isStaticText)
    }
}

struct UndoSkipBanner: View {
    @EnvironmentObject private var model: TurtlePodModel
    @Environment(\.appTheme) private var theme
    let event: SkipEvent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "forward.end.fill")
                .foregroundStyle(theme.teal)
            Text("Skipped \(max(event.skippedTo - event.skippedFrom, 0).shortDuration) ad")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.textPrimary)
            Spacer(minLength: 8)
            Button("Undo") {
                Task { await model.undoLastSkip() }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(theme.backgroundPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(theme.teal, in: Capsule())
            .contentShape(Rectangle().inset(by: -8))
            .accessibilityHint("Returns to where the ad started")
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .turtleFloatingCapsule(theme.backgroundElevated)
        .frame(maxWidth: 420)
    }
}
