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
    let id: String
    let threshold, stars, run: Int
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
  let canCelebrate: Bool
  @State private var celebration: RewardCelebration?
  @EnvironmentObject var model: AppModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var round: ExamRound?
  @State private var answer = ""
  @State private var busy = false
  @State private var message: String?
  @State private var confirmSkip = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        if let round {
          if let card = round.card {
            writing(card)
          } else {
            practiceSummary(round)
          }
        } else if message == nil { ProgressView() }
        if let message {
          Text(message).foregroundStyle(.secondary)
          Button("Oppdater") { Task { await update() } }.disabled(busy)
        }
      }.padding(20).frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity)
    }
      .background(Color(.systemGroupedBackground))
      .navigationTitle("Øving")
      .toolbar {
        if round?.card != nil {
          ToolbarItem(placement: .primaryAction) {
            Menu {
              Button("Avbryt oppgaven", role: .destructive) { confirmSkip = true }
            } label: { Label("Valg for oppgaven", systemImage: "ellipsis.circle") }
            .disabled(busy)
          }
        }
      }
      .fullScreenCover(item: $celebration) { value in
        RewardCelebrationView(celebration: value).presentationBackground(.clear)
      }
      .onChange(of: model.celebrationScope) { _, _ in celebration = nil }
      .task(id: celebrationTrigger) {
        guard canCelebrate, let round, round.card == nil, celebration == nil else { return }
        let ids = Set(round.milestones.filter(\.earned).map(\.id))
        let recorded = model.ownProgress?.achievements?.filter(\.earned).map(\.id) ?? []
        guard !ids.isEmpty, ids.isSubset(of: recorded) else { return }
        let notices = model.pendingRewardNotices().filter { notice in
          if case .achievement(let achievement) = notice.content { return ids.contains(achievement.id) }
          return false
        }
        if !notices.isEmpty {
          celebration = RewardCelebration(scope: model.celebrationScope, notices: notices)
        }
      }
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

  private var celebrationTrigger: [String] {
    guard canCelebrate, celebration == nil, let round, round.card == nil else { return [] }
    let earned = model.ownProgress?.achievements?.filter(\.earned).map(\.id) ?? []
    return [model.celebrationScope] + round.milestones.filter(\.earned).map(\.id) + earned
  }

  private func writing(_ card: ExamRound.Card) -> some View {
    TimelineView(.periodic(from: .now, by: 1)) { timeline in
      let seconds = max(0, Int(ceil(card.deadline - timeline.date.timeIntervalSince1970)))
      VStack(alignment: .leading, spacing: 18) {
        HStack(alignment: .firstTextBaseline) {
          Text(card.question.title ?? "Oppgave").font(.system(.title2, design: .rounded, weight: .bold))
          Spacer(minLength: 12)
          Label(String(format: "%d:%02d", seconds / 60, seconds % 60), systemImage: "timer")
            .font(.headline.monospacedDigit()).fixedSize()
            .accessibilityLabel("Tid igjen: \(seconds) sekunder")
        }
        QuestionPrompt(question: card.question)
        QuestionMaterials(question: card.question)
        AnswerEditor(text: Binding(get: { answer }, set: {
          answer = String($0.prefix(6000))
          UserDefaults.standard.set(["id": card.id, "base": card.answer, "answer": answer], forKey: draftKey)
        }), blocked: { message = "Skriv svaret med egne ord." })
          .frame(minHeight: 230).disabled(seconds == 0)
          .accessibilityLabel("Ditt svar")
        Button("Lever svar") { Task { await update("submit") } }.buttonStyle(PlayButton())
          .disabled(busy || seconds == 0 || answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
  }

  @ViewBuilder private func practiceSummary(_ round: ExamRound) -> some View {
    let last = round.history.first
    let pending = last.map { ["processing", "queued"].contains($0.status) } ?? false
    let failed = last.map { $0.status != "skipped" && $0.result == nil } == true && !pending
    if let last {
      VStack(alignment: .leading, spacing: 10) {
        Text(last.title).font(.subheadline).foregroundStyle(.secondary)
        if pending {
          SabboReadingAnswer().frame(width: 220, height: 196).frame(maxWidth: .infinity)
            .transition(.asymmetric(insertion: .opacity, removal: .offset(y: -8).combined(with: .opacity)))
        } else if let result = last.result {
          if let grade = result.grade {
            Text("Karakter \(grade)").font(.system(.largeTitle, design: .rounded, weight: .bold))
          }
          Text(result.improvement.isEmpty ? result.reason : result.improvement)
          if result.grade != nil { streakProgress(round) }
        } else if failed {
          Button("Prøv vurderingen igjen") { Task { await update("retry") } }
            .buttonStyle(PlayButton()).disabled(busy)
        } else {
          Text(statusText(last)).font(.headline)
        }
      }.animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: pending)
    } else {
      Text(round.title).font(.system(.title2, design: .rounded, weight: .bold))
      Text("Tre minutter per oppgave. Oppgaver du strever med kommer tilbake oftere.")
        .foregroundStyle(.secondary)
      streakProgress(round)
    }
    if !pending && !failed {
      if round.available {
        Button(last == nil ? "Start øving" : "Neste oppgave") { Task { await update("start") } }
          .buttonStyle(PlayButton()).disabled(busy)
      } else {
        Text("Ingen nye oppgaver akkurat nå.").foregroundStyle(.secondary)
      }
    }
    if let last, !pending {
      DisclosureGroup("Se gjennom svaret") { review(last) }.id(last.id)
    }
    Text("\(round.practiced) av \(round.total) oppgaver øvd").font(.footnote).foregroundStyle(.secondary)
    if round.history.count > 1 {
      DisclosureGroup("Tidligere svar") {
        ForEach(round.history.dropFirst()) { item in
          DisclosureGroup(item.title) { review(item) }.padding(.vertical, 6)
        }
      }
    }
  }

  @ViewBuilder private func streakProgress(_ round: ExamRound) -> some View {
    let target = round.milestones.filter { !$0.earned }.sorted {
      if $0.run != $1.run { return $0.run > $1.run }
      return $0.threshold < $1.threshold
    }.first
    if let target {
      VStack(alignment: .leading, spacing: 7) {
        HStack(spacing: 5) {
          ForEach(0..<3) { step in
            Capsule().fill(step < target.run ? SabboStyle.forest : Color.secondary.opacity(0.22))
              .frame(width: 28, height: 5)
          }
        }.accessibilityHidden(true)
        Text(target.run == 2
             ? "Én til med \(target.threshold) eller bedre gir \(target.stars) stjerner."
             : "\(target.run) av 3 oppgaver på rad med \(target.threshold) eller bedre")
          .font(.subheadline).foregroundStyle(.secondary)
      }
    }
  }

  private func statusText(_ item: ExamRound.Feedback) -> String {
    switch item.status {
    case "processing", "queued": return "Svaret vurderes …"
    case "skipped": return "Oppgaven er avbrutt."
    default: return "Vurdering er utilgjengelig."
    }
  }

  private func review(_ item: ExamRound.Feedback) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(item.prompt)
      Divider()
      Text("Ditt svar").font(.headline)
      Text(item.answer.isEmpty ? "Ingen tekst levert." : item.answer)
      if let result = item.result {
        if let grade = result.grade { Text("Karakter \(grade)").font(.headline) }
        AssessmentSummary(result: result, showsCriteria: true)
      } else { Text(statusText(item)).foregroundStyle(.secondary) }
    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
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

private struct SabboReadingAnswer: UIViewRepresentable {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeUIView(context: Context) -> ReadingAnswerImageView { ReadingAnswerImageView() }
  func updateUIView(_ view: ReadingAnswerImageView, context: Context) {
    view.reduceMotion = reduceMotion
  }
}

final class ReadingAnswerImageView: UIImageView {
  var reduceMotion = false { didSet { updatePlayback() } }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    contentMode = .scaleAspectFit
    isAccessibilityElement = true
    accessibilityLabel = "Svaret er levert og vurderes"
    updatePlayback()
  }

  private func updatePlayback() {
    guard window != nil, !reduceMotion else {
      stopAnimating()
      animationImages = nil
      image = Self.still
      return
    }
    if animationImages == nil {
      image = Self.still
      animationImages = Self.frames
      animationDuration = 2.8
      animationRepeatCount = 0
    }
    if !isAnimating { startAnimating() }
  }

  private static let portrait = UIImage(named: "Portrait")
  private static let still = frame(0.43)
  private static let frames = (0..<42).map { frame(CGFloat($0) / 42) }

  // Sabbo follows the pencil across three lines, then lifts his head as the page turns.
  private static func frame(_ phase: CGFloat) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1.5
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 220, height: 196), format: format)
    return renderer.image { output in
      let ctx = output.cgContext
      let writing = min(phase / 0.78, 1) * 3
      let line = min(2, Int(writing))
      let amount = writing - CGFloat(line)
      let lift = phase < 0.78 ? 0 : sin((phase - 0.78) / 0.22 * .pi)
      let scan = sin(2 * .pi * writing - .pi / 2)
      let ink = UIColor(red: 0.08, green: 0.24, blue: 0.19, alpha: 1)
      ctx.saveGState()
      ctx.translateBy(x: 106 + 7 * scan, y: 75 + 5 * cos(2 * .pi * writing) - 10 * lift)
      ctx.rotate(by: (6 * scan - 6 * lift) * .pi / 180)
      let face = CGRect(x: -65, y: -65, width: 130, height: 130)
      UIBezierPath(roundedRect: face, cornerRadius: 34).addClip()
      portrait?.draw(in: face)
      ctx.restoreGState()

      ctx.translateBy(x: 48, y: 116 - 7 * lift)
      ctx.rotate(by: (-0.07 - 0.15 * lift))
      let paper = UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 127, height: 68), cornerRadius: 7)
      UIColor(white: 0.99, alpha: 1).setFill()
      paper.fill()
      ink.setStroke()
      paper.lineWidth = 2
      paper.stroke()
      let widths: [CGFloat] = [84, 96, 69]
      for i in 0...line {
        let length = widths[i] * (i == line ? amount : 1)
        let path = UIBezierPath()
        let y = CGFloat(16 + 17 * i)
        path.move(to: CGPoint(x: 13, y: y))
        for x in stride(from: CGFloat(0), through: length, by: 1) {
          path.addLine(to: CGPoint(x: 13 + x, y: y + 2 * sin(x * 0.55)))
        }
        path.lineWidth = 2.5
        path.lineCapStyle = .round
        path.stroke()
      }
      let x = widths[line] * amount
      ctx.translateBy(x: 13 + x + 10 * lift, y: CGFloat(16 + 17 * line) + 2 * sin(x * 0.55) - 15 * lift)
      ctx.rotate(by: 0.55 + 0.12 * scan)
      let barrel = UIBezierPath(roundedRect: CGRect(x: -5, y: -46, width: 10, height: 39), cornerRadius: 3)
      UIColor.systemOrange.setFill()
      barrel.fill()
      barrel.lineWidth = 1.5
      barrel.stroke()
      let tip = UIBezierPath()
      tip.move(to: .zero)
      tip.addLine(to: CGPoint(x: -5, y: -8))
      tip.addLine(to: CGPoint(x: 5, y: -8))
      tip.close()
      ink.setFill()
      tip.fill()
    }
  }
}
