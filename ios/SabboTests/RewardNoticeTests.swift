import XCTest
@testable import Sabbo

final class RewardNoticeTests: XCTestCase {
  func testAcknowledgementSurvivesRelaunchAndIsAccountScoped() throws {
    let suite = "reward-notice-test-" + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = RewardNoticeStore(defaults: defaults)
    store.acknowledge(["stars:epoch:attempt", "cosmetic:c001"], account: "one")
    let relaunched = RewardNoticeStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
    XCTAssertEqual(relaunched.seen("one"), ["stars:epoch:attempt", "cosmetic:c001"])
    XCTAssertTrue(relaunched.seen("two").isEmpty)
  }
  func testBaselineRunsOncePerTrackWithoutConsumingLaterAwards() throws {
    let suite = "reward-notice-test-" + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = RewardNoticeStore(defaults: defaults)
    store.baseline(["stars:old"], track: "progress", account: "one")
    store.baseline(["stars:new"], track: "progress", account: "one")
    store.baseline(["cosmetic:old"], track: "cosmetics", account: "one")
    XCTAssertEqual(store.seen("one"), ["stars:old", "cosmetic:old"])
  }
  @MainActor func testDelayedCatchupGradeIsShownOnceAndResetEpochCanEarnAgain() throws {
    let suite = "reward-notice-test-" + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = RewardNoticeStore(defaults: defaults)
    let model = AppModel()
    model.session = Session(token: "unit-test", user_id: suite)
    model.local = LocalState()
    let streak = Streak(user_id: suite, name: "Test", current: 0, best: 0, completed_today: false, week_days: 0, days: [], epoch: "fire")
    func progress(_ epoch: String, _ awards: [StarAward]) {
      model.local.progress = PairProgress(people: [PersonProgress(streak: streak, stars: Stars(total: awards.reduce(0) { $0 + $1.stars }, epoch: epoch, awards: awards), fire_attempt_id: nil)])
    }
    let old = StarAward(day: "2026-10-01", attempt_id: "old", grade: 4, stars: 4)
    let catchup = StarAward(day: "2026-09-01", attempt_id: "late", grade: 5, stars: 5)
    progress("first", [old])
    XCTAssertTrue(model.pendingRewardNotices(store: store).isEmpty)
    progress("first", [old, catchup])
    let notices = model.pendingRewardNotices(store: store)
    XCTAssertEqual(notices.map(\.id), ["stars:first:late"])
    store.acknowledge(notices.map(\.id), account: suite)
    XCTAssertTrue(model.pendingRewardNotices(store: store).isEmpty)
    progress("reset", [catchup])
    XCTAssertEqual(model.pendingRewardNotices(store: store).map(\.id), ["stars:reset:late"])
  }
  @MainActor func testCosmeticsArrivingLaterBaselineOldInventoryThenShowNewUnlock() throws {
    let suite = "reward-notice-test-" + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = RewardNoticeStore(defaults: defaults)
    let model = AppModel()
    model.session = Session(token: "unit-test", user_id: suite)
    model.local = LocalState()
    let streak = Streak(user_id: suite, name: "Test", current: 0, best: 0, completed_today: false, week_days: 0, days: [])
    model.local.progress = PairProgress(people: [PersonProgress(streak: streak, stars: Stars(total: 0, epoch: "first", awards: []), fire_attempt_id: nil)])
    XCTAssertTrue(model.pendingRewardNotices(store: store).isEmpty)
    let items = [CosmeticItem(id: "old", name: "Old"), CosmeticItem(id: "new", name: "New")]
    model.local.cosmetics = CosmeticCollection(items: items, owned: ["old"], people: [])
    XCTAssertTrue(model.pendingRewardNotices(store: store).isEmpty)
    model.local.cosmetics = CosmeticCollection(items: items, owned: ["old", "new"], people: [])
    XCTAssertEqual(model.pendingRewardNotices(store: store).map(\.id), ["cosmetic:new"])
  }
}
