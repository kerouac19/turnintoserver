import Foundation
import ServiceManagement

@MainActor
protocol PowerGuardServiceRegistering: AnyObject {
    var status: SMAppService.Status { get }
    func register() throws
}

extension SMAppService: PowerGuardServiceRegistering {}

enum PowerGuardServiceStartupFailure: LocalizedError {
    case requiresApproval
    case notReady(SMAppService.Status)
    case registrationFailed(NSError)

    var errorDescription: String? {
        switch self {
        case .requiresApproval:
            return AppIdentity.text("请在系统设置的登录项中允许开发版电源看护后台运行",
                                    "Allow the development power guard in System Settings → Login Items")
        case .notReady(let status):
            let name: String
            switch status {
            case .notRegistered: name = "notRegistered"
            case .enabled: name = "enabled"
            case .requiresApproval: name = "requiresApproval"
            case .notFound: name = "notFound"
            @unknown default: name = "unknown(\(status.rawValue))"
            }
            return AppIdentity.text("电源看护注册后仍未就绪（\(name)）。请确认应用已完整安装到应用程序目录。",
                                    "Power guard is not ready after registration (\(name)). Verify the complete app is installed in Applications.")
        case .registrationFailed(let error):
            return AppIdentity.text("电源看护注册失败", "Power guard registration failed")
                + " (\(error.domain) \(error.code)): \(error.localizedDescription)"
        }
    }
}

/// Shared by the real client and the startup regression harness.
@MainActor
enum PowerGuardServiceReadiness {
    static func ensureReady(_ service: PowerGuardServiceRegistering) throws {
        let initial = service.status
        switch initial {
        case .enabled: return
        case .requiresApproval: throw PowerGuardServiceStartupFailure.requiresApproval
        case .notRegistered, .notFound:
            // A missing BTM record is not evidence that the user denied approval.
            // Attempt one registration and let ServiceManagement report the cause.
            do { try service.register() }
            catch {
                if service.status == .requiresApproval {
                    throw PowerGuardServiceStartupFailure.requiresApproval
                }
                throw PowerGuardServiceStartupFailure.registrationFailed(error as NSError)
            }
        @unknown default: throw PowerGuardServiceStartupFailure.notReady(initial)
        }
        let afterRegistration = service.status
        switch afterRegistration {
        case .enabled: return
        case .requiresApproval: throw PowerGuardServiceStartupFailure.requiresApproval
        default: throw PowerGuardServiceStartupFailure.notReady(afterRegistration)
        }
    }
}
