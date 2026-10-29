import SwiftUI
import UniformTypeIdentifiers
import TurtlePodCore

struct SettingsView: View {
    @EnvironmentObject private var model: TurtlePodModel
    @Environment(\.appTheme) private var theme
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.ember.rawValue
    @State private var isImportingOPML = false
    @State private var exportURL: URL?
    @State private var isConfirmingDeletePlayed = false

    private static let skipIntervals = [5, 10, 15, 30, 45, 60, 75, 90]

    var body: some View {
        Form {
            statsSection
            appearanceSection
            playbackSection
            adSkipSection
            analysisSection
            librarySection
        }
        .scrollContentBackground(.hidden)
        .background(theme.backgroundPrimary)
        .navigationTitle("Settings")
        .turtleNavBarBackground(theme)
        .onChange(of: model.settings) { _, _ in
            Task { await model.saveSettings(includingKeys: false) }
        }
        .onChange(of: model.library.playback) { _, playback in
            model.nowPlaying.updateSkipIntervals(forward: playback.skipForwardSeconds, back: playback.skipBackSeconds)
            model.saveLibrary()
        }
        .task(id: keyFingerprint) {
            // Save API keys shortly after typing stops.
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled, model.hasLoaded else { return }
            await model.saveSettings(includingKeys: true)
        }
        .fileImporter(isPresented: $isImportingOPML, allowedContentTypes: OPMLDocument.contentTypes) { result in
            guard case .success(let url) = result else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                model.statusMessage = "That file couldn't be opened."
                return
            }
            Task { _ = await model.importOPML(data) }
        }
        .confirmationDialog("Remove downloads of played episodes?", isPresented: $isConfirmingDeletePlayed, titleVisibility: .visible) {
            Button("Remove Played Downloads", role: .destructive) {
                Task {
                    let count = await model.deletePlayedDownloads()
                    model.statusMessage = count == 0 ? "No played downloads to remove." : "Removed \(count) downloads."
                }
            }
        }
        .tint(theme.amber)
    }

    private var keyFingerprint: String {
        "\(model.apiKeyDraft.count)-\(model.apiKeyDraft.hashValue)-\(model.typeSafeKeyDraft.hashValue)-\(model.openRouterKeyDraft.hashValue)"
    }

    // MARK: Sections

    private var statsSection: some View {
        let stats = model.library.stats
        return Section {
            if stats.secondsListened < 60 && stats.adsSkipped == 0 {
                Label("Your listening time and skipped ads will show up here.", systemImage: "chart.bar")
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 0) { statTiles(stats) }
                    VStack(alignment: .leading, spacing: 12) { statTiles(stats) }
                }
                .padding(.vertical, 6)
            }
        }
        .listRowBackground(theme.backgroundCard)
    }

    @ViewBuilder
    private func statTiles(_ stats: ListeningStats) -> some View {
        StatTile(value: stats.secondsListened.shortDuration, label: "listened", color: theme.amber)
        StatTile(value: stats.secondsSkippedAds.shortDuration, label: "of ads skipped", color: theme.teal)
        StatTile(value: "\(stats.adsSkipped)", label: stats.adsSkipped == 1 ? "ad break" : "ad breaks", color: theme.teal)
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            HStack(spacing: 12) {
                ForEach(AppTheme.allCases, id: \.self) { option in
                    ThemeSwatch(theme: option.theme, isSelected: selectedTheme == option.rawValue) {
                        selectedTheme = option.rawValue
                    }
                }
            }
            .padding(.vertical, 6)
        }
        .listRowBackground(theme.backgroundCard)
    }

    private var playbackSection: some View {
        Section {
            Picker("Skip forward", selection: $model.library.playback.skipForwardSeconds) {
                ForEach(Self.skipIntervals, id: \.self) { Text("\($0) seconds").tag($0) }
            }
            Picker("Skip back", selection: $model.library.playback.skipBackSeconds) {
                ForEach(Self.skipIntervals, id: \.self) { Text("\($0) seconds").tag($0) }
            }
            Stepper(value: Binding(
                get: { model.library.playback.speed },
                set: { model.setDefaultSpeed($0) }
            ), in: PlaybackPreferences.speedRange, step: 0.1) {
                LabeledContent("Default speed", value: model.library.playback.speed.speedLabel)
            }
            Toggle("Play Up Next automatically", isOn: $model.library.playback.autoPlayNext)
            Toggle("Check for new episodes on launch", isOn: $model.library.playback.refreshOnLaunch)
            Toggle("Remove downloads after playing", isOn: $model.library.playback.removeDownloadsWhenPlayed)
        } header: {
            Text("Playback")
        } footer: {
            Text("Each show can set its own speed and skip its intro or outro from its settings.")
        }
        .listRowBackground(theme.backgroundCard)
    }

    private var adSkipSection: some View {
        Section {
            Toggle("Skip ads automatically", isOn: $model.settings.autoSkipEnabled)
                .tint(theme.teal)
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Skip when confidence is at least") {
                    Text(model.settings.adSkipConfidenceThreshold.formatted(.percent.precision(.fractionLength(0))))
                        .monospacedDigit()
                        .foregroundStyle(theme.teal)
                }
                Slider(value: $model.settings.adSkipConfidenceThreshold, in: 0.5...0.95, step: 0.01)
                    .tint(theme.teal)
                    .accessibilityLabel("Skip confidence threshold")
            }
        } header: {
            Text("Ad skipping")
        } footer: {
            Text("A lower threshold skips more, but may skip parts of the show. You can always undo a skip.")
        }
        .listRowBackground(theme.backgroundCard)
    }

    private var analysisSection: some View {
        Section {
            Toggle("Find ads in downloads", isOn: $model.settings.aiAnalysisEnabled)
                .tint(theme.teal)
            if model.settings.aiAnalysisEnabled {
                Toggle("Start as soon as a download finishes", isOn: $model.settings.analyzeAfterDownload)
                    .tint(theme.teal)
            }

            if model.settings.aiAnalysisEnabled {
                Picker("Transcription", selection: $model.settings.aiTranscriptionProvider) {
                    ForEach(AITranscriptionProviderKind.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                transcriptionDetail

                Picker("Ad detection", selection: $model.settings.aiClassificationProvider) {
                    ForEach(AIClassificationProviderKind.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                classificationDetail

                if model.needsOpenAIKey {
                    keyField("OpenAI API key", prompt: "sk-…", text: $model.apiKeyDraft)
                }
                if model.needsTypeSafeKey {
                    keyField("TypeSafe API key", prompt: "API key", text: $model.typeSafeKeyDraft)
                }
                if model.needsOpenRouterKey {
                    keyField("OpenRouter API key", prompt: "API key", text: $model.openRouterKeyDraft)
                }
            }
        } header: {
            Text("Ad analysis")
        } footer: {
            if model.settings.aiAnalysisEnabled {
                if !model.needsOpenAIKey && !model.needsTypeSafeKey && !model.needsOpenRouterKey {
                    Text("Runs entirely on this device. No API key needed.")
                } else {
                    Text("Keys are stored in the Keychain. Audio or transcript text goes only to the services you pick here.")
                }
            } else {
                Text("Transcribes downloaded episodes and marks ad breaks so they can be skipped.")
            }
        }
        .listRowBackground(theme.backgroundCard)
    }

    @ViewBuilder
    private var transcriptionDetail: some View {
        switch model.settings.aiTranscriptionProvider {
        case .appleSpeech:
            DetailNote(symbol: "waveform", text: model.appleSpeechAvailabilityMessage)
                .task { await model.refreshAppleSpeechModelStatus() }
        case .localWhisper:
            Picker("Whisper model", selection: $model.settings.whisperModelSize) {
                ForEach(WhisperModelSize.allCases, id: \.self) { size in
                    Text(size.shortName).tag(size)
                }
            }
            .pickerStyle(.segmented)
            DetailNote(
                symbol: model.selectedWhisperModelIsDownloaded ? "checkmark.circle.fill" : "arrow.down.circle",
                text: "\(model.selectedWhisperModelIsDownloaded ? "Downloaded" : "Downloads on first use"). \(model.settings.whisperModelSize.storageDescription), \(model.settings.whisperModelSize.speedDescription.lowercased())."
            )
            .task(id: model.settings.whisperModelSize) {
                await model.refreshSelectedWhisperModelStatus()
            }
        case .openAI:
            EmptyView()
        }
    }

    @ViewBuilder
    private var classificationDetail: some View {
        if model.settings.aiClassificationProvider == .appleFoundationModels {
            DetailNote(symbol: "cpu", text: model.appleFoundationModelsAvailabilityMessage)
        } else if model.needsTypeSafeKey || model.needsOpenRouterKey {
            DetailNote(symbol: "text.magnifyingglass", text: "Jev checks short transcript passages for ads. Only transcript text is sent; skip times come from your audio.")
        }
    }

    private var librarySection: some View {
        Section {
            Button {
                isImportingOPML = true
            } label: {
                Label("Import Subscriptions (OPML)", systemImage: "square.and.arrow.down")
            }
            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("Export Subscriptions (OPML)", systemImage: "square.and.arrow.up")
                }
            }
            LabeledContent("Downloads", value: "\(model.downloadedEpisodes.count) episodes, \(model.downloadsSizeDescription)")
            Button("Remove Played Downloads", role: .destructive) {
                isConfirmingDeletePlayed = true
            }
        } header: {
            Text("Library")
        } footer: {
            Text("OPML moves your subscriptions to or from apps like Pocket Casts or Overcast.")
        }
        .listRowBackground(theme.backgroundCard)
        .task(id: model.feeds.count) {
            exportURL = model.feeds.isEmpty ? nil : try? model.exportOPMLFile()
        }
    }

    private func keyField(_ title: String, prompt: String, text: Binding<String>) -> some View {
        LabeledContent(title) {
            SecureField(title, text: text, prompt: Text(prompt))
                .secretEntryStyle()
                .multilineTextAlignment(.trailing)
                .font(.subheadline.monospaced())
        }
    }
}

private struct StatTile: View {
    @Environment(\.appTheme) private var theme
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
                .fontDesign(.rounded)
                .foregroundStyle(color)
                .fixedSize()
            Text(label)
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
                .fixedSize()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct ThemeSwatch: View {
    let theme: TurtleTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(theme.backgroundPrimary)
                    HStack(spacing: 4) {
                        Circle().fill(theme.amber).frame(width: 14, height: 14)
                        Capsule().fill(theme.teal).frame(width: 22, height: 6)
                    }
                    .padding(10)
                }
                .frame(height: 56)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isSelected ? theme.amber : theme.textTertiary.opacity(0.4), lineWidth: isSelected ? 2 : 0.5)
                )
                Text(theme.name)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("\(theme.name) theme")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct DetailNote: View {
    @Environment(\.appTheme) private var theme
    let symbol: String
    let text: String

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(theme.teal)
        }
        .font(.footnote)
        .foregroundStyle(theme.textSecondary)
    }
}

private extension AIClassificationProviderKind {
    var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .appleFoundationModels: "Apple on-device"
        case .jevTypeSafe: "Jev via TypeSafe"
        case .jevOpenRouter: "Jev via OpenRouter"
        }
    }
}

private extension AITranscriptionProviderKind {
    var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .localWhisper: "Whisper on device"
        case .appleSpeech: "Apple Speech"
        }
    }
}

private extension WhisperModelSize {
    var shortName: String {
        switch self {
        case .tiny: "Tiny"
        case .base: "Base"
        case .small: "Small"
        }
    }

    var storageDescription: String {
        switch self {
        case .tiny: "About 39 MB"
        case .base: "About 142 MB"
        case .small: "About 462 MB"
        }
    }

    var speedDescription: String {
        switch self {
        case .tiny: "Fastest"
        case .base: "Balanced"
        case .small: "Slower, more accurate"
        }
    }
}
