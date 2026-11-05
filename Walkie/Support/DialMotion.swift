import Foundation

/// Pure motion model for the station dial, ported from the web client's `src/dial/motion.ts`.
/// Positions are in detent units (station index as a Double).
///
/// - `drag`: follows the finger; past either end the overshoot is rubber-banded, never more than
///   `rubberLimit` detents.
/// - `coast`: after a flick, velocity decays exponentially with time constant `coastTau`; the
///   rest target is projected from the release velocity (`position + velocity * coastTau`).
/// - `spring`: critically damped settle onto a detent (`settleOmega`), or a stiffer bounce back
///   from an end (`bounceOmega`).
/// - `glide`: a programmatic move to a detent (accessibility increment, keyboard), using the
///   settle spring.
struct DialMotion: Equatable, Sendable {
    static let rubberLimit = 1.6
    static let coastTau = 0.24
    static let settleOmega = 18.0
    static let bounceOmega = 26.0

    /// Below these the motion snaps to rest.
    static let restDistance = 0.0005
    static let restVelocity = 0.01
    /// Coasting hands over to the settle spring once this slow (detents/s).
    static let coastHandoffVelocity = 1.5

    enum Mode: Equatable, Sendable {
        case rest
        case drag
        case glide(target: Int)
        case coast(target: Int)
        case spring(target: Int, omega: Double)
    }

    let count: Int
    private(set) var position: Double
    private(set) var velocity: Double = 0
    private(set) var mode: Mode = .rest

    /// Finger position (unbounded) at the last drag update, to rubber-band from.
    private var dragOrigin: Double = 0

    init(count: Int, index: Int) {
        precondition(count > 0)
        self.count = count
        position = Double(Self.clamp(index, count: count))
    }

    var maxIndex: Int { count - 1 }
    var isResting: Bool { mode == .rest }

    /// The detent currently under the pointer.
    var currentIndex: Int { Self.clamp(Int(position.rounded()), count: count) }

    /// Where the dial will come to rest if left alone from its current state.
    var restingIndex: Int {
        switch mode {
        case .rest, .drag: return Self.restingIndex(position: position, velocity: velocity, count: count)
        case .glide(let target), .coast(let target), .spring(let target, _): return target
        }
    }

    static func restingIndex(position: Double, velocity: Double, count: Int) -> Int {
        clamp(Int((position + velocity * coastTau).rounded()), count: count)
    }

    static func clamp(_ index: Int, count: Int) -> Int {
        min(max(index, 0), count - 1)
    }

    /// Maps an overshoot past an end (in detents, ≥ 0) to a displayed overshoot in
    /// `[0, limit)`: linear near zero, asymptotic to `limit`.
    static func rubber(_ overshoot: Double, limit: Double = rubberLimit) -> Double {
        guard overshoot > 0 else { return 0 }
        return limit * (1 - 1 / (overshoot / limit + 1))
    }

    /// Displayed position for an unbounded finger position.
    func rubberBanded(_ raw: Double) -> Double {
        let upper = Double(maxIndex)
        if raw < 0 { return -Self.rubber(-raw) }
        if raw > upper { return upper + Self.rubber(raw - upper) }
        return raw
    }

    // MARK: Input

    /// Returns the finger-space position to add drag translations to.
    @discardableResult
    mutating func beginDrag() -> Double {
        mode = .drag
        velocity = 0
        dragOrigin = unrubber(position)
        return dragOrigin
    }

    /// `raw` is the unbounded finger position in detents (drag origin + translation).
    mutating func drag(to raw: Double, velocity: Double = 0) {
        if mode != .drag { beginDrag() }
        position = rubberBanded(raw)
        self.velocity = velocity
    }

    /// Releases the drag with `velocity` (detents/s). With `reduceMotion`, skips the coast and
    /// settles on the nearest detent.
    mutating func endDrag(velocity: Double, reduceMotion: Bool = false) {
        let upper = Double(maxIndex)
        if position < 0 || position > upper {
            self.velocity = reduceMotion ? 0 : velocity
            mode = .spring(target: position < 0 ? 0 : maxIndex, omega: Self.bounceOmega)
            return
        }
        if reduceMotion || abs(velocity) < Self.coastHandoffVelocity {
            self.velocity = reduceMotion ? 0 : velocity
            mode = .spring(target: Self.clamp(Int(position.rounded()), count: count), omega: Self.settleOmega)
            return
        }
        self.velocity = velocity
        mode = .coast(target: Self.restingIndex(position: position, velocity: velocity, count: count))
    }

    mutating func glide(to index: Int) {
        mode = .glide(target: Self.clamp(index, count: count))
    }

    /// Jumps straight to a detent without animating.
    mutating func snap(to index: Int) {
        position = Double(Self.clamp(index, count: count))
        velocity = 0
        mode = .rest
    }

    // MARK: Simulation

    /// Advances by `dt` seconds. Returns true while still moving.
    @discardableResult
    mutating func step(_ dt: Double) -> Bool {
        guard dt > 0 else { return !isResting }
        switch mode {
        case .rest, .drag:
            return mode == .drag
        case .glide(let target):
            springStep(target: target, omega: Self.settleOmega, dt: dt)
        case .spring(let target, let omega):
            springStep(target: target, omega: omega, dt: dt)
        case .coast(let target):
            let decay = exp(-dt / Self.coastTau)
            position += velocity * Self.coastTau * (1 - decay)
            velocity *= decay
            let upper = Double(maxIndex)
            if position < 0 || position > upper {
                mode = .spring(target: position < 0 ? 0 : maxIndex, omega: Self.bounceOmega)
            } else if abs(velocity) < Self.coastHandoffVelocity {
                mode = .spring(target: target, omega: Self.settleOmega)
            }
        }
        return !isResting
    }

    /// Exact critically damped spring step toward `target`.
    private mutating func springStep(target: Int, omega: Double, dt: Double) {
        let x0 = position - Double(target)
        let b = velocity + omega * x0
        let e = exp(-omega * dt)
        let x = (x0 + b * dt) * e
        velocity = (b - omega * (x0 + b * dt)) * e
        position = Double(target) + x
        if abs(x) < Self.restDistance, abs(velocity) < Self.restVelocity {
            snap(to: target)
        }
    }

    /// Inverse of `rubberBanded`, so a drag that starts mid-bounce doesn't jump.
    private func unrubber(_ shown: Double) -> Double {
        let upper = Double(maxIndex)
        func inverse(_ y: Double) -> Double {
            let limit = Self.rubberLimit
            let clamped = min(y, limit * 0.999)
            return limit * (1 / (1 - clamped / limit) - 1)
        }
        if shown < 0 { return -inverse(-shown) }
        if shown > upper { return upper + inverse(shown - upper) }
        return shown
    }
}
