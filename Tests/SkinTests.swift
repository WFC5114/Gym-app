import XCTest
import SwiftUI
@testable import GymApp

final class SkinTests: XCTestCase {
    func testDefaultSkinIsMonoAndUnlocked() {
        XCTAssertEqual(Brutal.skin, Skin.mono)
        XCTAssertNil(Skin.mono.unlock)
        XCTAssertEqual(Skin.mono.base, Color(hex: 0x000000))
    }

    func testSkinIdsAreUnique() {
        XCTAssertEqual(Set(Skin.all.map(\.id)).count, Skin.all.count)
    }

    func testOtherSkinsAreUnlockable() {
        XCTAssertTrue(Skin.all.filter { $0 != .mono }.allSatisfy { $0.unlock != nil })
    }
}
