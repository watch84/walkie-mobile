import Foundation
import Observation

/// Port of the web client's `src/radio/tuner.ts`: decides which station's room is open.
///
/// - Locked stations go straight to `.locked` and never fetch a token or open a session.
/// - Moving to a live station closes the previous session immediately, shows `.tuning`, and
///   connects only after the dial has rested there for `debounce`; a fast scroll across many
///   stations therefore makes a single token call, for the station it stops on.
/// - A connection that completes after the dial moved on is dropped (generation counter).
/// - Token refused as off air → `.offAir`, retry after `offAirRetry`. A connected room ending off
///   air does the same; any other end → `.tuning` and retry after `retry`.
@MainActor
@Observable
final class Tuner {
    enum Phase: Equatable, Sendable {
        /// Not started (before "Tap to tune in").
        case idle
        case locked
        case tuning
        case live
        case offAir
        /// Token or connect failed for a reason other than off air; retrying.
        case error
    }

    struct Timing: Sendable {
        var debounce: Duration = .milliseconds(300)
        var offAirRetry: Duration = .seconds(10)
        var retry: Duration = .seconds(2)
    }

    struct Endpoint {
        let api: any WalkieAPIClient
        let liveKitFallback: URL?
    }

    typealias EndpointProvider = @MainActor () -> Endpoint?

    enum ConnectError: Error, Equatable {
        case misconfigured
        case noLiveKitURL
    }

    let session: ChannelSession

    private(set) var phase: Phase = .idle
    private(set) var stationIndex: Int
    private(set) var name: String?
    private(set) var lastError: String?

    var station: Station { Stations.all[stationIndex] }
    var isStarted: Bool { name != nil }

    @ObservationIgnored private let timing: Timing
    @ObservationIgnored private var endpoint: EndpointProvider?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    init(session: ChannelSession, stationIndex: Int = Stations.defaultIndex, timing: Timing = Timing()) {
        self.session = session
        self.stationIndex = Stations.clamp(stationIndex)
        self.timing = timing
        session.onEnded = { [weak self] reason in self?.sessionEnded(reason) }
    }

    /// Starts tuning the current station as `name`.
    func start(name: String, endpoint: @escaping EndpointProvider) {
        self.name = name
        self.endpoint = endpoint
        tuneCurrentStation()
    }

    /// Reconnects the current station, e.g. after the display name changed.
    func retune(name: String) {
        guard isStarted, name != self.name else { return }
        self.name = name
        tuneCurrentStation()
    }

    func setStation(_ index: Int) {
        let index = Stations.clamp(index)
        guard index != stationIndex else { return }
        stationIndex = index
        guard isStarted else { return }
        tuneCurrentStation()
    }

    func stop() async {
        name = nil
        endpoint = nil
        generation += 1
        task?.cancel()
        task = nil
        phase = .idle
        await session.close()
    }

    // MARK: Scheduling

    private func tuneCurrentStation() {
        let gen = bumpGeneration()
        session.closeNow()
        guard let channel = station.channel else {
            phase = .locked
            return
        }
        phase = .tuning
        task = Task { [weak self, timing] in
            do { try await Task.sleep(for: timing.debounce) } catch { return }
            await self?.connect(gen, channel: channel)
        }
    }

    private func scheduleRetry(after delay: Duration) {
        guard let channel = station.channel else { return }
        let gen = bumpGeneration()
        task = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            await self?.connect(gen, channel: channel)
        }
    }

    private func bumpGeneration() -> Int {
        generation += 1
        task?.cancel()
        task = nil
        return generation
    }

    // MARK: Connecting

    private func connect(_ gen: Int, channel: ChannelInfo) async {
        guard gen == generation else { return }
        do {
            guard let endpoint = endpoint?(), let name else { throw ConnectError.misconfigured }
            let token = try await endpoint.api.token(channel: channel.id, name: name)
            guard gen == generation else { return }
            guard let url = LiveKitURL.resolve(token.url, fallback: endpoint.liveKitFallback) else {
                throw ConnectError.noLiveKitURL
            }
            try await session.open(token: token, channel: channel, url: url, api: endpoint.api)
            guard gen == generation else {
                await session.close()
                return
            }
            lastError = nil
            phase = .live
        } catch ChannelSession.OpenError.superseded {
            return
        } catch {
            guard gen == generation else { return }
            lastError = String(describing: error)
            if case WalkieAPIError.offAir = error {
                phase = .offAir
                scheduleRetry(after: timing.offAirRetry)
            } else {
                phase = .error
                scheduleRetry(after: timing.retry)
            }
        }
    }

    private func sessionEnded(_ reason: ChannelSession.EndReason) {
        guard phase == .live else { return }
        switch reason {
        case .offAir:
            phase = .offAir
            scheduleRetry(after: timing.offAirRetry)
        case .disconnected(let message):
            lastError = message
            phase = .tuning
            scheduleRetry(after: timing.retry)
        }
    }
}
