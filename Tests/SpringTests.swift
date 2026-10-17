import XCTest
@testable import GymApp

final class SpringTests: XCTestCase {
    /// Runs a spring from 1 to 0 and returns the overshoot peaks as fractions of the start.
    private func peaks(_ config: SpringConfig) -> [Double] {
        var s = SpringState(position: 1, target: 0)
        var result: [Double] = []
        var lastVelocity = 0.0
        for _ in 0..<12_000 {
            s.step(1.0 / 1200, config: config)
            if lastVelocity != 0, (lastVelocity < 0) != (s.velocity < 0) {
                result.append(abs(s.position))
            }
            lastVelocity = s.velocity
        }
        return result
    }

    func testJarBouncesThreeTimes() {
        let visible = peaks(.jar).filter { $0 > 0.05 }
        XCTAssertEqual(visible.count, 3)
    }

    func testPrismOvershootsAboutEightPercent() {
        XCTAssertEqual(peaks(.prism).first ?? 0, 0.08, accuracy: 0.01)
    }

    func testBodyNumbersBarelyOvershoot() {
        XCTAssertLessThan(peaks(.bodyNumbers).first ?? 0, 0.01)
    }

    func testSpringSettles() {
        var s = SpringState(position: 0, target: 120)
        for _ in 0..<2400 { s.step(1.0 / 120, config: .prism) }
        XCTAssertTrue(s.isSettled(tolerance: 0.01))
    }

    func testPrismFacesWrap() {
        XCTAssertEqual(PrismFace.body.next(), .diet)
        XCTAssertEqual(PrismFace.diet.previous(), .body)
        XCTAssertEqual(PrismFace.train.yaw, 120)
    }

    func testQuickAddWeights() {
        XCTAssertEqual(QuickAdd.weights, [50, 100, 250, 500])
    }

    func testTumbleBouncesOnceThenSettles() {
        let visible = peaks(.tumble).filter { $0 > 0.05 }
        XCTAssertEqual(visible.count, 1)
    }
}
