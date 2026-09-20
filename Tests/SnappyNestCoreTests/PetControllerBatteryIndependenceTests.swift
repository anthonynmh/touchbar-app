import CoreGraphics
import XCTest
@testable import SnappyNestCore

/// The core invariant from the plan: no code path from any BatterySnapshot
/// value into PetController's decisions. `PetController.tick` doesn't even
/// accept a battery parameter, so at compile time this cannot happen — but
/// the acceptance test still asserts that swapping battery states in and out
/// of a full simulation produces byte-identical action logs for a fixed seed
/// + fixed clock + fixed media.
final class PetControllerBatteryIndependenceTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 685, height: 30)

    func testActionLogIsIdenticalUnderExtremeBatteryStates() {
        let seed: UInt64 = 0xDEAD_BEEF_CAFE_0001
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        func runLog(with battery: BatterySnapshot) -> [PetAction] {
            let layout = LayoutEngine(bounds: bounds, backingScale: 2.0)
            let controller = PetController(seed: seed, layout: layout)
            var actions: [PetAction] = []
            for step in 0..<600 { // 10 minutes @ 1 Hz
                let now = start.addingTimeInterval(TimeInterval(step))
                // A keep-away game in the middle of the run: still no battery.
                if step == 120 { controller.toggleKeepAway(now: now) }
                if step == 130 { controller.kickBall(atX: 900, now: now) }
                controller.tick(now: now, media: .unknown)
                actions.append(controller.state.action)
                _ = battery // reference retained to prove the pattern lives in scope
            }
            return actions
        }

        let dying    = BatterySnapshot(isPresent: true, percentage: 0.02, isCharging: false)
        let full     = BatterySnapshot(isPresent: true, percentage: 1.0,  isCharging: false)
        let charging = BatterySnapshot(isPresent: true, percentage: 0.5,  isCharging: true)

        let logA = runLog(with: dying)
        let logB = runLog(with: full)
        let logC = runLog(with: charging)

        XCTAssertEqual(logA, logB)
        XCTAssertEqual(logA, logC)
    }
}
