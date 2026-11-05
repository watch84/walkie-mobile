import AVFoundation
import LiveKit
import os

enum AudioSessionController {
    static var category: AVAudioSession.Category { .playAndRecord }
    static var options: AVAudioSession.CategoryOptions { [.defaultToSpeaker, .allowBluetooth] }

    /// Called from the tune-in tap and again after interruptions or resets. `.playAndRecord`
    /// with `.defaultToSpeaker` routes to the loudspeaker (not the earpiece) unless headphones or
    /// Bluetooth are connected. This does not prompt for the microphone.
    @MainActor
    static func activate() {
        // LiveKit would otherwise pick `.playback` while only listening and override this.
        AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = false

        let session = AVAudioSession.sharedInstance()
        do {
            if session.category != category || session.categoryOptions != options {
                try session.setCategory(category, mode: .default, options: options)
            }
            try session.setActive(true)
        } catch {
            Log.audio.error("Audio session activation failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Forwards interruptions, media-services resets, and category hijacks to `handler`.
    @MainActor
    static func observe(_ handler: @escaping @MainActor @Sendable (AudioSessionEvent) -> Void) {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()

        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let type = raw.flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            MainActor.assumeIsolated {
                switch type {
                case .began: handler(.interruptionBegan)
                case .ended: handler(.interruptionEnded)
                default: break
                }
            }
        })

        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main) { _ in
            MainActor.assumeIsolated { handler(.needsReactivation) }
        })

        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            let reason = raw.flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
            MainActor.assumeIsolated {
                // Re-assert only when something else changed the category; ordinary route
                // changes (headphones in/out) are left to `.defaultToSpeaker`.
                guard reason == .categoryChange || reason == .override,
                      AVAudioSession.sharedInstance().category != category
                else { return }
                handler(.needsReactivation)
            }
        })
    }

    @MainActor private static var observers: [NSObjectProtocol] = []
}
