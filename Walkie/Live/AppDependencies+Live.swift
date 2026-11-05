import Foundation
import os

extension AppDependencies {
    static var live: AppDependencies {
        AppDependencies(
            makeTransport: { LiveKitTransport() },
            makeAPI: { HTTPWalkieAPI(baseURL: $0) },
            activateAudio: { AudioSessionController.activate() },
            microphone: { SystemMicrophone() },
            chirps: { ToneChirps() },
            sounds: { RadioSoundEngine() },
            haptics: { DetentHaptics() }
        )
    }
}

enum Log {
    static let session = Logger(subsystem: "com.watch84.walkie", category: "session")
    static let audio = Logger(subsystem: "com.watch84.walkie", category: "audio")
}
