import SwiftUI

private struct LearnerPracticeReport: Decodable {
  struct Submission: Decodable, Identifiable {
    let id, title, prompt, answer, closed, status: String
    let result: GradeResult?
    let previous_grade: Int?

    var gradeText: String {
      if let grade = result?.grade { return "Karakter \(grade)" }
      if ["queued", "processing"].contains(status) { return "Vurderes" }
      return "Uten karakter"
    }
  }
  let today, practiced, total: Int
  let answers: [Submission]
}

struct LearnerPracticeHistory: View {
  @EnvironmentObject var model: AppModel
  @State private var report: LearnerPracticeReport?
  @State private var failed = false

  var body: some View {
    List {
      if model.session?.user_id == ClientProfile.ownerID {
        if failed {
          Button("Kunne ikke hente øvingssvar. Prøv igjen") { Task { await load() } }
        }
        if let report {
          Section("Øving") {
            LabeledContent("Svar i dag", value: String(report.today))
            LabeledContent("Oppgaver øvd", value: "\(report.practiced) av \(report.total)")
            LabeledContent("Ikke prøvd", value: String(report.total - report.practiced))
          }
          Section("Innleverte svar") {
            if report.answers.isEmpty { Text("Ingen svar levert ennå.").foregroundStyle(.secondary) }
            ForEach(report.answers) { submission in
              DisclosureGroup {
                VStack(alignment: .leading, spacing: 12) {
                  Text(submission.prompt)
                  Text("Innlevert svar").font(.headline)
                  Text(submission.answer)
                  if let result = submission.result {
                    AssessmentSummary(result: result, showsCriteria: true)
                  }
                }.padding(.vertical, 8)
              } label: {
                VStack(alignment: .leading, spacing: 4) {
                  Text(submission.title).font(.headline)
                  Text(StudyText.timestamp(submission.closed)).font(.caption).foregroundStyle(.secondary)
                  if let previous = submission.previous_grade {
                    Text("\(submission.gradeText) · Forrige karakter \(previous)").font(.subheadline)
                  } else { Text(submission.gradeText).font(.subheadline) }
                }
              }
            }
          }
        } else if !failed { ProgressView() }
      }
    }
    .navigationTitle("Øvingssvar")
    .task(id: model.session?.user_id) { report = nil; await load() }
    .refreshable { await load() }
  }

  @MainActor private func load() async {
    guard model.session?.user_id == ClientProfile.ownerID else { return }
    do {
      let response: LearnerPracticeReport = try await model.api.get("/exam/practice/learner-history")
      guard !Task.isCancelled, model.session?.user_id == ClientProfile.ownerID else { return }
      report = response
      failed = false
    } catch {
      if !Task.isCancelled { failed = true }
    }
  }
}
