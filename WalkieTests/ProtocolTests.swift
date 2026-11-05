import Foundation
import Testing
@testable import Walkie

struct ProtocolCodableTests {
    @Test func tokenResponseDecodesServerJSON() throws {
        let json = #"{"token":"jwt","url":"/livekit","identity":"u-1","name":"Ada","key":"secret"}"#
        let token = try JSONDecoder().decode(TokenResponse.self, from: Data(json.utf8))
        #expect(token == TokenResponse(url: "/livekit", token: "jwt", identity: "u-1", name: "Ada", key: "secret"))
    }

    @Test func tokenResponseIgnoresUnknownFields() throws {
        let json = #"{"token":"jwt","url":"ws://h:7880","identity":"u-1","name":"Ada","key":"k","extra":true}"#
        #expect(try JSONDecoder().decode(TokenResponse.self, from: Data(json.utf8)).url == "ws://h:7880")
    }

    @Test func tokenResponseRoundTrips() throws {
        let token = makeToken(url: "ws://10.0.0.5:7880")
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: JSONEncoder().encode(token))
        #expect(decoded == token)
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(token)) as? [String: String]
        #expect(object.map { Set($0.keys) } == ["token", "url", "identity", "name", "key"])
    }

    @Test func floorCredentialsUseRequestedChannel() throws {
        let creds = makeToken().floorCredentials(channel: "channel-2")
        #expect(creds == FloorCredentials(channel: "channel-2", identity: "id-Ada", name: "Ada", key: "k-Ada"))
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(creds)) as? [String: String]
        #expect(object.map { Set($0.keys) } == ["channel", "identity", "name", "key"])
    }

    @Test func roomMetaDecodesServerShape() {
        let idle = RoomMeta.decode(#"{"floor":null,"offAir":false,"seq":3}"#)
        #expect(idle == RoomMeta(floor: nil, offAir: false, seq: 3))

        let held = RoomMeta.decode(
            #"{"floor":{"identity":"u-2","name":"Grace","since":1730000000000,"expiresAt":1730000030000},"offAir":false,"seq":4}"#
        )
        #expect(held?.floor == FloorHolder(identity: "u-2", name: "Grace", since: 1_730_000_000_000, expiresAt: 1_730_000_030_000))
        #expect(held.map { $0.floor!.expiresAt - $0.floor!.since } == Double(WalkieProtocol.floorMaxMs))

        let offAir = RoomMeta.decode(#"{"floor":null,"offAir":true,"seq":7}"#)
        #expect(offAir?.offAir == true)
    }

    @Test func roomMetaRejectsMissingOrBadMetadata() {
        #expect(RoomMeta.decode(nil) == nil)
        #expect(RoomMeta.decode("") == nil)
        #expect(RoomMeta.decode("not json") == nil)
        #expect(RoomMeta.decode(#"{"seq":1}"#) == nil)
        #expect(RoomMeta.decode(#"{"floor":{"identity":"u","name":"N","startedAt":1},"offAir":false,"seq":1}"#) == nil)
    }

    @Test func roomMetaRoundTrips() throws {
        let meta = RoomMeta(floor: FloorHolder(identity: "u", name: "N", since: 1, expiresAt: 30_001), offAir: true, seq: 9)
        #expect(try JSONDecoder().decode(RoomMeta.self, from: JSONEncoder().encode(meta)) == meta)
    }

    @Test func staleSeqIsIgnored() {
        func meta(_ seq: Int) -> RoomMeta { RoomMeta(floor: nil, offAir: false, seq: seq) }
        let current = meta(5)
        #expect(RoomMeta.isFresh(meta(1), after: nil))
        #expect(RoomMeta.isFresh(meta(6), after: current))
        #expect(!RoomMeta.isFresh(meta(5), after: current))
        #expect(!RoomMeta.isFresh(meta(4), after: current))
    }

    @Test func floorMaxMatchesWeb() {
        #expect(WalkieProtocol.floorMaxMs == 30_000)
    }

    @Test func liveChannels() {
        #expect(ChannelInfo.live.map(\.id) == ["channel-1", "channel-2", "channel-3"])
        #expect(ChannelInfo.defaultChannel.id == "channel-1")
        #expect(ChannelInfo.defaultChannel.name == "Channel 1")
    }
}

struct LiveKitURLTests {
    let fallback = URL(string: "ws://127.0.0.1:7880")!

    @Test func relativeURLUsesFallback() {
        #expect(LiveKitURL.resolve("/livekit", fallback: fallback) == fallback)
        #expect(LiveKitURL.resolve("", fallback: fallback) == fallback)
        #expect(LiveKitURL.resolve("livekit", fallback: fallback) == fallback)
        #expect(LiveKitURL.resolve("/livekit", fallback: nil) == nil)
    }

    @Test func absoluteURLIsKept() {
        #expect(LiveKitURL.resolve("ws://192.168.1.20:7880", fallback: fallback)?.absoluteString == "ws://192.168.1.20:7880")
        #expect(LiveKitURL.resolve(" wss://lk.example.com ", fallback: fallback)?.absoluteString == "wss://lk.example.com")
    }

    @Test func httpSchemesMapToWebSocket() {
        #expect(LiveKitURL.resolve("http://10.0.0.2:7880", fallback: fallback)?.absoluteString == "ws://10.0.0.2:7880")
        #expect(LiveKitURL.resolve("https://lk.example.com", fallback: fallback)?.absoluteString == "wss://lk.example.com")
    }
}

struct APIErrorTests {
    private func body(_ json: String) -> Data { Data(json.utf8) }

    @Test func offAirFromCode() {
        #expect(WalkieAPIError.from(status: 403, body: body(#"{"error":"Channel is off air","code":"off_air"}"#)) == .offAir)
        #expect(WalkieAPIError.from(status: 403, body: body(#"{"error":"off_air"}"#)) == .offAir)
    }

    @Test func otherForbiddenIsNotOffAir() {
        #expect(WalkieAPIError.from(status: 403, body: body(#"{"code":"locked"}"#)) == .http(status: 403, code: "locked"))
        #expect(WalkieAPIError.from(status: 403, body: Data()) == .http(status: 403, code: nil))
    }

    @Test func busyAndBadKey() {
        #expect(WalkieAPIError.from(status: 409, body: body(#"{"code":"busy"}"#)) == .busy)
        #expect(WalkieAPIError.from(status: 401, body: Data()) == .badKey)
    }

    @Test func successIsNotAnError() {
        #expect(WalkieAPIError.from(status: 200, body: Data()) == nil)
        #expect(WalkieAPIError.from(status: 204, body: Data()) == nil)
    }

    @Test func nonJSONServerError() {
        #expect(WalkieAPIError.from(status: 500, body: body("<html>")) == .http(status: 500, code: nil))
    }

    @Test func tokenRequestShape() throws {
        let api = HTTPWalkieAPI(baseURL: URL(string: "http://127.0.0.1:8787")!)
        let request = try api.makeRequest("token", body: TokenRequest(channel: "channel-1", name: "Ada"))
        #expect(request.url?.absoluteString == "http://127.0.0.1:8787/token")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let sent = try JSONDecoder().decode(TokenRequest.self, from: request.httpBody ?? Data())
        #expect(sent == TokenRequest(channel: "channel-1", name: "Ada"))

        let floor = try api.makeRequest("floor/request", body: makeToken().floorCredentials(channel: "channel-1"))
        #expect(floor.url?.absoluteString == "http://127.0.0.1:8787/floor/request")
    }
}
