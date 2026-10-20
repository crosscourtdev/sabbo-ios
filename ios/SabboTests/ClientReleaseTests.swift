import XCTest
@testable import Sabbo

final class ClientReleaseTests: XCTestCase {
  func testNumericVersionsAndBuilds() {
    let release = ClientRelease(version: "0.10.0", build: "100", platform: "IOS", app_id: "123456789")
    XCTAssertTrue(release.isNewer(thanVersion: "0.9.9", build: "999", platform: "IOS"))
    XCTAssertTrue(release.isNewer(thanVersion: "0.10", build: "99", platform: "IOS"))
    XCTAssertFalse(release.isNewer(thanVersion: "0.10", build: "100", platform: "IOS"))
    XCTAssertFalse(release.isNewer(thanVersion: "0.10", build: "101", platform: "IOS"))
    XCTAssertFalse(release.isNewer(thanVersion: "1.0", build: "1", platform: "IOS"))
    XCTAssertFalse(release.isNewer(thanVersion: "0.9", build: "1", platform: "MAC_OS"))
    XCTAssertFalse(release.isNewer(thanVersion: "", build: "1", platform: "IOS"))
    XCTAssertEqual(release.testFlightURL?.absoluteString, "https://testflight.apple.com/v1/app/123456789")
  }
  func testInvalidReleaseDoesNotOfferUpdate() throws {
    for version in ["", "1..2", "new", "1.2-beta", "1.2.3.4", "99999999999999999999999999999999"] {
      XCTAssertFalse(ClientRelease(version: version, build: "2", platform: "IOS", app_id: "123").isNewer(thanVersion: "0.1", build: "1", platform: "IOS"))
    }
    XCTAssertNil(ClientRelease(version: "2", build: "2", platform: "IOS", app_id: "123/evil").testFlightURL)
    XCTAssertNil(try JSONDecoder().decode(ClientReleaseResponse.self, from: Data("{\"release\":null}".utf8)).release)
  }
}
