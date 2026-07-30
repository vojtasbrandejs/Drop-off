import AppKit
import Testing
@testable import DropOff

@Test
func duplicateShakeCallbacksAreCoalescedButLaterDragsAreAccepted() {
    var gate = ShakeActivationGate()
    let first = activation(eventNumber: 10, mouseDown: 1, triggered: 1.20)
    let sameDragAgain = activation(eventNumber: 10, mouseDown: 1, triggered: 2)
    let duplicateMonitor = activation(eventNumber: 11, mouseDown: 1.01, triggered: 1.21)
    let laterDrag = activation(eventNumber: 12, mouseDown: 2, triggered: 2.30)

    let acceptedFirst = gate.claim(first)
    let acceptedSameDragAgain = gate.claim(sameDragAgain)
    let acceptedDuplicateMonitor = gate.claim(duplicateMonitor)
    let acceptedLaterDrag = gate.claim(laterDrag)

    #expect(acceptedFirst)
    #expect(!acceptedSameDragAgain)
    #expect(!acceptedDuplicateMonitor)
    #expect(acceptedLaterDrag)
}

@Test @MainActor
func shelfManagerCreatesOnlyOneWindowForDuplicateShakeCallbacks() {
    let manager = ShelfManager()
    defer { manager.closeAllShelves() }
    let first = activation(eventNumber: 20, mouseDown: 3, triggered: 3.20)
    let duplicate = activation(eventNumber: 21, mouseDown: 3.01, triggered: 3.21)
    let laterDrag = activation(eventNumber: 22, mouseDown: 4, triggered: 4.20)

    #expect(manager.createShelf(from: first) != nil)
    #expect(manager.createShelf(from: duplicate) == nil)
    #expect(manager.shelfCountForTesting == 1)
    #expect(manager.createShelf(from: laterDrag) != nil)
    #expect(manager.shelfCountForTesting == 2)
}

private func activation(
    eventNumber: Int,
    mouseDown: TimeInterval,
    triggered: TimeInterval
) -> ShakeActivation {
    ShakeActivation(
        identifier: ShakeDragIdentifier(
            eventNumber: eventNumber,
            mouseDownTimestamp: mouseDown
        ),
        point: NSPoint(x: 400, y: 400),
        timestamp: triggered
    )
}
