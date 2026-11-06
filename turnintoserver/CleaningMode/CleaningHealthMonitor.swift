import Foundation

/// The query is serialized on the main thread and does not depend on key events
/// or on the event tap reporting itself enabled. Callers supply the system adapter.
final class CleaningHealthMonitor {
    private let allowed: () -> Bool
    private let interrupted: () -> Void
    private var timer: Timer?
    init(allowed: @escaping () -> Bool, interrupted: @escaping () -> Void) {
        self.allowed = allowed
        self.interrupted = interrupted
    }
    deinit { timer?.invalidate() }
    @discardableResult func start() -> Bool {
        precondition(Thread.isMainThread)
        stop()
        guard allowed() else { return false }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, self.timer != nil else { return }
            if !self.allowed() {
                self.stop()
                self.interrupted()
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        return true
    }
    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
