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
}
