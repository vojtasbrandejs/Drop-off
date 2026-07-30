#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MINIMUM_TEST_COUNT="${DROPOFF_MIN_TEST_COUNT:-68}"
LIST_OUTPUT="$(mktemp -t dropoff-test-list.XXXXXX)"
trap 'rm -f "$LIST_OUTPUT"' EXIT

cd "$ROOT"
if ! swift test list >"$LIST_OUTPUT"; then
    echo "error: Swift Testing discovery failed." >&2
    echo "Install/select full Xcode with a Swift Testing runtime, then retry." >&2
    exit 1
fi

DISCOVERED_TEST_COUNT="$({
    /usr/bin/awk '
        /^DropOffTests[.\/][[:alnum:]_]/ { count += 1 }
        END { print count + 0 }
    ' "$LIST_OUTPUT"
})"
if (( DISCOVERED_TEST_COUNT < MINIMUM_TEST_COUNT )); then
    echo "error: discovered $DISCOVERED_TEST_COUNT Swift tests; expected at least $MINIMUM_TEST_COUNT." >&2
    echo "Command Line Tools can compile these tests while silently running zero." >&2
    echo "Select full Xcode to run the suite. Meanwhile, run ./scripts/run-checks.sh for standalone coverage." >&2
    exit 1
fi

echo "Discovered $DISCOVERED_TEST_COUNT Swift tests (minimum: $MINIMUM_TEST_COUNT)."
swift test
