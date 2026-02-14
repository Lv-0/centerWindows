import CoreGraphics

enum WindowGeometry {
    static func centeredOrigin(windowSize: CGSize, visibleFrame: CGRect) -> CGPoint {
        // Center relative to the usable region (visibleFrame). If the window is larger than the visible area on
        // an axis, we keep the centered origin (best-effort) instead of clamping to an edge.
        let centeredX = visibleFrame.midX - windowSize.width / 2.0
        let centeredY = visibleFrame.midY - windowSize.height / 2.0

        var x = centeredX
        var y = centeredY

        if windowSize.width <= visibleFrame.width {
            let minX = visibleFrame.minX
            let maxX = visibleFrame.maxX - windowSize.width
            x = clamp(centeredX, min: minX, max: max(minX, maxX))
        }

        if windowSize.height <= visibleFrame.height {
            let minY = visibleFrame.minY
            let maxY = visibleFrame.maxY - windowSize.height
            y = clamp(centeredY, min: minY, max: max(minY, maxY))
        }

        return CGPoint(x: x.rounded(), y: y.rounded())
    }

    static func constrainedOrigin(origin: CGPoint, windowSize: CGSize, bounds: CGRect) -> CGPoint {
        let minX = bounds.minX
        let maxX = bounds.maxX - windowSize.width
        let minY = bounds.minY
        let maxY = bounds.maxY - windowSize.height

        let lowerX = Swift.min(minX, maxX)
        let upperX = Swift.max(minX, maxX)
        let lowerY = Swift.min(minY, maxY)
        let upperY = Swift.max(minY, maxY)

        let constrainedX = clamp(origin.x, min: lowerX, max: upperX)
        let constrainedY = clamp(origin.y, min: lowerY, max: upperY)

        return CGPoint(x: constrainedX.rounded(), y: constrainedY.rounded())
    }

    private static func clamp(_ value: CGFloat, min lowerBound: CGFloat, max upperBound: CGFloat) -> CGFloat {
        Swift.max(lowerBound, Swift.min(value, upperBound))
    }
}
