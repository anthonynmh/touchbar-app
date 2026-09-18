import XCTest
@testable import SnappyNestCore

final class RealBrightnessProviderTests: XCTestCase {
    func testSuccessfulWritePublishesConfirmedReadback() {
        let bridge = FakeBrightnessBridge(value: 0.4)
        let provider = RealBrightnessProvider(bridge: bridge)
        var observed: [Double] = []
        provider.subscribe { observed.append($0) }

        provider.set(0.75)

        XCTAssertEqual(provider.capability, .supported)
        XCTAssertEqual(provider.value, 0.75, accuracy: 0.001)
        XCTAssertEqual(bridge.setValues, [0.75])
        XCTAssertEqual(observed.last ?? -1, 0.75, accuracy: 0.001)
    }

    func testSetterFailureRestoresSnapshotWithoutOptimisticUpdate() {
        let bridge = FakeBrightnessBridge(value: 0.4)
        bridge.setStatuses = [-1, 0]
        let provider = RealBrightnessProvider(bridge: bridge)
        var observed: [Double] = []
        provider.subscribe { observed.append($0) }

        provider.set(0.8)

        XCTAssertEqual(provider.capability, .supported)
        XCTAssertEqual(provider.value, 0.4, accuracy: 0.001)
        XCTAssertEqual(bridge.value, 0.4, accuracy: 0.001)
        XCTAssertEqual(bridge.setValues, [0.8, 0.4])
        XCTAssertFalse(observed.contains { abs($0 - 0.8) < 0.001 })
    }

    func testMismatchedReadbackRestoresAndVerifiesSnapshot() {
        let bridge = FakeBrightnessBridge(value: 0.35)
        bridge.successfulSetOverrides = [0.6]
        let provider = RealBrightnessProvider(bridge: bridge)

        provider.set(0.8)

        XCTAssertEqual(provider.capability, .supported)
        XCTAssertEqual(provider.value, 0.35, accuracy: 0.001)
        XCTAssertEqual(bridge.value, 0.35, accuracy: 0.001)
        XCTAssertEqual(bridge.setValues, [0.8, 0.35])
    }

    func testReadbackFailureRestoresSnapshot() {
        let bridge = FakeBrightnessBridge(value: 0.3)
        bridge.failGetCalls = [3]
        let provider = RealBrightnessProvider(bridge: bridge)

        provider.set(0.7)

        XCTAssertEqual(provider.capability, .supported)
        XCTAssertEqual(provider.value, 0.3, accuracy: 0.001)
        XCTAssertEqual(bridge.value, 0.3, accuracy: 0.001)
    }

    func testIncompleteRollbackMarksUnavailableAndPublishesActualState() {
        let bridge = FakeBrightnessBridge(value: 0.25)
        bridge.successfulSetOverrides = [0.55]
        bridge.setStatuses = [0, -1]
        let provider = RealBrightnessProvider(bridge: bridge)
        var observed: [Double] = []
        provider.subscribe { observed.append($0) }

        provider.set(0.8)

        XCTAssertEqual(provider.capability, .unavailable(reason: "brightness_rollback_failed"))
        XCTAssertEqual(provider.value, 0.55, accuracy: 0.001)
        XCTAssertEqual(observed.last ?? -1, 0.55, accuracy: 0.001)
    }

    func testInitialReadFailureIsUnavailable() {
        let bridge = FakeBrightnessBridge(value: 0.5)
        bridge.failGetCalls = [1]

        let provider = RealBrightnessProvider(bridge: bridge)

        XCTAssertEqual(provider.capability, .unavailable(reason: "brightness_read_failed"))
    }
}

private final class FakeBrightnessBridge: BrightnessBridge {
    var value: Float
    var setStatuses: [Int32] = []
    var successfulSetOverrides: [Float] = []
    var failGetCalls: Set<Int> = []
    var setValues: [Float] = []
    private var getCallCount = 0

    init(value: Float) { self.value = value }

    func getBrightness() -> (status: Int32, value: Float) {
        getCallCount += 1
        if failGetCalls.contains(getCallCount) { return (-1, value) }
        return (0, value)
    }

    func setBrightness(_ value: Float) -> Int32 {
        setValues.append(value)
        let status = setStatuses.isEmpty ? 0 : setStatuses.removeFirst()
        guard status == 0 else { return status }
        self.value = successfulSetOverrides.isEmpty
            ? value
            : successfulSetOverrides.removeFirst()
        return 0
    }
}
