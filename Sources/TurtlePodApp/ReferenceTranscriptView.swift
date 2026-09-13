import SwiftUI
import UniformTypeIdentifiers
import TurtlePodCore

struct ReferenceTranscriptView: View {
    @EnvironmentObject private var model: TurtlePodModel
    @Environment(\.appTheme) private var theme
    let episode: PodcastEpisode
    @State private var transcriptURL = ""
    @State private var importing = false
    @State private var importError: String?

    private var isBusy: Bool { model.busyEpisodeIDs.contains(episode.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Reference Transcript", systemImage: "text.alignleft")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.textPrimary)
            Text("Use a publisher transcript or import one exported from your podcast app. TurtlePod compares it with your downloaded audio to look for inserted sections.")
                .font(.caption)
                .foregroundStyle(theme.textSecondary)

            if let reference = episode.referenceTranscript {
                HStack {
                    Label(reference.source.label, systemImage: "checkmark.circle")
                    Spacer()
                    Button("Remove", role: .destructive) {
                        Task { await model.removeReference(episodeID: episode.id) }
                    }
                    .disabled(isBusy)
                }
                .font(.caption)
                DisclosureGroup("Read transcript") {
                    ScrollView {
                        Text(reference.text)
                            .font(.caption)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 260)
                }
            }

            Button("Find Publisher Transcript") {
                importError = nil
                Task { await model.fetchReference(episode.id) }
            }
            .disabled(isBusy)
            HStack {
                TextField("Direct transcript URL", text: $transcriptURL)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                Button("Fetch") {
                    importError = nil
                    Task { await model.fetchReference(episode.id, urlString: transcriptURL) }
                }
                .disabled(isBusy || transcriptURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Button("Import Transcript File") { importing = true }
                .disabled(isBusy)
            Text("VTT, SRT, Podcast Index JSON, HTML, or TXT. Episode sharing links are not transcript URLs.")
                .font(.caption2)
                .foregroundStyle(theme.textTertiary)

            if let message = importError ?? model.referenceMessages[episode.id] {
                Text(message).font(.caption).foregroundStyle(theme.textSecondary)
            }
            if let comparison = episode.analysis.referenceComparison {
                if comparison.isReliable {
                    Text("Reference matched · \(comparison.candidates.count) possible inserted sections")
                        .font(.caption.weight(.medium))
                    Text("These are comparison hints. Only ads confirmed by audio analysis are skipped.")
                        .font(.caption2).foregroundStyle(theme.textSecondary)
                    ForEach(Array(comparison.candidates.enumerated()), id: \.offset) { _, gap in
                        Text("\(gap.start.formattedDuration) – \(gap.end.formattedDuration)")
                            .font(.caption.monospacedDigit())
                    }
                } else {
                    Text("The reference did not match closely enough. Ad analysis used the downloaded audio without reference hints.")
                        .font(.caption).foregroundStyle(theme.textSecondary)
                }
            }
        }
        .tint(theme.teal)
        .turtleCard()
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= ReferenceTranscriptParser.maximumBytes else { throw ReferenceTranscriptError.tooLarge }
                let data = try Data(contentsOf: url)
                importError = nil
                Task { await model.importReference(data, fileURL: url, episodeID: episode.id) }
            } catch { importError = error.localizedDescription }
        }
    }
}
