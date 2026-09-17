import AppKit
import XCTest
@testable import SnappyNestUI

final class TouchBarPresenterTests: XCTestCase {
    private let geometry = TouchBarPresentationGeometry(
        width: 1004,
        height: 30,
        backingScale: 2
    )

    func testTrayRegistrationPrecedesModalPresentation() {
        let runtime = FakeRuntime()
        let monitor = FakeAttachmentMonitor()
        let presenter = makePresenter(runtime: runtime, monitor: monitor)

        presenter.install()

        XCTAssertEqual(
            runtime.events,
            ["addTray", "presence:true", "presentModal:1:nil"]
        )
        XCTAssertEqual(presenter.state, .installing)
        XCTAssertFalse(presenter.isInstalled)

        monitor.completeLast(with: .attached(geometry))
        XCTAssertEqual(presenter.state, .visible(geometry))
        XCTAssertTrue(presenter.isInstalled)
    }

    func testHideShowDismissesAndRepresents() {
        let runtime = FakeRuntime()
        let monitor = FakeAttachmentMonitor()
        let presenter = makePresenter(runtime: runtime, monitor: monitor)

        presenter.install()
        monitor.completeLast(with: .attached(geometry))
        presenter.uninstall()

        XCTAssertEqual(
            Array(runtime.events.suffix(3)),
            ["dismissModal", "presence:false", "removeTray"]
        )
        XCTAssertEqual(presenter.state, .hidden)

        presenter.install()
        monitor.completeLast(with: .attached(geometry))

        XCTAssertEqual(runtime.events.filter { $0 == "addTray" }.count, 2)
        XCTAssertEqual(runtime.events.filter { $0 == "presentModal:1:nil" }.count, 2)
        XCTAssertEqual(presenter.state, .visible(geometry))
    }

    func testRepeatedCleanupRunsExactlyOnce() {
        let runtime = FakeRuntime()
        let monitor = FakeAttachmentMonitor()
        let presenter = makePresenter(runtime: runtime, monitor: monitor)

        presenter.install()
        monitor.completeLast(with: .attached(geometry))
        presenter.uninstall()
        presenter.uninstall()

        XCTAssertEqual(runtime.events.filter { $0 == "dismissModal" }.count, 1)
        XCTAssertEqual(runtime.events.filter { $0 == "presence:false" }.count, 1)
        XCTAssertEqual(runtime.events.filter { $0 == "removeTray" }.count, 1)
    }

    func testMissingSelectorSelectsFallback() {
        let runtime = FakeRuntime()
        runtime.capabilityFailureReason = "present selector unavailable"
        let monitor = FakeAttachmentMonitor()
        let fallback = FakeFallbackPresenter(rendererView: makeRenderer(), geometry: geometry)
        let presenter = makePresenter(
            runtime: runtime,
            monitor: monitor,
            fallback: fallback
        )

        presenter.install()

        XCTAssertTrue(runtime.events.isEmpty)
        XCTAssertEqual(fallback.installCount, 1)
        XCTAssertEqual(presenter.state, .fallback(geometry))
    }

    func testAttachmentTimeoutCleansPersistentResourcesAndSelectsFallback() {
        let runtime = FakeRuntime()
        let monitor = FakeAttachmentMonitor()
        let fallback = FakeFallbackPresenter(rendererView: makeRenderer(), geometry: geometry)
        let presenter = makePresenter(
            runtime: runtime,
            monitor: monitor,
            fallback: fallback
        )

        presenter.install()
        monitor.completeLast(with: .timedOut)

        XCTAssertEqual(
            Array(runtime.events.suffix(3)),
            ["dismissModal", "presence:false", "removeTray"]
        )
        XCTAssertEqual(fallback.installCount, 1)
        XCTAssertEqual(presenter.state, .fallback(geometry))
    }

    private func makePresenter(
        runtime: FakeRuntime,
        monitor: FakeAttachmentMonitor,
        fallback: FakeFallbackPresenter? = nil
    ) -> PersistentPresenter {
        let renderer = makeRenderer()
        let fallbackPresenter = fallback ?? FakeFallbackPresenter(
            rendererView: renderer,
            geometry: geometry
        )
        return PersistentPresenter(
            rendererView: renderer,
            runtime: runtime,
            attachmentMonitor: monitor,
            attachmentTimeout: 1,
            fallbackFactory: { fallbackPresenter }
        )
    }

    private func makeRenderer() -> SceneRenderer {
        SceneRenderer(frame: NSRect(x: 0, y: 0, width: 1085, height: 30))
    }
}

private final class FakeRuntime: PersistentTouchBarRuntime {
    var capabilityFailureReason: String?
    var events: [String] = []

    func addSystemTrayItem(_ item: NSCustomTouchBarItem) -> Bool {
        events.append("addTray")
        return true
    }

    func setControlStripPresence(identifier: String, present: Bool) {
        events.append("presence:\(present)")
    }

    func presentSystemModalTouchBar(
        _ touchBar: NSTouchBar,
        placement: Int64,
        trayIdentifier: String?
    ) -> Bool {
        events.append("presentModal:\(placement):\(trayIdentifier ?? "nil")")
        return true
    }

    func dismissSystemModalTouchBar(_ touchBar: NSTouchBar) {
        events.append("dismissModal")
    }

    func removeSystemTrayItem(_ item: NSCustomTouchBarItem) {
        events.append("removeTray")
    }

}

private final class FakeObservation: TouchBarAttachmentObservation {
    private(set) var isCancelled = false
    func cancel() { isCancelled = true }
}

private final class FakeAttachmentMonitor: TouchBarAttachmentMonitoring {
    private var completions: [(TouchBarAttachmentResult) -> Void] = []

    func start(
        observing view: NSView,
        timeout: TimeInterval,
        completion: @escaping (TouchBarAttachmentResult) -> Void
    ) -> TouchBarAttachmentObservation {
        completions.append(completion)
        return FakeObservation()
    }

    func completeLast(with result: TouchBarAttachmentResult) {
        completions.last?(result)
    }
}

private final class FakeFallbackPresenter: TouchBarPresenter {
    let rendererView: SceneRenderer
    var state: TouchBarPresentationState = .idle
    var stateDidChange: ((TouchBarPresentationState) -> Void)?
    var installCount = 0
    var uninstallCount = 0
    private let geometry: TouchBarPresentationGeometry

    init(rendererView: SceneRenderer, geometry: TouchBarPresentationGeometry) {
        self.rendererView = rendererView
        self.geometry = geometry
    }

    func install() {
        installCount += 1
        state = .fallback(geometry)
        stateDidChange?(state)
    }

    func uninstall() {
        uninstallCount += 1
        state = .hidden
        stateDidChange?(state)
    }
}
