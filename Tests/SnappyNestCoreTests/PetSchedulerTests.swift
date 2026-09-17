import XCTest
@testable import SnappyNestCore

final class PetSchedulerTests: XCTestCase {
    func testDeterministicSequenceGivenSeed() {
        let a = PetActionScheduler(seed: 42)
        let b = PetActionScheduler(seed: 42)
        for _ in 0..<50 {
            let da = a.decideNext(at: WorldTime(hour: 14, minute: 0, second: 0))
            let db = b.decideNext(at: WorldTime(hour: 14, minute: 0, second: 0))
            XCTAssertEqual(da, db)
        }
    }

    func testDifferentSeedsDiverge() {
        var a = PetActionScheduler(seed: 42).decideNext(at: WorldTime(hour: 14, minute: 0, second: 0))
        var b = PetActionScheduler(seed: 43).decideNext(at: WorldTime(hour: 14, minute: 0, second: 0))
        var same = a.action == b.action
        for _ in 0..<20 where same {
            a = PetActionScheduler(seed: 42).decideNext(at: WorldTime(hour: 14, minute: 0, second: 0))
            b = PetActionScheduler(seed: 43).decideNext(at: WorldTime(hour: 14, minute: 0, second: 0))
            same = a.action == b.action
        }
        // Not strictly guaranteed on any single call, but the seeds should
        // produce different sequences overall.
        var actionsA: [PetAction] = []
        var actionsB: [PetAction] = []
        let sa = PetActionScheduler(seed: 42)
        let sb = PetActionScheduler(seed: 43)
        for _ in 0..<30 {
            actionsA.append(sa.decideNext(at: WorldTime(hour: 14, minute: 0, second: 0)).action)
            actionsB.append(sb.decideNext(at: WorldTime(hour: 14, minute: 0, second: 0)).action)
        }
        XCTAssertNotEqual(actionsA, actionsB)
    }

    func testAvoidsConsecutiveRepeats() {
        let s = PetActionScheduler(seed: 12345)
        var last: PetAction?
        for _ in 0..<500 {
            let d = s.decideNext(at: WorldTime(hour: 14, minute: 0, second: 0))
            if let last = last {
                XCTAssertNotEqual(d.action, last, "consecutive repeat leaked past the 0.1x downweight")
            }
            last = d.action
        }
    }

    func testHoldWithinRange() {
        let s = PetActionScheduler(seed: 7, config: .init())
        for _ in 0..<200 {
            let d = s.decideNext(at: WorldTime(hour: 14, minute: 0, second: 0))
            XCTAssertGreaterThanOrEqual(d.holdSeconds, 20)
            XCTAssertLessThanOrEqual(d.holdSeconds, 90)
        }
    }

    func testNightWeightsSurfaceStargazeMoreOften() {
        var dayCount = 0
        var nightCount = 0
        for _ in 0..<300 {
            let s = PetActionScheduler(seed: UInt64.random(in: 0..<UInt64.max))
            if s.decideNext(at: WorldTime(hour: 22, minute: 0, second: 0)).action == .stargaze { nightCount += 1 }
        }
        for _ in 0..<300 {
            let s = PetActionScheduler(seed: UInt64.random(in: 0..<UInt64.max))
            if s.decideNext(at: WorldTime(hour: 10, minute: 0, second: 0)).action == .stargaze { dayCount += 1 }
        }
        XCTAssertGreaterThan(nightCount, dayCount, "stargaze should be more frequent at night")
    }
}
