import Foundation
import Observation

/// Developer-facing server endpoints. Nothing connects to these in M1; later
/// milestones read them for the HTTP API client and the LiveKit fallback URL.
@MainActor
@Observable
final class DebugSettings {
    enum Keys {
        static let apiBaseURL = "walkie.debug.apiBaseURL"
        static let liveKitURL = "walkie.debug.liveKitURL"
    }

    enum Defaults {
        /// The web walkie API server (`npm run dev:all`). `127.0.0.1` only reaches the
        /// Mac from the Simulator; on a physical device use `http://<mac-lan-ip>:8787`.
        static let apiBaseURL = "http://127.0.0.1:8787"
        /// Used only when the API does not hand back a LiveKit URL.
        static let liveKitURL = "ws://127.0.0.1:7880"
    }

    var apiBaseURL: String {
        didSet { defaults.set(apiBaseURL, forKey: Keys.apiBaseURL) }
    }

    var liveKitURL: String {
        didSet { defaults.set(liveKitURL, forKey: Keys.liveKitURL) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        apiBaseURL = defaults.string(forKey: Keys.apiBaseURL) ?? Defaults.apiBaseURL
        liveKitURL = defaults.string(forKey: Keys.liveKitURL) ?? Defaults.liveKitURL
    }

    var apiBaseURLValue: URL? { Self.parse(apiBaseURL, schemes: ["http", "https"]) }
    var liveKitURLValue: URL? { Self.parse(liveKitURL, schemes: ["ws", "wss"]) }

    var isAPIBaseURLValid: Bool { apiBaseURLValue != nil }
    var isLiveKitURLValid: Bool { liveKitURLValue != nil }

    func resetToDefaults() {
        apiBaseURL = Defaults.apiBaseURL
        liveKitURL = Defaults.liveKitURL
    }

    nonisolated static func parse(_ raw: String, schemes: Set<String>) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(), schemes.contains(scheme),
              let host = components.host, !host.isEmpty
        else { return nil }
        return components.url
    }
}
