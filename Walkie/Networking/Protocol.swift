import Foundation

// Wire types mirroring the web client's `shared/protocol.ts`. Field names must match it exactly.

enum WalkieProtocol {
    /// `FLOOR_MAX_MS`: the server releases the floor after this long.
    static let floorMaxMs = 30_000

    enum ErrorCode {
        static let offAir = "off_air"
    }
}

struct TokenRequest: Codable, Equatable, Sendable {
    let channel: String
    let name: String
}

/// `/token` response: `{ token, url, identity, name, key }`. The server doesn't echo the channel,
/// so callers keep the channel they asked for.
struct TokenResponse: Codable, Equatable, Sendable {
    /// LiveKit server URL. May be relative (`/livekit`, the web app's Vite proxy); see `LiveKitURL`.
    let url: String
    let token: String
    let identity: String
    let name: String
    let key: String

    func floorCredentials(channel: String) -> FloorCredentials {
        FloorCredentials(channel: channel, identity: identity, name: name, key: key)
    }
}

/// Body for `POST /floor/request` and `/floor/release`.
struct FloorCredentials: Codable, Equatable, Sendable {
    let channel: String
    let identity: String
    let name: String
    let key: String
}

/// Body for `POST /report`: the reporter's credentials plus who is being reported.
struct ReportRequest: Codable, Equatable, Sendable {
    let channel: String
    let identity: String
    let name: String
    let key: String
    let reportedIdentity: String
    let reportedName: String

    init(credentials: FloorCredentials, reportedIdentity: String, reportedName: String) {
        channel = credentials.channel
        identity = credentials.identity
        name = credentials.name
        key = credentials.key
        self.reportedIdentity = reportedIdentity
        self.reportedName = reportedName
    }
}

struct FloorHolder: Codable, Equatable, Sendable {
    let identity: String
    let name: String
    /// Server epoch milliseconds.
    let since: Double
    /// Server epoch milliseconds; at most `since + FLOOR_MAX_MS`.
    let expiresAt: Double
}

/// LiveKit room metadata JSON (`{ floor, offAir, seq }`), written only by the server.
struct RoomMeta: Codable, Equatable, Sendable {
    let floor: FloorHolder?
    let offAir: Bool
    let seq: Int

    static func decode(_ metadata: String?) -> RoomMeta? {
        guard let data = metadata?.data(using: .utf8), !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(RoomMeta.self, from: data)
    }

    /// Metadata updates can arrive out of order; only a strictly newer `seq` may replace the current state.
    static func isFresh(_ incoming: RoomMeta, after current: RoomMeta?) -> Bool {
        guard let current else { return true }
        return incoming.seq > current.seq
    }
}

enum WalkieAPIError: Error, Equatable, Sendable {
    /// 403 with `code: "off_air"`.
    case offAir
    /// 409: someone else holds the floor.
    case busy
    /// 401: the `key` from `/token` was rejected.
    case badKey
    case http(status: Int, code: String?)
    case invalidResponse
    case network(String)

    private struct Body: Decodable {
        let code: String?
        let error: String?
    }

    /// Maps a non-2xx response to an error; returns nil for success statuses.
    static func from(status: Int, body: Data) -> WalkieAPIError? {
        guard !(200..<300).contains(status) else { return nil }
        let parsed = try? JSONDecoder().decode(Body.self, from: body)
        let code = parsed?.code ?? parsed?.error
        switch status {
        case 403 where code == WalkieProtocol.ErrorCode.offAir: return .offAir
        case 409: return .busy
        case 401: return .badKey
        default: return .http(status: status, code: code)
        }
    }
}
