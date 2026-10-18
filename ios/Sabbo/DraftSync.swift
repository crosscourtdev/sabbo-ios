import Foundation
import SwiftUI

struct DraftSync: Codable {
  var revision = 0
  var base = ""
  var conflict: String?
  var backups: [String] = []

  static func equal(_ a: String, _ b: String) -> Bool {
    if a == b { return true }
    guard let ad = a.data(using: .utf8), let bd = b.data(using: .utf8),
      let av = try? JSONDecoder().decode([String: String].self, from: ad),
      let bv = try? JSONDecoder().decode([String: String].self, from: bd) else { return false }
    return av == bv
  }
  mutating func keep(_ body: String) {
    guard !body.isEmpty, !backups.contains(where: { Self.equal($0, body) }) else { return }
    backups.append(body)
  }
  mutating func receive(_ remote: Draft?, local: String) -> String {
    let server = remote?.body ?? ""
    let version = remote?.revision ?? 0
    guard version >= revision else { return local } // Ignore an older in-flight read.
    if Self.equal(local, server) || Self.equal(local, base) {
      base = server; revision = version; conflict = nil
      return server
    }
    if Self.equal(server, base) { revision = version; return local }
    // Both devices edited. Retain both verbatim; never choose by clock time.
    keep(local); keep(server)
    base = server; revision = version; conflict = server
    return local
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
      state.conflict = nil
      local.draftSync = (local.draftSync ?? [:]).merging([day.id: state]) { _, new in new }
      return
    }
    let body = local.drafts[day.id] ?? ""
    local.drafts[day.id] = state.receive(day.draft, local: body)
    local.draftSync = (local.draftSync ?? [:]).merging([day.id: state]) { _, new in new }
    editor = local.drafts[day.id] ?? ""
    persist()
  }

  func syncCurrentDraft() async {
    guard !testing, !draftSyncing, let account = session, let id = local.today?.id,
          !hasSubmitted else { return }
    draftSyncing = true
    defer { draftSyncing = false }
    let client = API(token: account.token)
    do {
      let day: Today = try await client.get("/assignments/" + id)
      guard session?.token == account.token, local.today?.id == id else { return }
      local.today = day
      reconcileDraft(day)
      guard day.attempt == nil else { await refresh(); return }
      guard var state = local.draftSync?[id] else { return }
      guard state.conflict == nil else { draftStatus = "To utkast – velg versjon"; return }
      let body = local.drafts[id] ?? ""
      guard !DraftSync.equal(body, state.base) else { draftStatus = "Synkronisert"; return }
      draftStatus = "Lagrer …"
      let result: DraftSave = try await client.send("/assignments/" + id + "/draft", method: "PUT",
        body: ["body": body, "base_revision": state.revision])
      guard session?.token == account.token, local.today?.id == id else { return }
      if result.submitted { await refresh(); return }
      if result.saved, let draft = result.draft {
        state.base = draft.body; state.revision = draft.revision ?? 0; state.conflict = nil
        local.draftSync?[id] = state
        draftStatus = DraftSync.equal(local.drafts[id] ?? "", state.base) ? "Synkronisert" : "Lagrer …"
      } else if result.conflict {
        local.drafts[id] = state.receive(result.draft, local: local.drafts[id] ?? "")
        local.draftSync?[id] = state
        draftStatus = "To utkast – velg versjon"
      }
      persist()
    } catch {
      if session?.token == account.token { draftStatus = "Lagret på enheten · venter på nett" }
    }
  }

  func resolveDraft(_ id: String, body: String) {
    guard var state = local.draftSync?[id] else { return }
    state.keep(local.drafts[id] ?? ""); state.keep(state.base)
    state.conflict = nil
    local.draftSync?[id] = state
    local.drafts[id] = body
    editor = body
    persist()
    scheduleDraftSync()
  }
}

struct DraftVersionsView: View {
  @EnvironmentObject var model: AppModel
  @Environment(\.dismiss) private var dismiss
  let day: Today
  var body: some View {
    List {
      if let state = model.local.draftSync?[day.id] {
        if let remote = state.conflict {
          Section("Begge utkastene er bevart") {
            Text("Svaret ble endret på begge enhetene. Velg utkastet du vil fortsette med.")
          }
          version("Denne enheten", model.local.drafts[day.id] ?? "")
          version("Den andre enheten", remote)
        }
        ForEach(Array(state.backups.enumerated().reversed()), id: \.offset) { index, body in
          version("Lagret utkast \(index + 1)", body)
        }
      }
    }.navigationTitle("Utkast")
      .toolbar { Button("Lukk") { dismiss() } }
  }
  @ViewBuilder private func version(_ title: String, _ body: String) -> some View {
    Section(title) {
      let values = AnswerSet.decode(body)
      if let parts = day.question.parts {
        ForEach(Array(parts.enumerated()), id: \.element.id) { index, part in
          VStack(alignment: .leading, spacing: 6) {
            Text("Oppgave \(index + 1)").font(.headline)
            Text(values[part.id] ?? "–")
          }
        }
      } else { Text(body) }
      Button("Fortsett med dette utkastet") { model.resolveDraft(day.id, body: body); dismiss() }
        .disabled(day.attempt != nil || model.local.pending.contains { $0.assignment.id == day.id && $0.mode == "daily" })
    }
  }
}
