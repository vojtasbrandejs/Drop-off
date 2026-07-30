import AppKit

@MainActor
final class ShelfContentView: NSVisualEffectView {
    private let model: ShelfModel
    private let onClose: () -> Void
    private let onToggleCollapsed: () -> Void
    private let onToggleItems: () -> Void

    private let closeButton = ShelfIconButton()
    private let collapseButton = ShelfIconButton()
    private let titleLabel = NSTextField(labelWithString: "DROP SHELF")
    private let countLabel = NSTextField(labelWithString: "Empty")
    private let hintLabel = NSTextField(labelWithString: "Drop files, folders & links here")
    private let itemsButton = NSButton(title: "", target: nil, action: nil)
    private let clearButton = NSButton(title: "Clear", target: nil, action: nil)
    private let removeUnavailableButton = NSButton(
        title: "Remove unavailable",
        target: nil,
        action: nil
    )
    private let previewView: ShelfPreviewView
    private let gridView: ShelfGridView
    private let gridScrollView = NSScrollView()
    private var isCollapsed = false
    private var isShowingItems = false
    private var isDropTargetActive = false
    private let promiseOperationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "DropOff.FilePromises"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private var promiseReceiverRegistry = PromiseReceiverRegistry()

    init(
        frame frameRect: NSRect,
        model: ShelfModel,
        onClose: @escaping () -> Void,
        onToggleCollapsed: @escaping () -> Void,
        onToggleItems: @escaping () -> Void
    ) {
        self.model = model
        self.onClose = onClose
        self.onToggleCollapsed = onToggleCollapsed
        self.onToggleItems = onToggleItems
        previewView = ShelfPreviewView(model: model)
        gridView = ShelfGridView(model: model)
        super.init(frame: frameRect)

        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 18
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 0
        layer?.borderColor = NSColor.clear.cgColor

        configureControls()
        var acceptedDragTypes = NSFilePromiseReceiver.readableDraggedTypes.map {
            NSPasteboard.PasteboardType($0)
        }
        acceptedDragTypes.append(.fileURL)
        acceptedDragTypes.append(NSPasteboard.PasteboardType("NSFilenamesPboardType"))
        acceptedDragTypes.append(contentsOf: ShelfDropPasteboard.readableTypes)
        registerForDraggedTypes(acceptedDragTypes)
        previewView.onActivate = { [weak self] in self?.onToggleItems() }
        model.onChange = { [weak self] in self?.updateFromModel() }
        updateFromModel()
        updateVisibility()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let top = bounds.maxY
        let headerCenterY = top - 20
        let iconCenterY = headerCenterY + 1.5
        let iconSize: CGFloat = 28
        let textHeight: CGFloat = 16
        closeButton.frame = NSRect(
            x: 7,
            y: iconCenterY - iconSize / 2,
            width: iconSize,
            height: iconSize
        )
        collapseButton.frame = NSRect(
            x: bounds.maxX - 35,
            y: iconCenterY - iconSize / 2,
            width: iconSize,
            height: iconSize
        )

        if isCollapsed {
            titleLabel.frame = NSRect(
                x: 39,
                y: headerCenterY - textHeight / 2,
                width: bounds.width - 78,
                height: textHeight
            )
            return
        }

        if isShowingItems {
            titleLabel.frame = NSRect(
                x: 39,
                y: headerCenterY - textHeight / 2,
                width: 160,
                height: textHeight
            )
            countLabel.frame = NSRect(
                x: 200,
                y: headerCenterY - textHeight / 2,
                width: bounds.width - 242,
                height: textHeight
            )

            let scrollFrame = NSRect(x: 12, y: 46, width: bounds.width - 24, height: bounds.height - 88)
            gridScrollView.frame = scrollFrame
            let documentWidth = scrollFrame.width
            let documentHeight = max(scrollFrame.height, gridView.requiredHeight(for: documentWidth))
            gridView.frame = NSRect(x: 0, y: 0, width: documentWidth, height: documentHeight)
            itemsButton.frame = NSRect(x: bounds.midX - 52, y: 10, width: 104, height: 27)
            clearButton.frame = NSRect(x: bounds.maxX - 58, y: 11, width: 48, height: 26)
            removeUnavailableButton.frame = NSRect(x: 10, y: 11, width: 128, height: 26)
        } else {
            titleLabel.frame = NSRect(
                x: 39,
                y: headerCenterY - textHeight / 2,
                width: 95,
                height: textHeight
            )
            countLabel.frame = NSRect(
                x: 134,
                y: headerCenterY - textHeight / 2,
                width: bounds.width - 176,
                height: textHeight
            )
            let itemCount = model.items.count
            let showsPromiseStatus = model.promisedFilesImportState.isImporting
                || model.promisedFilesImportState.failureMessage != nil
            if showsPromiseStatus {
                previewView.frame = NSRect(x: 42, y: 48, width: bounds.width - 84, height: 128)
                hintLabel.frame = NSRect(x: 24, y: 19, width: bounds.width - 48, height: 28)
            } else if itemCount == 0 {
                previewView.frame = NSRect(x: 42, y: 48, width: bounds.width - 84, height: 128)
                hintLabel.frame = NSRect(x: 24, y: bounds.midY - 8, width: bounds.width - 48, height: 16)
            } else if itemCount == 1 {
                previewView.frame = NSRect(x: 42, y: 48, width: bounds.width - 84, height: 132)
                hintLabel.frame = NSRect(x: 24, y: 19, width: bounds.width - 48, height: 16)
            } else {
                previewView.frame = NSRect(x: 34, y: 43, width: bounds.width - 68, height: 139)
                hintLabel.frame = .zero
            }
            itemsButton.frame = NSRect(x: bounds.midX - 52, y: 10, width: 104, height: 27)
        }
    }

    func setCollapsed(_ collapsed: Bool) {
        isCollapsed = collapsed
        collapseButton.image = NSImage(
            systemSymbolName: collapsed ? "chevron.down" : "chevron.up",
            accessibilityDescription: collapsed ? "Expand shelf" : "Collapse shelf"
        )
        collapseButton.toolTip = collapsed ? "Expand shelf" : "Collapse shelf"
        updateVisibility()
    }

    func setShowingItems(_ showingItems: Bool) {
        isShowingItems = showingItems
        titleLabel.stringValue = showingItems ? "SHELF ITEMS" : "DROP SHELF"
        updateItemsButton()
        updateVisibility()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard canAcceptItems(from: sender.draggingPasteboard) else { return [] }
        setDropHighlight(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        canAcceptItems(from: sender.draggingPasteboard) ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        setDropHighlight(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        canAcceptItems(from: sender.draggingPasteboard)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        setDropHighlight(false)
        let pasteboard = sender.draggingPasteboard

        // Messages and other item-provider sources often advertise both the original
        // media bytes and a compatibility file promise. Preserve the first concrete
        // media representation instead of asking the promise for a JPEG/HEIC conversion.
        let media = ShelfDropPasteboard.mediaRepresentations(
            from: pasteboard,
            includeMovies: false
        )
        if !media.isEmpty {
            do {
                try model.addDroppedMedia(media)
                return true
            } catch {
                return false
            }
        }

        let urls = fileURLs(from: pasteboard)
        if !urls.isEmpty {
            do {
                let links = ShelfDropPasteboard.webURLs(from: pasteboard)
                try model.addDropped(urls: urls + links)
                return true
            } catch {
                return false
            }
        }

        let receivers = promisedFileReceivers(from: pasteboard)
        if !receivers.isEmpty {
            return receivePromisedFiles(receivers)
        }

        // A raw movie representation can be large, so only load it when the source
        // provides neither a real file URL nor an asynchronous file promise.
        let movies = ShelfDropPasteboard.mediaRepresentations(from: pasteboard)
        if !movies.isEmpty {
            do {
                try model.addDroppedMedia(movies)
                return true
            } catch {
                return false
            }
        }

        let links = ShelfDropPasteboard.webURLs(from: pasteboard)
        guard !links.isEmpty else { return false }
        do {
            try model.addDropped(urls: links)
            return true
        } catch {
            return false
        }
    }

    private func configureControls() {
        configureIconButton(
            closeButton,
            symbol: "xmark",
            accessibilityDescription: "Close shelf",
            action: #selector(closeShelf)
        )
        configureIconButton(
            collapseButton,
            symbol: "chevron.up",
            accessibilityDescription: "Collapse shelf",
            action: #selector(toggleCollapsed)
        )
        titleLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail

        countLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        countLabel.textColor = .secondaryLabelColor
        countLabel.alignment = .right
        countLabel.lineBreakMode = .byTruncatingHead

        hintLabel.font = .systemFont(ofSize: 10, weight: .medium)
        hintLabel.textColor = .tertiaryLabelColor
        hintLabel.alignment = .center
        hintLabel.maximumNumberOfLines = 2

        itemsButton.target = self
        itemsButton.action = #selector(toggleItems)
        itemsButton.bezelStyle = .rounded
        itemsButton.controlSize = .small
        itemsButton.font = .systemFont(ofSize: 11, weight: .medium)
        itemsButton.image = NSImage(
            systemSymbolName: "chevron.right",
            accessibilityDescription: "Show all items"
        )
        itemsButton.imagePosition = .imageTrailing
        itemsButton.toolTip = "Show all items"

        clearButton.target = self
        clearButton.action = #selector(clearShelf)
        clearButton.bezelStyle = .recessed
        clearButton.controlSize = .small

        removeUnavailableButton.target = self
        removeUnavailableButton.action = #selector(removeUnavailable)
        removeUnavailableButton.bezelStyle = .recessed
        removeUnavailableButton.controlSize = .small

        gridScrollView.drawsBackground = false
        gridScrollView.hasVerticalScroller = true
        gridScrollView.autohidesScrollers = true
        gridScrollView.scrollerStyle = .overlay
        gridScrollView.documentView = gridView

        [
            closeButton,
            collapseButton,
            titleLabel,
            countLabel,
            previewView,
            hintLabel,
            itemsButton,
            gridScrollView,
            clearButton,
            removeUnavailableButton,
        ].forEach(addSubview)
    }

    private func configureIconButton(
        _ button: NSButton,
        symbol: String,
        accessibilityDescription: String,
        action: Selector
    ) {
        button.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: accessibilityDescription
        )
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        button.target = self
        button.action = action
        button.toolTip = accessibilityDescription
    }

    private func updateVisibility() {
        let unavailableCount = model.items.filter { !$0.isAvailable }.count
        let compact = !isCollapsed && !isShowingItems
        let showsPromiseStatus = model.promisedFilesImportState.isImporting
            || model.promisedFilesImportState.failureMessage != nil
        titleLabel.alignment = isCollapsed ? .center : .left
        countLabel.isHidden = isCollapsed
        previewView.isHidden = !compact || isDropTargetActive
        hintLabel.isHidden = !compact || (model.items.count > 1 && !showsPromiseStatus)
        itemsButton.isHidden = isCollapsed
            || (compact && showsPromiseStatus)
            || (!isShowingItems && (!compact || model.items.count < 2))
        gridScrollView.isHidden = isCollapsed || !isShowingItems
        clearButton.isHidden = isCollapsed || !isShowingItems
        removeUnavailableButton.isHidden = isCollapsed || !isShowingItems || unavailableCount == 0
        needsLayout = true
    }

    private func updateFromModel() {
        previewView.reload()
        gridView.reload()
        let unavailableCount = model.items.filter { !$0.isAvailable }.count
        switch model.items.count {
        case 0:
            countLabel.stringValue = "Empty"
        case 1:
            countLabel.stringValue = unavailableCount == 1 ? "Unavailable" : "1 item"
        default:
            countLabel.stringValue = "\(model.items.count) items"
        }
        countLabel.textColor = .secondaryLabelColor
        countLabel.toolTip = nil
        if let failureMessage = model.promisedFilesImportState.failureMessage {
            countLabel.stringValue = "Import failed"
            countLabel.textColor = .systemRed
            countLabel.toolTip = failureMessage
        } else if model.promisedFilesImportState.isImporting {
            countLabel.stringValue = "Importing…"
        }
        updateItemsButton()
        if let failureMessage = model.promisedFilesImportState.failureMessage {
            hintLabel.stringValue = "Import failed — drop again to retry"
            hintLabel.toolTip = failureMessage
            hintLabel.textColor = .systemRed
        } else if model.promisedFilesImportState.isImporting {
            let count = model.promisedFilesImportState.pendingFileCount
            hintLabel.stringValue = count == 1 ? "Importing promised file…" : "Importing \(count) promised files…"
            hintLabel.toolTip = nil
            hintLabel.textColor = .secondaryLabelColor
        } else {
            hintLabel.textColor = .tertiaryLabelColor
            switch model.items.count {
            case 0:
                hintLabel.stringValue = "Drop files, folders & links here"
                hintLabel.toolTip = nil
            case 1:
                let displayName = model.items[0].displayName
                hintLabel.stringValue = displayName
                hintLabel.toolTip = displayName
            default:
                hintLabel.stringValue = "Drag the stack to move all items"
                hintLabel.toolTip = nil
            }
        }
        clearButton.isEnabled = !model.items.isEmpty
        updateVisibility()
    }

    private func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
        ]
        let modernURLs = pasteboard
            .readObjects(forClasses: [NSURL.self], options: options)?
            .compactMap { $0 as? URL }
            .filter { $0.isFileURL && FileManager.default.fileExists(atPath: $0.path) }
            ?? []
        if !modernURLs.isEmpty {
            return modernURLs
        }

        let legacyType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        let paths = pasteboard.propertyList(forType: legacyType) as? [String] ?? []
        return paths
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func canAcceptItems(from pasteboard: NSPasteboard) -> Bool {
        if ShelfDropPasteboard.containsMediaRepresentation(pasteboard)
            || !ShelfDropPasteboard.webURLs(from: pasteboard).isEmpty {
            return true
        }
        if pasteboard.canReadObject(
            forClasses: [NSFilePromiseReceiver.self],
            options: nil
        ) {
            return true
        }
        return !fileURLs(from: pasteboard).isEmpty
    }

    private func promisedFileReceivers(from pasteboard: NSPasteboard) -> [NSFilePromiseReceiver] {
        pasteboard.readObjects(
            forClasses: [NSFilePromiseReceiver.self],
            options: nil
        ) as? [NSFilePromiseReceiver] ?? []
    }

    private func receivePromisedFiles(_ receivers: [NSFilePromiseReceiver]) -> Bool {
        let promisedImport: ShelfPromisedFilesImport
        do {
            promisedImport = try model.beginPromisedFilesImport()
        } catch {
            model.reportPromisedFilesImportFailure(error)
            return false
        }

        promiseOperationQueue.isSuspended = true
        defer { promiseOperationQueue.isSuspended = false }
        var pendingRegistrations: [(token: PromiseReceiverToken, receiver: NSFilePromiseReceiver)] = []
        for receiver in receivers {
            let token = promiseReceiverRegistry.reserveToken()
            pendingRegistrations.append((token, receiver))
            receiver.receivePromisedFiles(
                atDestination: promisedImport.destination,
                options: [:],
                operationQueue: promiseOperationQueue
            ) { [weak self] url, error in
                Task { @MainActor [weak self] in
                    guard let self,
                          self.promiseReceiverRegistry.consumeCallback(for: token) != nil else {
                        return
                    }
                    self.model.completePromisedFile(
                        at: url,
                        error: error,
                        generation: promisedImport.generation
                    )
                }
            }
        }
        var totalCallbackCount = 0
        for registration in pendingRegistrations {
            let callbackCount = max(registration.receiver.fileNames.count, 1)
            totalCallbackCount += callbackCount
            promiseReceiverRegistry.activate(
                token: registration.token,
                receiver: registration.receiver,
                callbackCount: callbackCount
            )
        }
        model.setPromisedFilesImportExpectedCount(
            totalCallbackCount,
            generation: promisedImport.generation
        )
        return true
    }

    var promiseFeedbackForTesting: (text: String, toolTip: String?, color: NSColor) {
        (hintLabel.stringValue, hintLabel.toolTip, hintLabel.textColor ?? .clear)
    }

    private func resetPromiseReceiverState() {
        promiseReceiverRegistry.cancelAll()
    }

    private func cancelPromiseImports() {
        promiseOperationQueue.cancelAllOperations()
        resetPromiseReceiverState()
    }

    private func updateItemsButton() {
        itemsButton.title = model.items.count == 1 ? "1 item" : "\(model.items.count) items"
        itemsButton.image = NSImage(
            systemSymbolName: isShowingItems ? "chevron.left" : "chevron.right",
            accessibilityDescription: isShowingItems ? "Back to stacked view" : "Show all items"
        )
        itemsButton.imagePosition = isShowingItems ? .imageLeading : .imageTrailing
        itemsButton.toolTip = isShowingItems ? "Back to stacked view" : "Show all items"
    }

    private func setDropHighlight(_ highlighted: Bool) {
        isDropTargetActive = highlighted
        updateVisibility()
        layer?.borderWidth = highlighted ? 3 : 0
        layer?.borderColor = highlighted
            ? NSColor.controlAccentColor.withAlphaComponent(0.9).cgColor
            : NSColor.clear.cgColor
    }

    @objc private func closeShelf() {
        cancelPromiseImports()
        onClose()
    }

    @objc private func toggleCollapsed() {
        onToggleCollapsed()
    }

    @objc private func toggleItems() {
        onToggleItems()
    }

    @objc private func clearShelf() {
        cancelPromiseImports()
        model.clear()
    }

    @objc private func removeUnavailable() {
        model.removeUnavailable()
    }
}

struct PromiseReceiverToken: Hashable {
    fileprivate let value: UInt64
}

struct PromiseReceiverRegistry {
    private struct Entry {
        let receiver: AnyObject
        var remainingCallbackCount: Int
    }

    private var nextTokenValue: UInt64 = 0
    private var entries: [PromiseReceiverToken: Entry] = [:]

    var pendingCallbackCount: Int {
        entries.values.reduce(0) { $0 + $1.remainingCallbackCount }
    }

    var activeReceiverCount: Int { entries.count }

    mutating func reserveToken() -> PromiseReceiverToken {
        nextTokenValue &+= 1
        return PromiseReceiverToken(value: nextTokenValue)
    }

    mutating func activate(token: PromiseReceiverToken, receiver: AnyObject, callbackCount: Int) {
        entries[token] = Entry(
            receiver: receiver,
            remainingCallbackCount: max(callbackCount, 1)
        )
    }

    /// Unknown and cancelled tokens are strict no-ops. For a known token, returns
    /// whether its final expected callback was consumed.
    mutating func consumeCallback(for token: PromiseReceiverToken) -> Bool? {
        guard var entry = entries[token] else { return nil }
        entry.remainingCallbackCount -= 1
        if entry.remainingCallbackCount > 0 {
            entries[token] = entry
            return false
        }
        entries[token] = nil
        return true
    }

    mutating func cancelAll() {
        entries.removeAll()
    }
}

private final class ShelfIconButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

}
