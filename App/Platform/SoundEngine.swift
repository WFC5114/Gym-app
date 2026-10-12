import AVFoundation
import os

/// Material sounds synthesised in code (no samples, no system sounds).
/// The audio session is `.ambient`: it honours the silent switch and mixes with
/// workout music instead of interrupting it.
enum SoundEvent: Int {
    /// Rubber mallet against granite: a food block landing on the deck.
    case mallet
    /// Barbell against a steel rack: SET DONE seats the hourglass.
    case rack
    /// Rotary encoder detent: ruler and stepper ticks.
    case detent
    /// Vault door seating: the prism locking on a face.
    case seat
    /// A knuckle on glass: the rest has run out.
    case glassTap
}

final class SoundEngine {
    static let shared = SoundEngine()

    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private let synth = OSAllocatedUnfairLock(uncheckedState: Synth())
    private var started = false

    static let enabledKey = "sound.enabled"
    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey) }
    }

    /// Fixtures and UI tests stay silent.
    var isMuted = false

    private func startIfNeeded() -> Bool {
        guard isEnabled, !isMuted else { return false }
        if started { return true }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
            let sampleRate = rate > 0 ? rate : 48_000
            guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return false }
            let synth = self.synth
            synth.withLock { $0.sampleRate = Float(sampleRate) }
            let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
                let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
                guard let data = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
                synth.withLock { $0.render(into: data, frames: Int(frameCount)) }
                return noErr
            }
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            engine.mainMixerNode.outputVolume = 0.9
            try engine.start()
            source = node
            started = true
            return true
        } catch {
            return false
        }
    }

    /// Plays a one-shot. `intensity` 0...1 scales level; `pitch` is a bounded multiplier
    /// (gesture velocity may raise it slightly).
    func play(_ event: SoundEvent, intensity: Float = 1, pitch: Float = 1) {
        guard startIfNeeded() else { return }
        let p = min(max(pitch, 0.8), 1.25)
        synth.withLock { $0.trigger(event, amp: min(max(intensity, 0), 1), pitch: p) }
    }

    /// Continuous vault grind while the prism turns: 0 = silent.
    func setGrind(_ level: Float) {
        guard started || level > 0.01 else { return }
        guard startIfNeeded() else { return }
        synth.withLock { $0.grindTarget = min(max(level, 0), 1) }
    }
}

/// Fixed-capacity voice pool. Rendering never allocates.
private struct Synth {
    struct Voice {
        var event: SoundEvent = .mallet
        var t: Float = 0
        var amp: Float = 0
        var pitch: Float = 1
        var active = false
        var lp: Float = 0
    }

    var sampleRate: Float = 48_000
    var voices = [Voice](repeating: Voice(), count: 12)
    var rng: UInt32 = 0x9E37_79B9
    var grindTarget: Float = 0
    var grindLevel: Float = 0
    var grindLP: Float = 0
    var grindPhase: Float = 0

    mutating func noise() -> Float {
        rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5
        return Float(rng) / Float(UInt32.max) * 2 - 1
    }

    mutating func trigger(_ event: SoundEvent, amp: Float, pitch: Float) {
        // Slight variation so repeated actions never sound identical.
        let vary = 1 + noise() * 0.03
        let level = amp * (1 + noise() * 0.08)
        let slot = voices.firstIndex { !$0.active } ?? voices.indices.max { voices[$0].t < voices[$1].t } ?? 0
        voices[slot] = Voice(event: event, t: 0, amp: level, pitch: pitch * vary, active: true, lp: 0)
    }

    static let rackFreq: [Float] = [218, 561, 1187, 2043, 3127]
    static let rackGain: [Float] = [0.42, 0.3, 0.22, 0.13, 0.08]
    static let rackDecay: [Float] = [6, 8.5, 12, 17, 24]

    static func duration(_ e: SoundEvent) -> Float {
        switch e {
        case .mallet: return 0.5
        case .rack: return 1.1
        case .detent: return 0.04
        case .seat: return 0.4
        case .glassTap: return 1.2
        }
    }

    mutating func render(into out: UnsafeMutablePointer<Float>, frames: Int) {
        let dt = 1 / sampleRate
        let twoPi = Float.pi * 2
        for i in 0..<frames {
            var s: Float = 0
            for v in voices.indices where voices[v].active {
                let t = voices[v].t
                let p = voices[v].pitch
                let a = voices[v].amp
                var x: Float = 0
                switch voices[v].event {
                case .mallet:
                    // Dull rubber body with a falling pitch, then a short stone tick.
                    let f = 92 * p * (1 + 1.4 * expf(-t * 38))
                    x += sinf(twoPi * f * t) * expf(-t * 13) * 0.9
                    let n = noise()
                    voices[v].lp += (n - voices[v].lp) * 0.18
                    x += voices[v].lp * expf(-t * 260) * 0.7
                    x += sinf(twoPi * 1750 * p * t) * expf(-t * 70) * 0.06
                case .rack:
                    // Inharmonic steel partials over a low thud.
                    for k in 0..<Self.rackFreq.count {
                        x += sinf(twoPi * Self.rackFreq[k] * p * t) * Self.rackGain[k] * expf(-t * Self.rackDecay[k])
                    }
                    x += sinf(twoPi * 68 * t) * expf(-t * 22) * 0.6
                    x += noise() * expf(-t * 320) * 0.5
                case .detent:
                    x += noise() * expf(-t * 900) * 0.6
                    x += sinf(twoPi * 3300 * p * t) * expf(-t * 260) * 0.25
                case .seat:
                    x += sinf(twoPi * 54 * p * t) * expf(-t * 16) * 0.9
                    let n = noise()
                    voices[v].lp += (n - voices[v].lp) * 0.08
                    x += voices[v].lp * expf(-t * 90) * 0.9
                case .glassTap:
                    x += sinf(twoPi * 1318 * p * t) * expf(-t * 6) * 0.22
                    x += sinf(twoPi * 1977 * p * t) * expf(-t * 9) * 0.14
                    x += sinf(twoPi * 3290 * p * t) * expf(-t * 15) * 0.06
                }
                s += x * a
                voices[v].t = t + dt
                if voices[v].t > Self.duration(voices[v].event) { voices[v].active = false }
            }
            // Grind: low-passed noise with a slow judder, following prism speed.
            grindLevel += (grindTarget - grindLevel) * 0.0015
            if grindLevel > 0.001 {
                grindPhase += 23 * dt
                if grindPhase > 1 { grindPhase -= 1 }
                let n = noise()
                grindLP += (n - grindLP) * (0.02 + 0.05 * grindLevel)
                s += grindLP * grindLevel * (0.7 + 0.3 * sinf(twoPi * grindPhase)) * 0.9
            }
            out[i] = max(-1, min(1, s * 0.8))
        }
    }
}
