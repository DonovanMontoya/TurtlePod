import SwiftUI
import TurtlePodCore

// MARK: - Formatting

extension TimeInterval {
    /// "1h 5m", "42m", or "35s" for compact metadata lines.
    var shortDuration: String {
        let total = max(0, Int(self.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(total)s"
    }
}

extension TimeInterval {
    /// "1 hour, 5 minutes" for VoiceOver, where "1h 5m" reads poorly.
    var spokenDuration: String {
        Duration.seconds(max(self, 0)).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide, maximumUnitCount: 2))
    }
}

extension Double {
    /// "1×", "1.5×".
    var speedLabel: String {
        let rounded = (self * 10).rounded() / 10
        return rounded == rounded.rounded() ? "\(Int(rounded))×" : String(format: "%.1f×", rounded)
    }
}

extension Date {
    var episodeDateLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return "Today" }
        if calendar.isDateInYesterday(self) { return "Yesterday" }
        if let days = calendar.dateComponents([.day], from: self, to: Date()).day, days < 7 {
            return formatted(.dateTime.weekday(.wide))
        }
        if calendar.isDate(self, equalTo: Date(), toGranularity: .year) {
            return formatted(.dateTime.month(.abbreviated).day())
        }
        return formatted(.dateTime.month(.abbreviated).day().year())
    }
}

// MARK: - Play button

/// Round play control with a ring showing how much has been heard.
struct EpisodePlayButton: View {
    @EnvironmentObject private var model: TurtlePodModel
    @Environment(\.appTheme) private var theme
    let episode: PodcastEpisode
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 36

    var body: some View {
        let isCurrent = model.player.episodeID == episode.id
        let isPlaying = isCurrent && model.player.isPlaying
        let progress = model.progress(for: episode) ?? 0
        let played = model.state(for: episode.id).isPlayed

        Button {
            Task {
                if isPlaying {
                    await model.pause()
                } else {
                    await model.play(episode)
                }
            }
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(theme.textTertiary.opacity(0.7), lineWidth: 1.5)
                Circle()
                    .trim(from: 0, to: played ? 1 : progress)
                    .stroke(theme.amber, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(1)
                if isCurrent && model.player.isBuffering {
                    ProgressView()
                        .controlSize(.small)
                        .tint(theme.amber)
                } else {
                    Image(systemName: isPlaying ? "pause.fill" : played ? "checkmark" : "play.fill")
                        .font(.system(size: size * 0.36, weight: .bold))
                        .foregroundStyle(played && !isCurrent ? theme.textTertiary : theme.amber)
                        .offset(x: isPlaying || played ? 0 : size * 0.03)
                }
            }
            .frame(width: size, height: size)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Pause" : "Play \(episode.title)")
        .accessibilityShowsLargeContentViewer()
    }
}

// MARK: - Episode row

struct EpisodeRow: View {
    @EnvironmentObject private var model: TurtlePodModel
    @Environment(\.appTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let episode: PodcastEpisode
    var showsPodcastTitle = false
    var showsArtwork = true

    var body: some View {
        let state = model.state(for: episode.id)

        HStack(alignment: .center, spacing: 12) {
            if showsArtwork {
                ArtworkView(url: episode.artworkURL, size: 56)
            }

            VStack(alignment: .leading, spacing: 4) {
                topLine
                Text(episode.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(state.isPlayed ? theme.textSecondary : theme.textPrimary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 6 : 2)
                    .multilineTextAlignment(.leading)
                EpisodeMetaLine(episode: episode)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            EpisodePlayButton(episode: episode)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(episode.title)
        .accessibilityValue(accessibilitySummary(state))
        .accessibilityAction(named: model.player.episodeID == episode.id && model.player.isPlaying ? "Pause" : "Play") {
            Task {
                if model.player.episodeID == episode.id && model.player.isPlaying {
                    await model.pause()
                } else {
                    await model.play(episode)
                }
            }
        }
        .episodeActions(episode)
    }

    private func accessibilitySummary(_ state: EpisodeUserState) -> String {
        var parts: [String] = []
        if showsPodcastTitle, let title = model.podcastTitle(for: episode) { parts.append(title) }
        if let date = episode.publishedAt { parts.append(date.episodeDateLabel) }
        if state.isPlayed {
            parts.append("Played")
        } else if let duration = model.duration(for: episode) {
            let position = model.position(for: episode)
            parts.append(position >= 1 ? "\(max(duration - position, 0).spokenDuration) left" : duration.spokenDuration)
        }
        if state.isStarred { parts.append("Starred") }
        if episode.download?.state == .downloaded { parts.append("Downloaded") }
        if episode.analysis.status == .complete, !episode.analysis.adSegments.isEmpty {
            parts.append("\(episode.analysis.adSegments.count) ads found")
        }
        return parts.joined(separator: ", ")
    }

    private var topLine: some View {
        HStack(spacing: 6) {
            if model.state(for: episode.id).isStarred {
                Image(systemName: "star.fill")
                    .foregroundStyle(theme.amber)
                    .accessibilityLabel("Starred")
            }
            if let date = episode.publishedAt {
                Text(date.episodeDateLabel)
            }
            if showsPodcastTitle, let title = model.podcastTitle(for: episode) {
                Text(title)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }
            if let label = episodeTypeLabel {
                Text(label)
                    .foregroundStyle(theme.amberMuted)
            }
        }
        .font(.caption)
        .foregroundStyle(theme.textSecondary)
    }

    private var episodeTypeLabel: String? {
        switch episode.episodeType?.lowercased() {
        case "trailer": "Trailer"
        case "bonus": "Bonus"
        default: nil
        }
    }
}

/// Time left, download, and ad-analysis state for an episode.
struct EpisodeMetaLine: View {
    @EnvironmentObject private var model: TurtlePodModel
    @Environment(\.appTheme) private var theme
    let episode: PodcastEpisode

    var body: some View {
        let state = model.state(for: episode.id)
        HStack(spacing: 10) {
            timeLabel(state)
            downloadLabel
            if episode.analysis.status == .complete, !episode.analysis.adSegments.isEmpty {
                Label("\(episode.analysis.adSegments.count) ads", systemImage: "forward.end.fill")
                    .foregroundStyle(theme.teal)
            }
        }
        .labelStyle(CompactLabelStyle())
        .font(.caption)
        .foregroundStyle(theme.textSecondary)
    }

    @ViewBuilder
    private func timeLabel(_ state: EpisodeUserState) -> some View {
        if state.isPlayed {
            Text("Played")
        } else if let duration = model.duration(for: episode) {
            let position = model.position(for: episode)
            if position >= 1 {
                Text("\(max(duration - position, 0).shortDuration) left")
                    .foregroundStyle(theme.amber)
            } else {
                Text(duration.shortDuration)
            }
        }
    }

    @ViewBuilder
    private var downloadLabel: some View {
        switch episode.download?.state {
        case .downloaded:
            Label("Downloaded", systemImage: "arrow.down.circle.fill")
                .foregroundStyle(theme.success)
                .labelStyle(.iconOnly)
        case .downloading:
            Label((episode.download?.progress ?? 0).formatted(.percent.precision(.fractionLength(0))), systemImage: "arrow.down.circle")
                .foregroundStyle(theme.amber)
        case .failed:
            Label("Download failed", systemImage: "exclamationmark.circle")
                .foregroundStyle(theme.destructive)
                .labelStyle(.iconOnly)
        default:
            EmptyView()
        }
    }
}

struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
        }
    }
}

// MARK: - Episode actions

extension View {
    /// Swipe actions and context menu shared by every episode list.
    func episodeActions(_ episode: PodcastEpisode) -> some View {
        modifier(EpisodeActionsModifier(episode: episode))
    }
}

private struct EpisodeActionsModifier: ViewModifier {
    @EnvironmentObject private var model: TurtlePodModel
    @Environment(\.appTheme) private var theme
    let episode: PodcastEpisode

    func body(content: Content) -> some View {
        let state = model.state(for: episode.id)
        let queued = model.library.upNext.contains(episode.id)

        content
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if queued {
                    Button {
                        model.removeFromUpNext(episode.id)
                    } label: {
                        Label("Remove from Up Next", systemImage: "text.badge.minus")
                    }
                    .tint(theme.swipeNeutral)
                } else {
                    Button {
                        model.playNext(episode)
                    } label: {
                        Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                    }
                    .tint(theme.swipePrimary)
                    Button {
                        model.playLast(episode)
                    } label: {
                        Label("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward")
                    }
                    .tint(theme.swipeSecondary)
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button {
                    Task {
                        if state.isPlayed { model.markUnplayed(episode) } else { await model.markPlayed(episode) }
                    }
                } label: {
                    Label(state.isPlayed ? "Mark Unplayed" : "Mark Played", systemImage: state.isPlayed ? "circle" : "checkmark.circle")
                }
                .tint(theme.swipeSuccess)
                Button {
                    model.toggleStar(episode)
                } label: {
                    Label(state.isStarred ? "Unstar" : "Star", systemImage: state.isStarred ? "star.slash" : "star")
                }
                .tint(theme.swipeSecondary)
            }
            .contextMenu {
                EpisodeMenuItems(episode: episode)
            }
    }
}

/// Menu items for an episode, used in context menus and "more" buttons.
struct EpisodeMenuItems: View {
    @EnvironmentObject private var model: TurtlePodModel
    let episode: PodcastEpisode
    var includesPlay = true

    var body: some View {
        let state = model.state(for: episode.id)
        let queued = model.library.upNext.contains(episode.id)
        let isCurrent = model.player.episodeID == episode.id

        if includesPlay {
            Button {
                Task { await model.play(episode) }
            } label: {
                Label(state.isInProgress ? "Resume" : "Play", systemImage: "play")
            }
        }
        if !isCurrent {
            if queued {
                Button {
                    model.removeFromUpNext(episode.id)
                } label: {
                    Label("Remove from Up Next", systemImage: "text.badge.minus")
                }
            } else {
                Button {
                    model.playNext(episode)
                } label: {
                    Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                }
                Button {
                    model.playLast(episode)
                } label: {
                    Label("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward")
                }
            }
        }
        Divider()
        switch episode.download?.state {
        case .downloaded:
            Button(role: .destructive) {
                Task { await model.deleteDownload(episode) }
            } label: {
                Label("Remove Download", systemImage: "trash")
            }
        case .downloading:
            Button {
                model.cancelDownload(episode.id)
            } label: {
                Label("Cancel Download", systemImage: "xmark.circle")
            }
        default:
            Button {
                model.startDownload(episode)
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
        }
        Button {
            model.toggleStar(episode)
        } label: {
            Label(state.isStarred ? "Unstar" : "Star", systemImage: state.isStarred ? "star.slash" : "star")
        }
        Button {
            Task {
                if state.isPlayed { model.markUnplayed(episode) } else { await model.markPlayed(episode) }
            }
        } label: {
            Label(state.isPlayed ? "Mark as Unplayed" : "Mark as Played", systemImage: state.isPlayed ? "circle" : "checkmark.circle")
        }
        ShareLink(item: episode.websiteURL ?? episode.audioURL, subject: Text(episode.title)) {
            Label("Share Episode", systemImage: "square.and.arrow.up")
        }
    }
}

// MARK: - Download control

/// Download, progress-with-cancel, or downloaded state for an episode.
struct DownloadControl: View {
    @EnvironmentObject private var model: TurtlePodModel
    @Environment(\.appTheme) private var theme
    let episode: PodcastEpisode
    var size: CGFloat = 44

    var body: some View {
        Group {
            switch episode.download?.state {
            case .downloading:
                Button {
                    model.cancelDownload(episode.id)
                } label: {
                    ZStack {
                        Circle().stroke(theme.backgroundElevated, lineWidth: 3)
                        Circle()
                            .trim(from: 0, to: max(episode.download?.progress ?? 0, 0.02))
                            .stroke(theme.amber, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Image(systemName: "stop.fill")
                            .font(.system(size: size * 0.24))
                            .foregroundStyle(theme.amber)
                    }
                    .padding(size * 0.2)
                }
                .accessibilityLabel("Cancel download")
                .accessibilityValue((episode.download?.progress ?? 0).formatted(.percent.precision(.fractionLength(0))))
            case .downloaded:
                Menu {
                    Button(role: .destructive) {
                        Task { await model.deleteDownload(episode) }
                    } label: {
                        Label("Remove Download", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: size * 0.5))
                        .foregroundStyle(theme.success)
                }
                .accessibilityLabel("Downloaded")
            default:
                Button {
                    model.startDownload(episode)
                } label: {
                    Image(systemName: episode.download?.state == .failed ? "exclamationmark.arrow.circlepath" : "arrow.down.circle")
                        .font(.system(size: size * 0.5))
                        .foregroundStyle(episode.download?.state == .failed ? theme.destructive : theme.textSecondary)
                }
                .accessibilityLabel(episode.download?.state == .failed ? "Retry download" : "Download")
            }
        }
        .buttonStyle(.plain)
        .frame(width: size, height: size)
        .disabled(model.busyEpisodeIDs.contains(episode.id) && episode.download?.state != .downloading)
    }
}

// MARK: - Ad-aware timeline

/// The playback track. Honey shows what you've heard; lagoon marks ad breaks
/// that auto-skip will jump over. Ads below the confidence threshold are
/// outlined because they will play.
struct AdTimeline: View {
    @Environment(\.appTheme) private var theme
    let currentTime: TimeInterval
    let duration: TimeInterval
    var adSegments: [AdSegment] = []
    var skipThreshold: Double = 0
    var chapters: [EpisodeChapter] = []
    var trackHeight: CGFloat = 6
    var showsThumb = true
    var onScrub: ((TimeInterval?) -> Void)?
    var onSeek: (TimeInterval) -> Void

    @State private var scrubTime: TimeInterval?

    private var effectiveDuration: TimeInterval { max(duration, 1) }
    private var displayTime: TimeInterval { scrubTime ?? currentTime }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let progress = fraction(displayTime)
            let thumb: CGFloat = scrubTime == nil ? trackHeight * 2.4 : trackHeight * 3.4

            ZStack(alignment: .leading) {
                Canvas { context, size in
                    let midY = size.height / 2
                    let track = CGRect(x: 0, y: midY - trackHeight / 2, width: size.width, height: trackHeight)
                    let trackPath = Path(roundedRect: track, cornerRadius: trackHeight / 2)
                    context.fill(trackPath, with: .color(theme.separator.opacity(0.55)))

                    var played = track
                    played.size.width = size.width * progress
                    context.fill(Path(roundedRect: played, cornerRadius: trackHeight / 2), with: .color(theme.amber))

                    for chapter in chapters where chapter.start > 1 {
                        let x = size.width * fraction(chapter.start)
                        context.fill(Path(CGRect(x: x - 0.75, y: track.minY, width: 1.5, height: trackHeight)), with: .color(theme.backgroundPrimary))
                    }

                    // Ads sit in a taller band so they read apart from progress
                    // even where the two colors are close.
                    let adHeight = trackHeight + 4
                    let playedX = size.width * progress
                    for segment in adSegments {
                        let start = size.width * fraction(segment.start)
                        let end = size.width * fraction(segment.end)
                        let rect = CGRect(x: start, y: midY - adHeight / 2, width: max(end - start, 3), height: adHeight)
                        let path = Path(roundedRect: rect, cornerRadius: 2)
                        let isBehind = rect.maxX <= playedX
                        if segment.confidence >= skipThreshold {
                            context.fill(path, with: .color(theme.teal.opacity(isBehind ? 0.5 : 1)))
                            context.stroke(path, with: .color(theme.backgroundPrimary), lineWidth: 1)
                        } else {
                            context.stroke(
                                Path(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), cornerRadius: 2),
                                with: .color(theme.teal),
                                style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])
                            )
                        }
                    }
                }

                if showsThumb {
                    Circle()
                        .fill(theme.textPrimary)
                        .frame(width: thumb, height: thumb)
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                        .offset(x: min(max(width * progress - thumb / 2, 0), width - thumb))
                        .animation(.easeOut(duration: 0.15), value: scrubTime == nil)
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let time = time(for: value.location.x, width: width)
                        scrubTime = time
                        onScrub?(time)
                    }
                    .onEnded { value in
                        let time = time(for: value.location.x, width: width)
                        scrubTime = nil
                        onScrub?(nil)
                        onSeek(time)
                    }
            )
        }
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onSeek(min(currentTime + 30, effectiveDuration))
            case .decrement: onSeek(max(currentTime - 15, 0))
            @unknown default: break
            }
        }
    }

    private var accessibilityValue: String {
        let base = "\(displayTime.spokenDuration) of \(effectiveDuration.spokenDuration)"
        let inAd = adSegments.contains { displayTime >= $0.start && displayTime < $0.end }
        return inAd ? base + ", in an ad break" : base
    }

    private func time(for x: CGFloat, width: CGFloat) -> TimeInterval {
        TimeInterval(min(max(x / max(width, 1), 0), 1)) * effectiveDuration
    }

    private func fraction(_ time: TimeInterval) -> CGFloat {
        CGFloat(min(max(time / effectiveDuration, 0), 1))
    }
}

// MARK: - Empty state

struct EmptyStateView<Actions: View>: View {
    @Environment(\.appTheme) private var theme
    let symbol: String
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(theme.amberMuted)
            Text(title)
                .font(.title3.weight(.semibold))
                .fontDesign(.rounded)
                .foregroundStyle(theme.textPrimary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            actions
                .padding(.top, 4)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(symbol: String, title: String, message: String) {
        self.init(symbol: symbol, title: title, message: message) { EmptyView() }
    }
}

/// Filled honey capsule for a screen's primary action.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.appTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isEnabled ? theme.backgroundPrimary : theme.textTertiary)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(isEnabled ? theme.amber : theme.backgroundElevated, in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// Quiet tinted capsule for secondary actions.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.appTheme) private var theme
    var tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        let color = tint ?? theme.amber
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(color.opacity(configuration.isPressed ? 0.2 : 0.12), in: Capsule())
    }
}

/// Themed list background and row styling.
extension View {
    func turtleList(_ theme: TurtleTheme) -> some View {
        self
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(theme.backgroundPrimary)
    }

    func turtleRow(_ theme: TurtleTheme) -> some View {
        self
            .listRowBackground(theme.backgroundPrimary)
            .listRowSeparatorTint(theme.separator.opacity(0.6))
    }
}

extension View {
    /// Episode rows already end in a play button, so the disclosure chevron is noise.
    @ViewBuilder
    func hidesLinkIndicator() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            navigationLinkIndicatorVisibility(.hidden)
        } else {
            self
        }
    }
}
