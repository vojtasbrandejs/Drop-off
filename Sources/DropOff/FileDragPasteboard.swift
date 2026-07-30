import AppKit

enum FileDragPasteboard {
    static func containsFiles(_ pasteboard: NSPasteboard) -> Bool {
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

        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
        ]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options),
           urls.contains(where: { ($0 as? URL)?.isFileURL == true }) {
            return true
        }

        let legacyType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        return pasteboard.propertyList(forType: legacyType) is [String]
    }
}
