import Foundation
import Testing
@testable import Walkie

func freshDefaults(_ name: String = #function) -> UserDefaults {
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
    let microphone = FakeMicrophone()
    let chirps = FakeChirps()
    let sounds = FakeSounds()
    let haptics = FakeHaptics()
    private(set) var audioActivations = 0
    private(set) var audioHandler: (@MainActor (AudioSessionEvent) -> Void)?
    private(set) var apiBaseURLs: [URL] = []

    init(_ responses: [Result<TokenResponse, WalkieAPIError>] = [.success(makeToken())]) {
        api = FakeAPI(responses)
    }

    var dependencies: AppDependencies {
        AppDependencies(
            makeTransport: { [factory] in factory.make() },
            makeAPI: { [self] url in apiBaseURLs.append(url); return api },
            activateAudio: { [self] in audioActivations += 1 },
            microphone: { [microphone] in microphone },
            chirps: { [chirps] in chirps },
            sounds: { [sounds] in sounds },
            haptics: { [haptics] in haptics },
            observeAudioSession: { [self] handler in audioHandler = handler },
            tunerTiming: fastTiming,
            grantTimeout: .milliseconds(100)
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

        #expect(await waitUntil { model.tuner.phase == .live })
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
        #expect(model.tuner.phase == .idle)

        model.tuneIn()
        #expect(model.phase == .radio)
        #expect(model.audioUnlocked)
        #expect(await waitUntil { model.tuner.phase == .live })
    }

    @Test func editNameReturnsStraightToRadioAndRejoinsWithNewName() async {
        let defaults = freshDefaults()
        let harness = AppHarness()
        ProfileStore(defaults: defaults).setDisplayName("Margaret")
        let model = harness.model(defaults)
        model.tuneIn()
        #expect(await waitUntil { model.tuner.phase == .live })

        model.editName()
        #expect(model.phase == .naming)

        model.submitName("Margaret  Hamilton")
        #expect(model.phase == .radio)
        #expect(model.profile.displayName == "Margaret Hamilton")
        #expect(harness.audioActivations == 1)
        #expect(await waitUntil { harness.factory.made.count == 2 && model.tuner.phase == .live })
        #expect(await harness.api.requests.last == TokenRequest(channel: "channel-1", name: "Margaret Hamilton"))
    }

    @Test func unchangedNameDoesNotRejoin() async {
        let harness = AppHarness()
        let model = harness.model(freshDefaults())
        model.submitName("Ada")
        #expect(await waitUntil { model.tuner.phase == .live })

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
        #expect(await waitUntil { model.tuner.phase == .live })

        model.selectStation(stationIndex("channel-3"))
        #expect(model.station.channel?.id == "channel-3")
        #expect(await waitUntil { harness.factory.made.count == 2 && model.tuner.phase == .live })
        #expect(await harness.api.requests.last == TokenRequest(channel: "channel-3", name: "Ada"))
    }

    @Test func stationPersistsAndLockedNeverConnects() async {
        let defaults = freshDefaults()
        let harness = AppHarness()
        let model = harness.model(defaults)
        #expect(model.station.index == Stations.defaultIndex)
        model.submitName("Ada")
        #expect(await waitUntil { model.tuner.phase == .live })

        model.selectStation(9)
        #expect(model.tuner.phase == .locked)
        #expect(defaults.integer(forKey: "walkie:station") == 9)

        let relaunched = AppHarness().model(defaults)
        #expect(relaunched.station.name == "Weather Desk")
        relaunched.tuneIn()
        #expect(relaunched.tuner.phase == .locked)
        try? await Task.sleep(for: .milliseconds(60))
        #expect(relaunched.session.isOpen == false)
    }

    @Test func bedFollowsPhaseAndFloor() async {
        let harness = AppHarness()
        let model = harness.model(freshDefaults())
        #expect(model.currentBed == .none)

        model.submitName("Ada")
        #expect(model.currentBed == .staticHiss)
        #expect(await waitUntil { harness.sounds.beds.last == .roomTone })

        harness.factory.last!.emit(.metadata(metaJSON(seq: 1, floor: ("u-2", "Grace"))))
        #expect(await waitUntil { harness.sounds.beds.last == SoundBed.none })

        harness.factory.last!.emit(.metadata(metaJSON(seq: 2)))
        #expect(await waitUntil { harness.sounds.beds.last == .roomTone })

        model.selectStation(0)
        #expect(await waitUntil { harness.sounds.beds.last == .staticHiss })
        #expect(harness.sounds.beds == [.staticHiss, .roomTone, .none, .roomTone, .staticHiss])
    }

    @Test func detentFeedbackClicksOnlyAfterUnlock() {
        let harness = AppHarness()
        let model = harness.model(freshDefaults())
        model.detentCrossed()
        #expect(harness.haptics.detents == 1)
        #expect(harness.sounds.clicks == 0)
        model.submitName("Ada")
        model.detentCrossed()
        #expect(harness.haptics.detents == 2)
        #expect(harness.sounds.clicks == 1)
    }

    @Test func backgroundingReleasesTheFloor() async {
        let harness = AppHarness()
        let model = harness.model(freshDefaults())
        model.submitName("Ada")
        #expect(await waitUntil { model.tuner.phase == .live })

        model.talk.press()
        #expect(await waitUntil { model.talk.phase == .keying })
        harness.factory.last!.emit(.publishPermission(true))
        #expect(await waitUntil { model.talk.phase == .live })

        model.appWillResignActive()
        #expect(model.talk.phase == .idle)
        let creds = makeToken(name: "Ada").floorCredentials(channel: "channel-1")
        #expect(await eventually { await harness.api.floorCalls == [.request(creds), .release(creds)] })
    }

    @Test func forgetNameReturnsToNamingAndStops() async {
        let harness = AppHarness()
        let model = harness.model(freshDefaults())
        model.submitName("Ada")
        #expect(await waitUntil { model.tuner.phase == .live })
        model.forgetName()
        #expect(model.phase == .naming)
        #expect(model.profile.displayName == nil)
        #expect(await waitUntil { model.tuner.phase == .idle })
    }
}
