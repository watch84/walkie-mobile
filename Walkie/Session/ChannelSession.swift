import Foundation
import Observation

/// Connection to one channel: fetches a token, joins the room, and mirrors the server's room
/// metadata. Floor state comes only from `RoomMeta`, never from local guesses. Push-to-talk
/// (`TalkController`) publishes through this session once the server grants `canPublish`.
@MainActor
@Observable
final class ChannelSession {
    enum Phase: Equatable, Sendable {
        case idle
        case tuningIn
        case live
        case reconnecting
        case noSignal
        case offAir
    }

    struct Endpoint {
        let api: any WalkieAPIClient
        let liveKitFallback: URL?
    }

    typealias EndpointProvider = @MainActor () -> Endpoint?

    enum JoinError: Error, Equatable {
        case misconfigured
        case noLiveKitURL
        case notConnected
    }

    /// Room changes push-to-talk must react to.
    enum TalkSignal: Equatable, Sendable {
        case canPublish(Bool)
        case floorChanged(FloorHolder?)
        /// The room was left, replaced, or lost; any transmission in it is over.
        case roomReset
    }

    private(set) var phase: Phase = .idle
    private(set) var channel: ChannelInfo = .defaultChannel
    private(set) var name: String?
    private(set) var meta: RoomMeta?
    private(set) var listenerCount: Int?
    private(set) var speakingIdentities: Set<String> = []
    /// Token identity plus the channel this session asked for (the server doesn't echo it).
    private(set) var credentials: FloorCredentials?
    /// Server-granted publish permission for this device (floor holder only).
    private(set) var canPublish = false
    private(set) var lastError: String?

    /// The API client the current room was joined with, for floor requests.
    @ObservationIgnored private(set) var api: (any WalkieAPIClient)?
    @ObservationIgnored var onTalkSignal: (@MainActor (TalkSignal) -> Void)?

    var isFloorHeldByMe: Bool {
        guard let floor, let credentials else { return false }
        return floor.identity == credentials.identity
    }

    var isFloorHeldByOther: Bool {
        guard let floor else { return false }
        return floor.identity != credentials?.identity
    }

    var floor: FloorHolder? { meta?.floor }

    var isFloorHolderSpeaking: Bool {
        guard let floor else { return false }
        return speakingIdentities.contains(floor.identity)
    }

    /// True while joined, joining, or retrying `channel` as `name`.
    func isTuned(to channel: ChannelInfo, as name: String) -> Bool {
        phase != .idle && self.channel == channel && self.name == name
    }

    @ObservationIgnored private let makeTransport: @MainActor () -> any RoomTransport
    @ObservationIgnored private let retryDelay: Duration
    @ObservationIgnored private var endpoint: EndpointProvider?
    @ObservationIgnored private var transport: (any RoomTransport)?
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Bumped on every (re)tune so callbacks from superseded attempts are dropped.
    @ObservationIgnored private var generation = 0

    init(retryDelay: Duration = .seconds(10), makeTransport: @escaping @MainActor () -> any RoomTransport) {
        self.retryDelay = retryDelay
        self.makeTransport = makeTransport
    }

    func tune(to channel: ChannelInfo, name: String, endpoint: @escaping EndpointProvider) {
        self.channel = channel
        self.name = name
        self.endpoint = endpoint
        restart(afterDelay: false)
    }

    func setMicrophone(enabled: Bool) async throws {
        guard let transport else {
            if enabled { throw JoinError.notConnected }
            return
        }
        try await transport.setMicrophone(enabled: enabled)
    }

    func stop() async {
        generation += 1
        task?.cancel()
        task = nil
        let old = transport
        transport = nil
        resetRoomState()
        phase = .idle
        await old?.disconnect()
    }

    private func restart(afterDelay: Bool) {
        generation += 1
        let gen = generation
        task?.cancel()
        let old = transport
        transport = nil
        resetRoomState()
        if !afterDelay { phase = .tuningIn }

        task = Task { [weak self, retryDelay] in
            await old?.disconnect()
            if afterDelay {
                do { try await Task.sleep(for: retryDelay) } catch { return }
            }
            await self?.joinLoop(gen)
        }
    }

    private func joinLoop(_ gen: Int) async {
        while gen == generation, !Task.isCancelled {
            do {
                try await join(gen)
                return
            } catch {
                guard gen == generation, !Task.isCancelled else { return }
                if case WalkieAPIError.offAir = error {
                    phase = .offAir
                } else {
                    phase = .noSignal
                }
                lastError = String(describing: error)
            }
            do { try await Task.sleep(for: retryDelay) } catch { return }
        }
    }

    private func join(_ gen: Int) async throws {
        guard let endpoint = endpoint?(), let name else { throw JoinError.misconfigured }
        let channelID = channel.id
        let token = try await endpoint.api.token(channel: channelID, name: name)
        guard gen == generation else { throw CancellationError() }
        guard let url = LiveKitURL.resolve(token.url, fallback: endpoint.liveKitFallback) else {
            throw JoinError.noLiveKitURL
        }

        // Each room connection starts its own `seq` sequence.
        resetRoomState()
        let room = makeTransport()
        try await room.connect(url: url, token: token.token) { [weak self] event in
            self?.handle(event, gen: gen)
        }
        guard gen == generation, !Task.isCancelled else {
            await room.disconnect()
            throw CancellationError()
        }
        if meta?.offAir == true {
            await room.disconnect()
            throw WalkieAPIError.offAir
        }
        transport = room
        api = endpoint.api
        credentials = token.floorCredentials(channel: channelID)
        lastError = nil
        phase = .live
    }

    private func handle(_ event: RoomEvent, gen: Int) {
        guard gen == generation else { return }
        switch event {
        case .metadata(let raw):
            guard let incoming = RoomMeta.decode(raw), RoomMeta.isFresh(incoming, after: meta) else { return }
            let floorChanged = incoming.floor != meta?.floor
            meta = incoming
            if floorChanged { onTalkSignal?(.floorChanged(incoming.floor)) }
            // While joining, `join` checks `offAir` itself once connect returns.
            if incoming.offAir, transport != nil {
                phase = .offAir
                restart(afterDelay: true)
            }
        case .participantCount(let count):
            listenerCount = count
        case .speaking(let identities):
            speakingIdentities = identities
        case .publishPermission(let allowed):
            guard allowed != canPublish else { return }
            canPublish = allowed
            onTalkSignal?(.canPublish(allowed))
        case .reconnecting:
            if transport != nil { phase = .reconnecting }
        case .reconnected:
            if transport != nil { phase = .live }
        case .disconnected(let reason):
            // Failures during connect surface as thrown errors in `join`; only react once live.
            guard transport != nil else { return }
            lastError = reason
            phase = .noSignal
            restart(afterDelay: true)
        }
    }

    private func resetRoomState() {
        meta = nil
        listenerCount = nil
        speakingIdentities = []
        credentials = nil
        api = nil
        canPublish = false
        onTalkSignal?(.roomReset)
    }
}
