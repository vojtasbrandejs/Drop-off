import AppKit

@MainActor
final class ShelfManager {
    private var shelves: [ShelfWindowController] = []
    private var shakeActivationGate = ShakeActivationGate()

    @discardableResult
    func createShelf(from activation: ShakeActivation) -> ShelfWindowController? {
        guard shakeActivationGate.claim(activation) else { return nil }
        return createShelf(near: activation.point)
    }

    @discardableResult
    func createShelf(near point: NSPoint) -> ShelfWindowController {
        let size = ShelfWindowController.expandedSize
        let screen = screen(containing: point)
        let frame = ShelfPlacement.frame(
            near: point,
            size: size,
            visibleFrame: screen.visibleFrame
        )
        let controller = ShelfWindowController(frame: frame, model: ShelfModel())
        controller.onClose = { [weak self, weak controller] in
            guard let self, let controller else { return }
            self.shelves.removeAll { $0 === controller }
        }
        shelves.append(controller)
        controller.showAnimated()
        return controller
    }

    func closeAllShelves() {
        let openShelves = shelves
        shelves.removeAll()
        for shelf in openShelves {
            shelf.onClose = nil
            shelf.closeAnimated()
        }
    }

    func containsScreenPoint(_ point: NSPoint) -> Bool {
        shelves.contains { shelf in
            guard let window = shelf.window, window.isVisible else { return false }
            return window.frame.contains(point)
        }
    }

    var shelfCountForTesting: Int { shelves.count }

    private func screen(containing point: NSPoint) -> NSScreen {
        NSScreen.screens.first(where: { $0.frame.contains(point) })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }
}

struct ShakeActivationGate {
    private struct Claim {
        let identifier: ShakeDragIdentifier
        let point: NSPoint
        let timestamp: TimeInterval
    }

    private var lastClaim: Claim?
    private let duplicateInterval: TimeInterval
    private let duplicateDistance: CGFloat

    init(
        duplicateInterval: TimeInterval = 0.25,
        duplicateDistance: CGFloat = 80
    ) {
        self.duplicateInterval = duplicateInterval
        self.duplicateDistance = duplicateDistance
    }

    mutating func claim(_ activation: ShakeActivation) -> Bool {
        if let lastClaim {
            if lastClaim.identifier == activation.identifier {
                return false
            }

            let elapsed = activation.timestamp - lastClaim.timestamp
            let distance = hypot(
                activation.point.x - lastClaim.point.x,
                activation.point.y - lastClaim.point.y
            )
            if elapsed >= 0,
               elapsed <= duplicateInterval,
               distance <= duplicateDistance {
                return false
            }
        }

        lastClaim = Claim(
            identifier: activation.identifier,
            point: activation.point,
            timestamp: activation.timestamp
        )
        return true
    }
}
