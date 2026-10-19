import SwiftUI
import UIKit

/// Brand-coloured confetti for earned moments. Nothing renders with Reduce Motion.
struct ConfettiBurst: View {
  enum Intensity {
    case small, medium, large
    var count: Int { switch self { case .small: 18; case .medium: 44; case .large: 90 } }
  }
  private struct Piece {
    let angle: Double, speed: Double, spin: Double, size: Double, delay: Double, shape: Int
    let color: Color
  }
  let trigger: Int
  var intensity: Intensity = .medium
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var started: Date?
  @State private var pieces: [Piece] = []
  @State private var run = UUID()
  private static let palette: [Color] = [SabboStyle.mint, SabboStyle.orange, SabboStyle.gold, Color("AccentColor"), .yellow, SabboStyle.forest]
  private static let lifetime = 1.8
  var body: some View {
    TimelineView(.animation(paused: started == nil)) { timeline in
      Canvas { canvas, size in
        guard let started else { return }
        let elapsed = timeline.date.timeIntervalSince(started)
        let origin = CGPoint(x: size.width / 2, y: size.height * 0.42)
        for piece in pieces {
          let age = elapsed - piece.delay
          guard age > 0, age < Self.lifetime else { continue }
          var context = canvas
          context.opacity = 1 - age / Self.lifetime
          let dx = cos(piece.angle) * piece.speed * age
          let dy = sin(piece.angle) * piece.speed * age + 450 * age * age
          context.translateBy(x: origin.x + CGFloat(dx), y: origin.y + CGFloat(dy))
          context.rotate(by: .radians(piece.spin * age))
          let side = CGFloat(piece.size)
          let rect = CGRect(x: -side / 2, y: -side / 2, width: side, height: piece.shape == 0 ? side * 0.5 : side)
          let path = piece.shape == 1 ? Path(ellipseIn: rect) : piece.shape == 2 ? Self.star(rect) : Path(roundedRect: rect, cornerRadius: 1.5)
          context.fill(path, with: .color(piece.color))
        }
      }
    }
    .allowsHitTesting(false).accessibilityHidden(true)
    .onChange(of: trigger) { _, value in
      guard value > 0, !reduceMotion else { return }
      pieces = (0..<intensity.count).map { _ in
        Piece(angle: -Double.pi / 2 + .random(in: -1.15...1.15), speed: .random(in: 240...620), spin: .random(in: -9...9),
              size: .random(in: 6...12), delay: .random(in: 0...0.12), shape: .random(in: 0...2), color: Self.palette.randomElement()!)
      }
      let id = UUID()
      run = id
      started = Date()
      Task { @MainActor in
        try? await Task.sleep(for: .seconds(Self.lifetime + 0.3))
        if run == id { started = nil }
      }
    }
  }
  private static func star(_ rect: CGRect) -> Path {
    var path = Path()
    let center = CGPoint(x: rect.midX, y: rect.midY)
    for index in 0..<10 {
      let radius: CGFloat = (index.isMultiple(of: 2) ? 1 : 0.45) * rect.width / 2
      let angle = CGFloat(index) * .pi / 5 - .pi / 2
      let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
      if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    path.closeSubpath()
    return path
  }
}

/// The grade counts up once, then lands with sound, haptics and confetti scaled to the result.
/// The accessibility label always states the final grade.
struct GradeHeadline: View {
  @EnvironmentObject var model: AppModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let grade: Int
  let key: String
  @State private var shown: Int
  @State private var landed: Bool
  @State private var pop = false
  @State private var confetti = 0
  private let celebrates: Bool
  init(grade: Int, key: String, celebrate: Bool) {
    self.grade = grade
    self.key = key
    celebrates = celebrate
    _shown = State(initialValue: celebrate ? 0 : grade)
    _landed = State(initialValue: !celebrate)
  }
  private var color: Color { grade >= 5 ? SabboStyle.gold : Color("AccentColor") }
  var body: some View {
    HStack(spacing: 16) {
      ZStack {
        Circle().stroke(color.opacity(0.18), lineWidth: 8)
        Circle().trim(from: 0, to: CGFloat(shown) / 6)
          .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90))
        Image(systemName: "star.fill").font(.title3).foregroundStyle(color)
          .symbolEffect(.bounce, value: landed)
      }.frame(width: 60, height: 60).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text("Karakter \(max(shown, 1))")
          .font(.system(.largeTitle, design: .rounded, weight: .heavy))
          .foregroundStyle(Color("AccentColor"))
          .contentTransition(.numericText(value: Double(shown)))
          .accessibilityLabel("Veiledende karakter \(grade) av 6")
        if landed {
          Text(GradeCelebration.phrase(grade)).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            .transition(.opacity.combined(with: .offset(y: 6)))
        }
      }
      Spacer(minLength: 0)
    }
    .scaleEffect(pop ? 1.08 : 1, anchor: .leading)
    .overlay {
      // Keep the overlay's bounds on the headline; overflowing confetti must
      // never enlarge the grade's accessibility frame over adjacent controls.
      GeometryReader { geometry in
        ConfettiBurst(trigger: confetti, intensity: GradeCelebration.confetti(grade))
          .frame(width: 440, height: 520)
          .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
      }.allowsHitTesting(false).accessibilityHidden(true)
    }
    .accessibilityIdentifier("grade-headline")
    .task {
      guard celebrates, model.collectGain(key) else {
        if !landed { shown = grade; landed = true }
        return
      }
      if reduceMotion {
        shown = grade; landed = true; land(); return
      }
      do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
      for value in 1...max(1, grade) {
        withAnimation(.snappy(duration: 0.2)) { shown = value }
        SabboFX.shared.play(.tick)
        SabboFX.shared.haptic(.tick(0.3 + 0.12 * Double(value)))
        if value < grade { do { try await Task.sleep(for: .milliseconds(150 + value * 30)) } catch { break } }
      }
      shown = grade
      withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { landed = true; pop = true }
      land()
      try? await Task.sleep(for: .milliseconds(200))
      withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { pop = false }
    }
  }
  private func land() {
    SabboFX.shared.play(GradeCelebration.sound(grade))
    SabboFX.shared.haptic(.success)
    UIAccessibility.post(notification: .announcement, argument: "Karakter \(grade). " + GradeCelebration.phrase(grade))
    confetti += 1
  }
}

/// Grading takes a few seconds; keep the wait alive without implying progress.
struct GradingWait: View {
  let text: String
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private static let tips = [
    "Tips: Fagbegreper løfter ofte svaret.",
    "Tips: Et konkret eksempel gjør forklaringen sterkere.",
    "Tips: Begrunn påstandene dine.",
    "Tips: «Neste steg» viser hva som gir mest uttelling.",
  ]
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 12) {
        Image(systemName: "pencil").font(.title2.weight(.semibold)).foregroundStyle(Color("AccentColor"))
          .symbolEffect(.wiggle, isActive: !reduceMotion && SabboFX.continuousMotion)
          .accessibilityHidden(true)
        Text(text).font(.subheadline)
      }
      TimelineView(.periodic(from: .now, by: 3.5)) { timeline in
        let index = Int(timeline.date.timeIntervalSinceReferenceDate / 3.5) % Self.tips.count
        Text(Self.tips[index]).font(.footnote).foregroundStyle(.secondary)
          .id(index).transition(.opacity)
          .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: index)
      }.accessibilityHidden(true)
    }
  }
}

/// Once per day, a light toast when the other person has delivered today's session.
struct PeerDeliveredToast: View {
  @EnvironmentObject var model: AppModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var shown: Streak?
  private var peer: Streak? { model.local.today?.streaks.first { $0.user_id != model.session?.user_id } }
  private var key: String { "peer:" + (model.local.today?.server_day ?? "") + ":" + (peer?.user_id ?? "") }
  var body: some View {
    VStack {
      if let shown {
        HStack(spacing: 12) {
          PlayerAvatar(userID: shown.user_id, size: 34)
          Text("\(shown.name) har levert dagens økt! 🔥").font(.subheadline.bold()).foregroundStyle(.primary)
        }
        .padding(.leading, 8).padding(.trailing, 16).padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .onTapGesture { self.shown = nil }
        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
        .accessibilityIdentifier("peer-delivered")
      }
    }.padding(.top, 6)
      .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.75), value: shown?.user_id)
      .onChange(of: key + String(peer?.completed_today ?? false), initial: true) { _, _ in check() }
  }
  private func check() {
    guard !model.testing, model.session != nil, let peer, peer.completed_today, model.collectGain(key) else { return }
    shown = peer
    SabboFX.shared.play(.peer)
    SabboFX.shared.haptic(.tap)
    UIAccessibility.post(notification: .announcement, argument: "\(peer.name) har levert dagens økt")
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(4))
      if self.shown?.user_id == peer.user_id { self.shown = nil }
    }
  }
}

/// Shown once when both people have delivered today's session and their answers open.
struct SharedUnlockBanner: View {
  @EnvironmentObject var model: AppModel
  let key: String
  @State private var visible = false
  @State private var unlocked = false
  @State private var confetti = 0
  var body: some View {
    Group {
      if visible {
        HStack(spacing: 12) {
          Image(systemName: unlocked ? "lock.open.fill" : "lock.fill").font(.title2).foregroundStyle(Color("AccentColor"))
            .contentTransition(.symbolEffect(.replace)).frame(width: 32).accessibilityHidden(true)
          Text("Begge har levert – svarene er låst opp!").font(.subheadline.bold())
          Spacer(minLength: 0)
        }.padding(14).background(SabboStyle.mint.opacity(0.5), in: RoundedRectangle(cornerRadius: 18))
          .overlay { ConfettiBurst(trigger: confetti, intensity: .small).frame(width: 360, height: 360) }
          .accessibilityElement(children: .combine)
          .accessibilityIdentifier("shared-unlock")
      }
    }.task {
      guard model.collectGain(key) else { return }
      visible = true
      do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
      withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { unlocked = true }
      SabboFX.shared.play(.unlock)
      SabboFX.shared.haptic(.success)
      confetti += 1
    }
  }
}

/// Slowly turning light behind an opened chest.
struct ChestRays: View {
  var size: CGFloat = 240
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var turning = false
  var body: some View {
    ZStack {
      ForEach(0..<12, id: \.self) { index in
        Capsule().fill(SabboStyle.gold.opacity(index.isMultiple(of: 2) ? 0.32 : 0.18))
          .frame(width: size * 0.07, height: size * 0.5).offset(y: -size * 0.25)
          .rotationEffect(.degrees(Double(index) * 30))
      }
    }.frame(width: size, height: size)
      .rotationEffect(.degrees(turning ? 360 : 0))
      .animation(reduceMotion || !SabboFX.continuousMotion ? nil : .linear(duration: 16).repeatForever(autoreverses: false), value: turning)
      .onAppear { turning = true }
      .allowsHitTesting(false).accessibilityHidden(true)
  }
}
