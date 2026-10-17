import XCTest
@testable import GymApp

final class RestCoachTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_791_800_000)
    let squat = Exercise.named("Back squat")!
    let bench = Exercise.named("Bench press")!
    let curl = Exercise.named("Barbell curl")!

    func testLegsRestLongerThanOtherParts() {
        let legs = RestCoach.recommend(for: squat, setNumber: 1, history: [], readiness: .unknown, now: now)
        let chest = RestCoach.recommend(for: bench, setNumber: 1, history: [], readiness: .unknown, now: now)
        let arms = RestCoach.recommend(for: curl, setNumber: 1, history: [], readiness: .unknown, now: now)
        XCTAssertGreaterThan(legs.seconds, chest.seconds)
        XCTAssertGreaterThan(chest.seconds, arms.seconds)
        XCTAssertEqual(legs.bodyPart, .legs)
    }

    func testMissingHealthDataIsSaidOutLoud() {
        let advice = RestCoach.recommend(for: bench, setNumber: 1, history: [], readiness: .unknown, now: now)
        XCTAssertTrue(advice.reasons.contains("NO HRV READING TODAY"))
        XCTAssertTrue(advice.reasons.contains("NO SLEEP DATA FOR LAST NIGHT"))
    }

    func testPoorRecoveryLengthensRest() {
        let rested = Readiness(hrvToday: 62, hrvBaseline: 58, restingHRToday: 54, restingHRBaseline: 54, sleepHours: 8)
        let tired = Readiness(hrvToday: 40, hrvBaseline: 58, restingHRToday: 62, restingHRBaseline: 54, sleepHours: 5)
        let a = RestCoach.recommend(for: bench, setNumber: 1, history: [], readiness: rested, now: now)
        let b = RestCoach.recommend(for: bench, setNumber: 1, history: [], readiness: tired, now: now)
        XCTAssertGreaterThan(b.seconds, a.seconds)
    }

    private func rest(_ part: BodyPart, daysAgo: Double, added: Int = 0, endedEarlyAfter: Int? = nil) -> RestPeriod {
        let start = now.addingTimeInterval(-daysAgo * 86400)
        var r = RestPeriod(id: UUID(), exercise: part == .legs ? "Back squat" : "Bench press", bodyPart: part,
                           afterSet: 1, startedAt: start, plannedSeconds: 150)
        if added > 0 { r.additions = [RestAddition(at: start.addingTimeInterval(100), seconds: added)] }
        if let early = endedEarlyAfter {
            r.endedAt = start.addingTimeInterval(TimeInterval(early))
            r.endReason = .nextSet
            r.nextSetAt = r.endedAt
        } else {
            r.endedAt = r.endsAt
            r.endReason = .elapsed
        }
        return r
    }

    func testLearnsFromTimeAddedToLegRests() {
        let history = (1...6).map { rest(.legs, daysAgo: Double($0), added: 30) }
        let base = RestCoach.recommend(for: squat, setNumber: 1, history: [], readiness: .unknown, now: now)
        let adapted = RestCoach.recommend(for: squat, setNumber: 1, history: history, readiness: .unknown, now: now)
        XCTAssertEqual(adapted.seconds, base.seconds + 30)
        // Chest is unaffected by leg history.
        let chest = RestCoach.recommend(for: bench, setNumber: 1, history: history, readiness: .unknown, now: now)
        XCTAssertEqual(chest.seconds, RestCoach.recommend(for: bench, setNumber: 1, history: [], readiness: .unknown, now: now).seconds)
    }

    func testLearnsFromStartingEarly() {
        let history = (1...5).map { rest(.chest, daysAgo: Double($0), endedEarlyAfter: 90) }
        let base = RestCoach.recommend(for: bench, setNumber: 1, history: [], readiness: .unknown, now: now)
        let adapted = RestCoach.recommend(for: bench, setNumber: 1, history: history, readiness: .unknown, now: now)
        XCTAssertEqual(adapted.seconds, base.seconds - 15)
    }

    func testOldHistoryIsIgnored() {
        let history = (1...6).map { rest(.legs, daysAgo: Double(20 + $0), added: 60) }
        let base = RestCoach.recommend(for: squat, setNumber: 1, history: [], readiness: .unknown, now: now)
        XCTAssertEqual(RestCoach.recommend(for: squat, setNumber: 1, history: history, readiness: .unknown, now: now).seconds, base.seconds)
    }

    func testRecommendationsAreBoundedAndRounded() {
        let tired = Readiness(hrvToday: 10, hrvBaseline: 80, restingHRToday: 90, restingHRBaseline: 50, sleepHours: 2)
        let history = (1...6).map { rest(.legs, daysAgo: Double($0), added: 60) }
        let advice = RestCoach.recommend(for: squat, setNumber: 5, history: history, readiness: tired, now: now)
        XCTAssertLessThanOrEqual(advice.seconds, RestLimits.maxSeconds)
        XCTAssertEqual(advice.seconds % RestLimits.step, 0)
    }

    func testDigestCarriesEveryAddition() throws {
        let r = rest(.legs, daysAgo: 1, added: 30)
        let digest = RestDigest(rests: [r])
        XCTAssertEqual(digest.rests.first?.addedSeconds, 30)
        XCTAssertEqual(digest.rests.first?.additions.count, 1)
        XCTAssertNoThrow(try JSONEncoder().encode(digest))
    }
}
