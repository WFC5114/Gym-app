import XCTest
@testable import GymApp

final class SkinTests: XCTestCase {
    func testDefaultSkinIsMonochromeAndUnlocked() {
        XCTAssertEqual(Brutal.skin, Skin.mono)
        XCTAssertNil(Skin.mono.unlock)
    }

    func testSkinIdsAreUnique() {
        XCTAssertEqual(Set(Skin.all.map(\.id)).count, Skin.all.count)
    }

    func testOtherSkinsAreUnlockable() {
        XCTAssertTrue(Skin.all.filter { $0 != .mono }.allSatisfy { $0.unlock != nil })
    }
}
