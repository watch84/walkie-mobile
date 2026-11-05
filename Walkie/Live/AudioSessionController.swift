import AVFoundation
import LiveKit
import os

enum AudioSessionController {
    /// Called from the tune-in tap. `.playAndRecord` now so push-to-talk (M3) won't need a
    /// category switch; this does not prompt for the microphone.
    @MainActor
    static func activate() {
        // LiveKit would otherwise pick `.playback` while only listening and override this.
        AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = false

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            Log.audio.error("Audio session activation failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
