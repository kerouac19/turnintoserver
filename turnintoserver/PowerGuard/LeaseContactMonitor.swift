import Foundation

/// Stop renewing after the first failed contact. A late reply from an older
/// generation must not interrupt a later session or restart the stopped timer.
final class LeaseContactMonitor {
    private let interval: TimeInterval
    private let contact: () async throws -> Void
    private let failed: @MainActor (Error) -> Void
    private let beginActivity: () -> (() -> Void)
    private var endActivity: (() -> Void)?
    private var timer: Timer?
    private var generation: UInt64 = 0
    private var inFlight = false

    init(interval: TimeInterval = 5, contact: @escaping () async throws -> Void,
         failed: @escaping @MainActor (Error) -> Void,
         beginActivity: @escaping () -> (() -> Void) = {
             let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep],
                 reason: "Maintains the power recovery lease")
             return { ProcessInfo.processInfo.endActivity(activity) }
         }) {
        self.interval = interval
        self.contact = contact
        self.failed = failed
        self.beginActivity = beginActivity
    }
    deinit { timer?.invalidate(); endActivity?() }
    func start() {
        precondition(Thread.isMainThread)
        stop()
        let current = generation
        endActivity = beginActivity()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            guard let self, self.timer != nil, !self.inFlight else { return }
            self.inFlight = true
            Task { @MainActor in
                do { try await self.contact() }
                catch {
                    guard self.generation == current, self.timer != nil else { return }
                    self.stop()
                    self.failed(error)
                    return
                }
                if self.generation == current { self.inFlight = false }
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    func stop() {
        generation &+= 1
        timer?.invalidate()
        timer = nil
        inFlight = false
        endActivity?()
        endActivity = nil
    }
}
