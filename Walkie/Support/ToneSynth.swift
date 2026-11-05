import Foundation

/// Builds short 16-bit mono PCM WAV clips from tone segments, for the key-up / release chirps.
enum ToneSynth {
    struct Segment: Equatable, Sendable {
        let hz: Double
        let milliseconds: Int
    }

    /// Rising two-tone blip when the transmission goes live.
    static let start = [Segment(hz: 1_200, milliseconds: 55), Segment(hz: 1_800, milliseconds: 70)]
    /// Falling "roger" blip when it ends.
    static let end = [Segment(hz: 1_500, milliseconds: 55), Segment(hz: 900, milliseconds: 80)]

    static func wav(_ segments: [Segment], sampleRate: Int = 44_100, volume: Double = 0.35) -> Data {
        var samples: [Int16] = []
        let fade = max(1, sampleRate / 400)  // 2.5 ms ramps avoid clicks between segments
        for segment in segments {
            let count = sampleRate * segment.milliseconds / 1_000
            for i in 0..<count {
                let envelope = min(1, Double(min(i, count - 1 - i)) / Double(fade))
                let value = sin(2 * .pi * segment.hz * Double(i) / Double(sampleRate)) * volume * envelope
                samples.append(Int16((value * Double(Int16.max)).rounded()))
            }
        }

        let dataSize = samples.count * 2
        var data = Data()
        data.append(contentsOf: Array("RIFF".utf8))
        data.appendLE(UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        data.appendLE(UInt32(16))
        data.appendLE(UInt16(1))
        data.appendLE(UInt16(1))
        data.appendLE(UInt32(sampleRate))
        data.appendLE(UInt32(sampleRate * 2))
        data.appendLE(UInt16(2))
        data.appendLE(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        data.appendLE(UInt32(dataSize))
        for sample in samples { data.appendLE(UInt16(bitPattern: sample)) }
        return data
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
