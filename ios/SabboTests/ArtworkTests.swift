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
