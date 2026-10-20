import Foundation
import SwiftUI

struct ClientReleaseResponse: Decodable {
  let release: ClientRelease?
}

struct ClientRelease: Decodable, Equatable {
  let version: String
  let build: String
  let platform: String
  let app_id: String

  static var currentPlatform: String {
    #if targetEnvironment(macCatalyst)
    return "MAC_OS"
    #else
    return "IOS"
    #endif
  }
  static func numbers(_ value: String) -> [UInt64]? {
    let parts = value.split(separator: ".", omittingEmptySubsequences: false)
    guard !parts.isEmpty, parts.count <= 3, value.count <= 32 else { return nil }
    var result: [UInt64] = []
    for part in parts {
      guard !part.isEmpty, part.allSatisfy({ $0 >= "0" && $0 <= "9" }), let n = UInt64(part) else { return nil }
      result.append(n)
    }
    return result + Array(repeating: 0, count: 3 - result.count)
  }
  var testFlightURL: URL? {
    guard (1...20).contains(app_id.count), app_id.allSatisfy({ $0 >= "0" && $0 <= "9" }) else { return nil }
    return URL(string: "https://testflight.apple.com/v1/app/" + app_id)
  }
  var key: String { "\(platform):\(version):\(build)" }
  func isNewer(thanVersion installedVersion: String, build installedBuild: String, platform installedPlatform: String) -> Bool {
    guard platform == installedPlatform, testFlightURL != nil,
          let latest = Self.numbers(version), let installed = Self.numbers(installedVersion),
          let latestBuild = Self.numbers(build), let currentBuild = Self.numbers(installedBuild) else { return false }
    return installed.lexicographicallyPrecedes(latest)
      || (latest == installed && currentBuild.lexicographicallyPrecedes(latestBuild))
  }
}

extension AppModel {
  func checkForUpdate() async {
    guard !testing, let account = session, !checkingRelease,
          Date().timeIntervalSince(lastReleaseCheck) >= 900 else { return }
    checkingRelease = true
    lastReleaseCheck = Date()
    defer { checkingRelease = false }
    do {
      let response: ClientReleaseResponse = try await api.get("/client-release?platform=" + ClientRelease.currentPlatform)
      guard session?.token == account.token else { return }
      let release = response.release
      availableRelease = release?.isNewer(
        thanVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
        build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
        platform: ClientRelease.currentPlatform) == true ? release : nil
    } catch {
      // Release discovery is optional and never interrupts saving or studying.
      availableRelease = nil
    }
  }
}

struct ClientUpdateNotice: View {
  @EnvironmentObject var model: AppModel
  @State private var dismissed: String?
  var body: some View {
    if let release = model.availableRelease, dismissed != release.key, let url = release.testFlightURL {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: "arrow.down.app.fill").font(.title2).foregroundStyle(Color("AccentColor"))
        VStack(alignment: .leading, spacing: 6) {
          Text("Oppdatering tilgjengelig").font(.headline)
          Text("Versjon \(release.version) er klar i TestFlight.").font(.subheadline).foregroundStyle(.secondary)
          Link("Åpne TestFlight", destination: url).font(.subheadline.bold()).accessibilityIdentifier("open-testflight")
        }
        Spacer(minLength: 0)
        Button { dismissed = release.key } label: {
          Image(systemName: "xmark").frame(width: 44, height: 44)
        }.buttonStyle(.plain).foregroundStyle(.secondary)
          .accessibilityLabel("Skjul oppdatering").accessibilityIdentifier("dismiss-update")
      }.padding(16).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }
  }
}
