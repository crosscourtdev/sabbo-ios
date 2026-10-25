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
      if ProcessInfo.processInfo.environment["SABBO_UPDATE_FIXTURE"] == "1" {
        availableRelease = ClientRelease(version: "99.0", build: "999", platform: ClientRelease.currentPlatform, app_id: "123456789")
      }
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
      if let mode = ProcessInfo.processInfo.environment["SABBO_PRESENTATION_FIXTURE"] { installPresentationFixture(mode) }
      if ProcessInfo.processInfo.environment["SABBO_MISSED_FIXTURE"] == "1" {
        let first = Question(id: "missed-1", version: 1, subject_id: "pome", goal_ids: [], prompt: "Hvordan undersøker du en kilde?")
        let second = Question(id: "missed-2", version: 1, subject_id: "pome", goal_ids: [], prompt: "Hva vil du sammenligne?")
        let question = Question(id: "missed-session", version: 1, subject_id: "pome", goal_ids: [], prompt: "Vurder informasjon.", parts: [first, second], title: "Undersøk kildene")
        local.missed_days = ["2026-10-12", "2026-10-11"].map { date in
          let assignment = Assignment(id: "missed-" + date, day: date, timezone: "Europe/Oslo", question_id: question.id, version: 1)
          return Today(assignment: assignment, question: question, attempt: nil,
            draft: date == "2026-10-11" ? Draft(revision: 1, body: AnswerSet.encode([first.id: "Utkast fra en annen enhet."]), assisted: 0) : nil,
            streaks: [], server_day: "2026-10-13")
        }
      }
    }
    func presentationFixture(_ assignmentID: String) -> TimelineDay? {
      guard testing, let mode = ProcessInfo.processInfo.environment["SABBO_PRESENTATION_FIXTURE"], mode != "writing",
        let today = local.today, today.id == assignmentID, let own = local.history.first else { return nil }
      let peerResult = Evaluation(status: "complete", result: GradeResult(status: "graded", grade: 4,
        reason: "Et annet perspektiv med gode eksempler.", strengths: "Tydelig sammenligning.", improvement: "Undersøk også begrensningene.",
        criteria: [CriterionResult(criterion_id: "presentation-2.c1", attainment: "partial", evidence: "Jeg sammenligner utvalgene.", comment: "Forklar hva forskjellen betyr.")]))
      let peer = HistoryItem(id: "presentation-peer", answer: AnswerSet.encode(["presentation-1": "Jeg starter med å undersøke hvem som står bak kilden.", "presentation-2": "Jeg sammenligner utvalgene."]), question: today.question,
        assignment_id: assignmentID, day: own.day, mode: "daily", assessment: "completed", assisted: 0,
        submitted_at: own.submitted_at, revisions: [], evaluations: [peerResult], answers_locked: mode == "locked")
      return TimelineDay(assignment: today.assignment, question: today.question,
        people: [TimelinePerson(user_id: "uitest", name: ClientProfile.learnerName, attempts: local.history),
                 TimelinePerson(user_id: "peer", name: ClientProfile.ownerName, attempts: [peer])])
    }
    private func installPresentationFixture(_ mode: String) {
      installResultFixture("graded")
      let first = Question(id: "presentation-1", version: 1, subject_id: "pome", goal_ids: [],
        prompt: "Hvilken kilde gir best grunnlag for å undersøke om en ny leseordning hjelper elever? Sammenlign metode og avsender, og forklar hva du fortsatt trenger å vite.",
        materials: [QuestionMaterial(title: "To kilder", body: "A, elevprosjekt: 80 frivillige leste daglig og fortalte at de husket mer. Deltakerne valgte selv om de ville være med. B, reklame: En butikk lover bedre hukommelse etter kjøp av en leselampe. Ingen metode eller sammenligningsgruppe er oppgitt.")],
        expectations: ["Sammenligne kildenes metode og avsender"], title: "Undersøk kildene", example_answer: "Jeg undersøker både metoden og hvem som deltok.")
      let second = Question(id: "presentation-2", version: 1, subject_id: "pome", goal_ids: [],
        prompt: "Hvordan ville du undersøkt to mulige forklaringer på resultatet? Beskriv hva som kunne styrket eller svekket hver forklaring.",
        expectations: ["Prøve alternative forklaringer"], title: "Undersøk kildene", example_answer: "Jeg sammenligner grupper med ulik lesevane.")
      let q = Question(id: "presentation", version: 1, subject_id: "pome", goal_ids: [], prompt: "Undersøke informasjon og alternative forklaringer.", parts: [first, second], title: "Undersøk kildene")
      let a = Assignment(id: "presentation-day", day: "2026-10-20", timezone: "Europe/Oslo", question_id: q.id, version: 1)
      let longAnswer = "Jeg undersøker hvem som har laget kilden og hvordan deltakerne ble valgt. Et stort utvalg er ikke nødvendigvis representativt.\n\nElevene meldte seg frivillig, så de kan ha vært mer motiverte enn andre elever. Jeg ville sammenlignet med en gruppe som ikke endret lesevanene sine, og undersøkt om begge gruppene fikk samme test."
      let answer = AnswerSet.encode([first.id: longAnswer, second.id: "Jeg sammenligner to forklaringer og undersøker forskjellene mellom gruppene."])
      let result = Evaluation(status: "complete", result: GradeResult(status: "graded", grade: 5,
        reason: "Du skiller mellom det kilden viser og det som fortsatt er usikkert. Begrunnelsen knytter utvalg og metode til konklusjonen, og viser hvordan en sammenligningsgruppe kan bidra til en bedre undersøkelse.",
        strengths: "Du forklarer hvorfor frivillige deltakere kan skille seg fra andre elever.",
        improvement: "Beskriv hvilke opplysninger du vil samle inn om begge gruppene før undersøkelsen starter. Forklar deretter hvordan du vil bruke disse opplysningene til å skille mellom lesetid, motivasjon og tidligere erfaring som mulige forklaringer.",
        criteria: [CriterionResult(criterion_id: first.id + ".c1", attainment: "strong", evidence: "Et stort utvalg er ikke nødvendigvis representativt.", comment: "Du vurderer utvalg og metode konkret."),
                   CriterionResult(criterion_id: second.id + ".c1", attainment: "met", evidence: "Jeg sammenligner to forklaringer", comment: "Du foreslår en relevant sammenligning.")]))
      let item = HistoryItem(id: "presentation-own", answer: answer, question: q, assignment_id: a.id, day: a.day, mode: "daily", assessment: "completed", assisted: 0, submitted_at: "2026-10-20T10:00:00Z", revisions: [], evaluations: [result])
      let bonus = HistoryItem(id: "presentation-bonus", answer: answer, question: q, assignment_id: a.id, day: a.day, mode: "bonus", assessment: "completed", assisted: 0, submitted_at: "2026-10-20T10:10:00Z", revisions: [], evaluations: [result], receipt_status: "practice")
      local.history = mode == "writing" ? [] : [item, bonus]
      evaluations[bonus.id] = result
      evaluations[item.id] = result
      local.bonus = nil
      local.today = Today(assignment: a, question: q, attempt: mode == "writing" ? nil : Attempt(id: item.id, user_id: "uitest", assignment_id: a.id, answer: answer, assessment: "completed", completed_at: item.submitted_at, assisted: 0), draft: nil,
        streaks: local.today!.streaks + [Streak(user_id: "peer", name: ClientProfile.ownerName, current: 2, best: 2, completed_today: true, week_days: 2, days: [])], server_day: a.day)
      if let peer = local.today?.streaks.last {
        local.progress = PairProgress(people: (local.progress?.people ?? []) + [PersonProgress(streak: peer, stars: Stars(total: 40, epoch: "presentation", awards: []), fire_attempt_id: nil)])
      }
      local.drafts = mode == "writing" ? [a.id: AnswerSet.encode([first.id: longAnswer])] : [:]
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
    func presentationFixture(_ assignmentID: String) -> TimelineDay? { nil }
  }
#endif
