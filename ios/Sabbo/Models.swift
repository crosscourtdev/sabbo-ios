import Foundation

struct Assignment: Codable, Identifiable {
  let id: String
  let day: String
  let timezone: String
  let question_id: String
  let version: Int
}
struct Question: Codable, Identifiable {
  let id: String
  let version: Int
  let subject_id: String
  let goal_ids: [String]
  let prompt: String
  var task_prompt: String? = nil
  var materials: [QuestionMaterial]? = nil
  var expectations: [String]? = nil
  var displayPrompt: String { task_prompt ?? prompt }
  var voicePracticePrompt: String {
    let task = ([displayPrompt] + (materials ?? []).map { $0.title + "\n" + $0.body })
      .joined(separator: "\n\n")
    return task + "\n\nNår du svarer meg, snakk med tykk norsk østlandsdialekt."
      + "\n\nHjelp meg å forstå oppgaven gjennom samtale, og still ett spørsmål om gangen. Ikke gi meg et ferdig svar. Når vi har diskutert ferdig, be meg si hele svaret mitt høyt med egne ord, som én sammenhengende besvarelse. La meg snakke ferdig før du gir tilbakemelding. Hvis noe viktig mangler, gi meg et lite hint og la meg prøve hele svaret på nytt."
  }
  var parts: [Question]? = nil
  var sources: [QuestionSource]? = nil
  var rubric: QuestionRubric? = nil
  var title: String? = nil
  var example_answer: String? = nil
  var key_points: [String]? = nil
  var guidance: String? = nil
}
struct QuestionMaterial: Codable { let title: String; let body: String }
struct Attempt: Codable, Identifiable {
  let id: String
  let user_id: String
  let assignment_id: String
  let answer: String
  let assessment: String?
  let completed_at: String?
  let assisted: Int
  var receipt_status: String? = nil
  var answers_locked: Bool? = nil
}
struct Draft: Codable {
  var revision: Int? = nil
  let body: String
  let assisted: Int
}
struct Streak: Codable, Identifiable {
  var id: String { user_id }
  let user_id: String
  let name: String
  let current: Int
  let best: Int
  let completed_today: Bool
  let week_days: Int
  let days: [String]
  var epoch: String? = nil
}
struct Today: Codable, Identifiable {
  var id: String { assignment.id }
  let assignment: Assignment
  let question: Question
  let attempt: Attempt?
  let draft: Draft?
  let streaks: [Streak]
  let server_day: String
}
struct QuestionSource: Codable {
  let url: String
  var title: String? = nil
  init(from decoder: Decoder) throws {
    if let value = try? decoder.singleValueContainer().decode(String.self) {
      url = value
    } else {
      let values = try decoder.container(keyedBy: CodingKeys.self)
      url = try values.decode(String.self, forKey: .url)
      title = try values.decodeIfPresent(String.self, forKey: .title)
    }
  }
  enum CodingKeys: String, CodingKey { case url, title }
}
struct QuestionRubric: Codable { let criteria: [RubricCriterion] }
struct RubricCriterion: Codable { let id: String; let expectation: String }
struct Feedback: Codable {
  var parts: [Question]? = nil
  let key_points: [String]
  let example_answer: String
  let guidance: String
}
struct Goal: Codable, Identifiable {
  let id: String
  let order: Int
  let wording: String
  var question_count: Int?
  var practiced_count: Int?
  var covered: Bool?
  var needs_practice: Bool?
}
struct Subject: Codable, Identifiable {
  let id: String
  let label: String
  let name: String
  let source_url: String
  let content_ready: Bool
  let goals: [Goal]
  var enabled: Int?
  var effective_date: String?
}
struct Revision: Codable, Identifiable {
  let id: String
  let answer: String
  let created_at: String
}
struct HistoryItem: Codable, Identifiable {
  let id: String
  let answer: String
  let question: Question
  let assignment_id: String
  let day: String
  let mode: String
  let assessment: String?
  let assisted: Int
  let submitted_at: String
  let revisions: [Revision]
  var evaluations: [Evaluation]? = nil
  var receipt_status: String? = nil
  var answers_locked: Bool? = nil
}
struct PairAnswer: Codable, Identifiable {
  var id: String { user_id }
  let user_id: String
  let author: String
  let original: String
  let revisions: [Revision]
}
struct Comparison: Codable {
  let revealed: Bool
  let answers: [PairAnswer]
}
struct Me: Codable {
  let id: String
  let name: String
  let role: String
  var ai_enabled: Bool? = nil
  var ai_choice_made: Bool? = nil
  let reminder: String
  var streak_reminder: Int? = nil
  var peer_notifications: Int? = nil
  var bonus_notifications: Int? = nil
  let enabled: Int
}
struct AuthConfig: Decodable {
  let issuer: String
  let client_id: String
  let authorization_endpoint: String
  let redirect_uri: String
}
struct AuthResult: Decodable {
  let token: String
  let user_id: String
}
struct Pending: Codable, Identifiable {
  let id: String
  let assignment: Assignment
  let question: Question
  let answer: String
  let assisted: Bool
  let mode: String
  let started_at: String
  var assessment: String?
  var attempt_id: String?
}
struct PendingRevision: Codable, Identifiable {
  let id: String
  let attempt_id: String
  let answer: String
}
struct LocalState: Codable {
  var bonus: BonusState? = nil
  var cosmetics: CosmeticCollection? = nil
  var bonus_clock_offset: Double? = nil
  var progress: PairProgress? = nil
  var saved_days: [Today] = []
  var revisions: [PendingRevision] = []
  var today: Today?
  var drafts: [String: String] = [:]
  var draftSync: [String: DraftSync]? = nil
  var editorPositions: [String: String]? = nil
  var pending: [Pending] = []
  var feedback: [String: Feedback] = [:]
  var subjects: [Subject] = []
  var history: [HistoryItem] = []
}
struct Empty: Decodable {}

struct Evaluation: Codable {
  var id: String? = nil
  var model: String? = nil
  var rubric_version: String? = nil
  var prompt_version: String? = nil
  let status: String
  let result: GradeResult?
}
struct GradeResult: Codable {
  let status: String
  let grade: Int?
  let reason: String
  let strengths: String
  let improvement: String
  let criteria: [CriterionResult]
}
struct CriterionResult: Codable, Identifiable {
  var id: String { criterion_id }
  let criterion_id: String
  let attainment: String
  let evidence: String
  let comment: String
}

struct StreakReward: Identifiable, Equatable {
  let day: Int
  var kind = "fire"
  var isStar: Bool { kind == "stars" }
  var threshold: Int { isStar ? day * 10 : day }
  var id: Int { isStar ? 1000 + day : day }
  static let milestones = [5, 15, 50].map { StreakReward(day: $0) }
  static let starMilestones = [5, 15, 50].map { StreakReward(day: $0, kind: "stars") }
  var title: String { isStar ? "\(threshold) stjerner!" : "\(day) dager på rad!" }
  var unlockLabel: String { isStar ? "\(threshold) stjerner" : "Dag \(day)" }
  var lockedMessage: String { isStar ? "Låses opp ved \(threshold) stjerner." : "Låses opp etter \(day) dager på rad." }
  var message: String {
    ClientProfile.value.rewardMessages[String(day)] ?? "Godt jobbet!"
  }

  func presentation(userID: String?, best: Int) -> RewardPresentation {
    let access: RewardAccess = best >= threshold ? .earned : userID == ClientProfile.ownerID ? .preview : .locked
    return RewardPresentation(reward: self, access: access)
  }
  static func next(best: Int, seen: [Int]) -> StreakReward? {
    milestones.first { $0.day <= best && !seen.contains($0.day) }
  }
}

enum RewardAccess: Equatable { case locked, preview, earned }
struct RewardPresentation: Identifiable {
  let reward: StreakReward
  let access: RewardAccess
  var id: Int { reward.id }
  var revealsMessage: Bool { access != .locked }
}


struct StarAward: Codable, Identifiable {
  var id: String { attempt_id }
  let day: String
  let attempt_id: String
  let grade: Int
  let stars: Int
}
struct Stars: Codable {
  let total: Int
  let epoch: String
  let awards: [StarAward]
}
struct PersonProgress: Codable, Identifiable {
  var id: String { streak.user_id }
  let streak: Streak
  let stars: Stars
  let fire_attempt_id: String?
  var achievements: [Achievement]? = nil
}
struct PairProgress: Codable { let people: [PersonProgress] }
struct SharedSession: Decodable, Identifiable {
  var id: String { assignment.id }
  let assignment: Assignment
  let question: Question
  let comparison: Comparison
}
struct TogetherFeed: Decodable { let sessions: [SharedSession] }


// Display dates always follow the study day in Oslo, regardless of phone locale.
enum StudyText {
  static let oslo = TimeZone(identifier: "Europe/Oslo")!
  static func subject(_ id: String) -> String {
    ["pome": "Politikk og menneskerettigheter", "reli": "Religion og etikk",
     "psyc": "Psykologi 1", "samf": "Samfunnsøkonomi 1"][id] ?? id
  }
  static func reminderDate(hour: Int, minute: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = oslo
    return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
  }
  static func day(_ value: String, weekday: Bool = false) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "nb_NO"); f.timeZone = oslo
    f.dateFormat = "yyyy-MM-dd"
    guard let date = f.date(from: value) else { return value }
    f.dateFormat = weekday ? "EEEE d. MMMM" : "d. MMM yyyy"
    return f.string(from: date)
  }
  static func timestamp(_ value: String) -> String {
    let parser = ISO8601DateFormatter()
    parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let date = parser.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    guard let date else { return day(String(value.prefix(10))) }
    let f = DateFormatter(); f.locale = Locale(identifier: "nb_NO"); f.timeZone = oslo
    f.dateFormat = "d. MMM yyyy · HH:mm"
    return f.string(from: date)
  }
  static func failure(_ error: Error, action: String) -> String {
    if let url = error as? URLError {
      switch url.code {
      case .notConnectedToInternet, .networkConnectionLost:
        return "Ingen forbindelse. " + action + " når du er på nett."
      case .timedOut: return "Det tok for lang tid. " + action + " igjen."
      case .userAuthenticationRequired: return "Logg inn igjen for å fortsette."
      default: break
      }
    }
    return "Noe gikk galt. " + action + " igjen."
  }
  static func evaluation(_ value: Evaluation?) -> String {
    if let grade = value?.result?.grade { return "Karakter \(grade)" }
    if value?.result != nil { return "Se tilbakemelding" }
    switch value?.status {
    case "queued", "processing": return "Vurderes …"
    case "failed", "unavailable", "budget_limited": return "Vurdering utilgjengelig"
    case "disabled", "skipped", "not_requested": return "Ingen vurdering"
    default: return "Se vurdering"
    }
  }
}

struct CosmeticItem: Codable, Identifiable { let id: String; let name: String }
struct EquippedCosmetic: Codable { let user_id: String; let cosmetic_id: String? }
struct CosmeticCollection: Codable {
  let items: [CosmeticItem]
  let owned: [String]
  let people: [EquippedCosmetic]
}
struct BonusState: Codable, Identifiable {
  var id: String? = nil
  let status: String
  let server_now: String
  let day: String
  var cutoff: String? = nil
  var assignment_id: String? = nil
  var question_id: String? = nil
  var question_version: Int? = nil
  var original_attempt_id: String? = nil
  var opens_at: String? = nil
  var expires_at: String? = nil
  var cosmetic_id: String? = nil
  var target_grade: Int? = nil
  var attempt_id: String? = nil
  var grade: Int? = nil
  var answers_locked: Bool? = nil
  static func date(_ value: String?) -> Date? {
    guard let value else { return nil }
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.date(from: value) ?? ISO8601DateFormatter().date(from: value)
  }
}
struct BonusSession: Decodable {
  let round: BonusState
  let assignment: Assignment
  let question: Question
}


struct TimelineBonus: Decodable {
  let status: String
  var target_grade: Int? = nil
  var grade: Int? = nil
  var opens_at: String? = nil
  var expires_at: String? = nil
  var cosmetic_id: String? = nil
  var label: String {
    switch status {
    case "won": return "Tilbehør vunnet"
    case "ready": return "Bonusrunde klar"
    case "waiting", "waiting_grade": return "Bonusrunde senere"
    case "grading": return "Bonus vurderes …"
    case "retry", "grading_failed": return "Bonusrunde · prøv igjen"
    case "too_late": return "Levert etter bonusfristen"
    case "collection_complete": return "Alt tilbehør samlet"
    default: return "Bonusrunde avsluttet"
    }
  }
}
struct TimelinePerson: Decodable, Identifiable {
  var id: String { user_id }
  let user_id: String
  let name: String
  let attempts: [HistoryItem]
  var bonus: TimelineBonus? = nil
  var daily: HistoryItem? { attempts.first { $0.mode == "daily" } }
  var bonusAttempts: [HistoryItem] { attempts.filter { $0.mode == "bonus" } }
}
struct TimelineDay: Decodable, Identifiable {
  var id: String { assignment.id }
  let assignment: Assignment
  let question: Question
  let people: [TimelinePerson]
}
struct TimelineFeed: Decodable { let sessions: [TimelineDay] }

// Presentation policy only. The server must independently authorize every request.
struct ClientProfile: Decodable {
  let ownerID: String
  let learnerID: String
  let ownerName: String
  let learnerName: String
  let ownerAvatar: String
  let learnerAvatar: String
  let rewardAsset: String
  let rewardAccessibilityLabel: String
  let rewardMessages: [String: String]
  static let value: ClientProfile = {
    guard let url = Bundle.main.url(forResource: "profile", withExtension: "json"),
      let data = try? Data(contentsOf: url),
      let profile = try? JSONDecoder().decode(ClientProfile.self, from: data)
    else { fatalError("Missing or invalid client profile") }
    return profile
  }()
  static var ownerID: String { value.ownerID }
  static var learnerID: String { value.learnerID }
  static var ownerName: String { value.ownerName }
  static var learnerName: String { value.learnerName }
}

struct Achievement: Codable, Identifiable {
  let id: String
  let title: String
  let description: String
  let target: Int
  let progress: Int
  let stars: Int
  let symbol: String
  let earned_at: String?
  let attempt_id: String?
  var earned: Bool { earned_at != nil }
}
