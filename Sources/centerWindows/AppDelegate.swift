import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let centeringService = WindowCenteringService()
    private var statusItem: NSStatusItem?
    private var autoCenterTimer: Timer?
    private var autoCenterEnabled = true
    private let detectionIntervals: [TimeInterval] = [1.0, 2.0, 5.0]
    private var currentIntervalIndex = 1
    private var autoCenterToggleItem: NSMenuItem?
    private var intervalItem: NSMenuItem?
    private var crossScreenFallbackEnabled = true
    private var crossScreenFallbackItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        _ = ScreenCapturePermission.ensureAuthorized(prompt: true)
        _ = AccessibilityPermission.ensureTrusted(prompt: true)
        centerOnceOnLaunch()
        restartAutoCenterTimerIfNeeded()
    }

    @objc private func centerNow() {
        do {
            try centeringService.centerFrontmostWindow(selectionPolicy: selectionPolicy)
        } catch {
            if let centeringError = error as? WindowCenteringError, centeringError == .fullscreenWindow {
                return
            }
            showAlert(title: "窗口居中失败", message: error.localizedDescription)
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

    @objc private func toggleAutoCenter() {
        autoCenterEnabled.toggle()
        autoCenterToggleItem?.state = autoCenterEnabled ? .on : .off
        restartAutoCenterTimerIfNeeded()
    }

    @objc private func cycleDetectionInterval() {
        currentIntervalIndex = (currentIntervalIndex + 1) % detectionIntervals.count
        intervalItem?.title = intervalMenuTitle
        if autoCenterEnabled {
            restartAutoCenterTimerIfNeeded()
        }
    }

    @objc private func toggleCrossScreenFallback() {
        crossScreenFallbackEnabled.toggle()
        crossScreenFallbackItem?.state = crossScreenFallbackEnabled ? .on : .off
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

        let toggleItem = menu.addItem(
            withTitle: "自动居中检测",
            action: #selector(toggleAutoCenter),
            keyEquivalent: ""
        )
        toggleItem.target = self
        toggleItem.state = autoCenterEnabled ? .on : .off
        autoCenterToggleItem = toggleItem

        let intervalItem = menu.addItem(
            withTitle: intervalMenuTitle,
            action: #selector(cycleDetectionInterval),
            keyEquivalent: ""
        )
        intervalItem.target = self
        self.intervalItem = intervalItem

        let fallbackItem = menu.addItem(
            withTitle: "多屏回退到非全屏窗口",
            action: #selector(toggleCrossScreenFallback),
            keyEquivalent: ""
        )
        fallbackItem.target = self
        fallbackItem.state = crossScreenFallbackEnabled ? .on : .off
        crossScreenFallbackItem = fallbackItem

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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.centerNow()
        }
    }

    private var intervalMenuTitle: String {
        let interval = detectionIntervals[currentIntervalIndex]
        return String(format: "检测间隔：%.0f 秒（点击切换）", interval)
    }

    private var selectionPolicy: WindowSelectionPolicy {
        crossScreenFallbackEnabled ? .focusedOrAnyNonFullscreen : .focusedOnly
    }

    private func restartAutoCenterTimerIfNeeded() {
        autoCenterTimer?.invalidate()
        autoCenterTimer = nil

        guard autoCenterEnabled else {
            return
        }

        let interval = detectionIntervals[currentIntervalIndex]
        autoCenterTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard AccessibilityPermission.ensureTrusted(prompt: false) else { return }
                try? self.centeringService.centerFrontmostWindow(selectionPolicy: self.selectionPolicy)
            }
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
