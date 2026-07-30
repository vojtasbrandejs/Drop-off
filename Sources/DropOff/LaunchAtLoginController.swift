import ServiceManagement

enum LaunchAtLoginStatus: Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

protocol LaunchAtLoginServicing: AnyObject {
    var status: LaunchAtLoginStatus { get }
    func register() throws
    func unregister() throws
}

final class MainAppLaunchAtLoginService: LaunchAtLoginServicing {
    private let service: SMAppService

    init(service: SMAppService = .mainApp) {
        self.service = service
    }

    var status: LaunchAtLoginStatus {
        switch service.status {
        case .notRegistered:
            return .notRegistered
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .notFound
        @unknown default:
            return .notFound
        }
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }
}

struct LaunchAtLoginMenuPresentation: Equatable {
    let title: String
    let isChecked: Bool
    let requiresApproval: Bool
    let isEnabled: Bool
}

enum LaunchAtLoginToggleResult: Equatable {
    case enabled
    case disabled
    case requiresApproval
    case unavailable
    case failed(String)
}

final class LaunchAtLoginController {
    private let service: LaunchAtLoginServicing

    init(service: LaunchAtLoginServicing = MainAppLaunchAtLoginService()) {
        self.service = service
    }

    var status: LaunchAtLoginStatus { service.status }

    var menuPresentation: LaunchAtLoginMenuPresentation {
        switch service.status {
        case .notRegistered:
            return LaunchAtLoginMenuPresentation(
                title: "Launch at Login",
                isChecked: false,
                requiresApproval: false,
                isEnabled: true
            )
        case .enabled:
            return LaunchAtLoginMenuPresentation(
                title: "Launch at Login",
                isChecked: true,
                requiresApproval: false,
                isEnabled: true
            )
        case .requiresApproval:
            return LaunchAtLoginMenuPresentation(
                title: "Launch at Login (Approval Required)",
                isChecked: false,
                requiresApproval: true,
                isEnabled: true
            )
        case .notFound:
            return LaunchAtLoginMenuPresentation(
                title: "Launch at Login (Unavailable)",
                isChecked: false,
                requiresApproval: false,
                isEnabled: false
            )
        }
    }

    func toggle() -> LaunchAtLoginToggleResult {
        do {
            switch service.status {
            case .enabled:
                try service.unregister()
                switch service.status {
                case .notRegistered:
                    return .disabled
                case .notFound:
                    return .unavailable
                case .enabled:
                    return .failed("Launch at Login is still enabled after the disable request.")
                case .requiresApproval:
                    return .failed("Launch at Login could not be disabled because approval is still pending.")
                }
            case .notRegistered:
                try service.register()
                switch service.status {
                case .enabled:
                    return .enabled
                case .requiresApproval:
                    return .requiresApproval
                case .notFound:
                    return .unavailable
                case .notRegistered:
                    return .failed("Launch at Login remains disabled after the enable request.")
                }
            case .requiresApproval:
                return .requiresApproval
            case .notFound:
                return .unavailable
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
