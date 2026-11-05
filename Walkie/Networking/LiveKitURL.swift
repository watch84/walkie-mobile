import Foundation

enum LiveKitURL {
    /// Resolves the `url` from `/token`. The web app gets a relative path (`/livekit`) that its
    /// dev server proxies; a native client has no page origin, so relative or empty values fall
    /// back to the configured LiveKit URL. `http(s)` is mapped to `ws(s)`.
    static func resolve(_ raw: String, fallback: URL?) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let host = components.host, !host.isEmpty
        else { return fallback }

        switch scheme {
        case "ws", "wss": break
        case "http": components.scheme = "ws"
        case "https": components.scheme = "wss"
        default: return fallback
        }
        return components.url ?? fallback
    }
}
