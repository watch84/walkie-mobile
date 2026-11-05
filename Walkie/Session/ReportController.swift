import Foundation
import Observation

/// Report and local mute for the current or most recent other speaker (RadioApp's chips).
/// Report: `POST /report` with this device's credentials plus the target; never yourself.
/// Mute: local unsubscribe only, never the server.
@MainActor
@Observable
final class ReportController {
    /// How long after release the last speaker can still be reported or muted.
    nonisolated static let recentWindow: TimeInterval = 120

    private(set) var reportedIdentities: Set<String> = []
    private(set) var isSending = false

    @ObservationIgnored private let session: ChannelSession
    @ObservationIgnored private let flash: FlashLine

    init(session: ChannelSession, flash: FlashLine) {
        self.session = session
        self.flash = flash
    }

    /// The floor holder if it's someone else, otherwise whoever last held it within `recentWindow`.
    func target(at now: Date) -> FloorHolder? {
        let mine = session.credentials?.identity
        if let floor = session.floor, floor.identity != mine { return floor }
        guard let last = session.lastSpeaker, last.identity != mine else { return nil }
        if let released = session.lastSpeakerReleasedAt {
            guard now.timeIntervalSince(released) <= Self.recentWindow else { return nil }
        }
        return last
    }

    func canReport(_ target: FloorHolder) -> Bool {
        !isSending && !reportedIdentities.contains(target.identity) && target.identity != session.credentials?.identity
    }

    func report(_ target: FloorHolder) async {
        guard canReport(target), let credentials = session.credentials, let api = session.api else { return }
        isSending = true
        defer { isSending = false }
        do {
            try await api.report(ReportRequest(
                credentials: credentials,
                reportedIdentity: target.identity,
                reportedName: target.name
            ))
            reportedIdentities.insert(target.identity)
            flash.show(.reported(target.name))
        } catch {
            flash.show(.reportFailed)
        }
    }

    func toggleMute(_ target: FloorHolder) {
        guard target.identity != session.credentials?.identity else { return }
        let mute = !session.isMuted(target.identity)
        session.setMuted(mute, identity: target.identity)
        flash.show(mute ? .muted(target.name) : .unmuted(target.name))
    }
}
