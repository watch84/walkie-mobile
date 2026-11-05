import SwiftUI

@main
struct WalkieApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(model.profile)
                .environment(model.debug)
                .preferredColorScheme(.dark)
                .tint(Theme.amber)
        }
    }
}
