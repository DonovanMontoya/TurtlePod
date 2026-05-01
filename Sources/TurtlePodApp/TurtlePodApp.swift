import SwiftUI
import TurtlePodCore

@main
struct TurtlePodApp: App {
    @StateObject private var model = TurtlePodModel.makeDefault()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .task {
                    await model.load()
                }
        }
    }
}
