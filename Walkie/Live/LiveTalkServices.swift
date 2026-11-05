import AVFoundation
import os

@MainActor
final class SystemMicrophone: MicrophoneAuthorizing {
    var permission: MicrophonePermission {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: .granted
        case .denied: .denied
        case .undetermined: .undetermined
        @unknown default: .undetermined
        }
    }

    func request() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }
}

/// Plays the synthesized chirps through the shared `.playAndRecord` session.
@MainActor
final class ToneChirps: ChirpPlaying {
    private let startPlayer = ToneChirps.makePlayer(ToneSynth.start)
    private let endPlayer = ToneChirps.makePlayer(ToneSynth.end)

    func playStart() {
        endPlayer?.stop()
        replay(startPlayer)
    }

    func playEnd() {
        startPlayer?.stop()
        replay(endPlayer)
    }

    private func replay(_ player: AVAudioPlayer?) {
        guard let player else { return }
        player.currentTime = 0
        player.play()
    }

    private static func makePlayer(_ segments: [ToneSynth.Segment]) -> AVAudioPlayer? {
        do {
            let player = try AVAudioPlayer(data: ToneSynth.wav(segments), fileTypeHint: AVFileType.wav.rawValue)
            player.prepareToPlay()
            return player
        } catch {
            Log.audio.error("Chirp setup failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
