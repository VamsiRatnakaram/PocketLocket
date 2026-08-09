import XCTest
@testable import PocketLocket

final class SupportEmailTests: XCTestCase {
    func testSupportURLPrefillsRecipientAndDiagnosticDetails() throws {
        let url = try XCTUnwrap(
            SupportEmail.url(version: "1.0", build: "7", operatingSystem: "iOS 26.5")
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.scheme, "mailto")
        XCTAssertEqual(components.path, "vamsiratnakaram@gmail.com")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "subject" })?.value, "PocketLocket Support Request")

        let body = components.queryItems?.first(where: { $0.name == "body" })?.value
        XCTAssertTrue(body?.contains("App version: 1.0 (7)") == true)
        XCTAssertTrue(body?.contains("SimpleFIN setup tokens") == true)
    }
}