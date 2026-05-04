import SwiftUI
import TurtlePodCore

@main
struct TurtlePodApp: App {
    @StateObject private var model = TurtlePodModel.makeDefault()
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.ember.rawValue

    private var activeTheme: TurtleTheme {
        (AppTheme(rawValue: selectedTheme) ?? .ember).theme
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environment(\.appTheme, activeTheme)
                .environment(\.colorScheme, activeTheme.colorScheme)
                .task { await model.load() }
        }
    }
}
