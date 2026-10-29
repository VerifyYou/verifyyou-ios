import XCTest

@testable import VerifyYou

final class AppBaseTests: XCTestCase {
    func testAcceptsTheProductionAppBase() {
        XCTAssertTrue(isValidAppBase(VerifyYou.defaultAppBase))
    }

    func testAcceptsAVerifyYouSubdomain() {
        XCTAssertTrue(isValidAppBase(URL(string: "https://staging.verifyyou.com")!))
    }

    func testAcceptsHttpOnlyForALocalDevHost() {
        XCTAssertTrue(isValidAppBase(URL(string: "http://localhost:5173")!))
        XCTAssertFalse(isValidAppBase(URL(string: "http://app.verifyyou.com")!))
    }

    func testRejectsANonVerifyYouOrigin() {
        // Mirrors the web SDK's "rejects an appBase that is not a VerifyYou
        // origin" test (browser-sdk/web/src/client.test.ts).
        XCTAssertFalse(isValidAppBase(URL(string: "https://evil.example.com")!))
    }

    func testInitializeAcceptsAValidAppBase() {
        VerifyYou.initialize(appBase: URL(string: "https://staging.verifyyou.com")!)
        VerifyYou.initialize(appBase: VerifyYou.defaultAppBase) // restore default
    }
}
