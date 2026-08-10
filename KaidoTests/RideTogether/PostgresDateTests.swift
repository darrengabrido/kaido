@testable import Kaido
import XCTest

final class PostgresDateTests: XCTestCase {
    func testParsesMicrosecondPrecision() {
        // What Postgres's `now()` actually produces most of the time — 6 fractional digits.
        XCTAssertNotNil(PostgresDate.parse("2026-08-09T02:15:30.123456+00:00"))
    }

    func testParsesSingleDigitFraction() {
        // Postgres trims trailing zeros, so 1-5 digit fractions are just as common as 6.
        XCTAssertNotNil(PostgresDate.parse("2026-08-09T02:15:30.5+00:00"))
    }

    func testParsesWholeSecond() {
        XCTAssertNotNil(PostgresDate.parse("2026-08-09T02:15:30+00:00"))
    }

    func testParsesExactlyMillisecondPrecision() {
        XCTAssertNotNil(PostgresDate.parse("2026-08-09T02:15:30.123+00:00"))
    }

    func testParsesZuluSuffix() {
        // What this app's own wireEncoder produces when round-tripping capturedAt.
        XCTAssertNotNil(PostgresDate.parse("2026-08-09T02:15:30.123Z"))
    }

    func testRejectsGarbage() {
        XCTAssertNil(PostgresDate.parse("not a date"))
    }
}
