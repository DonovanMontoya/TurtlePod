import SwiftUI
import TurtlePodCore

@main
struct TurtlePodApp: App {
    @StateObject private var model = TurtlePodModel.makeDefault()
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.ember.rawValue

    init() {
        // Artwork is fetched through URLSession.shared; give it room to cache.
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024, diskCapacity: 512 * 1024 * 1024)
    }

    private var activeTheme: TurtleTheme {
        (AppTheme(rawValue: selectedTheme) ?? .ember).theme
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environment(\.appTheme, activeTheme)
                .preferredColorScheme(activeTheme.colorScheme)
                .task { await model.load() }
        }
    }
}
