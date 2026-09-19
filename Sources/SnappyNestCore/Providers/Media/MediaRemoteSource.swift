import Foundation

/// Browser / system media playback via the private MediaRemote framework.
///
/// Since macOS 15.4 mediaremoted answers `MRMediaRemoteGetNowPlayingInfo`
/// only for Apple-signed processes, so the app cannot call it directly. The
/// calls live in `libSnappyMediaRemoteHost.dylib`, which the app loads into
/// `/usr/bin/perl` (Apple-signed) through `DynaLoader`; this source is a
/// client of that child: JSON lines in, command lines out. The transport is
/// injectable (`MediaRemoteHostBridge`) so the policy is testable without a
/// child process.
public final class MediaRemoteSource: MediaSource {
    public let identity = "browser"
    public private(set) var snapshot: MediaSnapshot = .unknown

    private let bridge: MediaRemoteHostBridge
    private let now: () -> Date
    private var handlers: [(MediaSnapshot) -> Void] = []
    private var launches = 0
    private var relaunchTimer: Timer?
    private var isRunning = false

    /// The host is restarted after a crash at most this many times.
    public static let maxLaunches = 3
    public static let relaunchDelay: TimeInterval = 2.0

    public init(bridge: MediaRemoteHostBridge, now: @escaping () -> Date = Date.init) {
        self.bridge = bridge
        self.now = now
        launch()
    }

    /// Production wiring: run the host dylib inside `/usr/bin/perl`.
    public convenience init(hostLibraryURL: URL?) {
        self.init(bridge: PerlMediaRemoteHost(libraryURL: hostLibraryURL))
    }

    deinit { bridge.stop() }

    /// True while the host child is alive. Without it the snapshot is
    /// `.unknown` (the playback page shows nothing) and no command is sent.
    public var isHostRunning: Bool { isRunning }

    private func launch() {
        guard launches < Self.maxLaunches else { return }
        launches += 1
        let started = bridge.start(
            onLine: { [weak self] line in self?.handle(line: line) },
            onExit: { [weak self] reason in self?.hostExited(reason: reason) }
        )
        switch started {
        case .success:
            isRunning = true
        case let .failure(error):
            isRunning = false
            NSLog("[SnappyNest] mediaremote host unavailable: %@", error.description)
            publish(MediaSnapshot(identity: identity, state: .unknown))
        }
    }

    private func hostExited(reason: String) {
        isRunning = false
        publish(MediaSnapshot(identity: identity, state: .unknown))
        NSLog("[SnappyNest] mediaremote host exited: %@", reason)
        guard launches < Self.maxLaunches else {
            NSLog("[SnappyNest] mediaremote host gave up after %d launches", launches)
            return
        }
        relaunchTimer?.invalidate()
        relaunchTimer = Timer.scheduledTimer(withTimeInterval: Self.relaunchDelay, repeats: false) { [weak self] _ in
            self?.launch()
        }
    }

    // MARK: - Host output

    /// One JSON object per line from the host; `{}` means no now-playing
    /// client. Anything unparsable is ignored.
    func handle(line: String) {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any] else { return }
        publish(build(from: dict))
    }

    private func build(from dict: [String: Any]) -> MediaSnapshot {
        if dict.isEmpty || dict["error"] != nil {
            return MediaSnapshot(identity: identity, state: .unknown)
        }
        let title = dict["title"] as? String
        let bundle = dict["bundle"] as? String
        let elapsed = dict["elapsed"] as? Double
        let duration = dict["duration"] as? Double
        let rate = dict["rate"] as? Double ?? 0
        let elapsedAt = (dict["timestamp"] as? Double).map(Date.init(timeIntervalSince1970:)) ?? now()

        let state: MediaSnapshot.State = rate > 0 ? .playing : .paused
        return MediaSnapshot(
            identity: identity, state: state,
            elapsed: elapsed, duration: duration,
            elapsedAt: elapsedAt, rate: rate == 0 ? 1 : rate,
            title: title,
            sourceApp: bundle,
            canPlayPause: true,
            canReadPosition: elapsed != nil,
            canReadDuration: (duration ?? 0) > 0.5,
            canSeek: elapsed != nil && (duration ?? 0) > 0.5,
            canSkip: true
        )
    }

    private func publish(_ new: MediaSnapshot) {
        guard new != snapshot else { return }
        snapshot = new
        handlers.forEach { $0(new) }
    }

    // MARK: - Commands

    /// Whether a command may be sent at all: with no now-playing client,
    /// mediaremoted routes it to the default/last media app and launches it
    /// (like the F8 key opening Music). The host applies the same gate.
    private var hasNowPlayingClient: Bool {
        isRunning && (snapshot.state == .playing || snapshot.state == .paused)
    }

    private func send(_ command: String) {
        guard hasNowPlayingClient else { return }
        bridge.send(command)
    }

    public func togglePlayPause() { send("toggle") }
    public func nextTrack() { send("next") }
    public func previousTrack() { send("previous") }

    public func seek(to seconds: TimeInterval) {
        guard hasNowPlayingClient, snapshot.canSeek else { return }
        let duration = snapshot.duration ?? seconds
        let clamped = min(duration, max(0, seconds))
        send(String(format: "seek %.3f", clamped))
    }

    public func subscribe(_ handler: @escaping (MediaSnapshot) -> Void) {
        handlers.append(handler)
        handler(snapshot)
    }

    public func unsubscribeAll() { handlers.removeAll() }

    /// Stop the host child. Called on app termination.
    public func shutdown() {
        relaunchTimer?.invalidate()
        launches = Self.maxLaunches
        bridge.stop()
        isRunning = false
    }
}

// MARK: - Transport

public struct MediaRemoteHostError: Error, CustomStringConvertible, Equatable {
    public let description: String
    public init(_ description: String) { self.description = description }
}

/// The channel to the MediaRemote host process. Lines and exit are delivered
/// on the main queue.
public protocol MediaRemoteHostBridge: AnyObject {
    func start(onLine: @escaping (String) -> Void,
               onExit: @escaping (String) -> Void) -> Result<Void, MediaRemoteHostError>
    func send(_ command: String)
    func stop()
}

/// `/usr/bin/perl` loading the host dylib. perl is Apple-signed, which is
/// what lets the MediaRemote calls inside the dylib see now-playing info.
public final class PerlMediaRemoteHost: MediaRemoteHostBridge {
    public static let perlPath = "/usr/bin/perl"
    public static let libraryName = "libSnappyMediaRemoteHost.dylib"
    public static let entrySymbol = "snappy_mediaremote_host"

    /// The fixed perl program (also used by Probe 05c).
    public static let perlScript = """
    use DynaLoader;
    my $lib = DynaLoader::dl_load_file($ARGV[0], 1) or die DynaLoader::dl_error();
    my $sym = DynaLoader::dl_find_symbol($lib, "\(entrySymbol)") or die "\(entrySymbol) not found";
    DynaLoader::dl_install_xsub("main::run", $sym);
    main::run();
    """

    private let libraryURL: URL?
    private var process: Process?
    private var stdinPipe: Pipe?
    private var buffer = Data()

    public init(libraryURL: URL?) {
        self.libraryURL = libraryURL
    }

    /// The host dylib next to the app: `Contents/Frameworks/` in a bundle,
    /// or beside the executable for a bare `swift build` run.
    public static func locateLibrary(bundle: Bundle = .main) -> URL? {
        var candidates: [URL] = []
        if let frameworks = bundle.privateFrameworksURL {
            candidates.append(frameworks.appendingPathComponent(libraryName))
        }
        candidates.append(bundle.bundleURL.appendingPathComponent(libraryName))
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        candidates.append(executable.appendingPathComponent(libraryName))
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    public func start(onLine: @escaping (String) -> Void,
                      onExit: @escaping (String) -> Void) -> Result<Void, MediaRemoteHostError> {
        guard let libraryURL else {
            return .failure(MediaRemoteHostError("\(Self.libraryName) not found next to the app"))
        }
        guard FileManager.default.isExecutableFile(atPath: Self.perlPath) else {
            return .failure(MediaRemoteHostError("\(Self.perlPath) is missing"))
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.perlPath)
        process.arguments = ["-e", Self.perlScript, libraryURL.path]
        let stdout = Pipe()
        let stdin = Pipe()
        process.standardOutput = stdout
        process.standardInput = stdin
        process.standardError = FileHandle.standardError
        buffer = Data()
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                self.buffer.append(data)
                while let newline = self.buffer.firstIndex(of: UInt8(ascii: "\n")) {
                    let lineData = self.buffer[self.buffer.startIndex..<newline]
                    self.buffer.removeSubrange(self.buffer.startIndex...newline)
                    if let line = String(data: lineData, encoding: .utf8) { onLine(line) }
                }
            }
        }
        process.terminationHandler = { proc in
            stdout.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                onExit("status \(proc.terminationStatus) (\(proc.terminationReason == .uncaughtSignal ? "signal" : "exit"))")
            }
        }
        do {
            try process.run()
        } catch {
            return .failure(MediaRemoteHostError("spawn failed: \(error)"))
        }
        self.process = process
        self.stdinPipe = stdin
        return .success(())
    }

    public func send(_ command: String) {
        guard let process, process.isRunning, let data = (command + "\n").data(using: .utf8) else { return }
        stdinPipe?.fileHandleForWriting.write(data)
    }

    public func stop() {
        guard let process else { return }
        process.terminationHandler = nil
        try? stdinPipe?.fileHandleForWriting.close()   // the host exits when stdin closes
        if process.isRunning { process.terminate() }
        self.process = nil
        self.stdinPipe = nil
    }
}

/// In-memory host for tests.
public final class FakeMediaRemoteHost: MediaRemoteHostBridge {
    public var startResult: Result<Void, MediaRemoteHostError> = .success(())
    public private(set) var startCount = 0
    public private(set) var sent: [String] = []
    public private(set) var stopped = false
    private var onLine: ((String) -> Void)?
    private var onExit: ((String) -> Void)?

    public init() {}

    public func start(onLine: @escaping (String) -> Void,
                      onExit: @escaping (String) -> Void) -> Result<Void, MediaRemoteHostError> {
        startCount += 1
        if case .success = startResult {
            self.onLine = onLine
            self.onExit = onExit
        }
        return startResult
    }

    public func send(_ command: String) { sent.append(command) }
    public func stop() { stopped = true }

    /// Simulate a line from the host's stdout.
    public func emit(_ line: String) { onLine?(line) }
    /// Simulate the host dying.
    public func crash(_ reason: String = "status 1 (exit)") { onExit?(reason) }
}
