import Foundation

/// Background sound under the radio, chosen as in the web client's `RadioApp`.
enum SoundBed: Equatable, Sendable {
    case none
    /// Soft brown noise while a live channel is quiet.
    case roomTone
    /// Band-limited hiss while tuning, on a locked station, or with no signal.
    case staticHiss

    static let roomToneLevel: Float = 0.018
    static let staticLevel: Float = 0.05

    /// - live + (floor held by anyone, or this device talking) → none
    /// - live + quiet → room tone
    /// - off air → none
    /// - everything else (locked, tuning, error) → static
    static func bed(for phase: Tuner.Phase, floorHeld: Bool, talking: Bool) -> SoundBed {
        switch phase {
        case .live: return floorHeld || talking ? .none : .roomTone
        case .offAir, .idle: return .none
        case .locked, .tuning, .error: return .staticHiss
        }
    }

    var level: Float {
        switch self {
        case .none: 0
        case .roomTone: Self.roomToneLevel
        case .staticHiss: Self.staticLevel
        }
    }
}
