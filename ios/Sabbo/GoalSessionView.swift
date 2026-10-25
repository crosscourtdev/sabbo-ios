import SwiftUI
import UIKit

// A whole competency goal is one durable answer set and one assessment.
enum AnswerSet {
  static func decode(_ raw: String) -> [String: String] {
    guard let data = raw.data(using: .utf8) else { return [:] }
    return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
  }
  static func encode(_ values: [String: String]) -> String {
    guard let data = try? JSONEncoder().encode(values) else { return "{}" }
    return String(decoding: data, as: UTF8.self)
  }
  static func scoped(_ raw: String, to question: Question) -> String {
    guard let parts = question.parts else { return raw }
    let allowed = Set(parts.map(\.id))
    return encode(decode(raw).filter { allowed.contains($0.key) })
  }
  static func complete(_ question: Question, _ raw: String) -> Bool {
    guard question.parts != nil else { return !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    let values = decode(raw)
    return (question.parts ?? []).allSatisfy { !(values[$0.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
  }
}

struct StudyVisual: View {
  @EnvironmentObject var model: AppModel
  @Environment(\.artworkAssignmentID) private var inheritedAssignment
  @Environment(\.scenePhase) private var scenePhase
  let question: Question
  var maximumHeight: CGFloat = 200
  var assignmentID: String? = nil
  var recordsOutfit = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var revealed = false
  @State private var downloaded: UIImage?
  private var assignment: String? { assignmentID ?? inheritedAssignment }
  private var identity: String { (model.session?.user_id ?? "") + ":" + (assignment ?? "") + ":" + question.id }
  var body: some View {
    Group {
      if let artwork = downloaded ?? UIImage(named: "Question-" + question.id) {
        Image(uiImage: artwork).resizable().scaledToFit()
          .frame(maxWidth: 360, maxHeight: maximumHeight)
          .clipShape(RoundedRectangle(cornerRadius: 18))
          .frame(maxWidth: .infinity).accessibilityHidden(true)
      }
    }
    .opacity(revealed ? 1 : 0)
    .task(id: identity) {
      downloaded = nil; revealed = false
      await Task.yield()
      guard !Task.isCancelled else { return }
      withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { revealed = true }
      await load()
    }
    .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await load() } } }
    .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
      if scenePhase == .active && downloaded == nil { Task { await load() } }
    }
  }
  private func load() async {
    guard !model.testing, let assignment, let account = model.session?.user_id else { return }
    let current = identity
    if let data = await ArtworkCache.shared.image(api: model.api, account: account, assignment: assignment, question: question.id),
      current == identity, !Task.isCancelled {
      downloaded = UIImage(data: data)
      if recordsOutfit, downloaded != nil {
        let _: Empty? = try? await model.api.send("/assignments/" + assignment + "/artwork/" + ArtworkImage.hash(data) + "/seen", body: [:])
        await model.refreshProgress()
      }
    }
  }
}

/// Keep the exercise readable and make the voice-practice action explicit.
struct QuestionPrompt: View {
  @EnvironmentObject var model: AppModel
  let question: Question
  @State private var copyID: UUID?
  private var allowsCopy: Bool { model.session?.user_id != ClientProfile.learnerID || question.subject_id != "reli" }
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(question.displayPrompt).fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("question-prompt-" + question.id)
      if allowsCopy {
        Button {
          UIPasteboard.general.string = question.voicePracticePrompt
          copyID = UUID()
          UIAccessibility.post(notification: .announcement, argument: "Oppgaven og instruksen for talemodus er kopiert")
        } label: {
          Label(copyID == nil ? "Kopier til talemodus" : "Kopiert", systemImage: copyID == nil ? "doc.on.doc" : "checkmark")
            .font(.subheadline).frame(minHeight: 44)
        }.buttonStyle(.borderless)
          .accessibilityHint("Kopierer oppgaven, materialet og instruksen for muntlig øving.")
      }
    }.onChange(of: question.id) { _, _ in copyID = nil }
      .onChange(of: model.session?.user_id) { _, _ in copyID = nil }
      .task(id: copyID) {
        guard copyID != nil else { return }
        do { try await Task.sleep(for: .seconds(2)) } catch { return }
        copyID = nil
      }
  }
}

struct AnswerReview: View {
  @EnvironmentObject var model: AppModel
  let question: Question
  let answer: String
  var body: some View {
    let values = AnswerSet.decode(answer)
    if model.answersLocked(question) { BonusAnswersHidden() }
    else if let parts = question.parts {
      ForEach(Array(parts.enumerated()), id: \.element.id) { index, part in
        VStack(alignment: .leading, spacing: 8) {
          Text("Oppgave \(index + 1)").font(.headline)
          QuestionPrompt(question: part).font(.subheadline).foregroundStyle(.secondary)
          Text(values[part.id] ?? "").textSelection(.enabled)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
          .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
      }
    } else { Text(answer).textSelection(.enabled) }
  }
}

// Question selection is owned by the day, so switching people retains context.
struct ResultAnswersView: View {
  @EnvironmentObject var model: AppModel
  let question: Question
  let answer: String
  var feedback: Feedback? = nil
  var answerLabel = "Ditt svar"
  var result: GradeResult? = nil
  @Binding var selection: Int
  var body: some View {
    if model.answersLocked(question) { BonusAnswersHidden() } else {
      let parts = question.parts ?? [question]
      if !parts.isEmpty {
        let index = min(selection, parts.count - 1)
        let part = parts[index]
        VStack(alignment: .leading, spacing: 18) {
          QuestionNavigator(parts: parts, selection: $selection)
          Text("Oppgave \(index + 1)").font(.title3.bold())
          QuestionPrompt(question: part).font(.body)
          QuestionMaterials(question: part, showExpectations: false)
          AnswerAssessment(question: question, part: part, answer: answer, label: answerLabel,
            result: result, feedback: feedback)
          if let example = question.parts == nil ? feedback?.example_answer : feedback?.parts?.first(where: { $0.id == part.id })?.example_answer,
             !example.isEmpty {
            DisclosureGroup("Eksempelsvar") { Text(example).textSelection(.enabled).padding(.top, 8) }
          }
          SourceLinks(question: part)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
          .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
          .accessibilityIdentifier("result-question-\(index + 1)")
      }
    }
  }
}

struct AnswerAssessment: View {
  let question: Question
  let part: Question
  let answer: String
  let label: String
  var result: GradeResult?
  var feedback: Feedback?
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(label).font(.headline)
      let value = question.parts == nil ? answer : AnswerSet.decode(answer)[part.id] ?? ""
      Text(value.isEmpty ? "Ingen svartekst tilgjengelig." : value).textSelection(.enabled)
      let criteria = (result?.criteria ?? []).filter { question.parts == nil || StudyPresentation.belongs($0, to: part) }
      if !criteria.isEmpty {
        Divider()
        Text("Vurdering av denne oppgaven").font(.subheadline.bold())
        ForEach(criteria) { criterion in
          CriterionFeedback(criterion: criterion, part: feedback?.parts?.first(where: { $0.id == part.id }) ?? part)
        }
      }
    }.frame(maxWidth: .infinity, alignment: .topLeading)
  }
}

struct GoalSessionView: View {
  @EnvironmentObject var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let day: Today
  var mode: String = "daily"
  var bonusID: String? = nil
  @State private var raw = "{}"
  @State private var index = 0
  @State private var reviewing = false
  @State private var draftVersions = false
  @State private var working = false
  @State private var delivered: String?
  @State private var deliveredID: String?
  var parts: [Question] { day.question.parts ?? [] }
  var draftKey: String { mode == "bonus" ? "bonus-" + (bonusID ?? day.id) : (mode == "optional" ? "practice-" : "") + day.assignment.id }
  var current: Today { model.local.today?.id == day.id ? model.local.today! : day }
  var isLate: Bool { mode == "daily" && day.assignment.day < max(model.local.today?.server_day ?? "", day.server_day) }
  var pending: Pending? { model.local.pending.last { $0.assignment.id == day.id && $0.mode == mode } }
  var answer: String? { delivered ?? pending?.answer ?? (mode == "daily" ? current.attempt?.answer ?? model.local.history.first(where: { $0.assignment_id == day.id && $0.mode == "daily" })?.answer : nil) }
  var attemptID: String? {
    deliveredID ?? pending?.attempt_id ?? (mode == "daily" ? current.attempt?.id : nil)
      ?? model.local.history.first(where: { $0.assignment_id == day.id && $0.mode == mode && $0.answer == answer })?.id
  }
  var body: some View {
    ScrollViewReader { scroll in
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          Color.clear.frame(height: 1).id("top")
          if isLate, answer == nil {
            VStack(alignment: .leading, spacing: 6) {
              Label(StudyText.day(day.assignment.day), systemImage: "calendar").font(.headline)
              Text("Du får karakter og tilbakemelding. Sene svar gir ikke stjerner eller dager på rad.")
                .font(.footnote).foregroundStyle(.secondary)
            }.accessibilityIdentifier("late-session-notice")
          }
          if mode == "daily", !model.answersLocked(day.question) {
            HStack {
              if answer == nil { Text(model.draftStatus).font(.caption).foregroundStyle(.secondary) }
              Spacer()
              if let state = model.local.draftSync?[day.id], state.conflict != nil || !state.backups.isEmpty {
                Button(state.conflict != nil ? "Velg svar" : "Tidligere svar") { draftVersions = true }
                  .font(.caption.bold())
              }
            }
          }
          if let answer {
            if let attemptID {
              DayResultsContent(assignment: day.assignment, question: day.question, initialStage: mode == "bonus" ? "bonus" : "daily",
                fallback: HistoryItem(id: attemptID, answer: answer, question: day.question, assignment_id: day.id, day: day.assignment.day, mode: mode, assessment: "completed", assisted: 0, submitted_at: "", revisions: [], receipt_status: mode == "daily" ? current.attempt?.receipt_status : "practice"))
            } else {
              VStack(alignment: .leading, spacing: 8) {
                Label("Lagret på telefonen – ikke levert ennå", systemImage: "icloud.and.arrow.up").font(.headline)
                Text("Åpne appen på nett for å levere.").font(.subheadline).foregroundStyle(.secondary)
              }.padding(20)
              DisclosureGroup("Svar") { AnswerReview(question: day.question, answer: answer) }
            }
          } else if reviewing {
            Text("Se over svarene").font(.system(.title, design: .rounded, weight: .bold))
            let values = AnswerSet.decode(raw)
            ForEach(Array(parts.enumerated()), id: \.element.id) { i, part in
              VStack(alignment: .leading, spacing: 10) {
                HStack {
                  Text("Oppgave \(i + 1)").font(.headline)
                  Spacer()
                  Button("Endre") { advance { index = i; reviewing = false }; scroll.scrollTo("top") }
                }
                QuestionPrompt(question: part).font(.subheadline).foregroundStyle(.secondary)
                Text(values[part.id] ?? "")
              }.padding(18).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
            }
            Button {
              if mode == "daily", model.local.draftSync?[day.id]?.conflict != nil {
                draftVersions = true; return
              }
              working = true
              Task {
                if mode == "bonus", let bonusID {
                  if let submitted = await model.submitBonus(bonusID, question: day.question, answer: raw) {
                    delivered = submitted.answer; deliveredID = submitted.id
                  }
                } else if let submitted = await model.submit(mode: mode, assignment: day.assignment, question: day.question, answer: raw) {
                  delivered = submitted.answer
                  deliveredID = submitted.attempt_id
                }
                if delivered != nil {
                  SabboFX.shared.play(.submit)
                  SabboFX.shared.haptic(.success)
                }
                working = false
                if mode == "daily", model.local.draftSync?[day.id]?.conflict != nil { draftVersions = true }
                scroll.scrollTo("top")
              }
            } label: {
              HStack { Text("Lever hele økten"); Spacer(); if working { ProgressView() } else { Image(systemName: "checkmark") } }
            }.buttonStyle(PlayButton()).disabled(working || !AnswerSet.complete(day.question, raw) )
              .accessibilityIdentifier("submit-session")
          } else if !parts.isEmpty {
            let part = parts[min(index, parts.count - 1)]
            VStack(alignment: .leading, spacing: 10) {
              HStack {
                Text("Oppgave \(index + 1) av \(parts.count)").contentTransition(.numericText(value: Double(index)))
                Spacer(); Text(StudyText.subject(day.question.subject_id))
              }.font(.subheadline.weight(.semibold))
              let completed = parts.filter { !(AnswerSet.decode(raw)[$0.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
              ProgressView(value: Double(completed), total: Double(parts.count)).accessibilityLabel("\(completed) av \(parts.count) oppgaver har svar")
              DisclosureGroup("Oppgaveoversikt · \(completed) av \(parts.count) har svar") {
                ForEach(Array(parts.enumerated()), id: \.element.id) { i, item in
                  Button {
                    endEditing(); advance { index = i }; scroll.scrollTo("top")
                  } label: {
                    HStack(alignment: .top) {
                      Image(systemName: (AnswerSet.decode(raw)[item.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "circle" : "checkmark.circle.fill")
                      Text("\(i + 1). " + item.displayPrompt).multilineTextAlignment(.leading)
                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                  }.accessibilityAddTraits(i == index ? .isSelected : [])
                }
              }
              DisclosureGroup("Dagens kompetansemål") { Text(day.question.prompt).font(.subheadline).padding(.top, 8) }
            }
            // Overlapping parts cross-fade in place instead of pushing the layout around.
            ZStack(alignment: .topLeading) {
              VStack(alignment: .leading, spacing: 20) {
                Text("Oppgave \(index + 1)").font(.system(.title2, design: .rounded, weight: .bold))
                QuestionPrompt(question: part).font(.body)
                StudyVisual(question: part, maximumHeight: 140, assignmentID: day.assignment.id, recordsOutfit: mode == "daily")
                QuestionMaterials(question: part, showExpectations: false)
                Text("Ditt svar").font(.headline)
                AnswerEditor(text: Binding(get: { AnswerSet.decode(raw)[part.id] ?? "" }, set: { value in
                  var values = AnswerSet.decode(raw); values[part.id] = value; raw = AnswerSet.encode(values); save()
                }), blocked: { model.message = "Skriv svaret med egne ord." })
                  .frame(minHeight: 230)
              }.id(part.id)
                .transition(reduceMotion ? .opacity : .asymmetric(insertion: .opacity.combined(with: .offset(y: 18)), removal: .opacity))
            }
            QuestionExpectations(question: part)
            SourceLinks(question: part)
          }
        }.padding(22).frame(maxWidth: 620).frame(maxWidth: .infinity)
      }.scrollDismissesKeyboard(.interactively).background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
          if answer == nil, !reviewing, !parts.isEmpty {
            let part = parts[min(index, parts.count - 1)]
            HStack {
              if index > 0 { Button("Tilbake") { endEditing(); advance { index -= 1 }; scroll.scrollTo("top") }.frame(minHeight: 44) }
              Button(index + 1 == parts.count ? "Se over svarene" : "Neste oppgave") {
                SabboFX.shared.play(.step)
                SabboFX.shared.haptic(.step)
                endEditing(); advance { if index + 1 == parts.count { reviewing = true } else { index += 1 } }
                scroll.scrollTo("top")
              }.buttonStyle(PlayButton())
                .disabled((AnswerSet.decode(raw)[part.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("next-question")
            }
              .padding(.horizontal, 22).padding(.vertical, 10)
              .frame(maxWidth: 620).frame(maxWidth: .infinity).background(.regularMaterial)
          }
        }
    }.safeAreaInset(edge: .bottom) {
      if answer != nil {
        Button("Ferdig") { dismiss() }.buttonStyle(PlayButton())
          .accessibilityIdentifier("result-done")
          .padding(.horizontal, 22).padding(.vertical, 12)
          .frame(maxWidth: 620).frame(maxWidth: .infinity)
          .background(.regularMaterial)
      }
    }.navigationTitle(answer == nil ? (mode == "bonus" ? "Bonusrunde" : isLate ? "Ta igjen økt" : "Dagens økt") : "Resultat").navigationBarTitleDisplayMode(.inline)
      .toolbar { if answer == nil { Button("Lukk", systemImage: "xmark") { save(); dismiss() } } }
      .sheet(isPresented: $draftVersions, onDismiss: {
        if answer == nil { raw = model.local.drafts[draftKey] ?? raw }
      }) { NavigationStack { DraftVersionsView(day: current) } }
      .onChange(of: model.local.drafts[draftKey]) { _, _ in
        // A render can observe an earlier keystroke after another edit was saved.
        // Read the current draft so that our own save notifications cannot rewind typing.
        if answer == nil, let value = model.local.drafts[draftKey], !DraftSync.equal(raw, value) { raw = value }
      }
      .onChange(of: index) { _, value in
        guard parts.indices.contains(value), answer == nil else { return }
        if model.local.editorPositions == nil { model.local.editorPositions = [:] }
        model.local.editorPositions?[draftKey] = parts[value].id; model.persist()
      }
      .onAppear { restoreSession() }
      .onChange(of: day.id) { _, _ in restoreSession(resetDelivery: true) }
  }
  private func restoreSession(resetDelivery: Bool = false) {
    raw = AnswerSet.scoped(model.local.drafts[draftKey] ?? (mode == "bonus" ? nil : current.draft?.body) ?? "{}", to: day.question)
    index = StudyPresentation.resumeIndex(parts: parts, saved: model.local.editorPositions?[draftKey], answer: raw)
    if resetDelivery {
      reviewing = false
      delivered = nil
      deliveredID = nil
    }
  }
  private func endEditing() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
  }
  private func advance(_ change: () -> Void) {
    withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .snappy(duration: 0.32), change)
  }
  func save() {
    guard answer == nil else { return }
    if mode == "daily", day.id == model.local.today?.id { model.edit(raw) }
    else {
      model.local.drafts[draftKey] = raw; model.persist()
      if mode == "daily" { model.scheduleDraftSync(day: day) }
    }
  }
}

struct QuestionLibraryView: View {
  @EnvironmentObject var model: AppModel
  @State private var sessions: [Question] = []
  @State private var error: String?
  var body: some View {
    List {
      if let error { Text(error); Button("Prøv igjen") { Task { await load() } } }
      ForEach(["pome", "reli", "psyc", "samf"], id: \.self) { subject in
        Section(StudyText.subject(subject)) {
          ForEach(sessions.filter { $0.subject_id == subject }) { session in
            NavigationLink {
              ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                  Text(session.prompt).font(.title2.bold())
                  Text("\(session.parts?.count ?? 1) oppgaver · \(session.goal_ids.joined(separator: ", "))").font(.caption).foregroundStyle(.secondary)
                  ForEach(Array((session.parts ?? [session]).enumerated()), id: \.element.id) { index, part in
                    VStack(alignment: .leading, spacing: 12) {
                      Text("Oppgave \(index + 1)").font(.headline)
                      StudyVisual(question: part)
                      QuestionPrompt(question: part)
                      QuestionMaterials(question: part, showExpectations: false)
                      if let example = part.example_answer { Text("Eksempelsvar").font(.subheadline.bold()); Text(example) }
                      let criteria = part.rubric?.criteria.map(\.expectation) ?? part.key_points ?? []
                      if !criteria.isEmpty {
                        Text("Vurderingskriterier").font(.subheadline.bold())
                        ForEach(Array(criteria.enumerated()), id: \.offset) { _, criterion in
                          Text("• " + criterion).font(.subheadline).foregroundStyle(.secondary)
                        }
                      }
                      ForEach(part.sources ?? [], id: \.url) { source in
                        if let url = URL(string: source.url) { Link(source.title ?? source.url, destination: url).font(.caption) }
                      }
                    }.padding(18).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                  }
                }.padding(20)
              }.background(Color(.systemGroupedBackground)).navigationTitle("Forhåndsvisning").navigationBarTitleDisplayMode(.inline)
            } label: {
              VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                  ForEach(session.parts ?? [session]) { part in
                    StudyVisual(question: part, maximumHeight: 100)
                  }
                }
                Text(session.title ?? session.prompt)
                Text("\(session.parts?.count ?? 1) oppgaver").font(.caption).foregroundStyle(.secondary)
              }.padding(.vertical, 6)
            }
          }
        }
      }
    }.navigationTitle("Oppgavebibliotek")
      .task { await load() }
      .refreshable { await load() }
  }
  private func load() async {
    do { sessions = try await model.api.get("/admin/questions"); error = nil }
    catch { self.error = StudyText.failure(error, action: "Åpne oppgavebiblioteket") }
  }
}


/// Essential task evidence stays open; optional criteria and links stay compact.
struct QuestionMaterials: View {
  let question: Question
  var showExpectations = true
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      ForEach(Array((question.materials ?? []).enumerated()), id: \.offset) { _, material in
        VStack(alignment: .leading, spacing: 8) {
          Label(material.title, systemImage: "doc.text").font(.subheadline.bold())
          ForEach(Array(StudyPresentation.paragraphs(material.body).enumerated()), id: \.offset) { _, paragraph in
            Text(paragraph).font(.body).fixedSize(horizontal: false, vertical: true).padding(.bottom, 4)
          }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
          .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
      }
      if showExpectations {
        QuestionExpectations(question: question)
        SourceLinks(question: question)
      }
    }
  }
}

struct QuestionExpectations: View {
  let question: Question
  var body: some View {
    if let expectations = question.expectations, !expectations.isEmpty {
      DisclosureGroup("Dette vurderes") {
        ForEach(Array(expectations.enumerated()), id: \.offset) { _, expectation in
          Text("• " + expectation).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
        }
      }
    }
  }
}
