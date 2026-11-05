import Foundation
import Testing
@testable import Walkie

struct ProtocolCodableTests {
    @Test func tokenResponseDecodesServerJSON() throws {
        let json = #"{"url":"/livekit","token":"jwt","identity":"u-1","name":"Ada","key":"secret","channel":"channel-1"}"#
        let token = try JSONDecoder().decode(TokenResponse.self, from: Data(json.utf8))
        #expect(token == TokenResponse(url: "/livekit", token: "jwt", identity: "u-1", name: "Ada", key: "secret", channel: "channel-1"))
    }

    @Test func tokenResponseRoundTrips() throws {
        let token = makeToken(url: "ws://10.0.0.5:7880")
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: JSONEncoder().encode(token))
        #expect(decoded == token)
    }

    @Test func floorCredentialsComeFromToken() throws {
        let creds = makeToken().floorCredentials
        #expect(creds == FloorCredentials(channel: "channel-1", identity: "id-Ada", name: "Ada", key: "k-Ada"))
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(creds)) as? [String: String]
        #expect(object.map { Set($0.keys) } == ["channel", "identity", "name", "key"])
    }

    @Test func roomMetaDecodesFloorAndNull() {
        #expect(RoomMeta.decode(metaJSON(seq: 3)) == RoomMeta(seq: 3, floor: nil))
        let held = RoomMeta.decode(metaJSON(seq: 4, floor: ("u-2", "Grace")))
        #expect(held?.floor?.identity == "u-2")
        #expect(held?.floor?.name == "Grace")
        #expect(held?.floor?.startedAt == 1_730_000_000_000)
    }

    @Test func roomMetaToleratesMissingOrBadMetadata() {
        #expect(RoomMeta.decode(nil) == nil)
        #expect(RoomMeta.decode("") == nil)
        #expect(RoomMeta.decode("not json") == nil)
        #expect(RoomMeta.decode(#"{"seq":1}"#) == RoomMeta(seq: 1, floor: nil))
    }

    @Test func roomMetaRoundTrips() throws {
        let meta = RoomMeta(seq: 9, floor: FloorHolder(identity: "u", name: "N", startedAt: nil))
        #expect(try JSONDecoder().decode(RoomMeta.self, from: JSONEncoder().encode(meta)) == meta)
    }

    @Test func staleSeqIsIgnored() {
        let current = RoomMeta(seq: 5, floor: nil)
        #expect(RoomMeta.isFresh(RoomMeta(seq: 1, floor: nil), after: nil))
        #expect(RoomMeta.isFresh(RoomMeta(seq: 6, floor: nil), after: current))
        #expect(!RoomMeta.isFresh(RoomMeta(seq: 5, floor: nil), after: current))
        #expect(!RoomMeta.isFresh(RoomMeta(seq: 4, floor: nil), after: current))
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

        let floor = try api.makeRequest("floor/request", body: makeToken().floorCredentials)
        #expect(floor.url?.absoluteString == "http://127.0.0.1:8787/floor/request")
    }
}
