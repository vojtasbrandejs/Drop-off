import AppKit
import QuartzCore

final class ShelfPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ShelfWindowController: NSWindowController, NSWindowDelegate {
    static let expandedSize = NSSize(width: 256, height: 224)
    static let collapsedSize = NSSize(width: 176, height: 40)
    static let itemsSize = NSSize(width: 430, height: 330)

    let model: ShelfModel
    var onClose: (() -> Void)?

    private var mode: ShelfWindowMode = .expanded
    private var isClosing = false
    private var frameTransitions = ShelfFrameTransitionQueue()
    private weak var shelfContentView: ShelfContentView?

    init(frame: NSRect, model: ShelfModel) {
        self.model = model

        let panel = ShelfPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]

        super.init(window: panel)
        panel.delegate = self

        let contentView = ShelfContentView(
            frame: NSRect(origin: .zero, size: frame.size),
            model: model,
            onClose: { [weak self] in self?.closeAnimated() },
            onToggleCollapsed: { [weak self] in self?.toggleCollapsed() },
            onToggleItems: { [weak self] in self?.toggleItems() }
        )
        contentView.autoresizingMask = [.width, .height]
        panel.contentView = contentView
        shelfContentView = contentView
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showAnimated() {
        guard let window else { return }
        let finalFrame = window.frame
        window.alphaValue = 0
        window.setFrame(scaledFrame(finalFrame, factor: 0.86, verticalOffset: -4), display: false)
        window.orderFrontRegardless()

        Task { @MainActor [weak window] in
            await Task.yield()
            guard let window else { return }
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.24
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1
                window.animator().setFrame(finalFrame, display: true)
            }
        }
    }

    func closeAnimated() {
        guard let window, !isClosing else { return }
        isClosing = true
        frameTransitions.cancelAll()
        // Freeze any in-flight resize before the close animation takes ownership
        // of the frame. Its stale completion is generation-guarded below.
        window.setFrame(window.frame, display: true)
        let targetFrame = scaledFrame(window.frame, factor: 0.86, verticalOffset: -5)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
            window.animator().setFrame(targetFrame, display: true)
        } completionHandler: { [weak self, weak window] in
            Task { @MainActor in
                window?.close()
                self?.isClosing = false
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        model.clear()
        onClose?()
        onClose = nil
    }

    func toggleCollapsed() {
        guard window != nil else { return }
        mode = mode == .collapsed ? .expanded : .collapsed
        synchronizeContentAndRequestTransition()
    }

    func toggleItems() {
        guard model.items.count > 1 || mode == .items else { return }
        mode = mode == .items ? .expanded : .items
        synchronizeContentAndRequestTransition()
    }

    var logicalModeForTesting: ShelfWindowMode { mode }
    var requestedTransitionSizeForTesting: NSSize? { frameTransitions.latestTargetSize }

    private func synchronizeContentAndRequestTransition() {
        shelfContentView?.setCollapsed(mode == .collapsed)
        shelfContentView?.setShowingItems(mode == .items)
        let size: NSSize
        switch mode {
        case .collapsed:
            size = Self.collapsedSize
        case .expanded:
            size = Self.expandedSize
        case .items:
            size = Self.itemsSize
        }
        requestWindowTransition(to: size)
    }

    private func requestWindowTransition(to newSize: NSSize) {
        guard let transition = frameTransitions.request(size: newSize) else { return }
        runWindowTransition(transition)
    }

    private func runWindowTransition(_ transition: ShelfFrameTransition) {
        guard let window else { return }
        let targetFrame = constrainedFrame(keepingTopLeftOf: window.frame, size: transition.size)
        window.contentView?.needsLayout = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.26
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(targetFrame, display: true)
        } completionHandler: { [weak self, weak window] in
            Task { @MainActor [weak self, weak window] in
                guard let self, !self.isClosing else { return }
                guard let next = self.frameTransitions.complete(
                    generation: transition.generation
                ) else {
                    // A mismatched generation is a stale completion. If this was
                    // the active final transition, the queue is now empty.
                    if self.frameTransitions.latestTargetSize == nil {
                        window?.contentView?.needsLayout = true
                        window?.contentView?.layoutSubtreeIfNeeded()
                    }
                    return
                }
                self.runWindowTransition(next)
            }
        }
    }

    private func constrainedFrame(keepingTopLeftOf oldFrame: NSRect, size: NSSize) -> NSRect {
        var frame = NSRect(
            x: oldFrame.minX,
            y: oldFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(oldFrame) }) ?? NSScreen.main else {
            return frame
        }

        let visible = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        frame.origin.x = min(max(frame.minX, visible.minX), max(visible.minX, visible.maxX - size.width))
        frame.origin.y = min(max(frame.minY, visible.minY), max(visible.minY, visible.maxY - size.height))
        return frame
    }

    private func scaledFrame(_ frame: NSRect, factor: CGFloat, verticalOffset: CGFloat) -> NSRect {
        let size = NSSize(width: frame.width * factor, height: frame.height * factor)
        return NSRect(
            x: frame.midX - size.width / 2,
            y: frame.midY - size.height / 2 + verticalOffset,
            width: size.width,
            height: size.height
        )
    }
}

enum ShelfWindowMode: Equatable {
    case collapsed
    case expanded
    case items
}

struct ShelfFrameTransition: Equatable {
    let generation: UInt64
    let size: NSSize
}

struct ShelfFrameTransitionQueue {
    private var nextGeneration: UInt64 = 0
    private var active: ShelfFrameTransition?
    private var pending: ShelfFrameTransition?

    var latestTargetSize: NSSize? { pending?.size ?? active?.size }

    mutating func request(size: NSSize) -> ShelfFrameTransition? {
        nextGeneration &+= 1
        let transition = ShelfFrameTransition(generation: nextGeneration, size: size)
        guard active == nil else {
            pending = transition
            return nil
        }
        active = transition
        return transition
    }

    mutating func complete(generation: UInt64) -> ShelfFrameTransition? {
        guard active?.generation == generation else { return nil }
        active = nil
        guard let pending else { return nil }
        self.pending = nil
        active = pending
        return pending
    }

    mutating func cancelAll() {
        nextGeneration &+= 1
        active = nil
        pending = nil
    }
}
