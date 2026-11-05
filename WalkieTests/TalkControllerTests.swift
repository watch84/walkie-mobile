import Foundation
import Testing
@testable import Walkie

@MainActor
final class TalkHarness {
    let factory = TransportFactory()
    let api: FakeAPI
    let microphone: FakeMicrophone
    let chirps = FakeChirps()
    let session: ChannelSession
    let tuner: Tuner
    let talk: TalkController
    let creds = makeToken().floorCredentials(channel: "channel-1")

    init(
        floor: [Result<Void, WalkieAPIError>] = [.success(())],
        microphone: FakeMicrophone = FakeMicrophone(),
        grantTimeout: Duration = .milliseconds(80)
    ) {
        api = FakeAPI([.success(makeToken())], floor: floor)
        self.microphone = microphone
        session = ChannelSession { [factory] in factory.make() }
        tuner = Tuner(session: session, timing: fastTiming)
        talk = TalkController(
            tuner: tuner,
            microphone: microphone,
            chirps: chirps,
            flash: FlashLine(duration: .seconds(5)),
            grantTimeout: grantTimeout
        )
    }

    var room: FakeTransport { factory.last! }

    func tuneIn() async {
        tuner.start(name: "Ada") { [api] in
            Tuner.Endpoint(api: api, liveKitFallback: URL(string: "ws://127.0.0.1:7880"))
        }
        _ = await waitUntil { self.tuner.phase == .live }
    }

    func floorCalls() async -> [FloorCall] { await api.floorCalls }

    /// Presses and lets the server grant publish, ending live.
    func goLive() async {
        talk.press()
        _ = await eventually { await self.api.floorCalls.count == 1 }
        room.emit(.publishPermission(true))
        _ = await waitUntil { self.talk.phase == .live }
    }
}

@MainActor
struct TalkControllerTests {
    @Test func pressRequestsFloorWaitsForGrantThenPublishes() async {
        let h = TalkHarness()
        await h.tuneIn()
        #expect(h.talk.buttonState == .ready)

        h.talk.press()
        #expect(h.talk.phase == .keying)
        #expect(h.talk.buttonState == .keying)
        #expect(await eventually { await h.floorCalls() == [.request(h.creds)] })
        try? await Task.sleep(for: .milliseconds(20))
        #expect(h.room.micStates.isEmpty)

        h.room.emit(.publishPermission(true))
        #expect(await waitUntil { h.talk.phase == .live })
        #expect(h.room.micStates == [true])
        #expect(h.chirps.starts == 1)
        #expect(h.talk.liveSince != nil)
        #expect(h.talk.buttonState == .live)

        h.talk.release()
        #expect(h.talk.phase == .idle)
        #expect(h.talk.liveSince == nil)
        #expect(h.chirps.ends == 1)
        #expect(await eventually { await h.floorCalls() == [.request(h.creds), .release(h.creds)] })
        #expect(await waitUntil { h.room.micStates == [true, false] })
        #expect(h.talk.flash == nil)
    }

    @Test func busyFlashesChannelBusyAndNeverPublishes() async {
        let h = TalkHarness(floor: [.failure(.busy)])
        await h.tuneIn()
        h.talk.press()
        #expect(await waitUntil { h.talk.flash == .busy })
        #expect(h.talk.phase == .idle)
        #expect(await h.floorCalls() == [.request(h.creds)])
        #expect(h.room.micStates.isEmpty)
        #expect(h.chirps.starts == 0)
    }

    @Test func offAirFlashesOffAir() async {
        let h = TalkHarness(floor: [.failure(.offAir)])
        await h.tuneIn()
        h.talk.press()
        #expect(await waitUntil { h.talk.flash == .offAir })
        #expect(h.talk.phase == .idle)
        #expect(h.room.micStates.isEmpty)
    }

    @Test func otherErrorsFlashKeyUpFailed() async {
        let h = TalkHarness(floor: [.failure(.http(status: 500, code: nil))])
        await h.tuneIn()
        h.talk.press()
        #expect(await waitUntil { h.talk.flash == .keyUpFailed })
        #expect(h.talk.phase == .idle)
    }

    @Test func grantTimeoutReleasesAndFlashes() async {
        let h = TalkHarness(grantTimeout: .milliseconds(40))
        await h.tuneIn()
        h.talk.press()
        #expect(await waitUntil { h.talk.flash == .keyUpFailed })
        #expect(h.talk.phase == .idle)
        #expect(await eventually { await h.floorCalls() == [.request(h.creds), .release(h.creds)] })
        #expect(h.room.micStates.isEmpty)
        #expect(h.chirps.starts == 0)

        h.room.emit(.publishPermission(true))
        try? await Task.sleep(for: .milliseconds(20))
        #expect(h.talk.phase == .idle)
        #expect(h.room.micStates.isEmpty)
    }

    @Test func releaseBeforeGrantGivesFloorBack() async {
        let h = TalkHarness(grantTimeout: .seconds(5))
        await h.tuneIn()
        h.talk.press()
        #expect(await eventually { await h.floorCalls().count == 1 })

        h.talk.release()
        #expect(h.talk.phase == .idle)
        #expect(await eventually { await h.floorCalls() == [.request(h.creds), .release(h.creds)] })

        h.room.emit(.publishPermission(true))
        try? await Task.sleep(for: .milliseconds(20))
        #expect(h.talk.phase == .idle)
        #expect(h.room.micStates.isEmpty)
        #expect(h.talk.flash == nil)
    }

    @Test func releaseDuringFloorRequestGivesFloorBack() async {
        let h = TalkHarness()
        await h.tuneIn()
        await h.api.setFloorDelay(.milliseconds(30))
        h.talk.press()
        h.talk.release()
        #expect(h.talk.phase == .idle)
        #expect(await eventually { await h.floorCalls() == [.request(h.creds), .release(h.creds)] })
        #expect(h.room.micStates.isEmpty)
    }

    @Test func backgroundWhileLiveReleases() async {
        let h = TalkHarness()
        await h.tuneIn()
        await h.goLive()

        h.talk.appWillResignActive()
        #expect(h.talk.phase == .idle)
        #expect(await eventually { await h.floorCalls() == [.request(h.creds), .release(h.creds)] })
        #expect(await waitUntil { h.room.micStates == [true, false] })
        #expect(h.talk.flash == nil)
    }

    @Test func backgroundWhileKeyingReleases() async {
        let h = TalkHarness(grantTimeout: .seconds(5))
        await h.tuneIn()
        h.talk.press()
        #expect(await eventually { await h.floorCalls().count == 1 })
        h.talk.appWillResignActive()
        #expect(await eventually { await h.floorCalls() == [.request(h.creds), .release(h.creds)] })
        #expect(h.room.micStates.isEmpty)
    }

    @Test func serverRevokeEndsTransmission() async {
        let h = TalkHarness()
        await h.tuneIn()
        await h.goLive()

        h.room.emit(.publishPermission(false))
        #expect(h.talk.phase == .idle)
        #expect(h.talk.flash == .transmissionEnded)
        #expect(h.chirps.ends == 1)
        #expect(await waitUntil { h.room.micStates == [true, false] })
        try? await Task.sleep(for: .milliseconds(20))
        #expect(await h.floorCalls() == [.request(h.creds)])

        h.talk.release()
        try? await Task.sleep(for: .milliseconds(20))
        #expect(await h.floorCalls() == [.request(h.creds)])
    }

    @Test func floorTakenByOtherEndsTransmission() async {
        let h = TalkHarness()
        await h.tuneIn()
        h.room.emit(.metadata(metaJSON(seq: 1)))
        await h.goLive()
        h.room.emit(.metadata(metaJSON(seq: 2, floor: ("id-Ada", "Ada"))))
        #expect(h.talk.phase == .live)

        h.room.emit(.metadata(metaJSON(seq: 3, floor: ("u-2", "Grace"))))
        #expect(h.talk.phase == .idle)
        #expect(h.talk.flash == .transmissionEnded)
        #expect(h.talk.buttonState == .busy)
    }

    @Test func roomLossEndsTransmissionAndReleases() async {
        let h = TalkHarness()
        await h.tuneIn()
        await h.goLive()

        h.room.emit(.disconnected("gone"))
        #expect(h.tuner.phase == .tuning)
        #expect(h.talk.phase == .idle)
        #expect(h.talk.flash == .transmissionEnded)
        #expect(h.talk.buttonState == .tuning)
        #expect(await eventually { await h.floorCalls() == [.request(h.creds), .release(h.creds)] })
    }

    @Test func micFailureReleasesAndFlashes() async {
        let h = TalkHarness()
        await h.tuneIn()
        h.room.micError = WalkieAPIError.network("no mic")
        h.talk.press()
        #expect(await eventually { await h.floorCalls().count == 1 })
        h.room.emit(.publishPermission(true))
        #expect(await waitUntil { h.talk.flash == .keyUpFailed })
        #expect(h.talk.phase == .idle)
        #expect(await eventually { await h.floorCalls() == [.request(h.creds), .release(h.creds)] })
    }

    @Test func firstPressOnlyRequestsMicrophone() async {
        let h = TalkHarness(microphone: FakeMicrophone(.undetermined, grantOnRequest: true))
        await h.tuneIn()

        h.talk.press()
        #expect(h.talk.phase == .requestingPermission)
        h.talk.release()
        #expect(await waitUntil { h.talk.phase == .idle })
        #expect(h.microphone.requestCount == 1)
        #expect(await h.floorCalls().isEmpty)
        #expect(h.talk.flash == nil)

        await h.goLive()
        #expect(h.talk.phase == .live)
        #expect(h.microphone.requestCount == 1)
    }

    @Test func deniedMicrophoneFlashesBlocked() async {
        let h = TalkHarness(microphone: FakeMicrophone(.undetermined, grantOnRequest: false))
        await h.tuneIn()

        h.talk.press()
        #expect(await waitUntil { h.talk.flash == .micBlocked })
        #expect(h.talk.phase == .idle)

        h.talk.press()
        #expect(h.talk.flash == .micBlocked)
        #expect(h.microphone.requestCount == 1)
        #expect(await h.floorCalls().isEmpty)
    }

    @Test func otherHolderDisablesButton() async {
        let h = TalkHarness()
        await h.tuneIn()
        h.room.emit(.metadata(metaJSON(seq: 1, floor: ("u-2", "Grace"))))
        #expect(h.talk.buttonState == .busy)

        h.talk.press()
        #expect(h.talk.flash == .busy)
        #expect(h.talk.phase == .idle)
        try? await Task.sleep(for: .milliseconds(20))
        #expect(await h.floorCalls().isEmpty)

        h.room.emit(.metadata(metaJSON(seq: 2)))
        #expect(h.talk.buttonState == .ready)
    }

    @Test func buttonStateFollowsSession() async {
        let h = TalkHarness()
        #expect(h.talk.buttonState == .tuning)
        h.talk.press()
        #expect(h.talk.phase == .idle)

        await h.tuneIn()
        #expect(h.talk.buttonState == .ready)

        h.room.emit(.metadata(metaJSON(seq: 1, offAir: true)))
        #expect(h.talk.buttonState == .offAir)
        h.talk.press()
        #expect(h.talk.flash == .offAir)
        #expect(await h.floorCalls().isEmpty)
    }

    @Test func lockedStationLocksButton() async {
        let h = TalkHarness()
        await h.tuneIn()
        h.tuner.setStation(0)
        #expect(h.talk.buttonState == .locked)
        h.talk.press()
        #expect(h.talk.phase == .idle)
        #expect(h.talk.flash == nil)
        #expect(await h.floorCalls().isEmpty)
    }

    @Test func movingDialWhileLiveEndsTransmission() async {
        let h = TalkHarness()
        await h.tuneIn()
        await h.goLive()
        h.tuner.setStation(stationIndex("channel-2"))
        #expect(h.talk.phase == .idle)
        #expect(h.talk.buttonState == .tuning)
        #expect(await eventually { await h.floorCalls() == [.request(h.creds), .release(h.creds)] })
    }

    @Test func tunerErrorShowsNoSignal() async {
        let h = TalkHarness()
        h.tuner.start(name: "Ada") { nil }
        #expect(await waitUntil { h.talk.buttonState == .noSignal })
        await h.tuner.stop()
    }

    @Test func reconnectingShowsTuning() async {
        let h = TalkHarness()
        await h.tuneIn()
        h.room.emit(.reconnecting)
        #expect(h.talk.buttonState == .tuning)
        h.room.emit(.reconnected)
        #expect(h.talk.buttonState == .ready)
    }

    @Test func pressWhileAlreadyGrantedGoesLiveWithoutWaiting() async {
        let h = TalkHarness(grantTimeout: .seconds(5))
        await h.tuneIn()
        h.room.emit(.publishPermission(true))
        h.talk.press()
        #expect(await waitUntil { h.talk.phase == .live })
    }
}

struct ToneSynthTests {
    @Test func buildsValidWavHeader() {
        let data = ToneSynth.wav([.init(hz: 1_000, milliseconds: 10)], sampleRate: 8_000)
        let bytes = [UInt8](data)
        #expect(String(decoding: bytes[0..<4], as: UTF8.self) == "RIFF")
        #expect(String(decoding: bytes[8..<16], as: UTF8.self) == "WAVEfmt ")
        #expect(String(decoding: bytes[36..<40], as: UTF8.self) == "data")
        #expect(data.count == 44 + 80 * 2)
    }

    @Test func chirpsAreShort() {
        #expect(ToneSynth.start.map(\.milliseconds).reduce(0, +) < 200)
        #expect(ToneSynth.end.map(\.milliseconds).reduce(0, +) < 200)
    }
}
