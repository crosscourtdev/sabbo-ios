import SwiftUI

struct NewsFeed: Codable {
  let items: [NewsItem]
}
struct NewsItem: Codable, Identifiable {
  let id: String
  let published_on: String
  let title: String
  let body: String
  var starts_on: String? = nil
  var ends_on: String? = nil
}

extension AppModel {
  func refreshNews() async {
    guard !testing, let account = session else { return }
    do {
      let feed: NewsFeed = try await API(token: account.token).get("/news")
      guard session?.token == account.token else { return }
      local.news = feed
      persist()
    } catch {
      // Keep the last successful feed available offline; news never blocks study.
    }
  }
}

struct NewsView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @State private var loading = true
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          if let feed = model.local.news, !feed.items.isEmpty {
            ForEach(feed.items) { item in
              VStack(alignment: .leading, spacing: 12) {
                Text(StudyText.day(item.published_on)).font(.caption).foregroundStyle(.secondary)
                Text(item.title).font(.system(.title2, design: .rounded, weight: .bold))
                  .accessibilityAddTraits(.isHeader)
                Text(item.body).font(.body).fixedSize(horizontal: false, vertical: true)
              }.frame(maxWidth: .infinity, alignment: .leading).padding(22)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
            }
          } else if loading {
            ProgressView("Henter nyheter …").frame(maxWidth: .infinity)
          } else {
            ContentUnavailableView("Ingen nyheter å vise", systemImage: "newspaper",
              description: Text("Koble til nettet og prøv igjen."))
            Button("Prøv igjen") { Task { loading = true; await model.refreshNews(); loading = false } }
              .buttonStyle(PlayButton())
          }
        }.padding(22).frame(maxWidth: 620).frame(maxWidth: .infinity)
      }.background(Color(.systemGroupedBackground)).navigationTitle("Nyheter")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Ferdig") { dismiss() }.accessibilityIdentifier("news-done") } }
        .refreshable { await model.refreshNews() }
        .task { await model.refreshNews(); loading = false }
    }.desktopSheet().accessibilityIdentifier("news-view")
  }
}
