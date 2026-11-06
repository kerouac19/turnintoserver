import Foundation

struct DisplaySnapshot: Equatable, Identifiable {
    let id: UInt32
    let name: String
    let active: Bool
    let builtin: Bool
}

struct DisplaySafetyContext: Equatable {
    enum Lid { case open, closed, unknown }
    var lid: Lid
    var serverActive: Bool
    var transitioning: Bool
    var allowsHeadless: Bool { lid == .closed && serverActive && !transitioning }
}

enum DisplaySafetyPolicy {
    static func canDisable(_ id: UInt32, displays: [DisplaySnapshot], context: DisplaySafetyContext) -> Bool {
        guard !context.transitioning, context.lid != .unknown,
              let target = displays.first(where: { $0.id == id }), !target.builtin else { return false }
        return displays.contains { $0.id != id && $0.active && (!$0.builtin || context.lid == .open) }
    }
    static func needsRecovery(displays: [DisplaySnapshot], context: DisplaySafetyContext) -> Bool {
        guard !context.transitioning, !context.allowsHeadless, context.lid == .open else { return false }
        return !displays.contains(where: { $0.active && (!$0.builtin || context.lid == .open) })
    }
}

/// Each event gets a finite observation window, including a late read without another callback.
struct DisplayRecheckRound {
    static let offsets: [TimeInterval] = [0, 0.25, 0.75, 1.5, 3]
    let generation: UInt64
    var target: (id: UInt32, enabled: Bool)?
    private(set) var confirmations = 0
    mutating func observe(_ displays: [DisplaySnapshot], safe: Bool) -> Bool {
        guard let target else { return false }
        let reached = displays.contains { $0.id == target.id && $0.active == target.enabled }
        confirmations = reached && safe ? confirmations + 1 : 0
        return confirmations >= 2
    }
}
