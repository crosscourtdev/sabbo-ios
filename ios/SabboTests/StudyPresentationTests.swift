import XCTest
@testable import Sabbo

final class StudyPresentationTests: XCTestCase {
  private func part(_ id: String) -> Question {
    Question(id: id, version: 1, subject_id: "pome", goal_ids: [], prompt: "En oppgave", expectations: ["Vurder metoden", "Vurder utvalget"])
  }
  func testCurrentAndLegacyCriteriaKeepTheirQuestionAndExpectation() {
    let q = part("task-1")
    for id in ["task-1.c2", "task-1.task-1.c2"] {
      let criterion = CriterionResult(criterion_id: id, attainment: "partial", evidence: "", comment: "")
      XCTAssertTrue(StudyPresentation.belongs(criterion, to: q))
      XCTAssertFalse(StudyPresentation.belongs(criterion, to: part("task-2")))
      XCTAssertEqual(StudyPresentation.expectation(criterion, part: q), "Vurder utvalget")
    }
    let unknown = CriterionResult(criterion_id: "task-1.c99", attainment: "unknown", evidence: "", comment: "")
    XCTAssertEqual(StudyPresentation.expectation(unknown, part: q), "Vurderingspunkt")
    XCTAssertEqual(StudyPresentation.attainment(unknown.attainment), "Ikke vurdert")
  }
  func testResumePrefersSavedPartAndOtherwiseFirstUnansweredPart() {
    let parts = [part("a"), part("b")]
    let answer = AnswerSet.encode(["a": "Svar", "b": " \n"])
    XCTAssertEqual(StudyPresentation.resumeIndex(parts: parts, saved: nil, answer: answer), 1)
    XCTAssertEqual(StudyPresentation.resumeIndex(parts: parts, saved: "a", answer: answer), 0)
    XCTAssertEqual(StudyPresentation.resumeIndex(parts: parts, saved: "removed", answer: answer), 1)
    XCTAssertEqual(StudyPresentation.resumeIndex(parts: [], saved: "a", answer: answer), 0)
  }
  func testMaterialSeparationDoesNotChangeWords() {
    let original = "A, rapport: 80 elever svarte. De meldte seg frivillig. B, reklame: Ingen metode oppgis."
    let paragraphs = StudyPresentation.paragraphs(original)
    XCTAssertEqual(paragraphs.count, 2)
    XCTAssertEqual(paragraphs.joined(separator: " "), original)
  }
  func testConflictHighlightHandlesUnicodeInsertionsDeletionsAndUnchangedText() {
    let longer = "Jeg undersøker både utvalg og metode."
    let shorter = "Jeg undersøker både utvalg."
    let range = StudyPresentation.changedRange(longer, comparedTo: shorter)!
    XCTAssertEqual(String(longer[range]), " og metode")
    XCTAssertTrue(StudyPresentation.changedRange(shorter, comparedTo: longer)!.isEmpty)
    XCTAssertNil(StudyPresentation.changedRange(longer, comparedTo: longer))
    XCTAssertEqual(String("Æøå"[StudyPresentation.changedRange("Æøå", comparedTo: "")!]), "Æøå")
  }
  func testSourceLinksOnSameHostRemainDistinguishable() throws {
    let decode: (String) throws -> QuestionSource = { try JSONDecoder().decode(QuestionSource.self, from: Data($0.utf8)) }
    let one = try decode(#""https://example.org/learning/study-methods""#)
    let two = try decode(#""https://example.org/learning/source-evaluation""#)
    XCTAssertEqual(StudyPresentation.sourceTitle(one), "Study methods")
    XCTAssertNotEqual(StudyPresentation.sourceTitle(one), StudyPresentation.sourceTitle(two))
  }
  @MainActor func testOwnerReviewOnlyBypassesPeerBonusLockAndProgressSelectionIsAccountScoped() {
    let model = AppModel()
    model.local = LocalState()
    model.session = Session(token: "unit-test", user_id: ClientProfile.ownerID)
    let q = part("review")
    let now = Date(); model.bonusClock = now
    let date = ISO8601DateFormatter()
    model.local.bonus = BonusState(id: "bonus", status: "ready", server_now: date.string(from: now),
      day: "2026-10-20", cutoff: "20:00", question_id: q.id, question_version: q.version,
      opens_at: date.string(from: now.addingTimeInterval(-60)), expires_at: date.string(from: now.addingTimeInterval(3600)), target_grade: 5)
    XCTAssertTrue(model.answersLocked(q))
    XCTAssertTrue(model.bonusAnswersLocked(q, for: ClientProfile.ownerID))
    XCTAssertFalse(model.bonusAnswersLocked(q, for: ClientProfile.learnerID))
    XCTAssertTrue(model.bonusAnswersLocked(q, for: "unrelated"))
    let learner = Streak(user_id: ClientProfile.learnerID, name: "Learner", current: 2, best: 2, completed_today: true, week_days: 2, days: [])
    model.local.progress = PairProgress(people: [PersonProgress(streak: learner, stars: Stars(total: 42, epoch: "peer", awards: []), fire_attempt_id: nil)])
    XCTAssertEqual(model.learnerProgressForOwner?.stars.total, 42)
    XCTAssertNil(model.ownProgress)
    model.session = Session(token: "unit-test", user_id: ClientProfile.learnerID)
    XCTAssertNil(model.learnerProgressForOwner)
    XCTAssertTrue(model.bonusAnswersLocked(q, for: ClientProfile.ownerID))
    model.session = nil
    XCTAssertNil(model.learnerProgressForOwner)
  }

}
