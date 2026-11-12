import XCTest
@testable import Sabbo

final class NewsTests: XCTestCase {
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
