import AppKit
import Darwin
import IOKit
import ServiceManagement

enum GuardAction: String, Codable { case ping, prepare, activate, dim, restoreBrightness, restore, heartbeat }
struct GuardRequest: Codable {
    let version: Int
    let bundleIdentifier: String
    let id: UUID
    let action: GuardAction
    let pid: Int32
    let processStart: String
    let token: UUID?
}
struct GuardReply: Codable {
    let version: Int
    let helperPID: Int32
    let helperStart: String
    let id: UUID
    let token: UUID?
    let error: String?
}

enum GuardProcess {
    static func startMarker(_ pid: Int32) -> String? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
              info.pbi_uid == getuid() else { return nil }
        return "\(info.pbi_start_tvsec):\(info.pbi_start_tvusec)"
    }
    static func isOurExecutable(_ pid: Int32) -> Bool {
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0,
              let executable = Bundle.main.executableURL else { return false }
        return URL(fileURLWithPath: String(cString: path)).resolvingSymlinksInPath()
            == executable.resolvingSymlinksInPath()
    }
}

enum GuardFiles {
    static var directory: URL { AppIdentity.supportDirectory.appendingPathComponent("PowerGuard", isDirectory: true) }
    static var journal: URL { directory.appendingPathComponent("lease.json") }

    static func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else {
            throw PowerGuardFailure(message: "Invalid power guard directory")
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try JSONEncoder().encode(value)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw PowerGuardFailure(message: "Cannot synchronize guard record") }
        defer { close(fd) }
        guard fsync(fd) == 0 else { throw PowerGuardFailure(message: "Cannot persist guard record") }
        let directoryFD = open(url.deletingLastPathComponent().path, O_RDONLY)
        if directoryFD >= 0 { _ = fsync(directoryFD); close(directoryFD) }
    }

    static func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attrs[.type] as? FileAttributeType == .typeRegular,
              (attrs[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              ((attrs[.size] as? NSNumber)?.intValue ?? Int.max) <= 65_536 else {
            throw PowerGuardFailure(message: "Invalid guard record")
        }
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }
}

final class SystemPowerLeaseBackend: PowerLeaseBackend {
    private let dimmer = BuiltInDisplayDimmer()
    func load() throws -> PowerLease? {
        guard FileManager.default.fileExists(atPath: GuardFiles.journal.path) else { return nil }
        return try GuardFiles.read(PowerLease.self, from: GuardFiles.journal)
    }
    func save(_ lease: PowerLease?) throws {
        if let lease { try GuardFiles.write(lease, to: GuardFiles.journal) }
        else if FileManager.default.fileExists(atPath: GuardFiles.journal.path) {
            try FileManager.default.removeItem(at: GuardFiles.journal)
        }
    }
    func sleepDisabled() throws -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { throw PowerGuardFailure(message: "Power state unavailable") }
        defer { IOObjectRelease(service) }
        guard let state = IORegistryEntryCreateCFProperty(service, "SleepDisabled" as CFString,
            kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool else {
            throw PowerGuardFailure(message: "Cannot read SleepDisabled; refusing to guess an original value")
        }
        return state
    }
    func setSleepDisabled(_ value: Bool) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-n", "/usr/bin/pmset", "disablesleep", value ? "1" : "0"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.1)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            throw PowerGuardFailure(message: "Power command timed out; recovery record retained")
        }
        guard process.terminationStatus == 0 else { throw PowerGuardFailure(message: "Power recovery permission unavailable") }
    }
    static var lidIsClosed: Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }
        return IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString,
            kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool == true
    }
    func captureBrightness() throws -> [BrightnessRecord] { try dimmer.captureRecords() }
    func setBrightness(_ values: [BrightnessRecord]) throws { try dimmer.applyRecords(values) }
}

/// A signed LaunchAgent runs the same executable with --power-guard. Only fixed
/// operations are decoded. Requests are confined to a user-owned 0700 mailbox.
@MainActor
final class PowerSessionGuardServer {
    private let engine: PowerLeaseEngine
    private var lastContact = ProcessInfo.processInfo.systemUptime
    private var directorySource: DispatchSourceFileSystemObject?
    private var ownerSource: DispatchSourceProcess?
    private var health: Timer?
    private var observers: [NSObjectProtocol] = []
    private var sleeping = false
    private var lastRecoveryFailure: String?
    private var activity: NSObjectProtocol?
    private var lockFD: Int32 = -1

    init() throws {
        try GuardFiles.ensureDirectory()
        lockFD = open(GuardFiles.directory.appendingPathComponent("agent.lock").path, O_CREAT | O_RDWR, 0o600)
        guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
            throw PowerGuardFailure(message: "Another power guard is running")
        }
        engine = try PowerLeaseEngine(backend: SystemPowerLeaseBackend())
    }

    func run() {
        let fd = open(GuardFiles.directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write], queue: .main)
        source.setEventHandler { [weak self] in self?.processRequests() }
        source.setCancelHandler { close(fd) }
        directorySource = source
        source.resume()
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.sleeping = true
                if let lease = self.engine.lease { try? self.engine.restore(lease.id) }
                self.updateActivity()
            }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sleeping = false
                self?.lastContact = ProcessInfo.processInfo.systemUptime
            }
        })
        health = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.recoverIfNeeded() }
        }
        watchOwner()
        recoverIfNeeded()
        processRequests()
        RunLoop.main.run()
    }

    private func recoverIfNeeded() {
        defer { updateActivity() }
        guard let lease = engine.lease else { return }
        let dead = GuardProcess.startMarker(lease.pid) != lease.processStart
        let expired = !sleeping && ProcessInfo.processInfo.systemUptime - lastContact > 30
        if dead || expired || lease.phase == .restoring {
            do { try engine.restore(lease.id); lastRecoveryFailure = nil }
            catch {
                if lastRecoveryFailure != error.localizedDescription {
                    lastRecoveryFailure = error.localizedDescription
                    NSLog("Power guard recovery pending: %@", error.localizedDescription)
                }
            }
        }
    }

    private func watchOwner() {
        updateActivity()
        ownerSource?.cancel()
        ownerSource = nil
        guard let lease = engine.lease else { return }
        let source = DispatchSource.makeProcessSource(identifier: lease.pid, eventMask: .exit, queue: .main)
        source.setEventHandler { [weak self] in self?.recoverIfNeeded() }
        ownerSource = source
        source.resume()
    }

    private func updateActivity() {
        if engine.lease != nil, activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep],
                reason: "Keeps the power recovery guard responsive")
        } else if engine.lease == nil, let current = activity {
            ProcessInfo.processInfo.endActivity(current)
            activity = nil
        }
    }

    private func processRequests() {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: GuardFiles.directory,
            includingPropertiesForKeys: nil) else { return }
        for url in urls where url.lastPathComponent.hasPrefix("request-") && url.pathExtension == "json" {
            defer { try? FileManager.default.removeItem(at: url); updateActivity() }
            guard let request = try? GuardFiles.read(GuardRequest.self, from: url),
                  request.version == 1, request.bundleIdentifier == AppIdentity.current.bundleIdentifier,
                  url.lastPathComponent == "request-\(request.id.uuidString).json",
                  GuardProcess.startMarker(request.pid) == request.processStart,
                  GuardProcess.isOurExecutable(request.pid) else { continue }
            var token = request.token
            var failure: String?
            do {
                if let lease = engine.lease, request.action != .ping {
                    guard lease.pid == request.pid && lease.processStart == request.processStart else {
                        throw PowerGuardFailure(message: "A different application instance owns the power session")
                    }
                }
                if sleeping && [.prepare, .activate, .dim].contains(request.action) {
                    throw PowerGuardFailure(message: "System is entering sleep; no new power mutation is allowed")
                }
                switch request.action {
                case .ping:
                    recoverIfNeeded()
                    if let lease = engine.lease, lease.pid != request.pid || lease.processStart != request.processStart {
                        throw PowerGuardFailure(message: "Previous power session recovery is still pending")
                    }
                case .prepare:
                    token = try engine.prepare(pid: request.pid, processStart: request.processStart)
                    lastContact = ProcessInfo.processInfo.systemUptime
                    watchOwner()
                case .activate: try engine.activate(try requiredToken(token))
                case .dim:
                    if SystemPowerLeaseBackend.lidIsClosed { try engine.dim(try requiredToken(token)) }
                case .restoreBrightness: try engine.restoreBrightness(try requiredToken(token))
                case .restore: try engine.restore(try requiredToken(token))
                case .heartbeat:
                    guard token == engine.lease?.id, token != nil else { throw PowerGuardFailure(message: "Unknown lease") }
                    lastContact = ProcessInfo.processInfo.systemUptime
                }
            } catch { failure = error.localizedDescription }
            try? GuardFiles.write(GuardReply(version: 1, helperPID: getpid(),
                                  helperStart: GuardProcess.startMarker(getpid()) ?? "",
                                  id: request.id, token: token, error: failure),
                                  to: GuardFiles.directory.appendingPathComponent("response-\(request.id.uuidString).json"))
        }
    }
    private func requiredToken(_ token: UUID?) throws -> UUID {
        guard let token else { throw PowerGuardFailure(message: "Missing power lease") }
        return token
    }
}

actor PowerGuardMailbox {
    func exchange(_ action: GuardAction, token: UUID? = nil, timeout: TimeInterval = 5) async throws -> GuardReply {
        try GuardFiles.ensureDirectory()
        let pid = ProcessInfo.processInfo.processIdentifier
        guard let marker = GuardProcess.startMarker(pid) else { throw PowerGuardFailure(message: "Cannot identify process") }
        let request = GuardRequest(version: 1, bundleIdentifier: AppIdentity.current.bundleIdentifier,
                                   id: UUID(), action: action, pid: pid, processStart: marker, token: token)
        let input = GuardFiles.directory.appendingPathComponent("request-\(request.id.uuidString).json")
        let output = GuardFiles.directory.appendingPathComponent("response-\(request.id.uuidString).json")
        defer { try? FileManager.default.removeItem(at: input); try? FileManager.default.removeItem(at: output) }
        try GuardFiles.write(request, to: input)
        let start = ProcessInfo.processInfo.systemUptime
        while ProcessInfo.processInfo.systemUptime - start < timeout {
            if FileManager.default.fileExists(atPath: output.path) {
                let reply = try GuardFiles.read(GuardReply.self, from: output)
                guard reply.id == request.id, reply.version == 1,
                      GuardProcess.startMarker(reply.helperPID) == reply.helperStart,
                      GuardProcess.isOurExecutable(reply.helperPID) else {
                    throw PowerGuardFailure(message: "Mismatched or stale guard identity")
                }
                if let error = reply.error { throw PowerGuardFailure(message: error) }
                return reply
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw PowerGuardFailure(message: "Power guard did not confirm the operation; recovery record is retained")
    }
}

@MainActor
final class PowerSessionGuardClient {
    var onFailure: ((String) -> Void)?
    private let mailbox = PowerGuardMailbox()
    private let service = SMAppService.agent(plistName: "com.local.macutils.turnintoserver.dev.power-guard.plist")
    private var token: UUID?
    private var contactMonitor: LeaseContactMonitor?
    private var restoring = false
    var hasSession: Bool { token != nil }

    func begin() async throws {
        if token != nil { try await restore() }
        try PowerGuardServiceReadiness.ensureReady(service)
        _ = try await mailbox.exchange(.ping)
        // Non-mutating sudo policy checks happen before preparing or changing state.
        for value in ["0", "1"] {
            let result = try await ShellRunner.run("/usr/bin/sudo", arguments: ["-n", "-l", "/usr/bin/pmset", "disablesleep", value])
            guard result.exitCode == 0 else { throw PowerGuardFailure(message: "Power guard permission preflight failed") }
        }
        token = try await mailbox.exchange(.prepare).token
        guard let token else { throw PowerGuardFailure(message: "Guard did not prepare a recovery lease") }
        do { _ = try await mailbox.exchange(.activate, token: token) }
        catch { try? await restore(); throw error }
        let monitor = LeaseContactMonitor(contact: { [weak self] in
            guard let self else { throw PowerGuardFailure(message: "Power session ended") }
            _ = try await self.mailbox.exchange(.heartbeat, token: token)
        }, failed: { [weak self] error in
            guard let self, self.token == token, !self.restoring else { return }
            self.onFailure?(error.localizedDescription)
        })
        contactMonitor = monitor
        monitor.start()
    }
    func dim() async throws {
        guard let token else { throw PowerGuardFailure(message: "Power guard has no active session") }
        _ = try await mailbox.exchange(.dim, token: token)
    }
    func restoreBrightness() async throws {
        guard let token else { return }
        _ = try await mailbox.exchange(.restoreBrightness, token: token)
    }
    func restore() async throws {
        guard let token else { return }
        restoring = true
        defer { restoring = false }
        contactMonitor?.stop()
        contactMonitor = nil
        _ = try await mailbox.exchange(.restore, token: token, timeout: 10)
        self.token = nil
        // The restore ACK precedes unregister, which can kill the running helper.
        do { try await service.unregister() }
        catch { NSLog("Power restored; background item unregistration failed: %@", error.localizedDescription) }
    }
}
