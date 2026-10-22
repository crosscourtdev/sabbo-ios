import SwiftUI

/// One destination for a day, regardless of whether it was opened from home,
/// a notification, or the shared timeline. Stage selection never changes a grade.
struct DayResultView: View {
  let assignment: Assignment
  let question: Question
  var personID: String? = nil
  var stage = "daily"
  var body: some View {
    ScrollView {
      DayResultsContent(assignment: assignment, question: question, initialPersonID: personID, initialStage: stage)
        .padding(22).frame(maxWidth: 1100).frame(maxWidth: .infinity)
    }.background(Color(.systemGroupedBackground))
      .navigationTitle(StudyText.day(assignment.day)).navigationBarTitleDisplayMode(.inline)
  }
}

struct DayResultsContent: View {
  @EnvironmentObject var model: AppModel
  @Environment(\.scenePhase) private var scenePhase
  let assignment: Assignment
  let question: Question
  var initialPersonID: String? = nil
  var initialStage = "daily"
  var fallback: HistoryItem? = nil
  @State private var loaded: TimelineDay?
  @State private var selectedPerson = ""
  @State private var stage = "daily"
  @State private var error: String?
  @State private var selectedQuestion = 0
  @State private var comparing = false
  private var ownID: String { model.session?.user_id ?? "" }
  private var people: [TimelinePerson] {
    if let loaded { return loaded.people }
    var attempts = model.local.history.filter { $0.assignment_id == assignment.id }
    if let fallback, !attempts.contains(where: { $0.id == fallback.id }) { attempts.append(fallback) }
    return [TimelinePerson(user_id: ownID, name: model.userName,
      attempts: attempts.sorted { $0.submitted_at < $1.submitted_at })]
  }
  private var person: TimelinePerson? { people.first { $0.id == selectedPerson } ?? people.first { $0.id == ownID } ?? people.first }
  private var mine: Bool { person?.id == ownID }
  private var bonus: [HistoryItem] { person?.bonusAttempts ?? [] }
  private var currentBonus: Bool { mine && model.local.bonus?.assignment_id == assignment.id }
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(question.title ?? question.prompt).font(.system(.title3, design: .rounded, weight: .bold))
      if people.count > 1 {
        Picker("Person", selection: $selectedPerson) {
          ForEach(people) { p in Text(p.id == ownID ? "Meg" : p.name).tag(p.id) }
        }.pickerStyle(.segmented).accessibilityIdentifier("result-person")
      }
      if loaded != nil, people.count > 1, people.allSatisfy({ $0.daily != nil }),
         assignment.day == model.local.today?.server_day, !model.answersLocked(question) {
        SharedUnlockBanner(key: "together:" + assignment.id)
      }
      if people.contains(where: { !$0.bonusAttempts.isEmpty }) {
        Picker("Runde", selection: $stage) {
          Text("Dagens økt").tag("daily")
          Text("Bonusrunde").tag("bonus")
        }.pickerStyle(.segmented).accessibilityIdentifier("result-stage")
      }
      if people.count > 1 {
        Toggle("Sammenlign svar", isOn: $comparing).accessibilityIdentifier("compare-answers")
      }
      if comparing {
        comparison
      } else if stage == "bonus", let latest = bonus.last {
        attempt(latest)
        if currentBonus {
          BonusPrizeView()
          if ["retry", "grading_failed"].contains(model.bonusStatus) {
            Button("Prøv bonusrunden igjen") { model.openBonus() }.buttonStyle(PlayButton())
          }
        } else if let id = person?.bonus?.cosmetic_id {
          Label("Tilbehør vunnet", systemImage: "gift.fill").font(.headline)
          CosmeticItemImage(id: id, size: 100)
        }
        if bonus.count > 1 {
          DisclosureGroup("Tidligere forsøk (\(bonus.count - 1))") {
            ForEach(Array(bonus.dropLast().reversed())) { old in
              DisclosureGroup(StudyText.timestamp(old.submitted_at) + " · " + StudyText.evaluation(old.evaluations?.last)) {
                attempt(old)
              }.padding(.top, 12)
            }
          }.font(.subheadline)
        }
      } else if stage == "bonus" {
        Text("Ingen bonusbesvarelse fra denne personen ennå.").foregroundStyle(.secondary)
      } else if let daily = person?.daily {
        attempt(daily)
        if mine {
          QuestGainsView(attemptID: daily.id)
          AchievementCelebration(attemptID: daily.id)
          SessionRewardsView()
        }
        if currentBonus {
          Divider()
          BonusStage(showAction: bonus.isEmpty)
        } else if let b = person?.bonus {
          Label(b.label, systemImage: b.status == "won" ? "gift.fill" : "sparkles").font(.subheadline).foregroundStyle(.secondary)
        }
      } else {
        Text("Dagens økt er ikke levert ennå.").foregroundStyle(.secondary)
      }
      if let p = person {
        let legacy = p.attempts.filter { $0.mode == "optional" }
        if !legacy.isEmpty {
          DisclosureGroup("Tidligere ekstraøving") {
            ForEach(legacy) { old in
              DisclosureGroup(StudyText.timestamp(old.submitted_at)) { attempt(old) }.padding(.top, 10)
            }
          }
        }
      }
      if let error {
        Text(error).font(.caption).foregroundStyle(.secondary)
        Button("Oppdater") { Task { await load() } }
      }
    }
    .environment(\.artworkAssignmentID, assignment.id)
    .task(id: assignment.id) { selectedPerson = initialPersonID ?? ownID; stage = initialStage; selectedQuestion = 0; await load() }

    .onChange(of: model.bonusStatus) { _, _ in Task { await load() } }
    .onChange(of: model.local.history.count) { _, _ in Task { await load() } }
    .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await load() } } }
    .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
      if scenePhase == .active { Task { await load() } }
    }
  }
  @ViewBuilder private func attempt(_ item: HistoryItem) -> some View {
    SubmissionReceiptView(status: item.receipt_status, day: item.day)
    if mine {
      EvaluationCard(attemptID: item.id, question: question, showsCriteria: false, feedbackHidden: item.answers_locked == true)
    } else {
      PeerEvaluation(evaluation: item.evaluations?.last, hidden: item.answers_locked == true || model.answersLocked(question))
    }
    if model.answersLocked(question) {
      // EvaluationCard also hides its feedback immediately when the timer ends.
      if !mine { BonusAnswersHidden() }
    } else if item.answers_locked == true {
      Text("Svarene vises når begge har levert dagens økt.").font(.subheadline).foregroundStyle(.secondary)
    } else {
      ResultAnswersView(question: item.question, answer: item.answer,
        feedback: model.resultFeedback(item.question, assignmentID: assignment.id),
        answerLabel: mine ? "Ditt svar" : "\(person?.name ?? "") sitt svar",
        result: mine ? model.savedEvaluation(item.id)?.result : item.evaluations?.last?.result,
        selection: $selectedQuestion)
        .accessibilityIdentifier("result-answers")
      if !item.revisions.isEmpty {
        DisclosureGroup("Tidligere versjoner") {
          ForEach(item.revisions) { revision in
            Text(StudyText.timestamp(revision.created_at)).font(.caption).foregroundStyle(.secondary)
            AnswerReview(question: question, answer: revision.answer)
          }
        }.font(.subheadline)
      }
    }
  }
  private var comparison: some View {
    VStack(alignment: .leading, spacing: 18) {
      let parts = question.parts ?? [question]
      if !parts.isEmpty {
        let part = parts[min(selectedQuestion, parts.count - 1)]
        QuestionNavigator(parts: parts, selection: $selectedQuestion)
        Text("Oppgave \(min(selectedQuestion, parts.count - 1) + 1)").font(.title3.bold())
        QuestionPrompt(question: part)
        QuestionMaterials(question: part, showExpectations: false)
        ComparisonAnswers(people: people, question: question, part: part, stage: stage, assignmentID: assignment.id)
        SourceLinks(question: part)
      }
    }.padding(18).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
  }
  private func load() async {
    if model.testing { loaded = model.presentationFixture(assignment.id); return }
    let account = ownID
    do {
      let value: TimelineDay = try await model.api.get("/timeline/" + assignment.id)
      guard account == ownID, !Task.isCancelled else { return }
      loaded = value; error = nil
      // Seed own evaluations only. Peer answers never enter the private cache.
      if let own = value.people.first(where: { $0.id == ownID }) {
        for item in own.attempts {
          if let evaluation = item.evaluations?.last, item.answers_locked != true || model.savedEvaluation(item.id) == nil {
            model.evaluations[item.id] = evaluation
          }
        }
      }
    } catch { self.error = "Kunne ikke oppdatere økten. Lagrede resultater vises." }
  }
}

private struct PeerEvaluation: View {
  let evaluation: Evaluation?
  let hidden: Bool
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Veiledende KI-vurdering").font(.caption).foregroundStyle(.secondary)
      Text(StudyText.evaluation(evaluation)).font(.system(.title, design: .rounded, weight: .bold)).foregroundStyle(Color("AccentColor"))
      if !hidden, let result = evaluation?.result {
        AssessmentSummary(result: result)
      }
    }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
      .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
  }
}

private struct ComparisonAnswers: View {
  @EnvironmentObject var model: AppModel
  @Environment(\.horizontalSizeClass) private var sizeClass
  @Environment(\.dynamicTypeSize) private var typeSize
  let people: [TimelinePerson]
  let question: Question
  let part: Question
  let stage: String
  let assignmentID: String
  var body: some View {
    let layout = sizeClass == .regular && !typeSize.isAccessibilitySize
      ? AnyLayout(HStackLayout(alignment: .top, spacing: 24))
      : AnyLayout(VStackLayout(alignment: .leading, spacing: 24))
    layout {
      ForEach(people) { person in
        VStack(alignment: .leading, spacing: 12) {
          let item = stage == "bonus" ? person.bonusAttempts.last : person.daily
          let mine = person.id == model.session?.user_id
          Text(mine ? "Ditt svar" : person.name + " sitt svar").font(.headline)
          if model.answersLocked(question) {
            BonusAnswersHidden()
          } else if let item {
            if item.answers_locked == true {
              Text("Svarene vises når begge har levert dagens økt.").foregroundStyle(.secondary)
            } else {
              let result = mine ? model.savedEvaluation(item.id)?.result : item.evaluations?.last?.result
              if let grade = result?.grade {
                Text("Veiledende KI-vurdering · \(grade) av 6").font(.caption).foregroundStyle(.secondary)
              }
              AnswerAssessment(question: question, part: part, answer: item.answer, label: "Besvarelse",
                result: result, feedback: model.resultFeedback(item.question, assignmentID: assignmentID))
            }
          } else { Text("Ikke levert ennå.").foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .topLeading)
      }
    }
  }
}
