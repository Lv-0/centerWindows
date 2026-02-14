import AppKit
import ApplicationServices

enum WindowCenteringError: LocalizedError {
    case accessibilityPermissionMissing
    case noFrontmostApplication
    case noWindow
    case fullscreenWindow
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
        case .fullscreenWindow:
            return "当前窗口处于全屏状态，已跳过居中。"
        case .unableToReadWindowFrame:
            return "无法读取窗口位置或尺寸。"
        case .unableToWriteWindowPosition:
            return "无法设置窗口位置（窗口可能不可移动）。"
        }
    }
}

enum WindowSelectionPolicy {
    case focusedOnly
    case focusedOrAnyNonFullscreen
}

final class WindowCenteringService {
    private enum RawSpace {
        case globalBottomLeft
        case globalTopLeft
        case localBottomLeft
        case localTopLeft
    }

    private struct WindowContext {
        let screen: NSScreen
        let space: RawSpace
        let overlap: CGFloat
        let currentGlobalRect: CGRect
    }

    private struct ContextCandidate {
        let screen: NSScreen
        let space: RawSpace
        let globalRect: CGRect
        let overlap: CGFloat
        let distance2: CGFloat
    }

    // When a window is mostly off-screen, overlap-based inference becomes ambiguous.
    // Cache the last reliable coordinate system per PID to keep behavior stable.
    private var cachedSpaceByPID: [pid_t: RawSpace] = [:]
    private var cachedDisplayByPID: [pid_t: CGDirectDisplayID] = [:]

    func centerFrontmostWindow(selectionPolicy: WindowSelectionPolicy = .focusedOrAnyNonFullscreen) throws {
        guard AccessibilityPermission.ensureTrusted(prompt: false) else {
            throw WindowCenteringError.accessibilityPermissionMissing
        }

        guard let app = NSWorkspace.shared.frontmostApplication else {
            throw WindowCenteringError.noFrontmostApplication
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        if isApplicationInFullscreen(appElement) {
            throw WindowCenteringError.fullscreenWindow
        }

        let focusedWindow = focusedWindowElement(for: appElement)
        let allWindows = windowElements(for: appElement)
        guard let windowElement = selectCenterableWindow(
            focused: focusedWindow,
            windows: allWindows,
            selectionPolicy: selectionPolicy
        ) else {
            if let focusedWindow, isFullscreenWindow(focusedWindow) {
                throw WindowCenteringError.fullscreenWindow
            }
            throw WindowCenteringError.noWindow
        }

        try centerWindowElement(windowElement, pid: app.processIdentifier)
    }

    func centerWindowElement(_ windowElement: AXUIElement, pid: pid_t? = nil, appElement: AXUIElement? = nil) throws {
        if let appElement, isApplicationInFullscreen(appElement) {
            throw WindowCenteringError.fullscreenWindow
        }
        if isFullscreenWindow(windowElement) {
            throw WindowCenteringError.fullscreenWindow
        }

        guard
            let currentPosition = pointAttribute(kAXPositionAttribute as CFString, on: windowElement),
            let windowSize = sizeAttribute(kAXSizeAttribute as CFString, on: windowElement)
        else {
            throw WindowCenteringError.unableToReadWindowFrame
        }

        let primaryTopY = primaryScreenTopY()
        let context: WindowContext?
        if let pid, let cgContext = detectWindowContextUsingCG(windowElement: windowElement, pid: pid, rawPosition: currentPosition, windowSize: windowSize, primaryTopY: primaryTopY) {
            context = cgContext
        } else {
            context = detectWindowContext(rawPosition: currentPosition, windowSize: windowSize, pid: pid, primaryTopY: primaryTopY)
        }

        guard let context else {
            throw WindowCenteringError.unableToReadWindowFrame
        }

        let visibleFrame = effectiveVisibleFrame(for: context.screen)
        let centeredBottomLeftOrigin = WindowGeometry.centeredOrigin(windowSize: windowSize, visibleFrame: visibleFrame)
        let targetAXOrigin = toAXOrigin(
            bottomLeftOrigin: centeredBottomLeftOrigin,
            windowSize: windowSize,
            screenFrame: context.screen.frame,
            space: context.space,
            primaryTopY: primaryTopY
        )

        if setPointAttribute(kAXPositionAttribute as CFString, value: targetAXOrigin, on: windowElement) {
            return
        }

        // If the window is far out-of-bounds, some apps reject "ideal" coordinates.
        // Try bringing it back into the visible region first, then re-apply centering.
        let backInVisible = WindowGeometry.constrainedOrigin(origin: context.currentGlobalRect.origin, windowSize: windowSize, bounds: visibleFrame)
        let backAXOrigin = toAXOrigin(
            bottomLeftOrigin: backInVisible,
            windowSize: windowSize,
            screenFrame: context.screen.frame,
            space: context.space,
            primaryTopY: primaryTopY
        )
        _ = setPointAttribute(kAXPositionAttribute as CFString, value: backAXOrigin, on: windowElement)

        if setPointAttribute(kAXPositionAttribute as CFString, value: targetAXOrigin, on: windowElement) {
            return
        }

        // Last resort: some windows accept AXFrame but not AXPosition.
        let frameRect = CGRect(origin: targetAXOrigin, size: windowSize)
        if setRectAttribute("AXFrame" as CFString, value: frameRect, on: windowElement) {
            return
        }

        throw WindowCenteringError.unableToWriteWindowPosition
    }

    private func focusedWindowElement(for appElement: AXUIElement) -> AXUIElement? {
        windowAttribute(kAXFocusedWindowAttribute as CFString, on: appElement)
    }

    private func mainWindowElement(for appElement: AXUIElement) -> AXUIElement? {
        windowAttribute(kAXMainWindowAttribute as CFString, on: appElement)
    }

    private func windowElements(for appElement: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)
        guard result == .success else {
            return []
        }
        return (value as? [AXUIElement]) ?? []
    }

    private func isApplicationInFullscreen(_ appElement: AXUIElement) -> Bool {
        // Prefer checking main/focused window to avoid scanning too many windows.
        if let main = mainWindowElement(for: appElement), isFullscreenWindow(main) {
            return true
        }
        if let focused = focusedWindowElement(for: appElement), isFullscreenWindow(focused) {
            return true
        }
        return false
    }

    private func selectCenterableWindow(
        focused: AXUIElement?,
        windows: [AXUIElement],
        selectionPolicy: WindowSelectionPolicy
    ) -> AXUIElement? {
        if let focused, !isFullscreenWindow(focused) {
            return focused
        }
        if selectionPolicy == .focusedOnly {
            return nil
        }
        return windows.first(where: { !isFullscreenWindow($0) })
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

    private func setRectAttribute(_ attribute: CFString, value: CGRect, on element: AXUIElement) -> Bool {
        var mutableRect = value
        guard let axValue = AXValueCreate(.cgRect, &mutableRect) else {
            return false
        }
        return AXUIElementSetAttributeValue(element, attribute, axValue) == .success
    }

    private func boolAttribute(_ attribute: CFString, on element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        guard let value, CFGetTypeID(value) == CFBooleanGetTypeID() else {
            return nil
        }
        return CFBooleanGetValue(unsafeDowncast(value, to: CFBoolean.self))
    }

    private func isFullscreenWindow(_ windowElement: AXUIElement) -> Bool {
        // Primary signal if available.
        if boolAttribute("AXFullScreen" as CFString, on: windowElement) == true {
            return true
        }

        // Fallback for apps/spaces that don't expose AXFullScreen reliably.
        // Try both coordinate interpretations against every screen and accept the best match.
        guard
            let rawPosition = pointAttribute(kAXPositionAttribute as CFString, on: windowElement),
            let windowSize = sizeAttribute(kAXSizeAttribute as CFString, on: windowElement)
        else {
            return false
        }

        let primaryTopY = primaryScreenTopY()
        for screen in NSScreen.screens {
            let screenFrame = screen.frame

            for space in [RawSpace.globalBottomLeft, .globalTopLeft, .localBottomLeft, .localTopLeft] {
                let rect = rawToGlobalRect(space: space, screenFrame: screenFrame, rawPosition: rawPosition, windowSize: windowSize, primaryTopY: primaryTopY)
                if isFullscreenLike(windowFrame: rect, screenFrame: screenFrame) {
                    return true
                }
            }
        }

        return false
    }

    private func isFullscreenLike(windowFrame: CGRect, screenFrame: CGRect) -> Bool {
        // Be tolerant of minor off-by-few-pixels differences (rounded corners, scaling, etc.).
        let tol: CGFloat = 6.0
        let posMatch = abs(windowFrame.minX - screenFrame.minX) <= tol &&
            abs(windowFrame.minY - screenFrame.minY) <= tol
        let sizeMatch = abs(windowFrame.width - screenFrame.width) <= tol &&
            abs(windowFrame.height - screenFrame.height) <= tol

        if posMatch && sizeMatch {
            return true
        }

        // Secondary heuristic: near-full coverage with aligned origin.
        let screenArea = max(1.0, screenFrame.width * screenFrame.height)
        let ratio = (windowFrame.width * windowFrame.height) / screenArea
        return posMatch && ratio >= 0.98
    }

    private func detectWindowContext(rawPosition: CGPoint, windowSize: CGSize, pid: pid_t?, primaryTopY: CGFloat) -> WindowContext? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }

        let cachedScreen: NSScreen? = {
            guard let pid, let id = cachedDisplayByPID[pid] else { return nil }
            return screens.first(where: { displayID(for: $0) == id })
        }()
        let cachedSpace: RawSpace? = {
            guard let pid else { return nil }
            return cachedSpaceByPID[pid]
        }()

        var best: ContextCandidate?

        for screen in screens {
            let screenFrame = screen.frame

            for space in [RawSpace.globalBottomLeft, .globalTopLeft, .localBottomLeft, .localTopLeft] {
                let globalRect = rawToGlobalRect(space: space, screenFrame: screenFrame, rawPosition: rawPosition, windowSize: windowSize, primaryTopY: primaryTopY)
                let overlap = globalRect.intersection(screenFrame).area
                let dist2 = distanceSquaredFromRectCenter(globalRect, to: screenFrame)
                consider(
                    candidate: ContextCandidate(screen: screen, space: space, globalRect: globalRect, overlap: overlap, distance2: dist2),
                    best: &best,
                    cachedScreen: cachedScreen,
                    cachedSpace: cachedSpace
                )
            }
        }

        if let best {
            // If we had any meaningful overlap, treat this as reliable and update cache.
            if let pid, best.overlap > 1 {
                if let id = displayID(for: best.screen) {
                    cachedDisplayByPID[pid] = id
                }
                cachedSpaceByPID[pid] = best.space
            } else if cachedScreen != nil, let cachedScreen, let cachedSpace {
                let screenFrame = cachedScreen.frame
                let globalRect = rawToGlobalRect(space: cachedSpace, screenFrame: screenFrame, rawPosition: rawPosition, windowSize: windowSize, primaryTopY: primaryTopY)
                return WindowContext(screen: cachedScreen, space: cachedSpace, overlap: 0, currentGlobalRect: globalRect)
            }
            return WindowContext(screen: best.screen, space: best.space, overlap: best.overlap, currentGlobalRect: best.globalRect)
        }
        return nil
    }

    private func detectWindowContextUsingCG(
        windowElement: AXUIElement,
        pid: pid_t,
        rawPosition: CGPoint,
        windowSize: CGSize,
        primaryTopY: CGFloat
    ) -> WindowContext? {
        guard
            ScreenCapturePermission.ensureAuthorized(prompt: false),
            let windowID = windowIDAttribute(on: windowElement),
            let cgRect = cgWindowBounds(windowID: windowID, pid: pid),
            let screenPick = pickScreenForCGRect(cgRect)
        else {
            return nil
        }

        let screen = screenPick.screen
        let screenFrame = screen.frame

        // Convert CG global rect (origin at top-left of primary, y grows down) to Cocoa global rect.
        let cocoaRect = cocoaRectFromCGWindowBounds(cgRect, screen: screen, primaryTopY: primaryTopY)

        var best: (space: RawSpace, globalRect: CGRect, error: CGFloat)?
        for space in [RawSpace.globalBottomLeft, .globalTopLeft, .localBottomLeft, .localTopLeft] {
            let globalRect = rawToGlobalRect(space: space, screenFrame: screenFrame, rawPosition: rawPosition, windowSize: windowSize, primaryTopY: primaryTopY)
            let err = rectMatchError(globalRect, cocoaRect)
            if let best, best.error <= err { continue }
            best = (space, globalRect, err)
        }
        guard let best else { return nil }

        if let id = displayID(for: screen) {
            cachedDisplayByPID[pid] = id
        }
        cachedSpaceByPID[pid] = best.space

        return WindowContext(screen: screen, space: best.space, overlap: screenPick.area, currentGlobalRect: best.globalRect)
    }

    private func rectMatchError(_ a: CGRect, _ b: CGRect) -> CGFloat {
        abs(a.minX - b.minX) +
            abs(a.minY - b.minY) +
            abs(a.width - b.width) +
            abs(a.height - b.height)
    }

    private func windowIDAttribute(on window: AXUIElement) -> CGWindowID? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, "AXWindowNumber" as CFString, &value) == .success else {
            return nil
        }
        guard let value, CFGetTypeID(value) == CFNumberGetTypeID() else {
            return nil
        }
        var n: Int32 = 0
        guard CFNumberGetValue(unsafeDowncast(value, to: CFNumber.self), .sInt32Type, &n) else {
            return nil
        }
        if n <= 0 { return nil }
        return CGWindowID(n)
    }

    private func cgWindowBounds(windowID: CGWindowID, pid: pid_t) -> CGRect? {
        let options: CGWindowListOption = [.optionIncludingWindow]
        guard let list = CGWindowListCopyWindowInfo(options, windowID) as? [[String: Any]] else {
            return nil
        }
        guard let info = list.first else { return nil }
        if let ownerPID = info[kCGWindowOwnerPID as String] as? Int, ownerPID != Int(pid) {
            return nil
        }
        guard let boundsDict = info[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: boundsDict)
    }

    private func pickScreenForCGRect(_ cgRect: CGRect) -> (screen: NSScreen, area: CGFloat)? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }

        var best: (screen: NSScreen, area: CGFloat)?
        var candidates: [NSScreen] = []

        for screen in screens {
            guard let id = displayID(for: screen) else { continue }
            let cgDisplay = CGDisplayBounds(id)
            let area = cgRect.intersection(cgDisplay).area
            if let best, abs(area - best.area) <= 0.5 {
                candidates.append(screen)
            } else if best == nil || area > best!.area + 0.5 {
                best = (screen, area)
                candidates = [screen]
            }
        }
        guard let best else { return nil }
        if candidates.count == 1 {
            return best
        }
        let center = CGPoint(x: cgRect.midX, y: cgRect.midY)
        let chosen = candidates.first(where: {
            guard let id = displayID(for: $0) else { return false }
            return CGDisplayBounds(id).contains(center)
        }) ?? best.screen
        return (chosen, best.area)
    }

    private func cocoaRectFromCGWindowBounds(_ cgRect: CGRect, screen: NSScreen, primaryTopY: CGFloat) -> CGRect {
        guard let id = displayID(for: screen) else {
            let y = primaryTopY - cgRect.minY - cgRect.height
            return CGRect(x: cgRect.minX, y: y, width: cgRect.width, height: cgRect.height)
        }
        let cgDisplay = CGDisplayBounds(id)
        let screenFrame = screen.frame
        let cocoaX = screenFrame.minX + (cgRect.minX - cgDisplay.minX)
        let cocoaY = primaryTopY - cgRect.minY - cgRect.height
        return CGRect(x: cocoaX, y: cocoaY, width: cgRect.width, height: cgRect.height)
    }

    private func consider(candidate: ContextCandidate, best: inout ContextCandidate?, cachedScreen: NSScreen?, cachedSpace: RawSpace?) {
        let overlapTol: CGFloat = 0.5
        let cacheBonus: CGFloat = 0.25

        // Score by overlap first; break ties by distance; preserve the historic tie-break of preferring top-left.
        func adjustedOverlap(_ c: ContextCandidate) -> CGFloat {
            if let cachedScreen, let cachedSpace,
               cachedScreen == c.screen, cachedSpace == c.space
            {
                return c.overlap + cacheBonus
            }
            return c.overlap
        }

        if let currentBest = best {
            let candOverlap = adjustedOverlap(candidate)
            let bestOverlap = adjustedOverlap(currentBest)

            if candOverlap > bestOverlap + overlapTol {
                best = candidate
                return
            }

            let diff = candOverlap > bestOverlap ? (candOverlap - bestOverlap) : (bestOverlap - candOverlap)
            if diff <= overlapTol {
                if candidate.distance2 + 0.5 < currentBest.distance2 {
                    best = candidate
                    return
                }
                // If still tied, prefer top-left (original behavior).
                let distDiff = candidate.distance2 > currentBest.distance2 ? (candidate.distance2 - currentBest.distance2) : (currentBest.distance2 - candidate.distance2)
                if distDiff <= 0.5 {
                    if isBottomLeft(space: currentBest.space), isTopLeft(space: candidate.space) {
                        best = candidate
                        return
                    }
                }
            }

            // If both overlaps are zero, pick the closest screen.
            if currentBest.overlap <= overlapTol, candidate.overlap <= overlapTol {
                if candidate.distance2 + 0.5 < currentBest.distance2 {
                    best = candidate
                    return
                }
            }
            return
        }

        best = candidate
    }

    private func toAXOrigin(bottomLeftOrigin: CGPoint, windowSize: CGSize, screenFrame: CGRect, space: RawSpace, primaryTopY: CGFloat) -> CGPoint {
        switch space {
        case .globalBottomLeft:
            return CGPoint(x: bottomLeftOrigin.x.rounded(), y: bottomLeftOrigin.y.rounded())
        case .globalTopLeft:
            let y = (primaryTopY - bottomLeftOrigin.y - windowSize.height).rounded()
            return CGPoint(x: bottomLeftOrigin.x.rounded(), y: y)
        case .localBottomLeft:
            let x = (bottomLeftOrigin.x - screenFrame.minX).rounded()
            let y = (bottomLeftOrigin.y - screenFrame.minY).rounded()
            return CGPoint(x: x, y: y)
        case .localTopLeft:
            let x = (bottomLeftOrigin.x - screenFrame.minX).rounded()
            let y = (screenFrame.maxY - bottomLeftOrigin.y - windowSize.height).rounded()
            return CGPoint(x: x, y: y)
        }
    }

    private func rawToGlobalRect(space: RawSpace, screenFrame: CGRect, rawPosition: CGPoint, windowSize: CGSize, primaryTopY: CGFloat) -> CGRect {
        switch space {
        case .globalBottomLeft:
            return CGRect(origin: rawPosition, size: windowSize)
        case .globalTopLeft:
            let convertedBottomY = primaryTopY - rawPosition.y - windowSize.height
            return CGRect(x: rawPosition.x, y: convertedBottomY, width: windowSize.width, height: windowSize.height)
        case .localBottomLeft:
            return CGRect(
                x: screenFrame.minX + rawPosition.x,
                y: screenFrame.minY + rawPosition.y,
                width: windowSize.width,
                height: windowSize.height
            )
        case .localTopLeft:
            let x = screenFrame.minX + rawPosition.x
            let y = screenFrame.maxY - rawPosition.y - windowSize.height
            return CGRect(x: x, y: y, width: windowSize.width, height: windowSize.height)
        }
    }

    private func isTopLeft(space: RawSpace) -> Bool {
        switch space {
        case .globalTopLeft, .localTopLeft:
            return true
        default:
            return false
        }
    }

    private func isBottomLeft(space: RawSpace) -> Bool {
        switch space {
        case .globalBottomLeft, .localBottomLeft:
            return true
        default:
            return false
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

    private func distanceSquaredFromRectCenter(_ rect: CGRect, to bounds: CGRect) -> CGFloat {
        let cx = rect.midX
        let cy = rect.midY
        let nx = clamp(cx, min: bounds.minX, max: bounds.maxX)
        let ny = clamp(cy, min: bounds.minY, max: bounds.maxY)
        let dx = cx - nx
        let dy = cy - ny
        return dx * dx + dy * dy
    }

    private func clamp(_ value: CGFloat, min lowerBound: CGFloat, max upperBound: CGFloat) -> CGFloat {
        Swift.max(lowerBound, Swift.min(value, upperBound))
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    private func primaryScreenTopY() -> CGFloat {
        // Primary display's top edge in Cocoa global coordinates (also equals its height when minY == 0).
        let screens = NSScreen.screens
        let primary = screens.first(where: { abs($0.frame.minX) < 0.5 && abs($0.frame.minY) < 0.5 })
        return (primary ?? NSScreen.main ?? screens.first)?.frame.maxY ?? 0
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
