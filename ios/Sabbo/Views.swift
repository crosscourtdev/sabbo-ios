import SwiftUI
import UserNotifications

struct SabboRoot: View {
  @EnvironmentObject var model: AppModel
  @Environment(\.scenePhase) private var scenePhase
  @State private var question = false
  @State private var reviewLogin = false
  @State private var notificationDay: Today?
  var body: some View {
    Group {
      if model.session == nil {
        login
      } else {
        navigation
        .overlay(alignment: .top) { PeerDeliveredToast() }
        .sheet(isPresented: $question) { NavigationStack {
          if let day = model.local.today, day.question.parts != nil { GoalSessionView(day: day).id(day.id) }
          else { QuestionView() }
        }.desktopSheet() }
        .sheet(item: $notificationDay) { day in NavigationStack {
          if day.question.parts != nil { GoalSessionView(day: day).id(day.id) } else { SavedDraftView(saved: day) }
        }.desktopSheet() }
      }
    }
    .sheet(isPresented: $model.showBonus) { BonusRoundView().id(model.bonusPresentationID) }
    .sheet(isPresented: $reviewLogin) { ReviewLoginView() }
    .sheet(item: $model.reward) { reward in
      StreakRewardView(presentation: reward).onAppear { model.rewardShown(reward) }
    }
    .tint(Color("AccentColor"))
    .task {
      await model.refresh()
      resumeNotification()
    }
    .task(id: "\(model.currentAttemptID ?? ""):\(question):\(notificationDay?.id ?? "")") {
      if !question && notificationDay == nil, let id = model.currentAttemptID {
        _ = await model.watchEvaluation(id)
      }
    }
    .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
      if scenePhase == .active { Task { await model.syncCurrentDraft() } }
    }
    .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { now in
      model.bonusClock = now
      if scenePhase == .active { Task {
        let wasLocked = model.local.bonus?.status == "ready"
        await model.refreshBonus()
        let newDay = model.local.bonus?.day != nil && model.local.bonus?.day != model.local.today?.server_day
        if newDay || (wasLocked && model.local.bonus?.status != "ready") {
          // Restore cached answers and the current daily assignment at rollover,
          // including a bonus submitted on the account's other device.
          await model.refresh()
        }
      } }
    }
    .onChange(of: model.session?.user_id) { _, _ in model.reward = nil; resumeNotification() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        Task {
          await model.refresh()
          resumeNotification()
        }
      } else {
        model.persist()
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SabboPush"))) { _ in
      resumeNotification()
    }
    .alert(
      "Sabbo",
      isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })
    ) {
      Button("OK") { model.message = nil }
    } message: {
      Text(model.message ?? "")
    }
  }
  @ViewBuilder private var navigation: some View {
    #if targetEnvironment(macCatalyst)
    NavigationSplitView {
      List(selection: Binding<String?>(get: { model.selectedTab }, set: { if let value = $0 { model.selectedTab = value } })) {
        Label("I dag", systemImage: "house.fill").tag("today")
        Label("Fag", systemImage: "books.vertical").tag("subjects")
        Label("Sammen", systemImage: "person.2.fill").tag("together")
        Label("Innstillinger", systemImage: "slider.horizontal.3").tag("settings")
      }.navigationTitle("Sabbo")
    } detail: {
      NavigationStack {
        switch model.selectedTab {
        case "subjects": SubjectsView()
        case "together": TogetherView()
        case "settings": SettingsView()
        default: TodayView(open: { question = true })
        }
      }.id(model.selectedTab)
    }
    #else
        TabView(selection: $model.selectedTab) {
          NavigationStack { TodayView(open: { question = true }) }.tabItem {
            Label("I dag", systemImage: "house.fill")
          }.tag("today")
          NavigationStack { SubjectsView() }.tabItem { Label("Fag", systemImage: "books.vertical") }.tag("subjects")
          NavigationStack { TogetherView() }.tabItem { Label("Sammen", systemImage: "person.2.fill") }.tag("together")
          NavigationStack { SettingsView() }.tabItem {
            Label("Innstillinger", systemImage: "slider.horizontal.3")
          }.tag("settings")
        }
    #endif
  }
  private func resumeNotification() {
    guard model.session != nil,
      let aid = UserDefaults.standard.string(forKey: "notification-assignment")
    else { return }
    let target = UserDefaults.standard.string(forKey: "notification-destination")
    let recipient = UserDefaults.standard.string(forKey: "notification-recipient")
    guard recipient == nil || recipient == model.session?.user_id else {
      UserDefaults.standard.removeObject(forKey: "notification-assignment")
      return
    }
    Task {
      do {
        let day: Today = try await model.api.get("/assignments/" + aid)
        if target == "bonus" {
          await model.refreshBonus()
          model.selectedTab = "today"
          if model.local.bonus?.assignment_id == aid, ["ready", "retry", "grading", "won"].contains(model.bonusStatus) { model.openBonus() }
        } else if target == "together" || target == "peer" {
          question = false; notificationDay = nil
          model.sharedAssignmentID = aid; model.selectedTab = "together"
        } else if aid == model.local.today?.assignment.id { question = true }
        else { notificationDay = day }
        UserDefaults.standard.removeObject(forKey: "notification-assignment")
      } catch { model.message = StudyText.failure(error, action: "Åpne dagens økt") }
    }
  }
  private var login: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        PortraitMark(size: 150).padding(.top, 50)
        Text("Sabbo").font(.system(.largeTitle, design: .rounded, weight: .heavy))
        Text("Litt hver dag.\nLenger sammen.").font(.system(.largeTitle, design: .rounded, weight: .bold))
        Button { Task { await model.signIn() } } label: {
          HStack { Text("Kom i gang"); Spacer(); if model.busy { ProgressView() } else { Image(systemName: "arrow.right") } }
        }.buttonStyle(PlayButton()).disabled(model.busy)
        Text("Du forblir innlogget på denne enheten.").font(.footnote).foregroundStyle(.secondary)
        Button("Testkonto") { reviewLogin = true }.font(.footnote).disabled(model.busy)
      }.padding(28).frame(maxWidth: 540).frame(maxWidth: .infinity)
    }.background(Color(.systemGroupedBackground))
  }
}

struct ReviewLoginView: View {
  @EnvironmentObject var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @State private var username = ""
  @State private var password = ""
  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Brukernavn", text: $username).textContentType(.username)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
          SecureField("Passord", text: $password).textContentType(.password)
        } footer: { Text("En egen testkonto med eksempeldata.") }
        Button {
          Task {
            await model.signInReview(username: username, password: password)
            if model.session != nil { password = ""; dismiss() }
          }
        } label: {
          HStack { Text("Logg inn"); Spacer(); if model.busy { ProgressView() } }
        }.disabled(model.busy || username.isEmpty || password.isEmpty)
        if let message = model.message { Text(message).foregroundStyle(.red) }
      }.navigationTitle("Testkonto")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Avbryt") { dismiss() } } }
    }
  }
}

struct TodayView: View {
  @State private var cosmetics = false
  @EnvironmentObject var model: AppModel
  var open: () -> Void
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        if let t = model.local.today {
          HomeCounters(openWardrobe: { cosmetics = true })
          VStack(alignment: .leading, spacing: 20) {
            HStack {
              SubjectPill(id: t.question.subject_id)
              Spacer()
              Text((t.question.parts?.count ?? 1) == 1 ? "1 oppgave" : "\(t.question.parts?.count ?? 1) oppgaver").font(.caption.bold()).foregroundStyle(.secondary)
            }
            Text(t.question.title ?? "Dagens utfordring")
              .font(.system(.title, design: .rounded, weight: .bold))
            if !model.hasSubmitted {
              Text(t.question.prompt).font(.body).lineLimit(4).foregroundStyle(.secondary)
            }
            if let id = model.currentAttemptID {
              Text(StudyText.evaluation(model.savedEvaluation(id)))
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(Color("AccentColor"))
            }
            if let id = model.currentAttemptID { QuestGainsView(attemptID: id) }
            AchievementCelebration()
            if model.hasSubmitted, ["ready", "retry", "grading_failed"].contains(model.bonusStatus) {
              Divider()
              BonusStage()
              Button("Se dagens resultat", action: open).font(.subheadline.bold()).frame(minHeight: 44).accessibilityIdentifier("start-question")
            } else {
            Button(action: open) {
              HStack {
                Text(model.hasSubmitted ? (model.bonusStatus == "won" ? "Se resultater" : "Se resultat") : !model.editor.isEmpty || !(model.local.drafts[t.id] ?? "").isEmpty ? "Fortsett økten" : "Start økten")
                Spacer()
                Image(systemName: model.complete ? "checkmark" : "arrow.right")
              }
            }.buttonStyle(PlayButton()).transaction { $0.animation = nil }.accessibilityIdentifier("start-question")
            if model.hasSubmitted, model.bonusStatus != "none" { Divider(); BonusStage(showAction: false) }
            }
            if !model.hasSubmitted {
              Text("Lever før kl. 20 for å få en bonusrunde").font(.caption).foregroundStyle(.secondary)
            }
            if !model.local.pending.isEmpty {
              Label("Ikke levert ennå", systemImage: "icloud.and.arrow.up").font(.caption).foregroundStyle(.secondary)
            }
          }.padding(22).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 28))
          ProgressPanel()
          AchievementPreview()

        } else {
          ContentUnavailableView("Dagens økt", systemImage: "books.vertical", description: Text("Oppdater for å hente oppgavene."))
          Button("Prøv igjen") { Task { await model.refresh() } }.buttonStyle(PlayButton())
        }
      }.padding(22).frame(maxWidth: 620)
        .frame(maxWidth: .infinity)
    }.sheet(isPresented: $cosmetics) { CosmeticPicker() }
      .background(Color(.systemGroupedBackground))
      .toolbar(.hidden, for: .navigationBar).refreshable { await model.refresh() }
  }

}
struct QuestionView: View {
  @EnvironmentObject var model: AppModel
  @Environment(\.dismiss) var dismiss
  @State private var working = false
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        if let t = model.local.today {
          SessionSteps(step: model.complete ? 2 : model.hasSubmitted ? 1 : 0)
          if model.complete { VictoryView(provisional: model.pending != nil) }
          if !model.hasSubmitted { StudyVisual(question: t.question, assignmentID: t.assignment.id) }
          QuestionPrompt(question: t.question).font(.system(.title2, design: .rounded, weight: .bold)).fixedSize(horizontal: false, vertical: true)
          QuestionMaterials(question: t.question)
          goalDisclosure(t.question)
          if model.hasSubmitted {
            DisclosureGroup("Ditt svar") {
              Text(model.pending?.answer ?? t.attempt?.answer ?? "").frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8).textSelection(.enabled)
            }.font(.subheadline)
            if let id = model.currentAttemptID { EvaluationCard(attemptID: id) }
            if let feedback = model.feedback { FeedbackView(feedback: feedback) }
            if !model.complete {
              Text("Hvordan gikk det?").font(.system(.headline, design: .rounded))
              VStack(spacing: 12) {
                Button("Dette forsto jeg") { Task { await model.assess("understood") } }.buttonStyle(PlayButton())
                Button("Jeg trenger mer øving") { Task { await model.assess("needs_practice") } }
                  .buttonStyle(.bordered).controlSize(.large).frame(maxWidth: .infinity)
              }
            } else {
              Button("Ferdig") { dismiss() }.buttonStyle(PlayButton())
            }
            if let compare = model.comparison, compare.revealed {
              DisclosureGroup("Se begge svarene") {
                ForEach(compare.answers) { answer in
                  VStack(alignment: .leading, spacing: 8) {
                    PlayerLabel(userID: answer.user_id, name: answer.author)
                    Text(answer.original)
                    ForEach(answer.revisions) { revision in
                      Text("Tidligere versjon: " + revision.answer).font(.subheadline).foregroundStyle(.secondary)
                    }
                  }.padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
                }
              }.font(.subheadline)
            }
          } else {
            AnswerEditor(text: Binding(get: { model.editor }, set: { model.edit($0) }), blocked: { model.message = "Skriv svaret med egne ord." })
              .frame(minHeight: 270).accessibilityIdentifier("answer-editor-wrapper")
            Button {
              working = true
              Task { await model.submit(); working = false }
            } label: {
              HStack { Text("Lever svar"); Spacer(); if working { ProgressView() } else { Image(systemName: "arrow.right") } }
            }.buttonStyle(PlayButton()).disabled(working || model.editor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
              .accessibilityIdentifier("submit-answer")
            Button("Jeg vet ikke ennå") { Task { await model.help() } }.frame(minHeight: 44)
            if let feedback = model.feedback {
              Text(feedback.guidance).font(.subheadline)
              FeedbackView(feedback: feedback)
            }
          }
        }
      }.padding(22).frame(maxWidth: 620).frame(maxWidth: .infinity)
    }.scrollDismissesKeyboard(.interactively).background(Color(.systemGroupedBackground))
      .navigationTitle(model.local.today.map { StudyText.subject($0.question.subject_id) } ?? "Dagens økt")
      .navigationBarTitleDisplayMode(.inline).toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Lukk", systemImage: "xmark") { model.persist(); dismiss() } }
      }
  }
  @ViewBuilder func goalDisclosure(_ q: Question) -> some View {
    if let subject = model.local.subjects.first(where: { $0.id == q.subject_id }) {
      DisclosureGroup("Kompetansemål") {
        ForEach(subject.goals.filter { q.goal_ids.contains($0.id) }) { goal in Text(goal.wording).padding(.vertical, 6) }
        if let url = URL(string: subject.source_url) { Link("Læreplan hos Udir", destination: url) }
      }.font(.caption).foregroundStyle(.secondary)
    }
  }
}
struct FeedbackView: View {
  let feedback: Feedback
  var body: some View {
    if let parts = feedback.parts {
      ForEach(Array(parts.enumerated()), id: \.element.id) { index, part in
        DisclosureGroup("Oppgave \(index + 1) · \(part.title ?? "Eksempelsvar")") {
          VStack(alignment: .leading, spacing: 12) {
            Text("Eksempelsvar").font(.subheadline.bold())
            Text(part.example_answer ?? "")
            ForEach(part.key_points ?? [], id: \.self) { Label($0, systemImage: "checkmark").font(.subheadline) }
          }.padding(.top, 12)
        }.padding(18).background(Color("AccentColor").opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
      }
    } else {
      DisclosureGroup("Et mulig svar") {
        VStack(alignment: .leading, spacing: 14) {
          Text(feedback.example_answer).fixedSize(horizontal: false, vertical: true)
          ForEach(feedback.key_points, id: \.self) { Label($0, systemImage: "checkmark").font(.subheadline) }
        }.padding(.top, 12)
      }.font(.subheadline).padding(18).background(Color("AccentColor").opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
    }
  }
}
struct SubjectsView: View {
  @EnvironmentObject var model: AppModel
  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        ForEach(model.local.subjects) { subject in
          NavigationLink { SubjectPathView(subject: subject) } label: {
            VStack(alignment: .leading, spacing: 14) {
              HStack {
                Image(systemName: SabboStyle.symbol(subject.id)).foregroundStyle(SabboStyle.subject(subject.id))
                  .accessibilityHidden(true)
                Spacer()
                Image(systemName: subject.enabled == 1 ? "chevron.right" : "lock.fill").foregroundStyle(.secondary)
              }
              Text(subject.name).font(.system(.title3, design: .rounded, weight: .bold)).foregroundStyle(.primary)
              if subject.content_ready {
                let practiced = subject.goals.reduce(0) { $0 + ($1.practiced_count ?? 0) }
                let total = subject.goals.reduce(0) { $0 + ($1.question_count ?? 0) }
                ProgressView(value: Double(practiced), total: Double(max(1, total))).tint(SabboStyle.subject(subject.id))
                Text("\(practiced) av \(total) spørsmål øvd").font(.caption).foregroundStyle(.secondary)
              } else { Text("Kommer senere").font(.caption).foregroundStyle(.secondary) }
            }.padding(22).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
          }.buttonStyle(.plain)
        }
      }.padding(22).frame(maxWidth: 620).frame(maxWidth: .infinity)
    }.background(Color(.systemGroupedBackground)).navigationTitle("Din læringssti")
  }
}
struct SubjectPathView: View {
  let subject: Subject
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        if !subject.content_ready { Text("Oppgavene kommer senere.").foregroundStyle(.secondary).padding(.bottom, 20) }
        ForEach(subject.goals) { goal in
          HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 0) {
              ZStack {
                Circle().fill(goal.covered == true ? SabboStyle.mint : Color(.secondarySystemGroupedBackground))
                if goal.needs_practice == true { Image(systemName: "arrow.clockwise").foregroundStyle(SabboStyle.forest) }
                else { Text("\(goal.order)").font(.system(.title3, design: .rounded, weight: .heavy)).foregroundStyle(goal.covered == true ? SabboStyle.forest : .primary) }
              }.frame(width: 50, height: 50)
              Rectangle().fill(Color(.separator)).frame(width: 2).frame(maxHeight: .infinity)
            }
            VStack(alignment: .leading, spacing: 10) {
              Text(goal.wording).font(.body).fixedSize(horizontal: false, vertical: true)
              if let count = goal.question_count, count > 0 {
                Label("\(goal.practiced_count ?? 0)/\(count) øvd", systemImage: goal.needs_practice == true ? "arrow.clockwise" : "checkmark.circle")
                  .font(.caption).foregroundStyle(.secondary)
              }
            }.padding(.bottom, 28).frame(maxWidth: .infinity, alignment: .leading)
          }.fixedSize(horizontal: false, vertical: true)
        }
        if let url = URL(string: subject.source_url) { Link("Offisiell læreplan", destination: url).font(.footnote).padding(.top, 12) }
      }.padding(22).frame(maxWidth: 620).frame(maxWidth: .infinity)
    }.background(Color(.systemGroupedBackground)).navigationTitle(subject.name)
  }
}
struct SettingsView: View {
  @EnvironmentObject var model: AppModel
  @AppStorage(SabboFX.soundKey) private var sound = true
  @AppStorage(SabboFX.hapticsKey) private var haptics = true
  private func reminderBinding<Value>(_ keyPath: ReferenceWritableKeyPath<AppModel, Value>) -> Binding<Value> {
    Binding(get: { model[keyPath: keyPath] }, set: { model[keyPath: keyPath] = $0; model.reminderChanged() })
  }
  var body: some View {
    Form {
      Section {
        Toggle("Daglig påminnelse", isOn: reminderBinding(\.reminderEnabled))
        if model.reminderEnabled {
          DatePicker("Tidspunkt", selection: reminderBinding(\.reminderTime), displayedComponents: .hourAndMinute)
            .environment(\.locale, Locale(identifier: "nb_NO"))
            .environment(\.timeZone, StudyText.oslo)
          Toggle("Streak-påminnelse kl. 21", isOn: reminderBinding(\.streakReminderEnabled))
        }
        Toggle("Når den andre har levert", isOn: reminderBinding(\.peerNotificationsEnabled))
        Toggle("Når bonusrunden er klar", isOn: reminderBinding(\.bonusNotificationsEnabled))
        if model.reminderSaving { ProgressView("Lagrer …") }
        if let error = model.reminderSaveError {
          Text(error).font(.footnote).foregroundStyle(.secondary)
          Button("Prøv igjen") { model.saveReminderChanges() }
        }
        if model.permission == "Ikke tillatt" {
          Button("Tillat varsler i iPhone-innstillinger") {
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
          }
        }
      } header: { Text("Varsler") } footer: {
        if model.reminderEnabled { Text("Tidspunktene følger norsk tid.") }
      }
      Section {
        Toggle("Lydeffekter", isOn: $sound).accessibilityIdentifier("fx-sound")
        #if !targetEnvironment(macCatalyst)
        Toggle("Vibrasjon", isOn: $haptics).accessibilityIdentifier("fx-haptics")
        #endif
      } header: { Text("Lyd og vibrasjon") } footer: {
        #if targetEnvironment(macCatalyst)
        Text("Korte lyder når du leverer, får karakter og åpner belønninger. De blandes med annen lyd.")
        #else
        Text("Korte lyder når du leverer, får karakter og åpner belønninger. De følger lydløsbryteren og blandes med annen lyd.")
        #endif
      }
      .onChange(of: sound) { _, on in if on { SabboFX.shared.play(.step) } }
      .onChange(of: haptics) { _, on in if on { SabboFX.shared.haptic(.success) } }
      if [ClientProfile.ownerID, "reviewer"].contains(model.session?.user_id ?? "") {
        Section { NavigationLink("Administrasjon") { AdministrationView() } }
      }
      Section {
        PlayerLabel(userID: model.session?.user_id ?? "", name: model.userName)
        NavigationLink("Mine data") { AccountDataView() }
        Button("Logg ut") { Task { await model.signOut() } }
      }
    }.navigationTitle("Innstillinger")
      .task { await model.permissionStatus() }
  }
}

struct AdministrationView: View {
  @EnvironmentObject var model: AppModel
  @State private var resetting = false
  @State private var resetBusy = false
  @State private var restartingSchedule = false
  var body: some View {
    Form {
      if [ClientProfile.ownerID, "reviewer"].contains(model.session?.user_id ?? "") {
        Section("Redaktør") { NavigationLink("Oppgavebibliotek") { QuestionLibraryView() } }
        Section("Neste fag") {
          ForEach(model.local.subjects.filter { ["psyc", "samf"].contains($0.id) }) { s in
            Button {
              Task { await model.unlock(s) }
            } label: {
              HStack {
                Text(s.name)
                Spacer()
                Text(s.enabled == 1 ? "Lås" : "Åpne")
              }
            }
          }
          Text("Tas med når oppgavene er klare.").font(.caption).foregroundStyle(.secondary)
        }
      }
      if model.session?.user_id == ClientProfile.ownerID {
        Section("Felles oppgaverekke") {
          Button("Start fra dag 1 for alle") { restartingSchedule = true }
            .disabled(resetBusy || model.local.today == nil)
            .accessibilityIdentifier("restart-shared-schedule")
        }
        Section("Nullstilling") {
          NavigationLink("Stjerner og flammer") { ProgressResetView() }

          Button("Nullstill dagens økt") { resetting = true }
            .disabled(resetBusy || model.local.today == nil)
            .accessibilityIdentifier("reset-daily")
        }
      }
    }.navigationTitle("Administrasjon")
      .confirmationDialog("Starte fra dag 1 for alle?", isPresented: $restartingSchedule, titleVisibility: .visible) {
        Button("Start fra dag 1", role: .destructive) {
          resetBusy = true
          Task { await model.restartSchedule(); resetBusy = false }
        }
      } message: {
        Text("\(ClientProfile.ownerName) og \(ClientProfile.learnerName) får dag 1 i dag. Tidligere svar, karakterer og dager på rad beholdes.")
      }
      .confirmationDialog("Nullstille dagens økt?", isPresented: $resetting, titleVisibility: .visible) {
        Button("Nullstill dagens økt", role: .destructive) {
          resetBusy = true
          Task { await model.resetDaily(); resetBusy = false }
        }
      } message: {
        Text("Du får en ny start på dagens oppgaver. Lever igjen for å forlenge streaken i dag. Tidligere svar beholdes i historikken. Økten til \(ClientProfile.learnerName) påvirkes ikke.")
      }
  }
}

struct AccountDataView: View {
  @EnvironmentObject var model: AppModel
  @State private var exportURL: URL?
  @State private var deleting = false
  var body: some View {
    Form {
      Section {
        Button("Eksporter lokale utkast") {
          do {
            guard let source = model.file() else { return }
            let data = try LocalRecovery.export(source)
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("sabbo-local-recovery.json")
            try data.write(to: file, options: [.atomic, .completeFileProtection])
            exportURL = file
          } catch { model.message = "Kunne ikke eksportere lokale utkast. Originalene er beholdt." }
        }.accessibilityIdentifier("export-local-drafts")
        Button("Eksporter innleverte svar") {
          Task {
            do {
              let data: Data = try await exportData()
              let file = FileManager.default.temporaryDirectory.appendingPathComponent(
                "sabbo-history.json")
              try data.write(to: file, options: [.atomic, .completeFileProtection])
              exportURL = file
            } catch { model.message = StudyText.failure(error, action: "Eksporter svarene") }
          }
        }
        if let exportURL { ShareLink("Del eksport", item: exportURL) }
        Button("Slett mine studiedata", role: .destructive) { deleting = true }
      }
    }.navigationTitle("Mine data")
      .confirmationDialog(
        "Slette svarhistorikken, stjernene og streaken din?", isPresented: $deleting,
        titleVisibility: .visible
      ) {
        Button("Slett mine data", role: .destructive) {
          Task {
            do {
              let _: Empty = try await model.api.request("/history", method: "DELETE")
              if let f = model.file() {
                try? FileManager.default.removeItem(at: f)
                try? FileManager.default.removeItem(at: LocalRecovery.snapshotURL(for: f))
              }
              Vault.clear()
              model.session = nil
              model.local = LocalState()
              model.editor = ""
            } catch { model.message = StudyText.failure(error, action: "Slett studiedataene") }
          }
        }
      } message: {
        Text("Studieparets oppgaver og den andre personens data beholdes. Dette kan ikke angres.")
      }
  }
  func exportData() async throws -> Data {
    var r = URLRequest(url: model.api.base.appendingPathComponent("history/export"))
    r.setValue("Bearer " + (model.session?.token ?? ""), forHTTPHeaderField: "Authorization")
    let (data, response) = try await URLSession.shared.data(for: r)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
      throw URLError(.badServerResponse)
    }
    return data
  }
}
struct SavedDraftView: View {
  @EnvironmentObject var model: AppModel
  let saved: Today
  @State private var text = ""
  @State private var working = false
  var p: Pending? {
    model.local.pending.first { $0.assignment.id == saved.assignment.id && $0.mode == "daily" }
  }
  var body: some View {
    if saved.question.parts != nil { GoalSessionView(day: saved) }
    else { legacyBody }
  }
  var legacyBody: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text(StudyText.day(saved.assignment.day)).font(.caption).foregroundStyle(.secondary)
        QuestionPrompt(question: saved.question).font(.title2)
        QuestionMaterials(question: saved.question)
        Text("Sene svar lagres, men teller ikke med i streaken.").font(
          .footnote
        ).foregroundStyle(.secondary)
        if let completed = model.local.history.first(where: {
          $0.assignment_id == saved.assignment.id && $0.mode == "daily"
        }) {
          Text(completed.answer)
          if let f = model.bundledFeedback(completed.question) { FeedbackView(feedback: f) }
          if completed.assessment == nil {
            Button("Dette forsto jeg") {
              Task { await model.assessHistory(completed, "understood") }
            }.buttonStyle(.borderedProminent)
            Button("Jeg trenger mer øving") {
              Task { await model.assessHistory(completed, "needs_practice") }
            }.buttonStyle(.bordered)
          } else {
            Label("Økten er fullført", systemImage: "checkmark.circle")
          }
        } else if let p {
          Text(p.answer)
          if let f = model.bundledFeedback(saved.question) { FeedbackView(feedback: f) }
          if p.assessment == nil {
            Button("Dette forsto jeg") {
              Task { await model.assess("understood", pendingID: p.id) }
            }.buttonStyle(.borderedProminent)
            Button("Jeg trenger mer øving") {
              Task { await model.assess("needs_practice", pendingID: p.id) }
            }.buttonStyle(.bordered)
          }
        } else {
          AnswerEditor(text: $text, blocked: { model.message = "Skriv svaret med egne ord." })
            .frame(height: 280)
          Button("Lever svar") {
            working = true
            Task {
              await model.submit(
                mode: "daily", assignment: saved.assignment, question: saved.question, answer: text)
              working = false
            }
          }.buttonStyle(.borderedProminent).disabled(
            working || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }.padding(24)
    }.navigationTitle("Tidligere økt").onAppear {
      text = model.local.drafts[saved.assignment.id] ?? ""
    }.onChange(of: text) { _, value in
      model.local.drafts[saved.assignment.id] = value
      model.persist()
    }
  }
}
