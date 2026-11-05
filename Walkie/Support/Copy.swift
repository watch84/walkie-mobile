import Foundation

/// User-facing strings. Keep in sync with the web client's `src/radio/RadioApp.tsx`.
enum Copy {
    static let brand = "walkie"

    enum Naming {
        static let title = "What should people hear you as?"
        static let placeholder = "Display name"
        static let hint = "Shown to everyone on the channel. No account, stored on this device only."
        static let submit = "Continue"
    }

    enum TuneIn {
        static let title = "Tap to tune in"
        /// The web hint is about browser autoplay; this is the native equivalent.
        static let hint = "One tap starts sound and connects you."
    }

    enum Radio {
        static func you(_ name: String) -> String { "You: \(name)" }
        static let tuningIn = "Tuning in…"
        static let reconnecting = "Reconnecting…"
        static let live = "Live"
        static let noSignal = "No signal. Retrying…"
        static let offAir = "Channel off air"
        static let onAir = "On air"
        static let quiet = "Quiet on the channel"
        static let youreOnAir = "You’re on air"
        static let mute = "Mute"
        static let unmute = "Unmute"
        static let report = "Report"
        static let reported = "Reported"
        static func muteHint(_ name: String) -> String { "Touch and hold to mute or unmute \(name) for you" }
        static let comingSoon = "Coming soon"
        static let dialLabel = "Station"
        static func dialValue(_ station: Station) -> String {
            station.isLocked
                ? "\(station.frequency), \(station.name), \(comingSoon)"
                : "\(station.frequency), \(station.name)"
        }
        static func listeners(_ count: Int) -> String { count == 1 ? "1 listening" : "\(count) listening" }
    }

    enum Talk {
        static let ready = "Hold to talk"
        static let keying = "Keying up…"
        static let live = "On air"
        static let busy = "Channel busy"
        static let offAir = "Channel off air"
        static let tuning = "Tuning in…"
        static let locked = "Coming soon"
        static let noSignal = "No signal"
        static let hint = "Hold to talk. Release to listen."

        static let micBlocked = "Microphone blocked. Allow it in Settings."
        static let keyUpFailed = "Couldn't key up. Try again."
        static let transmissionEnded = "Transmission ended"

        static func secondsLeft(_ seconds: Int) -> String { "\(seconds)s" }

        static func flash(_ flash: TalkController.Flash) -> String {
            switch flash {
            case .micBlocked: micBlocked
            case .busy: busy
            case .offAir: offAir
            case .keyUpFailed: keyUpFailed
            case .transmissionEnded: transmissionEnded
            case .muted(let name): "Muted \(name) for you"
            case .unmuted(let name): "Unmuted \(name)"
            case .reported(let name): "Reported \(name). Thanks."
            case .reportFailed: "Report failed. Try again."
            }
        }
    }

    enum Debug {
        static let title = "Debug settings"
        static let apiSection = "API base URL"
        static let liveKitSection = "LiveKit URL (fallback)"
        static let apiFooter = "Simulator: http://127.0.0.1:8787. Physical device: http://<mac-lan-ip>:8787 (same Wi-Fi as the Mac)."
        static let liveKitFooter = "Only used if the API doesn't return a LiveKit URL. Simulator: ws://127.0.0.1:7880. Device: ws://<mac-lan-ip>:7880."
        static let invalidHTTP = "Must be an http:// or https:// URL with a host."
        static let invalidWS = "Must be a ws:// or wss:// URL with a host."
        static let reset = "Reset to defaults"
        static let resetName = "Forget display name"
        static let done = "Done"
        static let nothingConnects = "No network connections are made in this build."
    }
}
