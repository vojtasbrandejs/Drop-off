import AppKit
import Foundation

@MainActor
final class ShelfModel {
    private(set) var items: [ShelfItem] = []
    private(set) var promisedFilesImportState = PromisedFilesImportState()
    var onChange: (() -> Void)?

    private let thumbnailProvider: ThumbnailProviding
    private let transientFileStore: ShelfTransientFileStore
    private var promisedFilesImportGeneration: UInt64 = 0

    init(
        thumbnailProvider: ThumbnailProviding = ThumbnailProvider(),
        transientFileStore: ShelfTransientFileStore = ShelfTransientFileStore()
    ) {
        self.thumbnailProvider = thumbnailProvider
        self.transientFileStore = transientFileStore
    }

    @discardableResult
    func addDropped(urls: [URL]) throws -> Int {
        let fileURLs = urls.filter(\.isFileURL)
        let links = urls.filter { !$0.isFileURL }
        let preservedURLs = try transientFileStore.preserveTransientURLs(fileURLs)
        return add(urls: preservedURLs + links)
    }

    @discardableResult
    func addDroppedMedia(_ representations: [DroppedMediaRepresentation]) throws -> Int {
        guard !representations.isEmpty else { return 0 }
        let destination = try transientFileStore.makePromisedFilesDestination()
        var materializedURLs: [URL] = []

        do {
            for representation in representations {
                let url = transientFileStore.uniqueDestination(
                    named: representation.fileName,
                    in: destination
                )
                try representation.data.write(to: url, options: .atomic)
                materializedURLs.append(url)
            }
            return add(urls: materializedURLs)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    func beginPromisedFilesImport(expectedFileCount: Int = 0) throws -> ShelfPromisedFilesImport {
        let promisedImport = ShelfPromisedFilesImport(
            destination: try transientFileStore.makePromisedFilesDestination(),
            generation: promisedFilesImportGeneration
        )
        promisedFilesImportState = PromisedFilesImportState(
            pendingFileCount: max(expectedFileCount, 0),
            failureMessage: nil
        )
        if expectedFileCount > 0 {
            onChange?()
        }
        return promisedImport
    }

    func setPromisedFilesImportExpectedCount(_ count: Int, generation: UInt64) {
        guard generation == promisedFilesImportGeneration else { return }
        promisedFilesImportState = PromisedFilesImportState(
            pendingFileCount: max(count, 0),
            failureMessage: nil
        )
        onChange?()
    }

    func addPromisedFile(at url: URL, generation: UInt64) {
        guard generation == promisedFilesImportGeneration else { return }
        add(urls: [url])
    }

    func completePromisedFile(
        at url: URL,
        error: Error?,
        generation: UInt64
    ) {
        guard generation == promisedFilesImportGeneration else { return }
        if let error {
            promisedFilesImportState.failureMessage = error.localizedDescription
        } else {
            let correctedURL = (try? transientFileStore.correctMediaFilenameIfNeeded(at: url))
                ?? url
            add(urls: [correctedURL])
        }
        promisedFilesImportState.pendingFileCount = max(
            promisedFilesImportState.pendingFileCount - 1,
            0
        )
        onChange?()
    }

    func reportPromisedFilesImportFailure(_ error: Error) {
        promisedFilesImportState = PromisedFilesImportState(
            pendingFileCount: 0,
            failureMessage: error.localizedDescription
        )
        onChange?()
    }

    @discardableResult
    func add(urls: [URL]) -> Int {
        var knownKeys = Set(items.map(\.identityKey))
        var addedItems: [ShelfItem] = []

        for url in urls {
            guard let item = ShelfItem(url: url), !knownKeys.contains(item.identityKey) else {
                continue
            }
            knownKeys.insert(item.identityKey)
            items.append(item)
            addedItems.append(item)
        }

        guard !addedItems.isEmpty else { return 0 }
        onChange?()

        for item in addedItems where item.kind == .file {
            thumbnailProvider.requestThumbnail(for: item.currentURL) { [weak self, weak item] image in
                guard let self, let item, self.items.contains(where: { $0 === item }) else { return }
                item.thumbnail = image
                self.onChange?()
            }
        }
        return addedItems.count
    }

    func clear() {
        let hadVisibleState = !items.isEmpty || promisedFilesImportState != PromisedFilesImportState()
        promisedFilesImportGeneration &+= 1
        promisedFilesImportState = PromisedFilesImportState()
        items.removeAll()
        transientFileStore.clear()
        if hadVisibleState {
            onChange?()
        }
    }

    func removeUnavailable() {
        let originalCount = items.count
        items.removeAll { !$0.isAvailable }
        if items.count != originalCount {
            onChange?()
        }
    }

    @discardableResult
    func refreshAvailability() -> Bool {
        let previous = items.map(\.isAvailable)
        for item in items {
            item.resolveCurrentURL()
        }
        let changed = previous != items.map(\.isAvailable)
        if changed {
            onChange?()
        }
        return changed
    }

    func availableItems() -> [ShelfItem] {
        refreshAvailability()
        return items.filter(\.isAvailable)
    }
}

struct ShelfPromisedFilesImport {
    let destination: URL
    let generation: UInt64
}

struct PromisedFilesImportState: Equatable {
    var pendingFileCount = 0
    var failureMessage: String?

    var isImporting: Bool { pendingFileCount > 0 }
}
