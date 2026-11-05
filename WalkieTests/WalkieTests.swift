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

    @Test func collapsesInternalWhitespace() {
        #expect(DisplayName.normalize("  a \n\t b  ") == "a b")
        #expect(DisplayName.normalize("Ada   Lovelace") == "Ada Lovelace")
    }

    @Test func rejectsEmptyAndWhitespaceOnly() {
        #expect(DisplayName.validate("") == .failure(.empty))
        #expect(DisplayName.validate("   \n\t ") == .failure(.empty))
        #expect(!DisplayName.isValid(" "))
    }

    @Test func acceptsSingleCharacterAndLimit() {
        #expect(DisplayName.isValid("a"))
        #expect(DisplayName.isValid(String(repeating: "x", count: 32)))
        #expect(DisplayName.validate(String(repeating: "x", count: 33)) == .failure(.tooLong))
    }

    @Test func clampsToUTF16Limit() {
        #expect(DisplayName.clampInput(String(repeating: "y", count: 40)) == String(repeating: "y", count: 32))
        #expect(DisplayName.clampInput("short") == "short")

        // Each 🎙️ is 3 UTF-16 units (U+1F399 surrogate pair + U+FE0F).
        let mics = String(repeating: "🎙️", count: 11)
        #expect(mics.utf16.count == 33)
        let clamped = DisplayName.clampInput(mics)
        #expect(clamped == String(repeating: "🎙️", count: 10))
        #expect(clamped.utf16.count == 30)
    }

    @Test func clampDoesNotSplitSurrogatePair() {
        // 31 ASCII + 😀 (2 units) = 33: the emoji must be dropped, not halved.
        let raw = String(repeating: "a", count: 31) + "😀"
        let clamped = DisplayName.clampInput(raw)
        #expect(clamped == String(repeating: "a", count: 31))
        #expect(DisplayName.isValid(clamped))
    }
}

@MainActor
struct ProfileStoreTests {
    @Test func usesWebStorageKey() {
        #expect(ProfileStore.displayNameKey == "walkie:name")
        let defaults = freshDefaults()
        ProfileStore(defaults: defaults).setDisplayName(" Grace  Hopper ")
        #expect(defaults.string(forKey: "walkie:name") == "Grace Hopper")
    }

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
        #expect(store.setDisplayName("   ") == .failure(.empty))
        #expect(store.displayName == nil)
        #expect(defaults.string(forKey: "walkie:name") == nil)
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
final class AppHarness {
    let factory = TransportFactory()
    let api: FakeAPI
    private(set) var audioActivations = 0
    private(set) var apiBaseURLs: [URL] = []

    init(_ responses: [Result<TokenResponse, WalkieAPIError>] = [.success(makeToken())]) {
        api = FakeAPI(responses)
    }

    var dependencies: AppDependencies {
        AppDependencies(
            makeTransport: { [factory] in factory.make() },
            makeAPI: { [self] url in apiBaseURLs.append(url); return api },
            activateAudio: { [self] in audioActivations += 1 },
            retryDelay: .milliseconds(20)
        )
    }

    func model(_ defaults: UserDefaults) -> AppModel {
        AppModel(defaults: defaults, dependencies: dependencies)
    }
}

@MainActor
struct AppModelTests {
    @Test func firstLaunchSubmitUnlocksAndJoinsChannelOne() async {
        let harness = AppHarness()
        let model = harness.model(freshDefaults())
        #expect(model.phase == .naming)

        model.tuneIn()
        #expect(model.phase == .naming)

        model.submitName("   ")
        #expect(model.phase == .naming)
        #expect(!model.audioUnlocked)
        #expect(harness.audioActivations == 0)

        model.submitName("Linus")
        #expect(model.phase == .radio)
        #expect(model.audioUnlocked)
        #expect(harness.audioActivations == 1)

        #expect(await waitUntil { model.session.phase == .live })
        #expect(await harness.api.requests == [TokenRequest(channel: "channel-1", name: "Linus")])
        #expect(harness.apiBaseURLs.first?.absoluteString == "http://127.0.0.1:8787")
        #expect(harness.factory.last?.connectedURL?.absoluteString == "ws://127.0.0.1:7880")
    }

    @Test func returningUserSeesTuneInGate() async {
        let defaults = freshDefaults()
        let harness = AppHarness()
        ProfileStore(defaults: defaults).setDisplayName("Margaret")

        let model = harness.model(defaults)
        #expect(model.phase == .tuneIn)
        #expect(!model.audioUnlocked)
        #expect(model.session.phase == .idle)

        model.tuneIn()
        #expect(model.phase == .radio)
        #expect(model.audioUnlocked)
        #expect(await waitUntil { model.session.phase == .live })
    }

    @Test func editNameReturnsStraightToRadioAndRejoinsWithNewName() async {
        let defaults = freshDefaults()
        let harness = AppHarness()
        ProfileStore(defaults: defaults).setDisplayName("Margaret")
        let model = harness.model(defaults)
        model.tuneIn()
        #expect(await waitUntil { model.session.phase == .live })

        model.editName()
        #expect(model.phase == .naming)

        model.submitName("Margaret  Hamilton")
        #expect(model.phase == .radio)
        #expect(model.profile.displayName == "Margaret Hamilton")
        #expect(harness.audioActivations == 1)
        #expect(await waitUntil { harness.factory.made.count == 2 && model.session.phase == .live })
        #expect(await harness.api.requests.last == TokenRequest(channel: "channel-1", name: "Margaret Hamilton"))
    }

    @Test func unchangedNameDoesNotRejoin() async {
        let harness = AppHarness()
        let model = harness.model(freshDefaults())
        model.submitName("Ada")
        #expect(await waitUntil { model.session.phase == .live })

        model.editName()
        model.submitName("Ada")
        #expect(model.phase == .radio)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(harness.factory.made.count == 1)
    }

    @Test func selectingChannelRetunes() async {
        let harness = AppHarness()
        let model = harness.model(freshDefaults())
        model.submitName("Ada")
        #expect(await waitUntil { model.session.phase == .live })

        model.select(ChannelInfo.live[2])
        #expect(model.selectedChannel.id == "channel-3")
        #expect(await waitUntil { harness.factory.made.count == 2 && model.session.phase == .live })
        #expect(await harness.api.requests.last == TokenRequest(channel: "channel-3", name: "Ada"))
    }

    @Test func forgetNameReturnsToNamingAndStops() async {
        let harness = AppHarness()
        let model = harness.model(freshDefaults())
        model.submitName("Ada")
        #expect(await waitUntil { model.session.phase == .live })
        model.forgetName()
        #expect(model.phase == .naming)
        #expect(model.profile.displayName == nil)
        #expect(await waitUntil { model.session.phase == .idle })
    }
}
