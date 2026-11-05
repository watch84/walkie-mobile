import Foundation

/// User-facing strings. Keep in sync with the web client's `src/radio/RadioApp.tsx`.
enum Copy {
    static let appName = "Walkie"

    enum Naming {
        static let title = "What should we call you?"
        static let placeholder = "Your name"
        static let submit = "Continue"
        static let tooLong = "Names can be up to \(DisplayName.maxLength) characters."
        static let empty = "Enter a name to continue."
    }

    enum TuneIn {
        static let action = "Tap to tune in"
        static func greeting(_ name: String) -> String { "Hi, \(name)" }
        static let changeName = "Change name"
    }

    enum Radio {
        static let placeholder = "Radio coming soon"
        static let tuneOut = "Tune out"
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
