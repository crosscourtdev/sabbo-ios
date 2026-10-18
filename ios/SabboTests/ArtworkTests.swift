import XCTest
@testable import Sabbo

final class ArtworkTests: XCTestCase {
  func testArtworkMustBeBoundToExactAssignmentAndHash() {
    let data = Data("test image".utf8)
    let sha = ArtworkImage.hash(data)
    let entry = ArtworkImage(question_id: "demo", sha256: sha, path: "/assignments/today/artwork/\(sha).jpg")
    XCTAssertTrue(entry.valid(for: "today"))
    XCTAssertFalse(entry.valid(for: "yesterday"))
    XCTAssertTrue(entry.matches(data))
    XCTAssertFalse(entry.matches(Data("corrupt".utf8)))
    XCTAssertFalse(ArtworkImage(question_id: "demo", sha256: sha, path: "https://other.invalid/image.jpg").valid(for: "today"))
    XCTAssertFalse(ArtworkImage(question_id: "demo", sha256: "../bad", path: "/assignments/today/artwork/../bad.jpg").valid(for: "today"))
  }
  func testOversizedArtworkIsRejectedEvenWithMatchingHash() {
    let data = Data(repeating: 0, count: 1_000_001)
    let entry = ArtworkImage(question_id: "demo", sha256: ArtworkImage.hash(data), path: "")
    XCTAssertFalse(entry.matches(data))
  }
}

private final class ArtworkURLProtocol: URLProtocol, @unchecked Sendable {
  static var responses: [String: (Int, Data)] = [:]
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    guard request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture",
      let url = request.url, let value = Self.responses[url.path] else {
      client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return
    }
    let response = HTTPURLResponse(url: url, statusCode: value.0, httpVersion: nil,
      headerFields: ["Content-Type": url.path.hasSuffix(".jpg") ? "image/jpeg" : "application/json"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: value.1)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

extension ArtworkTests {
  func testDownloadOfflineCacheAccountIsolationAndRevocation() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root); ArtworkURLProtocol.responses = [:] }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ArtworkURLProtocol.self]
    let cache = ArtworkCache(network: URLSession(configuration: configuration), root: root)
    let bytes = Data([255, 216, 255, 1, 255, 217])
    let hash = ArtworkImage.hash(bytes)
    let path = "/assignments/day/artwork/\(hash).jpg"
    let manifest = AssignmentArtwork(images: [ArtworkImage(question_id: "question", sha256: hash, path: path)])
    ArtworkURLProtocol.responses = ["/assignments/day/artwork": (200, try JSONEncoder().encode(manifest)), path: (200, bytes)]
    let api = API(token: "fixture")
    let online = await cache.image(api: api, account: "learner", assignment: "day", question: "question")
    XCTAssertEqual(online, bytes)
    ArtworkURLProtocol.responses = [:]
    let offline = await cache.image(api: api, account: "learner", assignment: "day", question: "question")
    XCTAssertEqual(offline, bytes)
    let otherAccount = await cache.image(api: api, account: "owner", assignment: "day", question: "question")
    XCTAssertNil(otherAccount)
    let otherDay = await cache.image(api: api, account: "learner", assignment: "another-day", question: "question")
    XCTAssertNil(otherDay)
    ArtworkURLProtocol.responses = ["/assignments/day/artwork": (401, Data())]
    let revoked = await cache.image(api: api, account: "learner", assignment: "day", question: "question")
    XCTAssertNil(revoked)
  }
}
