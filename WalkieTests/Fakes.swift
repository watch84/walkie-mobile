import Foundation
@testable import Walkie

enum FloorCall: Equatable, Sendable {
    case request(FloorCredentials)
    case release(FloorCredentials)
}

actor FakeAPI: WalkieAPIClient {
    private var queue: [Result<TokenResponse, WalkieAPIError>]
    private var floorResults: [Result<Void, WalkieAPIError>]
    private(set) var requests: [TokenRequest] = []
    private(set) var floorCalls: [FloorCall] = []
    private var floorDelay: Duration = .zero
    private var tokenDelay: Duration = .zero

    init(_ queue: [Result<TokenResponse, WalkieAPIError>], floor: [Result<Void, WalkieAPIError>] = [.success(())]) {
        self.queue = queue
        floorResults = floor
    }

    func setFloorDelay(_ delay: Duration) {
        floorDelay = delay
    }

    func setTokenDelay(_ delay: Duration) {
        tokenDelay = delay
    }

    func token(channel: String, name: String) async throws -> TokenResponse {
        requests.append(TokenRequest(channel: channel, name: name))
        if tokenDelay > .zero { try? await Task.sleep(for: tokenDelay) }
        let next = queue.count > 1 ? queue.removeFirst() : queue[0]
        return try next.get()
    }

    func requestFloor(_ credentials: FloorCredentials) async throws {
        floorCalls.append(.request(credentials))
        if floorDelay > .zero { try? await Task.sleep(for: floorDelay) }
        let next = floorResults.count > 1 ? floorResults.removeFirst() : floorResults[0]
        try next.get()
    }

    func releaseFloor(_ credentials: FloorCredentials) async throws {
        floorCalls.append(.release(credentials))
    }
}

@MainActor
final class FakeMicrophone: MicrophoneAuthorizing {
    var permission: MicrophonePermission
    var grantOnRequest: Bool
    private(set) var requestCount = 0

    init(_ permission: MicrophonePermission = .granted, grantOnRequest: Bool = true) {
        self.permission = permission
        self.grantOnRequest = grantOnRequest
    }

    func request() async -> Bool {
        requestCount += 1
        try? await Task.sleep(for: .milliseconds(5))
        permission = grantOnRequest ? .granted : .denied
        return grantOnRequest
    }
}

@MainActor
final class FakeChirps: ChirpPlaying {
    private(set) var starts = 0
    private(set) var ends = 0
    func playStart() { starts += 1 }
    func playEnd() { ends += 1 }
}

@MainActor
final class FakeTransport: RoomTransport {
    private(set) var connectedURL: URL?
    private(set) var token: String?
    private(set) var disconnected = false
    private(set) var micStates: [Bool] = []
    var micError: (any Error)?
    private var onEvent: RoomEventHandler?
    var initialMetadata: String?
    var initialCount = 1
    var connectDelay: Duration = .zero

    func connect(url: URL, token: String, onEvent: @escaping RoomEventHandler) async throws {
        if connectDelay > .zero { try? await Task.sleep(for: connectDelay) }
        connectedURL = url
        self.token = token
        self.onEvent = onEvent
        onEvent(.metadata(initialMetadata))
        onEvent(.participantCount(initialCount))
    }

    func disconnect() async {
        disconnected = true
    }

    func setMicrophone(enabled: Bool) async throws {
        if enabled, let micError { throw micError }
        micStates.append(enabled)
    }

    func emit(_ event: RoomEvent) {
        onEvent?(event)
    }
}

@MainActor
final class TransportFactory {
    private(set) var made: [FakeTransport] = []
    var configure: (FakeTransport) -> Void = { _ in }
    var connectDelay: Duration = .zero

    func make() -> any RoomTransport {
        let transport = FakeTransport()
        transport.connectDelay = connectDelay
        configure(transport)
        made.append(transport)
        return transport
    }

    var last: FakeTransport? { made.last }
}

func makeToken(url: String = "/livekit", name: String = "Ada") -> TokenResponse {
    TokenResponse(url: url, token: "jwt-\(name)", identity: "id-\(name)", name: name, key: "k-\(name)")
}

/// Server-shaped room metadata: `{ floor, offAir, seq }`.
func metaJSON(seq: Int, floor: (identity: String, name: String)? = nil, offAir: Bool = false) -> String {
    let floorJSON = floor.map {
        #"{"identity":"\#($0.identity)","name":"\#($0.name)","since":1730000000000,"expiresAt":1730000030000}"#
    } ?? "null"
    return #"{"floor":\#(floorJSON),"offAir":\#(offAir),"seq":\#(seq)}"#
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

/// Like `waitUntil`, for conditions that need to `await` (e.g. reading actor state).
@MainActor
func eventually(timeout: Duration = .seconds(2), _ condition: () async -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while !(await condition()) {
        if clock.now > deadline { return false }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return true
}

@MainActor
final class FakeSounds: SoundBedPlaying {
    private(set) var beds: [SoundBed] = []
    private(set) var clicks = 0
    func setBed(_ bed: SoundBed) { beds.append(bed) }
    func playDetentClick() { clicks += 1 }
}

@MainActor
final class FakeHaptics: HapticsPlaying {
    private(set) var detents = 0
    func detent() { detents += 1 }
}

let fastTiming = Tuner.Timing(debounce: .milliseconds(30), offAirRetry: .milliseconds(60), retry: .milliseconds(40))

func stationIndex(_ channelID: String) -> Int {
    Stations.all.firstIndex { $0.channel?.id == channelID }!
}
