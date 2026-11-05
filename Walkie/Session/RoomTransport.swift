import Foundation

/// What `ChannelSession` needs from a media room. The app uses LiveKit (`LiveKitTransport`);
/// tests use a fake.
enum RoomEvent: Equatable, Sendable {
    case metadata(String?)
    /// Everyone in the room, including this device.
    case participantCount(Int)
    case speaking(Set<String>)
    case reconnecting
    case reconnected
    case disconnected(String?)
}

typealias RoomEventHandler = @MainActor @Sendable (RoomEvent) -> Void

@MainActor
protocol RoomTransport: AnyObject {
    /// Connects subscribe-only and plays remote audio. Emits the current metadata and
    /// participant count once connected, then live updates.
    func connect(url: URL, token: String, onEvent: @escaping RoomEventHandler) async throws
    func disconnect() async
}
