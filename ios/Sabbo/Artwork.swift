import CryptoKit
import Foundation
import SwiftUI

struct AssignmentArtwork: Codable {
  let images: [ArtworkImage]
}
struct ArtworkImage: Codable {
  let question_id: String
  let sha256: String
  let path: String

  func valid(for assignment: String) -> Bool {
    sha256.count == 64 && sha256.allSatisfy { "0123456789abcdef".contains($0) }
      && path == "/assignments/\(assignment)/artwork/\(sha256).jpg"
  }
  func matches(_ data: Data) -> Bool {
    data.count <= 1_000_000 && Self.hash(data) == sha256
  }
  static func hash(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

private struct ArtworkAssignmentKey: EnvironmentKey { static let defaultValue: String? = nil }
extension EnvironmentValues {
  var artworkAssignmentID: String? {
    get { self[ArtworkAssignmentKey.self] }
    set { self[ArtworkAssignmentKey.self] = newValue }
  }
}

// Authenticated downloads never follow a redirect or enter a shared URL cache.
private final class ArtworkTransport: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  func urlSession(_ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

actor ArtworkCache {
  static let shared = ArtworkCache()
  private let transport = ArtworkTransport()
  private lazy var network: URLSession = {
    let config = URLSessionConfiguration.ephemeral
    config.urlCache = nil
    config.timeoutIntervalForRequest = 12
    config.timeoutIntervalForResource = 20
    return URLSession(configuration: config, delegate: transport, delegateQueue: nil)
  }()

  func image(api: API, account: String, assignment: String, question: String) async -> Data? {
    guard let token = api.token, !token.isEmpty else { return nil }
    let manager = FileManager.default
    guard let caches = manager.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
    let root = caches.appendingPathComponent("question-artwork", isDirectory: true)
    let scope = ArtworkImage.hash(Data((api.base.absoluteString + "|" + account).utf8))
    let folder = root.appendingPathComponent(scope, isDirectory: true)
    try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
    let manifestFile = folder.appendingPathComponent(ArtworkImage.hash(Data(assignment.utf8)) + ".json")
    var manifest: AssignmentArtwork?
    do {
      let received: AssignmentArtwork = try await api.get("/assignments/" + assignment + "/artwork")
      guard received.images.allSatisfy({ $0.valid(for: assignment) }) else { return nil }
      manifest = received
      // Preserve a previously downloaded manifest through an offline/server outage.
      try? JSONEncoder().encode(received).write(to: manifestFile, options: .atomic)
    } catch {
      let failure = error as NSError
      if (failure.domain == NSURLErrorDomain && failure.code == NSURLErrorUserAuthenticationRequired)
        || (failure.domain == "Sabbo" && [403, 404].contains(failure.code)) { return nil }
      if let data = try? Data(contentsOf: manifestFile) { manifest = try? JSONDecoder().decode(AssignmentArtwork.self, from: data) }
    }
    guard !Task.isCancelled, let entry = manifest?.images.first(where: { $0.question_id == question }),
      entry.valid(for: assignment) else { return nil }
    let file = folder.appendingPathComponent(entry.sha256 + ".jpg")
    if let saved = try? Data(contentsOf: file), entry.matches(saved) { return saved }
    guard let url = URL(string: entry.path, relativeTo: api.base)?.absoluteURL,
      url.scheme == "https", url.host == api.base.host, url.port == api.base.port else { return nil }
    var request = URLRequest(url: url)
    request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
    do {
      let (bytes, response) = try await network.bytes(for: request)
      guard let http = response as? HTTPURLResponse, http.statusCode == 200,
        response.mimeType == "image/jpeg", response.expectedContentLength <= 1_000_000 else { return nil }
      var data = Data()
      for try await byte in bytes {
        guard data.count < 1_000_000, !Task.isCancelled else { return nil }
        data.append(byte)
      }
      guard entry.matches(data) else { return nil }
      try? data.write(to: file, options: .atomic)
      trim(root)
      return data
    } catch { return nil }
  }

  private func trim(_ root: URL) {
    let manager = FileManager.default
    guard let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else { return }
    let files = enumerator.compactMap { $0 as? URL }.filter { ["jpg", "json"].contains($0.pathExtension) }
      .compactMap { url -> (URL, Int, Date)? in
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
        return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
      }.sorted { $0.2 < $1.2 }
    var total = files.reduce(0) { $0 + $1.1 }
    for file in files where total > 100_000_000 {
      try? manager.removeItem(at: file.0)
      total -= file.1
    }
  }
}
