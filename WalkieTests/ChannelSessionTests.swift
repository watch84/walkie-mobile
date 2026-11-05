import Foundation
import Testing
@testable import Walkie

@MainActor
struct ChannelSessionTests {
    let factory = TransportFactory()
    let fallback = URL(string: "ws://127.0.0.1:7880")!

    private func makeSession() -> ChannelSession {
        ChannelSession(retryDelay: .milliseconds(20)) { [factory] in factory.make() }
    }

    private func endpoint(_ api: FakeAPI) -> ChannelSession.EndpointProvider {
        { [fallback] in ChannelSession.Endpoint(api: api, liveKitFallback: fallback) }
    }

    @Test func joinsWithFallbackURLForRelativeTokenURL() async {
        let api = FakeAPI([.success(makeToken(url: "/livekit"))])
        let session = makeSession()
        session.tune(to: .defaultChannel, name: "Ada", endpoint: endpoint(api))
        #expect(session.phase == .tuningIn)

        #expect(await waitUntil { session.phase == .live })
        #expect(factory.last?.connectedURL == fallback)
        #expect(factory.last?.token == "jwt-channel-1")
        #expect(session.credentials?.key == "k-Ada")
        #expect(await api.requests == [TokenRequest(channel: "channel-1", name: "Ada")])
    }

    @Test func offAirRetriesUntilLive() async {
        let api = FakeAPI([.failure(.offAir), .failure(.offAir), .success(makeToken())])
        let session = makeSession()
        session.tune(to: .defaultChannel, name: "Ada", endpoint: endpoint(api))

        #expect(await waitUntil { session.phase == .offAir })
        #expect(await waitUntil { session.phase == .live })
        #expect(await api.requests.count == 3)
    }

    @Test func networkFailureIsNoSignal() async {
        let api = FakeAPI([.failure(.network("refused"))])
        let session = makeSession()
        session.tune(to: .defaultChannel, name: "Ada", endpoint: endpoint(api))
        #expect(await waitUntil { session.phase == .noSignal })
        await session.stop()
        #expect(session.phase == .idle)
    }

    @Test func floorComesFromMetadataAndIgnoresStaleSeq() async {
        factory.configure = { $0.initialMetadata = metaJSON(seq: 2); $0.initialCount = 3 }
        let session = makeSession()
        session.tune(to: .defaultChannel, name: "Ada", endpoint: endpoint(FakeAPI([.success(makeToken())])))
        #expect(await waitUntil { session.phase == .live })
        #expect(session.meta?.seq == 2)
        #expect(session.floor == nil)
        #expect(session.listenerCount == 3)

        let room = factory.last!
        room.emit(.metadata(metaJSON(seq: 5, floor: ("u-2", "Grace"))))
        #expect(session.floor?.name == "Grace")

        room.emit(.metadata(metaJSON(seq: 4)))
        #expect(session.floor?.name == "Grace")

        room.emit(.metadata("garbage"))
        #expect(session.meta?.seq == 5)

        room.emit(.speaking(["u-2"]))
        #expect(session.isFloorHolderSpeaking)
        room.emit(.speaking(["someone-else"]))
        #expect(!session.isFloorHolderSpeaking)

        room.emit(.metadata(metaJSON(seq: 6)))
        #expect(session.floor == nil)
    }

    @Test func disconnectRejoins() async {
        let session = makeSession()
        session.tune(to: .defaultChannel, name: "Ada", endpoint: endpoint(FakeAPI([.success(makeToken())])))
        #expect(await waitUntil { session.phase == .live })
        let first = factory.last!

        first.emit(.disconnected("server went away"))
        #expect(session.phase == .noSignal)
        #expect(session.meta == nil)

        #expect(await waitUntil { session.phase == .live && factory.made.count == 2 })
        first.emit(.metadata(metaJSON(seq: 99, floor: ("ghost", "Old room"))))
        #expect(session.floor == nil)
    }

    @Test func reconnectingKeepsSession() async {
        let session = makeSession()
        session.tune(to: .defaultChannel, name: "Ada", endpoint: endpoint(FakeAPI([.success(makeToken())])))
        #expect(await waitUntil { session.phase == .live })
        factory.last!.emit(.reconnecting)
        #expect(session.phase == .reconnecting)
        factory.last!.emit(.reconnected)
        #expect(session.phase == .live)
        #expect(factory.made.count == 1)
    }

    @Test func retuningDisconnectsPreviousRoom() async {
        let api = FakeAPI([.success(makeToken())])
        let session = makeSession()
        session.tune(to: .defaultChannel, name: "Ada", endpoint: endpoint(api))
        #expect(await waitUntil { session.phase == .live })
        let first = factory.last!

        session.tune(to: ChannelInfo.live[1], name: "Ada", endpoint: endpoint(api))
        #expect(await waitUntil { first.disconnected && session.phase == .live && factory.made.count == 2 })
        #expect(session.channel.id == "channel-2")
        #expect(await api.requests.last == TokenRequest(channel: "channel-2", name: "Ada"))
    }

    @Test func missingEndpointIsNoSignal() async {
        let session = makeSession()
        session.tune(to: .defaultChannel, name: "Ada") { nil }
        #expect(await waitUntil { session.phase == .noSignal })
        await session.stop()
    }
}
