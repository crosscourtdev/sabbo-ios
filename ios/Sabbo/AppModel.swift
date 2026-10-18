import Foundation
import SwiftUI
import UIKit
import UserNotifications

@MainActor final class AppModel: ObservableObject {
  @Published var bonusClock = Date()
  @Published var showBonus = false
  @Published var bonusPresentationID = UUID()
  func openBonus() { bonusPresentationID = UUID(); showBonus = true }
  @Published var reward: RewardPresentation?
  @Published var selectedTab = "today"
  @Published var sharedAssignmentID: String?
  var ownProgress: PersonProgress? { local.progress?.people.first { $0.id == session?.user_id } }
  var ownStreak: Streak? { ownProgress?.streak ?? local.today?.streaks.first { $0.user_id == session?.user_id } }
  private func rewardSeenKey(_ value: StreakReward) -> String {
    let base = "sabbo.rewards.seen." + (session?.user_id ?? "signed-out")
    let epoch = value.isStar ? ownProgress?.stars.epoch ?? "" : ownStreak?.epoch ?? ""
    return value.kind == "fire" && epoch.isEmpty ? base : base + "." + value.kind + "." + epoch
  }
  func rewardValue(_ value: StreakReward) -> Int { value.isStar ? ownProgress?.stars.total ?? 0 : ownStreak?.best ?? 0 }
  var unopenedRewards: [RewardPresentation] {
    guard session != nil else { return [] }
    return (StreakReward.milestones + StreakReward.starMilestones).compactMap { value in
      let seen = UserDefaults.standard.array(forKey: rewardSeenKey(value)) as? [Int] ?? []
      return rewardValue(value) >= value.threshold && !seen.contains(value.day)
        ? RewardPresentation(reward: value, access: .earned) : nil
    }
  }
  func openReward(_ value: StreakReward) {
    reward = value.presentation(userID: session?.user_id, best: rewardValue(value))
  }
  func rewardShown(_ presentation: RewardPresentation) {
    let value = presentation.reward
    guard session != nil, presentation.access == .earned, rewardValue(value) >= value.threshold else { return }
    let key = rewardSeenKey(value)
    var seen = UserDefaults.standard.array(forKey: key) as? [Int] ?? []
    if !seen.contains(value.day) { seen.append(value.day); UserDefaults.standard.set(seen, forKey: key) }
  }
  func collectGain(_ key: String) -> Bool {
    let accountKey = "sabbo.gains." + (session?.user_id ?? "signed-out")
    var seen = UserDefaults.standard.stringArray(forKey: accountKey) ?? []
    guard !seen.contains(key) else { return false }
    seen.append(key)
    UserDefaults.standard.set(Array(seen.suffix(200)), forKey: accountKey)
    return true
  }
  func refreshProgress() async {
    guard !testing, session != nil else { return }
    let account = session?.user_id
    do {
      let progress: PairProgress = try await api.get("/progress")
      guard session?.user_id == account else { return }
      local.progress = progress
      await refreshBonus()
      persist()
    } catch { /* Cached counters remain visible offline. */ }
  }
  func resetProgress(target: String, track: String) async {
    guard session?.user_id == ClientProfile.ownerID else { return }
    do {
      try await syncPending()
      let progress: PairProgress = try await api.send("/admin/progress/reset", body: ["target": target, "track": track, "request_id": UUID().uuidString])
      local.progress = progress
      reward = nil
      persist()
      await refresh()
      message = "Fremdriften er nullstilt. Svar og karakterer er beholdt."
    } catch { message = "Kunne ikke nullstille. Oppdater og prøv igjen." }
  }
  @Published var session: Session? {
    didSet {
      if oldValue?.token != session?.token {
        reminderTask?.cancel(); reminderTask = nil; reminderTaskID = nil
        reminderRevision = 0; savedReminderRevision = 0
        reminderSaving = false; reminderSaveError = nil
        reminderEnabled = false; streakReminderEnabled = true; peerNotificationsEnabled = true; bonusNotificationsEnabled = true
        reminderTime = StudyText.reminderDate(hour: 19, minute: 0)
      }
    }
  }
  @Published var local = LocalState()
  @Published var busy = false
  @Published var message: String?
  @Published var editor = ""
  @Published var me: Me?
  @Published var comparison: Comparison?
  @Published var permission = ""
  @Published var evaluations: [String: Evaluation] = [:]
  private var pendingSync: Task<Void, Error>?
  var currentAttemptID: String? { pending?.attempt_id ?? local.today?.attempt?.id }
  var canPractice: Bool { complete || local.history.contains { $0.mode == "daily" && $0.assessment != nil } }
  @Published var reminderEnabled = false
  @Published var streakReminderEnabled = false
  @Published var peerNotificationsEnabled = true
  @Published var bonusNotificationsEnabled = true
  @Published var reminderTime =
    StudyText.reminderDate(hour: 19, minute: 0)
  @Published var reminderSaving = false
  @Published var reminderSaveError: String?
  private var reminderRevision = 0
  private var savedReminderRevision = 0
  private var reminderTask: Task<Void, Never>?
  private var reminderTaskID: UUID?
  private var saveTask: Task<Void, Never>?
  private var syncing = false
  var draftSyncing = false
  @Published var draftStatus = ""
  private var editGeneration = 0
  let login = SignIn()
  var api: API { API(token: session?.token) }
  var pending: Pending? {
    local.pending.first { $0.mode == "daily" && $0.assignment.id == local.today?.assignment.id }
  }
  var feedback: Feedback? {
    guard let aid = local.today?.assignment.id else { return nil }
    return local.feedback[aid]
  }
  var hasSubmitted: Bool { local.today?.attempt != nil || pending != nil }
  var complete: Bool { local.today?.attempt?.completed_at != nil || pending?.assessment != nil }
  var userName: String { ownStreak?.name ?? (session?.user_id == "reviewer" ? "Testbruker" : session?.user_id == ClientProfile.learnerID ? ClientProfile.learnerName : ClientProfile.ownerName) }
  init() {
    session = Vault.read().flatMap { try? JSONDecoder().decode(Session.self, from: $0) }
    restore()
    installTestFixture()
  }
  func file() -> URL? {
    guard let user = session?.user_id else { return nil }
    let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Sabbo", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var excluded = folder
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? excluded.setResourceValues(values)
    return folder.appendingPathComponent(user + ".json")
  }
  func restore() {
    if let f = file(), let data = try? Data(contentsOf: f),
      let state = try? JSONDecoder().decode(LocalState.self, from: data)
    {
      local = state
      editor = state.today.flatMap { state.drafts[$0.assignment.id] } ?? ""
    }
  }
  @discardableResult func persist() -> Bool {
    guard let f = file() else { return false }
    do {
      try JSONEncoder().encode(local).write(
        to: f, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
      return true
    } catch {
      message = "Kunne ikke lagre på enheten. Behold appen åpen og prøv igjen."
      return false
    }
  }
  func signIn() async {
    busy = true
    defer { busy = false }
    do {
      session = try await login.login(api: API())
      local = LocalState()
      restore()
      await refresh()
    } catch { message = error.localizedDescription }
  }
  func signInReview(username: String, password: String) async {
    busy = true
    defer { busy = false }
    do {
      let saved: Session = try await API().send("/auth/review", body: ["username": username, "password": password])
      try Vault.save(JSONEncoder().encode(saved))
      session = saved
      local = LocalState()
      restore()
      await refresh()
    } catch { message = error.localizedDescription }
  }
  func edit(_ value: String) {
    editor = value
    editGeneration += 1
    guard let aid = local.today?.assignment.id else { return }
    if local.drafts[aid + ".started"] == nil {
      local.drafts[aid + ".started"] = ISO8601DateFormatter().string(from: Date())
    }
    local.drafts[aid] = value
    persist()  // synchronous durable write before network/debounce
    scheduleDraftSync()
  }
  func scheduleDraftSync() {
    saveTask?.cancel()
    saveTask = Task {
      try? await Task.sleep(for: .milliseconds(650))
      guard !Task.isCancelled else { return }
      await syncCurrentDraft()
    }
  }
  func refresh() async {
    if testing { return }
    guard let refreshAccount = session, !syncing else { return }
    syncing = true
    defer { syncing = false }
    do { try await syncPending() } catch {
      message = syncFailureMessage(error)
    }
    do {
      let generation = editGeneration
      let today: Today = try await API(token: refreshAccount.token).get("/today")
      guard session?.token == refreshAccount.token else { return }
      if let old = local.today, old.assignment.id != today.assignment.id,
        !local.saved_days.contains(where: { $0.assignment.id == old.assignment.id })
      {
        local.saved_days.append(old)
      }
      local.today = today
      reconcileDraft(today)
      if generation == editGeneration { editor = local.drafts[today.id] ?? "" }
      await syncCurrentDraft()
      let reminderVersion = reminderRevision
      let remindersWereSaved = reminderRevision == savedReminderRevision
      me = try await api.get("/me")
      if remindersWereSaved && reminderVersion == reminderRevision && reminderRevision == savedReminderRevision {
        reminderEnabled = me?.enabled == 1
        streakReminderEnabled = me?.streak_reminder == 1
        peerNotificationsEnabled = me?.peer_notifications == 1
        bonusNotificationsEnabled = me?.bonus_notifications != 0
        if let time = me?.reminder {
          let bits = time.split(separator: ":").compactMap { Int($0) }
          if bits.count == 2 {
            reminderTime =
              StudyText.reminderDate(hour: bits[0], minute: bits[1])
          }
        }
      }
      local.subjects = try await api.get("/subjects")
      local.history = try await api.get("/history")
      if today.attempt != nil {
        let f: Feedback = try await api.get("/assignments/" + today.assignment.id + "/feedback")
        local.feedback[today.assignment.id] = f
      }
      comparison = try await api.get("/assignments/" + today.assignment.id + "/comparison")
      persist()
      await refreshProgress()
      await registerDevice()
    } catch {
      if (error as? URLError)?.code == .userAuthenticationRequired {
        persist()
        Vault.clear()
        session = nil
        message = "Logg inn igjen. Svarene dine blir liggende på enheten."
      } else {
        message = StudyText.failure(error, action: "Oppdater")
      }
    }
    await permissionStatus()
  }
  func bundledFeedback(_ q: Question) -> Feedback? {
    if let answer = q.example_answer, let points = q.key_points, let guidance = q.guidance {
      return Feedback(parts: q.parts, key_points: points, example_answer: answer, guidance: guidance)
    }
    guard let url = Bundle.main.url(forResource: "questions.v1", withExtension: "json"),
      let data = try? Data(contentsOf: url),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let rows = json["questions"] as? [[String: Any]],
      let row = rows.first(where: {
        $0["id"] as? String == q.id && $0["version"] as? Int == q.version
      }),
      let decoded = try? JSONSerialization.data(withJSONObject: row)
    else { return nil }
    return try? JSONDecoder().decode(Feedback.self, from: decoded)
  }
  func help() async {
    guard let t = local.today else { return }
    // Assistance is persisted locally and reconciled before the attempt.
    if let f = bundledFeedback(t.question) {
      local.feedback[t.assignment.id] = f
      local.drafts[t.assignment.id + ".assisted"] = "yes"
      persist()
    }
    if testing { return }
    do {
      let f: Feedback = try await api.send(
        "/assignments/" + t.assignment.id + "/guidance", body: [:])
      local.feedback[t.assignment.id] = f
      persist()
    } catch { message = "Veiledningen er tilgjengelig. Skriv en kort forklaring med egne ord." }
  }
  @discardableResult
  func submit(
    mode: String = "daily", assignment: Assignment? = nil, question: Question? = nil,
    answer: String? = nil
  ) async -> Pending? {
    guard let a = assignment ?? local.today?.assignment, let q = question ?? local.today?.question
    else { return nil }
    let text = answer ?? editor
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      message = "Skriv et svar med egne ord."
      return nil
    }
    if mode == "daily" && a.id == local.today?.assignment.id && hasSubmitted { return nil }
    if q.parts != nil && !AnswerSet.complete(q, text) {
      message = "Svar på alle deloppgavene før du leverer økten."
      return nil
    }
    if mode == "daily", local.draftSync?[a.id]?.conflict != nil {
      message = "Velg hvilket utkast du vil levere først."; return nil
    }
    if mode == "daily", a.id == local.today?.id {
      await syncCurrentDraft()
      guard local.draftSync?[a.id]?.conflict == nil, !hasSubmitted,
            DraftSync.equal(text, local.drafts[a.id] ?? text) else {
        message = "Utkastet er oppdatert. Se over svarene før du leverer."; return nil
      }
    }
    let p = Pending(
      id: UUID().uuidString, assignment: a, question: q, answer: text,
      assisted: local.drafts[a.id + ".assisted"] == "yes", mode: mode,
      started_at: local.drafts[a.id + ".started"] ?? ISO8601DateFormatter().string(from: Date()),
      assessment: q.parts == nil ? nil : "completed", attempt_id: nil)
    local.pending.append(p)
    guard persist() else {
      local.pending.removeAll { $0.id == p.id }
      return nil
    }
    if mode == "daily" { await clearReminders(for: a.id) }
    if let f = bundledFeedback(q) { local.feedback[a.id] = f }
    saveTask?.cancel()
    do {
      try await syncPending()
      await refresh()
    } catch { message = syncFailureMessage(error) }
    return local.pending.first(where: { $0.id == p.id }) ?? p
  }
  func assess(_ value: String, pendingID: String? = nil) async {
    if let i = local.pending.firstIndex(where: {
      $0.id == pendingID || pendingID == nil && $0.id == pending?.id
    }) {
      local.pending[i].assessment = value
      persist()
    } else if pendingID == nil, let id = local.today?.attempt?.id {
      do {
        let _: Attempt = try await api.send(
          "/attempts/" + id + "/assessment", body: ["value": value])
      } catch {  // persist assessment against known attempt as a replayable workflow
        if let t = local.today, let a = t.attempt {
          local.pending.append(
            Pending(
              id: UUID().uuidString, assignment: t.assignment, question: t.question,
              answer: a.answer, assisted: a.assisted == 1, mode: "daily", started_at: "",
              assessment: value, attempt_id: a.id))
          persist()
        }
      }
    }
    do { try await syncPending() } catch {
      message = "Fullført på enheten. Synkroniseres senere; streak bekreftes av serveren."
    }
    await refresh()
  }
  private func syncFailureMessage(_ error: Error) -> String {
    let value = error as NSError
    if value.domain == "Sabbo" {
      return "Svaret er lagret på enheten. " + value.localizedDescription
    }
    if (error as? URLError)?.code == .userAuthenticationRequired {
      return "Logg inn igjen for å synkronisere. Svaret er lagret på enheten."
    }
    return "Svaret er lagret på enheten. " + StudyText.failure(error, action: "Synkroniser")
  }
  func syncPending() async throws {
    if testing { return }
    if let pendingSync { try await pendingSync.value; return }
    let task = Task { try await self.performPendingSync() }
    pendingSync = task
    defer { pendingSync = nil }
    try await task.value
  }
  private func performPendingSync() async throws {
    var failure: Error?
    for r in local.revisions {
      do {
        let _: Empty = try await api.send(
          "/attempts/" + r.attempt_id + "/revisions", body: ["answer": r.answer, "key": r.id])
        local.revisions.removeAll { $0.id == r.id }
        local.drafts.removeValue(forKey: "revision-" + r.attempt_id)
        persist()
      } catch { failure = error }
    }
    for p in local.pending {
      do {
        var id = p.attempt_id
        if id == nil {
          if p.assisted {
            let _: Feedback = try await api.send(
              "/assignments/" + p.assignment.id + "/guidance", body: [:])
          }
          let a: Attempt = try await api.send(
            "/assignments/" + p.assignment.id + "/attempts",
            body: [
              "answer": p.answer, "key": p.id, "mode": p.mode, "client_started_at": p.started_at,
            ])
          id = a.id
          if let i = local.pending.firstIndex(where: { $0.id == p.id }) {
            local.pending[i].attempt_id = id
            persist()
          }
        }
        if let assessment = p.assessment, let id {
          let _: Attempt = try await api.send(
            "/attempts/" + id + "/assessment", body: ["value": assessment])
        }
        if p.assessment != nil {
          local.pending.removeAll { $0.id == p.id }
          local.drafts.removeValue(forKey: p.mode == "optional" ? "practice-" + p.assignment.id : p.assignment.id)
          persist()
        }
      } catch {
        // Another device may have submitted while this one was offline.
        // Keep its answer locally and converge on the accepted daily attempt.
        let value = error as NSError
        if p.mode == "daily", value.domain == "Sabbo", value.code == 422,
           let day: Today = try? await api.get("/assignments/" + p.assignment.id), let accepted = day.attempt {
          var state = local.draftSync?[day.id] ?? DraftSync()
          state.keep(p.answer); state.conflict = nil
          local.draftSync = (local.draftSync ?? [:]).merging([day.id: state]) { _, new in new }
          if let i = local.pending.firstIndex(where: { $0.id == p.id }) { local.pending[i].attempt_id = accepted.id }
          persist()
          do {
            if let assessment = p.assessment {
              let _: Attempt = try await api.send("/attempts/" + accepted.id + "/assessment", body: ["value": assessment])
              local.pending.removeAll { $0.id == p.id }
              if local.today?.id == day.id { local.today = day }
              persist()
            }
          } catch { failure = error }
        } else { failure = error }
      }
    }
    if let failure { throw failure }
  }
  func revise(_ item: HistoryItem, text: String) async throws {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    local.revisions.append(
      PendingRevision(id: UUID().uuidString, attempt_id: item.id, answer: text))
    persist()
    do {
      try await syncPending()
      await refresh()
    } catch { message = "Revisjonen er lagret på enheten og sendes senere." }
  }
  func assessHistory(_ item: HistoryItem, _ value: String) async {
    do {
      let _: Attempt = try await api.send(
        "/attempts/" + item.id + "/assessment", body: ["value": value])
      await refresh()
    } catch { message = StudyText.failure(error, action: "Lagre gjennomgangen") }
  }
  func unlock(_ subject: Subject) async {
    do {
      let _: Empty = try await api.send(
        "/subjects/" + subject.id, method: "PUT", body: ["enabled": subject.enabled != 1])
      await refresh()
    } catch { message = error.localizedDescription }
  }
  private func clearReminders(for assignmentID: String) async {
    let center = UNUserNotificationCenter.current()
    let delivered = await center.deliveredNotifications()
    center.removeDeliveredNotifications(withIdentifiers: delivered.filter {
      $0.request.content.userInfo["assignment_id"] as? String == assignmentID
        && $0.request.content.userInfo["destination"] as? String != "together"
    }.map { $0.request.identifier })
  }
  func permissionStatus() async {
    let settings = await UNUserNotificationCenter.current().notificationSettings()
    switch settings.authorizationStatus {
    case .authorized, .provisional, .ephemeral: permission = "Tillatt"
    case .denied: permission = "Ikke tillatt"
    default: permission = "Ikke valgt"
    }
  }
  // One worker serializes changes. A refresh cannot overwrite an unsaved choice.
  func reminderChanged() {
    reminderRevision += 1
    reminderSaveError = nil
    saveReminderChanges()
  }
  func saveReminderChanges() {
    guard reminderTask == nil, let account = session else { return }
    let taskID = UUID()
    reminderTaskID = taskID
    reminderSaving = true
    reminderSaveError = nil
    reminderTask = Task {
      defer {
        if reminderTaskID == taskID { reminderTask = nil; reminderSaving = false }
      }
      while session?.token == account.token && reminderRevision != savedReminderRevision {
        let beforeDelay = reminderRevision
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled, session?.token == account.token else { return }
        if beforeDelay != reminderRevision { continue }
        let revision = reminderRevision
        var enabled = reminderEnabled
        let streak = streakReminderEnabled
        var peer = peerNotificationsEnabled
        var bonus = bonusNotificationsEnabled
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nb_NO"); formatter.timeZone = StudyText.oslo
        formatter.dateFormat = "HH:mm"
        let time = formatter.string(from: reminderTime)
        do {
          if enabled || peer || bonus {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            guard session?.token == account.token else { return }
            if !granted {
              enabled = false; peer = false; bonus = false
              if revision == reminderRevision { reminderEnabled = false; peerNotificationsEnabled = false; bonusNotificationsEnabled = false }
            } else { UIApplication.shared.registerForRemoteNotifications() }
          }
          guard session?.token == account.token else { return }
          let _: Empty = try await API(token: account.token).send("/reminder", method: "PUT",
            body: ["enabled": enabled, "time": time, "streak_reminder": streak, "peer_notifications": peer, "bonus_notifications": bonus])
          guard session?.token == account.token else { return }
          savedReminderRevision = revision
          await permissionStatus()
          await registerDevice()
        } catch {
          guard session?.token == account.token else { return }
          if revision != reminderRevision { continue }
          reminderSaveError = StudyText.failure(error, action: "Lagre påminnelsene")
          return
        }
      }
    }
  }
  func registerDevice() async {
    guard let token = UserDefaults.standard.string(forKey: "apns-token"), session != nil else {
      return
    }
    let environment =
      Bundle.main.object(forInfoDictionaryKey: "APNsEnvironment") as? String ?? "sandbox"
    do {
      let _: Empty = try await api.send(
        "/device", method: "PUT", body: ["token": token, "environment": environment, "peer_notifications": true, "bonus_notifications": true])
    } catch {}
  }
  func signOut() async {
    if reminderRevision != savedReminderRevision {
      saveReminderChanges()
      await reminderTask?.value
      guard reminderRevision == savedReminderRevision else {
        message = "Lagre påminnelsene før du logger ut."; return
      }
    }
    guard local.pending.isEmpty && local.revisions.isEmpty else {
      message = "Synkroniser svarene dine før du logger ut."
      return
    }
    do {
      saveTask?.cancel()
      await syncCurrentDraft()
      if let id = local.today?.id, let state = local.draftSync?[id],
         state.conflict != nil || !DraftSync.equal(local.drafts[id] ?? "", state.base) {
        message = "Synkroniser utkastet før du logger ut."; return
      }
      if let token = UserDefaults.standard.string(forKey: "apns-token") {
        let _: Empty = try await api.request("/device/" + token, method: "DELETE")
      }
      let _: Empty = try await api.request("/session", method: "DELETE")
    } catch {
      message = StudyText.failure(error, action: "Logg ut")
      return
    }
    saveTask?.cancel()
    evaluations = [:]
    Vault.clear()
    session = nil
    local = LocalState()
    editor = ""
    me = nil
  }
  func savedEvaluation(_ id: String) -> Evaluation? {
    let saved = local.history.first { $0.id == id }?.evaluations?.last
    if let saved, saved.result != nil { return saved }
    return evaluations[id] ?? saved
  }
  func resultFeedback(_ question: Question, assignmentID: String) -> Feedback? {
    if answersLocked(question) { return nil }
    if let cached = local.feedback[assignmentID], !cached.example_answer.isEmpty { return cached }
    return bundledFeedback(question)
  }
  func watchEvaluation(_ id: String) async -> String? {
    guard !testing else { return nil }
    if savedEvaluation(id)?.result != nil { await refreshProgress(); return nil }
    let account = session?.user_id
    var failures = 0
    for _ in 0..<60 {
      if Task.isCancelled || account != session?.user_id { return nil }
      do {
        let value: Evaluation = try await api.get("/attempts/" + id + "/evaluation")
        guard !Task.isCancelled, account == session?.user_id else { return nil }
        evaluations[id] = value
        failures = 0
        if let index = local.history.firstIndex(where: { $0.id == id }), value.result != nil {
          local.history[index].evaluations = [value]
          persist()
        }
        if !["queued", "processing"].contains(value.status) { await refreshProgress(); return nil }
      } catch {
        if Task.isCancelled || account != session?.user_id { return nil }
        failures += 1
        if failures >= 3 { return "Kunne ikke hente vurderingen. Svaret ditt er lagret." }
      }
      do { try await Task.sleep(for: .seconds(2)) } catch { return nil }
    }
    return "Vurderingen tar litt tid. Svaret ditt er lagret."
  }
  func resetDaily() async {
    guard session?.user_id == ClientProfile.ownerID, let old = local.today else { return }
    saveTask?.cancel()
    do {
      try await syncPending()
      let today: Today = try await api.send("/admin/daily/reset", body: ["assignment_id": old.id])
      local.pending.removeAll { $0.assignment.id == old.id && $0.mode == "daily" }
      for key in [old.id, old.id + ".started", old.id + ".assisted"] { local.drafts.removeValue(forKey: key) }
      local.today = today
      editor = ""
      comparison = nil
      persist()
      await refresh()
      message = "Dagens økt er nullstilt."
    } catch { message = StudyText.failure(error, action: "Nullstill dagens økt") }
  }
  func restartSchedule() async {
    guard session?.user_id == ClientProfile.ownerID, let old = local.today else { return }
    saveTask?.cancel()
    do {
      try await syncPending()
      let today: Today = try await api.send("/admin/schedule/restart", body: ["assignment_id": old.id])
      if today.id != old.id && !local.saved_days.contains(where: { $0.id == old.id }) {
        local.saved_days.append(old)
      }
      local.today = today
      editor = ""
      comparison = nil
      persist()
      await refresh()
      message = "\(ClientProfile.ownerName) og \(ClientProfile.learnerName) starter på dag 1 i dag."
    } catch {
      let value = error as NSError
      message = value.domain == "Sabbo" ? value.localizedDescription : "Kunne ikke starte oppgaverekken på nytt. Oppdater og prøv igjen."
    }
  }
}

extension AppModel {
  var bonusNow: Date { bonusClock.addingTimeInterval(local.bonus_clock_offset ?? 0) }
  var bonusStatus: String {
    guard let b = local.bonus else { return "none" }
    if ["won", "grading", "too_late", "collection_complete", "none"].contains(b.status) { return b.status }
    if let expires = BonusState.date(b.expires_at), bonusNow >= expires { return "expired" }
    if b.status == "waiting", let opens = BonusState.date(b.opens_at), bonusNow >= opens { return "ready" }
    return b.status
  }
  func answersLocked(_ question: Question) -> Bool {
    guard let b = local.bonus, b.question_id == question.id, b.question_version == question.version,
          b.target_grade != nil, b.attempt_id == nil,
          let opens = BonusState.date(b.opens_at), let expires = BonusState.date(b.expires_at) else { return false }
    return bonusNow >= opens && bonusNow < expires
  }
  func answersLocked(attemptID: String) -> Bool {
    if let h = local.history.first(where: { $0.id == attemptID }) { return answersLocked(h.question) }
    if local.today?.attempt?.id == attemptID, let q = local.today?.question { return answersLocked(q) }
    return false
  }
  func refreshBonus() async {
    guard !testing, let account = session?.user_id else { return }
    do {
      let bonus: BonusState = try await api.get("/bonus")
      let cosmetics: CosmeticCollection = try await api.get("/cosmetics")
      guard session?.user_id == account else { return }
      if let server = BonusState.date(bonus.server_now) { local.bonus_clock_offset = server.timeIntervalSinceNow }
      bonusClock = Date()
      local.bonus = bonus; local.cosmetics = cosmetics
      persist()
    } catch { /* Retain inventory and countdown offline; submissions are server checked. */ }
  }
  func equipCosmetic(_ id: String?) async -> Bool {
    guard let account = session?.user_id else { return false }
    do {
      let collection: CosmeticCollection = try await api.send("/cosmetics/equipped", method: "PUT", body: ["cosmetic_id": id as Any? ?? NSNull()])
      guard session?.user_id == account else { return false }
      local.cosmetics = collection; persist()
      return true
    } catch {
      if session?.user_id == account { message = StudyText.failure(error, action: "Bytt tilbehør") }
      return false
    }
  }
  func submitBonus(_ roundID: String, question: Question, answer: String) async -> Attempt? {
    guard let account = session?.user_id else { return nil }
    guard AnswerSet.complete(question, answer) else { message = "Svar på alle deloppgavene."; return nil }
    let previousAttemptID = local.bonus?.attempt_id
    let keyName = "bonus-key-" + roundID
    let key = local.drafts[keyName] ?? UUID().uuidString
    local.drafts[keyName] = key
    guard persist() else { return nil }
    do {
      let attempt: Attempt = try await api.send("/bonus/" + roundID + "/attempts", body: ["answer": answer, "key": key])
      guard session?.user_id == account else { return nil }
      local.drafts.removeValue(forKey: keyName)
      local.drafts.removeValue(forKey: "bonus-" + roundID)
      await refresh()
      return attempt
    } catch {
      guard session?.user_id == account else { return nil }
      await refresh()
      guard session?.user_id == account else { return nil }
      if let id = local.bonus?.attempt_id, id != previousAttemptID, local.bonus?.id == roundID,
         let accepted = local.history.first(where: { $0.id == id }) {
        local.drafts.removeValue(forKey: keyName)
        return Attempt(id: accepted.id, user_id: session?.user_id ?? "", assignment_id: accepted.assignment_id,
                       answer: accepted.answer, assessment: accepted.assessment, completed_at: accepted.submitted_at, assisted: accepted.assisted)
      }
      let errorValue = error as NSError
      message = errorValue.domain == "Sabbo" ? errorValue.localizedDescription : "Bonussvaret er lagret på enheten. Lever på nett før midnatt."
      return nil
    }
  }
}
