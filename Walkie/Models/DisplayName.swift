import Foundation

/// Display name rules shared with the web client (`shared/protocol.ts`).
enum DisplayName {
    static let minLength = 1
    static let maxLength = 32

    enum ValidationError: Error, Equatable {
        case empty
        case tooLong
    }

    static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns the normalized name, or why it is invalid.
    static func validate(_ raw: String) -> Result<String, ValidationError> {
        let name = normalize(raw)
        if name.count < minLength { return .failure(.empty) }
        if name.count > maxLength { return .failure(.tooLong) }
        return .success(name)
    }

    static func isValid(_ raw: String) -> Bool {
        if case .success = validate(raw) { return true }
        return false
    }

    /// Clamps live text-field input so the user can't type past the limit.
    static func clampInput(_ raw: String) -> String {
        raw.count > maxLength ? String(raw.prefix(maxLength)) : raw
    }
}
