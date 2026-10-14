import XCTest
import SwiftUI
@testable import GymApp

final class SkinTests: XCTestCase {
    /// Wei, 14 Oct 2026: NIGHT (graphite clay, ivory objects, glass) is the
    /// default; FLARE and MONO stay free.
    func testDefaultSkinIsNightAndTheFreeSkinsAreUnlocked() {
        XCTAssertEqual(Brutal.skin, Skin.night)
        XCTAssertTrue(Skin.night.clayUI)
        XCTAssertNil(Skin.night.unlock)
        XCTAssertNil(Skin.flare.unlock)
        XCTAssertNil(Skin.mono.unlock)
        XCTAssertEqual(Skin.night.base, Color(hex: 0x000000), "the void around the prism stays black")
        XCTAssertEqual(Skin.mono.base, Color(hex: 0x000000))
        XCTAssertEqual(Skin.flare.faceColors?.count, 3, "one colour per face")
        XCTAssertEqual(Skin.night.faceColors?.count, 3, "a clay tray on every face")
    }

    func testSkinIdsAreUnique() {
        XCTAssertEqual(Set(Skin.all.map(\.id)).count, Skin.all.count)
    }

    func testOtherSkinsAreUnlockable() {
        let free: Set<String> = ["night", "flare", "mono"]
        XCTAssertTrue(Skin.all.filter { !free.contains($0.id) }.allSatisfy { $0.unlock != nil })
    }
}
