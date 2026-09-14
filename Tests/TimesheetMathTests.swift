import XCTest
@testable import Yucca

final class TimesheetMathTests: XCTestCase {
    private var berlin: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    func testLuccaDurations() {
        XCTAssertEqual(TimesheetMath.seconds(fromLuccaDuration: "03:45:00"), 13_500)
        XCTAssertEqual(TimesheetMath.seconds(fromLuccaDuration: "1.01:02:03"), 90_123)
        XCTAssertEqual(TimesheetMath.luccaDuration(from: 13_501.9), "03:45:01")
    }

    func testFloatingDateRoundTripUsesTenantLocalShape() throws {
        let date = try XCTUnwrap(berlin.date(from: DateComponents(
            year: 2026, month: 9, day: 12, hour: 8, minute: 4, second: 9
        )))
        let encoded = LuccaDateCodec.string(from: date, calendar: berlin)
        XCTAssertEqual(encoded, "2026-09-12T08:04:09")
        XCTAssertEqual(LuccaDateCodec.date(from: encoded, calendar: berlin), date)
    }

    func testSnapshotIncludesElapsedActiveEntry() throws {
        let now = try XCTUnwrap(berlin.date(from: DateComponents(
            year: 2026, month: 9, day: 9, hour: 11
        )))
        let completed = TimeEntry(
            id: 1, ownerId: 7, unit: 2,
            startsAt: "2026-09-08T09:00:00", duration: "08:00:00",
            endsAt: "2026-09-08T17:00:00", archivedAt: nil, creationSource: 2
        )
        let active = TimeEntry(
            id: 2, ownerId: 7, unit: 2,
            startsAt: "2026-09-09T09:30:00", duration: "00:00:00",
            endsAt: nil, archivedAt: nil, creationSource: 4
        )
        let snapshot = TimesheetMath.snapshot(entries: [completed, active], now: now, calendar: berlin)
        XCTAssertTrue(snapshot.isClockedIn)
        XCTAssertEqual(snapshot.todaySeconds, 5_400)
        XCTAssertEqual(snapshot.weekSeconds, 34_200)
    }

    func testPreviousDayZeroEntryIsNotActive() throws {
        let now = try XCTUnwrap(berlin.date(from: DateComponents(
            year: 2026, month: 9, day: 9, hour: 8
        )))
        let old = TimeEntry(
            id: 3, ownerId: 7, unit: 2,
            startsAt: "2026-09-08T18:00:00", duration: "00:00:00",
            endsAt: nil, archivedAt: nil, creationSource: 4
        )
        XCTAssertNil(TimesheetMath.activeEntry(in: [old], today: now, calendar: berlin))
    }

    func testSnapshotDoesNotCountFuturePlannedEntries() throws {
        let now = try XCTUnwrap(berlin.date(from: DateComponents(
            year: 2026, month: 9, day: 14, hour: 8
        )))
        let future = TimeEntry(
            id: 4, ownerId: 7, unit: 2,
            startsAt: "2026-09-15T09:00:00", duration: "08:00:00",
            endsAt: "2026-09-15T17:00:00", archivedAt: nil, creationSource: 2
        )

        let snapshot = TimesheetMath.snapshot(entries: [future], now: now, calendar: berlin)

        XCTAssertEqual(snapshot.todaySeconds, 0)
        XCTAssertEqual(snapshot.weekSeconds, 0)
    }
}
