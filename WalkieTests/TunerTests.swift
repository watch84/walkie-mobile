import Foundation
import Testing
@testable import Walkie

@MainActor
final class TunerHarness {
    let factory = TransportFactory()
    let api: FakeAPI
    let session: ChannelSession
    let tuner: Tuner
    let fallback = URL(string: "ws://127.0.0.1:7880")!

    init(
        _ tokens: [Result<TokenResponse, WalkieAPIError>] = [.success(makeToken())],
        station: Int = Stations.defaultIndex,
        timing: Tuner.Timing = fastTiming
    ) {
        api = FakeAPI(tokens)
        session = ChannelSession { [factory] in factory.make() }
        tuner = Tuner(session: session, stationIndex: station, timing: timing)
    }

    func start(name: String = "Ada") {
        tuner.start(name: name) { [api, fallback] in Tuner.Endpoint(api: api, liveKitFallback: fallback) }
    }

    func tokenRequests() async -> [TokenRequest] { await api.requests }
}

@MainActor
struct TunerTests {
    @Test func stationsMatchWeb() {
        #expect(Stations.all.count == 12)
        #expect(Stations.all.map(\.frequency) == [
            "88.1", "89.7", "91.3", "92.9", "94.5", "96.1", "97.7", "99.3", "100.9", "102.5", "104.1", "105.7",
        ])
        #expect(Stations.all.map(\.name) == [
            "Morning Static", "Night Shift", "Field Notes", "Channel 1", "Channel 2", "Channel 3",
            "Lo-Fi Desk", "Open Mic", "Late Bus", "Weather Desk", "Quiet Car", "Deep Sea",
        ])
        #expect(Stations.all.map { $0.channel?.id } == [
            nil, nil, nil, "channel-1", "channel-2", "channel-3", nil, nil, nil, nil, nil, nil,
        ])
        #expect(Stations.defaultIndex == 3)
        #expect(Stations.all.filter(\.isLocked).count == 9)
        #expect(ChannelInfo.live.map(\.name) == ["Channel 1", "Channel 2", "Channel 3"])
    }

    @Test func idleUntilStarted() async {
        let h = TunerHarness()
        #expect(h.tuner.phase == .idle)
        h.tuner.setStation(4)
        try? await Task.sleep(for: .milliseconds(60))
        #expect(await h.tokenRequests().isEmpty)
        #expect(h.tuner.stationIndex == 4)
    }

    @Test func liveStationConnectsAfterDebounce() async {
        let h = TunerHarness()
        h.start()
        #expect(h.tuner.phase == .tuning)
        try? await Task.sleep(for: .milliseconds(10))
        #expect(await h.tokenRequests().isEmpty)

        #expect(await waitUntil { h.tuner.phase == .live })
        #expect(await h.tokenRequests() == [TokenRequest(channel: "channel-1", name: "Ada")])
        #expect(h.factory.last?.connectedURL == h.fallback)
        #expect(h.session.credentials?.channel == "channel-1")
    }

    @Test func lockedStationNeverTouchesNetwork() async {
        let h = TunerHarness(station: 0)
        h.start()
        #expect(h.tuner.phase == .locked)
        try? await Task.sleep(for: .milliseconds(80))
        #expect(h.tuner.phase == .locked)
        #expect(await h.tokenRequests().isEmpty)
        #expect(h.factory.made.isEmpty)
    }

    @Test func movingToLockedClosesSessionImmediately() async {
        let h = TunerHarness()
        h.start()
        #expect(await waitUntil { h.tuner.phase == .live })
        let room = h.factory.last!

        h.tuner.setStation(6)
        #expect(h.tuner.phase == .locked)
        #expect(await waitUntil { room.disconnected })
        #expect(!h.session.isOpen)
        try? await Task.sleep(for: .milliseconds(60))
        #expect(await h.tokenRequests().count == 1)
    }

    @Test func movingBetweenLiveStationsClosesThenDebounces() async {
        let h = TunerHarness()
        h.start()
        #expect(await waitUntil { h.tuner.phase == .live })
        let first = h.factory.last!

        h.tuner.setStation(stationIndex("channel-2"))
        #expect(h.tuner.phase == .tuning)
        #expect(await waitUntil { first.disconnected })
        #expect(await waitUntil { h.tuner.phase == .live && h.factory.made.count == 2 })
        #expect(await h.tokenRequests().last == TokenRequest(channel: "channel-2", name: "Ada"))
        #expect(h.session.credentials?.channel == "channel-2")
    }

    @Test func fastScrollConnectsOnlyTheRestedStation() async {
        let h = TunerHarness(station: 0)
        h.start()
        for index in 1...8 {
            h.tuner.setStation(index)
            try? await Task.sleep(for: .milliseconds(5))
        }
        h.tuner.setStation(stationIndex("channel-3"))
        #expect(h.tuner.phase == .tuning)

        #expect(await waitUntil { h.tuner.phase == .live })
        #expect(await h.tokenRequests() == [TokenRequest(channel: "channel-3", name: "Ada")])
        #expect(h.factory.made.count == 1)
    }

    @Test func fastScrollEndingOnLockedMakesNoCalls() async {
        let h = TunerHarness(station: 0)
        h.start()
        for index in [1, 2, 3, 4, 5, 6, 7] {
            h.tuner.setStation(index)
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(h.tuner.phase == .locked)
        try? await Task.sleep(for: .milliseconds(80))
        #expect(await h.tokenRequests().isEmpty)
    }

    @Test func tokenThatArrivesAfterDialMovedIsDropped() async {
        let h = TunerHarness()
        await h.api.setTokenDelay(.milliseconds(60))
        h.start()
        #expect(await eventually { await h.tokenRequests().count == 1 })

        h.tuner.setStation(0)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(h.tuner.phase == .locked)
        #expect(h.factory.made.isEmpty)
        #expect(!h.session.isOpen)
    }

    @Test func connectionThatFinishesAfterDialMovedIsDropped() async {
        let h = TunerHarness()
        h.factory.connectDelay = .milliseconds(60)
        h.start()
        #expect(await waitUntil { h.factory.made.count == 1 })

        h.tuner.setStation(1)
        #expect(await waitUntil { h.factory.last?.disconnected == true })
        #expect(h.tuner.phase == .locked)
        #expect(!h.session.isOpen)
    }

    @Test func offAirTokenRetriesAfterOffAirDelay() async {
        let h = TunerHarness([.failure(.offAir), .success(makeToken())])
        h.start()
        #expect(await waitUntil { h.tuner.phase == .offAir })
        #expect(await h.tokenRequests().count == 1)
        try? await Task.sleep(for: .milliseconds(30))
        #expect(await h.tokenRequests().count == 1)
        #expect(await waitUntil { h.tuner.phase == .live })
        #expect(await h.tokenRequests().count == 2)
    }

    @Test func otherTokenFailureIsErrorAndRetries() async {
        let h = TunerHarness([.failure(.network("refused")), .success(makeToken())])
        h.start()
        #expect(await waitUntil { h.tuner.phase == .error })
        #expect(await waitUntil { h.tuner.phase == .live })
    }

    @Test func roomEndingOffAirGoesOffAirAndRetries() async {
        let h = TunerHarness([.success(makeToken()), .failure(.offAir), .success(makeToken())])
        h.start()
        #expect(await waitUntil { h.tuner.phase == .live })
        let room = h.factory.last!

        room.emit(.metadata(metaJSON(seq: 2, offAir: true)))
        #expect(h.tuner.phase == .offAir)
        #expect(!h.session.isOpen)
        #expect(await waitUntil { room.disconnected })
        #expect(await waitUntil { h.tuner.phase == .live && h.factory.made.count == 2 })
        #expect(await h.tokenRequests().count == 3)
    }

    @Test func roomEndingOtherwiseRetunesAfterRetryDelay() async {
        let h = TunerHarness()
        h.start()
        #expect(await waitUntil { h.tuner.phase == .live })

        h.factory.last!.emit(.disconnected("server went away"))
        #expect(h.tuner.phase == .tuning)
        try? await Task.sleep(for: .milliseconds(15))
        #expect(h.factory.made.count == 1)
        #expect(await waitUntil { h.tuner.phase == .live && h.factory.made.count == 2 })
    }

    @Test func offAirInInitialMetadataIsOffAir() async {
        var joins = 0
        let h = TunerHarness()
        h.factory.configure = { transport in
            joins += 1
            transport.initialMetadata = metaJSON(seq: 1, offAir: joins == 1)
        }
        h.start()
        #expect(await waitUntil { h.tuner.phase == .offAir })
        #expect(h.factory.made.first?.disconnected == true)
        #expect(await waitUntil { h.tuner.phase == .live && h.factory.made.count == 2 })
    }

    @Test func movingAwayCancelsPendingRetry() async {
        let h = TunerHarness([.failure(.offAir)])
        h.start()
        #expect(await waitUntil { h.tuner.phase == .offAir })
        h.tuner.setStation(0)
        try? await Task.sleep(for: .milliseconds(120))
        #expect(h.tuner.phase == .locked)
        #expect(await h.tokenRequests().count == 1)
    }

    @Test func retuneWithNewNameReconnects() async {
        let h = TunerHarness()
        h.start(name: "Ada")
        #expect(await waitUntil { h.tuner.phase == .live })
        h.tuner.retune(name: "Ada")
        try? await Task.sleep(for: .milliseconds(50))
        #expect(h.factory.made.count == 1)

        h.tuner.retune(name: "Grace")
        #expect(await waitUntil { h.tuner.phase == .live && h.factory.made.count == 2 })
        #expect(await h.tokenRequests().last == TokenRequest(channel: "channel-1", name: "Grace"))
    }

    @Test func stopClosesAndGoesIdle() async {
        let h = TunerHarness()
        h.start()
        #expect(await waitUntil { h.tuner.phase == .live })
        await h.tuner.stop()
        #expect(h.tuner.phase == .idle)
        #expect(h.factory.last?.disconnected == true)
        h.tuner.setStation(4)
        try? await Task.sleep(for: .milliseconds(60))
        #expect(await h.tokenRequests().count == 1)
    }

    @Test func missingEndpointIsError() async {
        let h = TunerHarness()
        h.tuner.start(name: "Ada") { nil }
        #expect(await waitUntil { h.tuner.phase == .error })
        await h.tuner.stop()
    }
}

@MainActor
struct ChannelSessionTests {
    let factory = TransportFactory()
    let token = makeToken()
    let url = URL(string: "ws://127.0.0.1:7880")!

    private func open(_ session: ChannelSession) async throws {
        try await session.open(token: token, channel: .defaultChannel, url: url, api: FakeAPI([.success(token)]))
    }

    @Test func floorComesFromMetadataAndIgnoresStaleSeq() async throws {
        factory.configure = { $0.initialMetadata = metaJSON(seq: 2); $0.initialCount = 3 }
        let session = ChannelSession { [factory] in factory.make() }
        try await open(session)
        #expect(session.isOpen)
        #expect(session.meta?.seq == 2)
        #expect(session.floor == nil)
        #expect(session.listenerCount == 3)

        let room = factory.last!
        room.emit(.metadata(metaJSON(seq: 5, floor: ("u-2", "Grace"))))
        #expect(session.floor?.name == "Grace")
        #expect(session.isFloorHeldByOther)

        room.emit(.metadata(metaJSON(seq: 4)))
        #expect(session.floor?.name == "Grace")

        room.emit(.metadata("garbage"))
        #expect(session.meta?.seq == 5)

        room.emit(.speaking(["u-2"]))
        #expect(session.isFloorHolderSpeaking)
        room.emit(.speaking(["someone-else"]))
        #expect(!session.isFloorHolderSpeaking)

        room.emit(.metadata(metaJSON(seq: 6, floor: ("id-Ada", "Ada"))))
        #expect(session.isFloorHeldByMe)
        #expect(!session.isFloorHeldByOther)
    }

    @Test func eventsFromClosedRoomAreIgnored() async throws {
        let session = ChannelSession { [factory] in factory.make() }
        try await open(session)
        let first = factory.last!
        await session.close()
        #expect(first.disconnected)
        #expect(!session.isOpen)
        first.emit(.metadata(metaJSON(seq: 99, floor: ("ghost", "Old room"))))
        #expect(session.floor == nil)
    }

    @Test func reconnectingKeepsRoom() async throws {
        let session = ChannelSession { [factory] in factory.make() }
        try await open(session)
        factory.last!.emit(.reconnecting)
        #expect(session.isReconnecting)
        #expect(session.isOpen)
        factory.last!.emit(.reconnected)
        #expect(!session.isReconnecting)
    }

    @Test func endsReportReason() async throws {
        let session = ChannelSession { [factory] in factory.make() }
        var ends: [ChannelSession.EndReason] = []
        session.onEnded = { ends.append($0) }
        try await open(session)
        factory.last!.emit(.disconnected("bye"))
        #expect(ends == [.disconnected("bye")])
        #expect(!session.isOpen)

        try await open(session)
        factory.last!.emit(.metadata(metaJSON(seq: 1, offAir: true)))
        #expect(ends == [.disconnected("bye"), .offAir])

        try await open(session)
        await session.close()
        #expect(ends.count == 2)
    }
}

struct DialMotionTests {
    private func settle(_ motion: inout DialMotion, maxSeconds: Double = 5) -> Double {
        var t = 0.0
        while motion.step(1.0 / 120), t < maxSeconds { t += 1.0 / 120 }
        return t
    }

    @Test func constantsMatchWeb() {
        #expect(DialMotion.rubberLimit == 1.6)
        #expect(DialMotion.coastTau == 0.24)
        #expect(DialMotion.settleOmega == 18)
        #expect(DialMotion.bounceOmega == 26)
    }

    @Test func rubberBandIsBoundedAndMonotonic() {
        #expect(DialMotion.rubber(0) == 0)
        #expect(DialMotion.rubber(-1) == 0)
        var last = 0.0
        for overshoot in stride(from: 0.1, through: 100, by: 0.1) {
            let shown = DialMotion.rubber(overshoot)
            #expect(shown > last)
            #expect(shown < DialMotion.rubberLimit)
            #expect(shown <= overshoot)
            last = shown
        }
        #expect(abs(DialMotion.rubber(0.001) - 0.001) < 0.00001)
    }

    @Test func dragPastEndsIsRubberBanded() {
        var motion = DialMotion(count: 12, index: 0)
        motion.drag(to: -10)
        #expect(motion.position < 0)
        #expect(motion.position > -DialMotion.rubberLimit)
        motion.drag(to: 30)
        #expect(motion.position > 11)
        #expect(motion.position < 11 + DialMotion.rubberLimit)
        motion.drag(to: 5.3)
        #expect(motion.position == 5.3)
    }

    @Test func restingIndexProjectsVelocity() {
        #expect(DialMotion.restingIndex(position: 3, velocity: 0, count: 12) == 3)
        #expect(DialMotion.restingIndex(position: 3.4, velocity: 0, count: 12) == 3)
        #expect(DialMotion.restingIndex(position: 3.6, velocity: 0, count: 12) == 4)
        #expect(DialMotion.restingIndex(position: 3, velocity: 10, count: 12) == 5)
        #expect(DialMotion.restingIndex(position: 3, velocity: -10, count: 12) == 1)
        #expect(DialMotion.restingIndex(position: 3, velocity: 500, count: 12) == 11)
        #expect(DialMotion.restingIndex(position: 3, velocity: -500, count: 12) == 0)
    }

    @Test func slowReleaseSettlesOnNearestDetent() {
        var motion = DialMotion(count: 12, index: 3)
        motion.beginDrag()
        motion.drag(to: 4.4)
        motion.endDrag(velocity: 0.5)
        #expect(motion.restingIndex == 4)
        let t = settle(&motion)
        #expect(motion.isResting)
        #expect(motion.position == 4)
        #expect(t < 1)
    }

    @Test func flickCoastsToProjectedDetent() {
        var motion = DialMotion(count: 12, index: 3)
        motion.beginDrag()
        motion.drag(to: 3.2)
        motion.endDrag(velocity: 12)
        let target = motion.restingIndex
        #expect(target == DialMotion.restingIndex(position: 3.2, velocity: 12, count: 12))
        _ = settle(&motion)
        #expect(motion.isResting)
        #expect(motion.position == Double(target))
    }

    @Test func flickPastEndBouncesBack() {
        var motion = DialMotion(count: 12, index: 10)
        motion.beginDrag()
        motion.drag(to: 10.5)
        motion.endDrag(velocity: 60)
        var maxSeen = motion.position
        while motion.step(1.0 / 120) { maxSeen = max(maxSeen, motion.position) }
        #expect(motion.position == 11)
        #expect(maxSeen < 11 + DialMotion.rubberLimit + 1)
    }

    @Test func releasePastEndSpringsToEnd() {
        var motion = DialMotion(count: 12, index: 0)
        motion.beginDrag()
        motion.drag(to: -3)
        motion.endDrag(velocity: 0)
        #expect(motion.restingIndex == 0)
        _ = settle(&motion)
        #expect(motion.position == 0)
    }

    @Test func reduceMotionSkipsCoast() {
        var motion = DialMotion(count: 12, index: 3)
        motion.beginDrag()
        motion.drag(to: 3.2)
        motion.endDrag(velocity: 40, reduceMotion: true)
        #expect(motion.restingIndex == 3)
        _ = settle(&motion)
        #expect(motion.position == 3)
    }

    @Test func glideMovesToTarget() {
        var motion = DialMotion(count: 12, index: 3)
        motion.glide(to: 4)
        #expect(motion.restingIndex == 4)
        _ = settle(&motion)
        #expect(motion.position == 4)
        motion.glide(to: 99)
        #expect(motion.restingIndex == 11)
    }

    @Test func settleNeverOvershootsADetentFromRest() {
        var motion = DialMotion(count: 12, index: 3)
        motion.beginDrag()
        motion.drag(to: 3.45)
        motion.endDrag(velocity: 0)
        var minSeen = motion.position
        while motion.step(1.0 / 120) { minSeen = min(minSeen, motion.position) }
        #expect(minSeen >= 3 - 0.0001)
    }

    @Test func dragFromMidBounceDoesNotJump() {
        var motion = DialMotion(count: 12, index: 0)
        motion.drag(to: -2)
        let shown = motion.position
        let origin = motion.beginDrag()
        motion.drag(to: origin)
        #expect(abs(motion.position - shown) < 0.001)
    }
}

struct SoundBedTests {
    @Test func bedRules() {
        #expect(SoundBed.bed(for: .live, floorHeld: true, talking: false) == .none)
        #expect(SoundBed.bed(for: .live, floorHeld: false, talking: true) == .none)
        #expect(SoundBed.bed(for: .live, floorHeld: false, talking: false) == .roomTone)
        #expect(SoundBed.bed(for: .offAir, floorHeld: false, talking: false) == .none)
        #expect(SoundBed.bed(for: .locked, floorHeld: false, talking: false) == .staticHiss)
        #expect(SoundBed.bed(for: .tuning, floorHeld: false, talking: false) == .staticHiss)
        #expect(SoundBed.bed(for: .error, floorHeld: false, talking: false) == .staticHiss)
        #expect(SoundBed.roomTone.level == 0.018)
        #expect(SoundBed.staticHiss.level == 0.05)
    }
}
