import SwiftUI

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
