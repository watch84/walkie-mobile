import Foundation
import Observation

enum FlashMessage: Equatable, Sendable {
    case micBlocked
    case busy
    case offAir
    case keyUpFailed
    case transmissionEnded
    case muted(String)
    case unmuted(String)
    case reported(String)
    case reportFailed
}

/// The single transient message line under the push-to-talk button.
@MainActor
@Observable
final class FlashLine {
    private(set) var message: FlashMessage?
    /// Bumped on every flash so repeating the same message re-triggers it.
    private(set) var id = 0

    @ObservationIgnored private let duration: Duration
    @ObservationIgnored private var clearTask: Task<Void, Never>?

    init(duration: Duration = .seconds(2.5)) {
        self.duration = duration
    }

    func show(_ message: FlashMessage) {
        self.message = message
        id += 1
        let current = id
        clearTask?.cancel()
        clearTask = Task { [weak self, duration] in
            do { try await Task.sleep(for: duration) } catch { return }
            guard let self, self.id == current else { return }
            self.message = nil
        }
    }
}

/// Remaining floor time for the countdown ring. Prefers the server's `expiresAt`; falls back to
/// `FLOOR_MAX_MS` from local key-up when the floor isn't known yet or the clocks disagree wildly.
enum FloorCountdown {
    static let maxSeconds = Double(WalkieProtocol.floorMaxMs) / 1_000
    /// A server deadline further out than this is treated as clock skew.
    static let skewTolerance = 2.0

    static func deadline(floor: FloorHolder?, myIdentity: String?, liveSince: Date?, now: Date) -> Date? {
        if let floor, floor.identity == myIdentity {
            let server = Date(timeIntervalSince1970: floor.expiresAt / 1_000)
            let left = server.timeIntervalSince(now)
            if left <= maxSeconds + skewTolerance, left > -skewTolerance { return server }
        }
        return liveSince.map { $0.addingTimeInterval(maxSeconds) }
    }

    static func remaining(until deadline: Date, now: Date) -> TimeInterval {
        min(maxSeconds, max(0, deadline.timeIntervalSince(now)))
    }

    static func fraction(until deadline: Date, now: Date) -> Double {
        remaining(until: deadline, now: now) / maxSeconds
    }

    static func wholeSecondsLeft(until deadline: Date, now: Date) -> Int {
        Int(remaining(until: deadline, now: now).rounded(.up))
    }
}
