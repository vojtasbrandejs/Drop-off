import Foundation
import Testing
@testable import DropOff

@Test func launchAtLoginIsDefaultOffAndEnablesExplicitly() {
    let service = TestLaunchAtLoginService(status: .notRegistered)
    service.statusAfterRegister = .enabled
    let controller = LaunchAtLoginController(service: service)

    #expect(controller.menuPresentation.isChecked == false)
    #expect(controller.menuPresentation.isEnabled)
    #expect(controller.toggle() == .enabled)
    #expect(service.registerCallCount == 1)
    #expect(service.unregisterCallCount == 0)
}

@Test func launchAtLoginDisablesOnlyOnExplicitEnabledToggle() {
    let service = TestLaunchAtLoginService(status: .enabled)
    let controller = LaunchAtLoginController(service: service)

    #expect(controller.toggle() == .disabled)
    #expect(service.registerCallCount == 0)
    #expect(service.unregisterCallCount == 1)
}

@Test func existingEnabledRegistrationIsPreservedWhenStatusIsRead() {
    let service = TestLaunchAtLoginService(status: .enabled)
    let controller = LaunchAtLoginController(service: service)

    #expect(controller.menuPresentation.isChecked)
    #expect(controller.menuPresentation.title == "Launch at Login")
    #expect(service.registerCallCount == 0)
    #expect(service.unregisterCallCount == 0)
}

@Test func launchAtLoginRequiresApprovalWithoutReregistering() {
    let service = TestLaunchAtLoginService(status: .requiresApproval)
    let controller = LaunchAtLoginController(service: service)

    #expect(controller.menuPresentation.requiresApproval)
    #expect(controller.menuPresentation.title == "Launch at Login (Approval Required)")
    #expect(controller.toggle() == .requiresApproval)
    #expect(service.registerCallCount == 0)
    #expect(service.unregisterCallCount == 0)
}

@Test func registrationCanTransitionToRequiresApproval() {
    let service = TestLaunchAtLoginService(status: .notRegistered)
    service.statusAfterRegister = .requiresApproval
    let controller = LaunchAtLoginController(service: service)

    #expect(controller.toggle() == .requiresApproval)
    #expect(service.registerCallCount == 1)
    #expect(service.unregisterCallCount == 0)
}

@Test func missingLaunchAtLoginServiceIsUnavailable() {
    let service = TestLaunchAtLoginService(status: .notFound)
    let controller = LaunchAtLoginController(service: service)

    #expect(!controller.menuPresentation.isEnabled)
    #expect(controller.toggle() == .unavailable)
    #expect(service.registerCallCount == 0)
    #expect(service.unregisterCallCount == 0)
}

@Test func launchAtLoginRegistrationAndUnregistrationErrorsAreReported() {
    let enableService = TestLaunchAtLoginService(status: .notRegistered)
    enableService.registerError = TestLaunchAtLoginError(message: "register failed")
    let disableService = TestLaunchAtLoginService(status: .enabled)
    disableService.unregisterError = TestLaunchAtLoginError(message: "unregister failed")

    #expect(LaunchAtLoginController(service: enableService).toggle() == .failed("register failed"))
    #expect(LaunchAtLoginController(service: disableService).toggle() == .failed("unregister failed"))
}

@Test func enableDoesNotClaimSuccessWhenServiceRemainsUnregistered() {
    let service = TestLaunchAtLoginService(status: .notRegistered)
    service.statusAfterRegister = .notRegistered

    #expect(
        LaunchAtLoginController(service: service).toggle()
            == .failed("Launch at Login remains disabled after the enable request.")
    )
}

@Test func enableReportsUnavailableWhenServiceDisappearsAfterRegistration() {
    let service = TestLaunchAtLoginService(status: .notRegistered)
    service.statusAfterRegister = .notFound

    #expect(LaunchAtLoginController(service: service).toggle() == .unavailable)
}

@Test func disableDoesNotClaimSuccessWhenServiceRemainsEnabled() {
    let service = TestLaunchAtLoginService(status: .enabled)
    service.statusAfterUnregister = .enabled

    #expect(
        LaunchAtLoginController(service: service).toggle()
            == .failed("Launch at Login is still enabled after the disable request.")
    )
}

@Test func disableReportsUnexpectedApprovalAndUnavailableStatuses() {
    let approvalService = TestLaunchAtLoginService(status: .enabled)
    approvalService.statusAfterUnregister = .requiresApproval
    let missingService = TestLaunchAtLoginService(status: .enabled)
    missingService.statusAfterUnregister = .notFound

    #expect(
        LaunchAtLoginController(service: approvalService).toggle()
            == .failed("Launch at Login could not be disabled because approval is still pending.")
    )
    #expect(LaunchAtLoginController(service: missingService).toggle() == .unavailable)
}

private final class TestLaunchAtLoginService: LaunchAtLoginServicing {
    var status: LaunchAtLoginStatus
    var statusAfterRegister: LaunchAtLoginStatus?
    var statusAfterUnregister: LaunchAtLoginStatus = .notRegistered
    var registerError: Error?
    var unregisterError: Error?
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0

    init(status: LaunchAtLoginStatus) {
        self.status = status
    }

    func register() throws {
        registerCallCount += 1
        if let registerError { throw registerError }
        if let statusAfterRegister { status = statusAfterRegister }
    }

    func unregister() throws {
        unregisterCallCount += 1
        if let unregisterError { throw unregisterError }
        status = statusAfterUnregister
    }
}

private struct TestLaunchAtLoginError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
