import XCTest
@testable import Sabbo

final class LocalRecoveryTests: XCTestCase {
  func testUpgradeKeepsPendingAnswerDraftsAndConflictVersionsByteForByte() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("learner.json")
    struct Catalogue: Decodable { let questions: [Question] }
    let source = try XCTUnwrap(Bundle.main.url(forResource: "questions.v1", withExtension: "json"))
    let q = try XCTUnwrap(try JSONDecoder().decode(Catalogue.self, from: Data(contentsOf: source)).questions.first)
    let a = Assignment(id: "previous-day", day: "2026-10-18", timezone: "Europe/Oslo", question_id: q.id, version: q.version)
    var old = LocalState()
    old.drafts[a.id] = "Full answer saved offline at 23:59 — æøå"
    old.draftSync = [a.id: DraftSync(revision: 14, base: "Partial server draft", conflict: "Other version", backups: ["Earlier local answer"])]
    old.pending = [Pending(id: "pending-upload", assignment: a, question: q, answer: old.drafts[a.id]!, assisted: false, mode: "daily", started_at: "2026-10-18T21:59:00Z", assessment: "completed", attempt_id: nil)]
    var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
    json["retained_unknown_field"] = "Must survive in recovery copy"
    let original = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
    try original.write(to: file)
    let restored = try LocalRecovery.load(file)
    XCTAssertEqual(restored.pending.first?.answer, old.drafts[a.id])
    XCTAssertEqual(restored.draftSync?[a.id]?.backups, ["Earlier local answer"])
    XCTAssertEqual(restored.drafts[a.id], old.drafts[a.id])
    XCTAssertEqual(try Data(contentsOf: LocalRecovery.snapshotURL(for: file)), original)
    try JSONEncoder().encode(restored).write(to: file)
    _ = try LocalRecovery.load(file)
    XCTAssertEqual(try Data(contentsOf: LocalRecovery.snapshotURL(for: file)), original)
    let exported = try XCTUnwrap(JSONSerialization.jsonObject(with: LocalRecovery.export(file)) as? [String: Any])
    let files = try XCTUnwrap(exported["files"] as? [[String: String]])
    XCTAssertEqual(Data(base64Encoded: try XCTUnwrap(files.first?["data_base64"])), original)
  }
  func testUndecodableStateIsPreservedAndExportable() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("learner.json")
    let original = Data("{ damaged JSON but still containing a full answer".utf8)
    try original.write(to: file)
    XCTAssertThrowsError(try LocalRecovery.load(file))
    XCTAssertEqual(try Data(contentsOf: file), original)
    XCTAssertEqual(try Data(contentsOf: LocalRecovery.snapshotURL(for: file)), original)
    XCTAssertNoThrow(try LocalRecovery.export(file))
  }
  func testPreAchievementProgressStillDecodes() throws {
    let old = #"{"streak":{"user_id":"learner","name":"Learner","current":2,"best":3,"completed_today":true,"week_days":2,"days":[]},"stars":{"total":14,"epoch":"","awards":[]}}"#
    let progress = try JSONDecoder().decode(PersonProgress.self, from: Data(old.utf8))
    XCTAssertNil(progress.achievements)
    XCTAssertEqual(progress.stars.total, 14)
  }
}
