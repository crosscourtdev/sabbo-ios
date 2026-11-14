import SwiftUI

struct WritingContext: Equatable {
  let key: String
  let questionID: String
}

struct WritingEvent: Codable, Identifiable {
  var id: String { "\(at):\(kind):\(question_id)" }
  let at: Double
  let kind: String
  let question_id: String
  let words: Int
  let characters: Int
  let writing_seconds: Double
}

struct WritingReceipt: Codable {
  var session_id = UUID().uuidString
  var platform = ClientRelease.currentPlatform
  var truncated = false
  var events: [WritingEvent] = []
}

/// Only counts and timestamps are retained here, never text or keystrokes.
struct WritingCapture: Codable {
  var receipt = WritingReceipt()
  var questionID = ""
  var words = 0
  var characters = 0
  var writingSeconds = 0.0
  var lastEdit: Double?
  var lastSample: Double?
  var active = false

  mutating func append(_ kind: String, at time: Double) {
    let at = max(time, receipt.events.last?.at ?? time)
    let event = WritingEvent(at: at, kind: kind, question_id: questionID, words: words,
      characters: characters, writing_seconds: writingSeconds)
    if receipt.events.count == 1000 {
      receipt.truncated = true
      receipt.events.remove(at: 1) // Preserve the start and latest observations.
    }
    receipt.events.append(event)
  }

  mutating func edit(_ text: String, question: String, at time: Double) {
    if questionID != question || !active {
      if !questionID.isEmpty && active { append("close", at: time) }
      questionID = question; lastEdit = nil; lastSample = nil; active = true
    }
    words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    characters = text.count
    if let lastEdit, (0...5).contains(time - lastEdit) { writingSeconds += time - lastEdit }
    lastEdit = time
    if lastSample == nil || time - lastSample! >= 10 {
      append("write", at: time); lastSample = time
    }
  }

  mutating func phase(_ kind: String, at time: Double) {
    guard !questionID.isEmpty else { return }
    if kind == "inactive", !active { return }
    if kind == "active", active { return }
    append(kind, at: time)
    if ["inactive", "background", "close", "submit"].contains(kind) {
      active = false; lastEdit = nil; lastSample = nil
    } else if kind == "active" { active = true }
  }
}

struct PendingWritingReceipt: Codable {
  let attempt_id: String
  let receipt: WritingReceipt
}

struct WritingReport: Codable {
  let attempt_id: String
  let submitted_at: String
  let expired: Bool
  let sessions: [WritingReceipt]
}

extension AppModel {
  var recordsWriting: Bool { session?.user_id == ClientProfile.learnerID && !storageReadFailed }
  func recordWriting(_ context: WritingContext?, text: String, at date: Date = Date()) {
    guard recordsWriting, let context else { return }
    if let previous = activeWritingContext, previous != context { endWriting(previous) }
    activeWritingContext = context
    var captures = local.writingCaptures ?? [:]
    var capture = captures[context.key] ?? WritingCapture()
    capture.edit(text, question: context.questionID, at: date.timeIntervalSince1970)
    captures[context.key] = capture
    // Limit abandoned local sessions. Pending hand-ins retain their own receipt.
    if captures.count > 60, let oldest = captures.keys.filter({ $0 != context.key }).min(by: {
      (captures[$0]?.receipt.events.last?.at ?? 0) < (captures[$1]?.receipt.events.last?.at ?? 0)
    }) { captures.removeValue(forKey: oldest) }
    local.writingCaptures = captures; persist()
  }
  func blockedWritingPaste(_ context: WritingContext?, text: String) {
    guard recordsWriting, let context else { return }
    if local.writingCaptures?[context.key] == nil {
      var capture = WritingCapture(); capture.questionID = context.questionID
      capture.words = text.split(whereSeparator: { $0.isWhitespace }).count
      capture.characters = text.count
      local.writingCaptures = (local.writingCaptures ?? [:]).merging([context.key: capture]) { _, new in new }
    }
    activeWritingContext = context
    local.writingCaptures?[context.key]?.questionID = context.questionID
    local.writingCaptures?[context.key]?.append("paste", at: Date().timeIntervalSince1970)
    persist()
  }
  func endWriting(_ context: WritingContext?) {
    guard recordsWriting, let context, activeWritingContext == context else { return }
    local.writingCaptures?[context.key]?.phase("close", at: Date().timeIntervalSince1970)
    activeWritingContext = nil; persist()
  }
  func writingPhase(_ phase: ScenePhase) {
    guard recordsWriting, let context = activeWritingContext else { return }
    let kind = phase == .active ? "active" : phase == .background ? "background" : "inactive"
    local.writingCaptures?[context.key]?.phase(kind, at: Date().timeIntervalSince1970)
    persist()
  }
  func writingReceipt(for key: String) -> WritingReceipt? {
    guard recordsWriting, var capture = local.writingCaptures?[key], !capture.receipt.events.isEmpty else { return nil }
    capture.phase("submit", at: Date().timeIntervalSince1970)
    return capture.receipt
  }
  func retireWriting(_ key: String) {
    local.writingCaptures?.removeValue(forKey: key)
    if activeWritingContext?.key == key { activeWritingContext = nil }
  }
  func queueWriting(_ receipt: WritingReceipt?, attemptID: String) {
    guard recordsWriting, let receipt else { return }
    var queue = local.pendingWriting ?? []
    guard !queue.contains(where: { $0.receipt.session_id == receipt.session_id }) else { return }
    queue.append(PendingWritingReceipt(attempt_id: attemptID, receipt: receipt))
    local.pendingWriting = Array(queue.suffix(60)); persist()
  }
  func syncWriting() async {
    guard recordsWriting, !testing, !writingSyncing, let account = session else { return }
    writingSyncing = true
    defer { writingSyncing = false }
    let client = API(token: account.token)
    for pending in local.pendingWriting ?? [] {
      guard session?.token == account.token else { return }
      do {
        let data = try JSONEncoder().encode(pending.receipt)
        let body = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let _: Empty = try await client.send("/attempts/" + pending.attempt_id + "/writing-activity", body: body)
        guard session?.token == account.token else { return }
        local.pendingWriting?.removeAll { $0.receipt.session_id == pending.receipt.session_id }; persist()
      } catch {
        // Activity delivery never blocks an answer or changes a grade.
        guard session?.token == account.token else { return }
        let error = error as NSError
        if error.domain == "Sabbo", [403, 404, 422].contains(error.code) {
          local.pendingWriting?.removeAll { $0.receipt.session_id == pending.receipt.session_id }; persist()
        } else { return }
      }
    }
  }
}

struct WritingPrivacyView: View {
  var body: some View {
    Form {
      Section("Skriveaktivitet") {
        Text("Når du skriver svar i daglige økter og bonusrunder, registrerer Sabbo omtrentlige skriveperioder, antall ord og tegn, avbrudd når appen blir inaktiv, og forsøk på å lime inn tekst.")
        Text("Etter at du leverer, deles en aktivitetsoversikt med \(ClientProfile.ownerName). Oversikten er bare tilgjengelig for \(ClientProfile.ownerName) og brukes ikke til å beregne karakterer, stjerner eller streak.")
        Text("Sabbo registrerer ikke innhold fra andre apper, hvilke apper eller nettsider du åpner, eller en logg over tastetrykk. Et avbrudd kan også skyldes låst skjerm eller et systemvarsel. Tidene er omtrentlige, og frakoblet bruk kan gi mangler.")
        Text("Aktivitetsoversikten slettes fra tjenesten etter 30 dager. Hvis du sletter historikken din, slettes også skriveaktiviteten. Opplysningene samles bare i Sabbo mens du arbeider med svarene.")
      }
    }.navigationTitle("Personvern").accessibilityIdentifier("writing-privacy")
  }
}

struct WritingActivityView: View {
  @EnvironmentObject var model: AppModel
  let attemptID: String
  let question: Question
  @State private var report: WritingReport?
  @State private var error: String?
  private var authorized: Bool { model.session?.user_id == ClientProfile.ownerID }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        if authorized {
          Text("Skriveaktivitet").font(.title2.bold())
          Text("Omtrentlige observasjoner fra Sabbo. Avbrudd viser ikke hvilken app som ble åpnet eller hvorfor. Manglende data er ikke det samme som ingen aktivitet.")
            .font(.subheadline).foregroundStyle(.secondary)
          if let report {
            Text("Mottatt: " + StudyText.timestamp(report.submitted_at)).font(.subheadline)
            if report.sessions.isEmpty {
              Text(report.expired ? "Aktivitetsoversikten er utløpt etter 30 dager." : "Ingen skriveaktivitet er mottatt. Besvarelsen kan være fra en eldre app, eller aktiviteten kan vente på synkronisering.")
                .accessibilityIdentifier("writing-empty")
            }
            ForEach(report.sessions, id: \.session_id) { receipt in
              session(receipt)
            }
          } else if let error {
            Text(error); Button("Prøv igjen") { Task { await load() } }
          } else { ProgressView("Henter aktivitet …") }
        }
      }.padding(22).frame(maxWidth: 760).frame(maxWidth: .infinity, alignment: .leading)
    }.navigationTitle("Skriveaktivitet").navigationBarTitleDisplayMode(.inline)
      .task(id: model.session?.user_id) { report = nil; await load() }
      .refreshable { await load() }
      .accessibilityIdentifier("writing-report")
  }
  @ViewBuilder private func session(_ receipt: WritingReceipt) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(receipt.platform == "MAC_OS" ? "Mac" : "iPhone / iPad").font(.headline)
      let seconds = Int(receipt.events.last?.writing_seconds ?? 0)
      let duration = seconds < 60 ? "\(seconds) s" : "\(seconds / 60) min \(seconds % 60) s"
      Text("Omtrent \(duration) aktiv skriving · \(receipt.events.filter { $0.kind == "inactive" }.count) avbrudd · \(receipt.events.filter { $0.kind == "paste" }.count) blokkerte innliminger")
        .font(.subheadline).accessibilityIdentifier("writing-summary")
      Text("Skrivetid teller korte mellomrom mellom tekstendringer, ikke all tid med appen åpen.")
        .font(.caption).foregroundStyle(.secondary)
      if receipt.truncated { Text("Lang økt: noen eldre observasjoner er utelatt.").font(.caption) }
      ForEach(Array(receipt.events.enumerated()), id: \.offset) { _, event in
        VStack(alignment: .leading, spacing: 4) {
          Text(Date(timeIntervalSince1970: event.at), format: .dateTime.day().month().hour().minute().second())
            .font(.caption).foregroundStyle(.secondary)
          Text(label(event)).font(.subheadline)
        }.frame(maxWidth: .infinity, alignment: .leading)
      }
    }.padding(18).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
  }
  private func label(_ event: WritingEvent) -> String {
    let parts = question.parts ?? [question]
    let number = (parts.firstIndex(where: { $0.id == event.question_id }) ?? 0) + 1
    switch event.kind {
    case "inactive": return "Sabbo ble inaktiv"
    case "background": return "Sabbo gikk i bakgrunnen"
    case "active": return "Tilbake i Sabbo"
    case "close": return "Forlot svarfeltet · oppgave \(number): \(event.words) ord"
    case "paste": return "Innliming blokkert · oppgave \(number)"
    case "submit": return "Levering startet · oppgave \(number): \(event.words) ord"
    default: return "Oppgave \(number): \(event.words) ord · \(event.characters) tegn"
    }
  }
  private func load() async {
    guard authorized, let account = model.session else { return }
    error = nil
    #if DEBUG
    if model.testing {
      report = WritingReport(attempt_id: attemptID, submitted_at: "2026-10-20T10:00:00Z", expired: false,
        sessions: [WritingReceipt(events: [
          WritingEvent(at: 1792489800, kind: "write", question_id: question.parts?.first?.id ?? question.id, words: 12, characters: 74, writing_seconds: 35),
          WritingEvent(at: 1792489860, kind: "inactive", question_id: question.parts?.first?.id ?? question.id, words: 30, characters: 180, writing_seconds: 65),
          WritingEvent(at: 1792489880, kind: "active", question_id: question.parts?.first?.id ?? question.id, words: 30, characters: 180, writing_seconds: 65),
          WritingEvent(at: 1792489900, kind: "submit", question_id: question.parts?.first?.id ?? question.id, words: 40, characters: 240, writing_seconds: 80)])])
      return
    }
    #endif
    do {
      let value: WritingReport = try await API(token: account.token).get("/attempts/" + attemptID + "/writing-activity")
      if model.session?.token == account.token { report = value }
    } catch {
      if model.session?.token == account.token { self.error = StudyText.failure(error, action: "Hent skriveaktivitet") }
    }
  }
}
