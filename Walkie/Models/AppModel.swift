import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case naming
        case tuneIn
        case radio
    }

    let profile: ProfileStore
    let debug: DebugSettings

    private(set) var phase: Phase

    /// Per launch, like the web app's audio unlock; only the name persists. Submitting the
    /// name screen counts as the unlocking tap, as it does on web.
    private(set) var audioUnlocked = false

    init(profile: ProfileStore, debug: DebugSettings) {
        self.profile = profile
        self.debug = debug
        phase = profile.hasDisplayName ? .tuneIn : .naming
    }

    convenience init(defaults: UserDefaults = .standard) {
        self.init(profile: ProfileStore(defaults: defaults), debug: DebugSettings(defaults: defaults))
    }

    @discardableResult
    func submitName(_ raw: String) -> Result<String, DisplayName.ValidationError> {
        let result = profile.setDisplayName(raw)
        if case .success = result {
            audioUnlocked = true
            phase = .radio
        }
        return result
    }

    func tuneIn() {
        guard profile.hasDisplayName else {
            phase = .naming
            return
        }
        audioUnlocked = true
        phase = .radio
    }

    func editName() {
        phase = .naming
    }

    func forgetName() {
        profile.clearDisplayName()
        phase = .naming
    }
}
