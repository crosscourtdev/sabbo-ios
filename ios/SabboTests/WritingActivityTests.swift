import XCTest
@testable import Sabbo

final class WritingActivityTests: XCTestCase {
  func testBlockedPasteUsesCurrentQuestionCountsWithoutCountingItAsTyping() {
    var capture = WritingCapture()
    capture.edit("Previous question answer", question: "q1", at: 100)
    capture.blockedPaste("", question: "q2", at: 102)
    XCTAssertEqual(capture.receipt.events.last?.question_id, "q2")
    XCTAssertEqual(capture.receipt.events.last?.words, 0)
    XCTAssertEqual(capture.receipt.events.last?.characters, 0)
    capture.edit("Own", question: "q2", at: 103)
    XCTAssertEqual(capture.writingSeconds, 0)
  }
  func testSamplingRecordsCountsWithoutTextAndExcludesLongPauses() throws {
    var capture = WritingCapture()
    capture.edit("Private draft sentinel", question: "q1", at: 100)
    capture.edit("Private draft sentinel changed", question: "q1", at: 102)
    XCTAssertEqual(capture.receipt.events.count, 1)
    XCTAssertEqual(capture.writingSeconds, 2)
    capture.edit("One two", question: "q1", at: 200)
    XCTAssertEqual(capture.writingSeconds, 2)
    XCTAssertEqual(capture.receipt.events.last?.words, 2)
    capture.phase("inactive", at: 201)
    capture.phase("inactive", at: 202)
    capture.phase("background", at: 203)
    capture.phase("active", at: 250)
    capture.edit("One two three", question: "q1", at: 251)
    XCTAssertEqual(capture.writingSeconds, 2)
    XCTAssertEqual(capture.receipt.events.filter { $0.kind == "inactive" }.count, 1)
    capture.phase("submit", at: 252)
    let json = String(data: try JSONEncoder().encode(capture.receipt), encoding: .utf8)!
    XCTAssertFalse(json.contains("Private draft"))
    XCTAssertFalse(json.contains("One two"))
    XCTAssertEqual(capture.receipt.events.last?.words, 3)
  }
  func testQuestionChangeAndRelaunchDoNotCountReadingAsTyping() throws {
    var capture = WritingCapture()
    capture.edit("First", question: "q1", at: 100)
    capture.edit("Second", question: "q2", at: 102)
    XCTAssertEqual(capture.writingSeconds, 0)
    XCTAssertEqual(capture.receipt.events.map(\.question_id), ["q1", "q1", "q2"])
    var state = LocalState(); state.writingCaptures = ["day": capture]
    state = try JSONDecoder().decode(LocalState.self, from: JSONEncoder().encode(state))
    XCTAssertEqual(state.writingCaptures?["day"]?.receipt.session_id, capture.receipt.session_id)
    XCTAssertNil(try JSONDecoder().decode(LocalState.self, from: JSONEncoder().encode(LocalState())).writingCaptures)
  }
  func testBoundedLongSessionRetainsStartAndSubmitAndMonotonicTime() {
    var capture = WritingCapture()
    for i in 0..<1100 { capture.edit("word", question: "q", at: Double(i * 11)) }
    capture.phase("submit", at: 1) // Device clock adjustment cannot reverse the event order.
    XCTAssertEqual(capture.receipt.events.count, 1000)
    XCTAssertTrue(capture.receipt.truncated)
    XCTAssertEqual(capture.receipt.events.first?.at, 0)
    XCTAssertEqual(capture.receipt.events.last?.kind, "submit")
    XCTAssertEqual(capture.receipt.events.last?.at, Double(1099 * 11))
  }
  @MainActor func testOwnerAndOtherAccountsNeverRecordOrQueueActivity() {
    let model = AppModel()
    for user in [ClientProfile.ownerID, "reviewer", "unknown"] {
      model.session = Session(token: "fixture", user_id: user)
      model.local = LocalState()
      model.recordWriting(WritingContext(key: "day", questionID: "q"), text: "Answer")
      model.blockedWritingPaste(WritingContext(key: "day", questionID: "q"), text: "Answer")
      model.queueWriting(WritingReceipt(), attemptID: "attempt")
      XCTAssertNil(model.local.writingCaptures)
      XCTAssertNil(model.local.pendingWriting)
    }
    model.session = nil
  }
  func testPendingOfflineAnswerKeepsImmutableWritingReceipt() throws {
    let q = Question(id: "q", version: 1, subject_id: "sample", goal_ids: [], prompt: "Sample")
    let a = Assignment(id: "day", day: "2026-11-14", timezone: "Europe/Oslo", question_id: q.id, version: 1)
    var capture = WritingCapture(); capture.edit("Own answer", question: q.id, at: 100); capture.phase("submit", at: 101)
    let pending = Pending(id: "pending", assignment: a, question: q, answer: "Own answer", assisted: false,
      mode: "daily", started_at: "", assessment: "completed", attempt_id: nil, writing_activity: capture.receipt)
    let restored = try JSONDecoder().decode(Pending.self, from: JSONEncoder().encode(pending))
    XCTAssertEqual(restored.writing_activity?.session_id, capture.receipt.session_id)
    XCTAssertEqual(restored.writing_activity?.events.last?.kind, "submit")
  }
}
