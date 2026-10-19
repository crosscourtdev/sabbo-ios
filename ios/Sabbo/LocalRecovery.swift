import Foundation

/// Preserve the exact pre-upgrade bytes before decoding, syncing or saving.
/// Recovery files are never rotated or replaced automatically.
enum LocalRecovery {
  static func snapshotURL(for file: URL) -> URL {
    file.deletingLastPathComponent().appendingPathComponent("Recovery", isDirectory: true)
      .appendingPathComponent("before-achievements-v1-" + file.lastPathComponent)
  }
  static func preserve(_ file: URL) throws {
    let fm = FileManager.default
    guard fm.fileExists(atPath: file.path) else { return }
    let copy = snapshotURL(for: file)
    guard !fm.fileExists(atPath: copy.path) else { return }
    try fm.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
    let staging = copy.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".tmp")
    defer { try? fm.removeItem(at: staging) }
    try Data(contentsOf: file).write(to: staging, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    try fm.moveItem(at: staging, to: copy)
  }
  static func load(_ file: URL) throws -> LocalState {
    try preserve(file)
    return try JSONDecoder().decode(LocalState.self, from: Data(contentsOf: file))
  }
  static func export(_ file: URL) throws -> Data {
    try preserve(file)
    let files = try [snapshotURL(for: file), file].filter { FileManager.default.fileExists(atPath: $0.path) }.map { url in
      ["name": url.lastPathComponent, "data_base64": try Data(contentsOf: url).base64EncodedString()]
    }
    return try JSONSerialization.data(withJSONObject: ["format": "sabbo-local-recovery", "version": 1, "files": files], options: [.prettyPrinted, .sortedKeys])
  }
}
