import AppKit
import XCTest
@testable import SnappyNestUI

final class TouchBarPresenterTests: XCTestCase {
    private let geometry = TouchBarPresentationGeometry(
        width: 685,
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
            ["addTray", "presence:true", "presentModal", "status:2"]
        )
        XCTAssertEqual(presenter.state, .installing)

        monitor.completeLast(with: .attached(geometry))
        XCTAssertEqual(presenter.state, .visible(geometry))
    }

    func testHideShowDismissesAndRepresents() {
        let runtime = FakeRuntime()
        let monitor = FakeAttachmentMonitor()
        let presenter = makePresenter(runtime: runtime, monitor: monitor)

        presenter.install()
        monitor.completeLast(with: .attached(geometry))
        presenter.uninstall()

        XCTAssertEqual(
            Array(runtime.events.suffix(4)),
            ["dismissModal", "presence:false", "removeTray", "status:0"]
        )
        XCTAssertEqual(presenter.state, .hidden)

        presenter.install()
        monitor.completeLast(with: .attached(geometry))

        XCTAssertEqual(runtime.events.filter { $0 == "addTray" }.count, 2)
        XCTAssertEqual(runtime.events.filter { $0 == "presentModal" }.count, 2)
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
        XCTAssertEqual(runtime.events.filter { $0 == "status:0" }.count, 1)
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
            Array(runtime.events.suffix(4)),
            ["dismissModal", "presence:false", "removeTray", "status:0"]
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
        SceneRenderer(frame: NSRect(x: 0, y: 0, width: 685, height: 30))
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

    func presentSystemModalTouchBar(_ touchBar: NSTouchBar, trayIdentifier: String) -> Bool {
        events.append("presentModal")
        return true
    }

    func dismissSystemModalTouchBar(_ touchBar: NSTouchBar) {
        events.append("dismissModal")
    }

    func removeSystemTrayItem(_ item: NSCustomTouchBarItem) {
        events.append("removeTray")
    }

    func setPresentationStatus(_ status: Int32) {
        events.append("status:\(status)")
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
