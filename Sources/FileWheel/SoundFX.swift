import AVFoundation

/// Small synthesised sounds (no audio files): a tick as you move between slices.
@MainActor
final class SoundFX {
    static let shared = SoundFX()
    private let rate = 44_100.0
    private var ticks: [AVAudioPlayer] = []
    private var lowTicks: [AVAudioPlayer] = []
    private var next = 0

    private init() {
        ticks = (0..<4).compactMap { _ in player(tick(freq: 2600)) }
        lowTicks = (0..<4).compactMap { _ in player(tick(freq: 1700)) }
    }

    func tick(center: Bool = false) {
        let pool = center ? lowTicks : ticks
        guard !pool.isEmpty else { return }
        next = (next + 1) % pool.count
        let p = pool[next]
        p.currentTime = 0
        p.play()
    }

    // MARK: building the sounds

    private func tick(freq: Double) -> [Float] {
        let n = Int(0.035 * rate)
        return (0..<n).map { i in
            let t = Double(i) / rate
            let body = sin(2 * .pi * freq * t) * exp(-t * 170)
            let click = Double.random(in: -1...1) * exp(-t * 520)
            return Float((body * 0.55 + click * 0.45) * 0.5)
        }
    }

    private func player(_ samples: [Float]) -> AVAudioPlayer? {
        var data = Data()
        func put<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        let pcm = samples.map { Int16(max(-1, min(1, $0)) * 32_000) }
        data.append("RIFF".data(using: .ascii)!); put(UInt32(36 + pcm.count * 2))
        data.append("WAVEfmt ".data(using: .ascii)!); put(UInt32(16)); put(UInt16(1)); put(UInt16(1))
        put(UInt32(rate)); put(UInt32(rate) * 2); put(UInt16(2)); put(UInt16(16))
        data.append("data".data(using: .ascii)!); put(UInt32(pcm.count * 2))
        pcm.forEach { put($0) }
        let p = try? AVAudioPlayer(data: data)
        p?.prepareToPlay()
        return p
    }
}
