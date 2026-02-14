import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let centeringService = WindowCenteringService()
    private lazy var eventObserver = WindowEventObserver(service: centeringService)
    private var statusItem: NSStatusItem?
    private var launchCenterTimer: DispatchSourceTimer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        _ = ScreenCapturePermission.ensureAuthorized(prompt: true)
        _ = AccessibilityPermission.ensureTrusted(prompt: true)
        eventObserver.start()
        centerOnceOnLaunch()
    }

    @objc private func centerNow() {
        centerNowInternal(showAlertOnFailure: true, selectionPolicy: .focusedOnly)
    }

    private func centerNowInternal(showAlertOnFailure: Bool, selectionPolicy: WindowSelectionPolicy) {
        do {
            try centeringService.centerFrontmostWindow(selectionPolicy: selectionPolicy)
        } catch {
            if let centeringError = error as? WindowCenteringError, centeringError == .fullscreenWindow {
                return
            }
            if showAlertOnFailure {
                showAlert(title: "窗口居中失败", message: error.localizedDescription)
            }
        }
    }

    @objc private func openAccessibilitySettings() {
        AccessibilityPermission.openSettings()
    }

    @objc private func openScreenCaptureSettings() {
        ScreenCapturePermission.openSettings()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if
            let iconURL = Bundle.main.url(forResource: "StatusIconTemplate", withExtension: "png"),
            let statusImage = NSImage(contentsOf: iconURL)
        {
            statusImage.isTemplate = true
            statusImage.size = NSSize(width: 18, height: 18)
            item.button?.image = statusImage
            item.button?.imagePosition = .imageOnly
            item.button?.title = ""
        } else {
            item.button?.title = "centerWindows"
        }

        let menu = NSMenu()
        menu.autoenablesItems = false

        let centerItem = menu.addItem(
            withTitle: "立即将前台窗口居中",
            action: #selector(centerNow),
            keyEquivalent: ""
        )
        centerItem.target = self

        menu.addItem(.separator())
        let permissionItem = menu.addItem(
            withTitle: "打开辅助功能权限设置",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        permissionItem.target = self
        let screenPermissionItem = menu.addItem(
            withTitle: "打开屏幕录制权限设置",
            action: #selector(openScreenCaptureSettings),
            keyEquivalent: ""
        )
        screenPermissionItem.target = self
        menu.addItem(.separator())
        let quitItem = menu.addItem(
            withTitle: "退出",
            action: #selector(quitApp),
            keyEquivalent: ""
        )
        quitItem.target = self

        item.menu = menu
        statusItem = item
    }

    private func centerOnceOnLaunch() {
        // On launch, focus/permission prompts can delay when the "real" frontmost window is stable.
        // Retry for a short period without showing alerts.
        launchCenterTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        var attempts = 0
        timer.schedule(deadline: .now() + 0.35, repeating: 0.45)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            attempts += 1
            self.centerNowInternal(showAlertOnFailure: false, selectionPolicy: .focusedOrAnyNonFullscreen)

            // Stop after a few seconds to avoid any "continuous" behavior.
            if attempts >= 10 {
                self.launchCenterTimer?.cancel()
                self.launchCenterTimer = nil
            }
        }
        launchCenterTimer = timer
        timer.resume()
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
