import XCTest
@testable import Sabbo

final class GoalSessionTests: XCTestCase {
  func testBundledWholeGoalRestoresEveryPartBeforeCompletion() throws {
    let url = try XCTUnwrap(Bundle.main.url(forResource: "questions.v1", withExtension: "json"))
    struct Catalogue: Decodable { let questions: [Question] }
    let catalogue = try JSONDecoder().decode(Catalogue.self, from: Data(contentsOf: url))
    let goals = catalogue.questions.filter { $0.parts != nil }
    XCTAssertFalse(goals.isEmpty) // Catalogue includes retained versions as well as current goals.
    for goal in goals {
      let parts = try XCTUnwrap(goal.parts)
      XCTAssertGreaterThanOrEqual(parts.count, 2)
      var answers = Dictionary(uniqueKeysWithValues: parts.map { ($0.id, "Ærlig svar: å ø æ") })
      let durable = AnswerSet.encode(answers)
      XCTAssertEqual(AnswerSet.decode(durable), answers)
      XCTAssertTrue(AnswerSet.complete(goal, durable))
      answers[parts[0].id] = " \n "
      XCTAssertFalse(AnswerSet.complete(goal, AnswerSet.encode(answers)))
      XCTAssertFalse(AnswerSet.complete(goal, "A legacy plain-text draft"))
    }
  }
}

final class StreakRewardTests: XCTestCase {
  func testOnlyOwnerCanPreviewLockedRewards() {
    for reward in StreakReward.milestones {
      let owner = reward.presentation(userID: ClientProfile.ownerID, best: reward.day - 1)
      XCTAssertEqual(owner.access, .preview)
      XCTAssertTrue(owner.revealsMessage)
      for user in [ClientProfile.learnerID, "reviewer", "unknown"] {
        let locked = reward.presentation(userID: user, best: reward.day - 1)
        XCTAssertEqual(locked.access, .locked)
        XCTAssertFalse(locked.revealsMessage)
      }
      XCTAssertFalse(reward.presentation(userID: nil, best: 0).revealsMessage)
    }
  }
  func testEarnedRewardsStayOpenAfterAStreakBreak() {
    for reward in StreakReward.milestones {
      let earned = reward.presentation(userID: ClientProfile.learnerID, best: reward.day)
      XCTAssertEqual(earned.access, .earned)
      XCTAssertTrue(earned.revealsMessage)
    }
  }
  func testMilestonesOnlyUnlockAtConfirmedThresholds() {
    XCTAssertNil(StreakReward.next(best: 4, seen: []))
    XCTAssertEqual(StreakReward.next(best: 5, seen: [])?.day, 5)
    XCTAssertNil(StreakReward.next(best: 14, seen: [5]))
    XCTAssertEqual(StreakReward.next(best: 15, seen: [5])?.day, 15)
    XCTAssertNil(StreakReward.next(best: 49, seen: [5, 15]))
    XCTAssertEqual(StreakReward.next(best: 50, seen: [5, 15])?.day, 50)
    XCTAssertNil(StreakReward.next(best: 60, seen: [5, 15, 50]))
  }
  func testReturningUserGetsUnseenRewardsInOrder() {
    XCTAssertEqual(StreakReward.next(best: 50, seen: [])?.day, 5)
    XCTAssertEqual(StreakReward.next(best: 50, seen: [5])?.day, 15)
    XCTAssertEqual(StreakReward.next(best: 50, seen: [5, 15])?.day, 50)
    // Historical best keeps rewards earned even if the current streak breaks.
    XCTAssertEqual(StreakReward.next(best: 15, seen: [])?.day, 5)
  }
}

final class ResultContentTests: XCTestCase {
  func testFeedbackDecodesEveryBundledSessionIncludingLegacySourceLinks() throws {
    let url = try XCTUnwrap(Bundle.main.url(forResource: "questions.v1", withExtension: "json"))
    let data = try Data(contentsOf: url)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let questions = try XCTUnwrap(object["questions"] as? [[String: Any]])
    let sessions = questions.filter { $0["parts"] != nil }
    XCTAssertFalse(sessions.isEmpty)
    for session in sessions {
      let feedback = try JSONDecoder().decode(Feedback.self, from: JSONSerialization.data(withJSONObject: session))
      XCTAssertFalse(feedback.example_answer.isEmpty)
      XCTAssertTrue(try XCTUnwrap(feedback.parts).allSatisfy { !($0.example_answer ?? "").isEmpty })
    }
  }
  func testSourceDecodesBothWireAndBundledFormats() throws {
    for json in [#""https://example.org""#, #"{"url":"https://example.org","title":"Kilde"}"#] {
      let source = try JSONDecoder().decode(QuestionSource.self, from: Data(json.utf8))
      XCTAssertEqual(source.url, "https://example.org")
      let restored = try JSONDecoder().decode(QuestionSource.self, from: JSONEncoder().encode(source))
      XCTAssertEqual(restored.url, source.url)
    }
  }
}

final class MidnightDraftTests: XCTestCase {
  func testRolloverKeepsOnlyTheNewSessionsAnswers() throws {
    struct Catalogue: Decodable { let questions: [Question] }
    let url = try XCTUnwrap(Bundle.main.url(forResource: "questions.v1", withExtension: "json"))
    let goals = try JSONDecoder().decode(Catalogue.self, from: Data(contentsOf: url)).questions.filter { $0.parts != nil }
    let old = goals[0], next = goals[1]
    var answers = Dictionary(uniqueKeysWithValues: old.parts!.map { ($0.id, "Gammelt svar") })
    answers[next.parts![0].id] = "Dagens svar"
    let recovered = AnswerSet.scoped(AnswerSet.encode(answers), to: next)
    XCTAssertEqual(AnswerSet.decode(recovered), [next.parts![0].id: "Dagens svar"])
    XCTAssertFalse(AnswerSet.complete(next, recovered))
    XCTAssertEqual(AnswerSet.decode(AnswerSet.scoped("{}", to: next)), [:])
  }
}

final class StarRewardTests: XCTestCase {
  func testStarTrackUsesDistinctRewardsAndSameMessages() {
    XCTAssertEqual(StreakReward.starMilestones.map(\.threshold), [50, 150, 500])
    for (fire, star) in zip(StreakReward.milestones, StreakReward.starMilestones) {
      XCTAssertNotEqual(fire.id, star.id)
      XCTAssertEqual(fire.message, star.message)
      XCTAssertEqual(star.presentation(userID: ClientProfile.learnerID, best: star.threshold - 1).access, .locked)
      XCTAssertEqual(star.presentation(userID: ClientProfile.learnerID, best: star.threshold).access, .earned)
      XCTAssertEqual(star.presentation(userID: ClientProfile.ownerID, best: 0).access, .preview)
    }
  }
  func testOldOfflineCacheStillDecodes() throws {
    let old = #"{"user_id":"learner","name":"Learner","current":2,"best":3,"completed_today":true,"week_days":2,"days":[]}"#
    let streak = try JSONDecoder().decode(Streak.self, from: Data(old.utf8))
    XCTAssertNil(streak.epoch)
    XCTAssertEqual(streak.best, 3)
  }
}

final class DisplayStateTests: XCTestCase {
  func testServerFailureIsNotReportedAsOffline() {
    let server = NSError(domain: "Sabbo", code: 503)
    XCTAssertFalse(StudyText.failure(server, action: "Oppdater").contains("nett"))
    XCTAssertTrue(StudyText.failure(URLError(.notConnectedToInternet), action: "Oppdater").contains("nett"))
    XCTAssertTrue(StudyText.failure(URLError(.timedOut), action: "Oppdater").contains("lang tid"))
    XCTAssertTrue(StudyText.failure(URLError(.userAuthenticationRequired), action: "Oppdater").contains("Logg inn"))
  }
  func testDatesRespectOsloMidnightAndSummerTime() {
    XCTAssertTrue(StudyText.timestamp("2026-10-14T22:30:00.000Z").contains("15. okt"))
    XCTAssertTrue(StudyText.timestamp("2026-10-14T22:30:00.000Z").contains("00:30"))
    XCTAssertTrue(StudyText.timestamp("2026-12-14T22:30:00Z").contains("23:30"))
    var oslo = Calendar(identifier: .gregorian); oslo.timeZone = StudyText.oslo
    XCTAssertEqual(oslo.component(.hour, from: StudyText.reminderDate(hour: 19, minute: 15)), 19)
    XCTAssertEqual(oslo.component(.minute, from: StudyText.reminderDate(hour: 19, minute: 15)), 15)
  }
}
