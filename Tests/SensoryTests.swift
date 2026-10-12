import XCTest
@testable import GymApp

final class SensoryTests: XCTestCase {
    func testEveryEventBuildsAPattern() throws {
        for event in SensoryEvent.allCases {
            XCTAssertNoThrow(try HapticPatterns.pattern(for: event))
        }
    }

    func testSpecValues() {
        XCTAssertEqual(SensoryEvent.dropWeight.intensity, 0.85)
        XCTAssertEqual(SensoryEvent.dropWeight.sharpness, 0.20)
        XCTAssertEqual(SensoryEvent.setDone.intensity, 1.0)
        XCTAssertEqual(SensoryEvent.setDone.sharpness, 0.95)
        XCTAssertEqual(SensoryEvent.scrubTick.intensity, 0.25)
        XCTAssertEqual(SensoryEvent.scrubTick.sharpness, 0.80)
    }
}
