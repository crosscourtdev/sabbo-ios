import XCTest
@testable import Sabbo

final class EffectsTests: XCTestCase {
  func testEverySoundIsShortAudibleUnclippedAndEndsSilently() {
    for sound in SabboSound.allCases {
      let samples = SoundRecipe.render(sound)
      let seconds = Double(samples.count) / SoundRecipe.sampleRate
      XCTAssertGreaterThan(seconds, 0.05, sound.rawValue)
      XCTAssertLessThan(seconds, 2, sound.rawValue)
      XCTAssertFalse(samples.contains { !$0.isFinite }, sound.rawValue)
      let peak = samples.map { abs($0) }.max() ?? 0
      XCTAssertGreaterThan(peak, 0.1, sound.rawValue)
      XCTAssertLessThanOrEqual(peak, 0.61, sound.rawValue)
      XCTAssertEqual(samples.last ?? 1, 0, accuracy: 0.0001, sound.rawValue)
    }
  }
  func testSynthesisIsDeterministic() {
    XCTAssertEqual(SoundRecipe.render(.submit), SoundRecipe.render(.submit))
    XCTAssertEqual(SoundRecipe.render(.chestKnock), SoundRecipe.render(.chestKnock))
  }
  func testLowGradesAreEncouragedNotPunished() {
    XCTAssertEqual(GradeCelebration.sound(1), .gradeLow)
    XCTAssertEqual(GradeCelebration.sound(2), .gradeLow)
    XCTAssertEqual(GradeCelebration.sound(3), .gradeMid)
    XCTAssertEqual(GradeCelebration.sound(4), .gradeMid)
    XCTAssertEqual(GradeCelebration.sound(5), .gradeHigh)
    XCTAssertEqual(GradeCelebration.sound(6), .gradeHigh)
    XCTAssertEqual(GradeCelebration.confetti(1), .small)
    XCTAssertEqual(GradeCelebration.confetti(4), .medium)
    XCTAssertEqual(GradeCelebration.confetti(6), .large)
    XCTAssertEqual(Set((1...6).map(GradeCelebration.phrase)).count, 6)
  }
  func testPreferencesDefaultOnAndFollowSettings() {
    let defaults = UserDefaults.standard
    let saved = [SabboFX.soundKey: defaults.object(forKey: SabboFX.soundKey), SabboFX.hapticsKey: defaults.object(forKey: SabboFX.hapticsKey)]
    defer {
      for (key, value) in saved {
        if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
      }
    }
    defaults.removeObject(forKey: SabboFX.soundKey)
    defaults.removeObject(forKey: SabboFX.hapticsKey)
    XCTAssertTrue(SabboFX.shared.soundEnabled)
    XCTAssertTrue(SabboFX.shared.hapticsEnabled)
    defaults.set(false, forKey: SabboFX.soundKey)
    XCTAssertFalse(SabboFX.shared.soundEnabled)
    XCTAssertTrue(SabboFX.shared.hapticsEnabled)
    defaults.set(false, forKey: SabboFX.hapticsKey)
    XCTAssertFalse(SabboFX.shared.hapticsEnabled)
  }
}
