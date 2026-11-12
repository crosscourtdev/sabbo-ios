import SwiftUI

/// A durable, account-scoped acknowledgement. Reading a result does not consume it.
struct RewardNoticeStore {
  var defaults: UserDefaults = .standard
  private func key(_ account: String) -> String { "sabbo.celebrations." + account }
  func seen(_ account: String) -> Set<String> { Set(defaults.stringArray(forKey: key(account)) ?? []) }
  func acknowledge(_ ids: [String], account: String) {
    defaults.set(Array(seen(account).union(ids)).sorted(), forKey: key(account))
  }
  func baseline(_ ids: [String], track: String, account: String) {
    let marker = key(account) + ".baseline." + track
    guard !defaults.bool(forKey: marker) else { return }
    acknowledge(ids, account: account)
    defaults.set(true, forKey: marker)
  }
}

struct RewardNotice: Identifiable {
  enum Content {
    case stars(Int), fire, achievement(Achievement), milestone(StreakReward), cosmetic(CosmeticItem)
  }
  let id: String
  let content: Content
}

struct RewardCelebration: Identifiable {
  let id = UUID()
  let scope: String
  let notices: [RewardNotice]
}

extension AppModel {
  var celebrationScope: String {
    [session?.user_id ?? "", ownProgress?.stars.epoch ?? "", ownStreak?.epoch ?? ""].joined(separator: "|")
  }
  /// Migration suppresses historical inventory, but preserves today's uncollected reward.
  /// Separate baselines tolerate progress and wardrobe arriving in different requests.
  func pendingRewardNotices(store: RewardNoticeStore = RewardNoticeStore()) -> [RewardNotice] {
    guard let account = session?.user_id, let progress = ownProgress else { return [] }
    let stars = progress.stars
    func starKey(_ award: StarAward) -> String { "stars:\(stars.epoch):\(award.id)" }
    let legacy = Set(store.defaults.stringArray(forKey: "sabbo.gains." + account) ?? [])
    let oldFire = progress.fire_attempt_id.flatMap { attempt in
      attempt == currentAttemptID ? nil : "fire:\(progress.streak.epoch ?? ""):\(attempt)"
    }
    store.baseline(stars.awards.filter { $0.attempt_id != currentAttemptID }.map(starKey) + Array(legacy) + [oldFire].compactMap { $0 }, track: "progress", account: account)
    if let collection = local.cosmetics {
      let justWon = local.bonus?.status == "won" ? local.bonus?.cosmetic_id : nil
      let prizeSeen = legacy.contains("prize:" + (local.bonus?.id ?? local.bonus?.day ?? ""))
      store.baseline(collection.owned.filter { $0 != justWon || prizeSeen }.map { "cosmetic:" + $0 }, track: "cosmetics", account: account)
    }
    let seen = store.seen(account)
    let oldAchievements = Set(store.defaults.stringArray(forKey: "sabbo.achievements.seen." + account) ?? [])
    var notices = stars.awards.filter { $0.stars > 0 }.map { RewardNotice(id: starKey($0), content: .stars($0.stars)) }
    if let attempt = progress.fire_attempt_id {
      notices.append(RewardNotice(id: "fire:\(progress.streak.epoch ?? ""):\(attempt)", content: .fire))
    }
    for achievement in progress.achievements ?? [] where achievement.earned && !oldAchievements.contains(achievement.id) {
      notices.append(RewardNotice(id: "achievement:" + achievement.id, content: .achievement(achievement)))
    }
    for reward in unopenedRewards.map(\.reward) {
      let epoch = reward.isStar ? stars.epoch : progress.streak.epoch ?? ""
      notices.append(RewardNotice(id: "milestone:\(reward.kind):\(epoch):\(reward.day)", content: .milestone(reward)))
    }
    if let collection = local.cosmetics {
      for item in collection.items where collection.owned.contains(item.id) {
        notices.append(RewardNotice(id: "cosmetic:" + item.id, content: .cosmetic(item)))
      }
    }
    return notices.filter { !seen.contains($0.id) }
  }
  func acknowledgeCelebration(_ celebration: RewardCelebration) {
    guard celebration.scope == celebrationScope, let account = session?.user_id else { return }
    RewardNoticeStore().acknowledge(celebration.notices.map(\.id), account: account)
    for notice in celebration.notices {
      if case .stars = notice.content { _ = collectGain(notice.id) }
      if case .fire = notice.content { _ = collectGain(notice.id) }
      if case .milestone(let reward) = notice.content { rewardShown(RewardPresentation(reward: reward, access: .earned)) }
    }
  }
}

struct RewardCelebrationView: View {
  @EnvironmentObject var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @AccessibilityFocusState private var focused: Bool
  let celebration: RewardCelebration
  private var stars: Int {
    celebration.notices.reduce(0) { total, notice in
      if case .stars(let count) = notice.content { return total + count }
      return total
    }
  }
  var body: some View {
    GeometryReader { geometry in
      ZStack {
        Color.black.opacity(0.45).ignoresSafeArea().accessibilityHidden(true)
        ViewThatFits(in: .vertical) {
          VStack(spacing: 24) { content; done }.padding(24).fixedSize(horizontal: false, vertical: true)
          VStack(spacing: 20) {
            ScrollView { content.padding(.bottom, 4) }
            done
          }.padding(24)
        }
        .frame(maxWidth: 520)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 28))
        .shadow(color: .black.opacity(0.15), radius: 24, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reward-overlay-card")
        .padding(20)
        .frame(width: geometry.size.width, height: geometry.size.height)
      }
    }
    .accessibilityAction(.escape) { dismiss() }
    .onAppear { model.acknowledgeCelebration(celebration); focused = true }
  }
  private var done: some View {
    Button("Herlig!") { dismiss() }.buttonStyle(PlayButton())
      .accessibilityIdentifier("reward-overlay-done")
  }
  private var content: some View {
    VStack(alignment: .leading, spacing: 22) {
      VStack(spacing: 12) {
        Text("Godt jobbet!").font(.system(.largeTitle, design: .rounded, weight: .heavy))
          .accessibilityAddTraits(.isHeader).accessibilityFocused($focused)
        if stars > 0 {
          Label("+\(stars) stjerner", systemImage: "star.fill").font(.title2.bold())
            .accessibilityIdentifier("reward-overlay-stars")
        }
      }.multilineTextAlignment(.center).frame(maxWidth: .infinity)
      ForEach(celebration.notices) { notice in
        switch notice.content {
        case .stars: EmptyView()
        case .fire:
          Label("+1 dag på rad", systemImage: "flame.fill").font(.headline).foregroundStyle(SabboStyle.orange)
        case .achievement(let achievement): AchievementRow(achievement: achievement)
        case .milestone(let reward):
          HStack(spacing: 16) {
            RewardIcon(reward: reward, unlocked: true, size: 64)
            VStack(alignment: .leading, spacing: 6) {
              Text(reward.title).font(.headline)
              Text(reward.message).font(.subheadline)
            }
          }.accessibilityElement(children: .combine)
        case .cosmetic(let item):
          HStack(spacing: 16) {
            CosmeticItemImage(id: item.id, size: 88)
            VStack(alignment: .leading, spacing: 6) {
              Text("Nytt tilbehør!").font(.headline)
              Text(item.name)
              Text("Du finner det i garderoben.").font(.caption).foregroundStyle(.secondary)
            }
          }.accessibilityElement(children: .combine).accessibilityIdentifier("reward-overlay-cosmetic")
        }
      }
      Text("Belønningene dine finner du via tellerne og garderoben.").font(.footnote).foregroundStyle(.secondary)
        .multilineTextAlignment(.center).frame(maxWidth: .infinity)
    }
  }
}
