import Foundation
import Observation

enum MicrophonePermission: Equatable, Sendable {
    case undetermined
    case granted
    case denied
}

@MainActor
protocol MicrophoneAuthorizing: AnyObject {
    var permission: MicrophonePermission { get }
    /// Shows the system prompt; returns whether access was granted.
    func request() async -> Bool
}

@MainActor
protocol ChirpPlaying: AnyObject {
    func playStart()
    func playEnd()
}

/// Hold-to-talk state machine, ported from the web client's `session.ts`:
/// press → (first press: mic prompt only) → `POST /floor/request` → wait for the server's
/// `canPublish` grant → publish mic → live. Finger up, backgrounding, or termination release the
/// floor and unpublish; a server revoke (30 s cap or kill) ends the transmission.
@MainActor
@Observable
final class TalkController {
    enum Phase: Equatable, Sendable {
        case idle
        case requestingPermission
        case keying
        case live
    }

    /// What the button shows.
    enum ButtonState: Equatable, Sendable {
        case locked
        case tuning
        case noSignal
        case offAir
        case busy
        case ready
        case keying
        case live
    }

    enum Flash: Equatable, Sendable {
        case micBlocked
        case busy
        case offAir
        case keyUpFailed
        case transmissionEnded
    }

    enum EndReason: Equatable, Sendable {
        case released
        case background
        case revoked
        case roomLost
    }

    nonisolated static let defaultGrantTimeout: Duration = .seconds(4)
    nonisolated static let floorMax: Duration = .milliseconds(WalkieProtocol.floorMaxMs)

    private(set) var phase: Phase = .idle
    private(set) var liveSince: Date?
    private(set) var flash: Flash?
    /// Bumped on every flash so repeating the same message re-triggers it.
    private(set) var flashID = 0

    var buttonState: ButtonState {
        switch phase {
        case .live: return .live
        case .keying, .requestingPermission: return .keying
        case .idle: break
        }
        switch tuner.phase {
        case .locked: return .locked
        case .offAir: return .offAir
        case .error: return .noSignal
        case .idle, .tuning: return .tuning
        case .live:
            guard session.isOpen, !session.isReconnecting else { return .tuning }
            return session.isFloorHeldByOther ? .busy : .ready
        }
    }

    @ObservationIgnored private let tuner: Tuner
    @ObservationIgnored private var session: ChannelSession { tuner.session }
    @ObservationIgnored private let microphone: any MicrophoneAuthorizing
    @ObservationIgnored private let chirps: any ChirpPlaying
    @ObservationIgnored private let grantTimeout: Duration
    @ObservationIgnored private let flashDuration: Duration
    @ObservationIgnored private let now: @MainActor () -> Date

    @ObservationIgnored private var isHeld = false
    /// Bumped on every press so work from an earlier press can tell it has been superseded.
    @ObservationIgnored private var attempt = 0
    @ObservationIgnored private var floor: (credentials: FloorCredentials, api: any WalkieAPIClient)?
    @ObservationIgnored private var grantWaiter: CheckedContinuation<Bool, Never>?
    @ObservationIgnored private var grantTimeoutTask: Task<Void, Never>?
    @ObservationIgnored private var flashTask: Task<Void, Never>?

    init(
        tuner: Tuner,
        microphone: any MicrophoneAuthorizing,
        chirps: any ChirpPlaying,
        grantTimeout: Duration = TalkController.defaultGrantTimeout,
        flashDuration: Duration = .seconds(2.5),
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.tuner = tuner
        self.microphone = microphone
        self.chirps = chirps
        self.grantTimeout = grantTimeout
        self.flashDuration = flashDuration
        self.now = now
        tuner.session.onTalkSignal = { [weak self] signal in self?.handle(signal) }
    }

    // MARK: Press / release

    func press() {
        guard phase == .idle else { return }
        switch buttonState {
        case .ready: break
        case .busy: show(.busy); return
        case .offAir: show(.offAir); return
        case .locked, .tuning, .noSignal, .keying, .live: return
        }
        guard let credentials = session.credentials, let api = session.api else { return }

        switch microphone.permission {
        case .undetermined:
            // The system dialog takes the touch; never key up behind it.
            phase = .requestingPermission
            attempt += 1
            let current = attempt
            Task {
                let granted = await microphone.request()
                guard current == attempt, phase == .requestingPermission else { return }
                phase = .idle
                if !granted { show(.micBlocked) }
            }
            return
        case .denied:
            show(.micBlocked)
            return
        case .granted:
            break
        }

        isHeld = true
        attempt += 1
        floor = (credentials, api)
        phase = .keying
        let current = attempt
        Task { await keyUp(current, credentials: credentials, api: api) }
    }

    func release() {
        end(.released)
    }

    /// App moved to the background or is terminating.
    func appWillResignActive() {
        end(.background)
    }

    // MARK: Keying

    private func keyUp(_ current: Int, credentials: FloorCredentials, api: any WalkieAPIClient) async {
        do {
            try await api.requestFloor(credentials)
        } catch {
            guard current == attempt else { return }
            if phase == .keying { phase = .idle }
            floor = nil
            // A finger already lifted doesn't need to hear why keying failed, except for busy.
            switch error {
            case WalkieAPIError.busy: show(.busy)
            case WalkieAPIError.offAir: show(.offAir)
            default: if isHeld { show(.keyUpFailed) }
            }
            isHeld = false
            return
        }

        guard current == attempt else { return }
        guard isHeld else { return await abandon(credentials, api: api) }

        let granted = await waitForGrant()
        guard current == attempt else { return }
        guard isHeld else { return await abandon(credentials, api: api) }
        guard granted else {
            phase = .idle
            isHeld = false
            show(.keyUpFailed)
            return await abandon(credentials, api: api)
        }

        do {
            try await session.setMicrophone(enabled: true)
        } catch {
            guard current == attempt else { return }
            phase = .idle
            isHeld = false
            show(.keyUpFailed)
            return await abandon(credentials, api: api)
        }

        guard current == attempt, isHeld else {
            try? await session.setMicrophone(enabled: false)
            return await abandon(credentials, api: api)
        }
        phase = .live
        liveSince = now()
        chirps.playStart()
    }

    /// Gives the floor back after a press that never went live.
    private func abandon(_ credentials: FloorCredentials, api: any WalkieAPIClient) async {
        floor = nil
        try? await api.releaseFloor(credentials)
    }

    private func waitForGrant() async -> Bool {
        if session.canPublish { return true }
        return await withCheckedContinuation { continuation in
            grantWaiter = continuation
            grantTimeoutTask = Task { [weak self, grantTimeout] in
                do { try await Task.sleep(for: grantTimeout) } catch { return }
                self?.resolveGrant(false)
            }
        }
    }

    private func resolveGrant(_ granted: Bool) {
        grantTimeoutTask?.cancel()
        grantTimeoutTask = nil
        let waiter = grantWaiter
        grantWaiter = nil
        waiter?.resume(returning: granted)
    }

    // MARK: Ending

    private func end(_ reason: EndReason) {
        isHeld = false
        switch phase {
        case .idle, .requestingPermission:
            return
        case .keying:
            // `keyUp` sees `isHeld == false` and releases the floor itself.
            phase = .idle
            resolveGrant(false)
        case .live:
            phase = .idle
            liveSince = nil
            chirps.playEnd()
            if reason == .revoked || reason == .roomLost { show(.transmissionEnded) }
            let held = floor
            floor = nil
            Task { [session] in
                try? await session.setMicrophone(enabled: false)
                // A revoke means the server already took the floor back.
                if reason != .revoked, let held {
                    try? await held.api.releaseFloor(held.credentials)
                }
            }
        }
    }

    private func handle(_ signal: ChannelSession.TalkSignal) {
        switch signal {
        case .canPublish(true):
            resolveGrant(true)
        case .canPublish(false):
            if phase == .live { end(.revoked) }
        case .floorChanged(let holder):
            if phase == .live, holder?.identity != floor?.credentials.identity { end(.revoked) }
        case .roomReset:
            end(.roomLost)
        }
    }

    // MARK: Flash

    private func show(_ message: Flash) {
        flash = message
        flashID += 1
        let id = flashID
        flashTask?.cancel()
        flashTask = Task { [weak self, flashDuration] in
            do { try await Task.sleep(for: flashDuration) } catch { return }
            guard let self, self.flashID == id else { return }
            self.flash = nil
        }
    }
}
