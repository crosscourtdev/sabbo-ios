import SwiftUI

struct BonusAnswersHidden: View {
  var body: some View {
    Label("Svarene vises etter bonusrunden", systemImage: "lock.fill")
      .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 12)
      .accessibilityIdentifier("bonus-answers-hidden")
  }
}

struct CosmeticItemImage: View {
  let id: String
  var locked = false
  var size: CGFloat = 76
  var body: some View {
    Image("Cosmetic-\(id)-item")
      .renderingMode(locked ? .template : .original).resizable().scaledToFit()
      .foregroundStyle(Color.primary.opacity(0.65))
      .frame(width: size, height: size).accessibilityHidden(true)
  }
}

struct BonusStage: View {
  var showAction = true
  @EnvironmentObject var model: AppModel
  @State private var showCosmetics = false
  var body: some View {
    if let b = model.local.bonus, model.bonusStatus != "none" {
      VStack(alignment: .leading, spacing: 14) {
        HStack(spacing: 16) {
          if let id = b.cosmetic_id { CosmeticItemImage(id: id, locked: model.bonusStatus != "won", size: 52) }
          VStack(alignment: .leading, spacing: 6) {
            Text(model.bonusStatus == "too_late" ? "Ingen bonusrunde i dag" : "Bonusrunde · valgfri")
              .font(.system(.title3, design: .rounded, weight: .bold))
            Text(detail(b)).font(.subheadline).foregroundStyle(.secondary)
            if let target = b.target_grade, ["waiting", "ready", "retry"].contains(model.bonusStatus) {
              Text("Karakter \(target) eller bedre → nytt tilbehør")
                .font(.caption.weight(.semibold)).foregroundStyle(.primary)
            }
          }
          Spacer(minLength: 0)
        }
        if showAction && ["ready", "retry", "grading_failed"].contains(model.bonusStatus) {
          Button(model.bonusStatus == "won" ? "Se belønningen" : model.bonusStatus == "grading" ? "Se vurderingen" : "Start bonusrunde") {
            if b.id == nil { showCosmetics = true }
            else { model.openBonus() }
          }.buttonStyle(PlayButton()).accessibilityIdentifier("start-bonus")
        }
      }.frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("bonus-stage")
        .sheet(isPresented: $showCosmetics) { CosmeticPicker() }
    }
  }
  private func detail(_ b: BonusState) -> String {
    switch model.bonusStatus {
    case "too_late": return "Levert etter kl. 20. Neste sjanse er i morgen."
    case "waiting":
      let minutes = max(1, Int(ceil((BonusState.date(b.opens_at)?.timeIntervalSince(model.bonusNow) ?? 0) / 60)))
      return "Klar om \(minutes / 60) t \(minutes % 60) min"
    case "waiting_grade": return "Klar tre timer etter levering. Venter på dagens karakter."
    case "ready": return "Klar! Lever bonusrunden før midnatt."
    case "retry": return "Karakter \(b.grade ?? 0). Du kan prøve igjen før midnatt."
    case "grading": return "Svarene er mottatt. Vurderer …"
    case "grading_failed": return "Vurderingen mangler. Du kan prøve igjen før midnatt."
    case "won": return b.grade.map { "Karakter \($0) · Tilbehør vunnet!" } ?? "Tilbehør vunnet!"
    case "collection_complete": return "Du har samlet alt tilbehøret!"
    default: return "Bonusrunden er utløpt. En ny sjanse i morgen."
    }
  }
}

struct CosmeticPicker: View {
  @EnvironmentObject var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @State private var saving = false
  private var user: String { model.session?.user_id == ClientProfile.ownerID ? ClientProfile.ownerID : ClientProfile.learnerID }
  private var selected: String? { model.local.cosmetics?.people.first(where: { $0.user_id == model.session?.user_id })?.cosmetic_id }
  private var items: [CosmeticItem] {
    let owned = Set(model.local.cosmetics?.owned ?? [])
    return (model.local.cosmetics?.items ?? []).sorted {
      if owned.contains($0.id) != owned.contains($1.id) { return owned.contains($0.id) }
      return $0.id < $1.id
    }
  }
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 22) {
          PlayerAvatar(userID: model.session?.user_id, size: 132)
          Text("\(model.local.cosmetics?.owned.count ?? 0) av \(model.local.cosmetics?.items.count ?? 100) samlet")
            .font(.subheadline).foregroundStyle(.secondary)
          Button("Uten tilbehør") { equip(nil) }.buttonStyle(.bordered).disabled(saving || selected == nil)
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 16) {
            ForEach(items) { item in
              let unlocked = model.local.cosmetics?.owned.contains(item.id) == true
              Button { equip(item.id) } label: {
                VStack(spacing: 8) {
                  if unlocked {
                    Image("Cosmetic-\(item.id)-\(user)").resizable().scaledToFit()
                      .clipShape(RoundedRectangle(cornerRadius: 18))
                  } else { CosmeticItemImage(id: item.id, locked: true, size: 80).frame(height: 100) }
                  HStack(spacing: 4) {
                    if selected == item.id { Image(systemName: "checkmark.circle.fill") }
                    if unlocked { Text(item.name).lineLimit(1).minimumScaleFactor(0.8) }
                    else { Image(systemName: "lock.fill") }
                  }.font(.caption.weight(.semibold))
                    .foregroundStyle(selected == item.id ? SabboStyle.forest : Color.primary)
                }.padding(8).frame(maxWidth: .infinity)
                  .background(selected == item.id ? SabboStyle.mint : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
              }.buttonStyle(.plain).disabled(!unlocked || saving)
                .accessibilityLabel(unlocked ? item.name : "Låst tilbehør")
            }
          }
        }.padding(22).frame(maxWidth: 620).frame(maxWidth: .infinity)
      }.background(Color(.systemGroupedBackground)).navigationTitle("Mitt tilbehør")
        .toolbar { Button("Ferdig") { dismiss() } }
        .task { await model.refreshBonus() }
    }
  }
  private func equip(_ id: String?) {
    saving = true
    Task { _ = await model.equipCosmetic(id); saving = false }
  }
}

struct BonusRoundView: View {
  @EnvironmentObject var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @State private var session: BonusSession?
  @State private var error: String?
  @State private var retry = false
  var body: some View {
    NavigationStack {
      Group {
        if let session {
          if !retry, model.local.bonus?.attempt_id != nil, model.local.bonus?.id == session.round.id {
            DayResultView(assignment: session.assignment, question: session.question, stage: "bonus")
              .toolbar { Button("Ferdig") { dismiss() } }
          } else {
            GoalSessionView(day: Today(assignment: session.assignment, question: session.question, attempt: nil, draft: nil, streaks: [], server_day: session.assignment.day), mode: "bonus", bonusID: session.round.id)
          }
        } else if let error {
          ContentUnavailableView("Bonusrunde", systemImage: "gift", description: Text(error))
            .toolbar { Button("Lukk") { dismiss() } }
        } else { ProgressView("Henter bonusrunde …") }
      }.task { await load() }
    }
  }
  private func load() async {
    retry = ["retry", "grading_failed"].contains(model.bonusStatus)
    #if DEBUG
    if model.testing, let b = model.local.bonus, let day = model.local.today {
      session = BonusSession(round: b, assignment: day.assignment, question: day.question)
      return
    }
    #endif
    await model.refreshBonus()
    guard let id = model.local.bonus?.id else { error = "Ingen bonusrunde tilgjengelig."; return }
    do { session = try await model.api.get("/bonus/" + id) }
    catch { self.error = error.localizedDescription }
  }
}

struct BonusPrizeView: View {
  @EnvironmentObject var model: AppModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var appeared = false
  @State private var saving = false
  var body: some View {
    if let b = model.local.bonus, model.bonusStatus == "won", let id = b.cosmetic_id {
      VStack(spacing: 14) {
        Text("Nytt tilbehør!").font(.system(.title2, design: .rounded, weight: .heavy))
        CosmeticItemImage(id: id, size: 140)
          .scaleEffect(appeared || reduceMotion ? 1 : 0.55)
          .rotationEffect(.degrees(appeared || reduceMotion ? 0 : -12))
        Text(model.local.cosmetics?.items.first(where: { $0.id == id })?.name ?? "Låst opp")
          .font(.headline)
        let equipped = model.local.cosmetics?.people.first(where: { $0.user_id == model.session?.user_id })?.cosmetic_id == id
        Button(equipped ? "I bruk" : "Ta på") { saving = true; Task { _ = await model.equipCosmetic(id); saving = false } }
          .buttonStyle(PlayButton()).disabled(saving || equipped)
      }.padding(24).frame(maxWidth: .infinity)
        .background(SabboStyle.mint.opacity(0.35), in: RoundedRectangle(cornerRadius: 24))
        .accessibilityIdentifier("cosmetic-unlocked")
        .onAppear { withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.55)) { appeared = true } }
    }
  }
}
