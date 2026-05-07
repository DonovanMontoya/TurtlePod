import SwiftUI
import TurtlePodCore

struct SettingsView: View {
    @EnvironmentObject private var model: TurtlePodModel
    @Environment(\.appTheme) private var theme

    var body: some View {
        ZStack {
            theme.backgroundPrimary.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    // AI Section
                    VStack(alignment: .leading, spacing: 14) {
                        SectionLabel(title: "AI", icon: "sparkles")

                        HStack {
                            Text("Enable AI analysis")
                                .font(.subheadline)
                                .foregroundStyle(theme.textPrimary)
                            Spacer()
                            Toggle("", isOn: $model.settings.aiAnalysisEnabled)
                                .tint(theme.teal)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Ad detection model")
                                .font(.caption)
                                .foregroundStyle(theme.textTertiary)

                            Picker("Ad detection model", selection: $model.settings.aiClassificationProvider) {
                                ForEach(AIClassificationProviderKind.allCases, id: \.self) { provider in
                                    Text(provider.displayName)
                                        .tag(provider)
                                }
                            }
                            .pickerStyle(.segmented)

                            if model.settings.aiClassificationProvider == .appleFoundationModels {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "cpu")
                                        .font(.caption)
                                        .foregroundStyle(theme.teal)
                                        .frame(width: 16)
                                    Text(model.appleFoundationModelsAvailabilityMessage)
                                        .font(.caption)
                                        .foregroundStyle(theme.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(theme.backgroundElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Transcription model")
                                .font(.caption)
                                .foregroundStyle(theme.textTertiary)

                            Picker("Transcription model", selection: $model.settings.aiTranscriptionProvider) {
                                ForEach(AITranscriptionProviderKind.allCases, id: \.self) { provider in
                                    Text(provider.displayName)
                                        .tag(provider)
                                }
                            }
                            .pickerStyle(.segmented)

                            if model.settings.aiTranscriptionProvider == .localWhisper {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Whisper model size")
                                        .font(.caption)
                                        .foregroundStyle(theme.textTertiary)

                                    Picker("Model size", selection: $model.settings.whisperModelSize) {
                                        ForEach(WhisperModelSize.allCases, id: \.self) { size in
                                            Text(size.displayName)
                                                .tag(size)
                                        }
                                    }
                                    .pickerStyle(.segmented)

                                    HStack(alignment: .center, spacing: 8) {
                                        Image(systemName: model.selectedWhisperModelIsDownloaded ? "checkmark.circle.fill" : "arrow.down.circle")
                                            .font(.caption)
                                            .foregroundStyle(model.selectedWhisperModelIsDownloaded ? theme.teal : theme.amberMuted)
                                            .frame(width: 16)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(model.selectedWhisperModelIsDownloaded ? "Model downloaded" : "Downloads on first analysis")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(theme.textPrimary)
                                            Text("\(model.settings.whisperModelSize.storageDescription) • \(model.settings.whisperModelSize.speedDescription)")
                                                .font(.caption)
                                                .foregroundStyle(theme.textSecondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }

                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(theme.backgroundElevated)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))

                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "cpu")
                                            .font(.caption)
                                            .foregroundStyle(theme.teal)
                                            .frame(width: 16)
                                        Text("Model downloads on first use. Larger models are more accurate but slower and use more memory.")
                                            .font(.caption)
                                            .foregroundStyle(theme.textSecondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(theme.backgroundElevated)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .task(id: model.settings.whisperModelSize) {
                                    await model.refreshSelectedWhisperModelStatus()
                                }
                            }
                        }

                        if model.needsOpenAIKey {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("OpenAI API Key")
                                    .font(.caption)
                                    .foregroundStyle(theme.textTertiary)
                                SecureField("sk-...", text: $model.apiKeyDraft)
                                    .secretEntryStyle()
                                    .font(.subheadline.monospaced())
                                    .foregroundStyle(theme.textPrimary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(theme.backgroundElevated)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(theme.textTertiary.opacity(0.2), lineWidth: 0.5)
                                    )
                            }
                        } else {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "checkmark.shield")
                                    .font(.caption)
                                    .foregroundStyle(theme.teal)
                                    .frame(width: 16)
                                Text("Fully local — no API key required.")
                                    .font(.caption)
                                    .foregroundStyle(theme.textSecondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(theme.backgroundElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .turtleCard()

                    // Ad Skip Section
                    VStack(alignment: .leading, spacing: 14) {
                        SectionLabel(title: "Ad Skip", icon: "forward.end")

                        HStack {
                            Text("Auto-skip ads")
                                .font(.subheadline)
                                .foregroundStyle(theme.textPrimary)
                            Spacer()
                            Toggle("", isOn: $model.settings.autoSkipEnabled)
                                .tint(theme.teal)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Confidence threshold")
                                    .font(.subheadline)
                                    .foregroundStyle(theme.textPrimary)
                                Spacer()
                                Text("\(Int(model.settings.adSkipConfidenceThreshold * 100))%")
                                    .font(.subheadline.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(theme.amber)
                            }
                            Slider(value: $model.settings.adSkipConfidenceThreshold, in: 0.5...0.95, step: 0.01)
                                .tint(theme.amber)
                        }
                    }
                    .turtleCard()

                    // Save
                    Button {
                        Task { await model.saveSettings() }
                    } label: {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark")
                            Text("Save Settings")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                        }
                        .foregroundStyle(theme.backgroundPrimary)
                        .padding(14)
                        .background(theme.amber)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: theme.amber.opacity(0.25), radius: 8, y: 4)
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
            }
        }
        .navigationTitle("Settings")
        .turtleNavBarBackground(theme)
    }
}

private extension AIClassificationProviderKind {
    var displayName: String {
        switch self {
        case .openAI:
            "OpenAI"
        case .appleFoundationModels:
            "Apple On-Device"
        }
    }
}

private extension AITranscriptionProviderKind {
    var displayName: String {
        switch self {
        case .openAI:
            "OpenAI"
        case .localWhisper:
            "Local Whisper"
        }
    }
}

private extension WhisperModelSize {
    var storageDescription: String {
        switch self {
        case .tiny:
            "~39 MB"
        case .base:
            "~142 MB"
        case .small:
            "~462 MB"
        }
    }

    var speedDescription: String {
        switch self {
        case .tiny:
            "Fastest"
        case .base:
            "Balanced speed"
        case .small:
            "Slower, more accurate"
        }
    }
}

private struct SectionLabel: View {
    @Environment(\.appTheme) private var theme
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(theme.amberMuted)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.textTertiary)
                .textCase(.uppercase)
                .tracking(0.8)
        }
    }
}
