import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let shelfManager = ShelfManager()
    private let launchAtLoginController = LaunchAtLoginController()
    private var shakeDetector: ShakeDetector?
    private var statusItem: NSStatusItem?
    private weak var launchAtLoginMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureApplicationIcon()
        configureStatusItem()

        shakeDetector = ShakeDetector(
            shouldOpenShelfAt: { [weak shelfManager] point in
                guard let shelfManager else { return false }
                return !shelfManager.containsScreenPoint(point)
            },
            onShake: { [weak shelfManager] activation in
                shelfManager?.createShelf(from: activation)
            }
        )
        shakeDetector?.start()

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-test-shelf") {
            let point = NSScreen.main.map {
                NSPoint(x: $0.visibleFrame.midX, y: $0.visibleFrame.midY)
            } ?? NSEvent.mouseLocation
            let shelf = shelfManager.createShelf(near: point)
            let testURLs = ProcessInfo.processInfo.arguments.compactMap { argument -> URL? in
                let prefix = "--ui-test-file="
                guard argument.hasPrefix(prefix) else { return nil }
                return URL(fileURLWithPath: String(argument.dropFirst(prefix.count)))
            }
            shelf.model.add(urls: testURLs)
        }
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        DistributedNotificationCenter.default().removeObserver(self)
        shakeDetector?.stop()
        shelfManager.closeAllShelves()
    }

    private func configureApplicationIcon() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(interfaceThemeDidChange),
            name: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
        updateApplicationIcon()
    }

    @objc private func interfaceThemeDidChange(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.updateApplicationIcon()
        }
    }

    private func updateApplicationIcon() {
        let appearance = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
        let resourceName = appearance == .darkAqua ? "AppIconDark" : "AppIcon"
        guard
            let iconURL = Bundle.main.url(forResource: resourceName, withExtension: "icns"),
            let icon = NSImage(contentsOf: iconURL)
        else { return }

        NSApp.applicationIconImage = icon
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "tray.2.fill",
                accessibilityDescription: "Drop-off"
            )
            button.toolTip = "Drop-off"
        }

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(menuItem("New Shelf", action: #selector(newShelf)))
        menu.addItem(menuItem("Close All Shelves", action: #selector(closeAllShelves)))
        menu.addItem(.separator())
        let launchAtLoginItem = menuItem(
            "Launch at Login",
            action: #selector(toggleLaunchAtLogin)
        )
        menu.addItem(launchAtLoginItem)
        launchAtLoginMenuItem = launchAtLoginItem
        updateLaunchAtLoginMenuItem()
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit", action: #selector(quit)))
        item.menu = menu
        statusItem = item
    }

    private func menuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func newShelf() {
        shelfManager.createShelf(near: NSEvent.mouseLocation)
    }

    @objc private func closeAllShelves() {
        shelfManager.closeAllShelves()
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateLaunchAtLoginMenuItem()
    }

    @objc private func toggleLaunchAtLogin() {
        switch launchAtLoginController.toggle() {
        case .enabled, .disabled:
            break
        case .requiresApproval:
            showLaunchAtLoginApprovalPrompt()
        case .unavailable:
            showAlert(
                title: "Launch at Login Is Unavailable",
                message: "Move Drop-off.app to Applications, then try again."
            )
        case let .failed(message):
            showAlert(
                title: "Launch at Login Couldn’t Be Changed",
                message: message
            )
        }
        updateLaunchAtLoginMenuItem()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func updateLaunchAtLoginMenuItem() {
        guard let launchAtLoginMenuItem else { return }
        let presentation = launchAtLoginController.menuPresentation
        launchAtLoginMenuItem.title = presentation.title
        launchAtLoginMenuItem.state = presentation.requiresApproval
            ? .mixed
            : (presentation.isChecked ? .on : .off)
        launchAtLoginMenuItem.isEnabled = presentation.isEnabled
        launchAtLoginMenuItem.toolTip = presentation.requiresApproval
            ? "Allow Drop-off in System Settings → General → Login Items."
            : nil
    }

    private func showLaunchAtLoginApprovalPrompt() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Approval Required"
        alert.informativeText = "Drop-off is waiting for approval in System Settings → General → Login Items."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Login Items")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    private func showAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
