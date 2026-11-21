import SwiftUI

private struct ExamRound: Decodable {
  struct Card: Decodable {
    let id: String
    let question: Question
    let deadline: Double
    let answer: String
  }
  struct Feedback: Decodable, Identifiable {
    let id, title, prompt, answer, status: String
    let result: GradeResult?
  }
  struct Milestone: Decodable {
    let title: String
    let threshold, stars, run, best: Int
    let earned: Bool
  }
  let title: String
  let card: Card?
  let history: [Feedback]
  let milestones: [Milestone]
  let available, conflict: Bool
  let practiced, total: Int
}

struct ExamPractice: View {
  @EnvironmentObject var model: AppModel
  @State private var round: ExamRound?
  @State private var answer = ""
  @State private var busy = false
  @State private var message: String?
  @State private var confirmSkip = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        if let round { Text(round.title).font(.headline) }
        if let round {
          if let card = round.card {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
              let seconds = max(0, Int(ceil(card.deadline - timeline.date.timeIntervalSince1970)))
              VStack(alignment: .leading, spacing: 16) {
                Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                  .font(.largeTitle.monospacedDigit()).accessibilityLabel("Tid igjen: " + String(seconds) + " sekunder")
                QuestionPrompt(question: card.question)
                QuestionMaterials(question: card.question)
                AnswerEditor(text: Binding(get: { answer }, set: {
                  answer = String($0.prefix(6000))
                  UserDefaults.standard.set(["id": card.id, "base": card.answer, "answer": answer], forKey: draftKey)
                }), blocked: { message = "Skriv svaret med egne ord." })
                  .frame(minHeight: 230)
                  .disabled(seconds == 0)
                Button("Lever svar") { Task { await update("submit") } }
                  .buttonStyle(.borderedProminent).disabled(busy || seconds == 0 || answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
              }
            }
            Button("Avbryt oppgaven") { confirmSkip = true }.disabled(busy)
          } else {
            if let last = round.history.first {
              Text(last.title).font(.headline)
              feedback(last)
            } else {
              Text("Skriv ett svar på tre minutter. Oppgaver du strever med kommer tilbake oftere.")
            }
            Text("\(round.practiced) av \(round.total) oppgaver øvd").foregroundStyle(.secondary)
            if round.available {
              Button(round.history.isEmpty ? "Start · 3 minutter" : "Neste oppgave · 3 minutter") {
                Task { await update("start") }
              }.buttonStyle(.borderedProminent).disabled(busy)
            } else {
              Text("Ingen nye oppgaver akkurat nå.").foregroundStyle(.secondary)
            }
            ForEach(round.milestones, id: \.threshold) { m in
              VStack(alignment: .leading) {
                Label("\(m.title) · \(m.stars) stjerner", systemImage: m.earned ? "star.fill" : "star")
                Text("Karakter \(m.threshold)+ · \(m.run) på rad · rekord \(m.best) · mål 3").font(.caption)
              }
            }
            if round.history.count > 1 {
              DisclosureGroup("Tidligere oppgaver") {
                ForEach(round.history.dropFirst()) { item in
                  DisclosureGroup(item.title) { feedback(item) }
                }
              }
            }
          }
        } else if message == nil { ProgressView() }
        if let message {
          Text(message).foregroundStyle(.secondary)
          Button("Oppdater") { Task { await update() } }.disabled(busy)
        }
      }.padding().frame(maxWidth: 740).frame(maxWidth: .infinity)
    }.navigationTitle("Eksamen")
      .confirmationDialog("Avbryte oppgaven og bryte rekken?", isPresented: $confirmSkip) {
        Button("Avbryt oppgaven", role: .destructive) { Task { await update("skip") } }
      }
      .task {
        await update()
        var ticks = 0
        while !Task.isCancelled {
          do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
          ticks += 1
          if let card = round?.card {
            if Date().timeIntervalSince1970 >= card.deadline {
              await update("submit")
            } else if card.answer != answer {
              await update("draft")
            }
          } else if ticks.isMultiple(of: 6), round?.history.contains(where: { ["processing","queued"].contains($0.status) }) == true {
            await update()
          }
        }
      }
  }

  @ViewBuilder private func feedback(_ item: ExamRound.Feedback) -> some View {
    if let result = item.result {
      if let grade = result.grade { Text("Karakter \(grade)").font(.largeTitle.bold()) }
      Text(result.improvement.isEmpty ? result.reason : result.improvement)
      DisclosureGroup("Hele vurderingen") { AssessmentSummary(result: result, showsCriteria: true) }
    } else {
      Text(["processing","queued"].contains(item.status) ? "Svaret vurderes …" :
           item.status == "skipped" ? "Oppgaven er avbrutt." : "Vurdering er utilgjengelig.")
    }
    DisclosureGroup("Oppgaven og svaret ditt") {
      VStack(alignment: .leading, spacing: 10) {
        Text(item.prompt).font(.subheadline)
        Text(item.answer.isEmpty ? "Ingen tekst levert." : item.answer)
      }
    }
  }

  private var draftKey: String { "exam-draft-\(model.session?.user_id ?? "")" }

  @MainActor private func update(_ action: String? = nil) async {
    guard !busy, let user = model.session?.user_id else { return }
    busy = true
    defer { busy = false }
    let previous = round?.card?.id
    do {
      let next: ExamRound
      if let action {
        var body: [String: Any] = ["action": action, "answer": answer]
        if let base = round?.card?.answer { body["base_answer"] = base }
        if let id = previous ?? round?.history.first?.id { body["card_id"] = id }
        next = try await model.api.send("/exam/pome", body: body)
      } else {
        next = try await model.api.get("/exam/pome")
      }
      guard model.session?.user_id == user else { return }
      let draft = UserDefaults.standard.dictionary(forKey: draftKey) as? [String: String]
      if let card = next.card {
        if next.conflict {
          answer = card.answer
        } else if card.id != previous {
          let canRestore = draft?["id"] == card.id && draft?["base"] == card.answer
          answer = canRestore ? draft?["answer"] ?? card.answer : card.answer
        } else if action == nil && answer == round?.card?.answer {
          answer = card.answer
        }
        if card.answer == answer {
          UserDefaults.standard.removeObject(forKey: draftKey)
        } else {
          UserDefaults.standard.set(["id": card.id, "base": card.answer, "answer": answer], forKey: draftKey)
        }
      } else {
        answer = ""
        UserDefaults.standard.removeObject(forKey: draftKey)
      }
      let earned = next.milestones.filter(\.earned).map(\.threshold)
      let refreshRewards = !earned.isEmpty && earned != round?.milestones.filter(\.earned).map(\.threshold)
      round = next
      message = next.conflict ? "En annen enhet lagret svaret først. Det lagrede svaret vises her." : nil
      if refreshRewards { await model.refreshProgress() }
    } catch {
      if !Task.isCancelled { message = "Kunne ikke synkronisere eksamensøkten." }
    }
  }
}
