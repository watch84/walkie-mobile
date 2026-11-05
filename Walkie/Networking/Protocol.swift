import Foundation

// Wire types mirroring the web client's `shared/protocol.ts`. Field names must match it exactly.

enum WalkieProtocol {
    /// `FLOOR_MAX_MS`: the server releases the floor after this long.
    static let floorMaxMs = 30_000

    enum ErrorCode {
        static let offAir = "off_air"
    }
}

struct ChannelInfo: Identifiable, Hashable, Sendable {
    let id: String
    let number: Int
    var name: String { "Channel \(number)" }

    static let live: [ChannelInfo] = (1...3).map { ChannelInfo(id: "channel-\($0)", number: $0) }
    static let defaultChannel = live[0]
}

struct TokenRequest: Codable, Equatable, Sendable {
    let channel: String
    let name: String
}

struct TokenResponse: Codable, Equatable, Sendable {
    /// LiveKit server URL. May be relative (`/livekit`, the web app's Vite proxy); see `LiveKitURL`.
    let url: String
    let token: String
    let identity: String
    let name: String
    let key: String
    let channel: String

    var floorCredentials: FloorCredentials {
        FloorCredentials(channel: channel, identity: identity, name: name, key: key)
    }
}

/// Body for `POST /floor/request`, `/floor/release` and `/report`.
struct FloorCredentials: Codable, Equatable, Sendable {
    let channel: String
    let identity: String
    let name: String
    let key: String
}

struct FloorHolder: Codable, Equatable, Sendable {
    let identity: String
    let name: String
    let startedAt: Double?
}

/// LiveKit room metadata JSON, written only by the server.
struct RoomMeta: Codable, Equatable, Sendable {
    let seq: Int
    let floor: FloorHolder?

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
