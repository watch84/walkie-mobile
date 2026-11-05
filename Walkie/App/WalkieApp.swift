import SwiftUI
import UIKit

@main
struct WalkieApp: App {
    @State private var model = AppModel(dependencies: .live)
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(model.profile)
                .environment(model.debug)
                .preferredColorScheme(.dark)
                .tint(Theme.amber)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
                    model.appWillResignActive()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.appWillResignActive() }
        }
    }
}
