import XCTest

@testable import VerifyYou

final class BridgeTests: XCTestCase {
    private func query(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    func testHostURLPointsAtTheHostPageOnTheAppBaseOrigin() {
        let url = hostURL(
            appBase: URL(string: "https://dev.app.verifyyou.com/some/path?x=1")!, session: "sess_123",
            theme: "dark")!
        XCTAssertEqual(url.host, "dev.app.verifyyou.com")
        XCTAssertEqual(url.path, "/native.html")
        XCTAssertEqual(query(url), ["vys": "sess_123", "vy_bridge": "1", "theme": "dark"])
    }

    func testHostURLKeepsALocalDevPort() {
        let url = hostURL(
            appBase: URL(string: "https://192.168.1.7:5173")!, session: "s", theme: "light")!
        XCTAssertEqual(url.port, 5173)
    }

    func testHostURLEncodesAPlusInTheSession() {
        let url = hostURL(appBase: VerifyYou.defaultAppBase, session: "a+b", theme: "light")!
        XCTAssertTrue(url.absoluteString.contains("vys=a%2Bb"))
    }

    func testHostURLRoundTripsAnAwkwardSession() {
        let session = "a&b#c%d=e f+g"
        let url = hostURL(appBase: VerifyYou.defaultAppBase, session: session, theme: "light")!
        XCTAssertNil(url.fragment)
        XCTAssertEqual(query(url), ["vys": session, "vy_bridge": "1", "theme": "light"])
        XCTAssertFalse(url.absoluteString.contains("&b"))
    }

    func testSameOriginMatchesSchemeHostAndPort() {
        let url = URL(string: "https://app.verifyyou.com")!
        XCTAssertTrue(isSameOrigin(scheme: "https", host: "app.verifyyou.com", port: 0, as: url))
        XCTAssertTrue(isSameOrigin(scheme: "https", host: "app.verifyyou.com", port: nil, as: url))
        XCTAssertFalse(isSameOrigin(scheme: "http", host: "app.verifyyou.com", port: 0, as: url))
        XCTAssertFalse(isSameOrigin(scheme: "https", host: "other.verifyyou.com", port: 0, as: url))
        XCTAssertFalse(isSameOrigin(scheme: "https", host: "app.verifyyou.com", port: 8443, as: url))
    }

    func testSameOriginTreatsADefaultPortAsItsExplicitForm() {
        XCTAssertTrue(
            isSameOrigin(
                scheme: "https", host: "app.verifyyou.com", port: 0,
                as: URL(string: "https://app.verifyyou.com:443")!))
        XCTAssertTrue(
            isSameOrigin(
                scheme: "http", host: "localhost", port: 80, as: URL(string: "http://localhost")!))
        XCTAssertFalse(
            isSameOrigin(
                scheme: "https", host: "app.verifyyou.com", port: 80,
                as: URL(string: "https://app.verifyyou.com")!))
    }

    func testSameOriginKeepsAnExplicitPortAndIgnoresHostCase() {
        let url = URL(string: "https://192.168.1.7:5173")!
        XCTAssertTrue(isSameOrigin(scheme: "https", host: "192.168.1.7", port: 5173, as: url))
        XCTAssertFalse(isSameOrigin(scheme: "https", host: "192.168.1.7", port: 5174, as: url))
        XCTAssertFalse(isSameOrigin(scheme: "https", host: "192.168.1.7", port: 0, as: url))
        XCTAssertTrue(
            isSameOrigin(
                scheme: "HTTPS", host: "app.verifyyou.com", port: 0,
                as: URL(string: "https://App.VerifyYou.com")!))
    }

    func testSameOriginRefusesAnOriginWithNoHost() {
        let url = URL(string: "https://app.verifyyou.com")!
        XCTAssertFalse(isSameOrigin(scheme: "about", host: "", port: 0, as: url))
        XCTAssertFalse(isSameOrigin(scheme: nil, host: nil, port: nil, as: url))
        XCTAssertFalse(isSameOrigin(scheme: "https", host: "", port: 0, as: URL(string: "about:blank")!))
    }

    func testParsesACompletedRun() {
        XCTAssertEqual(
            parseBridgeMessage(#"{"type":"vy:complete","token":"tok_1","verified":true,"vyc":"1"}"#),
            .complete(VyResult(token: "tok_1", verified: true, vyc: "1")))
    }

    func testParsesADeniedRunAsComplete() {
        XCTAssertEqual(
            parseBridgeMessage(#"{"type":"vy:complete","token":"tok_2","verified":false,"vyc":"0"}"#),
            .complete(VyResult(token: "tok_2", verified: false, vyc: "0")))
    }

    func testParsesReadyCloseAndError() {
        XCTAssertEqual(parseBridgeMessage(#"{"type":"vy:ready"}"#), .ready)
        XCTAssertEqual(parseBridgeMessage(#"{"type":"vy:close"}"#), .close)
        XCTAssertEqual(
            parseBridgeMessage(#"{"type":"vy:error","message":"VerifyYou: boom"}"#), .error("VerifyYou: boom"))
    }

    func testIgnoresUnknownOrMalformedMessages() {
        XCTAssertNil(parseBridgeMessage(#"{"type":"vy:something-newer"}"#))
        XCTAssertNil(parseBridgeMessage("not json"))
        XCTAssertNil(parseBridgeMessage(42))
    }

    func testVygetIsEmptyBeforeAnyRun() {
        XCTAssertEqual(VerifyYou.vyget(), .empty)
    }
}
