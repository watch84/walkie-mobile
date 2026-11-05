import Foundation
@testable import Walkie

actor FakeAPI: WalkieAPIClient {
    private var queue: [Result<TokenResponse, WalkieAPIError>]
    private(set) var requests: [TokenRequest] = []

    init(_ queue: [Result<TokenResponse, WalkieAPIError>]) {
        self.queue = queue
    }

    func token(channel: String, name: String) async throws -> TokenResponse {
        requests.append(TokenRequest(channel: channel, name: name))
        let next = queue.count > 1 ? queue.removeFirst() : queue[0]
        return try next.get()
    }
}

@MainActor
final class FakeTransport: RoomTransport {
    private(set) var connectedURL: URL?
    private(set) var token: String?
    private(set) var disconnected = false
    private var onEvent: RoomEventHandler?
    var initialMetadata: String?
    var initialCount = 1

    func connect(url: URL, token: String, onEvent: @escaping RoomEventHandler) async throws {
        connectedURL = url
        self.token = token
        self.onEvent = onEvent
        onEvent(.metadata(initialMetadata))
        onEvent(.participantCount(initialCount))
    }

    func disconnect() async {
        disconnected = true
    }

    func emit(_ event: RoomEvent) {
        onEvent?(event)
    }
}

@MainActor
final class TransportFactory {
    private(set) var made: [FakeTransport] = []
    var configure: (FakeTransport) -> Void = { _ in }

    func make() -> any RoomTransport {
        let transport = FakeTransport()
        configure(transport)
        made.append(transport)
        return transport
    }

    var last: FakeTransport? { made.last }
}

func makeToken(url: String = "/livekit", channel: String = "channel-1", name: String = "Ada") -> TokenResponse {
    TokenResponse(url: url, token: "jwt-\(channel)", identity: "id-\(name)", name: name, key: "k-\(name)", channel: channel)
}

func metaJSON(seq: Int, floor: (identity: String, name: String)? = nil) -> String {
    guard let floor else { return #"{"seq":\#(seq),"floor":null}"# }
    return #"{"seq":\#(seq),"floor":{"identity":"\#(floor.identity)","name":"\#(floor.name)","startedAt":1730000000000}}"#
}

@MainActor
func waitUntil(timeout: Duration = .seconds(2), _ condition: () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while !condition() {
        if clock.now > deadline { return false }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return true
}
