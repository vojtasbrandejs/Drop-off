import AppKit
import Foundation

final class ShelfItem: NSObject {
    enum Kind {
        case file
        case webLink
    }

    let id = UUID()
    let kind: Kind
    let originalURL: URL
    private(set) var currentURL: URL
    let fileReferenceURL: URL?
    let bookmarkData: Data?
    var thumbnail: NSImage
    private(set) var isAvailable: Bool

    init?(url: URL) {
        if url.isFileURL {
            let normalizedURL = url.standardizedFileURL
            guard FileManager.default.fileExists(atPath: normalizedURL.path) else {
                return nil
            }

            kind = .file
            originalURL = normalizedURL
            currentURL = normalizedURL
            fileReferenceURL = (normalizedURL as NSURL).fileReferenceURL()
            bookmarkData = try? normalizedURL.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: [.fileResourceIdentifierKey, .nameKey],
                relativeTo: nil
            )
            thumbnail = ThumbnailProvider.fallbackIcon(for: normalizedURL)
        } else {
            guard let normalizedURL = Self.normalizedWebURL(url) else { return nil }

            kind = .webLink
            originalURL = normalizedURL
            currentURL = normalizedURL
            fileReferenceURL = nil
            bookmarkData = nil
            thumbnail = Self.linkIcon()
        }

        isAvailable = true
        super.init()
    }

    var displayName: String {
        switch kind {
        case .file:
            return currentURL.lastPathComponent
        case .webLink:
            return currentURL.host(percentEncoded: false) ?? currentURL.absoluteString
        }
    }

    var identityKey: String {
        if kind == .webLink {
            return "link:\(currentURL.absoluteString)"
        }
        if let identifier = try? currentURL.resourceValues(
            forKeys: [.fileResourceIdentifierKey]
        ).fileResourceIdentifier {
            return String(describing: identifier)
        }
        return currentURL.resolvingSymlinksInPath().path
    }

    @discardableResult
    func resolveCurrentURL() -> URL? {
        if kind == .webLink {
            isAvailable = true
            return currentURL
        }

        if FileManager.default.fileExists(atPath: currentURL.path) {
            isAvailable = true
            return currentURL
        }

        if let fileReferenceURL,
           FileManager.default.fileExists(atPath: fileReferenceURL.path) {
            currentURL = fileReferenceURL.standardizedFileURL
            isAvailable = true
            return currentURL
        }

        if let bookmarkData {
            var isStale = false
            if let resolved = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withoutUI, .withoutMounting],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ), FileManager.default.fileExists(atPath: resolved.path) {
                currentURL = resolved.standardizedFileURL
                isAvailable = true
                return currentURL
            }
        }

        isAvailable = false
        return nil
    }

    var pasteboardWriter: NSPasteboardWriting {
        switch kind {
        case .file:
            return currentURL as NSURL
        case .webLink:
            return WebLinkPasteboardWriter(url: currentURL)
        }
    }

    private static func normalizedWebURL(_ url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = scheme
        components.host = components.host?.lowercased()
        return components.url
    }

    private static func linkIcon() -> NSImage {
        let image = NSImage(
            systemSymbolName: "link",
            accessibilityDescription: "Web link"
        ) ?? NSWorkspace.shared.icon(for: .url)
        image.size = NSSize(width: 128, height: 128)
        return image
    }
}

final class WebLinkPasteboardWriter: NSObject, NSPasteboardWriting {
    let url: URL

    init(url: URL) {
        self.url = url
    }

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        [.URL, .string]
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        guard type == .URL || type == .string else { return nil }
        return url.absoluteString
    }
}
