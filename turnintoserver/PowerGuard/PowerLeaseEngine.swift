import Foundation

struct BrightnessRecord: Codable, Equatable {
    let uuid: String
    let value: Float
}

struct PowerLease: Codable, Equatable {
    enum Phase: String, Codable { case prepared, active, restoring }
    let id: UUID
    let pid: Int32
    let processStart: String
    let originalSleepDisabled: Bool
    var phase: Phase = .prepared
    var powerChanged = false
    var brightness: [BrightnessRecord] = []
}

protocol PowerLeaseBackend: AnyObject {
    func load() throws -> PowerLease?
    func save(_ lease: PowerLease?) throws
    func sleepDisabled() throws -> Bool
    func setSleepDisabled(_ value: Bool) throws
    func captureBrightness() throws -> [BrightnessRecord]
    func setBrightness(_ values: [BrightnessRecord]) throws
}

struct PowerGuardFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// The helper is the sole writer. Every mutation has a durable recovery intent;
/// a failed readback/save keeps the lease available for an idempotent retry.
final class PowerLeaseEngine {
    private let backend: PowerLeaseBackend
    private(set) var lease: PowerLease?

    init(backend: PowerLeaseBackend) throws {
        self.backend = backend
        lease = try backend.load()
    }

    func prepare(pid: Int32, processStart: String) throws -> UUID {
        guard lease == nil else { throw failure("A previous power session still needs recovery") }
        let candidate = PowerLease(id: UUID(), pid: pid, processStart: processStart,
                                   originalSleepDisabled: try backend.sleepDisabled())
        try backend.save(candidate)
        lease = candidate
        return candidate.id
    }

    func activate(_ token: UUID) throws {
        var current = try checked(token)
        guard current.phase == .prepared else {
            if current.phase == .active { return }
            throw failure("Recovery is still in progress")
        }
        guard try backend.sleepDisabled() == current.originalSleepDisabled else {
            throw failure("Power setting changed after preparation; refusing to take ownership")
        }
        current.powerChanged = !current.originalSleepDisabled
        try commit(current)
        if current.powerChanged { try backend.setSleepDisabled(true) }
        guard try backend.sleepDisabled() else { throw failure("Power setting verification failed") }
        current.phase = .active
        try commit(current)
    }

    func dim(_ token: UUID) throws {
        var current = try checked(token)
        guard current.phase == .active else { throw failure("Power session is not active") }
        let readings = try backend.captureBrightness()
        for value in readings where !current.brightness.contains(where: { $0.uuid == value.uuid }) {
            current.brightness.append(value)
        }
        try commit(current)
        try backend.setBrightness(readings.map { BrightnessRecord(uuid: $0.uuid, value: 0) })
    }

    func restoreBrightness(_ token: UUID) throws {
        var current = try checked(token)
        guard !current.brightness.isEmpty else { return }
        let actual = try backend.captureBrightness()
        for record in current.brightness {
            guard let value = actual.first(where: { $0.uuid == record.uuid })?.value else {
                throw failure("Built-in display is offline; brightness recovery remains pending")
            }
            guard value < 0.04 || abs(value - record.value) < 0.04 else {
                throw failure("Brightness was changed outside this session; current value preserved")
            }
        }
        try backend.setBrightness(current.brightness)
        current.brightness = []
        try commit(current)
    }

    func restore(_ token: UUID) throws {
        guard lease != nil else { return } // A repeated acknowledged restore is harmless.
        var current = try checked(token)
        current.phase = .restoring
        try commit(current)
        if current.powerChanged {
            let actual = try backend.sleepDisabled()
            if actual != current.originalSleepDisabled { try backend.setSleepDisabled(current.originalSleepDisabled) }
            guard try backend.sleepDisabled() == current.originalSleepDisabled else {
                throw failure("Power restoration verification failed")
            }
            current.powerChanged = false
            try commit(current)
        }
        try restoreBrightness(token)
        try backend.save(nil)
        lease = nil
    }

    private func checked(_ token: UUID) throws -> PowerLease {
        guard let lease, lease.id == token else { throw failure("Stale or unknown power session") }
        return lease
    }
    private func commit(_ value: PowerLease) throws {
        try backend.save(value)
        lease = value
    }
    private func failure(_ text: String) -> PowerGuardFailure { PowerGuardFailure(message: text) }
}
