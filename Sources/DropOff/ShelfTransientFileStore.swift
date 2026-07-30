import Foundation
import Darwin

final class ShelfTransientFileStore {
    private struct OwnershipMarker: Codable {
        let processIdentifier: Int32
        let createdAt: Date
    }

    private static let ownershipMarkerName = ".dropoff-shelf-owner.json"
    private static let staleAge: TimeInterval = 24 * 60 * 60

    private let fileManager: FileManager
    private let shelvesURL: URL
    private let rootURL: URL
    private let now: () -> Date
    private let isProcessAlive: (Int32) -> Bool

    init(
        fileManager: FileManager = .default,
        shelvesURL: URL? = nil,
        now: @escaping () -> Date = Date.init,
        isProcessAlive: @escaping (Int32) -> Bool = { processIdentifier in
            processIdentifier > 0 && (kill(processIdentifier, 0) == 0 || errno == EPERM)
        }
    ) {
        self.fileManager = fileManager
        self.now = now
        self.isProcessAlive = isProcessAlive
        let requestedShelvesURL = shelvesURL ?? fileManager.temporaryDirectory
            .appendingPathComponent("Drop-off", isDirectory: true)
            .appendingPathComponent("Shelves", isDirectory: true)
        self.shelvesURL = requestedShelvesURL.standardizedFileURL.resolvingSymlinksInPath()
        rootURL = self.shelvesURL.appendingPathComponent(UUID().uuidString, isDirectory: true)

        removeStaleOwnedShelves()
    }

    deinit {
        try? fileManager.removeItem(at: rootURL)
    }

    func preserveTransientURLs(_ urls: [URL]) throws -> [URL] {
        var dropDirectory: URL?
        var seenSourcePaths = Set<String>()
        var preservedURLs: [URL] = []

        do {
            for url in urls {
                let standardizedURL = url.standardizedFileURL
                guard seenSourcePaths.insert(standardizedURL.path).inserted else { continue }
                let ownedSource = sourceOwnedByAnotherShelf(standardizedURL)
                guard isTransient(standardizedURL, ownedSource: ownedSource) else {
                    preservedURLs.append(standardizedURL)
                    continue
                }

                let directory: URL
                if let dropDirectory {
                    directory = dropDirectory
                } else {
                    directory = try makeDropDirectory()
                    dropDirectory = directory
                }

                let destination = uniqueDestination(
                    named: standardizedURL.lastPathComponent,
                    in: directory
                )
                // Copy the resolved file rather than the link itself. Otherwise a shelf that
                // receives a symlink owned by another shelf still depends on that shelf's root.
                try fileManager.copyItem(at: ownedSource ?? standardizedURL, to: destination)
                preservedURLs.append(destination.standardizedFileURL)
            }

            return preservedURLs
        } catch {
            if let dropDirectory {
                try? fileManager.removeItem(at: dropDirectory)
            }
            throw error
        }
    }

    func makePromisedFilesDestination() throws -> URL {
        try makeDropDirectory()
    }

    func correctMediaFilenameIfNeeded(at url: URL) throws -> URL {
        let standardizedURL = url.standardizedFileURL
        guard isContained(standardizedURL, in: rootURL),
              let detectedExtension = MediaFileFormat.detectedPathExtension(at: standardizedURL),
              url.pathExtension.lowercased() != detectedExtension else {
            return url
        }

        let stem = standardizedURL.deletingPathExtension().lastPathComponent
        let destination = uniqueDestination(
            named: "\(stem.isEmpty ? "Dropped Media" : stem).\(detectedExtension)",
            in: standardizedURL.deletingLastPathComponent()
        )
        try fileManager.moveItem(at: standardizedURL, to: destination)
        return destination
    }

    func clear() {
        try? fileManager.removeItem(at: rootURL)
    }

    private func isTransient(_ url: URL, ownedSource: URL?) -> Bool {
        let path = url.standardizedFileURL.path
        return path.contains("/TemporaryItems/")
            || path.contains("/NSIRD_screencaptureui")
            || path.contains("/com.apple.NSItemProvider")
            || ownedSource != nil
    }

    private func makeDropDirectory() throws -> URL {
        try ensureOwnedRootExists()
        let directory = rootURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func ensureOwnedRootExists() throws {
        guard !fileManager.fileExists(atPath: rootURL.path) else { return }
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let marker = OwnershipMarker(
            processIdentifier: ProcessInfo.processInfo.processIdentifier,
            createdAt: now()
        )
        let data = try JSONEncoder().encode(marker)
        try data.write(
            to: rootURL.appendingPathComponent(Self.ownershipMarkerName),
            options: .atomic
        )
    }

    private func sourceOwnedByAnotherShelf(_ url: URL) -> URL? {
        let lexicalSource = url.standardizedFileURL
        let resolvedSource = lexicalSource.resolvingSymlinksInPath()
        let lexicallyOwnedByAnotherShelf = isContained(lexicalSource, in: shelvesURL)
            && !isContained(lexicalSource, in: rootURL)
        let canonicallyOwnedByAnotherShelf = isContained(resolvedSource, in: shelvesURL)
            && !isContained(resolvedSource, in: rootURL)
        return lexicallyOwnedByAnotherShelf || canonicallyOwnedByAnotherShelf
            ? resolvedSource
            : nil
    }

    private func removeStaleOwnedShelves() {
        guard let candidates = try? fileManager.contentsOfDirectory(
            at: shelvesURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for candidate in candidates where isDirectChild(candidate, of: shelvesURL) {
            let values = try? candidate.resourceValues(forKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey,
            ])
            guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }

            let markerURL = candidate.appendingPathComponent(Self.ownershipMarkerName)
            let markerValues = try? markerURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ])
            guard
                markerValues?.isRegularFile == true,
                markerValues?.isSymbolicLink != true,
                let data = try? Data(contentsOf: markerURL),
                let marker = try? JSONDecoder().decode(OwnershipMarker.self, from: data),
                now().timeIntervalSince(marker.createdAt) >= Self.staleAge,
                !isProcessAlive(marker.processIdentifier)
            else { continue }

            try? fileManager.removeItem(at: candidate)
        }
    }

    private func isContained(_ candidate: URL, in directory: URL) -> Bool {
        let candidatePath = candidate.standardizedFileURL.path
        let directoryPath = directory.standardizedFileURL.path
        return candidatePath == directoryPath || candidatePath.hasPrefix(directoryPath + "/")
    }

    private func isDirectChild(_ candidate: URL, of directory: URL) -> Bool {
        let standardizedCandidate = candidate.standardizedFileURL
        let standardizedDirectory = directory.standardizedFileURL
        return standardizedCandidate.deletingLastPathComponent().path == standardizedDirectory.path
            && standardizedCandidate != rootURL.standardizedFileURL
    }

    func uniqueDestination(named suggestedName: String, in directory: URL) -> URL {
        let name = suggestedName.isEmpty ? "Dropped File" : suggestedName
        var destination = directory.appendingPathComponent(name)
        guard fileManager.fileExists(atPath: destination.path) else { return destination }

        let source = URL(fileURLWithPath: name)
        let stem = source.deletingPathExtension().lastPathComponent
        let pathExtension = source.pathExtension
        var counter = 2

        repeat {
            let candidateName = pathExtension.isEmpty
                ? "\(stem) \(counter)"
                : "\(stem) \(counter).\(pathExtension)"
            destination = directory.appendingPathComponent(candidateName)
            counter += 1
        } while fileManager.fileExists(atPath: destination.path)

        return destination
    }
}
