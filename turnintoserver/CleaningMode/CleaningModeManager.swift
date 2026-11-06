// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Modified 2026-11-06: instance ownership, AppKit overlay, secure-input/session monitoring.

import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import Carbon

/// "Cleaning mode" temporarily locks the keyboard so the user can wipe it down
/// without typing gibberish, then restores it on a deliberate gesture. The lock
/// is a HID-level event tap that swallows key events before the system handles
/// them, including keyboard system keys such as brightness, media and volume.
/// The very same tap watches for the unlock gesture, so there is always a way
/// back.
///
/// Two deliberate escapes guarantee no one is ever stranded:
///   1. press Escape five times in a row,
///   2. click Unlock on the overlay (pointer movement and clicks stay available).
///
/// Requires Accessibility, like the app's other event taps. If it is missing the
/// tap can't be created, so we never lock the keyboard with no way to unlock it.
final class CleaningModeManager: NSObject, ObservableObject {
    @Published private(set) var status: String?
    var keepScreenVisible = false
    private var healthMonitor: CleaningHealthMonitor?
    private var sessionObservers: [NSObjectProtocol] = []
    private var sessionIsActive: Bool {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        return (session?[kCGSessionOnConsoleKey as String] as? Bool ?? false)
            && !(session?["CGSSessionScreenIsLocked"] as? Bool ?? false)
    }

    private static let systemDefinedEventType = CGEventType(rawValue: CleaningSystemKeyEvent.systemDefinedEventTypeRawValue)!
    private static let gestureEventType = CGEventType(rawValue: UInt32(NSEvent.EventType.gesture.rawValue))!
    private static let escapeKeyCode: Int64 = 53
    private static let eventMask: CGEventMask = [
        CGEventType.keyDown,
        .keyUp,
        .flagsChanged,
        .scrollWheel,
        .leftMouseDown,
        .leftMouseUp,
        .rightMouseDown,
        .rightMouseUp,
        .otherMouseDown,
        .otherMouseUp,
        systemDefinedEventType,
        gestureEventType,
    ].reduce(CGEventMask(0)) { mask, type in
        mask | (CGEventMask(1) << type.rawValue)
    }

    @Published private(set) var isActive = false
    /// Consecutive Escape presses so far (0...unlockThreshold). The
    /// overlay shows this as progress.
    @Published private(set) var unlockProgress = 0

    /// Deliberate Escape presses needed to unlock. Other keys reset the count so
    /// wiping the keyboard cannot complete the gesture accidentally.
    let unlockThreshold = 5

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var overlays: [NSPanel] = []
    private var screenObserver: NSObjectProtocol?
    // Mouse events still pass through Cleaning Mode. We only remember the
    // down/up lifecycle so teardown never cuts a click in half.
    private var mouseReleaseGate = CleaningMouseReleaseGate()
    /// Ends a user unlock's wait for a release this tap never sees.
    private var releaseDeadline: DispatchWorkItem?

    /// The unlock-gesture state machine (pure, unit-tested separately).
    /// The 6s press window forgives hesitant, deliberate presses — at 2s a user
    /// pressing Escape slower than once per two seconds could never unlock
    /// (progress restarted at 1 on every press). The window's one remaining job
    /// is rejecting five isolated Esc-only contacts spread across a long wipe:
    /// every other key resets the count — modifiers included, they reach the
    /// counter as flags-changed events — and auto-repeat never counts, but a
    /// cloth can strike Escape alone. Widening to 6s weakens that guard on
    /// purpose — a gesture a deliberate user cannot complete protects nothing.
    private lazy var unlock = CleaningUnlockCounter(requiredKeyCode: Self.escapeKeyCode,
                                                    threshold: unlockThreshold,
                                                    pressWindow: 6.0)

    override init() {
        super.init()
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.willSleepNotification,
                     NSWorkspace.willPowerOffNotification] {
            sessionObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.stop(reason: nil)
            })
        }
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(screenLocked),
            name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
    }

    deinit {
        removeTap()
        removeScreenObserver()
        hideOverlays()
        releaseDeadline?.cancel()
        healthMonitor?.stop()
        for observer in sessionObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc private func screenLocked() { stop(reason: nil) }

    func stop(reason: String?) {
        precondition(Thread.isMainThread)
        if let reason { status = reason }
        deactivateForSystemTeardown()
    }

    private func conditionsAllowCleaning() -> Bool {
        sessionIsActive && AXIsProcessTrusted() && !IsSecureEventInputEnabled()
    }

    private func installHealthMonitor() -> Bool {
        let monitor = CleaningHealthMonitor(allowed: { [weak self] in self?.conditionsAllowCleaning() ?? false },
            interrupted: { [weak self] in
                self?.stop(reason: AppIdentity.text("清洁模式已停止：安全输入、授权或会话状态发生变化",
                    "Cleaning stopped: secure input, permission or session changed"))
            })
        guard monitor.start() else { return false }
        healthMonitor = monitor
        return true
    }

    func toggle() { isActive ? deactivate() : activate() }

    /// Starts the lock. No-op (and guides the user) when Accessibility is missing,
    /// because without the tap there would be no way to unlock the keyboard.
    func activate() {
        guard !isActive else { return }
        // Check Accessibility explicitly (same gate the other event taps use) so a
        // missing grant is reported clearly, rather than inferred from a nil tap.
        guard AXIsProcessTrusted() else {
            promptForAccessibility()
            return
        }
        precondition(Thread.isMainThread)
        guard conditionsAllowCleaning() else {
            status = AppIdentity.text("无法启动清洁模式：请关闭安全键盘输入并返回当前登录会话",
                "Cannot start cleaning: disable Secure Keyboard Entry and return to the current session")
            return
        }
        mouseReleaseGate.reset()
        guard installTap() else {
            status = AppIdentity.text("无法创建输入拦截，请检查辅助功能授权", "Cannot create input filter; check Accessibility permission")
            return
        }
        guard conditionsAllowCleaning() else { removeTap(); return }
        status = nil
        guard installHealthMonitor() else { removeTap(); return }
        unlock.reset()
        unlockProgress = 0
        isActive = true
        installScreenObserver()
        showOverlays()
    }

    func deactivate() {
        guard isActive else { return }
        // If a click began while the overlay was up, keep the overlay and tap
        // alive until its real mouse-up passes through. Never manufacture a
        // release: the physical event is the only event that completes the click.
        armReleaseDeadline()
        guard mouseReleaseGate.requestDeactivation() else { return }
        scheduleUserDeactivation()
    }

    /// Every unlock path waits on the gate, and the overlay can cover the menu
    /// bar, so the wait is bounded. Nothing is posted; it only stops waiting.
    private func armReleaseDeadline() {
        guard releaseDeadline == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.releaseDeadline = nil
            guard self.isActive, self.mouseReleaseGate.releaseWaitExpired() else { return }
            self.scheduleUserDeactivation()
        }
        releaseDeadline = work
        DispatchQueue.main.asyncAfter(deadline: .now() + CleaningMouseReleaseGate.releaseWaitLimit, execute: work)
    }

    /// Permission teardown must remove the tap before Accessibility is reset.
    func deactivateForSystemTeardown() {
        stopImmediately()
    }

    private func stopImmediately() {
        guard isActive else { return }
        // Session/tap failure paths cannot wait for another input event. They
        // retain the existing fail-open behaviour and tear down immediately.
        finishDeactivation()
    }

    private func scheduleUserDeactivation() {
        // Even when no button is currently held, leave the AppKit control action
        // before unmapping its non-activating panel. A new press may arrive before
        // this block runs, so keep the request pending until teardown completes.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isActive, self.mouseReleaseGate.deactivationPending,
                  self.mouseReleaseGate.pressedButtons.isEmpty else { return }
            self.finishDeactivation()
        }
    }

    private func finishDeactivation() {
        guard isActive else { return }
        releaseDeadline?.cancel()
        releaseDeadline = nil
        mouseReleaseGate.reset()
        removeTap()
        removeScreenObserver()
        hideOverlays()
        unlock.reset()
        unlockProgress = 0
        isActive = false
        healthMonitor?.stop()
        healthMonitor = nil
    }

    // MARK: - Event tap

    private func installTap() -> Bool {
        let mask = Self.eventMask
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<CleaningModeManager>.fromOpaque(userInfo).takeUnretainedValue()
                return manager.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        self.tap = tap
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            self.tap = nil
            return false
        }
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func removeTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        runLoopSource = nil
    }

    /// The tap callback. Its run-loop source lives on the main run loop, so this
    /// runs on the main thread and can touch published state and AppKit directly.
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The system disables taps that stall or when the session locks; re-arm so
        // the keyboard stays locked instead of silently coming back.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if sessionIsActive, AXIsProcessTrusted(), let tap {
                // A disabled tap creates an observation gap: any tracked mouseDown
                // may already have received its real mouseUp while we were blind.
                // Invalidate that incomplete sequence so no later unlock can wait
                // forever for a release that already happened. If the user had
                // already requested deactivation, fail open after the callback.
                let shouldFinishUserDeactivation = mouseReleaseGate.deactivationPending
                mouseReleaseGate.invalidateTrackedPresses()
                CGEvent.tapEnable(tap: tap, enable: true)
                if shouldFinishUserDeactivation {
                    scheduleUserDeactivation()
                }
                return nil
            }
            DispatchQueue.main.async { [weak self] in
                self?.stopImmediately()
            }
            return Unmanaged.passUnretained(event)
        }

        // Mouse clicks are never locked. Observe only their boundaries so a
        // user-requested teardown can wait for a matching real release.
        if handleMouseButton(type: type, event: event) {
            return Unmanaged.passUnretained(event)
        }

        // Feed key-downs to the unlock state machine. Auto-repeat (holding a key)
        // is ignored, so only distinct, deliberate taps of the same key count.
        if type == .keyDown {
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            registerUnlockKeyDown(code: code, isRepeat: isRepeat)
        } else if type == .flagsChanged {
            // Shift, control, option, command, fn and caps lock arrive here rather
            // than as key-downs, and they are the keys nearest Escape — a cloth
            // resting on them must reset the count like any other key. Both the
            // press and the release report the same key code and neither is
            // Escape, so each one resets and the pair is idempotent. Modifiers
            // never auto-repeat.
            registerUnlockKeyDown(code: event.getIntegerValueField(.keyboardEventKeycode),
                                  isRepeat: false)
        } else if type == Self.systemDefinedEventType,
                  let systemKey = systemKeyEvent(from: event),
                  systemKey.isKeyDown {
            registerUnlockKeyDown(code: systemKey.code, isRepeat: systemKey.isRepeat)
        }

        // Swallow keys, scrolling and trackpad gestures while the lock is on.
        // Pointer movement and clicks remain available for the Unlock button.
        return nil
    }

    private func handleMouseButton(type: CGEventType, event: CGEvent) -> Bool {
        let button: Int64
        let isDown: Bool
        switch type {
        case .leftMouseDown:
            button = 0
            isDown = true
        case .leftMouseUp:
            button = 0
            isDown = false
        case .rightMouseDown:
            button = 1
            isDown = true
        case .rightMouseUp:
            button = 1
            isDown = false
        case .otherMouseDown:
            button = event.getIntegerValueField(.mouseEventButtonNumber)
            isDown = true
        case .otherMouseUp:
            button = event.getIntegerValueField(.mouseEventButtonNumber)
            isDown = false
        default:
            return false
        }

        if isDown {
            mouseReleaseGate.buttonDown(button)
        } else if mouseReleaseGate.buttonUp(button) {
            // The callback is running on this tap's run loop. Removing the tap
            // here would invalidate it from its own callback stack, so finish on
            // the next main-loop turn after the real release has propagated.
            scheduleUserDeactivation()
        }
        return true
    }

    private func systemKeyEvent(from event: CGEvent) -> CleaningSystemKeyEvent? {
        guard let nsEvent = NSEvent(cgEvent: event) else { return nil }
        return CleaningSystemKeyEvent.decode(subtype: Int(nsEvent.subtype.rawValue),
                                             data1: nsEvent.data1)
    }

    private func registerUnlockKeyDown(code: Int64, isRepeat: Bool) {
        let unlocked = unlock.registerKeyDown(code: code,
                                              time: ProcessInfo.processInfo.systemUptime,
                                              isRepeat: isRepeat)
        unlockProgress = unlock.progress
        if unlocked {
            // deactivate() only records the request here; actual teardown is
            // scheduled after this tap callback has returned.
            deactivate()
        }
    }

    // MARK: - Overlay

    private func showOverlays() {
        let frames = NSScreen.screens.map(\.frame)
        let targetFrames = frames.isEmpty
            ? [NSRect(x: 0, y: 0, width: 800, height: 600)]
            : frames
        // Screen notifications can arrive in bursts even when the frames stay
        // unchanged. Reuse those panels so the overlay never flashes or drops a click.
        var reusable = overlays
        overlays = targetFrames.map { frame in
            if let index = reusable.firstIndex(where: { $0.frame == frame }) {
                return reusable.remove(at: index)
            }
            return makeOverlay(frame: frame)
        }
        reusable.forEach { $0.orderOut(nil) }
    }

    private func makeOverlay(frame: NSRect) -> NSPanel {
        let panel = CleaningPanel(contentRect: frame,
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        // Above the menu bar and full-screen apps — the shielding level macOS uses
        // for its own lock-style windows.
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // acceptsFirstMouse so the Unlock button fires on the very first click even
        // though the panel never becomes key or activates the app — otherwise that
        // click would just be absorbed as the window-activating click.
        let host = CleaningSurface(manager: self, keepScreenVisible: keepScreenVisible)
        host.frame = NSRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.orderFrontRegardless()
        return panel
    }

    private func hideOverlays() {
        overlays.forEach { $0.orderOut(nil) }
        overlays = []
    }

    private func installScreenObserver() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard self?.isActive == true else { return }
            self?.showOverlays()
        }
    }

    private func removeScreenObserver() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        screenObserver = nil
    }

    private final class CleaningPanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override func accessibilitySubrole() -> NSAccessibility.Subrole? { .unknown }
    }

    private func promptForAccessibility() {
        status = AppIdentity.text("清洁模式需要辅助功能授权", "Cleaning mode requires Accessibility permission")
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
