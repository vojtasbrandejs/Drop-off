import AppKit
import Testing
@testable import DropOff

private let visibleFrame = NSRect(x: 0, y: 25, width: 1440, height: 850)
private let shelfSize = NSSize(width: 320, height: 280)

@Test func placementStaysInsideTopRightCorner() {
    let frame = ShelfPlacement.frame(
        near: NSPoint(x: 1438, y: 873),
        size: shelfSize,
        visibleFrame: visibleFrame
    )
    #expect(frame.maxX <= visibleFrame.maxX - 8)
    #expect(frame.maxY <= visibleFrame.maxY - 8)
}

@Test func placementStaysAboveDockAndInsideBottomLeftCorner() {
    let frame = ShelfPlacement.frame(
        near: NSPoint(x: 1, y: 26),
        size: shelfSize,
        visibleFrame: visibleFrame
    )
    #expect(frame.minX >= visibleFrame.minX + 8)
    #expect(frame.minY >= visibleFrame.minY + 8)
}

@Test func placementUsesSuppliedMonitorCoordinates() {
    let secondDisplay = NSRect(x: -1920, y: -120, width: 1920, height: 1080)
    let frame = ShelfPlacement.frame(
        near: NSPoint(x: -1800, y: 800),
        size: shelfSize,
        visibleFrame: secondDisplay
    )
    #expect(secondDisplay.insetBy(dx: 8, dy: 8).contains(frame))
}
