import Foundation

struct ApplicationIdentity {
    static let developmentBundleIdentifier = "com.local.macutils.turnintoserver.dev"
    let bundleIdentifier: String

    var isDevelopment: Bool { bundleIdentifier != "com.qianyushi.turnintoserver" }
    var allowsLegacyConfigurationMigration: Bool { !isDevelopment }
    var supportDirectoryName: String { isDevelopment ? "turnintoserver-dev" : "turnintoserver" }
    var displayName: String { isDevelopment ? "turnintoserver Dev" : "turnintoserver" }
    var socketEnvironmentKey: String { isDevelopment ? "TURNINTOSERVER_DEV_CONTROL_SOCKET" : "TURNINTOSERVER_CONTROL_SOCKET" }
    var sudoersName: String { isDevelopment ? "turnintoserver-dev" : "turnintoserver" }
    var updatesEnabled: Bool { !isDevelopment }

    func initialRoutingEnabled(saved: Bool?, legacyExists: () -> Bool) -> Bool {
        if let saved { return saved }
        return allowsLegacyConfigurationMigration && legacyExists()
    }
}

enum AppIdentity {
    static let current = ApplicationIdentity(bundleIdentifier: Bundle.main.bundleIdentifier
        ?? ApplicationIdentity.developmentBundleIdentifier)
    static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(current.supportDirectoryName, isDirectory: true)
    }
    static func text(_ chinese: String, _ english: String) -> String {
        Locale.preferredLanguages.first?.hasPrefix("zh") == true ? chinese : english
    }
}

struct OwnedRoute: Codable, Hashable {
    let service: String
    let destination: String
    let netmask: String
    let gateway: String
}

/// An exact persisted creation record, never a CIDR heuristic, establishes ownership.
struct RouteOwnership {
    private(set) var records: Set<OwnedRoute>
    init(records: Set<OwnedRoute> = []) { self.records = records }
    func owns(_ route: OwnedRoute) -> Bool { records.contains(route) }
    func conflicts(with proposed: OwnedRoute, existing: [OwnedRoute]) -> Bool {
        existing.contains { $0.service == proposed.service && $0.destination == proposed.destination
            && $0.netmask == proposed.netmask && !owns($0) }
    }
    mutating func record(_ routes: [OwnedRoute], on service: String) {
        records = Set(records.filter { $0.service != service }).union(routes)
    }
}
