import Foundation
import Testing
@testable import Walkie

private func freshDefaults(_ name: String = #function) -> UserDefaults {
    let suite = "walkie.tests.\(name).\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

struct DisplayNameTests {
    @Test func trimsWhitespace() {
        #expect(DisplayName.validate("  Ada  ") == .success("Ada"))
    }

    @Test func rejectsEmptyAndBlank() {
        #expect(DisplayName.validate("") == .failure(.empty))
        #expect(DisplayName.validate("   \n") == .failure(.empty))
    }

    @Test func acceptsBoundaryLengths() {
        #expect(DisplayName.isValid("a"))
        #expect(DisplayName.isValid(String(repeating: "x", count: 32)))
        #expect(DisplayName.validate(String(repeating: "x", count: 33)) == .failure(.tooLong))
    }

    @Test func clampsInput() {
        let long = String(repeating: "y", count: 40)
        #expect(DisplayName.clampInput(long).count == 32)
        #expect(DisplayName.clampInput("short") == "short")
    }
}

@MainActor
struct ProfileStoreTests {
    @Test func persistsAcrossInstances() {
        let defaults = freshDefaults()
        let store = ProfileStore(defaults: defaults)
        #expect(store.displayName == nil)

        store.setDisplayName(" Grace ")
        #expect(ProfileStore(defaults: defaults).displayName == "Grace")

        store.clearDisplayName()
        #expect(ProfileStore(defaults: defaults).displayName == nil)
    }

    @Test func invalidNameIsNotSaved() {
        let defaults = freshDefaults()
        let store = ProfileStore(defaults: defaults)
        #expect(store.setDisplayName("") == .failure(.empty))
        #expect(store.displayName == nil)
    }
}

@MainActor
struct DebugSettingsTests {
    @Test func defaults() {
        let settings = DebugSettings(defaults: freshDefaults())
        #expect(settings.apiBaseURL == "http://127.0.0.1:8787")
        #expect(settings.liveKitURL == "ws://127.0.0.1:7880")
        #expect(settings.isAPIBaseURLValid)
        #expect(settings.isLiveKitURLValid)
    }

    @Test func persistsAndResets() {
        let defaults = freshDefaults()
        let settings = DebugSettings(defaults: defaults)
        settings.apiBaseURL = "http://192.168.1.20:8787"
        #expect(DebugSettings(defaults: defaults).apiBaseURL == "http://192.168.1.20:8787")

        settings.resetToDefaults()
        #expect(DebugSettings(defaults: defaults).apiBaseURL == "http://127.0.0.1:8787")
    }

    @Test func validatesSchemes() {
        #expect(DebugSettings.parse("ws://127.0.0.1:7880", schemes: ["http", "https"]) == nil)
        #expect(DebugSettings.parse("http://127.0.0.1:8787", schemes: ["ws", "wss"]) == nil)
        #expect(DebugSettings.parse("127.0.0.1:8787", schemes: ["http", "https"]) == nil)
        #expect(DebugSettings.parse(" https://walkie.example ", schemes: ["http", "https"]) != nil)
    }
}

@MainActor
struct AppModelTests {
    @Test func firstLaunchFlow() {
        let model = AppModel(defaults: freshDefaults())
        #expect(model.phase == .naming)

        model.tuneIn()
        #expect(model.phase == .naming)

        model.submitName("")
        #expect(model.phase == .naming)

        model.submitName("Linus")
        #expect(model.phase == .tuneIn)

        model.tuneIn()
        #expect(model.phase == .radio)
    }

    @Test func returningUserStartsAtTuneIn() {
        let defaults = freshDefaults()
        AppModel(defaults: defaults).submitName("Margaret")
        #expect(AppModel(defaults: defaults).phase == .tuneIn)
    }
}
