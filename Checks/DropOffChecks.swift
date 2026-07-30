import AppKit
import Foundation

@main
enum DropOffChecks {
    @MainActor
    static func main() throws {
        try checkShakeRecognition()
        try checkDragActivation()
        try checkSingleInstanceLock()
        try checkPromisedFileDragRecognition()
        try checkPlacement()
        try checkFileModel()
        try checkWebLink()
        try checkMediaFormatCorrection()
        try checkTransientScreenshot()
        print("Drop-off checks passed: single-instance launch, drag activation, file promises, shake recognition, placement, file references, media formats, links, and transient screenshots")
    }

    private static func checkDragActivation() throws {
        var touchpadDrag = DragActivationState()
        touchpadDrag.begin(pasteboardChangeCount: 5, beganInsideDropOff: false)
        try require(
            !touchpadDrag.shouldProcessDrag(
                currentPasteboardChangeCount: 5,
                pasteboardContainsFiles: true
            ),
            "A held touchpad without a new file drag must be ignored"
        )

        var fileDrag = DragActivationState()
        fileDrag.begin(pasteboardChangeCount: 5, beganInsideDropOff: false)
        try require(
            fileDrag.shouldProcessDrag(
                currentPasteboardChangeCount: 6,
                pasteboardContainsFiles: true
            ),
            "A new file drag should be accepted"
        )

        var shelfWindowDrag = DragActivationState()
        shelfWindowDrag.begin(pasteboardChangeCount: 5, beganInsideDropOff: true)
        try require(
            !shelfWindowDrag.shouldProcessDrag(
                currentPasteboardChangeCount: 6,
                pasteboardContainsFiles: true
            ),
            "Dragging a Drop-off shelf must not create another shelf"
        )
    }

    private static func checkSingleInstanceLock() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let lockURL = directory.appendingPathComponent("drop-off-instance.lock")

        var firstInstance: SingleInstanceLock? = SingleInstanceLock(url: lockURL)
        try require(firstInstance != nil, "The first app instance must acquire its lock")
        try require(
            SingleInstanceLock(url: lockURL) == nil,
            "A second app instance must be rejected"
        )
        firstInstance = nil
        try require(
            SingleInstanceLock(url: lockURL) != nil,
            "The lock must recover after the first app exits"
        )
    }

    private static func checkShakeRecognition() throws {
        var recognizer = ShakeGestureRecognizer()
        let shake = [0, 42, 0, 42, 0].enumerated().map { index, x in
            recognizer.process(
                point: CGPoint(x: x, y: 0),
                timestamp: Double(index) * 0.05
            )
        }
        try require(shake.filter { $0 }.count == 1, "Fast shake should trigger exactly once")
        try require(
            !recognizer.process(point: CGPoint(x: 42, y: 0), timestamp: 0.3),
            "A drag must not trigger twice"
        )

        recognizer.reset()
        let ordinary = stride(from: CGFloat(0), through: 180, by: 30).enumerated().map {
            recognizer.process(
                point: CGPoint(x: $0.element, y: $0.element * 0.2),
                timestamp: Double($0.offset) * 0.04
            )
        }
        try require(!ordinary.contains(true), "Ordinary pointer travel should not trigger")

        recognizer.reset()
        let slow = [0, 50, 0, 50, 0].enumerated().map { index, x in
            recognizer.process(
                point: CGPoint(x: x, y: 0),
                timestamp: Double(index) * 0.2
            )
        }
        try require(!slow.contains(true), "Slow waving should not trigger")
    }

    @MainActor
    private static func checkPromisedFileDragRecognition() throws {
        let delegate = CheckFilePromiseDelegate()
        let provider = NSFilePromiseProvider(fileType: "public.png", delegate: delegate)
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        try require(
            pasteboard.writeObjects([provider]),
            "A promised screenshot should be writable to the drag pasteboard"
        )
        try require(
            FileDragPasteboard.containsFiles(pasteboard),
            "Shake activation must recognize a promised screenshot drag"
        )
    }

    private static func checkPlacement() throws {
        let visibleFrame = NSRect(x: -1920, y: -120, width: 1920, height: 1080)
        let frame = ShelfPlacement.frame(
            near: NSPoint(x: -1, y: 959),
            size: NSSize(width: 320, height: 280),
            visibleFrame: visibleFrame
        )
        try require(
            visibleFrame.insetBy(dx: 8, dy: 8).contains(frame),
            "Shelf frame must stay within the active display"
        )
    }

    @MainActor
    private static func checkFileModel() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = directory.appendingPathComponent("before.bin")
        let moved = directory.appendingPathComponent("after.bin")
        try Data([1, 2, 3]).write(to: original)

        let model = ShelfModel(thumbnailProvider: CheckThumbnailProvider())
        try require(model.add(urls: [original, original]) == 1, "Duplicate files must be ignored")
        try FileManager.default.moveItem(at: original, to: moved)
        try require(
            model.availableItems().first?.currentURL.standardizedFileURL == moved.standardizedFileURL,
            "Moved files should resolve through their file reference or bookmark"
        )

        try FileManager.default.removeItem(at: moved)
        try require(model.availableItems().isEmpty, "Deleted files must become unavailable")
        model.removeUnavailable()
        try require(model.items.isEmpty, "Unavailable items must be removable")
    }

    @MainActor
    private static func checkWebLink() throws {
        let model = ShelfModel(thumbnailProvider: CheckThumbnailProvider())
        guard let link = URL(string: "https://Example.com/drop-off") else {
            throw CheckFailure(message: "Check URL should be valid")
        }
        try require(model.add(urls: [link]) == 1, "A web link should be accepted")
        guard let item = model.items.first else {
            throw CheckFailure(message: "A web link should create a shelf item")
        }
        try require(item.kind == .webLink, "A web link must remain a link")

        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        try require(
            pasteboard.writeObjects([item.pasteboardWriter]),
            "A saved link should be writable to a pasteboard"
        )
        try require(
            pasteboard.string(forType: .URL) == "https://example.com/drop-off",
            "A saved link should drag back out as its normalized URL"
        )
    }

    private static func checkMediaFormatCorrection() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        try require(
            MediaFileFormat.detectedPathExtension(in: png) == "png",
            "PNG contents must be recognized independently of their filename"
        )
    }

    @MainActor
    private static func checkTransientScreenshot() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let screenshotDirectory = root
            .appendingPathComponent("TemporaryItems", isDirectory: true)
            .appendingPathComponent("NSIRD_screencaptureui_check", isDirectory: true)
        try FileManager.default.createDirectory(
            at: screenshotDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        for pathExtension in ["png", "jpg", "heic", "pdf", "txt", "zip"] {
            let source = screenshotDirectory.appendingPathComponent("capture.\(pathExtension)")
            let contents = Data("transient-\(pathExtension)".utf8)
            try contents.write(to: source)

            let model = ShelfModel(thumbnailProvider: CheckThumbnailProvider())
            let addedCount = try model.addDropped(urls: [source])
            try require(
                addedCount == 1,
                "Transient \(pathExtension) should be accepted"
            )
            guard let preserved = model.items.first?.currentURL else {
                throw CheckFailure(message: "Transient \(pathExtension) should be preserved")
            }
            try require(
                preserved.standardizedFileURL != source.standardizedFileURL,
                "Transient \(pathExtension) must not retain its short-lived URL"
            )

            try FileManager.default.removeItem(at: source)
            try require(
                model.availableItems().first?.currentURL == preserved,
                "Transient \(pathExtension) should remain available after its source disappears"
            )
            let preservedContents = try Data(contentsOf: preserved)
            try require(
                preservedContents == contents,
                "Preserved \(pathExtension) contents must match the source"
            )

            model.clear()
            try require(
                !FileManager.default.fileExists(atPath: preserved.path),
                "Clearing the shelf must remove its preserved transient files"
            )
        }

        let promiseModel = ShelfModel(thumbnailProvider: CheckThumbnailProvider())
        let promisedImport = try promiseModel.beginPromisedFilesImport()
        let lateFile = promisedImport.destination.appendingPathComponent("late.png")
        try Data("late".utf8).write(to: lateFile)
        promiseModel.clear()
        promiseModel.addPromisedFile(at: lateFile, generation: promisedImport.generation)
        try require(
            promiseModel.items.isEmpty,
            "A cleared shelf must reject late file-promise callbacks"
        )
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw CheckFailure(message: message) }
    }
}

private struct CheckFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

private final class CheckThumbnailProvider: ThumbnailProviding {
    func requestThumbnail(for url: URL, completion: @escaping (NSImage) -> Void) {
        completion(NSImage(size: NSSize(width: 16, height: 16)))
    }
}

private final class CheckFilePromiseDelegate: NSObject, NSFilePromiseProviderDelegate {
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
        completionHandler(nil)
    }
}
