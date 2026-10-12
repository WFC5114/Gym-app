import XCTest
@testable import GymApp

final class TrendTests: XCTestCase {
    private func day(_ n: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(n) * 86_400)
    }

    func testEmptyInput() {
        XCTAssertTrue(Trend.smooth([]).isEmpty)
        XCTAssertNil(Trend.weeklyRate([]))
    }

    func testFlatWeightStaysFlat() {
        let points = (0..<14).map { Trend.Point(date: day($0), value: 80) }
        let smoothed = Trend.smooth(points)
        XCTAssertEqual(smoothed.count, 14)
        XCTAssertTrue(smoothed.allSatisfy { abs($0.value - 80) < 0.0001 })
        XCTAssertEqual(Trend.weeklyRate(smoothed) ?? 1, 0, accuracy: 0.0001)
    }

    func testSingleSpikeIsDamped() {
        var points = (0..<10).map { Trend.Point(date: day($0), value: 80) }
        points[5].value = 82
        let smoothed = Trend.smooth(points)
        XCTAssertEqual(smoothed[5].value, 80.2, accuracy: 0.0001)
    }

    func testSortsByDate() {
        let points = [Trend.Point(date: day(2), value: 82), Trend.Point(date: day(0), value: 80)]
        let smoothed = Trend.smooth(points)
        XCTAssertEqual(smoothed.first?.date, day(0))
    }

    func testLosingWeightGivesNegativeRate() {
        let points = (0..<28).map { Trend.Point(date: day($0), value: 80 - Double($0) * 0.1) }
        let rate = Trend.weeklyRate(Trend.smooth(points)) ?? 0
        XCTAssertLessThan(rate, 0)
    }
}
