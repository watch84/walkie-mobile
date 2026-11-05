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

    /// Tuning in is per launch, like the web app's tap-to-start gate; only the name persists.
    private(set) var phase: Phase

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
        if case .success = result { phase = .tuneIn }
        return result
    }

    func tuneIn() {
        guard profile.hasDisplayName else {
            phase = .naming
            return
        }
        phase = .radio
    }

    func changeName() {
        phase = .naming
    }

    func tuneOut() {
        phase = profile.hasDisplayName ? .tuneIn : .naming
    }
}
