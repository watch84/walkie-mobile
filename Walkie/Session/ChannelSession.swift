import Foundation
import Observation

/// Listen-only connection to one channel: fetches a token, joins the room, and mirrors the
/// server's room metadata. Floor state comes only from `RoomMeta`, never from local guesses.
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
    }

    private(set) var phase: Phase = .idle
    private(set) var channel: ChannelInfo = .defaultChannel
    private(set) var name: String?
    private(set) var meta: RoomMeta?
    private(set) var listenerCount: Int?
    private(set) var speakingIdentities: Set<String> = []
    private(set) var credentials: TokenResponse?
    private(set) var lastError: String?

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
        let token = try await endpoint.api.token(channel: channel.id, name: name)
        guard gen == generation else { throw CancellationError() }
        guard let url = LiveKitURL.resolve(token.url, fallback: endpoint.liveKitFallback) else {
            throw JoinError.noLiveKitURL
        }

        let room = makeTransport()
        try await room.connect(url: url, token: token.token) { [weak self] event in
            self?.handle(event, gen: gen)
        }
        guard gen == generation, !Task.isCancelled else {
            await room.disconnect()
            throw CancellationError()
        }
        transport = room
        credentials = token
        lastError = nil
        phase = .live
    }

    private func handle(_ event: RoomEvent, gen: Int) {
        guard gen == generation else { return }
        switch event {
        case .metadata(let raw):
            if let incoming = RoomMeta.decode(raw), RoomMeta.isFresh(incoming, after: meta) {
                meta = incoming
            }
        case .participantCount(let count):
            listenerCount = count
        case .speaking(let identities):
            speakingIdentities = identities
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
    }
}
