import AVFoundation
import UIKit

/// Short original sounds, synthesized on the device: no audio files, licences or downloads.
/// A distribution can replace any of them with a data asset named `Sound-<rawValue>`.
enum SabboSound: String, CaseIterable {
  case tick, step, submit, gradeLow, gradeMid, gradeHigh, star, chestKnock, chestOpen, prize, wear, streak, peer, unlock
}

enum SabboHaptic { case tap, step, tick(Double), knock, open, success }

struct SabboTone {
  var frequency: Double
  var start: Double
  var duration: Double
  var gain = 0.5
  var glide = 1.0  // Frequency multiplier reached at the end of the tone.
  var bell = false // Inharmonic partials for sparkles and chimes.
  var noise = 0.0  // Filtered noise share, for whooshes and knocks.
}

enum SoundRecipe {
  static let sampleRate = 44_100.0
  private static func arpeggio(_ notes: [Double], every: Double, from: Double = 0, duration: Double, gain: Double, bell: Bool = true) -> [SabboTone] {
    notes.enumerated().map { SabboTone(frequency: $1, start: from + Double($0) * every, duration: duration, gain: gain, bell: bell) }
  }
  static func tones(_ sound: SabboSound) -> [SabboTone] {
    switch sound {
    case .tick: return [SabboTone(frequency: 1760, start: 0, duration: 0.04, gain: 0.4, bell: true)]
    case .step: return arpeggio([659.25, 987.77], every: 0.06, duration: 0.14, gain: 0.4, bell: false)
    case .submit:
      return [SabboTone(frequency: 320, start: 0, duration: 0.26, gain: 0.3, glide: 2.6, noise: 0.6)]
        + arpeggio([783.99, 1174.66], every: 0.08, from: 0.18, duration: 0.32, gain: 0.4)
    case .gradeLow: return arpeggio([392, 523.25], every: 0.16, duration: 0.5, gain: 0.4, bell: false)
    case .gradeMid: return arpeggio([523.25, 659.25, 783.99], every: 0.1, duration: 0.5, gain: 0.38)
    case .gradeHigh:
      return arpeggio([523.25, 659.25, 783.99, 1046.5], every: 0.09, duration: 0.5, gain: 0.36)
        + [523.25, 659.25, 783.99].map { SabboTone(frequency: $0, start: 0.38, duration: 0.95, gain: 0.2) }
        + arpeggio([2093, 2637], every: 0.12, from: 0.45, duration: 0.5, gain: 0.12)
    case .star: return arpeggio([1567.98, 2349.32], every: 0.04, duration: 0.18, gain: 0.3)
    case .chestKnock: return [SabboTone(frequency: 150, start: 0, duration: 0.09, gain: 0.6, glide: 0.6, noise: 0.35)]
    case .chestOpen:
      return [SabboTone(frequency: 220, start: 0, duration: 0.34, gain: 0.3, glide: 2, noise: 0.45)]
        + arpeggio([783.99, 987.77, 1174.66, 1567.98], every: 0.07, from: 0.2, duration: 0.55, gain: 0.3)
    case .prize:
      return arpeggio([783.99, 987.77], every: 0.11, duration: 0.18, gain: 0.38, bell: false)
        + [SabboTone(frequency: 1174.66, start: 0.22, duration: 0.7, gain: 0.38)]
        + arpeggio([2349.32], every: 0, from: 0.3, duration: 0.5, gain: 0.12)
    case .wear:
      return [SabboTone(frequency: 440, start: 0, duration: 0.16, gain: 0.35, glide: 2)]
        + arpeggio([1318.51], every: 0, from: 0.12, duration: 0.3, gain: 0.25)
    case .streak:
      return [SabboTone(frequency: 180, start: 0, duration: 0.4, gain: 0.3, glide: 2.4, noise: 0.7)]
        + arpeggio([659.25, 987.77], every: 0.08, from: 0.24, duration: 0.36, gain: 0.3)
    case .peer: return arpeggio([987.77, 1318.51], every: 0.12, duration: 0.4, gain: 0.32)
    case .unlock:
      return [SabboTone(frequency: 1200, start: 0, duration: 0.04, gain: 0.3, noise: 0.8)]
        + arpeggio([659.25, 880], every: 0.1, from: 0.08, duration: 0.3, gain: 0.32, bell: false)
    }
  }
  private static func peak(_ sound: SabboSound) -> Double {
    switch sound {
    case .tick: return 0.22
    case .step, .star: return 0.35
    case .chestKnock: return 0.5
    default: return 0.6
    }
  }
  /// Deterministic mono samples, normalized and ending in silence so playback never clicks.
  static func render(_ sound: SabboSound) -> [Float] {
    let tones = tones(sound)
    let end = tones.map { $0.start + $0.duration }.max() ?? 0
    var samples = [Double](repeating: 0, count: Int((end + 0.05) * sampleRate))
    var seed: UInt32 = 0x2545_F491
    for tone in tones {
      let first = Int(tone.start * sampleRate)
      var phase = 0.0
      var low = 0.0
      for i in 0..<Int(tone.duration * sampleRate) where first + i < samples.count {
        let t = Double(i) / sampleRate
        let progress = t / tone.duration
        let frequency = tone.frequency * pow(tone.glide, progress)
        phase += 2 * Double.pi * frequency / sampleRate
        var voice = tone.bell
          ? sin(phase) + 0.45 * exp(-7 * progress) * sin(2.76 * phase) + 0.2 * exp(-11 * progress) * sin(5.4 * phase)
          : sin(phase) + 0.2 * sin(2 * phase)
        if tone.noise > 0 {
          seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
          let white = Double(seed) / Double(UInt32.max) * 2 - 1
          low += (1 - exp(-2 * Double.pi * min(frequency * 3, 9_000) / sampleRate)) * (white - low)
          voice = voice * (1 - tone.noise) + low * tone.noise * 2.5
        }
        let attack = min(1, t / (tone.bell ? 0.002 : 0.005))
        let release = max(0, min(1, (tone.duration - t) / 0.015))
        samples[first + i] += voice * tone.gain * attack * release * exp(-(tone.bell ? 4.5 : 2.5) * progress)
      }
    }
    let loudest = samples.map { abs($0) }.max() ?? 0
    let scale = loudest > 0 ? peak(sound) / loudest : 0
    return samples.map { Float($0 * scale) }
  }
}

/// Sound and haptic feedback. Sounds use the ambient category: they obey the silent
/// switch and mix with music. Both follow the per-device preferences in Settings.
final class SabboFX: @unchecked Sendable {
  static let shared = SabboFX()
  static let soundKey = "sabbo.fx.sound"
  static let hapticsKey = "sabbo.fx.haptics"
  private static let environment = ProcessInfo.processInfo.environment
  /// Automated tests run silently and without indefinite motion, so the app can idle.
  static let automated = environment["SABBO_UI_TEST"] == "1" || environment["XCTestConfigurationFilePath"] != nil
  static var continuousMotion: Bool { !automated }

  private let engine = AVAudioEngine()
  private var players: [AVAudioPlayerNode] = []
  private var nextPlayer = 0
  private var buffers: [SabboSound: AVAudioPCMBuffer] = [:]
  private var overrides: [SabboSound: AVAudioPlayer] = [:]
  private let format = AVAudioFormat(standardFormatWithSampleRate: SoundRecipe.sampleRate, channels: 1)
  private var configured = false

  var soundEnabled: Bool { UserDefaults.standard.object(forKey: Self.soundKey) as? Bool ?? true }
  var hapticsEnabled: Bool { UserDefaults.standard.object(forKey: Self.hapticsKey) as? Bool ?? true }

  func play(_ sound: SabboSound, after delay: Double = 0) {
    guard soundEnabled, !Self.automated else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
      MainActor.assumeIsolated { self.perform(sound) }
    }
  }

  func haptic(_ kind: SabboHaptic, after delay: Double = 0) {
    #if !targetEnvironment(macCatalyst)
    guard hapticsEnabled, !Self.automated else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
      MainActor.assumeIsolated {
        switch kind {
        case .tap: UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
        case .step: UISelectionFeedbackGenerator().selectionChanged()
        case .tick(let intensity): UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: min(1, max(0.2, intensity)))
        case .knock: UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        case .open: UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
      }
    }
    #endif
  }

  @MainActor private func perform(_ sound: SabboSound) {
    if let player = override(sound) {
      player.currentTime = 0
      player.play()
      return
    }
    guard prepare(), let buffer = buffer(sound) else { return }
    let player = players[nextPlayer]
    nextPlayer = (nextPlayer + 1) % players.count
    player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
    if !player.isPlaying { player.play() }
  }

  @MainActor private func override(_ sound: SabboSound) -> AVAudioPlayer? {
    if let player = overrides[sound] { return player }
    guard let data = NSDataAsset(name: "Sound-" + sound.rawValue)?.data, let player = try? AVAudioPlayer(data: data) else { return nil }
    player.prepareToPlay()
    overrides[sound] = player
    return player
  }

  @MainActor private func prepare() -> Bool {
    guard let format else { return false }
    if !configured {
      try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
      for _ in 0..<4 {
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        players.append(player)
      }
      configured = true
      // Render the remaining sounds away from the main thread before they are needed.
      DispatchQueue.global(qos: .utility).async {
        let rendered = SabboSound.allCases.map { ($0, SoundRecipe.render($0)) }
        DispatchQueue.main.async {
          MainActor.assumeIsolated {
            for (sound, samples) in rendered where self.buffers[sound] == nil { self.buffers[sound] = self.makeBuffer(samples) }
          }
        }
      }
    }
    if !engine.isRunning {
      // Interruptions and route changes stop the engine; restart on the next sound.
      do {
        try AVAudioSession.sharedInstance().setActive(true)
        try engine.start()
      } catch { return false }
    }
    return true
  }

  @MainActor private func buffer(_ sound: SabboSound) -> AVAudioPCMBuffer? {
    if let buffer = buffers[sound] { return buffer }
    let buffer = makeBuffer(SoundRecipe.render(sound))
    buffers[sound] = buffer
    return buffer
  }

  private func makeBuffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
    guard let format, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
          let channel = buffer.floatChannelData?[0] else { return nil }
    buffer.frameLength = AVAudioFrameCount(samples.count)
    for (index, sample) in samples.enumerated() { channel[index] = sample }
    return buffer
  }
}

/// Celebration scales with the grade; low grades get warmth, never a failure sound.
enum GradeCelebration {
  static func sound(_ grade: Int) -> SabboSound { grade >= 5 ? .gradeHigh : grade >= 3 ? .gradeMid : .gradeLow }
  static func confetti(_ grade: Int) -> ConfettiBurst.Intensity { grade >= 5 ? .large : grade >= 3 ? .medium : .small }
  static func phrase(_ grade: Int) -> String {
    switch grade {
    case 6...: return "Toppkarakter! 🔥"
    case 5: return "Sterkt levert!"
    case 4: return "Godt jobbet!"
    case 3: return "På god vei!"
    case 2: return "Fint forsøk – sjekk neste steg."
    default: return "Hver økt teller – sjekk neste steg."
    }
  }
}
