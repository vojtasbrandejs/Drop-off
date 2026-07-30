import AppKit

enum ShelfPlacement {
    static func frame(
        near point: NSPoint,
        size: NSSize,
        visibleFrame: NSRect,
        margin: CGFloat = 8
    ) -> NSRect {
        var origin = NSPoint(
            x: point.x + 20,
            y: point.y - size.height / 2
        )

        let minimumX = visibleFrame.minX + margin
        let maximumX = max(minimumX, visibleFrame.maxX - size.width - margin)
        let minimumY = visibleFrame.minY + margin
        let maximumY = max(minimumY, visibleFrame.maxY - size.height - margin)
        origin.x = min(max(origin.x, minimumX), maximumX)
        origin.y = min(max(origin.y, minimumY), maximumY)
        return NSRect(origin: origin, size: size)
    }
}
