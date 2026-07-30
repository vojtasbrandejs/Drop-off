import AppKit
import QuickLookThumbnailing

protocol ThumbnailProviding: AnyObject {
    func requestThumbnail(for url: URL, completion: @escaping (NSImage) -> Void)
}

final class ThumbnailProvider: ThumbnailProviding {
    private let generator = QLThumbnailGenerator.shared

    func requestThumbnail(for url: URL, completion: @escaping (NSImage) -> Void) {
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let image = Self.fallbackIcon(for: url)
            DispatchQueue.main.async {
                completion(image)
            }
            return
        }

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: NSSize(width: 160, height: 160),
            scale: scale,
            representationTypes: .all
        )

        generator.generateBestRepresentation(for: request) { representation, _ in
            let image = representation?.nsImage ?? Self.fallbackIcon(for: url)
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }

    static func fallbackIcon(for url: URL) -> NSImage {
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 128, height: 128)
        return image
    }
}
