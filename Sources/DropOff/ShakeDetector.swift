import AppKit

@MainActor
final class ShakeDetector {
    private let shouldOpenShelfAt: (NSPoint) -> Bool
    private let onShake: (ShakeActivation) -> Void
    private var recognizer = ShakeGestureRecognizer()
    private var dragActivation = DragActivationState()
    private var didOpenShelfForCurrentDrag = false
    private var currentDragIdentifier: ShakeDragIdentifier?
    private var localMonitor: Any?
    private var globalMonitor: Any?

    init(
        shouldOpenShelfAt: @escaping (NSPoint) -> Bool,
        onShake: @escaping (ShakeActivation) -> Void
    ) {
        self.shouldOpenShelfAt = shouldOpenShelfAt
        self.onShake = onShake
    }

    func start() {
        guard localMonitor == nil, globalMonitor == nil else { return }

        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
        }
    }

    func stop() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        localMonitor = nil
        globalMonitor = nil
        resetDrag()
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            beginDrag(with: event)
        case .leftMouseUp:
            resetDrag()
        case .leftMouseDragged:
            processDrag(event)
        default:
            break
        }
    }

    private func beginDrag(with event: NSEvent) {
        recognizer.reset()
        didOpenShelfForCurrentDrag = false
        currentDragIdentifier = ShakeDragIdentifier(
            eventNumber: event.eventNumber,
            mouseDownTimestamp: event.timestamp
        )
        let beganInsideDropOff = event.window?.windowController is ShelfWindowController
            || event.window?.contentView is ShelfContentView
        dragActivation.begin(
            pasteboardChangeCount: NSPasteboard(name: .drag).changeCount,
            beganInsideDropOff: beganInsideDropOff
        )
    }

    private func processDrag(_ event: NSEvent) {
        let pasteboard = NSPasteboard(name: .drag)
        let containsFiles = FileDragPasteboard.containsFiles(pasteboard)
        guard !didOpenShelfForCurrentDrag,
              dragActivation.shouldProcessDrag(
                currentPasteboardChangeCount: pasteboard.changeCount,
                pasteboardContainsFiles: containsFiles
              ) else {
            return
        }

        let point = NSEvent.mouseLocation
        guard recognizer.process(point: point, timestamp: event.timestamp) else { return }
        guard shouldOpenShelfAt(point), let currentDragIdentifier else { return }

        didOpenShelfForCurrentDrag = true
        onShake(
            ShakeActivation(
                identifier: currentDragIdentifier,
                point: point,
                timestamp: event.timestamp
            )
        )
    }

    private func resetDrag() {
        recognizer.reset()
        dragActivation.reset()
        didOpenShelfForCurrentDrag = false
        currentDragIdentifier = nil
    }

}

struct ShakeDragIdentifier: Hashable {
    let eventNumber: Int
    let mouseDownTimestamp: TimeInterval
}

struct ShakeActivation {
    let identifier: ShakeDragIdentifier
    let point: NSPoint
    let timestamp: TimeInterval
}
