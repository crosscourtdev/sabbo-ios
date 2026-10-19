import SwiftUI

struct HomeCounters: View {
  @EnvironmentObject var model: AppModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var openWardrobe: () -> Void
  @State private var destination: String?
  var body: some View {
    HStack(spacing: 12) {
      Button(action: openWardrobe) {
        PlayerAvatar(userID: model.session?.user_id, size: 58)
          .overlay(alignment: .bottomTrailing) {
            Image(systemName: "tshirt.fill").font(.caption).padding(5).background(.regularMaterial, in: Circle()).offset(x: 8, y: 8)
          }.padding(.trailing, 8).padding(.bottom, 8)
      }.buttonStyle(.plain).accessibilityLabel("Bytt tilbehør").accessibilityIdentifier("avatar-picker")
      Spacer(minLength: 0)
      counter("fire", value: model.ownStreak?.current ?? 0, symbol: "flame.fill", color: SabboStyle.orange, label: "dager på rad", flame: flame)
      counter("stars", value: model.ownProgress?.stars.total ?? 0, symbol: "star.fill", color: .yellow, label: "stjerner")
    }.sheet(isPresented: Binding(get: { destination != nil }, set: { if !$0 { destination = nil } })) {
      NavigationStack { RewardCollection(stars: destination == "stars") }.desktopSheet()
    }
  }
  /// The flame is dim until today's session is delivered and wiggles from 18:00 while a streak is at risk.
  private var flame: FlameState {
    guard let streak = model.ownStreak else { return .none }
    if streak.completed_today || model.hasSubmitted { return .lit }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = StudyText.oslo
    return streak.current > 0 && calendar.component(.hour, from: model.bonusNow) >= 18 ? .atRisk : .waiting
  }
  private func counter(_ id: String, value: Int, symbol: String, color: Color, label: String, flame: FlameState = .none) -> some View {
    CounterChip(value: value, symbol: symbol, color: color, stars: id == "stars", flame: flame) { destination = id }
      .accessibilityLabel("\(value) \(label)")
      .accessibilityValue(flame == .atRisk ? "Lever i dag for å holde rekken" : flame == .lit ? "Levert i dag" : "")
      .accessibilityHint(id == "stars" ? "Vis stjernekister og prestasjoner" : "Vis rekken og belønningene")
      .accessibilityIdentifier("home-counter-" + id)
  }
}

enum FlameState { case none, waiting, atRisk, lit }

private struct CounterChip: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let value: Int
  let symbol: String
  let color: Color
  let stars: Bool
  var flame: FlameState = .none
  var action: () -> Void
  @State private var gathering = false
  @State private var arrived = false
  @State private var animationID = UUID()
  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: symbol).foregroundStyle(color)
          .opacity(flame == .waiting || flame == .atRisk ? 0.55 : 1)
          .symbolEffect(.bounce, value: reduceMotion ? 0 : value)
          .symbolEffect(.breathe, isActive: flame == .lit && !reduceMotion && SabboFX.continuousMotion)
          .symbolEffect(.wiggle, isActive: flame == .atRisk && !reduceMotion && SabboFX.continuousMotion)
        Text("\(value)").foregroundStyle(.primary).contentTransition(.numericText())
      }.font(.system(.title3, design: .rounded, weight: .heavy))
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground), in: Capsule())
        .overlay {
          if gathering {
            ForEach(0..<4) { index in
              Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow)
                .offset(x: arrived ? 0 : CGFloat(index - 2) * 16, y: arrived ? 0 : 52 + CGFloat(index % 2) * 12)
                .opacity(arrived ? 0 : 1).scaleEffect(arrived ? 0.4 : 1)
            }.accessibilityHidden(true)
          }
        }
    }.buttonStyle(.plain)
      .animation(reduceMotion ? nil : .spring(duration: 0.45), value: value)
      .onChange(of: value) { old, new in
        guard stars, new > old, !reduceMotion else { return }
        let id = UUID(); animationID = id; arrived = false; gathering = true
        Task {
          try? await Task.sleep(for: .milliseconds(30))
          guard animationID == id else { return }
          withAnimation(.easeOut(duration: 0.8)) { arrived = true }
          try? await Task.sleep(for: .milliseconds(850))
          if animationID == id { gathering = false }
        }
      }
  }
}

struct AchievementRow: View {
  let achievement: Achievement
  var compact = false
  var body: some View {
    HStack(alignment: .center, spacing: 14) {
      Image(systemName: achievement.earned ? "checkmark.seal.fill" : achievement.symbol)
        .font(.title2).foregroundStyle(achievement.earned ? Color("AccentColor") : .secondary)
        .frame(width: 48, height: 48).background(SabboStyle.mint.opacity(0.4), in: RoundedRectangle(cornerRadius: 15))
      VStack(alignment: .leading, spacing: 5) {
        Text(achievement.title).font(.system(.headline, design: .rounded)).foregroundStyle(.primary)
        if !compact { Text(achievement.description).font(.subheadline).foregroundStyle(.secondary) }
        Text(achievement.earned ? "Låst opp" : "\(achievement.progress)/\(achievement.target)")
          .font(.caption.bold()).foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
      Label("+\(achievement.stars)", systemImage: "star.fill").font(.subheadline.bold()).foregroundStyle(.primary)
    }.accessibilityElement(children: .combine)
  }
}

struct AchievementPreview: View {
  @EnvironmentObject var model: AppModel
  @State private var expanded = false
  private var next: Achievement? {
    model.ownProgress?.achievements?.filter { !$0.earned }.sorted {
      Double($0.progress) / Double($0.target) > Double($1.progress) / Double($1.target)
    }.first
  }
  var body: some View {
    if let next {
      Button { expanded = true } label: { AchievementRow(achievement: next, compact: true).padding(16) }
        .buttonStyle(.plain).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
        .accessibilityIdentifier("achievement-preview")
        .sheet(isPresented: $expanded) { NavigationStack { RewardCollection(stars: true) }.desktopSheet() }
    }
  }
}

struct RewardCollection: View {
  @EnvironmentObject var model: AppModel
  @Environment(\.dismiss) private var dismiss
  let stars: Bool
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        if stars {
          Label("\(model.ownProgress?.stars.total ?? 0) stjerner", systemImage: "star.fill")
            .font(.system(.largeTitle, design: .rounded, weight: .heavy))
          if let next = StreakReward.starMilestones.first(where: { $0.threshold > (model.ownProgress?.stars.total ?? 0) }) {
            Text("\(next.threshold - (model.ownProgress?.stars.total ?? 0)) stjerner til neste kiste").foregroundStyle(.secondary)
          }
          HStack {
            ForEach(StreakReward.starMilestones) { reward in
              NavigationLink {
                let presentation = reward.presentation(userID: model.session?.user_id, best: model.rewardValue(reward))
                StreakRewardView(presentation: presentation).onAppear { model.rewardShown(presentation) }
              } label: {
                VStack(spacing: 8) {
                  TreasureChest(unlocked: model.rewardValue(reward) >= reward.threshold, size: 56)
                  Text("\(reward.threshold) ★").font(.headline).foregroundStyle(.primary)
                }.frame(maxWidth: .infinity).padding(.vertical, 12)
              }.buttonStyle(.plain).accessibilityIdentifier("stars-reward-\(reward.threshold)")
                .accessibilityLabel("Stjernekiste, \(reward.threshold) stjerner")
            }
          }
          Text("Prestasjoner").font(.system(.title2, design: .rounded, weight: .bold))
          ForEach(model.ownProgress?.achievements ?? []) { item in
            AchievementRow(achievement: item).padding(16)
              .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
          }
          Text("Karakteren gir 1–6 stjerner. Hver prestasjon gir 25 ekstra, én gang. Bare aktivitet etter at prestasjonene ble lansert teller.")
            .font(.footnote).foregroundStyle(.secondary)
        } else {
          ProgressPanel()
          Text("Lever dagsøkten før midnatt for å holde rekken. Opptjente kister beholdes ved en pause.")
            .font(.subheadline).foregroundStyle(.secondary)
        }
      }.padding(22).frame(maxWidth: 620).frame(maxWidth: .infinity)
    }.background(Color(.systemGroupedBackground)).navigationTitle(stars ? "Stjerner og prestasjoner" : "Rekken din")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Ferdig") { dismiss() } } }
  }
}

struct AchievementCelebration: View {
  @EnvironmentObject var model: AppModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var attemptID: String? = nil
  @State private var dismissed: Set<String> = []
  private var key: String { "sabbo.achievements.seen." + (model.session?.user_id ?? "") }
  private var unseen: [Achievement] {
    let seen = Set(UserDefaults.standard.stringArray(forKey: key) ?? []).union(dismissed)
    return (model.ownProgress?.achievements ?? []).filter {
      $0.earned && !seen.contains($0.id) && (attemptID == nil || $0.attempt_id == attemptID)
    }
  }
  var body: some View {
    ForEach(unseen) { item in
      VStack(alignment: .leading, spacing: 12) {
        Text("Prestasjon låst opp!").font(.caption.bold()).foregroundStyle(Color("AccentColor"))
        AchievementRow(achievement: item)
        Button("Herlig!") {
          dismissed.insert(item.id)
          let seen = Set(UserDefaults.standard.stringArray(forKey: key) ?? []).union(dismissed)
          UserDefaults.standard.set(Array(seen), forKey: key)
        }.font(.subheadline.bold()).frame(minHeight: 44)
      }.padding(16).background(SabboStyle.mint.opacity(0.5), in: RoundedRectangle(cornerRadius: 20))
        .transition(reduceMotion ? .identity : .scale.combined(with: .opacity))
    }
  }
}
