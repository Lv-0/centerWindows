import AppKit
import ApplicationServices

enum WindowCenteringError: LocalizedError {
    case accessibilityPermissionMissing
    case noFrontmostApplication
    case noWindow
    case unableToReadWindowFrame
    case unableToWriteWindowPosition

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionMissing:
            return "缺少辅助功能权限，请在“系统设置 -> 隐私与安全性 -> 辅助功能”中授权。"
        case .noFrontmostApplication:
            return "未检测到前台应用。"
        case .noWindow:
            return "前台应用没有可操作窗口。"
        case .unableToReadWindowFrame:
            return "无法读取窗口位置或尺寸。"
        case .unableToWriteWindowPosition:
            return "无法设置窗口位置（窗口可能不可移动）。"
        }
    }
}

final class WindowCenteringService {
    private enum CoordinateMode {
        case bottomLeft
        case topLeft(screenTop: CGFloat)
    }

    func centerFrontmostWindow() throws {
        guard AccessibilityPermission.ensureTrusted(prompt: false) else {
            throw WindowCenteringError.accessibilityPermissionMissing
        }

        guard let app = NSWorkspace.shared.frontmostApplication else {
            throw WindowCenteringError.noFrontmostApplication
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let windowElement = focusedWindowElement(for: appElement) else {
            throw WindowCenteringError.noWindow
        }

        guard
            let currentPosition = pointAttribute(kAXPositionAttribute as CFString, on: windowElement),
            let windowSize = sizeAttribute(kAXSizeAttribute as CFString, on: windowElement)
        else {
            throw WindowCenteringError.unableToReadWindowFrame
        }

        guard let context = detectWindowContext(rawPosition: currentPosition, windowSize: windowSize) else {
            throw WindowCenteringError.unableToReadWindowFrame
        }

        let visibleFrame = effectiveVisibleFrame(for: context.screen)
        let centeredBottomLeftOrigin = WindowGeometry.centeredOrigin(windowSize: windowSize, visibleFrame: visibleFrame)
        let targetAXOrigin = CGPoint(
            x: centeredBottomLeftOrigin.x,
            y: toAXY(bottomLeftY: centeredBottomLeftOrigin.y, windowHeight: windowSize.height, mode: context.mode)
        )

        guard setPointAttribute(kAXPositionAttribute as CFString, value: targetAXOrigin, on: windowElement) else {
            throw WindowCenteringError.unableToWriteWindowPosition
        }
    }

    private func focusedWindowElement(for appElement: AXUIElement) -> AXUIElement? {
        if let focused = windowAttribute(kAXFocusedWindowAttribute as CFString, on: appElement) {
            return focused
        }

        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)
        guard result == .success else {
            return nil
        }

        return (value as? [AXUIElement])?.first
    }

    private func windowAttribute(_ attribute: CFString, on element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let value else {
            return nil
        }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private func pointAttribute(_ attribute: CFString, on element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        guard let value else {
            return nil
        }
        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = unsafeDowncast(value, to: AXValue.self)

        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else {
            return nil
        }
        return point
    }

    private func sizeAttribute(_ attribute: CFString, on element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        guard let value else {
            return nil
        }
        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = unsafeDowncast(value, to: AXValue.self)

        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else {
            return nil
        }
        return size
    }

    private func setPointAttribute(_ attribute: CFString, value: CGPoint, on element: AXUIElement) -> Bool {
        var mutablePoint = value
        guard let axValue = AXValueCreate(.cgPoint, &mutablePoint) else {
            return false
        }
        return AXUIElementSetAttributeValue(element, attribute, axValue) == .success
    }

    private func detectWindowContext(rawPosition: CGPoint, windowSize: CGSize) -> (screen: NSScreen, mode: CoordinateMode)? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }

        var best: (screen: NSScreen, mode: CoordinateMode, overlap: CGFloat)?

        for screen in screens {
            let convertedBottomY = screen.frame.maxY - rawPosition.y - windowSize.height
            let convertedRect = CGRect(
                x: rawPosition.x,
                y: convertedBottomY,
                width: windowSize.width,
                height: windowSize.height
            )
            let topOverlap = convertedRect.intersection(screen.frame).area
            updateBest(
                best: &best,
                candidate: (screen, .topLeft(screenTop: screen.frame.maxY), topOverlap)
            )

            let bottomRect = CGRect(origin: rawPosition, size: windowSize)
            let bottomOverlap = bottomRect.intersection(screen.frame).area
            updateBest(
                best: &best,
                candidate: (screen, .bottomLeft, bottomOverlap)
            )
        }

        if let best {
            return (best.screen, best.mode)
        }
        if let main = NSScreen.main {
            return (main, .bottomLeft)
        }
        return nil
    }

    private func updateBest(
        best: inout (screen: NSScreen, mode: CoordinateMode, overlap: CGFloat)?,
        candidate: (screen: NSScreen, mode: CoordinateMode, overlap: CGFloat)
    ) {
        if let currentBest = best {
            if candidate.overlap > currentBest.overlap {
                best = candidate
                return
            }

            let isTie = abs(candidate.overlap - currentBest.overlap) < 0.5
            if isTie {
                switch (currentBest.mode, candidate.mode) {
                case (.bottomLeft, .topLeft):
                    best = candidate
                    return
                default:
                    return
                }
            }
            return
        }
        best = candidate
    }

    private func toAXY(bottomLeftY: CGFloat, windowHeight: CGFloat, mode: CoordinateMode) -> CGFloat {
        switch mode {
        case .bottomLeft:
            return bottomLeftY
        case .topLeft(let screenTop):
            return (screenTop - bottomLeftY - windowHeight).rounded()
        }
    }

    private func effectiveVisibleFrame(for screen: NSScreen) -> CGRect {
        let frame = screen.frame
        let visible = screen.visibleFrame

        let leftInset = visible.minX - frame.minX
        let rightInset = frame.maxX - visible.maxX
        let bottomInset = visible.minY - frame.minY
        let topInset = frame.maxY - visible.maxY

        return CGRect(
            x: frame.minX + leftInset,
            y: frame.minY + bottomInset,
            width: frame.width - leftInset - rightInset,
            height: frame.height - topInset - bottomInset
        )
    }
}

private extension CGRect {
    var area: CGFloat {
        if isNull || isEmpty {
            return 0
        }
        return width * height
    }
}
