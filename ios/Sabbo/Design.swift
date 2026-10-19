import SwiftUI
import ImageIO
import UIKit

// The portrait's forest/mint palette, with semantic surfaces in both appearances.
enum SabboStyle {
  static let forest = Color(red: 0.09, green: 0.25, blue: 0.21)
  static let mint = Color(red: 0.86, green: 0.93, blue: 0.78)
  static let orange = Color(red: 0.91, green: 0.40, blue: 0.15)
  static let gold = Color(red: 0.96, green: 0.69, blue: 0.18)
  static func subject(_ id: String) -> Color { id == "pome" ? Color("AccentColor") : .indigo }
  static func symbol(_ id: String) -> String { id == "pome" ? "building.columns.fill" : "sparkles" }
}
struct PlayButton: ButtonStyle {
  @Environment(\.isEnabled) private var enabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.system(.headline, design: .rounded, weight: .bold))
      .frame(maxWidth: .infinity, minHeight: 28).padding(.vertical, 14).padding(.horizontal, 20)
      .foregroundStyle(SabboStyle.forest)
      .background { RoundedRectangle(cornerRadius: 20).fill(SabboStyle.mint)
        .shadow(color: SabboStyle.forest.opacity(0.35), radius: 0, y: configuration.isPressed ? 1 : 5) }
      .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(SabboStyle.forest.opacity(0.12), lineWidth: 1))
      .offset(y: configuration.isPressed ? 3 : 0)
      .opacity(enabled ? 1 : 0.45)
      .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
      .onChange(of: configuration.isPressed) { _, pressed in if pressed && enabled { SabboFX.shared.haptic(.tap) } }
  }
}
struct PortraitMark: View {
  var size: CGFloat = 72
  var body: some View {
    Image("Portrait").resizable().scaledToFit().frame(width: size, height: size)
      .clipShape(RoundedRectangle(cornerRadius: size * 0.3)).accessibilityHidden(true)
  }
}
// Account identity is independent of display names and administrator permissions.
struct PlayerAvatar: View {
  @EnvironmentObject var model: AppModel
  let userID: String?
  var size: CGFloat = 48
  var body: some View {
    Group {
      if let userID, let equipped = model.local.cosmetics?.people.first(where: { $0.user_id == userID })?.cosmetic_id,
         let image = UIImage(named: "Cosmetic-\(equipped)-\(userID)") {
        Image(uiImage: image).resizable().scaledToFit()
      } else {
      switch userID {
      case ClientProfile.ownerID: Image(ClientProfile.value.ownerAvatar).resizable().scaledToFit()
      case ClientProfile.learnerID: Image(ClientProfile.value.learnerAvatar).resizable().scaledToFit()
      default:
        Image(systemName: "person.crop.circle.fill").resizable().scaledToFit()
          .foregroundStyle(.secondary)
      }
      }
    }.frame(width: size, height: size)
      .clipShape(RoundedRectangle(cornerRadius: size * 0.3))
      .accessibilityHidden(true)
  }
}

struct PlayerLabel: View {
  let userID: String
  let name: String
  var body: some View {
    HStack(spacing: 10) {
      PlayerAvatar(userID: userID, size: 32)
      Text(name).font(.system(.headline, design: .rounded, weight: .bold))
    }
  }
}
struct SubjectPill: View {
  let id: String
  var body: some View {
    Label(StudyText.subject(id), systemImage: SabboStyle.symbol(id))
      .font(.system(.caption, design: .rounded, weight: .bold))
      .padding(.horizontal, 12).padding(.vertical, 8)
      .foregroundStyle(SabboStyle.subject(id))
      .background(SabboStyle.subject(id).opacity(0.1), in: Capsule())
  }
}
struct SessionSteps: View {
  let step: Int
  var body: some View {
    HStack(spacing: 6) {
      ForEach(0..<3) { index in
        Capsule().fill(index <= step ? Color("AccentColor") : Color(.tertiarySystemFill)).frame(height: 7)
      }
    }.accessibilityElement(children: .ignore)
      .accessibilityLabel(["Skriv", "Se gjennom", "Fullført"][step])
      .accessibilityValue("Trinn \(step + 1) av 3")
  }
}
struct VictoryView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var appeared = false
  let provisional: Bool
  var body: some View {
    VStack(spacing: 12) {
      ZStack {
        Circle().fill(SabboStyle.mint).frame(width: 100, height: 100)
        Image(systemName: "checkmark.seal.fill").font(.system(size: 60, weight: .bold)).foregroundStyle(SabboStyle.forest)
        ForEach(0..<6) { i in
          Image(systemName: "sparkle").font(.system(size: CGFloat(10 + i % 3 * 4)))
            .foregroundStyle(i.isMultiple(of: 2) ? SabboStyle.orange : Color("AccentColor"))
            .offset(x: cos(Double(i) * .pi / 3) * 70, y: sin(Double(i) * .pi / 3) * 60)
        }
      }.frame(height: 140).scaleEffect(appeared ? 1 : 0.85)
      Text("Dagens seier!").font(.system(.title, design: .rounded, weight: .heavy))
      if provisional { Label("Lagret på telefonen", systemImage: "icloud.and.arrow.up").font(.caption).foregroundStyle(.secondary) }
    }.frame(maxWidth: .infinity).padding(.vertical, 12)
      .onAppear { withAnimation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.3)) { appeared = true } }
      .sensoryFeedback(.success, trigger: appeared)
  }
}
struct EvaluationCard: View {
  @EnvironmentObject var model: AppModel
  let attemptID: String
  var question: Question? = nil
  @Environment(\.scenePhase) private var scenePhase
  @State private var retry = 0
  @State private var loadError: String?
  @State private var waitedHere = false
  /// Celebrate a grade that arrived on screen, or today's unseen result; never old history.
  private var celebrates: Bool {
    (waitedHere || attemptID == model.currentAttemptID || attemptID == model.local.bonus?.attempt_id)
      && !model.gainCollected("grade:" + attemptID)
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let evaluation = model.savedEvaluation(attemptID) {
        if let result = evaluation.result {
          VStack(alignment: .leading, spacing: 18) {
            if let grade = result.grade {
              GradeHeadline(grade: grade, key: "grade:" + attemptID, celebrate: celebrates).id(attemptID + String(grade))
            }
            if model.answersLocked(attemptID: attemptID) || question.map({ model.answersLocked($0) }) == true { BonusAnswersHidden() } else {
            Text(result.reason).lineLimit(3)
            if !result.improvement.isEmpty {
              VStack(alignment: .leading, spacing: 6) {
                Label("Neste steg", systemImage: "arrow.up.right").font(.subheadline.bold())
                Text(result.improvement).font(.subheadline).lineLimit(3)
              }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                .background(Color("AccentColor").opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
            }
            DisclosureGroup("Vurderingsdetaljer") {
              VStack(alignment: .leading, spacing: 16) {
                Text(result.reason).fixedSize(horizontal: false, vertical: true)
                if !result.improvement.isEmpty {
                  Text(result.improvement).fixedSize(horizontal: false, vertical: true)
                }
                if !result.strengths.isEmpty {
                  VStack(alignment: .leading, spacing: 6) {
                    Text("Dette fikk du til").font(.subheadline.bold())
                    Text(result.strengths)
                  }
                }
                ForEach(result.criteria) { c in
                  VStack(alignment: .leading, spacing: 6) {
                    Text(c.comment)
                    if !c.evidence.isEmpty { Text("«" + c.evidence + "»").italic().foregroundStyle(.secondary) }
                  }
                }
                Text("Veiledende KI-vurdering, ikke en eksamenskarakter.").font(.caption).foregroundStyle(.secondary)
              }.padding(.top, 12)
            }.font(.subheadline)
            }
          }
        } else if ["queued", "processing"].contains(evaluation.status) {
          GradingWait(text: "Mottatt · Vurderer …")
        } else if ["failed", "unavailable", "budget_limited"].contains(evaluation.status) {
          Label("Vurderingen er ikke tilgjengelig nå.", systemImage: "exclamationmark.circle").font(.subheadline)
        } else {
          Text("Ingen vurdering er tilgjengelig for dette forsøket.").font(.subheadline)
        }
      } else if loadError == nil {
        GradingWait(text: "Mottatt · Henter vurderingen …")
      }
      if let loadError, model.savedEvaluation(attemptID)?.result == nil {
        Text(loadError).font(.subheadline)
        Button("Prøv igjen") { retry += 1 }
      }
    }.frame(maxWidth: .infinity, alignment: .topLeading)
      .padding(20)
      .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
      .accessibilityIdentifier("result-evaluation")
      .onAppear { if model.savedEvaluation(attemptID)?.result == nil { waitedHere = true } }
      .task(id: attemptID + String(retry)) {
        loadError = nil
        loadError = await model.watchEvaluation(attemptID)
      }
      .onChange(of: scenePhase) { _, phase in
        if phase == .active { retry += 1 }
      }
  }
}

struct TreasureChest: View {
  var unlocked = false
  var size: CGFloat = 64
  /// 0 is closed; 1 lifts and tilts the lid over a glow.
  var lid: Double = 0
  private var gold: Color { unlocked ? SabboStyle.gold : Color(.systemGray3) }
  var body: some View {
    ZStack {
      if unlocked {
        Circle().fill(SabboStyle.mint).frame(width: size, height: size)
        Image(systemName: "sparkles").font(.system(size: size * 0.22, weight: .bold))
          .foregroundStyle(gold).offset(x: size * 0.32, y: -size * 0.32)
      }
      if lid > 0 {
        Ellipse().fill(Color(red: 1, green: 0.9, blue: 0.55)).frame(width: size * 0.7, height: size * 0.16)
          .blur(radius: size * 0.05).offset(y: -size * 0.06).opacity(lid)
      }
      RoundedRectangle(cornerRadius: size * 0.08)
        .fill(unlocked ? SabboStyle.forest : Color(.systemGray2))
        .frame(width: size * 0.78, height: size * 0.48).offset(y: size * 0.14)
      RoundedRectangle(cornerRadius: size * 0.12)
        .fill(gold).frame(width: size * 0.84, height: size * 0.32)
        .rotationEffect(.degrees(-22 * lid), anchor: .bottomLeading)
        .offset(y: -size * (0.1 + 0.16 * lid))
      HStack(spacing: size * 0.36) {
        Rectangle().fill(gold).frame(width: size * 0.07, height: size * 0.38)
        Rectangle().fill(gold).frame(width: size * 0.07, height: size * 0.38)
      }.offset(y: size * 0.17)
      RoundedRectangle(cornerRadius: size * 0.04).fill(gold)
        .frame(width: size * 0.19, height: size * 0.23).offset(y: size * 0.09)
      Image(systemName: unlocked ? "star.fill" : "lock.fill")
        .font(.system(size: size * 0.1, weight: .heavy)).foregroundStyle(SabboStyle.forest)
        .offset(y: size * 0.09)
    }.frame(width: size, height: size).accessibilityHidden(true)
  }
}

struct StreakRewardView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  let presentation: RewardPresentation
  @State private var revealed = false
  @State private var lid: Double
  @State private var wobble = 0.0
  @State private var opened: Bool
  @State private var confetti = 0
  private var reward: StreakReward { presentation.reward }
  /// Earned chests open with a short knock-knock-pop; previews and locks stay calm.
  private var ceremony: Bool { presentation.access == .earned && presentation.revealsMessage }
  init(presentation: RewardPresentation) {
    self.presentation = presentation
    let ceremony = presentation.access == .earned && presentation.revealsMessage
    _lid = State(initialValue: presentation.revealsMessage && !ceremony ? 1 : 0)
    _opened = State(initialValue: !ceremony)
  }
  var body: some View {
    ScrollView {
      VStack(spacing: 24) {
        if presentation.access == .preview {
          Text("Forhåndsvisning").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
        }
        Label(reward.isStar ? "Stjernebelønning" : "Flammebelønning", systemImage: reward.isStar ? "star.fill" : "flame.fill")
          .font(.headline).foregroundStyle(reward.isStar ? .yellow : SabboStyle.orange)
        ZStack {
          if ceremony && lid > 0 && !reduceMotion { ChestRays(size: 220).opacity(lid) }
          TreasureChest(unlocked: presentation.revealsMessage, size: presentation.revealsMessage ? 140 : 180, lid: lid)
            .rotationEffect(.degrees(wobble))
            .scaleEffect(presentation.access == .earned && !reduceMotion && !revealed ? 0.85 : 1)
        }.frame(height: presentation.revealsMessage ? 200 : 180)
          .overlay { ConfettiBurst(trigger: confetti, intensity: .large).frame(width: 440, height: 560) }
          .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.55)) { revealed = true }
          }
          .task { await openChest() }
        Text(presentation.access == .earned ? reward.title : reward.unlockLabel)
          .font(.system(.largeTitle, design: .rounded, weight: .heavy)).multilineTextAlignment(.center)
        if presentation.revealsMessage && opened {
          Text(reward.message).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
            .accessibilityIdentifier("reward-message")
          if reward.day == 50 && NSDataAsset(name: ClientProfile.value.rewardAsset) != nil {
            RewardGIF(animate: !reduceMotion && scenePhase == .active)
              .aspectRatio(478.0 / 268.0, contentMode: .fit)
              .clipShape(RoundedRectangle(cornerRadius: 20))
              .accessibilityLabel(ClientProfile.value.rewardAccessibilityLabel)
              .accessibilityIdentifier("reward-no-gif")
          } else if presentation.access == .earned {
            ShareLink(item: "\(reward.title)\n\(reward.message)") {
              Label("Del belønningen", systemImage: "square.and.arrow.up")
            }.buttonStyle(PlayButton())
          }
        } else if !presentation.revealsMessage {
          Text(reward.lockedMessage)
            .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
            .accessibilityIdentifier("reward-unlock-day")
        }
        Button("Lukk") { dismiss() }.buttonStyle(PlayButton())
          .accessibilityIdentifier("close-streak-reward")
      }.padding(28).padding(.top, 20).frame(maxWidth: 520).frame(maxWidth: .infinity)
    }.background(Color(.systemGroupedBackground))
  }
  private func openChest() async {
    guard ceremony, !opened else { return }
    if reduceMotion || UIAccessibility.isVoiceOverRunning {
      lid = 1; opened = true
      SabboFX.shared.play(.chestOpen); SabboFX.shared.haptic(.success)
      return
    }
    do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
    for angle in [-7.0, 7, -5] {
      withAnimation(.easeInOut(duration: 0.07)) { wobble = angle }
      SabboFX.shared.play(.chestKnock); SabboFX.shared.haptic(.knock)
      do { try await Task.sleep(for: .milliseconds(150)) } catch { break }
    }
    withAnimation(.easeOut(duration: 0.08)) { wobble = 0 }
    SabboFX.shared.play(.chestOpen); SabboFX.shared.haptic(.open)
    withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { lid = 1 }
    confetti += 1
    try? await Task.sleep(for: .milliseconds(250))
    withAnimation(.easeOut(duration: 0.35)) { opened = true }
    SabboFX.shared.haptic(.success, after: 0.1)
  }
}

// Bundled data avoids third-party requests and keeps the reveal available offline.
struct RewardGIF: UIViewRepresentable {
  let animate: Bool
  private static let frames: (images: [UIImage], duration: TimeInterval) = {
    guard let data = NSDataAsset(name: ClientProfile.value.rewardAsset)?.data,
          let source = CGImageSourceCreateWithData(data as CFData, nil) else { return ([], 0) }
    var images: [UIImage] = []
    var duration: TimeInterval = 0
    for index in 0..<CGImageSourceGetCount(source) {
      guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
      let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
      let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
      let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
        ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
      images.append(UIImage(cgImage: image))
      duration += max(0.02, delay)
    }
    return (images, duration)
  }()
  func makeUIView(context: Context) -> UIImageView {
    let view = UIImageView()
    view.contentMode = .scaleAspectFit
    view.clipsToBounds = true
    view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    view.image = Self.frames.images.last
    view.animationImages = Self.frames.images
    view.animationDuration = Self.frames.duration
    view.animationRepeatCount = 0
    return view
  }
  func updateUIView(_ view: UIImageView, context: Context) {
    if animate && !view.isAnimating { view.startAnimating() }
    else if !animate { view.stopAnimating() }
  }
  static func dismantleUIView(_ view: UIImageView, coordinator: ()) { view.stopAnimating() }
}


struct SubmissionReceiptView: View {
  let status: String?
  let day: String
  var body: some View {
    if status == "late" {
      VStack(alignment: .leading, spacing: 6) {
        Label("Levert for sent", systemImage: "clock.badge.exclamationmark").font(.subheadline.bold())
        Text("Fristen var kl. 23:59 den \(StudyText.day(day)). Sen levering gir ikke streak, stjerner eller bonusrunde.")
          .font(.footnote)
      }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityIdentifier("submission-late")
    } else if status == "exception" {
      Label("Levert for sent · Belønning godkjent", systemImage: "checkmark.seal")
        .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("submission-exception")
    } else if status != "practice" {
      Label("Mottatt", systemImage: "checkmark.icloud").font(.caption).foregroundStyle(.secondary)
    }
  }
}
