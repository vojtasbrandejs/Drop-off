import AppKit

@main
enum DropOffApplication {
    @MainActor
    static func main() {
        guard let instanceLock = SingleInstanceLock() else {
            activateExistingInstance()
            return
        }

        let application = NSApplication.shared
        let applicationDelegate = AppDelegate()
        application.delegate = applicationDelegate
        withExtendedLifetime(instanceLock) {
            application.run()
        }
    }

    private static func activateExistingInstance() {
        let bundleIdentifier = "com.vojtechbrandejs.dropoff"
        let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .first { $0.processIdentifier != currentProcessIdentifier }?
            .activate(options: [])
    }
}
