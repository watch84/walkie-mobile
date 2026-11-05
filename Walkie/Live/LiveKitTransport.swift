import Foundation
import LiveKit
import os

/// `RoomTransport` backed by a LiveKit `Room`. The `/token` grant is subscribe-only; the server
/// grants `canPublish` to the floor holder, and only then is the mic published. Remote audio
/// tracks are auto-subscribed and played by the SDK.
@MainActor
final class LiveKitTransport: RoomTransport {
    private var room: Room?
    private var bridge: RoomDelegateBridge?

    func connect(url: URL, token: String, onEvent: @escaping RoomEventHandler) async throws {
        let bridge = RoomDelegateBridge { event in
            Task { @MainActor in onEvent(event) }
        }
        let room = Room(delegate: bridge)
        self.room = room
        self.bridge = bridge

        Log.session.info("Connecting to \(url.absoluteString, privacy: .public)")
        do {
            try await room.connect(url: url.absoluteString, token: token)
        } catch {
            Log.session.error("Connect failed: \(String(describing: error), privacy: .public)")
            await disconnect()
            throw error
        }

        onEvent(.metadata(room.metadata))
        onEvent(.participantCount(RoomDelegateBridge.participantCount(room)))
        onEvent(.publishPermission(room.localParticipant.permissions.canPublish))
    }

    func setMicrophone(enabled: Bool) async throws {
        guard let room else { return }
        try await room.localParticipant.setMicrophone(enabled: enabled)
    }

    func disconnect() async {
        guard let room else { return }
        self.room = nil
        await room.disconnect()
        bridge = nil
    }
}

/// LiveKit calls delegates off the main actor; this forwards plain-value events.
private final class RoomDelegateBridge: NSObject, RoomDelegate, @unchecked Sendable {
    private let emit: @Sendable (RoomEvent) -> Void

    init(emit: @escaping @Sendable (RoomEvent) -> Void) {
        self.emit = emit
    }

    static func participantCount(_ room: Room) -> Int {
        room.remoteParticipants.count + 1
    }

    func room(_ room: Room, didUpdateMetadata metadata: String?) {
        emit(.metadata(metadata))
    }

    func room(_ room: Room, participantDidConnect participant: RemoteParticipant) {
        emit(.participantCount(Self.participantCount(room)))
    }

    func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) {
        emit(.participantCount(Self.participantCount(room)))
    }

    func room(_ room: Room, didUpdateSpeakingParticipants participants: [Participant]) {
        emit(.speaking(Set(participants.compactMap { $0.identity?.stringValue })))
    }

    func room(_ room: Room, participant: Participant, didUpdatePermissions permissions: ParticipantPermissions) {
        guard participant is LocalParticipant else { return }
        emit(.publishPermission(permissions.canPublish))
    }

    func roomIsReconnecting(_ room: Room) {
        emit(.reconnecting)
    }

    func roomDidReconnect(_ room: Room) {
        emit(.reconnected)
        emit(.metadata(room.metadata))
        emit(.participantCount(Self.participantCount(room)))
    }

    func room(_ room: Room, didDisconnectWithError error: LiveKitError?) {
        emit(.disconnected(error.map { String(describing: $0) }))
    }
}
