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

extension DraftSyncTests {
  func testDifferentQuestionsMergeAndRoundTripOnBothDevices() {
    let base = DraftSync.encode(["q1": "One", "q2": "Two"])
    var phone = DraftSync(revision: 1, base: base)
    var mac = DraftSync(revision: 1, base: base)
    let phoneText = DraftSync.encode(["q1": "Phone answer", "q2": "Two"])
    let macText = DraftSync.encode(["q1": "One", "q2": "Mac answer"])
    let merged = phone.receive(Draft(revision: 2, body: macText, assisted: 0), local: phoneText)
    XCTAssertEqual(DraftSync.parts(merged), ["q1": "Phone answer", "q2": "Mac answer"])
    XCTAssertNil(phone.conflict)
    XCTAssertEqual(mac.receive(Draft(revision: 3, body: merged, assisted: 0), local: macText), merged)
    XCTAssertNil(mac.conflict)
  }
  func testLostAcknowledgementWhileTypingAndRelaunch() throws {
    var state = DraftSync(revision: 1, base: "A")
    let sent = DraftWrite(revision: 1, body: "AB")
    state.write = sent
    state = try JSONDecoder().decode(DraftSync.self, from: JSONEncoder().encode(state))
    // Reads cannot interpret the phone's own unacknowledged write as another device.
    XCTAssertEqual(state.receive(Draft(revision: 2, body: "AB", assisted: 0), local: "ABC"), "ABC")
    XCTAssertNil(state.conflict)
    XCTAssertEqual(state.write?.id, sent.id)
    state.acknowledge(sent, draft: Draft(revision: 2, body: "AB", assisted: 0))
    XCTAssertEqual(state.receive(Draft(revision: 2, body: "AB", assisted: 0), local: "ABC"), "ABC")
    XCTAssertNil(state.conflict)
    XCTAssertNil(state.write)
    XCTAssertEqual(state.base, "AB")
  }
  func testConflictOnlyIncludesOverlappingQuestionAndChoicesKeepOtherAnswers() {
    var state = DraftSync(revision: 1, base: DraftSync.encode(["q1":"A", "q2":"B"]))
    let local = DraftSync.encode(["q1":"Phone", "q2":"B"])
    let remote = DraftSync.encode(["q1":"Mac", "q2":"New second answer"])
    let merged = state.receive(Draft(revision: 2, body: remote, assisted: 0), local: local)
    XCTAssertEqual(state.unresolved(local: merged), ["q1"])
    XCTAssertEqual(DraftSync.parts(merged)["q2"], "New second answer")
    let refreshed = state.receive(Draft(revision: 2, body: remote, assisted: 0), local: merged)
    XCTAssertEqual(state.unresolved(local: refreshed), ["q1"])
    let chosen = state.choose(["q1": false], local: refreshed)
    XCTAssertEqual(DraftSync.parts(chosen), ["q1":"Phone", "q2":"New second answer"])
    XCTAssertNil(state.conflict)
    XCTAssertTrue(state.backups.contains { DraftSync.equal($0, remote) })
  }
  func testLegacyConflictStillReadableAndNoSilentChoice() throws {
    let data = Data(#"{"revision":2,"base":"Server","conflict":"Server","backups":["Local","Server"]}"#.utf8)
    var state = try JSONDecoder().decode(DraftSync.self, from: data)
    XCTAssertEqual(state.receive(Draft(revision: 2, body: "Server", assisted: 0), local: "Local"), "Local")
    XCTAssertEqual(state.unresolved(local: "Local"), [""])
    XCTAssertEqual(state.choose(["": true], local: "Local"), "Server")
    XCTAssertNil(state.conflict)
  }
  func testDeletingOneAnswerDoesNotEraseAnotherDevicesEdit() {
    var state = DraftSync(revision: 1, base: DraftSync.encode(["q1":"A", "q2":"B"]))
    let result = state.receive(Draft(revision: 2, body: DraftSync.encode(["q1":"A", "q2":"New"]), assisted: 0),
      local: DraftSync.encode(["q2":"B"]))
    XCTAssertEqual(DraftSync.parts(result), ["q2":"New"])
    XCTAssertNil(state.conflict)
  }
}
