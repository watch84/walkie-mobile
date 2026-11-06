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

    /// Build-time defaults come from `WALKIE_API_BASE_URL` / `WALKIE_LIVEKIT_URL` in the
    /// xcconfigs (via Info.plist), so `Configs/Local.xcconfig` can point a build at a local backend.
    enum Defaults {
        /// The live web walkie API server. Must match `Configs/Base.xcconfig`.
        static let builtInAPIBaseURL = "https://walkie-radial.fly.dev"
        /// Used when `/token` returns a relative LiveKit URL (the web app's `/livekit` proxy).
        static let builtInLiveKitURL = "wss://walkie-pfv6bw45.livekit.cloud"

        static let apiBaseURL = infoValue("WalkieAPIBaseURL") ?? builtInAPIBaseURL
        static let liveKitURL = infoValue("WalkieLiveKitURL") ?? builtInLiveKitURL

        private static func infoValue(_ key: String) -> String? {
            guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty || trimmed.hasPrefix("$(") ? nil : trimmed
        }
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
