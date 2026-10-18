import XCTest
@testable import Sabbo

final class DraftSyncTests: XCTestCase {
  func testUneditedDeviceReceivesNewDraft() {
    var state = DraftSync(revision: 1, base: "First")
    XCTAssertEqual(state.receive(Draft(revision: 2, body: "Second", assisted: 0), local: "First"), "Second")
    XCTAssertNil(state.conflict)
    XCTAssertEqual(state.revision, 2)
  }
  func testOfflineEditsAreRetainedUntilExplicitChoice() {
    var state = DraftSync(revision: 1, base: "First")
    let remote = Draft(revision: 2, body: "Mac", assisted: 0)
    XCTAssertEqual(state.receive(remote, local: "Phone"), "Phone")
    XCTAssertEqual(state.conflict, "Mac")
    XCTAssertEqual(Set(state.backups), Set(["Phone", "Mac"]))
    XCTAssertEqual(state.receive(remote, local: "Phone extended"), "Phone extended")
    XCTAssertEqual(state.conflict, "Mac")
    XCTAssertEqual(state.receive(Draft(revision: 3, body: "Phone extended", assisted: 0), local: "Phone extended"), "Phone extended")
    XCTAssertNil(state.conflict)
  }
  func testLostResponseAndJSONKeyOrderDoNotCreateConflicts() {
    XCTAssertTrue(DraftSync.equal("{\"a\":\"å\",\"b\":\"ø\"}", "{\"b\":\"ø\",\"a\":\"å\"}"))
    var state = DraftSync()
    XCTAssertEqual(state.receive(Draft(revision: 1, body: "Typed", assisted: 0), local: "Typed"), "Typed")
    XCTAssertNil(state.conflict)
  }
}

extension DraftSyncTests {
  func testDelayedReadCannotRollbackAcknowledgedDraft() {
    var state = DraftSync(revision: 3, base: "Latest")
    XCTAssertEqual(state.receive(Draft(revision: 2, body: "Old", assisted: 0), local: "Latest"), "Latest")
    XCTAssertEqual(state.revision, 3)
  }
}
