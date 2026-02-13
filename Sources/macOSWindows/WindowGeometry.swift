import CoreGraphics

enum WindowGeometry {
    static func centeredOrigin(windowSize: CGSize, visibleFrame: CGRect) -> CGPoint {
        let centeredX = visibleFrame.origin.x + (visibleFrame.width - windowSize.width) / 2.0
        let centeredY = visibleFrame.origin.y + (visibleFrame.height - windowSize.height) / 2.0

        let minX = visibleFrame.minX
        let maxX = visibleFrame.maxX - windowSize.width
        let minY = visibleFrame.minY
        let maxY = visibleFrame.maxY - windowSize.height

        let clampedX = clamp(centeredX, min: minX, max: max(minX, maxX))
        let clampedY = clamp(centeredY, min: minY, max: max(minY, maxY))

        return CGPoint(x: clampedX.rounded(), y: clampedY.rounded())
    }

    private static func clamp(_ value: CGFloat, min lowerBound: CGFloat, max upperBound: CGFloat) -> CGFloat {
        Swift.max(lowerBound, Swift.min(value, upperBound))
    }
}
