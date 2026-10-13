import XCTest
import SwiftUI
@testable import GymApp

final class SkinTests: XCTestCase {
    /// Wei, 13 Oct 2026: the colour skin is the default; MONO stays free.
    func testDefaultSkinIsFlareAndBothFreeSkinsAreUnlocked() {
        XCTAssertEqual(Brutal.skin, Skin.flare)
        XCTAssertNil(Skin.flare.unlock)
        XCTAssertNil(Skin.mono.unlock)
        XCTAssertEqual(Skin.mono.base, Color(hex: 0x000000))
        XCTAssertEqual(Skin.flare.faceColors?.count, 3, "one colour per face")
    }

    func testSkinIdsAreUnique() {
        XCTAssertEqual(Set(Skin.all.map(\.id)).count, Skin.all.count)
    }

    func testOtherSkinsAreUnlockable() {
        XCTAssertTrue(Skin.all.filter { $0 != .mono && $0 != .flare }.allSatisfy { $0.unlock != nil })
    }
}
