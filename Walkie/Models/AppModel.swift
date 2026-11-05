import Foundation
import Observation

@MainActor
protocol SoundBedPlaying: AnyObject {
    func setBed(_ bed: SoundBed)
    /// Short tick for a dial detent.
    func playDetentClick()
    /// Restarts output after an audio interruption or session reset.
    func resume()
}

/// `AVAudioSession` notifications `AppModel` reacts to.
enum AudioSessionEvent: Equatable, Sendable {
    /// Phone call, Siri, alarm, or another app took audio.
    case interruptionBegan
    case interruptionEnded
    /// Media services reset, or the category/route was changed out from under the app.
    case needsReactivation
}

@MainActor
protocol HapticsPlaying: AnyObject {
    func detent()
}

/// Platform services `AppModel` uses; `.live` (LiveKit, AVAudioSession, URLSession) is in `Walkie/Live`.
struct AppDependencies {
    var makeTransport: @MainActor () -> any RoomTransport
    var makeAPI: @MainActor (URL) -> any WalkieAPIClient
    var activateAudio: @MainActor () -> Void
    var microphone: @MainActor () -> any MicrophoneAuthorizing
    var chirps: @MainActor () -> any ChirpPlaying
    var sounds: @MainActor () -> any SoundBedPlaying
    var haptics: @MainActor () -> any HapticsPlaying
    /// Registers a handler for audio session interruptions and resets.
    var observeAudioSession: @MainActor (@escaping @MainActor @Sendable (AudioSessionEvent) -> Void) -> Void = { _ in }
    var tunerTiming = Tuner.Timing()
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

    static let stationKey = "walkie:station"

    let profile: ProfileStore
    let debug: DebugSettings
    let tuner: Tuner
    let talk: TalkController
    let flash: FlashLine
    let report: ReportController

    var session: ChannelSession { tuner.session }
    var station: Station { tuner.station }

    private(set) var phase: Phase

    /// Per launch, like the web app's audio unlock; only the name and station persist.
    /// Submitting the name screen counts as the unlocking tap, as it does on web.
    private(set) var audioUnlocked = false
    private(set) var isAudioInterrupted = false

    var currentBed: SoundBed {
        guard audioUnlocked else { return .none }
        let talking = talk.phase == .keying || talk.phase == .live
        return SoundBed.bed(for: tuner.phase, floorHeld: session.floor != nil, talking: talking)
    }

    @ObservationIgnored private let dependencies: AppDependencies
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let sounds: any SoundBedPlaying
    @ObservationIgnored private let haptics: any HapticsPlaying
    @ObservationIgnored private var appliedBed: SoundBed = .none

    init(defaults: UserDefaults = .standard, dependencies: AppDependencies) {
        self.defaults = defaults
        self.dependencies = dependencies
        profile = ProfileStore(defaults: defaults)
        debug = DebugSettings(defaults: defaults)

        let storedStation = defaults.object(forKey: Self.stationKey) as? Int ?? Stations.defaultIndex
        let session = ChannelSession(makeTransport: dependencies.makeTransport)
        let flash = FlashLine()
        self.flash = flash
        tuner = Tuner(session: session, stationIndex: storedStation, timing: dependencies.tunerTiming)
        talk = TalkController(
            tuner: tuner,
            microphone: dependencies.microphone(),
            chirps: dependencies.chirps(),
            flash: flash,
            grantTimeout: dependencies.grantTimeout
        )
        report = ReportController(session: session, flash: flash)
        sounds = dependencies.sounds()
        haptics = dependencies.haptics()
        phase = profile.hasDisplayName ? .tuneIn : .naming
        observeBed()
        dependencies.observeAudioSession { [weak self] event in self?.handleAudioSession(event) }
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

    /// The dial came to rest on, or passed, `index`.
    func selectStation(_ index: Int) {
        tuner.setStation(index)
        defaults.set(tuner.stationIndex, forKey: Self.stationKey)
    }

    /// The dial crossed a detent while moving.
    func detentCrossed() {
        haptics.detent()
        if audioUnlocked { sounds.playDetentClick() }
    }

    func editName() {
        talk.release()
        phase = .naming
    }

    /// Backgrounding or termination ends any transmission and gives the floor back.
    func appWillResignActive() {
        talk.appWillResignActive()
    }

    /// Awaited inside a UIKit background task so the floor release reaches the server.
    func finishPendingWork() async {
        await talk.finishPendingWork()
    }

    func handleAudioSession(_ event: AudioSessionEvent) {
        switch event {
        case .interruptionBegan:
            isAudioInterrupted = true
            talk.audioInterrupted()
        case .interruptionEnded, .needsReactivation:
            isAudioInterrupted = false
            guard audioUnlocked else { return }
            dependencies.activateAudio()
            sounds.resume()
        }
    }

    func forgetName() {
        talk.release()
        profile.clearDisplayName()
        phase = .naming
        Task { await tuner.stop() }
    }

    private func unlockAndListen() {
        if !audioUnlocked {
            dependencies.activateAudio()
            audioUnlocked = true
        }
        phase = .radio
        guard let name = profile.displayName else { return }
        if tuner.isStarted {
            tuner.retune(name: name)
        } else {
            tuner.start(name: name) { [weak self] in self?.endpoint() }
        }
    }

    /// Read on every connect attempt so Debug settings edits apply on the next retry.
    private func endpoint() -> Tuner.Endpoint? {
        guard let base = debug.apiBaseURLValue else { return nil }
        return Tuner.Endpoint(api: dependencies.makeAPI(base), liveKitFallback: debug.liveKitURLValue)
    }

    private func observeBed() {
        let bed = withObservationTracking {
            currentBed
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeBed() }
        }
        guard bed != appliedBed else { return }
        appliedBed = bed
        sounds.setBed(bed)
    }
}
