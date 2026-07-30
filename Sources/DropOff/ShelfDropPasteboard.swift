import AppKit
import UniformTypeIdentifiers

struct DroppedMediaRepresentation {
    let data: Data
    let typeIdentifier: String
    let fileName: String
}

enum ShelfDropPasteboard {
    static let readableTypes: [NSPasteboard.PasteboardType] = [
        .URL,
        .string,
        NSPasteboard.PasteboardType(UTType.image.identifier),
        NSPasteboard.PasteboardType(UTType.movie.identifier),
        NSPasteboard.PasteboardType(UTType.png.identifier),
        NSPasteboard.PasteboardType(UTType.jpeg.identifier),
        NSPasteboard.PasteboardType(UTType.svg.identifier),
        NSPasteboard.PasteboardType(UTType.gif.identifier),
        NSPasteboard.PasteboardType(UTType.heic.identifier),
        NSPasteboard.PasteboardType(UTType.mpeg4Movie.identifier),
        NSPasteboard.PasteboardType(UTType.quickTimeMovie.identifier),
    ]

    private static let ignoredImageTypes: Set<String> = [
        UTType.tiff.identifier,
        "com.apple.pict",
        "com.apple.icns",
    ]

    static func mediaRepresentations(
        from pasteboard: NSPasteboard,
        includeMovies: Bool = true
    ) -> [DroppedMediaRepresentation] {
        guard let pasteboardItems = pasteboard.pasteboardItems else { return [] }

        return pasteboardItems.compactMap { item in
            guard let type = firstOriginalMediaType(in: item, includeMovies: includeMovies),
                  let data = item.data(forType: type),
                  !data.isEmpty,
                  let contentType = UTType(type.rawValue),
                  let pathExtension = contentType.preferredFilenameExtension else {
                return nil
            }

            return DroppedMediaRepresentation(
                data: data,
                typeIdentifier: type.rawValue,
                fileName: fileName(for: item, pathExtension: pathExtension)
            )
        }
    }

    static func webURLs(from pasteboard: NSPasteboard) -> [URL] {
        var urls: [URL] = []

        if let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) {
            urls.append(contentsOf: objects.compactMap { object in
                guard let url = object as? URL, isWebURL(url) else { return nil }
                return url
            })
        }

        if let pasteboardItems = pasteboard.pasteboardItems {
            for item in pasteboardItems {
                if let value = item.string(forType: .URL),
                   let url = URL(string: value),
                   isWebURL(url) {
                    urls.append(url)
                    continue
                }
                if let value = item.string(forType: .string)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   let url = URL(string: value),
                   isWebURL(url) {
                    urls.append(url)
                }
            }
        }

        var seen = Set<String>()
        return urls.filter { seen.insert($0.absoluteString).inserted }
    }

    static func containsMediaRepresentation(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.pasteboardItems?.contains {
            firstOriginalMediaType(in: $0, includeMovies: true) != nil
        } == true
    }

    private static func firstOriginalMediaType(
        in item: NSPasteboardItem,
        includeMovies: Bool
    ) -> NSPasteboard.PasteboardType? {
        item.types.first { pasteboardType in
            guard !ignoredImageTypes.contains(pasteboardType.rawValue),
                  let type = UTType(pasteboardType.rawValue),
                  type.preferredFilenameExtension != nil else {
                return false
            }
            return type.conforms(to: .image)
                || (includeMovies && type.conforms(to: .movie))
        }
    }

    private static func fileName(
        for item: NSPasteboardItem,
        pathExtension: String
    ) -> String {
        let nameTypes = [
            NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-name"),
            NSPasteboard.PasteboardType("public.url-name"),
        ]
        let suggestedName = nameTypes.lazy
            .compactMap { item.string(forType: $0) }
            .first { !$0.isEmpty }
            ?? "Dropped Media"
        let safeName = URL(fileURLWithPath: suggestedName).lastPathComponent
        let stem = URL(fileURLWithPath: safeName)
            .deletingPathExtension()
            .lastPathComponent
        return "\(stem.isEmpty ? "Dropped Media" : stem).\(pathExtension)"
    }

    private static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && url.host != nil
    }
}
