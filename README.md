# Drop-off

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="packaging/AppIconDark.png">
    <source media="(prefers-color-scheme: light)" srcset="packaging/AppIconLight.png">
    <img src="packaging/AppIconLight.png" alt="Drop-off app icon" width="150">
  </picture>
</p>

<p align="center"><strong>A shelf that follows you. Shake a file in, paste anywhere.</strong></p>

<p align="center">
  <a href="#install"><strong>Install Drop-off for macOS</strong></a><br>
  <sub>One command · built locally · macOS 13+</sub>
</p>

<p align="center">
  <a href="https://github.com/vojtasbrandejs/Drop-off/releases/latest/download/drop-off-demo.mp4">
    <img src="https://github.com/vojtasbrandejs/Drop-off/releases/latest/download/drop-off-demo.gif" alt="Drop-off in action" width="760">
  </a>
</p>

Dragging a file across desktops while holding the cursor down is awkward. Saving a generated image to Downloads just to attach it somewhere is a step nobody wants.

Drop-off is copy and paste, except it holds more than one thing and comes with you.

Shake a file — an image, a folder, a zip, a video, or a link — and a shelf appears. It follows you between windows and Spaces, so you can open the conversation or folder you actually wanted first and paste afterwards.

Several shelves at once, several files in each. Keep a stack collapsed in the corner or open it and pick one item at a time.

Media dragged straight from Messages keeps its original advertised format. If a provider gives a file the wrong extension, Drop-off corrects the name from the actual PNG, JPEG, GIF, SVG, HEIC, MP4, or MOV contents before you drag it back out.

## Install

Open Terminal, paste this command, and press Return:

```sh
curl -fsSL https://raw.githubusercontent.com/vojtasbrandejs/Drop-off/v1.1.1/scripts/install.sh | bash
```

That is the entire installation. The command:

- downloads the pinned Drop-off source release from this repository,
- builds the app locally on your Mac,
- installs only `Drop-off.app` in Applications,
- removes the temporary source and build files,
- opens Drop-off in the menu bar.

No prebuilt executable is downloaded and the installer does not disable or bypass Gatekeeper. You can [read the installer](scripts/install.sh) before running it.

Drop-off requires macOS 13 Ventura or newer and Apple’s free Command Line Tools. If the tools are missing, macOS offers to install them; finish that installation and run the same command again. The resulting app works on both Apple Silicon and Intel Macs.

## Updating

Copy the current install command from this README again. It builds that release, closes the running copy, replaces it safely, and reopens Drop-off. It also removes the obsolete `Dropoff.app` name used by early development builds.

Your shelves are temporary, so there is no library or account to migrate.

## How it works

1. Start dragging one or more files or web links.
2. Shake the pointer quickly from side to side.
3. Drop the files on the shelf that appears.
4. Go where you were headed and drag the stack back out. Links are placed back on the pasteboard as normal URLs.

Click the item count to open a stack and choose files individually. The arrow collapses a shelf. The menu-bar icon creates a shelf manually, closes them all, and controls Launch at Login.

## Permissions

Drop-off does not require Accessibility, Screen Recording, Full Disk Access, or keyboard monitoring. It watches mouse drag events while running and handles only files you actively drag into a shelf.

Launch at Login is optional and off by default. If you enable it, macOS may ask you to approve Drop-off in **System Settings → General → Login Items**.

## Troubleshooting

- **No shelf appears:** make sure you are holding an actual file, folder, or web link, then shake the pointer quickly from side to side.
- **Drop-off is not in the Dock:** it is a menu-bar utility. Look for the tray icon at the top of the screen.
- **The Command Line Tools window appeared:** complete Apple’s free installation, then run the install command again.
- **The build stopped:** copy the complete Terminal output into a new issue so the failed step is visible.
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

## For contributors

Drop-off is native Swift and AppKit with no external dependencies.

```sh
git clone https://github.com/vojtasbrandejs/Drop-off.git
cd Drop-off
git config core.hooksPath .githooks
./scripts/run-tests.sh
./scripts/run-checks.sh
./scripts/build-app.sh
```

The tracked pre-push hook runs the complete Swift test suite and standalone checks. A failing check blocks the push.

## Project information

- [Privacy](PRIVACY.md)
- [Security policy](SECURITY.md)
- [Support](SUPPORT.md)
- [MIT License](LICENSE)
