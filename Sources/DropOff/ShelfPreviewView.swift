import AppKit

@MainActor
final class ShelfPreviewView: NSView, NSDraggingSource {
    private let model: ShelfModel
    private var mouseDownPoint: NSPoint?
    private var startedDragging = false
    private var imageViews: [NSImageView] = []
    var onActivate: (() -> Void)?

    init(model: ShelfModel) {
        self.model = model
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0.01, super.hitTest(point) != nil else {
            return nil
        }
        return self
    }

    func reload() {
        imageViews.forEach { $0.removeFromSuperview() }
        imageViews = Array(model.items.prefix(3).reversed()).map { item in
            let imageView = NSImageView()
            imageView.image = item.thumbnail
            imageView.imageAlignment = .alignCenter
            imageView.imageScaling = .scaleProportionallyDown
            imageView.alphaValue = item.isAvailable ? 1 : 0.35
            imageView.wantsLayer = true
            imageView.layer?.backgroundColor = NSColor.clear.cgColor
            imageView.layer?.borderWidth = 0
            imageView.layer?.shadowColor = NSColor.black.cgColor
            imageView.layer?.shadowOpacity = 0.18
            imageView.layer?.shadowRadius = 5
            imageView.layer?.shadowOffset = CGSize(width: 0, height: -2)
            addSubview(imageView)
            return imageView
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let configurations = fanConfigurations(for: imageViews.count)
        for (imageView, configuration) in zip(imageViews, configurations) {
            let size = min(configuration.size, bounds.height - 4)
            imageView.frameRotation = 0
            imageView.frame = NSRect(
                x: bounds.midX + configuration.xOffset - size / 2,
                y: bounds.midY + configuration.yOffset - size / 2,
                width: size,
                height: size
            )
            imageView.frameRotation = configuration.rotation
        }
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        startedDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !startedDragging, let mouseDownPoint else { return }
        let currentPoint = convert(event.locationInWindow, from: nil)
        guard hypot(currentPoint.x - mouseDownPoint.x, currentPoint.y - mouseDownPoint.y) >= 4 else {
            return
        }

        let items = model.availableItems()
        guard !items.isEmpty else { return }
        startedDragging = true

        let draggingItems = items.enumerated().map { index, item -> NSDraggingItem in
            let draggingItem = NSDraggingItem(pasteboardWriter: item.pasteboardWriter)
            let offset = CGFloat(index) * 4
            let frame = NSRect(
                x: bounds.midX - 48 + offset,
                y: bounds.midY - 48 - offset,
                width: 96,
                height: 96
            )
            draggingItem.setDraggingFrame(frame, contents: item.thumbnail)
            return draggingItem
        }
        beginDraggingSession(with: draggingItems, event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        if !startedDragging, model.items.count > 1 {
            onActivate?()
        }
        mouseDownPoint = nil
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        model.availableItems().contains { $0.kind == .webLink } ? .copy : [.copy, .move]
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        mouseDownPoint = nil
        model.refreshAvailability()
    }

    private func fanConfigurations(for count: Int) -> [FanConfiguration] {
        switch count {
        case 1:
            return [FanConfiguration(xOffset: 0, yOffset: 0, size: 112, rotation: 0)]
        case 2:
            return [
                FanConfiguration(xOffset: -27, yOffset: 0, size: 92, rotation: -7),
                FanConfiguration(xOffset: 27, yOffset: 0, size: 92, rotation: 7),
            ]
        default:
            return [
                FanConfiguration(xOffset: -38, yOffset: 1, size: 78, rotation: -9),
                FanConfiguration(xOffset: 0, yOffset: -3, size: 84, rotation: 0),
                FanConfiguration(xOffset: 38, yOffset: 1, size: 78, rotation: 9),
            ]
        }
    }
}

private struct FanConfiguration {
    let xOffset: CGFloat
    let yOffset: CGFloat
    let size: CGFloat
    let rotation: CGFloat
}
