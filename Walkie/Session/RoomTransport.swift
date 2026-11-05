import Foundation

/// What `ChannelSession` needs from a media room. The app uses LiveKit (`LiveKitTransport`);
/// tests use a fake.
enum RoomEvent: Equatable, Sendable {
    case metadata(String?)
    /// Everyone in the room, including this device.
    case participantCount(Int)
    case speaking(Set<String>)
    /// The server grants `canPublish` to the floor holder only.
    case publishPermission(Bool)
    case reconnecting
    case reconnected
    case disconnected(String?)
}

typealias RoomEventHandler = @MainActor @Sendable (RoomEvent) -> Void

@MainActor
protocol RoomTransport: AnyObject {
    /// Connects (subscribe-only until the server grants publish) and plays remote audio. Emits the
    /// current metadata, participant count and publish permission once connected, then live updates.
    func connect(url: URL, token: String, onEvent: @escaping RoomEventHandler) async throws
    func disconnect() async
    /// Publishes or unpublishes the local microphone track.
    func setMicrophone(enabled: Bool) async throws
}
