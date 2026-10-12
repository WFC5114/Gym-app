import XCTest
@testable import GymApp

final class SnapshotStoreTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "SnapshotStoreTests")
        defaults.removePersistentDomain(forName: "SnapshotStoreTests")
    }

    func testRoundTrip() {
        let snapshot = DailySnapshot.placeholder
        SnapshotStore.save(snapshot, to: defaults)
        XCTAssertEqual(SnapshotStore.load(from: defaults), snapshot)
    }

    func testMissingSnapshotIsNil() {
        XCTAssertNil(SnapshotStore.load(from: defaults))
    }

    func testLeftNeverGoesNegative() {
        var snapshot = DailySnapshot.placeholder
        snapshot.caloriesEaten = 3000
        snapshot.proteinEaten = 250
        XCTAssertEqual(snapshot.caloriesLeft, 0)
        XCTAssertEqual(snapshot.proteinLeft, 0)
        XCTAssertEqual(snapshot.caloriesProgress, 1)
    }

    func testZeroTargetHasZeroProgress() {
        var snapshot = DailySnapshot.placeholder
        snapshot.caloriesTarget = 0
        XCTAssertEqual(snapshot.caloriesProgress, 0)
    }
}
