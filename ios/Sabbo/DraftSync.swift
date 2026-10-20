import Foundation
import SwiftUI

struct DraftWrite: Codable {
  var id = UUID().uuidString
  let revision: Int
  let body: String
}

struct DraftSync: Codable {
  var revision = 0
  var base = ""
  var conflict: String?
  var backups: [String] = []
  var conflictKeys: [String]?
  var write: DraftWrite?

  static func parts(_ body: String) -> [String: String] {
    if body.isEmpty { return [:] }
    if let data = body.data(using: .utf8),
       let value = try? JSONDecoder().decode([String: String].self, from: data) { return value }
    return ["": body]
  }
  static func encode(_ parts: [String: String]) -> String {
    if parts.isEmpty { return "" }
    if let plain = parts[""], parts.count == 1 { return plain }
    let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
    return String(data: (try? encoder.encode(parts)) ?? Data("{}".utf8), encoding: .utf8) ?? "{}"
  }
  static func equal(_ a: String, _ b: String) -> Bool { parts(a) == parts(b) }
  mutating func keep(_ body: String) {
    guard !body.isEmpty, !backups.contains(where: { Self.equal($0, body) }) else { return }
    backups.append(body)
  }
  func unresolved(local: String) -> [String] {
    guard let conflict else { return [] }
    let l = Self.parts(local), r = Self.parts(conflict)
    return (conflictKeys ?? Array(Set(l.keys).union(r.keys)))
      .filter { l[$0] != r[$0] }.sorted()
  }
  mutating func receive(_ remote: Draft?, local: String) -> String {
    let server = remote?.body ?? "", version = remote?.revision ?? 0
    // An uncertain write must be acknowledged before interpreting server changes.
    guard write == nil, version >= revision else { return local }
    let b = Self.parts(base), l = Self.parts(local), r = Self.parts(server)
    let previous = Set(unresolved(local: local))
    var merged = l, conflicts: [String] = []
    for key in Set(b.keys).union(l.keys).union(r.keys) {
      if l[key] == r[key] { merged[key] = l[key] }
      else if previous.contains(key) { conflicts.append(key) }
      else if l[key] == b[key] { merged[key] = r[key] }
      else if r[key] != b[key] { conflicts.append(key) }
    }
    let result = Self.encode(merged)
    if !conflicts.isEmpty || !Self.equal(result, local) { keep(local); keep(server) }
    base = server; revision = version
    conflict = conflicts.isEmpty ? nil : server
    conflictKeys = conflicts.isEmpty ? nil : conflicts.sorted()
    return result
  }
  mutating func acknowledge(_ sent: DraftWrite, draft: Draft) {
    guard write?.id == sent.id else { return }
    if (draft.revision ?? 0) >= revision {
      base = draft.body; revision = draft.revision ?? 0
    }
    write = nil
  }
  mutating func choose(_ choices: [String: Bool], local: String) -> String {
    guard let remote = conflict else { return local }
    keep(local); keep(remote)
    var values = Self.parts(local)
    let other = Self.parts(remote)
    let keys = unresolved(local: local)
    for key in keys where choices[key] == true { values[key] = other[key] }
    let remaining = keys.filter { choices[$0] == nil }
    conflictKeys = remaining.isEmpty ? nil : remaining
    conflict = remaining.isEmpty ? nil : remote
    return Self.encode(values)
  }
}

struct DraftSave: Decodable {
  let saved: Bool
  let submitted: Bool
  let conflict: Bool
  let draft: Draft?
}

extension AppModel {
  func reconcileDraft(_ day: Today) {
    guard !local.pending.contains(where: { $0.assignment.id == day.id && $0.mode == "daily" }) else { return }
    var state = local.draftSync?[day.id] ?? DraftSync()
    if day.attempt != nil {
      if let body = local.drafts[day.id] { state.keep(body) }
      state.conflict = nil; state.conflictKeys = nil; state.write = nil
    } else {
      local.drafts[day.id] = state.receive(day.draft, local: local.drafts[day.id] ?? "")
    }
    local.draftSync = (local.draftSync ?? [:]).merging([day.id: state]) { _, new in new }
    if local.today?.id == day.id { editor = local.drafts[day.id] ?? "" }
    persist()
  }

  func syncCurrentDraft() async {
    guard let day = local.today else { return }
    await syncDraft(day)
  }

  func syncDraft(_ day: Today) async {
    guard !storageReadFailed, !testing, let account = session else { return }
    let key = account.user_id + ":" + day.id
    if let worker = draftWorkers[key] { await worker.value; return }
    // Unstructured task: cancelling a typing debounce must never cancel a save.
    let worker = Task { await self.performDraftSync(day, account: account) }
    draftWorkers[key] = worker
    await worker.value
    draftWorkers.removeValue(forKey: key)
  }

  private func performDraftSync(_ day: Today, account: Session) async {
    let id = day.id, client = draftAPIOverride ?? API(token: account.token)
    func status(_ value: String) { if local.today?.id == id { draftStatus = value } }
    do {
      // Coalesce edits made during a request; never run overlapping saves for a day.
      for _ in 0..<8 {
        guard session?.token == account.token, !storageReadFailed,
              !local.pending.contains(where: { $0.assignment.id == id && $0.mode == "daily" }) else { return }
        if let sent = local.draftSync?[id]?.write {
          let result: DraftSave = try await client.send("/assignments/" + id + "/draft", method: "PUT",
            body: ["body": sent.body, "base_revision": sent.revision, "mutation_id": sent.id])
          guard session?.token == account.token else { return }
          if result.submitted {
            let accepted: Today = try await client.get("/assignments/" + id)
            guard session?.token == account.token else { return }
            if local.today?.id == id { local.today = accepted }
            reconcileDraft(accepted); return
          }
          var state = local.draftSync?[id] ?? DraftSync()
          if result.saved, let draft = result.draft { state.acknowledge(sent, draft: draft) }
          else if result.conflict {
            state.write = nil
            local.drafts[id] = state.receive(result.draft, local: local.drafts[id] ?? sent.body)
          } else { throw URLError(.cannotParseResponse) }
          local.draftSync?[id] = state
          guard persist() else { return }
        }
        let fresh: Today = try await client.get("/assignments/" + id)
        guard session?.token == account.token else { return }
        if local.today?.id == id { local.today = fresh }
        reconcileDraft(fresh)
        guard fresh.attempt == nil, var state = local.draftSync?[id] else { return }
        guard state.conflict == nil else { status("Velg svar før levering"); return }
        let body = local.drafts[id] ?? ""
        guard !DraftSync.equal(body, state.base) else { status("Synkronisert"); return }
        state.write = DraftWrite(revision: state.revision, body: body)
        local.draftSync?[id] = state
        // Persist the exact request before sending, so relaunch can replay its receipt.
        guard persist() else { return }
        status("Lagrer …")
      }
    } catch {
      if session?.token == account.token {
        status((error as? URLError)?.code == .userAuthenticationRequired
          ? "Lagret på enheten · logg inn for å synkronisere" : "Lagret på enheten · prøver igjen")
      }
    }
  }

  func resolveDraft(_ id: String, body: String) {
    guard var state = local.draftSync?[id] else { return }
    state.keep(local.drafts[id] ?? ""); state.keep(state.base)
    state.conflict = nil; state.conflictKeys = nil
    local.draftSync?[id] = state; local.drafts[id] = body
    if local.today?.id == id { editor = body }
    persist()
  }
  func resolveAnswers(_ day: Today, choices: [String: Bool]) {
    guard var state = local.draftSync?[day.id] else { return }
    let body = state.choose(choices, local: local.drafts[day.id] ?? "")
    local.draftSync?[day.id] = state; local.drafts[day.id] = body
    if local.today?.id == day.id { editor = body }
    persist(); scheduleDraftSync(day: day)
  }
}

struct DraftVersionsView: View {
  @EnvironmentObject var model: AppModel
  @Environment(\.dismiss) private var dismiss
  let day: Today
  @State private var choices: [String: Bool] = [:]
  private var state: DraftSync { model.local.draftSync?[day.id] ?? DraftSync() }
  private var local: String { model.local.drafts[day.id] ?? "" }
  private var keys: [String] { state.unresolved(local: local) }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        if !keys.isEmpty {
          Text("Hvilket svar vil du levere?").font(.title2.bold())
          Text("Begge versjonene beholdes.").font(.subheadline).foregroundStyle(.secondary)
          ForEach(keys, id: \.self) { key in
            VStack(alignment: .leading, spacing: 12) {
              Text(title(key)).font(.headline)
              option("Svaret på denne enheten", key: key, other: false, body: DraftSync.parts(local)[key] ?? "")
              option("Den andre versjonen", key: key, other: true, body: DraftSync.parts(state.conflict ?? "")[key] ?? "")
            }
          }
        }
        if !state.backups.isEmpty {
          DisclosureGroup("Tidligere versjoner") {
            ForEach(Array(state.backups.enumerated().reversed()), id: \.offset) { index, body in
              DisclosureGroup("Lagret svar \(index + 1)") {
                AnswerReview(question: day.question, answer: body)
                if keys.isEmpty {
                  Button("Bruk denne versjonen") {
                    model.resolveDraft(day.id, body: body); model.scheduleDraftSync(day: day); dismiss()
                  }.disabled(day.attempt != nil || model.local.pending.contains { $0.assignment.id == day.id })
                }
              }.padding(.vertical, 8)
            }
          }
        }
      }.padding(22).frame(maxWidth: 620).frame(maxWidth: .infinity)
    }.safeAreaInset(edge: .bottom) {
      if !keys.isEmpty {
        Button("Se over valgte svar") {
          model.resolveAnswers(day, choices: choices); dismiss()
        }.buttonStyle(PlayButton()).disabled(keys.contains { choices[$0] == nil })
          .accessibilityIdentifier("confirm-draft-choices")
          .padding().background(.regularMaterial)
      }
    }.navigationTitle(keys.isEmpty ? "Tidligere svar" : "Velg svar")
      .toolbar { Button("Lukk") { dismiss() } }
      .onChange(of: state.conflict) { _, _ in choices = [:] }
  }
  private func title(_ key: String) -> String {
    guard let index = day.question.parts?.firstIndex(where: { $0.id == key }) else { return "Ditt svar" }
    return "Oppgave \(index + 1)"
  }
  private func option(_ title: String, key: String, other: Bool, body: String) -> some View {
    Button {
      choices[key] = other
    } label: {
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Image(systemName: choices[key] == other ? "checkmark.circle.fill" : "circle")
          Text(title).font(.headline)
        }
        Text(body.isEmpty ? "Tomt svar" : body).font(.body).multilineTextAlignment(.leading)
      }.foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading).padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(choices[key] == other ? Color.accentColor : .clear, lineWidth: 2))
    }.buttonStyle(.plain).accessibilityIdentifier("draft-choice-\(key)-\(other ? "remote" : "local")")
      .accessibilityAddTraits(choices[key] == other ? .isSelected : [])
  }
}
