import Foundation

/// Display name rules, mirroring the web client (`src/radio/RadioApp.tsx`).
enum DisplayName {
    /// Matches the web input's `maxLength={32}`, which counts UTF-16 code units of the raw input.
    static let maxLength = 32

    enum ValidationError: Error, Equatable {
        case empty
        case tooLong
    }

    /// `value.replace(/\s+/g, ' ').trim()`
    static func normalize(_ raw: String) -> String {
        raw.replacing(/\s+/, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns the normalized name, or why it is invalid.
    static func validate(_ raw: String) -> Result<String, ValidationError> {
        let name = normalize(raw)
        if name.isEmpty { return .failure(.empty) }
        if name.utf16.count > maxLength { return .failure(.tooLong) }
        return .success(name)
    }

    static func isValid(_ raw: String) -> Bool {
        if case .success = validate(raw) { return true }
        return false
    }

    /// Clamps raw text-field input like the web input's `maxLength`, without splitting a character.
    static func clampInput(_ raw: String) -> String {
        guard raw.utf16.count > maxLength else { return raw }
        var result = ""
        var used = 0
        for character in raw {
            let size = character.utf16.count
            if used + size > maxLength { break }
            result.append(character)
            used += size
        }
        return result
    }
}
