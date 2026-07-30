import AppKit
import Testing
@testable import DropOff

@Test @MainActor func acceptsArbitraryExtensionsEmptyFilesAndFolders() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let oddFile = temporaryDirectory.appendingPathComponent("archive.anything")
    let emptyFile = temporaryDirectory.appendingPathComponent("empty")
    let folder = temporaryDirectory.appendingPathComponent("Folder", isDirectory: true)
    #expect(FileManager.default.createFile(atPath: oddFile.path, contents: Data([1, 2, 3])))
    #expect(FileManager.default.createFile(atPath: emptyFile.path, contents: Data()))
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)

    let model = ShelfModel(thumbnailProvider: StubThumbnailProvider())
    #expect(model.add(urls: [oddFile, emptyFile, folder]) == 3)
    #expect(model.items.count == 3)
}

@Test @MainActor func deduplicatesFilesWithinShelf() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let file = temporaryDirectory.appendingPathComponent("video.mov")
    #expect(FileManager.default.createFile(atPath: file.path, contents: Data()))
    let model = ShelfModel(thumbnailProvider: StubThumbnailProvider())

    #expect(model.add(urls: [file, file]) == 1)
    #expect(model.add(urls: [file]) == 0)
    #expect(model.items.count == 1)
}

@Test @MainActor func acceptsAndDeduplicatesNormalizedWebLinks() throws {
    let model = ShelfModel(thumbnailProvider: StubThumbnailProvider())
    let mixedCase = try #require(URL(string: "HTTPS://Example.COM/path?q=1"))
    let normalized = try #require(URL(string: "https://example.com/path?q=1"))

    #expect(model.add(urls: [mixedCase, normalized]) == 1)
    let item = try #require(model.items.first)
    #expect(item.kind == .webLink)
    #expect(item.displayName == "example.com")
    #expect(item.resolveCurrentURL()?.absoluteString == "https://example.com/path?q=1")
    #expect(item.isAvailable)
}

@Test @MainActor func rejectsNonWebAndMalformedURLs() throws {
    let model = ShelfModel(thumbnailProvider: StubThumbnailProvider())
    let mail = try #require(URL(string: "mailto:hello@example.com"))
    let relative = try #require(URL(string: "/not-a-link"))

    #expect(model.add(urls: [mail, relative]) == 0)
    #expect(model.items.isEmpty)
}

@Test @MainActor func largeFileIsReferencedWithoutLoadingContents() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let file = temporaryDirectory.appendingPathComponent("large-video.mov")
    #expect(FileManager.default.createFile(atPath: file.path, contents: nil))
    let handle = try FileHandle(forWritingTo: file)
    try handle.truncate(atOffset: 2_000_000_000)
    try handle.close()

    let model = ShelfModel(thumbnailProvider: StubThumbnailProvider())
    #expect(model.add(urls: [file]) == 1)
    #expect(model.items.first?.currentURL == file.standardizedFileURL)
}

@Test @MainActor func movedFileCanBeResolved() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let original = temporaryDirectory.appendingPathComponent("before.txt")
    let moved = temporaryDirectory.appendingPathComponent("after.txt")
    #expect(FileManager.default.createFile(atPath: original.path, contents: Data("x".utf8)))
    let item = try #require(ShelfItem(url: original))

    try FileManager.default.moveItem(at: original, to: moved)
    let resolved = item.resolveCurrentURL()
    #expect(resolved?.standardizedFileURL == moved.standardizedFileURL)
    #expect(item.isAvailable)
}

@Test @MainActor func deletedFileBecomesUnavailableAndCanBeRemoved() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let file = temporaryDirectory.appendingPathComponent("gone.zip")
    #expect(FileManager.default.createFile(atPath: file.path, contents: Data()))
    let model = ShelfModel(thumbnailProvider: StubThumbnailProvider())
    model.add(urls: [file])

    try FileManager.default.removeItem(at: file)
    #expect(model.availableItems().isEmpty)
    #expect(!model.items[0].isAvailable)

    model.removeUnavailable()
    #expect(model.items.isEmpty)
}

@Test @MainActor func transientScreenshotFormatsArePreservedForLaterDragging() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let screenshotDirectory = temporaryDirectory
        .appendingPathComponent("TemporaryItems", isDirectory: true)
        .appendingPathComponent("NSIRD_screencaptureui_test", isDirectory: true)
    try FileManager.default.createDirectory(
        at: screenshotDirectory,
        withIntermediateDirectories: true
    )

    for pathExtension in ["png", "jpg", "heic", "pdf", "txt", "zip"] {
        let source = screenshotDirectory.appendingPathComponent("capture.\(pathExtension)")
        let contents = Data("transient-\(pathExtension)".utf8)
        try contents.write(to: source)

        let model = ShelfModel(thumbnailProvider: StubThumbnailProvider())
        #expect(try model.addDropped(urls: [source]) == 1)
        let preservedURL = try #require(model.items.first?.currentURL)
        #expect(preservedURL.standardizedFileURL != source.standardizedFileURL)

        try FileManager.default.removeItem(at: source)
        #expect(model.items.first?.resolveCurrentURL() == preservedURL)
        #expect(try Data(contentsOf: preservedURL) == contents)

        let cell = ShelfGridCellView(item: try #require(model.items.first))
        cell.frame = NSRect(x: 0, y: 0, width: 126, height: 126)
        #expect(cell.makeDraggingItem() != nil)
    }
}

@Test @MainActor func stableFilesAndFoldersRemainReferences() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let image = temporaryDirectory.appendingPathComponent("saved-screenshot.png")
    let folder = temporaryDirectory.appendingPathComponent("Saved Folder", isDirectory: true)
    try Data("stable".utf8).write(to: image)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

    let model = ShelfModel(thumbnailProvider: StubThumbnailProvider())
    #expect(try model.addDropped(urls: [image, folder]) == 2)
    #expect(model.items.map(\.currentURL) == [image, folder].map(\.standardizedFileURL))
}

@Test @MainActor func clearingShelfRemovesPreservedTransientFiles() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let screenshotDirectory = temporaryDirectory
        .appendingPathComponent("TemporaryItems", isDirectory: true)
        .appendingPathComponent("NSIRD_screencaptureui_test", isDirectory: true)
    try FileManager.default.createDirectory(
        at: screenshotDirectory,
        withIntermediateDirectories: true
    )
    let source = screenshotDirectory.appendingPathComponent("capture.png")
    try Data("transient".utf8).write(to: source)

    let model = ShelfModel(thumbnailProvider: StubThumbnailProvider())
    #expect(try model.addDropped(urls: [source]) == 1)
    let preservedURL = try #require(model.items.first?.currentURL)
    #expect(FileManager.default.fileExists(atPath: preservedURL.path))

    model.clear()
    #expect(!FileManager.default.fileExists(atPath: preservedURL.path))
}

@Test @MainActor func clearedShelfRejectsLatePromisedFileCompletion() throws {
    let model = ShelfModel(thumbnailProvider: StubThumbnailProvider())
    let promisedImport = try model.beginPromisedFilesImport()
    let promisedFile = promisedImport.destination.appendingPathComponent("late.png")
    try Data("late".utf8).write(to: promisedFile)

    model.clear()
    model.addPromisedFile(at: promisedFile, generation: promisedImport.generation)

    #expect(model.items.isEmpty)
}

@Test @MainActor func promisedFileSuccessClearsPendingStateAndAddsFile() throws {
    let model = ShelfModel(thumbnailProvider: StubThumbnailProvider())
    let promisedImport = try model.beginPromisedFilesImport(expectedFileCount: 1)
    let promisedFile = promisedImport.destination.appendingPathComponent("success.png")
    try Data("success".utf8).write(to: promisedFile)

    #expect(model.promisedFilesImportState.pendingFileCount == 1)
    #expect(model.promisedFilesImportState.failureMessage == nil)
    model.completePromisedFile(
        at: promisedFile,
        error: nil,
        generation: promisedImport.generation
    )

    #expect(model.items.map(\.displayName) == ["success.png"])
    #expect(model.promisedFilesImportState == PromisedFilesImportState())
}

@Test @MainActor func promisedMediaUsesItsActualFormatInsteadOfMisleadingExtension() throws {
    let model = ShelfModel(thumbnailProvider: StubThumbnailProvider())
    let promisedImport = try model.beginPromisedFilesImport(expectedFileCount: 1)
    let misleadingURL = promisedImport.destination.appendingPathComponent("Message Image.jpeg")
    let pngData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 4, 5, 6])
    try pngData.write(to: misleadingURL)

    model.completePromisedFile(
        at: misleadingURL,
        error: nil,
        generation: promisedImport.generation
    )

    let storedURL = try #require(model.items.first?.currentURL)
    #expect(storedURL.lastPathComponent == "Message Image.png")
    #expect(try Data(contentsOf: storedURL) == pngData)
    #expect(!FileManager.default.fileExists(atPath: misleadingURL.path))
}

@Test func mediaFormatDetectionCoversImagesAndCommonVideoContainers() {
    let cases: [(Data, String)] = [
        (Data([0xFF, 0xD8, 0xFF, 0]), "jpg"),
        (Data("GIF89a".utf8), "gif"),
        (Data("<svg viewBox=\"0 0 1 1\"></svg>".utf8), "svg"),
        (Data([0, 0, 0, 20] + Array("ftypqt  ".utf8)), "mov"),
        (Data([0, 0, 0, 20] + Array("ftypmp42".utf8)), "mp4"),
        (Data([0, 0, 0, 20] + Array("ftypheic".utf8)), "heic"),
    ]

    for (data, expectedExtension) in cases {
        #expect(MediaFileFormat.detectedPathExtension(in: data) == expectedExtension)
    }
}

@Test func mediaCorrectionNeverRenamesFilesOutsideItsShelfStore() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let store = ShelfTransientFileStore(
        shelvesURL: temporaryDirectory.appendingPathComponent("Shelves", isDirectory: true)
    )
    let externalURL = temporaryDirectory.appendingPathComponent("External.jpeg")
    try Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]).write(to: externalURL)

    #expect(try store.correctMediaFilenameIfNeeded(at: externalURL) == externalURL)
    #expect(FileManager.default.fileExists(atPath: externalURL.path))
    #expect(
        !FileManager.default.fileExists(
            atPath: temporaryDirectory.appendingPathComponent("External.png").path
        )
    )
}

@Test @MainActor func promisedFileFailureIsRetainedUntilRetry() throws {
    let model = ShelfModel(thumbnailProvider: StubThumbnailProvider())
    let firstImport = try model.beginPromisedFilesImport(expectedFileCount: 1)
    model.completePromisedFile(
        at: firstImport.destination.appendingPathComponent("failed.png"),
        error: TestPromiseError(message: "Provider stopped exporting"),
        generation: firstImport.generation
    )

    #expect(model.items.isEmpty)
    #expect(model.promisedFilesImportState.pendingFileCount == 0)
    #expect(model.promisedFilesImportState.failureMessage == "Provider stopped exporting")

    _ = try model.beginPromisedFilesImport(expectedFileCount: 2)
    #expect(model.promisedFilesImportState.pendingFileCount == 2)
    #expect(model.promisedFilesImportState.failureMessage == nil)
}

@Test @MainActor func droppingFileOwnedByAnotherShelfCreatesIndependentCopy() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let shelves = temporaryDirectory.appendingPathComponent("Shelves", isDirectory: true)
    let firstStore = ShelfTransientFileStore(shelvesURL: shelves)
    let secondStore = ShelfTransientFileStore(shelvesURL: shelves)
    let firstModel = ShelfModel(
        thumbnailProvider: StubThumbnailProvider(),
        transientFileStore: firstStore
    )
    let secondModel = ShelfModel(
        thumbnailProvider: StubThumbnailProvider(),
        transientFileStore: secondStore
    )
    let sourceDirectory = temporaryDirectory
        .appendingPathComponent("TemporaryItems", isDirectory: true)
    try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
    let source = sourceDirectory.appendingPathComponent("capture.png")
    try Data("owned".utf8).write(to: source)

    #expect(try firstModel.addDropped(urls: [source]) == 1)
    let firstCopy = try #require(firstModel.items.first?.currentURL)
    #expect(try secondModel.addDropped(urls: [firstCopy]) == 1)
    let secondCopy = try #require(secondModel.items.first?.currentURL)
    #expect(firstCopy != secondCopy)

    firstModel.clear()
    #expect(!FileManager.default.fileExists(atPath: firstCopy.path))
    #expect(try Data(contentsOf: secondCopy) == Data("owned".utf8))
}

@Test @MainActor func droppingSymlinkOwnedByAnotherShelfCopiesResolvedContents() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let shelves = temporaryDirectory.appendingPathComponent("Shelves", isDirectory: true)
    let firstStore = ShelfTransientFileStore(shelvesURL: shelves)
    let secondModel = ShelfModel(
        thumbnailProvider: StubThumbnailProvider(),
        transientFileStore: ShelfTransientFileStore(shelvesURL: shelves)
    )
    let firstDrop = try firstStore.makePromisedFilesDestination()
    let target = firstDrop.appendingPathComponent("target.txt")
    let link = firstDrop.appendingPathComponent("linked.txt")
    try Data("resolved".utf8).write(to: target)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

    #expect(try secondModel.addDropped(urls: [link]) == 1)
    let secondCopy = try #require(secondModel.items.first?.currentURL)
    let values = try secondCopy.resourceValues(forKeys: [.isSymbolicLinkKey])
    #expect(values.isSymbolicLink != true)

    firstStore.clear()
    #expect(!FileManager.default.fileExists(atPath: target.path))
    #expect(try Data(contentsOf: secondCopy) == Data("resolved".utf8))
}

@Test func staleCleanupRemovesOnlyOldDeadOwnedShelf() throws {
    let fixture = try makeCleanupFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let old = Date(timeIntervalSince1970: 1_000)
    let owned = try makeOwnedShelf(in: fixture.shelves, createdAt: old)

    _ = ShelfTransientFileStore(
        shelvesURL: fixture.shelves,
        now: { old.addingTimeInterval(25 * 60 * 60) },
        isProcessAlive: { _ in false }
    )

    #expect(!FileManager.default.fileExists(atPath: owned.root.path))
    withExtendedLifetime(owned.store) {}
}

@Test func staleCleanupPreservesOldLiveAndYoungDeadShelves() throws {
    let fixture = try makeCleanupFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let now = Date(timeIntervalSince1970: 100_000)
    let oldLive = try makeOwnedShelf(
        in: fixture.shelves,
        createdAt: now.addingTimeInterval(-25 * 60 * 60)
    )
    let youngDead = try makeOwnedShelf(
        in: fixture.shelves,
        createdAt: now.addingTimeInterval(-60 * 60)
    )

    _ = ShelfTransientFileStore(
        shelvesURL: fixture.shelves,
        now: { now },
        isProcessAlive: { _ in true }
    )
    #expect(FileManager.default.fileExists(atPath: oldLive.root.path))

    _ = ShelfTransientFileStore(
        shelvesURL: fixture.shelves,
        now: { now },
        isProcessAlive: { _ in false }
    )
    #expect(FileManager.default.fileExists(atPath: youngDead.root.path))
    withExtendedLifetime((oldLive.store, youngDead.store)) {}
}

@Test func staleCleanupPreservesMissingAndMalformedMarkers() throws {
    let fixture = try makeCleanupFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let missing = fixture.shelves.appendingPathComponent("missing", isDirectory: true)
    let malformed = fixture.shelves.appendingPathComponent("malformed", isDirectory: true)
    try FileManager.default.createDirectory(at: missing, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: malformed, withIntermediateDirectories: true)
    try Data("not-json".utf8).write(
        to: malformed.appendingPathComponent(".dropoff-shelf-owner.json")
    )

    _ = ShelfTransientFileStore(
        shelvesURL: fixture.shelves,
        now: { Date.distantFuture },
        isProcessAlive: { _ in false }
    )

    #expect(FileManager.default.fileExists(atPath: missing.path))
    #expect(FileManager.default.fileExists(atPath: malformed.path))
}

@Test func staleCleanupPreservesConcurrentActiveStore() throws {
    let fixture = try makeCleanupFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let old = Date(timeIntervalSince1970: 1_000)
    let active = try makeOwnedShelf(in: fixture.shelves, createdAt: old)

    _ = ShelfTransientFileStore(
        shelvesURL: fixture.shelves,
        now: { old.addingTimeInterval(25 * 60 * 60) },
        isProcessAlive: { processIdentifier in
            processIdentifier == ProcessInfo.processInfo.processIdentifier
        }
    )

    #expect(FileManager.default.fileExists(atPath: active.root.path))
    _ = try active.store.makePromisedFilesDestination()
}

@Test func staleCleanupNeverFollowsCandidateSymlinkOutsideShelvesRoot() throws {
    let fixture = try makeCleanupFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let outsideShelves = fixture.root.appendingPathComponent("Outside", isDirectory: true)
    let old = Date(timeIntervalSince1970: 1_000)
    let outside = try makeOwnedShelf(in: outsideShelves, createdAt: old)
    let sentinel = outside.root.appendingPathComponent("sentinel")
    try Data("keep".utf8).write(to: sentinel)
    let candidate = fixture.shelves.appendingPathComponent("linked-outside")
    try FileManager.default.createSymbolicLink(at: candidate, withDestinationURL: outside.root)

    _ = ShelfTransientFileStore(
        shelvesURL: fixture.shelves,
        now: { old.addingTimeInterval(25 * 60 * 60) },
        isProcessAlive: { _ in false }
    )

    #expect(FileManager.default.fileExists(atPath: sentinel.path))
    #expect(FileManager.default.fileExists(atPath: candidate.path))
    withExtendedLifetime(outside.store) {}
}

private func makeCleanupFixture() throws -> (root: URL, shelves: URL) {
    let root = try makeTemporaryDirectory()
    let shelves = root.appendingPathComponent("Shelves", isDirectory: true)
    try FileManager.default.createDirectory(at: shelves, withIntermediateDirectories: true)
    return (root, shelves)
}

private func makeOwnedShelf(
    in shelves: URL,
    createdAt: Date
) throws -> (store: ShelfTransientFileStore, root: URL) {
    let existing = Set(
        (try? FileManager.default.contentsOfDirectory(at: shelves, includingPropertiesForKeys: nil))
            ?? []
    )
    let store = ShelfTransientFileStore(
        shelvesURL: shelves,
        now: { createdAt },
        isProcessAlive: { _ in true }
    )
    _ = try store.makePromisedFilesDestination()
    let created = Set(
        try FileManager.default.contentsOfDirectory(at: shelves, includingPropertiesForKeys: nil)
    )
    return (store, try #require(created.subtracting(existing).first))
}

private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private final class StubThumbnailProvider: ThumbnailProviding {
    func requestThumbnail(for url: URL, completion: @escaping (NSImage) -> Void) {
        completion(NSImage(size: NSSize(width: 16, height: 16)))
    }
}

private struct TestPromiseError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
