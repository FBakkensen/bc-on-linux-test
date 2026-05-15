#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/mutation"
LOG_PATH="$BUILD_DIR/mutations.json"

mkdir -p "$BUILD_DIR"

# AL mutation testing (BusinessCentral.AL.Mutations).
# Mutates app/src/logic (pure-logic codeunits with stub-based fast-test coverage
# in test/src). app/src/seams (BC-coupled glue) is passed as --stubs: compiled
# into the test graph, not mutated. Output (mutations.json + report.md) lands
# in .build/mutation/.
#
# Requires a clean git working tree — al-mutate restores mutants via
# `git checkout` and aborts on dirty trees to avoid clobbering uncommitted work.
# Stash or commit first.
#
# Extra al-mutate flags can be appended: --max, --operators, --silent, --timeout, ...
cd "$BUILD_DIR"
exec dotnet al-mutate run \
    "$ROOT_DIR/app/src/logic" \
    --stubs "$ROOT_DIR/app/src/seams" \
    --tests "$ROOT_DIR/test/src" \
    --log "$LOG_PATH" \
    "$@"
