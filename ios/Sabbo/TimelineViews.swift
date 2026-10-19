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
        .padding(22).frame(maxWidth: 620).frame(maxWidth: .infinity)
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
      if !bonus.isEmpty {
        Picker("Runde", selection: $stage) {
          Text("Dagens økt").tag("daily")
          Text("Bonusrunde").tag("bonus")
        }.pickerStyle(.segmented).accessibilityIdentifier("result-stage")
      }
      if stage == "bonus", let latest = bonus.last {
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
    .task(id: assignment.id) { selectedPerson = initialPersonID ?? ownID; stage = initialStage; await load() }
    .onChange(of: selectedPerson) { old, _ in if !old.isEmpty { stage = "daily" } }
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
      EvaluationCard(attemptID: item.id, question: question)
    } else {
      PeerEvaluation(evaluation: item.evaluations?.last, hidden: item.answers_locked == true || model.answersLocked(question))
    }
    if model.answersLocked(question) {
      // EvaluationCard also hides its feedback immediately when the timer ends.
      if !mine { BonusAnswersHidden() }
    } else if item.answers_locked == true {
      Text("Svarene vises når begge har levert dagens økt.").font(.subheadline).foregroundStyle(.secondary)
    } else {
      DisclosureGroup("Svar og eksempelsvar") {
        ResultAnswersView(question: question, answer: item.answer,
          feedback: model.resultFeedback(question, assignmentID: assignment.id),
          answerLabel: mine ? "Ditt svar" : "\(person?.name ?? "") sitt svar").padding(.top, 10)
      }.font(.subheadline).accessibilityIdentifier("result-answers")
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
  private func load() async {
    guard !model.testing else { return }
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
      Text(StudyText.evaluation(evaluation)).font(.system(.title, design: .rounded, weight: .bold)).foregroundStyle(Color("AccentColor"))
      if !hidden, let result = evaluation?.result {
        Text(result.reason)
        if !result.improvement.isEmpty { Label("Neste steg", systemImage: "arrow.up.right").font(.subheadline.bold()); Text(result.improvement).font(.subheadline) }
        DisclosureGroup("Vurderingsdetaljer") {
          Text(result.strengths)
          ForEach(result.criteria) { criterion in
            Text(criterion.comment).padding(.top, 8)
            if !criterion.evidence.isEmpty { Text("«\(criterion.evidence)»").italic() }
          }
        }.font(.subheadline)
      }
    }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
      .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
  }
}
