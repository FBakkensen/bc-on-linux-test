#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
PACKAGE_CACHE="$ROOT_DIR/.alpackages"
JUNIT_OUTPUT="$BUILD_DIR/al-runner-results.xml"

mkdir -p "$BUILD_DIR"

# Transpile-based AL unit test loop (BusinessCentral.AL.Runner).
# Runs out-of-process against app/src + test/src — no BC container needed.
# Use ./scripts/smoke.sh for the full BC-tier test path (covers TestPage,
# real DB state, permissions, etc.) when a feature exceeds al-runner's reach.
#
# Extra al-runner flags can be appended: --run, --coverage, --verbose, etc.
exec al-runner \
    --packages "$PACKAGE_CACHE" \
    --output-junit "$JUNIT_OUTPUT" \
    "$ROOT_DIR/app/src" \
    "$ROOT_DIR/test/src" \
    "$@"
