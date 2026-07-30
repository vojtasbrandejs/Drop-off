import AppKit

@MainActor
final class ShelfGridView: NSView {
    private let model: ShelfModel
    private var cells: [ShelfGridCellView] = []

    init(model: ShelfModel) {
        self.model = model
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    func reload() {
        cells.forEach { $0.removeFromSuperview() }
        cells = model.items.map { [weak self] item in
            ShelfGridCellView(item: item) {
                self?.model.refreshAvailability()
                self?.reload()
            }
        }
        cells.forEach(addSubview)
        needsLayout = true
    }

    func requiredHeight(for width: CGFloat) -> CGFloat {
        let rowCount = Int(ceil(Double(max(cells.count, 1)) / 3.0))
        return CGFloat(rowCount) * 126 + CGFloat(max(rowCount - 1, 0)) * 10 + 4
    }

    override func layout() {
        super.layout()
        let columns = 3
        let gap: CGFloat = 10
        let cellWidth = floor((bounds.width - gap * CGFloat(columns - 1)) / CGFloat(columns))
        let cellHeight: CGFloat = 126

        for (index, cell) in cells.enumerated() {
            let column = index % columns
            let row = index / columns
            cell.frame = NSRect(
                x: CGFloat(column) * (cellWidth + gap),
                y: 2 + CGFloat(row) * (cellHeight + gap),
                width: cellWidth,
                height: cellHeight
            )
        }
    }
}

@MainActor
final class ShelfGridCellView: NSView, NSDraggingSource {
    private let item: ShelfItem
    private let onDragEnded: () -> Void
    private let imageView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let metadataLabel = NSTextField(labelWithString: "")
    private var mouseDownPoint: NSPoint?
    private var startedDragging = false

    init(item: ShelfItem, onDragEnded: @escaping () -> Void = {}) {
        self.item = item
        self.onDragEnded = onDragEnded
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.055).cgColor
        layer?.cornerRadius = 12
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor

        imageView.image = item.thumbnail
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.alphaValue = item.isAvailable ? 1 : 0.35
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 8
        imageView.layer?.masksToBounds = true

        nameLabel.stringValue = item.displayName
        nameLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        nameLabel.textColor = item.isAvailable ? .labelColor : .secondaryLabelColor
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingMiddle

        metadataLabel.stringValue = metadataText(for: item)
        metadataLabel.font = .monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        metadataLabel.textColor = item.isAvailable ? .tertiaryLabelColor : .systemRed
        metadataLabel.alignment = .center
        metadataLabel.lineBreakMode = .byTruncatingMiddle

        [imageView, nameLabel, metadataLabel].forEach(addSubview)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    var representedItemName: String { item.displayName }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0.01, super.hitTest(point) != nil else {
            return nil
        }
        return self
    }

    override func layout() {
        super.layout()
        imageView.frame = NSRect(x: 12, y: 10, width: bounds.width - 24, height: 74)
        nameLabel.frame = NSRect(x: 7, y: 88, width: bounds.width - 14, height: 16)
        metadataLabel.frame = NSRect(x: 7, y: 106, width: bounds.width - 14, height: 14)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        startedDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !startedDragging, let mouseDownPoint else { return }
        let currentPoint = convert(event.locationInWindow, from: nil)
        guard hypot(currentPoint.x - mouseDownPoint.x, currentPoint.y - mouseDownPoint.y) >= 4,
              let draggingItem = makeDraggingItem() else {
            return
        }

        startedDragging = true
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownPoint = nil
        startedDragging = false
    }

    func makeDraggingItem() -> NSDraggingItem? {
        guard item.resolveCurrentURL() != nil else { return nil }
        let draggingItem = NSDraggingItem(pasteboardWriter: item.pasteboardWriter)
        let size = min(82, bounds.width - 20, bounds.height - 20)
        draggingItem.setDraggingFrame(
            NSRect(
                x: bounds.midX - size / 2,
                y: bounds.midY - size / 2,
                width: size,
                height: size
            ),
            contents: item.thumbnail
        )
        return draggingItem
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        item.kind == .webLink ? .copy : [.copy, .move]
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        mouseDownPoint = nil
        startedDragging = false
        onDragEnded()
    }

    private func metadataText(for item: ShelfItem) -> String {
        guard item.isAvailable else { return "Unavailable" }
        if item.kind == .webLink {
            return item.currentURL.absoluteString
        }
        let values = try? item.currentURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        if values?.isDirectory == true {
            return "Folder"
        }
        guard let size = values?.fileSize else { return "File" }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}
