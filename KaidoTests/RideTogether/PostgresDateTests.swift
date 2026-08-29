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
        XCTAssertNotNil(PostgresDate.parse("2026-08-09T02:15:30.123Z"))
    }

    func testParsesOffsetLessUTCFormat() {
        // What supabase-swift's default JSONEncoder actually produces for a bare `Date` embedded
        // in an arbitrary JSON payload — e.g. `GroupRideRouteSnapshot.capturedAt` inside the
        // opaque `route_snapshot` jsonb blob, which isn't a real timestamptz column that Postgres
        // would normalize. No offset, but the encoder always renders in UTC.
        XCTAssertNotNil(PostgresDate.parse("2026-08-10T19:55:37.760"))
    }

    func testRejectsGarbage() {
        XCTAssertNil(PostgresDate.parse("not a date"))
    }
}
