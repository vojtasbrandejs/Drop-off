# Privacy

Drop-off is a local macOS utility. It has no account system, analytics, advertising, telemetry, cloud service, or network communication. It does not maintain a database or persist shelf contents between launches.

The optional installation command connects to GitHub over HTTPS to download Drop-off's source code. It builds the app locally, deletes its temporary source and build folder, and does not send file contents, analytics, or personal data. The installed Drop-off app itself does not make network requests.

## Mouse events and drag detection

While Drop-off is running, it installs local and global macOS event monitors for left mouse down, left mouse dragged, and left mouse up events. It uses the pointer coordinates and event timing only to recognize a shake during an active file drag and to place a shelf near the pointer.

Drop-off does not log, retain, or transmit those events. It does not monitor keyboard events.

During a drag, Drop-off inspects the system drag pasteboard only to determine whether it contains local file URLs, legacy file paths, file promises, media representations, or web URLs. It does not provide clipboard history and does not inspect the general clipboard outside this drag-handling path.

## Files and temporary copies

For ordinary files and folders, a shelf keeps local file URLs, file-reference URLs, and bookmark data in memory so items can remain usable after many local moves or renames. Drop-off uses local Quick Look and Finder icons for previews. Shelf state is not restored after quitting.

Fresh screenshots and file promises may disappear when their source drag ends. Drop-off therefore copies those items into a shelf-owned directory under the macOS temporary directory. Moving a temporary item between shelves creates an independent copy so closing one shelf cannot delete another shelf's item.

Shelf-owned temporary files are removed when the shelf is cleared or closed and when Drop-off quits normally. If Drop-off or macOS exits unexpectedly, a later Drop-off session removes only marker-validated shelf directories that are at least 24 hours old and whose owning process is no longer running. It does not delete unmarked directories, live sessions, or paths outside Drop-off's shelf root.

Web links are kept only in memory as URLs. Drop-off does not open, preview, request, or upload their contents; it places the same URL back on the drag pasteboard when you drag the link out.

## User controls

You can remove temporary content immediately by choosing **Clear**, closing its shelf, choosing **Close All Shelves**, or quitting Drop-off. Launch at Login is off by default for new users and can be explicitly enabled or disabled from the menu-bar menu. macOS may require approval in **System Settings → General → Login Items**.

Because Drop-off has no network service or account, there is no server-side personal data to export or delete.
