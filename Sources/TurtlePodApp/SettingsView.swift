import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: TurtlePodModel

    var body: some View {
        Form {
            Section("AI") {
                Toggle("Enable AI analysis", isOn: $model.settings.aiAnalysisEnabled)
                SecureField("OpenAI API key", text: $model.apiKeyDraft)
                    .secretEntryStyle()
            }

            Section("Ad Skip") {
                Toggle("Auto-skip ads", isOn: $model.settings.autoSkipEnabled)
                VStack(alignment: .leading) {
                    HStack {
                        Text("Confidence")
                        Spacer()
                        Text("\(Int(model.settings.adSkipConfidenceThreshold * 100))%")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $model.settings.adSkipConfidenceThreshold, in: 0.5...0.95, step: 0.01)
                }
            }

            Section {
                Button {
                    Task { await model.saveSettings() }
                } label: {
                    Label("Save Settings", systemImage: "checkmark")
                }
            }
        }
        .navigationTitle("Settings")
    }
}
