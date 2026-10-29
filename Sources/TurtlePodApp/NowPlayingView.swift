import AVKit
import SwiftUI
import TurtlePodCore

struct NowPlayingView: View {
    @EnvironmentObject private var model: TurtlePodModel
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title) private var playButtonSize: CGFloat = 78
    @ScaledMetric(relativeTo: .title) private var skipGlyphSize: CGFloat = 30
    @State private var scrubTime: TimeInterval?
    @State private var isShowingChapters = false
    @State private var isShowingUpNext = false

    var body: some View {
        let player = model.player

        ZStack {
            LinearGradient(
                colors: [theme.backgroundElevated, theme.backgroundPrimary, theme.backgroundPrimary],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            if let episode = model.nowPlayingEpisode {
                Group {
                    // ArrangementView ships in the iOS 27.1 SDK (Swift 6.4); older SDKs get the fallback.
                    #if os(iOS) && compiler(>=6.4)
                    if #available(iOS 27.1, *) {
                        // Splits around the fold: artwork above and controls below on a
                        // half-open iPhone Duo, side by side whenever the space is wide.
                        VStack(spacing: 0) {
                            header(episode)
                            ArrangementView {
                                artwork(episode)
                                    .padding(.vertical, 12)
                            } secondary: {
                                controls(episode)
                            }
                            .arrangementViewStyle(.split)
                        }
                    } else {
                        fallbackLayout(episode)
                    }
                    #else
                    fallbackLayout(episode)
                    #endif
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
                .animation(reduceMotion ? nil : .spring(duration: 0.35), value: model.activeSkipEvent?.id)
                .magicTapTogglesPlayback { Task { await model.togglePlayback() } }
            } else {
                EmptyStateView(symbol: "waveform", title: "Nothing playing", message: "Pick an episode to start listening.")
                    .onAppear { player.isFullPlayerPresented = false }
            }
        }
        .sheet(isPresented: $isShowingChapters) {
            ChaptersSheet()
        }
        .sheet(isPresented: $isShowingUpNext) {
            NavigationStack {
                UpNextView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done", systemImage: "checkmark") { isShowingUpNext = false }
                        }
                    }
                    .navigationDestination(for: Route.self) { route in
                        if case .episode(let id) = route { EpisodeDetailView(episodeID: id) }
                    }
            }
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: Sections

    /// Before iOS 27.1: side by side in short landscape, stacked otherwise.
    @ViewBuilder
    private func fallbackLayout(_ episode: PodcastEpisode) -> some View {
        if verticalSizeClass == .compact {
            // Landscape phone: artwork beside the controls.
            HStack(spacing: 28) {
                artwork(episode)
                VStack(spacing: 0) {
                    header(episode)
                    Spacer(minLength: 4)
                    titles(episode)
                    timeline(episode).padding(.top, 12)
                    transport.padding(.top, 8)
                    Spacer(minLength: 4)
                    utilityRow(episode)
                }
            }
        } else {
            VStack(spacing: 0) {
                header(episode)
                Spacer(minLength: 12)
                artwork(episode)
                Spacer(minLength: 16)
                titles(episode)
                timeline(episode)
                    .padding(.top, 20)
                transport
                    .padding(.top, 18)
                Spacer(minLength: 16)
                utilityRow(episode)
            }
        }
    }

    private func controls(_ episode: PodcastEpisode) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)
            titles(episode)
            timeline(episode)
                .padding(.top, 20)
            transport
                .padding(.top, 18)
            Spacer(minLength: 16)
            utilityRow(episode)
        }
    }

    private func header(_ episode: PodcastEpisode) -> some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close player")

            Spacer()
            Text(model.podcastTitle(for: episode) ?? "")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
            Spacer()

            Menu {
                EpisodeMenuItems(episode: episode, includesPlay: false)
                Divider()
                Button(role: .destructive) {
                    model.closePlayer()
                } label: {
                    Label("Stop and Close Player", systemImage: "stop.circle")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("More")
        }
        .foregroundStyle(theme.textPrimary)
        .buttonStyle(.plain)
        .padding(.top, 8)
    }

    private func artwork(_ episode: PodcastEpisode) -> some View {
        let chapterImage = model.player.currentChapter?.imageURL
        return GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ArtworkView(url: chapterImage ?? episode.artworkURL, size: side, cornerRadius: 18)
                .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
                .scaleEffect(model.player.isPlaying || reduceMotion ? 1 : 0.92)
                .animation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.25), value: model.player.isPlaying)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxHeight: 360)
    }

    private func titles(_ episode: PodcastEpisode) -> some View {
        VStack(spacing: 6) {
            if let chapter = model.player.currentChapter {
                Button {
                    isShowingChapters = true
                } label: {
                    Label(chapter.title, systemImage: "list.bullet")
                        .labelStyle(CompactLabelStyle())
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(theme.amber)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows all chapters")
            }
            Text(episode.title)
                .font(.title3.weight(.bold))
                .fontDesign(.rounded)
                .foregroundStyle(theme.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
    }

    private func timeline(_ episode: PodcastEpisode) -> some View {
        let player = model.player
        let duration = player.duration ?? model.duration(for: episode) ?? max(player.currentTime + 1, 1)
        let shown = scrubTime ?? player.currentTime
        let threshold = model.settings.adSkipConfidenceThreshold
        let skippable = episode.analysis.adSegments.filter { $0.confidence >= threshold }
        let skipTotal = skippable.reduce(0) { $0 + max($1.end - $1.start, 0) }

        return VStack(spacing: 8) {
            if let event = model.activeSkipEvent {
                UndoSkipBanner(event: event)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
            AdTimeline(
                currentTime: player.currentTime,
                duration: duration,
                adSegments: episode.analysis.adSegments,
                skipThreshold: threshold,
                chapters: player.chapters,
                trackHeight: 6,
                onScrub: { scrubTime = $0 },
                onSeek: { time in Task { await model.seek(to: time) } }
            )
            .frame(height: 28)

            HStack {
                Text(shown.formattedDuration)
                Spacer()
                if !skippable.isEmpty {
                    Label(
                        model.settings.autoSkipEnabled && episode.autoSkipEnabled
                            ? "\(skippable.count) ads · skips \(skipTotal.shortDuration)"
                            : "\(skippable.count) ads · auto-skip off",
                        systemImage: "forward.end.fill"
                    )
                    .labelStyle(CompactLabelStyle())
                    .foregroundStyle(theme.teal)
                } else if player.isBuffering {
                    Text("Buffering…")
                } else if player.isStreaming {
                    Label("Download to find ads", systemImage: "arrow.down.circle")
                        .labelStyle(CompactLabelStyle())
                        .accessibilityLabel("Streaming. Download this episode to find and skip its ads.")
                }
                Spacer()
                Text("-\(max(duration - shown, 0).formattedDuration)")
            }
            .font(.caption.monospacedDigit().weight(.medium))
            .foregroundStyle(theme.textSecondary)
        }
    }

    private var transport: some View {
        let player = model.player
        let back = model.library.playback.skipBackSeconds
        let forward = model.library.playback.skipForwardSeconds

        return HStack {
            if !player.chapters.isEmpty {
                transportButton("backward.end.fill", label: "Previous chapter", size: 20) {
                    await model.skipChapter(forward: false)
                }
            }
            Spacer()
            transportButton(Self.skipSymbol("gobackward", seconds: back), label: "Skip back \(back) seconds", size: skipGlyphSize) {
                await model.skipBack()
            }
            Spacer()
            Button {
                Task { await model.togglePlayback() }
            } label: {
                ZStack {
                    Circle()
                        .fill(theme.amber)
                        .frame(width: playButtonSize, height: playButtonSize)
                        .shadow(color: theme.amber.opacity(0.35), radius: 16, y: 6)
                    if player.isBuffering {
                        ProgressView().tint(theme.backgroundPrimary)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: playButtonSize * 0.41, weight: .bold))
                            .foregroundStyle(theme.backgroundPrimary)
                            .offset(x: player.isPlaying ? 0 : 2)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            Spacer()
            transportButton(Self.skipSymbol("goforward", seconds: forward), label: "Skip forward \(forward) seconds", size: skipGlyphSize) {
                await model.skipForward()
            }
            Spacer()
            if !player.chapters.isEmpty {
                transportButton("forward.end.fill", label: "Next chapter", size: 20) {
                    await model.skipChapter(forward: true)
                }
            }
        }
    }

    private func utilityRow(_ episode: PodcastEpisode) -> some View {
        let player = model.player
        return HStack {
            Menu {
                ForEach(PlaybackPreferences.speedPresets, id: \.self) { speed in
                    Button {
                        model.setSpeed(speed)
                    } label: {
                        if abs(player.rate - speed) < 0.05 {
                            Label(speed.speedLabel, systemImage: "checkmark")
                        } else {
                            Text(speed.speedLabel)
                        }
                    }
                }
            } label: {
                Text(player.rate.speedLabel)
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .fontDesign(.rounded)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Playback speed \(player.rate.speedLabel)")
            Spacer()

            SleepTimerMenu()
            Spacer()

            let skipOn = episode.autoSkipEnabled && model.settings.autoSkipEnabled
            Button {
                Task { await model.setEpisodeAutoSkip(!episode.autoSkipEnabled, episodeID: episode.id) }
            } label: {
                Image(systemName: skipOn ? "forward.end.circle.fill" : "forward.end.circle")
                    .font(.title3)
                    .foregroundStyle(skipOn ? theme.teal : theme.textSecondary)
                    .frame(width: 44, height: 44)
            }
            .disabled(!model.settings.autoSkipEnabled)
            .accessibilityLabel("Auto-skip ads")
            .accessibilityValue(skipOn ? "On" : "Off")
            .accessibilityAddTraits(.isToggle)
            Spacer()

            RoutePicker()
                .frame(width: 44, height: 44)
            Spacer()

            Button {
                isShowingUpNext = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .overlay(alignment: .topTrailing) {
                        let count = model.library.upNext.items.count
                        if count > 0 {
                            Text("\(count)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(theme.backgroundPrimary)
                                .padding(.horizontal, 5)
                                .background(theme.amber, in: Capsule())
                                .offset(x: 2, y: 4)
                        }
                    }
            }
            .accessibilityLabel("Up Next, \(model.library.upNext.items.count) episodes")
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.textPrimary)
    }

    private func transportButton(_ symbol: String, label: String, size: CGFloat, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(theme.textPrimary)
                .frame(minWidth: 56, minHeight: 56)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// SF Symbols only ship numbered skip glyphs for common intervals.
    static func skipSymbol(_ base: String, seconds: Int) -> String {
        [5, 10, 15, 30, 45, 60, 75, 90].contains(seconds) ? "\(base).\(seconds)" : base
    }
}

private struct SleepTimerMenu: View {
    @EnvironmentObject private var model: TurtlePodModel
    @Environment(\.appTheme) private var theme

    var body: some View {
        let timer = model.player.sleepTimer
        Menu {
            ForEach(SleepTimer.presetMinutes, id: \.self) { minutes in
                Button("\(minutes) minutes") {
                    model.setSleepTimer(.until(Date().addingTimeInterval(TimeInterval(minutes * 60))))
                }
            }
            if !model.player.chapters.isEmpty {
                Button("End of chapter") { model.setSleepTimer(.endOfChapter) }
            }
            Button("End of episode") { model.setSleepTimer(.endOfEpisode) }
            if timer.isActive {
                Divider()
                Button("Turn Off Timer", role: .destructive) { model.setSleepTimer(.off) }
            }
        } label: {
            Group {
                switch timer {
                case .until(let date):
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(max(date.timeIntervalSince(context.date), 0).formattedDuration)
                            .font(.footnote.weight(.bold).monospacedDigit())
                    }
                case .endOfEpisode, .endOfChapter:
                    Image(systemName: "moon.zzz.fill").font(.title3)
                case .off:
                    Image(systemName: "moon.zzz").font(.title3)
                }
            }
            .foregroundStyle(timer.isActive ? theme.amber : theme.textPrimary)
            .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Sleep timer")
        .accessibilityValue(timer.isActive ? "On" : "Off")
    }
}

private struct ChaptersSheet: View {
    @EnvironmentObject private var model: TurtlePodModel
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(model.player.chapters) { chapter in
                let isCurrent = model.player.currentChapter?.id == chapter.id
                Button {
                    Task { await model.seekToChapter(chapter) }
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Text(chapter.start.formattedDuration)
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(theme.textSecondary)
                            .frame(minWidth: 52, alignment: .leading)
                        Text(chapter.title)
                            .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                            .foregroundStyle(isCurrent ? theme.amber : theme.textPrimary)
                        Spacer()
                        if isCurrent {
                            Image(systemName: "speaker.wave.2.fill")
                                .foregroundStyle(theme.amber)
                                .accessibilityLabel("Playing")
                        }
                    }
                }
                .turtleRow(theme)
            }
            .turtleList(theme)
            .navigationTitle("Chapters")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// AirPlay and Bluetooth output picker.
private struct RoutePicker: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        #if os(iOS)
        RoutePickerRepresentable(tint: theme.textPrimary, activeTint: theme.amber)
            .accessibilityLabel("Audio output")
        #else
        Image(systemName: "airplayaudio")
        #endif
    }
}

#if os(iOS)
private struct RoutePickerRepresentable: UIViewRepresentable {
    let tint: Color
    let activeTint: Color

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {
        view.tintColor = UIColor(tint)
        view.activeTintColor = UIColor(activeTint)
    }
}
#endif

private extension View {
    /// VoiceOver's two-finger double tap plays or pauses from anywhere in the player.
    func magicTapTogglesPlayback(_ action: @escaping () -> Void) -> some View {
        #if os(iOS)
        accessibilityAction(.magicTap, action)
        #else
        self
        #endif
    }
}
