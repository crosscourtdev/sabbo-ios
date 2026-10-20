#if DEBUG
  import Foundation
  extension AppModel {
    var testing: Bool { ProcessInfo.processInfo.environment["SABBO_UI_TEST"] == "1" }
    func installTestFixture() {
      guard testing else { return }
      // Separate local account identifier: tests never overwrite a learner's cache.
      session = Session(token: "test-fixture-unusable-token", user_id: "uitest")
      // Each launch replays one-time celebrations, so tests always exercise them.
      UserDefaults.standard.removeObject(forKey: "sabbo.gains.uitest")
      let q = Question(
        id: "pome-km11643-1", version: 1, subject_id: "pome", goal_ids: ["KM11643"],
        prompt:
          "To innlegg hevder at ungdom ikke stemmer. Hvilken kilde gir best grunnlag, og hva må du undersøke?"
      )
      let a = Assignment(
        id: "fixture-assignment", day: "2026-10-13", timezone: "Europe/Oslo", question_id: q.id,
        version: 1)
      local = LocalState()
      local.today = Today(
        assignment: a, question: q, attempt: nil, draft: nil,
        streaks: [
          Streak(
            user_id: "uitest", name: ClientProfile.learnerName, current: 0, best: 0, completed_today: false,
            week_days: 0, days: []),
          Streak(
            user_id: "peer", name: ClientProfile.ownerName, current: 0, best: 0, completed_today: false,
            week_days: 0, days: []),
        ], server_day: a.day)
      editor = ""
      if let state = ProcessInfo.processInfo.environment["SABBO_RESULT_FIXTURE"] {
        installResultFixture(state)
      }
      if ProcessInfo.processInfo.environment["SABBO_DRAFT_FIXTURE"] == "1" {
        let first = Question(id: "q1", version: 1, subject_id: "pome", goal_ids: [], prompt: "Forklar hvordan du undersøker en kilde.")
        let second = Question(id: "q2", version: 1, subject_id: "pome", goal_ids: [], prompt: "Hva vil du sammenligne?")
        let question = Question(id: "draft-session", version: 1, subject_id: "pome", goal_ids: [], prompt: "Vurder informasjon.", parts: [first, second])
        let assignment = Assignment(id: "draft-fixture", day: "2026-10-20", timezone: "Europe/Oslo", question_id: question.id, version: 1)
        local.today = Today(assignment: assignment, question: question, attempt: nil, draft: nil, streaks: [], server_day: assignment.day)
        let base = DraftSync.encode(["q1":"Første utkast", "q2":"Et utkast"])
        let own = DraftSync.encode(["q1":"Jeg undersøker avsenderen.", "q2":"Et utkast"])
        let other = DraftSync.encode(["q1":"Jeg undersøker avsenderen og metoden.", "q2":"Jeg sammenligner flere uavhengige kilder."])
        var sync = DraftSync(revision: 1, base: base)
        local.drafts[assignment.id] = sync.receive(Draft(revision: 2, body: other, assisted: 0), local: own)
        local.draftSync = [assignment.id: sync]
        editor = local.drafts[assignment.id]!
      }
      if let state = ProcessInfo.processInfo.environment["SABBO_BONUS_FIXTURE"] {
        installResultFixture("graded")
        let now = Date(); bonusClock = now
        let formatter = ISO8601DateFormatter()
        local.bonus = BonusState(id: "fixture-bonus", status: state, server_now: formatter.string(from: now), day: "2026-10-16", cutoff: "20:00", assignment_id: "fixture-result", question_id: "fixture-goal", question_version: 1, original_attempt_id: "fixture-attempt", opens_at: formatter.string(from: now.addingTimeInterval(state == "waiting" ? 10800 : -60)), expires_at: formatter.string(from: now.addingTimeInterval(3600)), cosmetic_id: "c001", target_grade: 5, attempt_id: state == "won" ? "fixture-attempt" : nil, grade: state == "won" ? 5 : nil)
        local.cosmetics = CosmeticCollection(items: [CosmeticItem(id: "c001", name: "Blå caps"), CosmeticItem(id: "c002", name: "Rød lue")], owned: ["c001"], people: [])
      }
      if ProcessInfo.processInfo.environment["SABBO_TIMELINE_FIXTURE"] == "1" {
        installResultFixture("graded")
        let daily = local.history[0]
        for (id, grade) in [("bonus-first", 3), ("bonus-latest", 6)] {
          let evaluation = Evaluation(status: "complete", result: GradeResult(status: "graded", grade: grade, reason: "Et selvstendig svar.", strengths: "God begrunnelse.", improvement: "", criteria: []))
          local.history.append(HistoryItem(id: id, answer: daily.answer, question: daily.question, assignment_id: daily.assignment_id, day: daily.day, mode: "bonus", assessment: "completed", assisted: 0, submitted_at: id == "bonus-first" ? "2026-10-16T15:00:00Z" : "2026-10-16T15:10:00Z", revisions: [], evaluations: [evaluation], receipt_status: "practice"))
        }
      }
    }
    private func installResultFixture(_ state: String) {
      let part = Question(id: "fixture-part", version: 1, subject_id: "pome", goal_ids: ["fixture"], prompt: "Hvordan undersøker du en kilde?", title: "Kildekritikk", example_answer: "Undersøk avsender og metode.")
      let question = Question(id: "fixture-goal", version: 1, subject_id: "pome", goal_ids: ["fixture"], prompt: "Vurder en kilde.", parts: [part], title: "Undersøk kilden")
      let assignment = Assignment(id: "fixture-result", day: "2026-10-16", timezone: "Europe/Oslo", question_id: question.id, version: 1)
      let answer = AnswerSet.encode([part.id: "Jeg undersøker utvalget og metoden."])
      let attempt = Attempt(id: "fixture-attempt", user_id: "uitest", assignment_id: assignment.id, answer: answer, assessment: "completed", completed_at: "2026-10-16T12:00:00Z", assisted: 0, receipt_status: state == "late" ? "late" : state == "exception" ? "exception" : "received")
      let streak = Streak(user_id: "uitest", name: ClientProfile.learnerName, current: state == "late" ? 0 : 5, best: state == "late" ? 0 : 5, completed_today: state != "late", week_days: state == "late" ? 0 : 5, days: [], epoch: UUID().uuidString)
      local.today = Today(assignment: assignment, question: question, attempt: state == "offline" ? nil : attempt, draft: nil, streaks: [streak], server_day: assignment.day)
      if state == "offline" {
        local.pending = [Pending(id: "fixture-pending", assignment: assignment, question: question, answer: answer, assisted: false, mode: "daily", started_at: "", assessment: "completed", attempt_id: nil)]
      } else {
        evaluations[attempt.id] = Evaluation(status: state == "waiting" ? "processing" : "completed", result: state == "waiting" ? nil : GradeResult(status: "graded", grade: 5, reason: "Du vurderer kilden med relevante fagbegreper.", strengths: "Du undersøker metoden.", improvement: "Forklar også hvordan utvalget påvirker konklusjonen.", criteria: []))
        local.history = [HistoryItem(id: attempt.id, answer: answer, question: question, assignment_id: assignment.id, day: assignment.day, mode: "daily", assessment: "completed", assisted: 0, submitted_at: "2026-10-16T12:00:00Z", revisions: [], evaluations: [evaluations[attempt.id]!], receipt_status: attempt.receipt_status)]
        local.progress = PairProgress(people: [PersonProgress(streak: streak, stars: Stars(total: state == "late" ? 0 : 50, epoch: UUID().uuidString, awards: ["waiting", "late"].contains(state) ? [] : [StarAward(day: assignment.day, attempt_id: attempt.id, grade: 5, stars: 5)]), fire_attempt_id: state == "late" ? nil : attempt.id, achievements: [
          Achievement(id: "studious", title: "Studious", description: "Få karakter 6 på en dagsøkt.", target: 1, progress: 0, stars: 25, symbol: "graduationcap.fill", earned_at: nil, attempt_id: nil),
          Achievement(id: "smarter_brother", title: "The smarter brother", description: "Få bedre karakter enn \(ClientProfile.ownerName) tre dager på rad.", target: 3, progress: 1, stars: 25, symbol: "bolt.shield.fill", earned_at: nil, attempt_id: nil),
          Achievement(id: "drip_check", title: "Drip check", description: "Bruk tre forskjellige antrekk i dagsoppgavenes illustrasjoner.", target: 3, progress: 2, stars: 25, symbol: "tshirt.fill", earned_at: nil, attempt_id: nil)
        ])])
      }
    }

  }
#else
  extension AppModel {
    var testing: Bool { false }
    func installTestFixture() {}
  }
#endif
