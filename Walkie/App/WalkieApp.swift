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
                    releaseFloorBeforeSuspension()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { releaseFloorBeforeSuspension() }
        }
    }

    /// Ends any transmission and keeps the app alive (briefly) until `/floor/release` and the
    /// unpublish have gone out, instead of leaving the server to time the floor out.
    private func releaseFloorBeforeSuspension() {
        model.appWillResignActive()
        let task = BackgroundTask(name: "Release floor")
        Task { @MainActor in
            await model.finishPendingWork()
            task.end()
        }
    }
}

/// A UIKit background task that ends exactly once, on completion or expiry.
@MainActor
private final class BackgroundTask {
    private var id: UIBackgroundTaskIdentifier = .invalid

    init(name: String) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
