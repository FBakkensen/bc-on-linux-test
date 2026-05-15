#!/usr/bin/env bash
set -euo pipefail

# AL mutation testing (BusinessCentral.AL.Mutations).
#
# Mutates app/src/logic (pure-logic codeunits with stub-based fast-test
# coverage in /test/). app/src/seams (BC-coupled glue) is passed as --stubs:
# compiled into the test graph, not mutated. Output lands in .build/mutation/
# (mutations.json + report.md).
#
# Requires a clean git working tree — al-mutate restores mutants via
# `git checkout` and aborts on dirty trees to avoid clobbering uncommitted
# work. Stash or commit first.
#
# al-mutate currently has upstream issues that limit its usefulness; track
# the project's notes for current status.
#
# Usage:
#   ./scripts/test-mutation.sh
#   ./scripts/test-mutation.sh --max 20 --timeout 15
#   ./scripts/test-mutation.sh --operators ops.json --silent
#
# Extra al-mutate flags pass through.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
MUTATION_DIR="$BUILD_DIR/mutation"
LOG_PATH="$MUTATION_DIR/mutations.json"

mkdir -p "$MUTATION_DIR"

cd "$MUTATION_DIR"
exec dotnet al-mutate run \
    "$ROOT_DIR/app/src/logic" \
    --stubs "$ROOT_DIR/app/src/seams" \
    --tests "$ROOT_DIR/test/src" \
    --log "$LOG_PATH" \
    "$@"
