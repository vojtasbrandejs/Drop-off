#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="$ROOT/.build/DropOffChecks"
ARCH="$(uname -m)"

cd "$ROOT"
mkdir -p "$(dirname "$OUTPUT")"
swiftc \
    -parse-as-library \
    -target "${ARCH}-apple-macosx13.0" \
    -o "$OUTPUT" \
    Checks/DropOffChecks.swift \
    Sources/DropOff/DragActivationState.swift \
    Sources/DropOff/MediaFileFormat.swift \
    Sources/DropOff/FileDragPasteboard.swift \
    Sources/DropOff/ShakeGestureRecognizer.swift \
    Sources/DropOff/SingleInstanceLock.swift \
    Sources/DropOff/ShelfPlacement.swift \
    Sources/DropOff/ThumbnailProvider.swift \
    Sources/DropOff/ShelfItem.swift \
    Sources/DropOff/ShelfDropPasteboard.swift \
    Sources/DropOff/ShelfTransientFileStore.swift \
    Sources/DropOff/ShelfModel.swift

"$OUTPUT"
