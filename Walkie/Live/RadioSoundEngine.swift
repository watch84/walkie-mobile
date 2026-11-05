import AVFoundation
import os

/// Generates the radio's sound beds and detent clicks locally with `AVAudioEngine`; no audio
/// files. One mono source node mixes:
/// - static: white noise band-limited to roughly 400 Hz–6 kHz, at `SoundBed.staticLevel`
/// - room tone: leaky-integrated (brown) noise, at `SoundBed.roomToneLevel`
/// - click: a ~4 ms decaying noise burst
/// Bed gains ramp (~60 ms) so switching beds never clicks.
@MainActor
final class RadioSoundEngine: SoundBedPlaying {
    private let engine = AVAudioEngine()
    private let state = NoiseState()
    private var source: AVAudioSourceNode?
    private var configurationObserver: NSObjectProtocol?

    func setBed(_ bed: SoundBed) {
        state.staticTarget = bed == .staticHiss ? SoundBed.staticLevel : 0
        state.roomTarget = bed == .roomTone ? SoundBed.roomToneLevel : 0
        if bed != .none { startIfNeeded() }
    }

    func playDetentClick() {
        startIfNeeded()
        state.clickRequests &+= 1
    }

    private func startIfNeeded() {
        if source == nil { setUp() }
        _ = start()
    }

    private func setUp() {
        let format = engine.outputNode.inputFormat(forBus: 0)
        let sampleRate = format.sampleRate > 0 ? format.sampleRate : 48_000
        guard let mono = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return }
        state.configure(sampleRate: Float(sampleRate))

        let node = Self.makeSourceNode(format: mono, state: state)
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: mono)
        source = node

        // Route and session changes (e.g. LiveKit starting voice processing) stop the engine.
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.start() }
        }
    }

    private func start() -> Bool {
        guard !engine.isRunning else { return true }
        do {
            try engine.start()
            return true
        } catch {
            Log.audio.error("Sound engine failed to start: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Built outside the main actor: the render block runs on the audio thread, and a closure
    /// formed in a `@MainActor` context would trap there under Swift 6 isolation checks.
    private nonisolated static func makeSourceNode(format: AVAudioFormat, state: NoiseState) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frameCount, bufferList in
            state.render(frameCount: Int(frameCount), into: UnsafeMutableAudioBufferListPointer(bufferList))
            return noErr
        }
    }
}

/// Render-thread state. Targets and click requests are written from the main actor and read on
/// the audio thread; single aligned scalar writes, so a torn read is impossible in practice.
private final class NoiseState: @unchecked Sendable {
    var staticTarget: Float = 0
    var roomTarget: Float = 0
    var clickRequests: UInt32 = 0

    private var seenClicks: UInt32 = 0
    private var rng: UInt32 = 0x9E37_79B9
    private var staticGain: Float = 0
    private var roomGain: Float = 0
    private var rampCoefficient: Float = 0.001
    private var lowpass: Float = 0
    private var highpassState: Float = 0
    private var lowpassCoefficient: Float = 0.5
    private var highpassCoefficient: Float = 0.05
    private var brown: Float = 0
    private var clickSamplesLeft = 0
    private var clickLength = 200

    func configure(sampleRate: Float) {
        rampCoefficient = 1 - exp(-1 / (0.06 * sampleRate))
        lowpassCoefficient = 1 - exp(-2 * .pi * 6_000 / sampleRate)
        highpassCoefficient = 1 - exp(-2 * .pi * 400 / sampleRate)
        clickLength = Int(0.004 * sampleRate)
    }

    func render(frameCount: Int, into buffers: UnsafeMutableAudioBufferListPointer) {
        if clickRequests != seenClicks {
            seenClicks = clickRequests
            clickSamplesLeft = clickLength
        }
        guard let first = buffers.first, let data = first.mData?.assumingMemoryBound(to: Float.self) else { return }
        let staticTarget = self.staticTarget
        let roomTarget = self.roomTarget

        for frame in 0..<frameCount {
            let white = nextNoise()

            lowpass += lowpassCoefficient * (white - lowpass)
            highpassState += highpassCoefficient * (lowpass - highpassState)
            let hiss = (lowpass - highpassState) * 1.6

            brown = (brown + 0.02 * white) / 1.02
            let room = brown * 3.5

            staticGain += rampCoefficient * (staticTarget - staticGain)
            roomGain += rampCoefficient * (roomTarget - roomGain)

            var sample = hiss * staticGain + room * roomGain
            if clickSamplesLeft > 0 {
                let envelope = Float(clickSamplesLeft) / Float(max(clickLength, 1))
                sample += white * envelope * envelope * 0.12
                clickSamplesLeft -= 1
            }
            data[frame] = sample
        }
        for buffer in buffers.dropFirst() {
            if let other = buffer.mData { memcpy(other, data, Int(buffer.mDataByteSize)) }
        }
    }

    /// xorshift32 mapped to [-1, 1); allocation- and lock-free for the render thread.
    private func nextNoise() -> Float {
        rng ^= rng << 13
        rng ^= rng >> 17
        rng ^= rng << 5
        return Float(rng) / Float(UInt32.max) * 2 - 1
    }
}
