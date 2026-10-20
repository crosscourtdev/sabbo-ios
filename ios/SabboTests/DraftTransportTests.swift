import XCTest
@testable import Sabbo

private final class DraftServer: @unchecked Sendable {
  let lock = NSLock()
  var day: Today
  var body = ""
  var revision = 0
  var receipts: [String: (Int, String)] = [:]
  var failNextSave = false
  var saveObserved: (() -> Void)?
  init(day: Today) { self.day = day }
  func respond(_ request: URLRequest) throws -> (Data, Bool) {
    lock.lock(); defer { lock.unlock() }
    if request.httpMethod == "PUT" {
      var data = request.httpBody ?? Data()
      if data.isEmpty, let stream = request.httpBodyStream {
        stream.open(); defer { stream.close() }
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
          let count = stream.read(&buffer, maxLength: buffer.count)
          if count <= 0 { break }; data.append(contentsOf: buffer.prefix(count))
        }
      }
      let value = try JSONSerialization.jsonObject(with: data) as! [String: Any]
      let id = value["mutation_id"] as! String, text = value["body"] as! String
      let base = value["base_revision"] as! Int
      var accepted: (Int, String)? = receipts[id]
      if accepted == nil, base == revision {
        revision += 1; body = text; accepted = (revision, text); receipts[id] = accepted
        saveObserved?()
      }
      let fail = failNextSave; failNextSave = false
      return (try JSONSerialization.data(withJSONObject: [
        "saved": accepted != nil, "submitted": false, "conflict": accepted == nil,
        "draft": ["revision": accepted?.0 ?? revision, "body": accepted?.1 ?? body, "assisted": 0]
      ]), fail)
    }
    let fresh = Today(assignment: day.assignment, question: day.question, attempt: nil,
      draft: revision == 0 ? nil : Draft(revision: revision, body: body, assisted: 0), streaks: [], server_day: day.server_day)
    return (try JSONEncoder().encode(fresh), false)
  }
}
private final class DraftProtocol: URLProtocol, @unchecked Sendable {
  static var server: DraftServer!
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    do {
      let (data, fail) = try Self.server.respond(request)
      // Delay the acknowledgement so more typing can happen after acceptance.
      DispatchQueue.global().asyncAfter(deadline: .now() + (request.httpMethod == "PUT" ? 0.2 : 0)) { [self] in
        if fail { client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost)); return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200,
          httpVersion: nil, headerFields: ["Content-Type":"application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
      }
    } catch { client?.urlProtocol(self, didFailWithError: error) }
  }
  override func stopLoading() {}
}

@MainActor final class DraftTransportTests: XCTestCase {
  private var models: [AppModel] = []
  private var network: URLSession!
  private var day: Today!
  override func setUp() async throws {
    let question = Question(id: "sample", version: 1, subject_id: "sample", goal_ids: [], prompt: "Sample")
    day = Today(assignment: Assignment(id: "day-one", day: "2026-01-01", timezone: "Europe/Oslo", question_id: question.id, version: 1),
      question: question, attempt: nil, draft: nil, streaks: [], server_day: "2026-01-01")
    DraftProtocol.server = DraftServer(day: day)
    let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [DraftProtocol.self]
    network = URLSession(configuration: config)
  }
  override func tearDown() async throws {
    for model in models {
      for worker in model.draftWorkers.values { await worker.value }
      if let file = model.file() {
        try? FileManager.default.removeItem(at: file)
        try? FileManager.default.removeItem(at: LocalRecovery.snapshotURL(for: file))
      }
      model.session = nil
    }
    models = []; network.invalidateAndCancel()
  }
  private func model(user: String = UUID().uuidString) -> AppModel {
    let model = AppModel(); model.session = Session(token: "fixture", user_id: "sync-test-" + user)
    model.restore(); model.local.today = day
    model.draftAPIOverride = API(base: URL(string: "https://draft.example.invalid")!, token: "fixture", transport: network)
    models.append(model); return model
  }
  func testTypingDoesNotCancelAcceptedSaveAndLatestTextDrains() async throws {
    let phone = model()
    let accepted = expectation(description: "first save accepted")
    DraftProtocol.server.saveObserved = { accepted.fulfill(); DraftProtocol.server.saveObserved = nil }
    phone.edit("First paragraph")
    await fulfillment(of: [accepted], timeout: 5)
    phone.edit("First paragraph and the rest of my answer")
    await phone.syncCurrentDraft()
    XCTAssertEqual(DraftProtocol.server.body, "First paragraph and the rest of my answer")
    XCTAssertEqual(DraftProtocol.server.revision, 2)
    XCTAssertNil(phone.local.draftSync?[day.id]?.conflict)
    XCTAssertNil(phone.local.draftSync?[day.id]?.write)
  }
  func testRelaunchRecoversAcceptedWriteAndKeepsTypingAfterLostResponse() async throws {
    let phone = model()
    phone.local.drafts[day.id] = "First paragraph"
    DraftProtocol.server.failNextSave = true
    await phone.syncCurrentDraft()
    XCTAssertEqual(DraftProtocol.server.body, "First paragraph")
    XCTAssertNotNil(phone.local.draftSync?[day.id]?.write)
    phone.local.drafts[day.id] = "Full answer after the lost response"
    XCTAssertTrue(phone.persist())
    let relaunched = model(user: String(phone.session!.user_id.dropFirst("sync-test-".count)))
    relaunched.restore()
    await relaunched.syncCurrentDraft()
    XCTAssertEqual(DraftProtocol.server.body, "Full answer after the lost response")
    XCTAssertEqual(DraftProtocol.server.revision, 2)
    XCTAssertNil(relaunched.local.draftSync?[day.id]?.conflict)
  }
  func testTwoClientsMergeDifferentQuestionsAndKeepOldDayAcrossMidnight() async throws {
    let phone = model(), mac = model()
    let base = DraftSync.encode(["q1":"One", "q2":"Two"])
    phone.local.drafts[day.id] = base; await phone.syncCurrentDraft(); await mac.syncCurrentDraft()
    phone.local.drafts[day.id] = DraftSync.encode(["q1":"Phone", "q2":"Two"])
    mac.local.drafts[day.id] = DraftSync.encode(["q1":"One", "q2":"Mac"])
    await mac.syncCurrentDraft(); await phone.syncCurrentDraft(); await mac.syncCurrentDraft()
    let expected = ["q1":"Phone", "q2":"Mac"]
    XCTAssertEqual(DraftSync.parts(DraftProtocol.server.body), expected)
    XCTAssertEqual(DraftSync.parts(mac.local.drafts[day.id]!), expected)
    XCTAssertNil(phone.local.draftSync?[day.id]?.conflict)
    phone.local.today = Today(assignment: Assignment(id: "day-two", day: "2026-01-02", timezone: "Europe/Oslo", question_id: "sample", version: 1),
      question: day.question, attempt: nil, draft: nil, streaks: [], server_day: "2026-01-02")
    phone.local.drafts[day.id] = DraftSync.encode(["q1":"Recovered old answer", "q2":"Mac"])
    await phone.syncDraft(day)
    XCTAssertEqual(phone.local.today?.id, "day-two")
    XCTAssertEqual(DraftSync.parts(DraftProtocol.server.body)["q1"], "Recovered old answer")
    XCTAssertNil(phone.local.drafts["day-two"])
  }
}
