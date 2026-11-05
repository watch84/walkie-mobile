import Foundation
import Testing
@testable import Walkie

struct FloorCountdownTests {
    let now = Date(timeIntervalSince1970: 1_730_000_010)

    private func holder(_ identity: String, expiresIn seconds: Double) -> FloorHolder {
        let nowMs = now.timeIntervalSince1970 * 1_000
        return FloorHolder(identity: identity, name: "N", since: nowMs - 10_000, expiresAt: nowMs + seconds * 1_000)
    }

    @Test func prefersServerExpiryForMyFloor() {
        let liveSince = now.addingTimeInterval(-3)
        let deadline = FloorCountdown.deadline(floor: holder("me", expiresIn: 20), myIdentity: "me", liveSince: liveSince, now: now)
        #expect(deadline.map { FloorCountdown.remaining(until: $0, now: now) } == 20)
        #expect(deadline.map { FloorCountdown.wholeSecondsLeft(until: $0, now: now) } == 20)
        #expect(deadline.map { FloorCountdown.fraction(until: $0, now: now) } == 20.0 / 30.0)
    }

    @Test func fallsBackToLocalThirtySeconds() {
        let liveSince = now.addingTimeInterval(-4)
        let none = FloorCountdown.deadline(floor: nil, myIdentity: "me", liveSince: liveSince, now: now)
        #expect(none.map { FloorCountdown.remaining(until: $0, now: now) } == 26)

        let someoneElse = FloorCountdown.deadline(floor: holder("other", expiresIn: 5), myIdentity: "me", liveSince: liveSince, now: now)
        #expect(someoneElse.map { FloorCountdown.remaining(until: $0, now: now) } == 26)

        #expect(FloorCountdown.deadline(floor: nil, myIdentity: "me", liveSince: nil, now: now) == nil)
    }

    @Test func ignoresSkewedServerClock() {
        let liveSince = now.addingTimeInterval(-1)
        let ahead = FloorCountdown.deadline(floor: holder("me", expiresIn: 3_600), myIdentity: "me", liveSince: liveSince, now: now)
        #expect(ahead.map { FloorCountdown.remaining(until: $0, now: now) } == 29)
        let behind = FloorCountdown.deadline(floor: holder("me", expiresIn: -60), myIdentity: "me", liveSince: liveSince, now: now)
        #expect(behind.map { FloorCountdown.remaining(until: $0, now: now) } == 29)
    }

    @Test func remainingIsClamped() {
        #expect(FloorCountdown.remaining(until: now.addingTimeInterval(-5), now: now) == 0)
        #expect(FloorCountdown.remaining(until: now.addingTimeInterval(31), now: now) == 30)
        #expect(FloorCountdown.wholeSecondsLeft(until: now.addingTimeInterval(0.2), now: now) == 1)
    }
}

@MainActor
struct TalkCountdownTests {
    @Test func liveDeadlineSwitchesToServerExpiry() async {
        let h = TalkHarness()
        await h.tuneIn()
        #expect(h.talk.deadline(now: Date()) == nil)
        await h.goLive()

        let local = h.talk.deadline(now: Date())
        #expect(local.map { abs($0.timeIntervalSince(h.talk.liveSince!) - 30) < 0.001 } == true)

        let expires = Date().addingTimeInterval(12)
        let since = expires.addingTimeInterval(-30)
        h.room.emit(.metadata(#"{"floor":{"identity":"id-Ada","name":"Ada","since":\#(since.timeIntervalSince1970 * 1_000),"expiresAt":\#(expires.timeIntervalSince1970 * 1_000)},"offAir":false,"seq":9}"#))
        let server = h.talk.deadline(now: Date())
        #expect(server.map { abs($0.timeIntervalSince(expires)) < 0.01 } == true)

        h.talk.release()
        #expect(h.talk.deadline(now: Date()) == nil)
    }
}

@MainActor
final class SpeakerHarness {
    var clock = Date(timeIntervalSince1970: 1_730_000_000)
    let factory = TransportFactory()
    let api = FakeAPI([.success(makeToken())])
    let flash = FlashLine(duration: .seconds(5))
    var session: ChannelSession!
    var tuner: Tuner!
    var report: ReportController!

    init() {
        session = ChannelSession(makeTransport: { [factory] in factory.make() }, now: { [unowned self] in self.clock })
        tuner = Tuner(session: session, timing: fastTiming)
        report = ReportController(session: session, flash: flash)
    }

    var room: FakeTransport { factory.last! }

    func tuneIn() async {
        tuner.start(name: "Ada") { [api] in Tuner.Endpoint(api: api, liveKitFallback: URL(string: "ws://127.0.0.1:7880")) }
        _ = await waitUntil { self.tuner.phase == .live }
    }

    func floor(_ seq: Int, _ holder: (String, String)?) {
        room.emit(.metadata(metaJSON(seq: seq, floor: holder.map { (identity: $0.0, name: $0.1) })))
    }
}

@MainActor
struct MuteTests {
    @Test func muteIsLocalPerIdentityAndReachesTransport() async {
        let h = SpeakerHarness()
        await h.tuneIn()
        h.floor(1, ("u-2", "Grace"))
        let grace = h.session.floor!

        h.report.toggleMute(grace)
        #expect(h.session.isMuted("u-2"))
        #expect(h.flash.message == .muted("Grace"))
        #expect(await waitUntil { h.room.mutedSets.last == ["u-2"] })

        h.report.toggleMute(grace)
        #expect(!h.session.isMuted("u-2"))
        #expect(h.flash.message == .unmuted("Grace"))
        #expect(await waitUntil { h.room.mutedSets.last == [] })

        #expect(await h.api.floorCalls.isEmpty)
        #expect(await h.api.reports.isEmpty)
    }

    @Test func muteSetIsAppliedToNewRooms() async {
        let h = SpeakerHarness()
        await h.tuneIn()
        h.session.setMuted(true, identity: "u-2")
        h.session.setMuted(true, identity: "u-3")

        h.tuner.setStation(stationIndex("channel-2"))
        #expect(await waitUntil { h.tuner.phase == .live && h.factory.made.count == 2 })
        #expect(h.room.mutedSets.last == ["u-2", "u-3"])
        #expect(h.session.isMuted("u-3"))
    }

    @Test func noTransportCallsWhenNothingMuted() async {
        let h = SpeakerHarness()
        await h.tuneIn()
        #expect(h.room.mutedSets.isEmpty)
    }

    @Test func cannotMuteYourself() async {
        let h = SpeakerHarness()
        await h.tuneIn()
        h.report.toggleMute(FloorHolder(identity: "id-Ada", name: "Ada", since: 0, expiresAt: 0))
        #expect(!h.session.isMuted("id-Ada"))
        #expect(h.flash.message == nil)
    }
}

@MainActor
struct ReportTests {
    @Test func reportSendsCredentialsPlusTarget() async {
        let h = SpeakerHarness()
        await h.tuneIn()
        h.floor(1, ("u-2", "Grace"))
        let target = h.report.target(at: h.clock)!
        #expect(target.identity == "u-2")
        #expect(h.report.canReport(target))

        await h.report.report(target)
        #expect(await h.api.reports == [ReportRequest(
            credentials: FloorCredentials(channel: "channel-1", identity: "id-Ada", name: "Ada", key: "k-Ada"),
            reportedIdentity: "u-2",
            reportedName: "Grace"
        )])
        #expect(h.flash.message == .reported("Grace"))
        #expect(!h.report.canReport(target))

        await h.report.report(target)
        #expect(await h.api.reports.count == 1)
    }

    @Test func reportFailureFlashesAndAllowsRetry() async {
        let h = SpeakerHarness()
        await h.api.setReportResults([.failure(.http(status: 500, code: nil)), .success(())])
        await h.tuneIn()
        h.floor(1, ("u-2", "Grace"))
        let target = h.report.target(at: h.clock)!

        await h.report.report(target)
        #expect(h.flash.message == .reportFailed)
        #expect(h.report.canReport(target))

        await h.report.report(target)
        #expect(h.flash.message == .reported("Grace"))
    }

    @Test func neverTargetsYourself() async {
        let h = SpeakerHarness()
        await h.tuneIn()
        h.floor(1, ("id-Ada", "Ada"))
        #expect(h.report.target(at: h.clock) == nil)
        h.floor(2, nil)
        #expect(h.report.target(at: h.clock) == nil)

        await h.report.report(FloorHolder(identity: "id-Ada", name: "Ada", since: 0, expiresAt: 0))
        #expect(await h.api.reports.isEmpty)
    }

    @Test func lastSpeakerStaysReportableForTwoMinutes() async {
        let h = SpeakerHarness()
        await h.tuneIn()
        #expect(h.report.target(at: h.clock) == nil)

        h.floor(1, ("u-2", "Grace"))
        h.clock = h.clock.addingTimeInterval(10)
        h.floor(2, nil)
        #expect(h.session.lastSpeakerReleasedAt == h.clock)
        #expect(h.report.target(at: h.clock)?.identity == "u-2")
        #expect(h.report.target(at: h.clock.addingTimeInterval(119))?.identity == "u-2")
        #expect(h.report.target(at: h.clock.addingTimeInterval(121)) == nil)

        h.floor(3, ("u-3", "Linus"))
        #expect(h.report.target(at: h.clock)?.identity == "u-3")
        h.floor(4, ("id-Ada", "Ada"))
        #expect(h.report.target(at: h.clock)?.identity == "u-3")
    }

    @Test func reportRequestJSONShape() throws {
        let request = ReportRequest(
            credentials: FloorCredentials(channel: "channel-2", identity: "me", name: "Ada", key: "k"),
            reportedIdentity: "u-2",
            reportedName: "Grace"
        )
        let api = HTTPWalkieAPI(baseURL: URL(string: "http://127.0.0.1:8787")!)
        let urlRequest = try api.makeRequest("report", body: request)
        #expect(urlRequest.url?.absoluteString == "http://127.0.0.1:8787/report")
        let object = try JSONSerialization.jsonObject(with: urlRequest.httpBody ?? Data()) as? [String: String]
        #expect(object == [
            "channel": "channel-2", "identity": "me", "name": "Ada", "key": "k",
            "reportedIdentity": "u-2", "reportedName": "Grace",
        ])
    }
}

@MainActor
struct InterruptionTests {
    private func liveModel() async -> (AppHarness, AppModel) {
        let harness = AppHarness()
        let model = harness.model(freshDefaults())
        model.submitName("Ada")
        _ = await waitUntil { model.tuner.phase == .live }
        model.talk.press()
        _ = await eventually { await harness.api.floorCalls.count == 1 }
        harness.factory.last!.emit(.publishPermission(true))
        _ = await waitUntil { model.talk.phase == .live }
        return (harness, model)
    }

    @Test func interruptionEndsTransmissionAndReleases() async {
        let (harness, model) = await liveModel()
        let creds = makeToken().floorCredentials(channel: "channel-1")

        harness.audioHandler?(.interruptionBegan)
        #expect(model.isAudioInterrupted)
        #expect(model.talk.phase == .idle)
        #expect(model.talk.flash == .transmissionEnded)
        await model.finishPendingWork()
        #expect(await harness.api.floorCalls == [.request(creds), .release(creds)])
        #expect(harness.factory.last!.micStates == [true, false])
    }

    @Test func interruptionEndRestoresAudioAndKeepsListening() async {
        let (harness, model) = await liveModel()
        let activations = harness.audioActivations

        harness.audioHandler?(.interruptionBegan)
        harness.audioHandler?(.interruptionEnded)
        #expect(!model.isAudioInterrupted)
        #expect(harness.audioActivations == activations + 1)
        #expect(harness.sounds.resumes == 1)
        #expect(model.tuner.phase == .live)
        #expect(model.session.isOpen)

        harness.audioHandler?(.needsReactivation)
        #expect(harness.audioActivations == activations + 2)
        #expect(harness.sounds.resumes == 2)
    }

    @Test func interruptionBeforeUnlockDoesNotActivateAudio() {
        let harness = AppHarness()
        _ = harness.model(freshDefaults())
        harness.audioHandler?(.interruptionEnded)
        #expect(harness.audioActivations == 0)
        #expect(harness.sounds.resumes == 0)
    }

    @Test func backgroundReleaseCanBeAwaited() async {
        let (harness, model) = await liveModel()
        model.appWillResignActive()
        await model.finishPendingWork()
        let creds = makeToken().floorCredentials(channel: "channel-1")
        #expect(await harness.api.floorCalls == [.request(creds), .release(creds)])
    }

    @Test func backgroundWhileKeyingCanBeAwaited() async {
        let harness = AppHarness()
        let model = harness.model(freshDefaults())
        model.submitName("Ada")
        _ = await waitUntil { model.tuner.phase == .live }
        model.talk.press()
        _ = await eventually { await harness.api.floorCalls.count == 1 }

        model.appWillResignActive()
        await model.finishPendingWork()
        let creds = makeToken().floorCredentials(channel: "channel-1")
        #expect(await harness.api.floorCalls == [.request(creds), .release(creds)])
    }
}
