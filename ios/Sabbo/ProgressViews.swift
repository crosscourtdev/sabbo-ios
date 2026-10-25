import SwiftUI

struct ProgressPanel: View {
  @EnvironmentObject var model: AppModel
  var body: some View {
    if model.ownStreak != nil || model.ownProgress?.stars != nil {
      VStack(alignment: .leading, spacing: 20) {
        if let streak = model.ownStreak {
          RewardTrack(value: streak.current, best: streak.best,
            label: streak.current == 1 ? "dag på rad" : "dager på rad", symbol: "flame.fill",
            color: SabboStyle.orange, rewards: StreakReward.milestones)
        }
      }.padding(20).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 26))
        .accessibilityIdentifier("reward-progress")
    }
  }
}

struct RewardTrack: View {
  @EnvironmentObject var model: AppModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let value: Int
  let best: Int
  let label: String
  let symbol: String
  let color: Color
  let rewards: [StreakReward]
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("Streak").font(.system(.title3, design: .rounded, weight: .bold))
        Spacer()
        if let next = rewards.first(where: { $0.threshold > best }) {
          Text("\(max(0, next.threshold - value)) dager til neste kiste").font(.caption).foregroundStyle(.secondary)
        } else {
          Text("Alle kistene er åpnet").font(.caption).foregroundStyle(.secondary)
        }
      }
      HStack(spacing: 8) {
        ForEach(Array(rewards.enumerated()), id: \.element.id) { index, reward in
          let previous = index == 0 ? 0 : rewards[index - 1].threshold
          let fraction = min(1, max(0, Double(value - previous) / Double(reward.threshold - previous)))
          let access = reward.presentation(userID: model.session?.user_id, best: best).access
          VStack(spacing: 8) {
            GeometryReader { geometry in
              ZStack(alignment: .leading) {
                Capsule().fill(Color(.tertiarySystemFill))
                Capsule().fill(color).frame(width: geometry.size.width * fraction)
              }
            }.frame(height: 6).accessibilityHidden(true)
            NavigationLink {
                let presentation = reward.presentation(userID: model.session?.user_id, best: model.rewardValue(reward))
                StreakRewardView(presentation: presentation).onAppear { model.rewardShown(presentation) }
              } label: {
              VStack(spacing: 4) {
                RewardIcon(reward: reward, unlocked: access == .earned, size: 48)
                Text(reward.isStar ? "\(reward.threshold) ★" : "Dag \(reward.threshold)")
                  .font(.system(.caption, design: .rounded, weight: .bold))
              }.frame(maxWidth: .infinity).contentShape(Rectangle())
            }.buttonStyle(.plain)
              .accessibilityLabel(reward.isStar ? "Stjernegave, \(reward.threshold) stjerner" : "Skattekiste, dag \(reward.threshold)")
              .accessibilityValue(access == .earned ? "Låst opp" : access == .preview ? "Forhåndsvis belønningen" : reward.lockedMessage)
              .accessibilityIdentifier("\(reward.kind)-reward-\(reward.threshold)")
          }
        }
      }
    }.animation(reduceMotion ? nil : .easeOut(duration: 0.6), value: value)
  }
}

struct QuestGainsView: View {
  @EnvironmentObject var model: AppModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let attemptID: String
  @State private var firePulse = 0
  @State private var starPulse = 0
  private var award: StarAward? { model.ownProgress?.stars.awards.first { $0.attempt_id == attemptID } }
  private var earnedFire: Bool { model.ownProgress?.fire_attempt_id == attemptID }
  private var key: String {
    "\(attemptID):\(model.ownProgress?.stars.epoch ?? ""): \(award?.stars ?? 0):\(model.ownStreak?.epoch ?? ""): \(earnedFire)"
  }
  var body: some View {
    if earnedFire || award != nil {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 16) { badges }
        VStack(alignment: .leading, spacing: 12) { badges }
      }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(SabboStyle.mint.opacity(0.5), in: RoundedRectangle(cornerRadius: 18))
      .task(id: key) {
        // Let a grade revealed alongside these gains land first.
        do { try await Task.sleep(for: .milliseconds(1400)) } catch { return }
        if earnedFire, model.collectGain("fire:\(model.ownStreak?.epoch ?? ""):\(attemptID)") {
          if !reduceMotion { firePulse += 1 }
          SabboFX.shared.play(.streak)
          SabboFX.shared.haptic(.success)
        }
        if let award, model.collectGain("stars:\(model.ownProgress?.stars.epoch ?? ""):\(award.id)") {
          if !reduceMotion { starPulse += 1 }
          for index in 0..<min(award.stars, 6) {
            let delay = (earnedFire ? 0.45 : 0) + Double(index) * 0.09
            SabboFX.shared.play(.star, after: delay)
            SabboFX.shared.haptic(.tick(0.4 + 0.08 * Double(index)), after: delay)
          }
        }
      }
    }
  }
  @ViewBuilder private var badges: some View {
    if earnedFire {
      GainBadge(symbol: "flame.fill", text: "+1 dag i streaken", detail: "", color: SabboStyle.orange, pulse: firePulse)
    }
    if let award {
      GainBadge(symbol: "star.fill", text: "+\(award.stars) stjerner", detail: "", color: .yellow, pulse: starPulse)
    }
  }
}

private struct GainBadge: View {
  let symbol: String
  let text: String
  let detail: String
  let color: Color
  let pulse: Int
  @State private var burst = false
  var body: some View {
    HStack(spacing: 12) {
      ZStack {
        ForEach(0..<5) { i in
          Image(systemName: symbol).font(.system(size: 10)).foregroundStyle(color)
            .offset(x: burst ? CGFloat(i - 2) * 12 : 0, y: burst ? -34 - CGFloat(i % 2) * 10 : 0)
            .opacity(burst ? 0 : 0.8)
        }.opacity(pulse > 0 ? 1 : 0)
        Image(systemName: symbol).font(.title2).foregroundStyle(color)
          .symbolEffect(.bounce, value: pulse)
      }.frame(width: 30)
      VStack(alignment: .leading, spacing: 3) {
        Text(text).font(.system(.headline, design: .rounded, weight: .bold))
        if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary) }
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .combine)
      .onChange(of: pulse) { _, value in
        if value > 0 { withAnimation(.easeOut(duration: 0.85)) { burst = true } }
      }
  }
}

struct TogetherView: View {
  @EnvironmentObject var model: AppModel
  @Environment(\.scenePhase) private var scenePhase
  @State private var sessions: [TimelineDay] = []
  @State private var loading = true
  @State private var selected: TimelineDay?
  @State private var filter = "both"
  @State private var subjectFilter = "all"
  @State private var search = ""
  @State private var error: String?
  private var ownID: String { model.session?.user_id ?? "" }
  private var peer: Streak? { model.local.today?.streaks.first { $0.user_id != ownID } }
  private var unfinished: [Today] {
    var days = model.local.missed_days ?? []
    for saved in model.local.saved_days where !days.contains(where: { $0.id == saved.id })
      && !(model.local.drafts[saved.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      days.append(saved)
    }
    return days.filter { day in
      day.id != model.local.today?.id
        && !model.local.history.contains { $0.assignment_id == day.id && $0.mode == "daily" }
        && !model.local.pending.contains { $0.assignment.id == day.id && $0.mode == "daily" }
        && (subjectFilter == "all" || day.question.subject_id == subjectFilter)
        && (search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          || (day.question.title ?? day.question.prompt).localizedStandardContains(search.trimmingCharacters(in: .whitespacesAndNewlines)))
    }.sorted { $0.assignment.day > $1.assignment.day }
  }
  private var visible: [TimelineDay] {
    // Own cached sessions also keep private resets and older history reachable offline.
    var days = sessions
    let cached = Dictionary(grouping: model.local.history, by: \.assignment_id)
    for (id, attempts) in cached where !days.contains(where: { $0.id == id }) {
      guard let item = attempts.first else { continue }
      days.append(TimelineDay(assignment: Assignment(id: id, day: item.day, timezone: "Europe/Oslo", question_id: item.question.id, version: item.question.version), question: item.question,
        people: [TimelinePerson(user_id: ownID, name: model.userName, attempts: attempts.sorted { $0.submitted_at < $1.submitted_at })]))
    }
    return days.filter { day in
      (filter == "both" || day.people.contains { $0.id == filter && !$0.attempts.isEmpty })
        && (subjectFilter == "all" || day.question.subject_id == subjectFilter)
        && (search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          || (day.question.title ?? day.question.prompt).localizedStandardContains(search.trimmingCharacters(in: .whitespacesAndNewlines)))
    }.sorted { $0.assignment.day == $1.assignment.day ? $0.id < $1.id : $0.assignment.day > $1.assignment.day }
  }
  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 18) {
        ViewThatFits(in: .horizontal) {
          HStack(spacing: 16) { profiles }
          VStack(alignment: .leading, spacing: 12) { profiles }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
          .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        Picker("Vis økter", selection: $filter) {
          Text("Begge").tag("both")
          Text("Meg").tag(ownID)
          if let peer { Text(peer.name).tag(peer.user_id) }
        }.pickerStyle(.segmented).accessibilityIdentifier("timeline-filter")
        HStack {
          Picker("Fag", selection: $subjectFilter) {
            Text("Alle fag").tag("all")
            ForEach(["pome", "reli", "psyc", "samf"], id: \.self) { Text(StudyText.subject($0)).tag($0) }
          }.accessibilityIdentifier("timeline-subject")
          Spacer()
          Text("\(visible.count) økter").font(.caption).foregroundStyle(.secondary)
        }
        if filter == "both" || filter == ownID { privateDrafts }
        if let error {
          Text(error).font(.caption).foregroundStyle(.secondary)
          Button("Prøv igjen") { Task { await load() } }
        }
        if loading && visible.isEmpty { ProgressView() }
        if !loading && visible.isEmpty && (unfinished.isEmpty || (filter != "both" && filter != ownID)) {
          ContentUnavailableView(search.isEmpty && subjectFilter == "all" ? "Ingen økter ennå" : "Ingen treff", systemImage: "magnifyingglass", description: Text(search.isEmpty && subjectFilter == "all" ? "Når dere leverer en økt, finner dere den her." : "Prøv et annet søk eller fag."))
        }
        ForEach(Array(visible.enumerated()), id: \.element.id) { index, day in
          if index == 0 || month(day) != month(visible[index - 1]) {
            Text(monthTitle(day)).font(.headline).padding(.top, 8)
          }
          NavigationLink {
            DayResultView(assignment: day.assignment, question: day.question, personID: filter == "both" ? nil : filter)
          } label: { row(day) }.buttonStyle(.plain).accessibilityIdentifier("timeline-day-" + day.id)
        }
      }.padding(22).frame(maxWidth: 620).frame(maxWidth: .infinity)
    }.background(Color(.systemGroupedBackground)).navigationTitle("Sammen")
      .searchable(text: $search, prompt: "Søk etter øktens tittel")
      .task { await load() }.refreshable { await model.refresh(); await load() }
      .onChange(of: model.sharedAssignmentID) { _, value in if value != nil { Task { await load() } } }
      .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await load() } } }
      .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
        if scenePhase == .active { Task { await load() } }
      }
      .navigationDestination(isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) {
        if let day = selected { DayResultView(assignment: day.assignment, question: day.question) }
      }
  }
  private func month(_ day: TimelineDay) -> String { String(day.assignment.day.prefix(7)) }
  private func monthTitle(_ day: TimelineDay) -> String {
    let input = DateFormatter(); input.locale = Locale(identifier: "en_US_POSIX"); input.dateFormat = "yyyy-MM-dd"
    let output = DateFormatter(); output.locale = Locale(identifier: "nb_NO"); output.dateFormat = "LLLL yyyy"
    return input.date(from: day.assignment.day).map { output.string(from: $0).capitalized } ?? month(day)
  }
  @ViewBuilder private var profiles: some View {
    ForEach(model.local.progress?.people ?? []) { person in
      HStack(spacing: 10) {
        PlayerAvatar(userID: person.id, size: 36)
        VStack(alignment: .leading, spacing: 4) {
          Text(person.streak.name).font(.subheadline.bold())
          HStack(spacing: 12) { counters(person) }.font(.caption)
        }
      }.fixedSize(horizontal: true, vertical: false).frame(maxWidth: .infinity, alignment: .leading)
    }
  }
  @ViewBuilder private func counters(_ person: PersonProgress) -> some View {
    Label("\(person.streak.current)", systemImage: "flame.fill").foregroundStyle(SabboStyle.orange)
      .accessibilityLabel("\(person.streak.current) dager på rad")
    Label("\(person.stars.total)", systemImage: "star.fill").foregroundStyle(.primary)
      .accessibilityLabel("\(person.stars.total) stjerner")
  }
  @ViewBuilder private var privateDrafts: some View {
    if !unfinished.isEmpty {
      DisclosureGroup {
        Text("Tidligere økter du ikke har levert. Du får karakter og tilbakemelding, men ingen stjerner eller dager på rad.")
          .font(.footnote).foregroundStyle(.secondary).padding(.vertical, 8)
        ForEach(unfinished) { saved in
          NavigationLink {
            CatchUpSessionView(saved: saved)
          } label: {
            HStack {
              VStack(alignment: .leading, spacing: 4) {
                Text(StudyText.day(saved.assignment.day) + " · " + StudyText.subject(saved.question.subject_id))
                  .font(.caption).foregroundStyle(.secondary)
                Text(saved.question.title ?? saved.question.prompt).font(.subheadline.bold()).foregroundStyle(.primary)
              }
              Spacer()
              Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }.frame(minHeight: 44).padding(.vertical, 6)
          }.accessibilityIdentifier("missed-day-" + saved.id)
        }
      } label: {
        Text("Ta igjen økter · \(unfinished.count)").accessibilityIdentifier("missed-sessions")
      }.font(.subheadline)
    }
    if model.local.pending.contains(where: { $0.attempt_id == nil }) {
      DisclosureGroup("Venter på nett") {
        ForEach(model.local.pending.filter { $0.attempt_id == nil }) { pending in
          DisclosureGroup(StudyText.day(pending.assignment.day) + " · Venter på nett") {
            AnswerReview(question: pending.question, answer: pending.answer)
          }.padding(.vertical, 8)
        }
      }.font(.subheadline)
    }
  }
  private func row(_ day: TimelineDay) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text(StudyText.day(day.assignment.day)).font(.caption).foregroundStyle(.secondary)
        Spacer()
        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
      }
      Text(StudyText.subject(day.question.subject_id)).font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
      Text(day.question.title ?? day.question.prompt).font(.system(.headline, design: .rounded)).foregroundStyle(.primary)
      ForEach(day.people.filter { filter == "both" || $0.id == filter }) { person in
        HStack(alignment: .top, spacing: 10) {
          PlayerAvatar(userID: person.id, size: 32)
          VStack(alignment: .leading, spacing: 4) {
            Text(person.id == ownID ? "Meg" : person.name).font(.subheadline.bold()).foregroundStyle(.primary)
            Text(person.daily.map { "Dagens økt · " + StudyText.evaluation($0.evaluations?.last) } ?? "Ikke levert ennå")
              .font(.caption).foregroundStyle(.secondary)
            if let latest = person.bonusAttempts.last {
              Text("Bonus · " + StudyText.evaluation(latest.evaluations?.last)).font(.caption).foregroundStyle(.secondary)
            } else if let b = person.bonus { Text(b.label).font(.caption).foregroundStyle(.secondary) }
          }
          Spacer(minLength: 0)
          if let id = person.bonus?.cosmetic_id { CosmeticItemImage(id: id, size: 36) }
        }
      }
    }.padding(18).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
  }
  private func load() async {
    if model.testing {
      if let id = model.local.today?.id, let day = model.presentationFixture(id) { sessions = [day] }
      loading = false; return
    }
    let account = ownID
    await model.refreshProgress()
    do {
      let feed: TimelineFeed = try await model.api.get("/timeline")
      guard account == ownID, !Task.isCancelled else { return }
      sessions = feed.sessions; error = nil
      if let missed = feed.missed { model.local.missed_days = missed; model.persist() }
      if let aid = model.sharedAssignmentID {
        selected = try await model.api.get("/timeline/" + aid)
        model.sharedAssignmentID = nil
      }
    } catch { self.error = "Kunne ikke oppdatere. Dine lagrede økter vises fortsatt." }
    loading = false
  }
}

/// Opening a past day restores its server draft without replacing today's task.
struct CatchUpSessionView: View {
  @EnvironmentObject var model: AppModel
  let saved: Today
  @State private var loaded: Today?
  @State private var failed = false
  var body: some View {
    Group {
      if let day = loaded {
        if day.question.parts != nil { GoalSessionView(day: day).id(day.id) }
        else { SavedDraftView(saved: day) }
      } else if failed {
        ContentUnavailableView {
          Label("Kunne ikke åpne økten", systemImage: "wifi.exclamationmark")
        } description: {
          Text("Koble til nettet for å hente oppgaven og eventuelle lagrede svar.")
        } actions: {
          Button("Prøv igjen") { Task { await load() } }
        }
      } else { ProgressView("Henter økten …") }
    }.task { await load() }
  }
  private func load() async {
    failed = false
    let account = model.session
    do {
      let day: Today
      if model.testing { day = saved }
      else { day = try await model.api.get("/assignments/" + saved.id) }
      guard account?.token == model.session?.token, !Task.isCancelled else { return }
      model.reconcileDraft(day)
      model.local.saved_days.removeAll { $0.id == day.id }
      model.local.saved_days.append(day)
      model.persist()
      loaded = day
    } catch {
      // Previously opened drafts remain usable offline. Never treat a feed-only
      // snapshot as a fetched draft: the server may hold work from another device.
      if let cached = model.local.saved_days.first(where: { $0.id == saved.id }) { loaded = cached }
      else { failed = true }
    }
  }
}

struct ProgressResetView: View {
  @EnvironmentObject var model: AppModel
  @State private var target = ClientProfile.ownerID
  @State private var track = "stars"
  @State private var confirm = false
  @State private var busy = false
  private var person: String { target == "both" ? ClientProfile.ownerName + " og " + ClientProfile.learnerName : target == ClientProfile.learnerID ? ClientProfile.learnerName : ClientProfile.ownerName }
  private var what: String { track == "both" ? "stjerner og flammer" : track == "stars" ? "stjerner" : "flammer" }
  var body: some View {
    Form {
      if model.session?.user_id == ClientProfile.ownerID {
        Section("Hvem") {
          Picker("Person", selection: $target) {
            Text(ClientProfile.ownerName).tag(ClientProfile.ownerID); Text(ClientProfile.learnerName).tag(ClientProfile.learnerID); Text("Begge").tag("both")
          }.pickerStyle(.segmented)
        }
        Section("Hva") {
          Picker("Nullstill", selection: $track) {
            Text("Stjerner").tag("stars"); Text("Flammer").tag("fire"); Text("Begge").tag("both")
          }.pickerStyle(.segmented)
          Text("Telleren og tilhørende belønninger starter på nytt. Svar og karakterer beholdes. Tidligere innleveringer gir ikke nye poeng etter nullstilling.")
            .font(.footnote).foregroundStyle(.secondary)
        }
        Section {
          Button("Nullstill \(what) for \(person)", role: .destructive) { confirm = true }.disabled(busy)
          if busy { ProgressView() }
        }
      }
    }.navigationTitle("Nullstill fremdrift")
      .confirmationDialog("Nullstille \(what) for \(person)?", isPresented: $confirm, titleVisibility: .visible) {
        Button("Nullstill", role: .destructive) {
          busy = true
          Task { await model.resetProgress(target: target, track: track); busy = false }
        }
      } message: { Text("Dette kan ikke angres. Svar, karakterer og oppgaverekkefølgen beholdes.") }
      .disabled(busy)
  }
}


/// Earned rewards are an invitation, never a chain of automatic sheets.
struct SessionRewardsView: View {
  @EnvironmentObject var model: AppModel
  @State private var opened: RewardPresentation?
  @State private var rewards: [RewardPresentation] = []
  var body: some View {
    VStack(spacing: 10) {
      ForEach(rewards) { reward in
        Button { opened = reward } label: {
          HStack(spacing: 14) {
            RewardIcon(reward: reward.reward, unlocked: true, size: 48)
            VStack(alignment: .leading, spacing: 4) {
              Text(reward.reward.isStar ? "Ny gave!" : "Ny kiste!").font(.headline)
              Text(reward.reward.unlockLabel).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("Åpne").font(.subheadline.bold())
          }.padding(14).background(reward.reward.isStar ? Color.purple.opacity(0.12) : SabboStyle.mint, in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain)
      }
    }
    .onAppear { collect() }
    .onChange(of: model.unopenedRewards.map(\.id)) { _, _ in collect() }
    .sheet(item: $opened) { reward in
      StreakRewardView(presentation: reward).onAppear { model.rewardShown(reward) }
    }
  }
  private func collect() {
    for value in model.unopenedRewards where !rewards.contains(where: { $0.id == value.id }) { rewards.append(value) }
  }
}
