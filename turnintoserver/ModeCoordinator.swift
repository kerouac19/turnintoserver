import AppKit
import Combine
import CoreGraphics

@MainActor
final class ModeCoordinator: ObservableObject {
    @Published private(set) var displays: [DisplaySnapshot] = []
    @Published private(set) var status: String?
    let cleaning = CleaningModeManager()
    private let state: AppState
    private let displayManager = ExternalDisplayManager()
    private var subscriptions = Set<AnyCancellable>()
    private var observers: [NSObjectProtocol] = []
    private var pending: [DispatchWorkItem] = []
    private var round: DisplayRecheckRound?
    private var generation: UInt64 = 0
    private var previousLid: LidState = .unknown
    private var registered = false
    var isCheckingDisplays: Bool { round != nil || !pending.isEmpty }

    init(state: AppState) {
        self.state = state
        displayManager.context = { [weak state] in
            guard let state else { return .init(lid: .unknown, serverActive: false, transitioning: true) }
            return .init(lid: state.lidState == .open ? .open : state.lidState == .closed ? .closed : .unknown,
                         serverActive: state.serverModeActive, transitioning: state.displayTransitionInProgress)
        }
        state.prepareForSystemTransition = { [weak self] in self?.prepareForTransition() }
        cleaning.$isActive.sink { [weak state] active in state?.isCleaningModeActive = active }.store(in: &subscriptions)
        cleaning.$status.sink { [weak self] message in if let message { self?.status = message } }.store(in: &subscriptions)
        state.$lidState.removeDuplicates().receive(on: RunLoop.main).sink { [weak self] lid in
            guard let self else { return }
            if lid != self.previousLid {
                self.cleaning.stop(reason: nil)
                self.previousLid = lid
                self.scheduleRecheck()
            }
        }.store(in: &subscriptions)
        Publishers.CombineLatest(state.$serverModeActive, state.$isCommandRunning)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.scheduleRecheck() }.store(in: &subscriptions)
    }

    func start() {
        guard !registered else { return }
        registered = true
        CGDisplayRegisterReconfigurationCallback(Self.displayChanged, Unmanaged.passUnretained(self).toOpaque())
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleRecheck() }
            })
        }
        scheduleRecheck()
    }

    private static let displayChanged: CGDisplayReconfigurationCallBack = { _, flags, pointer in
        guard !flags.contains(.beginConfigurationFlag), let pointer else { return }
        let owner = Unmanaged<ModeCoordinator>.fromOpaque(pointer).takeUnretainedValue()
        DispatchQueue.main.async { [weak owner] in owner?.scheduleRecheck() }
    }

    func shutdown() {
        prepareForTransition()
        if registered {
            CGDisplayRemoveReconfigurationCallback(Self.displayChanged, Unmanaged.passUnretained(self).toOpaque())
            registered = false
        }
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
    }

    func prepareForTransition() {
        cleaning.stop(reason: nil)
        cancelRound()
    }

    func startCleaning(keepScreenVisible: Bool) {
        guard !state.isCommandRunning else { return }
        cleaning.keepScreenVisible = keepScreenVisible
        UserDefaults.standard.set(keepScreenVisible, forKey: "cleaning.keepScreenVisible")
        cleaning.activate()
    }

    func setDisplay(_ id: UInt32, enabled: Bool) {
        guard !cleaning.isActive else { return }
        guard enabled || !isCheckingDisplays else {
            status = AppIdentity.text("显示状态尚未稳定，可重试", "Display state has not settled; retry")
            return
        }
        guard displayManager.setExternalDisplayEnabled(id, enabled) else {
            status = AppIdentity.text("无法切换显示器：最后屏保护、屏幕变化或系统调用失败",
                "Cannot switch display: last-display protection, topology change or system error")
            scheduleRecheck()
            return
        }
        status = nil
        cancelRound()
        beginRound(target: (id, enabled))
    }

    func scheduleRecheck() {
        guard round == nil, pending.isEmpty else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pending.removeAll()
            self.beginRound(target: nil)
        }
        pending = [work]
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    private func beginRound(target: (UInt32, Bool)?) {
        generation &+= 1
        round = DisplayRecheckRound(generation: generation, target: target)
        let current = generation
        for (index, delay) in DisplayRecheckRound.offsets.enumerated() {
            let work = DispatchWorkItem { [weak self] in self?.check(generation: current, index: index) }
            pending.append(work)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    private func check(generation expected: UInt64, index: Int) {
        guard var current = round, current.generation == expected else { return }
        displays = displayManager.reconcileSafety()
        let context = displayManager.context()
        let safe = context.allowsHeadless || (!context.transitioning && context.lid != .unknown
            && !DisplaySafetyPolicy.needsRecovery(displays: displays, context: context))
        let finished = current.observe(displays, safe: safe)
        round = current
        if finished || index == DisplayRecheckRound.offsets.count - 1 {
            if !safe || (current.target != nil && !finished) {
                status = AppIdentity.text("显示状态尚未稳定，可重试", "Display state has not settled; retry")
            }
            cancelRound()
        }
    }

    private func cancelRound() {
        generation &+= 1
        pending.forEach { $0.cancel() }
        pending.removeAll()
        round = nil
    }
}
