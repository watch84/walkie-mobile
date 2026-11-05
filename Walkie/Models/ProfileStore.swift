import Foundation
import Observation

@MainActor
@Observable
final class ProfileStore {
    static let displayNameKey = "walkie.displayName"

    private(set) var displayName: String?

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.string(forKey: Self.displayNameKey)
        if let stored, case .success(let name) = DisplayName.validate(stored) {
            displayName = name
        } else {
            displayName = nil
        }
    }

    var hasDisplayName: Bool { displayName != nil }

    @discardableResult
    func setDisplayName(_ raw: String) -> Result<String, DisplayName.ValidationError> {
        let result = DisplayName.validate(raw)
        if case .success(let name) = result {
            displayName = name
            defaults.set(name, forKey: Self.displayNameKey)
        }
        return result
    }

    func clearDisplayName() {
        displayName = nil
        defaults.removeObject(forKey: Self.displayNameKey)
    }
}
