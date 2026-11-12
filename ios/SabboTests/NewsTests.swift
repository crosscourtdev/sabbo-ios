import XCTest
@testable import Sabbo

final class NewsTests: XCTestCase {
  func testUnreadNewsSurvivesRelaunchAndOnlyNewItemsRestoreBadge() throws {
    var state = LocalState()
    XCTAssertEqual(state.unreadNewsCount, 0)
    let first = NewsItem(id: "one", published_on: "2026-11-12", title: "First", body: "News")
    let second = NewsItem(id: "two", published_on: "2026-11-12", title: "Second", body: "More news")
    state.news = NewsFeed(items: [first, first])
    XCTAssertEqual(state.unreadNewsCount, 1)
    state.markNewsRead()
    state = try JSONDecoder().decode(LocalState.self, from: JSONEncoder().encode(state))
    XCTAssertEqual(state.unreadNewsCount, 0)
    state.news = NewsFeed(items: [second, first])
    XCTAssertEqual(state.unreadNewsCount, 1)
    state.markNewsRead()
    XCTAssertEqual(state.unreadNewsCount, 0)
    state.news = NewsFeed(items: [])
    state.markNewsRead()
    state.news = NewsFeed(items: [first])
    XCTAssertEqual(state.unreadNewsCount, 0)
    var otherAccount = LocalState(); otherAccount.news = state.news
    XCTAssertEqual(otherAccount.unreadNewsCount, 1)
  }
  @MainActor func testReadNewsIsSavedAndRestoredPerSignedInAccount() throws {
    let model = AppModel()
    let firstUser = "news-test-" + UUID().uuidString
    let secondUser = "news-test-" + UUID().uuidString
    defer {
      for user in [firstUser, secondUser] {
        model.session = Session(token: "fixture", user_id: user)
        if let file = model.file() {
          try? FileManager.default.removeItem(at: file)
          try? FileManager.default.removeItem(at: LocalRecovery.snapshotURL(for: file))
        }
      }
      model.session = nil
    }
    model.session = Session(token: "fixture", user_id: firstUser)
    let feed = NewsFeed(items: [NewsItem(id: "fresh", published_on: "2026-11-12", title: "News", body: "News")])
    model.local.news = feed
    model.markNewsRead()
    model.local = LocalState(); model.restore()
    XCTAssertEqual(model.local.unreadNewsCount, 0)
    XCTAssertEqual(model.local.readNewsIDs, ["fresh"])
    model.session = Session(token: "fixture", user_id: secondUser)
    model.local = LocalState(); model.restore(); model.local.news = feed
    XCTAssertEqual(model.local.unreadNewsCount, 1)
  }
  func testQueuedHandInKeepsItsPlatformAndOldQueueStillDecodes() throws {
    let question = Question(id: "sample", version: 1, subject_id: "sample", goal_ids: [], prompt: "Sample")
    let assignment = Assignment(id: "sample", day: "2026-11-12", timezone: "Europe/Oslo", question_id: "sample", version: 1)
    var pending = Pending(id: "receipt", assignment: assignment, question: question, answer: "Answer", assisted: false,
      mode: "daily", started_at: "2026-11-12T09:00:00Z", assessment: nil, attempt_id: nil)
    let old = try JSONDecoder().decode(Pending.self, from: JSONEncoder().encode(pending))
    XCTAssertNil(old.client_platform)
    pending.client_platform = "MAC_OS"
    let queued = try JSONDecoder().decode(Pending.self, from: JSONEncoder().encode(pending))
    XCTAssertEqual(queued.client_platform, "MAC_OS")
    #if targetEnvironment(macCatalyst)
    XCTAssertEqual(ClientRelease.currentPlatform, "MAC_OS")
    #else
    XCTAssertEqual(ClientRelease.currentPlatform, "IOS")
    #endif
  }
  func testOldCacheStillDecodesAndNewsSurvivesOfflineRoundTrip() throws {
    var state = LocalState()
    let old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as! [String: Any]
    XCTAssertNil(old["news"])
    XCTAssertNil(try JSONDecoder().decode(LocalState.self, from: JSONSerialization.data(withJSONObject: old)).news)
    let payload = Data(#"{"items":[{"id":"event","published_on":"2026-11-12","title":"Nyheter","body":"Doble stjerner","starts_on":"2026-11-13","ends_on":"2026-11-15"}]}"#.utf8)
    state.news = try JSONDecoder().decode(NewsFeed.self, from: payload)
    let restored = try JSONDecoder().decode(LocalState.self, from: JSONEncoder().encode(state))
    XCTAssertEqual(restored.news?.items.first?.ends_on, "2026-11-15")
  }
  func testDoubledAwardRemainsCompatibleWithExistingClientModel() throws {
    let payload = Data(#"{"day":"2026-11-13","attempt_id":"morning","grade":5,"stars":10,"base_stars":5,"multiplier":2,"event_id":"morning-stars-2026-11"}"#.utf8)
    let award = try JSONDecoder().decode(StarAward.self, from: payload)
    XCTAssertEqual(award.stars, 10)
    XCTAssertEqual(award.grade, 5)
  }
}
