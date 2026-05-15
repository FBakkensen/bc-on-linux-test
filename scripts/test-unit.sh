#!/usr/bin/env bash
set -euo pipefail

# Fast unit-test loop — transpile-based, no BC container required.
#
# Compiles app + test with full analyzers (via ./scripts/compile.sh) so a
# fresh code-analyzer pass guards every test run, then executes the tests in
# /test/ out-of-process via BusinessCentral.AL.Runner against source.
#
# Use ./scripts/test-integration.sh for the full BC-tier path (TestPage
# choreography, real DB state, permissions, lifecycle integration events
# beyond --init-events) when a feature exceeds al-runner's reach.
#
# Usage:
#   ./scripts/test-unit.sh                     # compile + run all unit tests
#   ./scripts/test-unit.sh --run MyProc        # filter to a single procedure
#   ./scripts/test-unit.sh --coverage          # extra al-runner flags pass through
#
# Output: .build/test-unit.xml (JUnit).

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
PACKAGE_CACHE="$ROOT_DIR/.alpackages"
JUNIT_OUTPUT="$BUILD_DIR/test-unit.xml"

mkdir -p "$BUILD_DIR"

"$ROOT_DIR/scripts/compile.sh" app test

echo "Running unit tests..."
exec al-runner \
    --packages "$PACKAGE_CACHE" \
    --output-junit "$JUNIT_OUTPUT" \
    "$ROOT_DIR/app/src" \
    "$ROOT_DIR/test/src" \
    "$@"
