import Foundation
import Observation

/// Platform services `AppModel` uses; `.live` (LiveKit, AVAudioSession, URLSession) is in `Walkie/Live`.
struct AppDependencies {
    var makeTransport: @MainActor () -> any RoomTransport
    var makeAPI: @MainActor (URL) -> any WalkieAPIClient
    var activateAudio: @MainActor () -> Void
    var microphone: @MainActor () -> any MicrophoneAuthorizing
    var chirps: @MainActor () -> any ChirpPlaying
    var retryDelay: Duration = .seconds(10)
    var grantTimeout: Duration = TalkController.defaultGrantTimeout
}

@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case naming
        case tuneIn
        case radio
    }

    let profile: ProfileStore
    let debug: DebugSettings
    let session: ChannelSession
    let talk: TalkController

    private(set) var phase: Phase
    private(set) var selectedChannel: ChannelInfo = .defaultChannel

    /// Per launch, like the web app's audio unlock; only the name persists. Submitting the
    /// name screen counts as the unlocking tap, as it does on web.
    private(set) var audioUnlocked = false

    @ObservationIgnored private let dependencies: AppDependencies

    init(profile: ProfileStore, debug: DebugSettings, dependencies: AppDependencies) {
        self.profile = profile
        self.debug = debug
        self.dependencies = dependencies
        session = ChannelSession(retryDelay: dependencies.retryDelay, makeTransport: dependencies.makeTransport)
        talk = TalkController(
            session: session,
            microphone: dependencies.microphone(),
            chirps: dependencies.chirps(),
            grantTimeout: dependencies.grantTimeout
        )
        phase = profile.hasDisplayName ? .tuneIn : .naming
    }

    convenience init(defaults: UserDefaults = .standard, dependencies: AppDependencies) {
        self.init(
            profile: ProfileStore(defaults: defaults),
            debug: DebugSettings(defaults: defaults),
            dependencies: dependencies
        )
    }

    @discardableResult
    func submitName(_ raw: String) -> Result<String, DisplayName.ValidationError> {
        let result = profile.setDisplayName(raw)
        if case .success = result {
            unlockAndListen()
        }
        return result
    }

    func tuneIn() {
        guard profile.hasDisplayName else {
            phase = .naming
            return
        }
        unlockAndListen()
    }

    func select(_ channel: ChannelInfo) {
        guard channel != selectedChannel else { return }
        selectedChannel = channel
        listen()
    }

    func editName() {
        talk.release()
        phase = .naming
    }

    /// Backgrounding or termination ends any transmission and gives the floor back.
    func appWillResignActive() {
        talk.appWillResignActive()
    }

    func forgetName() {
        talk.release()
        profile.clearDisplayName()
        phase = .naming
        Task { await session.stop() }
    }

    private func unlockAndListen() {
        if !audioUnlocked {
            dependencies.activateAudio()
            audioUnlocked = true
        }
        phase = .radio
        listen()
    }

    private func listen() {
        guard let name = profile.displayName else { return }
        guard !session.isTuned(to: selectedChannel, as: name) else { return }
        session.tune(to: selectedChannel, name: name) { [weak self] in self?.endpoint() }
    }

    /// Read on every join attempt so Debug settings edits apply on the next retry.
    private func endpoint() -> ChannelSession.Endpoint? {
        guard let base = debug.apiBaseURLValue else { return nil }
        return ChannelSession.Endpoint(api: dependencies.makeAPI(base), liveKitFallback: debug.liveKitURLValue)
    }
}
