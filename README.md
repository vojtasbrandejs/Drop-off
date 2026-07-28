# Drop-off

<p align="center"><strong>A shelf that follows you. Shake a file in, paste anywhere.</strong></p>

<p align="center">
  <a href="https://github.com/vojtasbrandejs/Drop-off/releases/latest/download/Drop-off.dmg"><strong>Download Drop-off for macOS</strong></a><br>
  <sub>macOS 13+ · Apple Silicon and Intel</sub>
</p>

<p align="center">
  <a href="https://github.com/vojtasbrandejs/Drop-off/releases/latest/download/drop-off-demo.mp4">
    <img src="https://github.com/vojtasbrandejs/Drop-off/releases/latest/download/drop-off-demo.gif" alt="Drop-off in action" width="760">
  </a>
</p>

Dragging a file across desktops while holding the cursor down is awkward. Saving a generated image to Downloads just to attach it somewhere is a step nobody wants.

Drop-off is copy and paste, except it holds more than one thing and comes with you.

Shake a file — an image, a folder, a zip, a video — and a shelf appears. It follows you between windows and Spaces, so you can open the conversation or folder you actually wanted first and paste afterwards.

Several shelves at once, several files in each. Keep a stack collapsed in the corner or open it and pick one item at a time.

## Download

### Standard install

1. **[Download Drop-off.dmg](https://github.com/vojtasbrandejs/Drop-off/releases/latest/download/Drop-off.dmg)**.
2. Open it and drag `Drop-off.app` onto the Applications shortcut.
3. On the first launch, right-click Drop-off and choose **Open**.
4. The tray icon appears in your menu bar.

This downloads only the app. Do not use GitHub’s green **Code → Download ZIP** button — that button downloads the repository documents, not the app.

### Terminal install

Or download, verify, install, and open the latest release with one command:

```bash
curl -fsSL https://raw.githubusercontent.com/vojtasbrandejs/Drop-off/main/scripts/install.sh | bash
```

The installer fetches only the release app and its SHA-256 checksum. It does not clone the repository.
You can [inspect the installer](scripts/install.sh) before running it.

Prefer a ZIP? **[Download only Drop-off.app.zip](https://github.com/vojtasbrandejs/Drop-off/releases/latest/download/Drop-off.app.zip)**.

The current build is signed locally but not yet Apple-notarized, so macOS shows an unidentified-developer warning once. Only download Drop-off from this repository and verify the attached SHA-256 checksum.

Requires macOS 13 Ventura or newer. The same download works on Apple Silicon and Intel Macs.

## Updating

Quit Drop-off, then use the DMG or Terminal command above again. Your shelves are temporary, so there is no library or account to migrate.

## How it works

1. Start dragging one or more files.
2. Shake the pointer quickly from side to side.
3. Drop the files on the shelf that appears.
4. Go where you were headed and drag the stack back out.

Click the item count to open a stack and choose files individually. The arrow collapses a shelf. The menu-bar icon creates a shelf manually, closes them all, and controls Launch at Login.

## Permissions

Drop-off does not require Accessibility, Screen Recording, Full Disk Access, or keyboard monitoring. It watches mouse drag events while running and handles only files you actively drag into a shelf.

Launch at Login is optional and off by default. If you enable it, macOS may ask you to approve Drop-off in **System Settings → General → Login Items**.

## Troubleshooting

- **No shelf appears:** make sure you are holding an actual file or folder, then shake the pointer quickly from side to side.
- **Drop-off is not in the Dock:** it is a menu-bar utility. Look for the tray icon at the top of the screen.
- **macOS blocks the first launch:** right-click `Drop-off.app` and choose **Open**.
- **Launch at Login needs approval:** open **System Settings → General → Login Items** and allow Drop-off.

For bugs and questions, see [Support](SUPPORT.md).

## Uninstall

1. Open the Drop-off menu-bar menu and turn off **Launch at Login** if it is enabled.
2. Choose **Close All Shelves**, then **Quit**.
3. Move `Drop-off.app` from Applications to the Trash.

That is all. Drop-off installs no browser extension, launch daemon, account, database, or Application Support data. Temporary shelf copies are removed when their shelf closes or the app quits. If you deleted the app before disabling Launch at Login, remove it from **System Settings → General → Login Items**.

## Local by design

Your normal files stay where they are. Drop-off remembers their locations and never uploads them. Fresh screenshots and other temporary drag items are copied into a local temporary folder and cleaned up with their shelf.

No account. No analytics. No database. No network connection. See the plain-language [privacy details](PRIVACY.md).

## Project information

- [Privacy](PRIVACY.md)
- [Security policy](SECURITY.md)
- [Support](SUPPORT.md)
- [MIT License](LICENSE)
