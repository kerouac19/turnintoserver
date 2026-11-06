// Portions derived from Unplug, Copyright (c) 2026 Sezer Iltekin, MIT License.
// See THIRD_PARTY_NOTICES.md and Licenses/Unplug-MIT.txt.
import AppKit
import CoreGraphics
import IOKit
import IOKit.graphics
import OSLog

private let displayLog = Logger(subsystem: AppIdentity.current.bundleIdentifier, category: "display")


// Private CoreGraphics/SkyLight API: BetterDisplay'in "disconnect" özelliğinin kullandığı çağrı.
// Ekranı yazılımsal olarak bağlantıdan koparır; monitöre giden sinyal kesilir.
@_silgen_name("CGSConfigureDisplayEnabled")
func CGSConfigureDisplayEnabled(_ config: CGDisplayConfigRef, _ display: CGDirectDisplayID, _ enabled: Bool) -> CGError

// Kapatılmış ekranlar CGGetOnlineDisplayList'ten düşer; bu liste onları da içerir.
@_silgen_name("CGSGetDisplayList")
func CGSGetDisplayList(_ maxCount: UInt32, _ displays: UnsafeMutablePointer<CGDirectDisplayID>?, _ count: UnsafeMutablePointer<UInt32>) -> CGError


@MainActor
final class ExternalDisplayManager {
    var context: () -> DisplaySafetyContext = { .init(lid: .unknown, serverActive: false, transitioning: true) }

    func setExternalDisplayEnabled(_ id: UInt32, _ enabled: Bool) -> Bool {
        let current = displays()
        guard current.contains(where: { $0.id == id && !$0.builtin }) else { return false }
        var latest = context()
        latest.lid = detectedLid()
        guard enabled || DisplaySafetyPolicy.canDisable(id, displays: current, context: latest) else { return false }
        return setEnabled(id, enabled)
    }

    func reconcileSafety() -> [DisplaySnapshot] {
        let current = displays()
        var state = context()
        state.lid = detectedLid()
        if state.lid == .open, !state.transitioning {
            turnOnBuiltinDisplayIfLidOpen()
            if DisplaySafetyPolicy.needsRecovery(displays: current, context: state) { restoreIfNoActiveDisplay() }
        }
        return displays()
    }

    private let defaults = UserDefaults.standard
    private let namesKey = "displayNames"          // [String(id): name]

    /// Kapalı ekranın adı sistemden okunamadığı için açıkken görülen adlar saklanır.
    private var knownNames: [String: String] {
        get { defaults.dictionary(forKey: namesKey) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: namesKey) }
    }

    func displays() -> [DisplaySnapshot] {
        let lid = detectedLid()
        var names = knownNames
        for screen in NSScreen.screens {
            if let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
                names[String(id)] = screen.localizedName
            }
        }
        knownNames = names

        var ids = Set(onlineDisplayIDs()).union(allDisplayIDs())

        // Kapalı ekran fişi çekilince de sistem listesinde kalır; kabloyla bağlı olmayanları gösterme.
        let hardware = attachedHardware()
        ids = ids.filter { id in
            CGDisplayVendorNumber(id) != 0 && (CGDisplayIsActive(id) != 0
                || CGDisplayIsBuiltin(id) != 0 || hardware.contains { $0.matches(id) })
        }

        return ids.map { id in
            // Açık/kapalı durumu her zaman sistemden: macOS ekranı kendisi de geri açabilir
            // (örneğin fişi çekilip yeniden takılınca).
            let active = CGDisplayIsActive(id) != 0 && (CGDisplayIsBuiltin(id) == 0 || lid == .open)
            let name = names[String(id)] ?? hardware.first(where: { $0.matches(id) })?.name ?? String(format: NSLocalizedString("Display %u", comment: "Fallback display name"), id)
            return DisplaySnapshot(id: id, name: name, active: active, builtin: CGDisplayIsBuiltin(id) != 0)
        }
        .sorted { ($0.builtin ? 0 : 1, $0.name) < ($1.builtin ? 0 : 1, $1.name) }
    }

    private func onlineDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        return Array(ids.prefix(Int(count)))
    }

    /// Kapalılar dahil tüm ekranlar; üretici kimliği olmayan boş yer tutucular atlanır.
    private func allDisplayIDs() -> [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        guard CGSGetDisplayList(UInt32(ids.count), &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).filter { CGDisplayVendorNumber($0) != 0 }
    }

    private struct AttachedHardware {
        let vendor: UInt32
        let product: UInt32?
        var name: String? = nil

        func matches(_ id: CGDirectDisplayID) -> Bool {
            vendor == CGDisplayVendorNumber(id) && (product == nil || product == CGDisplayModelNumber(id))
        }
    }

    /// Kabloyla bağlı ekranların üretici/model kimlikleri. Apple Silicon'da her ekran çıkışının
    /// bir framebuffer'ı vardır ve yalnızca bağlı bir ekran varken "DisplayAttributes" taşır;
    /// Intel Mac'lerde bağlı her ekran için bir IODisplayConnect bulunur.
    private func attachedHardware() -> [AttachedHardware] {
        var result: [AttachedHardware] = []
        for serviceClass in ["IOMobileFramebuffer", "IODisplayConnect"] {
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(serviceClass), &iterator) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(iterator) }
            while case let service = IOIteratorNext(iterator), service != 0 {
                defer { IOObjectRelease(service) }
                if let attributes = IORegistryEntryCreateCFProperty(service, "DisplayAttributes" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? [String: Any],
                   let product = attributes["ProductAttributes"] as? [String: Any],
                   let vendor = (product["LegacyManufacturerID"] as? NSNumber)?.uint32Value {
                    result.append(AttachedHardware(vendor: vendor, product: (product["ProductID"] as? NSNumber)?.uint32Value,
                                                   name: product["ProductName"] as? String))
                } else if serviceClass == "IODisplayConnect",
                          let info = IODisplayCreateInfoDictionary(service, 0)?.takeRetainedValue() as? [String: Any],
                          let vendor = (info[kDisplayVendorID] as? NSNumber)?.uint32Value {
                    result.append(AttachedHardware(vendor: vendor, product: (info[kDisplayProductID] as? NSNumber)?.uint32Value))
                }
            }
        }
        return result
    }

    private var lastSafetyState = ""

    /// Gerçekten görüntü veren ekran sayısı. Sistemin ekran listesi fişi çekilen ekranı bir süre
    /// açık göstermeye devam edebildiği için harici ekranlar ancak kablosu da bağlıysa sayılır.
    /// Üreticisi olmayan 1x1'lik sahte ekran da sayılmaz.
    private func activeDisplayCount() -> Int {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        let active = ids.prefix(Int(count))
        let hardware = attachedHardware()
        let real = active.filter { id in
            CGDisplayVendorNumber(id) != 0
                && (CGDisplayIsBuiltin(id) != 0 || hardware.contains { $0.matches(id) })
        }

        let state = "active=\(Array(active)) real=\(real) attached=\(hardware.map { "\($0.vendor)/\($0.product.map(String.init) ?? "-")" })"
        if state != lastSafetyState {
            displayLog.notice("Safety check: \(state, privacy: .public)")
            lastSafetyState = state
        }
        return real.count
    }

    private let builtinKey = "builtinDisplayID"

    /// Hiç ekran kalmayınca macOS dahili ekranı listelerden düşürebiliyor; kimliğini önceden sakla.
    private func rememberBuiltinDisplay() {
        if let id = (onlineDisplayIDs() + allDisplayIDs()).first(where: { CGDisplayIsBuiltin($0) != 0 }) {
            defaults.set(Int(id), forKey: builtinKey)
        }
    }

    /// Örneğin dahili ekran kapalıyken harici ekranın fişi çekilirse hiç ekran kalmaz;
    /// bu durumda önce dahili ekranı, o da olmazsa listedeki diğer ekranları geri açar.
    private func restoreIfNoActiveDisplay() {
        guard activeDisplayCount() == 0 else {
            rememberBuiltinDisplay()
            return
        }

        if let builtin = defaults.object(forKey: builtinKey) as? Int {
            let id = CGDirectDisplayID(builtin)
            let restored = setEnabled(id, true)
            displayLog.notice("No active display left, turning on built-in display \(id): \(restored ? "ok" : "failed", privacy: .public)")
            if restored, CGDisplayIsActive(id) != 0 { return }
        }

        var ids = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        _ = CGSGetDisplayList(UInt32(ids.count), &ids, &count)
        let candidates = ids.prefix(Int(count)).filter { CGDisplayIsActive($0) == 0 }
        displayLog.notice("No active display left and built-in unknown, turning on \(Array(candidates), privacy: .public)")
        for id in candidates { setEnabled(id, true) }
    }

    /// Dahili ekran artık menüden kapatılamıyor; eski bir sürümle kapatılmış kaldıysa geri aç.
    /// Kapak kapalıyken dahili ekran zaten kapalıdır, o zaman dokunma.
    private func turnOnBuiltinDisplayIfLidOpen() {
        rememberBuiltinDisplay()
        guard detectedLid() == .open, let builtin = defaults.object(forKey: builtinKey) as? Int else { return }
        let id = CGDirectDisplayID(builtin)
        guard CGDisplayIsActive(id) == 0 else { return }
        let restored = setEnabled(id, true)
        displayLog.notice("Built-in display \(id) was off, turning it on: \(restored ? "ok" : "failed", privacy: .public)")
    }

    private func detectedLid() -> DisplaySafetyContext.Lid {
        let rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard rootDomain != 0 else { return .unknown }
        defer { IOObjectRelease(rootDomain) }
        let state = IORegistryEntryCreateCFProperty(rootDomain, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Bool
        guard let state else { return .unknown }
        return state ? .closed : .open
    }

    @discardableResult
    private func setEnabled(_ display: DisplaySnapshot, _ enabled: Bool) -> Bool {
        setEnabled(display.id, enabled)
    }

    @discardableResult
    private func setEnabled(_ id: CGDirectDisplayID, _ enabled: Bool) -> Bool {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
        guard CGSConfigureDisplayEnabled(config, id, enabled) == .success else {
            CGCancelDisplayConfiguration(config)
            return false
        }
        // forSession: oturum kapanınca/yeniden başlatınca ekranlar kendiliğinden geri gelir.
        return CGCompleteDisplayConfiguration(config, .forSession) == .success
    }
}
