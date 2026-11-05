import Foundation
import Observation

/// One room connection, opened and closed by `Tuner` (the web client's `openSession`). Mirrors the
/// server's room metadata: floor state comes only from `RoomMeta`, never from local guesses.
/// Push-to-talk (`TalkController`) publishes through it once the server grants `canPublish`.
@MainActor
@Observable
final class ChannelSession {
    enum EndReason: Equatable, Sendable {
        /// Fresh room metadata said `offAir: true`.
        case offAir
        case disconnected(String?)
    }

    enum OpenError: Error, Equatable {
        /// `close()` (or another `open`) superseded this one while it was connecting.
        case superseded
    }

    enum MicError: Error, Equatable {
        case notConnected
    }

    /// Room changes push-to-talk must react to.
    enum TalkSignal: Equatable, Sendable {
        case canPublish(Bool)
        case floorChanged(FloorHolder?)
        /// The room was left, replaced, or lost; any transmission in it is over.
        case roomReset
    }

    private(set) var channel: ChannelInfo?
    private(set) var isOpen = false
    private(set) var isReconnecting = false
    private(set) var meta: RoomMeta?
    private(set) var listenerCount: Int?
    private(set) var speakingIdentities: Set<String> = []
    /// Token identity plus the channel that was requested (the server doesn't echo it).
    private(set) var credentials: FloorCredentials?
    /// Server-granted publish permission for this device (floor holder only).
    private(set) var canPublish = false
    /// Identities muted on this device only. Kept across rooms and applied to each new one.
    private(set) var mutedIdentities: Set<String> = []
    /// The most recent other floor holder and when they released (nil while still holding).
    private(set) var lastSpeaker: FloorHolder?
    private(set) var lastSpeakerReleasedAt: Date?

    /// The API client the current room was joined with, for floor requests.
    @ObservationIgnored private(set) var api: (any WalkieAPIClient)?
    @ObservationIgnored var onTalkSignal: (@MainActor (TalkSignal) -> Void)?
    /// Called when an open room ends on its own (never for `close()`).
    @ObservationIgnored var onEnded: (@MainActor (EndReason) -> Void)?

    var floor: FloorHolder? { meta?.floor }

    var isFloorHolderSpeaking: Bool {
        guard let floor else { return false }
        return speakingIdentities.contains(floor.identity)
    }

    var isFloorHeldByMe: Bool {
        guard let floor, let credentials else { return false }
        return floor.identity == credentials.identity
    }

    var isFloorHeldByOther: Bool {
        guard let floor else { return false }
        return floor.identity != credentials?.identity
    }

    @ObservationIgnored private let makeTransport: @MainActor () -> any RoomTransport
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var transport: (any RoomTransport)?
    /// Bumped on every open/close so callbacks from superseded rooms are dropped.
    @ObservationIgnored private var generation = 0

    init(
        makeTransport: @escaping @MainActor () -> any RoomTransport,
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.makeTransport = makeTransport
        self.now = now
    }

    func isMuted(_ identity: String) -> Bool {
        mutedIdentities.contains(identity)
    }

    /// Local-only: stops (or resumes) playing `identity`'s audio on this device.
    func setMuted(_ muted: Bool, identity: String) {
        guard muted != isMuted(identity) else { return }
        if muted {
            mutedIdentities.insert(identity)
        } else {
            mutedIdentities.remove(identity)
        }
        let identities = mutedIdentities
        guard let transport else { return }
        Task { await transport.setMuted(identities) }
    }

    /// Connects to `url` with `token`. Throws `WalkieAPIError.offAir` if the room is already off
    /// air, or `OpenError.superseded` if `close()` was called meanwhile.
    func open(token: TokenResponse, channel: ChannelInfo, url: URL, api: any WalkieAPIClient) async throws {
        await close()
        generation += 1
        let gen = generation
        self.channel = channel

        let room = makeTransport()
        do {
            try await room.connect(url: url, token: token.token) { [weak self] event in
                self?.handle(event, gen: gen)
            }
        } catch {
            guard gen == generation else { throw OpenError.superseded }
            resetRoomState()
            throw error
        }
        guard gen == generation else {
            await room.disconnect()
            throw OpenError.superseded
        }
        if meta?.offAir == true {
            resetRoomState()
            await room.disconnect()
            throw WalkieAPIError.offAir
        }
        transport = room
        if !mutedIdentities.isEmpty { await room.setMuted(mutedIdentities) }
        self.api = api
        credentials = token.floorCredentials(channel: channel.id)
        isOpen = true
    }

    func close() async {
        await detach()?.disconnect()
    }

    /// Drops the room immediately (state reset, push-to-talk told); the disconnect finishes in
    /// the background.
    func closeNow() {
        guard let old = detach() else { return }
        Task { await old.disconnect() }
    }

    private func detach() -> (any RoomTransport)? {
        generation += 1
        let old = transport
        transport = nil
        resetRoomState()
        return old
    }

    func setMicrophone(enabled: Bool) async throws {
        guard let transport else {
            if enabled { throw MicError.notConnected }
            return
        }
        try await transport.setMicrophone(enabled: enabled)
    }

    private func handle(_ event: RoomEvent, gen: Int) {
        guard gen == generation else { return }
        switch event {
        case .metadata(let raw):
            guard let incoming = RoomMeta.decode(raw), RoomMeta.isFresh(incoming, after: meta) else { return }
            let previous = meta?.floor
            let floorChanged = incoming.floor != previous
            meta = incoming
            if floorChanged { trackSpeaker(previous: previous, current: incoming.floor) }
            if floorChanged { onTalkSignal?(.floorChanged(incoming.floor)) }
            // While connecting, `open` checks `offAir` itself once connect returns.
            if incoming.offAir, isOpen { end(.offAir) }
        case .participantCount(let count):
            listenerCount = count
        case .speaking(let identities):
            speakingIdentities = identities
        case .publishPermission(let allowed):
            guard allowed != canPublish else { return }
            canPublish = allowed
            onTalkSignal?(.canPublish(allowed))
        case .reconnecting:
            if isOpen { isReconnecting = true }
        case .reconnected:
            isReconnecting = false
        case .disconnected(let reason):
            // Failures while connecting surface as errors thrown from `open`.
            guard isOpen else { return }
            end(.disconnected(reason))
        }
    }

    private func trackSpeaker(previous: FloorHolder?, current: FloorHolder?) {
        let mine = credentials?.identity
        if let current, current.identity != mine {
            lastSpeaker = current
            lastSpeakerReleasedAt = nil
        } else if let previous, previous.identity != mine, lastSpeaker?.identity == previous.identity {
            lastSpeakerReleasedAt = now()
        }
    }

    private func end(_ reason: EndReason) {
        closeNow()
        onEnded?(reason)
    }

    private func resetRoomState() {
        let hadRoom = isOpen || channel != nil
        isOpen = false
        isReconnecting = false
        meta = nil
        listenerCount = nil
        speakingIdentities = []
        credentials = nil
        api = nil
        canPublish = false
        lastSpeaker = nil
        lastSpeakerReleasedAt = nil
        channel = nil
        if hadRoom { onTalkSignal?(.roomReset) }
    }
}
