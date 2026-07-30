import AppKit
import Testing
import UniformTypeIdentifiers
@testable import DropOff

@Test @MainActor
func borderlessShelfPanelCanReceiveControlClicks() {
    let panel = ShelfPanel(
        contentRect: NSRect(x: 0, y: 0, width: 176, height: 40),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )

    #expect(panel.canBecomeKey)
    #expect(!panel.canBecomeMain)
}

@Test @MainActor
func hiddenPreviewDoesNotInterceptCollapsedShelfControls() {
    let preview = ShelfPreviewView(model: ShelfModel())
    preview.frame = NSRect(x: 0, y: 0, width: 176, height: 40)
    preview.isHidden = true

    #expect(preview.hitTest(NSPoint(x: 155, y: 20)) == nil)
    #expect(preview.hitTest(NSPoint(x: 21, y: 20)) == nil)
}

@Test @MainActor
func shelfRegistersFileDropsWhilePreviewCoversItsCenter() throws {
    let content = ShelfContentView(
        frame: NSRect(x: 0, y: 0, width: 256, height: 224),
        model: ShelfModel(),
        onClose: {},
        onToggleCollapsed: {},
        onToggleItems: {}
    )
    let preview = try #require(
        content.subviews.first { $0 is ShelfPreviewView } as? ShelfPreviewView
    )
    preview.frame = NSRect(x: 42, y: 48, width: 172, height: 132)

    #expect(preview.hitTest(NSPoint(x: 86, y: 66)) === preview)
    #expect(content.registeredDraggedTypes.contains(.fileURL))
    #expect(
        content.registeredDraggedTypes.contains(
            NSPasteboard.PasteboardType("NSFilenamesPboardType")
        )
    )
}

@Test @MainActor
func shelfRegistersAllFilePromisePasteboardTypes() {
    let content = ShelfContentView(
        frame: NSRect(x: 0, y: 0, width: 256, height: 224),
        model: ShelfModel(),
        onClose: {},
        onToggleCollapsed: {},
        onToggleItems: {}
    )

    for type in NSFilePromiseReceiver.readableDraggedTypes {
        #expect(content.registeredDraggedTypes.contains(NSPasteboard.PasteboardType(type)))
    }
}

@Test @MainActor
func promisedScreenshotDropIsAcceptedForAsynchronousMaterialization() {
    let model = ShelfModel()
    let content = ShelfContentView(
        frame: NSRect(x: 0, y: 0, width: 256, height: 224),
        model: model,
        onClose: {},
        onToggleCollapsed: {},
        onToggleItems: {}
    )
    let delegate = TestFilePromiseDelegate()
    let provider = NSFilePromiseProvider(fileType: "public.png", delegate: delegate)
    let pasteboard = NSPasteboard.withUniqueName()
    pasteboard.clearContents()
    #expect(pasteboard.writeObjects([provider]))
    let drag = TestDraggingInfo(pasteboard: pasteboard)

    #expect(content.draggingEntered(drag) == .copy)
    #expect(content.prepareForDragOperation(drag))
    #expect(content.performDragOperation(drag))
}

@Test @MainActor
func originalPNGRepresentationWinsOverCompatibilityFilePromise() throws {
    let pngData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3])
    let item = NSPasteboardItem()
    #expect(item.setData(pngData, forType: NSPasteboard.PasteboardType(UTType.png.identifier)))
    #expect(
        item.setString(
            "Message Artwork.svg",
            forType: NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-name")
        )
    )
    let delegate = TestFilePromiseDelegate()
    let compatibilityPromise = NSFilePromiseProvider(
        fileType: UTType.jpeg.identifier,
        delegate: delegate
    )
    let pasteboard = NSPasteboard.withUniqueName()
    pasteboard.clearContents()
    #expect(pasteboard.writeObjects([item, compatibilityPromise]))

    let model = ShelfModel(thumbnailProvider: PanelStubThumbnailProvider())
    let content = makeShelfContent(model: model)
    #expect(content.performDragOperation(TestDraggingInfo(pasteboard: pasteboard)))

    let storedURL = try #require(model.items.first?.currentURL)
    #expect(model.items.count == 1)
    #expect(storedURL.pathExtension == "png")
    #expect(try Data(contentsOf: storedURL) == pngData)
}

@Test @MainActor
func svgAndMoviePasteboardRepresentationsKeepTheirAdvertisedFormats() throws {
    let cases: [(UTType, Data, String)] = [
        (.svg, Data("<svg xmlns=\"http://www.w3.org/2000/svg\"/>".utf8), "svg"),
        (.mpeg4Movie, Data([0, 0, 0, 20, 0x66, 0x74, 0x79, 0x70]), "mp4"),
    ]

    for (type, expectedData, expectedExtension) in cases {
        let item = NSPasteboardItem()
        #expect(
            item.setData(
                expectedData,
                forType: NSPasteboard.PasteboardType(type.identifier)
            )
        )
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        #expect(pasteboard.writeObjects([item]))

        let representation = try #require(
            ShelfDropPasteboard.mediaRepresentations(from: pasteboard).first
        )
        #expect(representation.typeIdentifier == type.identifier)
        #expect(representation.fileName.hasSuffix(".\(expectedExtension)"))
        #expect(representation.data == expectedData)
    }
}

@Test @MainActor
func webLinkDropIsAcceptedStoredAndDraggedBackAsURL() throws {
    let link = try #require(URL(string: "https://Example.com/work/drop-off?from=messages"))
    let pasteboard = NSPasteboard.withUniqueName()
    pasteboard.clearContents()
    #expect(pasteboard.writeObjects([link as NSURL]))

    let model = ShelfModel(thumbnailProvider: PanelStubThumbnailProvider())
    let content = makeShelfContent(model: model)
    let drag = TestDraggingInfo(pasteboard: pasteboard)
    #expect(content.draggingEntered(drag) == .copy)
    #expect(content.performDragOperation(drag))

    let stored = try #require(model.items.first)
    #expect(stored.kind == ShelfItem.Kind.webLink)
    #expect(stored.currentURL.absoluteString == "https://example.com/work/drop-off?from=messages")

    let outbound = NSPasteboard.withUniqueName()
    outbound.clearContents()
    #expect(outbound.writeObjects([stored.pasteboardWriter]))
    #expect(outbound.string(forType: .URL) == stored.currentURL.absoluteString)
    #expect(outbound.string(forType: .string) == stored.currentURL.absoluteString)
}

@Test @MainActor
func mixedFileAndLinkDropKeepsBothItems() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("mixed.txt")
    try Data("file".utf8).write(to: file)
    let link = try #require(URL(string: "https://example.com/mixed"))

    let pasteboard = NSPasteboard.withUniqueName()
    pasteboard.clearContents()
    #expect(
        pasteboard.writeObjects([
            file as NSURL,
            WebLinkPasteboardWriter(url: link),
        ])
    )
    let model = ShelfModel(thumbnailProvider: PanelStubThumbnailProvider())
    let content = makeShelfContent(model: model)

    #expect(content.performDragOperation(TestDraggingInfo(pasteboard: pasteboard)))
    #expect(model.items.map(\.kind) == [.file, .webLink])
}

@Test @MainActor
func plainTextIsRejectedButPlainTextWebURLIsAccepted() {
    let plainText = NSPasteboard.withUniqueName()
    plainText.clearContents()
    #expect(plainText.setString("not a link", forType: .string))
    #expect(!FileDragPasteboard.containsFiles(plainText))

    let linkText = NSPasteboard.withUniqueName()
    linkText.clearContents()
    #expect(linkText.setString("https://example.com/from-text", forType: .string))
    #expect(FileDragPasteboard.containsFiles(linkText))
}

@Test @MainActor
func promisedFileImportShowsPendingAndRetryableFailureFeedback() throws {
    let model = ShelfModel()
    let content = ShelfContentView(
        frame: NSRect(x: 0, y: 0, width: 256, height: 224),
        model: model,
        onClose: {},
        onToggleCollapsed: {},
        onToggleItems: {}
    )
    let promisedImport = try model.beginPromisedFilesImport(expectedFileCount: 1)

    #expect(content.promiseFeedbackForTesting.text == "Importing promised file…")
    model.completePromisedFile(
        at: promisedImport.destination.appendingPathComponent("failed.png"),
        error: TestPromiseFailure(message: "The source app cancelled the export."),
        generation: promisedImport.generation
    )

    #expect(content.promiseFeedbackForTesting.text == "Import failed — drop again to retry")
    #expect(content.promiseFeedbackForTesting.toolTip == "The source app cancelled the export.")
    #expect(content.promiseFeedbackForTesting.color == .systemRed)
}

@Test func promiseReceiverIsRetainedThroughItsFinalMultiFileCallback() {
    var registry = PromiseReceiverRegistry()
    var receiver: NSObject? = NSObject()
    weak let weakReceiver = receiver
    let token = registry.reserveToken()
    registry.activate(token: token, receiver: receiver!, callbackCount: 3)
    receiver = nil

    #expect(weakReceiver != nil)
    #expect(registry.consumeCallback(for: token) == false)
    #expect(registry.pendingCallbackCount == 2)
    #expect(weakReceiver != nil)
    #expect(registry.consumeCallback(for: token) == false)
    #expect(registry.activeReceiverCount == 1)
    #expect(weakReceiver != nil)
    #expect(registry.consumeCallback(for: token) == true)
    #expect(registry.pendingCallbackCount == 0)
    #expect(registry.activeReceiverCount == 0)
    #expect(weakReceiver == nil)
}

@Test func cancelledImportLateCallbackCannotCollideWithNewReceiver() {
    var registry = PromiseReceiverRegistry()
    let firstToken = registry.reserveToken()
    registry.activate(token: firstToken, receiver: NSObject(), callbackCount: 1)
    registry.cancelAll()

    let secondToken = registry.reserveToken()
    registry.activate(token: secondToken, receiver: NSObject(), callbackCount: 1)

    #expect(firstToken != secondToken)
    #expect(registry.consumeCallback(for: firstToken) == nil)
    #expect(registry.activeReceiverCount == 1)
    #expect(registry.pendingCallbackCount == 1)
    #expect(registry.consumeCallback(for: secondToken) == true)
    #expect(registry.activeReceiverCount == 0)
}

@Test @MainActor
func shakeDetectorRecognizesPromisedScreenshotDrag() {
    let delegate = TestFilePromiseDelegate()
    let provider = NSFilePromiseProvider(fileType: "public.png", delegate: delegate)
    let pasteboard = NSPasteboard.withUniqueName()
    pasteboard.clearContents()
    #expect(pasteboard.writeObjects([provider]))
    #expect(FileDragPasteboard.containsFiles(pasteboard))
}

@Test @MainActor
func droppingOnPreviewCenterAddsFileToShelfModel() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let file = directory.appendingPathComponent("center-drop.txt")
    try Data("drop".utf8).write(to: file)

    let model = ShelfModel()
    let content = ShelfContentView(
        frame: NSRect(x: 0, y: 0, width: 256, height: 224),
        model: model,
        onClose: {},
        onToggleCollapsed: {},
        onToggleItems: {}
    )
    let preview = try #require(content.subviews.first { $0 is ShelfPreviewView } as? ShelfPreviewView)
    content.layoutSubtreeIfNeeded()
    #expect(preview.hitTest(NSPoint(x: preview.bounds.midX, y: preview.bounds.midY)) === preview)

    let pasteboard = NSPasteboard.withUniqueName()
    pasteboard.clearContents()
    pasteboard.writeObjects([file as NSURL])
    let drag = TestDraggingInfo(pasteboard: pasteboard)

    #expect(content.draggingEntered(drag) == .copy)
    #expect(content.prepareForDragOperation(drag))
    #expect(content.performDragOperation(drag))
    #expect(model.items.map(\.displayName) == ["center-drop.txt"])
}

@Test @MainActor
func expandedGridCellCreatesSingleItemDrag() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let file = directory.appendingPathComponent("individual-item.txt")
    try Data("drag".utf8).write(to: file)
    let item = try #require(ShelfItem(url: file))
    let cell = ShelfGridCellView(item: item)
    cell.frame = NSRect(x: 0, y: 0, width: 126, height: 126)

    #expect(cell.hitTest(NSPoint(x: 63, y: 63)) === cell)
    #expect(cell.makeDraggingItem() != nil)
}

@Test @MainActor
func expandedGridHitTestsEachColumnIndependently() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let names = ["left.txt", "middle.txt", "right.txt"]
    let urls = try names.map { name -> URL in
        let url = directory.appendingPathComponent(name)
        try Data(name.utf8).write(to: url)
        return url
    }
    let model = ShelfModel()
    #expect(model.add(urls: urls) == 3)

    let grid = ShelfGridView(model: model)
    grid.frame = NSRect(x: 0, y: 0, width: 406, height: 132)
    grid.reload()
    grid.layoutSubtreeIfNeeded()

    let hitNames = [CGFloat(64), 202, 340].compactMap { x in
        (grid.hitTest(NSPoint(x: x, y: 64)) as? ShelfGridCellView)?.representedItemName
    }
    #expect(hitNames == names)
}

@Test @MainActor func frameTransitionQueueCoalescesRapidRequestsToLatestTarget() throws {
    var queue = ShelfFrameTransitionQueue()
    let firstRequest = queue.request(size: ShelfWindowController.collapsedSize)
    let first = try #require(firstRequest)
    let itemsRequest = queue.request(size: ShelfWindowController.itemsSize)
    let expandedRequest = queue.request(size: ShelfWindowController.expandedSize)
    #expect(itemsRequest == nil)
    #expect(expandedRequest == nil)
    #expect(queue.latestTargetSize == ShelfWindowController.expandedSize)

    let latestRequest = queue.complete(generation: first.generation)
    let latest = try #require(latestRequest)
    #expect(latest.size == ShelfWindowController.expandedSize)
    let staleCompletion = queue.complete(generation: first.generation + 1)
    #expect(staleCompletion == nil)
    #expect(queue.latestTargetSize == ShelfWindowController.expandedSize)
    let finalCompletion = queue.complete(generation: latest.generation)
    #expect(finalCompletion == nil)
    #expect(queue.latestTargetSize == nil)
}

@Test @MainActor func cancelledTransitionQueueRejectsStaleCompletionAndUsesNewGeneration() throws {
    var queue = ShelfFrameTransitionQueue()
    let cancelledRequest = queue.request(size: ShelfWindowController.collapsedSize)
    let cancelled = try #require(cancelledRequest)
    queue.cancelAll()

    let staleCompletion = queue.complete(generation: cancelled.generation)
    #expect(staleCompletion == nil)
    #expect(queue.latestTargetSize == nil)
    let replacementRequest = queue.request(size: ShelfWindowController.itemsSize)
    let replacement = try #require(replacementRequest)
    #expect(replacement.generation > cancelled.generation)
    #expect(queue.latestTargetSize == ShelfWindowController.itemsSize)
}

@Test @MainActor func rapidControllerTogglesSynchronizeModeAndLatestFrameTarget() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let urls = try ["one.txt", "two.txt"].map { name -> URL in
        let url = directory.appendingPathComponent(name)
        try Data(name.utf8).write(to: url)
        return url
    }
    let model = ShelfModel()
    #expect(model.add(urls: urls) == 2)
    let controller = ShelfWindowController(
        frame: NSRect(origin: .zero, size: ShelfWindowController.expandedSize),
        model: model
    )

    controller.toggleCollapsed()
    controller.toggleCollapsed()
    controller.toggleItems()
    controller.toggleCollapsed()
    controller.toggleCollapsed()

    #expect(controller.logicalModeForTesting == .expanded)
    #expect(controller.requestedTransitionSizeForTesting == ShelfWindowController.expandedSize)
}

@MainActor
private final class TestDraggingInfo: NSObject, @preconcurrency NSDraggingInfo {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard) {
        self.pasteboard = pasteboard
    }

    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { .copy }
    var draggingLocation: NSPoint { .zero }
    var draggedImageLocation: NSPoint { .zero }
    var draggedImage: NSImage? { nil }
    var draggingPasteboard: NSPasteboard { pasteboard }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }

    func slideDraggedImage(to screenPoint: NSPoint) {}

    override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? {
        nil
    }

    func enumerateDraggingItems(
        options enumOpts: NSDraggingItemEnumerationOptions = [],
        for view: NSView?,
        classes classArray: [AnyClass],
        searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
        using block: @escaping (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {}

    func resetSpringLoading() {}
}

private final class TestFilePromiseDelegate: NSObject, NSFilePromiseProviderDelegate {
    let contents = Data("promised-screenshot".utf8)

    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        fileNameForType fileType: String
    ) -> String {
        "Immediate Screenshot.png"
    }

    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        writePromiseTo url: URL,
        completionHandler: @escaping (Error?) -> Void
    ) {
        do {
            try contents.write(to: url)
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }
}

private final class PanelStubThumbnailProvider: ThumbnailProviding {
    func requestThumbnail(for url: URL, completion: @escaping (NSImage) -> Void) {
        completion(NSImage(size: NSSize(width: 16, height: 16)))
    }
}

@MainActor
private func makeShelfContent(model: ShelfModel) -> ShelfContentView {
    ShelfContentView(
        frame: NSRect(x: 0, y: 0, width: 256, height: 224),
        model: model,
        onClose: {},
        onToggleCollapsed: {},
        onToggleItems: {}
    )
}

private struct TestPromiseFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
