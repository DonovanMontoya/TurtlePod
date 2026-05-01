import SwiftUI
import TurtlePodCore

struct RootView: View {
    @EnvironmentObject private var model: TurtlePodModel

    var body: some View {
        TabView {
            NavigationStack {
                LibraryView()
            }
            .tabItem {
                Label("Library", systemImage: "books.vertical")
            }

            NavigationStack {
                DownloadsView()
            }
            .tabItem {
                Label("Downloads", systemImage: "arrow.down.circle")
            }

            NavigationStack {
                PlayerView()
            }
            .tabItem {
                Label("Player", systemImage: "play.circle")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .overlay(alignment: .bottom) {
            if let event = model.activeSkipEvent {
                UndoSkipBanner(event: event)
                    .padding()
            }
        }
    }
}

private struct UndoSkipBanner: View {
    @EnvironmentObject private var model: TurtlePodModel
    let event: SkipEvent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "forward.end")
            Text("Skipped ad")
                .font(.callout.weight(.semibold))
            Spacer()
            Button("Undo") {
                Task { await model.undoLastSkip() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 8, y: 3)
    }
}
