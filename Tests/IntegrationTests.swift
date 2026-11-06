import Foundation
import CoreFoundation

private var checks = 0
private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !condition() { fatalError("FAIL: \(message)") }
}
private func fails(_ message: String, _ action: () throws -> Void) {
    do { try action(); fatalError("FAIL: expected failure: \(message)") }
    catch { checks += 1 }
}

private final class MemoryPowerBackend: PowerLeaseBackend {
    var journal: PowerLease?
    var disabled = false
    var brightness: [BrightnessRecord] = [.init(uuid: "built-in", value: 0.7)]
    var events: [String] = []
    var failSave = false
    var failDelete = false
    var failPower = false
    var failBrightness = false
    var ignorePowerWrite = false
    func load() throws -> PowerLease? { journal }
    func save(_ lease: PowerLease?) throws {
        if failSave || (lease == nil && failDelete) { throw PowerGuardFailure(message: "storage failure") }
        journal = lease
        events.append(lease.map { "save:\($0.phase.rawValue)" } ?? "clear")
    }
    func sleepDisabled() throws -> Bool { disabled }
    func setSleepDisabled(_ value: Bool) throws {
        if failPower { throw PowerGuardFailure(message: "permission denied") }
        events.append("power:\(value)")
        if !ignorePowerWrite { disabled = value }
    }
    func captureBrightness() throws -> [BrightnessRecord] { brightness }
    func setBrightness(_ values: [BrightnessRecord]) throws {
        if failBrightness { throw PowerGuardFailure(message: "display offline") }
        brightness = values
        events.append("brightness")
    }
}

@main @MainActor enum IntegrationTests {
    static func main() throws {
        identityAndRoutes()
        routeStartupDoesNotTouchNetwork()
        displayPolicy()
        cleaningCounters()
        cleaningHealth()
        contactFailureStopsRenewal()
        try powerRecovery()
        print("PASS: \(checks) checks (no hardware, power, routing or permission changes)")
    }

    static func identityAndRoutes() {
        let dev = ApplicationIdentity(bundleIdentifier: ApplicationIdentity.developmentBundleIdentifier)
        var legacyRead = false
        expect(!dev.initialRoutingEnabled(saved: nil, legacyExists: { legacyRead = true; return true }), "dev does not inherit old route intent")
        expect(!legacyRead, "dev must not even inspect original LaunchAgent")
        expect(dev.initialRoutingEnabled(saved: true, legacyExists: { false }), "explicit dev preference remains available")
        let original = ApplicationIdentity(bundleIdentifier: "com.qianyushi.turnintoserver")
        expect(original.initialRoutingEnabled(saved: nil, legacyExists: { true }), "original migration policy preserved")
        expect(dev.supportDirectoryName != original.supportDirectoryName, "support isolation")
        expect(dev.sudoersName != original.sudoersName, "authorization isolation")
        expect(dev.socketEnvironmentKey != original.socketEnvironmentKey, "socket override isolation")
        expect(!dev.updatesEnabled, "no upstream updater in dev build")
        let old = OwnedRoute(service: "Wi-Fi", destination: "196.1.1.1", netmask: "255.255.255.255", gateway: "10.0.0.1")
        let other = OwnedRoute(service: "Ethernet", destination: old.destination, netmask: old.netmask, gateway: old.gateway)
        var ledger = RouteOwnership()
        expect(!ledger.owns(old), "legacy 196 route is not owned just because migration flag is empty")
        expect(ledger.conflicts(with: old, existing: [old]), "same CIDR is a conflict, never automatic takeover")
        ledger.record([old], on: old.service)
        expect(ledger.owns(old), "recorded creation establishes ownership")
        expect(!ledger.owns(other), "same route on another network service is not ours")
        ledger.record([other], on: other.service)
        ledger.record([], on: old.service)
        expect(!ledger.owns(old) && ledger.owns(other), "cleanup is scoped to the recorded network service")
    }

    static func routeStartupDoesNotTouchNetwork() {
        let suite = "integration-tests." + UUID().uuidString
        let prefs = UserDefaults(suiteName: suite)!
        prefs.setVolatileDomain([:], forName: suite)
        defer { prefs.removeVolatileDomain(forName: suite) }
        var commands: [String] = []
        let manager = AutomaticRouteManager(defaults: prefs, runCommand: { executable, arguments in
            commands.append(executable + " " + arguments.joined(separator: " "))
            throw PowerGuardFailure(message: "No real network command is allowed in this test")
        })
        var finished = false
        var failure: Error?
        Task { @MainActor in
            do { try await manager.setEnabled(false) } catch { failure = error }
            finished = true
        }
        let deadline = Date().addingTimeInterval(1)
        while !finished && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        expect(finished && failure == nil, "actual route module accepts startup-disable with empty ownership")
        expect(commands.isEmpty, "startup-disable performs zero network queries or writes without an ownership record")
    }

    static func displayPolicy() {
        let built = DisplaySnapshot(id: 1, name: "Internal", active: true, builtin: true)
        let ext = DisplaySnapshot(id: 2, name: "External", active: true, builtin: false)
        var context = DisplaySafetyContext(lid: .open, serverActive: false, transitioning: false)
        expect(DisplaySafetyPolicy.canDisable(2, displays: [built, ext], context: context), "external can stop when open internal remains")
        expect(!DisplaySafetyPolicy.canDisable(1, displays: [built, ext], context: context), "never expose internal disconnect")
        expect(!DisplaySafetyPolicy.canDisable(2, displays: [ext], context: context), "last external is protected in command policy")
        context.lid = .closed
        context.serverActive = true
        expect(context.allowsHeadless, "actual server with closed lid permits natural headless state")
        expect(!DisplaySafetyPolicy.canDisable(2, displays: [built, ext], context: context), "closed internal is not counted for manual switch")
        expect(!DisplaySafetyPolicy.needsRecovery(displays: [], context: context), "headless server does not fight recovery")
        context.lid = .unknown
        expect(!DisplaySafetyPolicy.canDisable(2, displays: [built, ext], context: context), "unknown lid denies risky close")
        context.lid = .open
        context.transitioning = true
        expect(!DisplaySafetyPolicy.canDisable(2, displays: [built, ext], context: context), "transition denies close")
        context.transitioning = false
        expect(DisplaySafetyPolicy.needsRecovery(displays: [], context: context), "open lid with no output needs recovery")
        var round = DisplayRecheckRound(generation: 1, target: nil)
        for _ in DisplayRecheckRound.offsets {
            expect(!round.observe([ext], safe: true), "unrequested topology rounds must retain late recheck even with stale identical lists")
        }
        expect(DisplayRecheckRound.offsets.count == 5 && DisplayRecheckRound.offsets.last == 3, "finite 5-read observation window")
        var target = DisplayRecheckRound(generation: 2, target: (2, true))
        expect(!target.observe([], safe: false), "not settled before target appears")
        expect(!target.observe([ext], safe: true), "one target observation insufficient")
        expect(target.observe([ext], safe: true), "two target confirmations permit early completion")
    }

    static func cleaningCounters() {
        var counter = CleaningUnlockCounter(requiredKeyCode: 53, threshold: 5, pressWindow: 6)
        for n in 0..<4 { expect(!counter.registerKeyDown(code: 53, time: Double(n), isRepeat: false), "no early escape unlock") }
        expect(!counter.registerKeyDown(code: 53, time: 4, isRepeat: true), "held Escape never counts")
        expect(counter.progress == 4, "repeat leaves count intact")
        _ = counter.registerKeyDown(code: 56, time: 4.1, isRepeat: false)
        expect(counter.progress == 0, "modifier wipes streak")
        for n in 0..<5 { _ = counter.registerKeyDown(code: 53, time: 10 + Double(n), isRepeat: false) }
        expect(counter.progress == 5, "five deliberate escapes unlock")
        _ = counter.registerKeyDown(code: 53, time: 30, isRepeat: false)
        expect(counter.progress == 1, "long gaps restart streak")
        var mouse = CleaningMouseReleaseGate()
        mouse.buttonDown(0); mouse.buttonDown(2)
        expect(!mouse.requestDeactivation(), "held mouse delays user unlock")
        expect(!mouse.buttonUp(0), "wait for every real release")
        expect(mouse.buttonUp(2), "last release completes unlock")
        mouse.reset(); mouse.buttonDown(1); _ = mouse.requestDeactivation()
        expect(mouse.releaseWaitExpired() && mouse.pressedButtons.isEmpty, "disconnected mouse cannot trap unlock")
        let media = CleaningSystemKeyEvent.decode(subtype: 8, data1: (16 << 16) | (10 << 8))
        expect(media?.isKeyDown == true && media?.code != 53, "media key resets rather than advances Escape")
    }

    static func cleaningHealth() {
        var allowed = true
        var interrupted = 0
        var queries = 0
        let monitor = CleaningHealthMonitor(allowed: { queries += 1; return allowed }, interrupted: { interrupted += 1 })
        expect(monitor.start(), "admitted when conditions allow")
        allowed = false // No keyboard event is delivered and the fake tap stays 'enabled'.
        let mode = RunLoop.Mode(rawValue: "IntegrationTrackingMode")
        CFRunLoopAddCommonMode(CFRunLoopGetMain(), CFRunLoopMode(rawValue: mode.rawValue as CFString))
        _ = RunLoop.main.run(mode: mode, before: Date().addingTimeInterval(0.25))
        expect(interrupted == 1, "independent monitor catches secure-input/session loss in tracking mode without keys")
        let stoppedQueries = queries
        _ = RunLoop.main.run(mode: mode, before: Date().addingTimeInterval(0.15))
        expect(queries == stoppedQueries, "stopped monitor never queries again")
        expect(!monitor.start(), "secure input before admission denies start")
        allowed = true
        expect(monitor.start(), "explicit new request can restart after conditions recover")
        monitor.stop()
    }

    static func contactFailureStopsRenewal() {
        var contacts = 0
        var failures = 0
        var activityReleased = 0
        let monitor = LeaseContactMonitor(interval: 0.01, contact: {
            contacts += 1
            throw PowerGuardFailure(message: "unreachable")
        }, failed: { _ in failures += 1 }, beginActivity: { { activityReleased += 1 } })
        monitor.start()
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        expect(contacts == 1 && failures == 1, "failed heartbeat stops renewal instead of perpetuating an inactive session")
        expect(activityReleased == 1, "contact failure releases App Nap suppression")
        RunLoop.main.run(until: Date().addingTimeInterval(0.06))
        expect(contacts == 1, "stopped heartbeat cannot silently restart")
    }

    static func powerRecovery() throws {
        let backend = MemoryPowerBackend()
        let engine = try PowerLeaseEngine(backend: backend)
        let token = try engine.prepare(pid: 42, processStart: "one")
        expect(!backend.disabled && backend.events == ["save:prepared"], "prepare persists before any system mutation")
        try engine.activate(token)
        expect(backend.disabled && backend.journal?.phase == .active, "activation is recorded")
        try engine.dim(token); try engine.dim(token)
        expect(engine.lease?.brightness.first?.value == 0.7, "repeated dim preserves original brightness")
        let restartedHelper = try PowerLeaseEngine(backend: backend)
        try restartedHelper.restore(token)
        expect(!backend.disabled && backend.brightness.first?.value == 0.7 && backend.journal == nil, "helper restart recovers persisted power and brightness")
        try restartedHelper.restore(token)
        expect(backend.journal == nil, "restore is idempotent after completed acknowledgement")

        let failed = MemoryPowerBackend(); failed.failSave = true
        let unprepared = try PowerLeaseEngine(backend: failed)
        fails("prepare storage failure") { _ = try unprepared.prepare(pid: 42, processStart: "two") }
        expect(!failed.disabled && failed.events.isEmpty, "failed prepare makes zero power writes")
        failed.failSave = false
        let pending = try unprepared.prepare(pid: 42, processStart: "two")
        try unprepared.restore(pending)
        expect(!failed.disabled && failed.journal == nil, "GUI crash between prepare and activate needs no mutation")

        let denied = MemoryPowerBackend(); let deniedEngine = try PowerLeaseEngine(backend: denied)
        let deniedToken = try deniedEngine.prepare(pid: 42, processStart: "three")
        denied.failPower = true
        fails("permission denial during activation") { try deniedEngine.activate(deniedToken) }
        expect(denied.journal != nil, "failed mutation retains recovery intent")
        denied.failPower = false; try deniedEngine.restore(deniedToken)

        let external = MemoryPowerBackend(); external.disabled = true
        let externalEngine = try PowerLeaseEngine(backend: external)
        let externalToken = try externalEngine.prepare(pid: 42, processStart: "four")
        try externalEngine.activate(externalToken); try externalEngine.restore(externalToken)
        expect(external.disabled && !external.events.contains("power:false"), "do not clear a pre-existing external power setting")

        let offline = MemoryPowerBackend(); let offlineEngine = try PowerLeaseEngine(backend: offline)
        let offlineToken = try offlineEngine.prepare(pid: 42, processStart: "five")
        try offlineEngine.activate(offlineToken); try offlineEngine.dim(offlineToken)
        offline.failBrightness = true
        fails("brightness restoration failure") { try offlineEngine.restore(offlineToken) }
        expect(offline.journal?.phase == .restoring && !offline.disabled, "power restored but failed brightness keeps lease")
        offline.failBrightness = false; try offlineEngine.restore(offlineToken)
        expect(offline.journal == nil, "retry finishes recovery before removing lease")

        let verify = MemoryPowerBackend(); verify.ignorePowerWrite = true
        let verifyEngine = try PowerLeaseEngine(backend: verify)
        let verifyToken = try verifyEngine.prepare(pid: 42, processStart: "six")
        fails("readback failure") { try verifyEngine.activate(verifyToken) }
        expect(verify.journal != nil, "readback failure is never reported as successful activation")

        let again = try restartedHelper.prepare(pid: 43, processStart: "new")
        fails("old lease cannot restore the next session") { try restartedHelper.restore(token) }
        expect(restartedHelper.lease?.id == again, "stale release preserves new lease")
        try restartedHelper.restore(again)

        let raced = MemoryPowerBackend(); let racedEngine = try PowerLeaseEngine(backend: raced)
        let racedToken = try racedEngine.prepare(pid: 42, processStart: "seven")
        raced.disabled = true // Another owner changed it before our activation.
        fails("external change between prepare and activation") { try racedEngine.activate(racedToken) }
        try racedEngine.restore(racedToken)
        expect(raced.disabled, "refused activation never takes ownership of another writer's change")

        let changed = MemoryPowerBackend(); let changedEngine = try PowerLeaseEngine(backend: changed)
        let changedToken = try changedEngine.prepare(pid: 42, processStart: "eight")
        try changedEngine.activate(changedToken); try changedEngine.dim(changedToken)
        changed.brightness = [.init(uuid: "built-in", value: 0.4)]
        fails("external brightness change is a conflict") { try changedEngine.restore(changedToken) }
        expect(changed.brightness.first?.value == 0.4 && changed.journal != nil, "preserve external brightness and a visible recovery failure")
        changed.brightness = [.init(uuid: "built-in", value: 0.7)]
        try changedEngine.restore(changedToken)

        let deletion = MemoryPowerBackend(); let deletionEngine = try PowerLeaseEngine(backend: deletion)
        let deletionToken = try deletionEngine.prepare(pid: 42, processStart: "nine")
        try deletionEngine.activate(deletionToken)
        deletion.failDelete = true
        fails("completion record deletion failure") { try deletionEngine.restore(deletionToken) }
        expect(!deletion.disabled && deletion.journal?.powerChanged == false, "confirmed recovery is persisted before journal deletion")
        deletion.disabled = true // A new independent owner after our completed mutation.
        deletion.failDelete = false
        try PowerLeaseEngine(backend: deletion).restore(deletionToken)
        expect(deletion.disabled, "retrying record cleanup must not restore already-released power again")
    }
}
