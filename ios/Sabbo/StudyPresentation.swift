import SwiftUI

/// Pure presentation rules also support historical question and criterion IDs.
enum StudyPresentation {
  static func belongs(_ criterion: CriterionResult, to part: Question) -> Bool {
    criterion.criterion_id.hasPrefix(part.id + ".")
      || (part.rubric?.criteria.contains { $0.id == criterion.criterion_id } == true)
  }
  static func expectation(_ criterion: CriterionResult, part: Question) -> String {
    if let exact = part.rubric?.criteria.first(where: {
      $0.id == criterion.criterion_id || criterion.criterion_id.hasSuffix("." + $0.id)
    }) { return exact.expectation }
    // Public questions expose ordered expectations, while the rubric stays private.
    if belongs(criterion, to: part), let suffix = criterion.criterion_id.split(separator: ".").last,
       suffix.first == "c", let number = Int(suffix.dropFirst()), number > 0,
       let expectations = part.expectations ?? part.key_points, number <= expectations.count {
      return expectations[number - 1]
    }
    return "Vurderingspunkt"
  }
  static func attainment(_ value: String) -> String {
    switch value {
    case "strong": return "Godt oppfylt"
    case "met": return "Oppfylt"
    case "partial": return "Delvis oppfylt"
    case "missing": return "Ikke vist i svaret"
    default: return "Ikke vurdert"
    }
  }
  static func resumeIndex(parts: [Question], saved: String?, answer: String) -> Int {
    if let saved, let index = parts.firstIndex(where: { $0.id == saved }) { return index }
    let values = AnswerSet.decode(answer)
    return parts.firstIndex { (values[$0.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? 0
  }
  static func paragraphs(_ body: String) -> [String] {
    // Preserve every word; only separate explicitly labelled extracts/examples.
    body.replacingOccurrences(of: #"(?<=\.) (?=(?:[ABC][,:]|[\p{L}]+ \d{4}(?:[–-]\d{4})?:))"#,
      with: "\n\n", options: .regularExpression)
      .components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
  }
  static func sourceTitle(_ source: QuestionSource) -> String {
    if let title = source.title, !title.isEmpty { return title }
    guard let url = URL(string: source.url) else { return "Kilde" }
    let path = url.path
    if path.contains("kompetansemaal") || path.contains("kompetansemaal-og-vurdering") { return "Kompetansemål og vurdering" }
    if path.contains("kjennetegn") { return "Kjennetegn på måloppnåelse" }
    let slug = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
    let name = slug.replacingOccurrences(of: ".html", with: "").replacingOccurrences(of: ".htm", with: "")
      .replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
    return name.isEmpty ? (url.host ?? "Åpne kilde") : name.prefix(1).uppercased() + name.dropFirst()
  }
  static func changedRange(_ text: String, comparedTo other: String) -> Range<String.Index>? {
    guard text != other else { return nil }
    let left = Array(text), right = Array(other)
    var start = 0
    while start < min(left.count, right.count), left[start] == right[start] { start += 1 }
    var end = left.count, otherEnd = right.count
    while end > start, otherEnd > start, left[end - 1] == right[otherEnd - 1] { end -= 1; otherEnd -= 1 }
    return text.index(text.startIndex, offsetBy: start)..<text.index(text.startIndex, offsetBy: end)
  }
}

struct AssessmentSummary: View {
  let result: GradeResult
  var question: Question? = nil
  var showsCriteria = false
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      if !result.strengths.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          Label("Dette fikk du til", systemImage: "checkmark.circle").font(.subheadline.bold())
          Text(result.strengths)
        }
      }
      if !result.improvement.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          Label("Neste steg", systemImage: "arrow.up.right").font(.subheadline.bold())
          Text(result.improvement)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
          .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
      }
      DisclosureGroup("Vurderingsdetaljer") {
        VStack(alignment: .leading, spacing: 14) {
          Text(result.reason)
          if showsCriteria {
            ForEach(result.criteria) { criterion in
              let part = question?.parts?.first { StudyPresentation.belongs(criterion, to: $0) } ?? question
              CriterionFeedback(criterion: criterion, part: part)
            }
          }
        }.padding(.top, 10)
      }.font(.subheadline)
    }.fixedSize(horizontal: false, vertical: true)
  }
}

struct CriterionFeedback: View {
  let criterion: CriterionResult
  let part: Question?
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(part.map { StudyPresentation.expectation(criterion, part: $0) } ?? "Vurderingspunkt").font(.subheadline.bold())
      Label(StudyPresentation.attainment(criterion.attainment), systemImage: symbol)
        .font(.caption.weight(.semibold)).foregroundStyle(criterion.attainment == "strong" || criterion.attainment == "met" ? Color.accentColor : .secondary)
      Text(criterion.comment).font(.subheadline)
      if !criterion.evidence.isEmpty {
        DisclosureGroup("Utdrag fra svaret") {
          Text("«" + criterion.evidence + "»").italic().textSelection(.enabled).padding(.top, 6)
        }.font(.subheadline)
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
  private var symbol: String {
    switch criterion.attainment {
    case "strong", "met": return "checkmark.circle"
    case "partial": return "circle.lefthalf.filled"
    default: return "circle.dashed"
    }
  }
}

struct QuestionNavigator: View {
  let parts: [Question]
  @Binding var selection: Int
  var body: some View {
    if parts.count > 1 {
      Menu {
        Picker("Oppgave", selection: $selection) {
          ForEach(Array(parts.enumerated()), id: \.element.id) { index, part in
            Text("\(index + 1). " + part.displayPrompt).tag(index)
          }
        }
      } label: {
        Label("Velg oppgave · \(selection + 1) av \(parts.count)", systemImage: "list.bullet")
          .frame(minHeight: 44)
      }.accessibilityIdentifier("result-question-picker")
      HStack {
        Button("Forrige oppgave", systemImage: "chevron.left") { selection -= 1 }.disabled(selection == 0)
        Spacer()
        Text("\(selection + 1) av \(parts.count)").font(.subheadline).foregroundStyle(.secondary)
        Spacer()
        Button("Neste oppgave", systemImage: "chevron.right") { selection += 1 }.disabled(selection + 1 >= parts.count)
      }.labelStyle(.iconOnly).buttonStyle(.bordered).frame(minHeight: 44)
    }
  }
}

struct SourceLinks: View {
  let question: Question
  var body: some View {
    if let sources = question.sources, !sources.isEmpty {
      DisclosureGroup("Kilder og videre lesing") {
        ForEach(sources, id: \.url) { source in
          if let url = URL(string: source.url) {
            Link(destination: url) {
              VStack(alignment: .leading, spacing: 3) {
                Text(StudyPresentation.sourceTitle(source))
                Text(url.host ?? "").font(.caption).foregroundStyle(.secondary)
              }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.font(.subheadline)
          }
        }
      }
    }
  }
}
