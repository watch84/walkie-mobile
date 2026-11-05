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
        static let placeholder = "Radio coming soon"
        static func you(_ name: String) -> String { "You: \(name)" }
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
