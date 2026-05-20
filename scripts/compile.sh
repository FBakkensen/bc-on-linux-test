#!/usr/bin/env bash
set -euo pipefail

# Compile AL projects with full analyzer set via al-compile (al-smart-compile).
#
# Default: compiles all three projects (app, test, integration-test) and stages
# the production app's .app into .alpackages/ so dependents can resolve the
# "Bc Linux Smoke" symbol. With no BC container required — runs entirely
# against the local symbol cache.
#
# Usage:
#   ./scripts/compile.sh                       # all four projects
#   ./scripts/compile.sh app test              # subset (app auto-included
#                                              # when test/integration-test/
#                                              # seed are requested)
#
# Outputs land in .build/:
#   BcLinuxSmoke.app
#   BcLinuxSmokeTests.app
#   BcLinuxSmokeIntegrationTests.app
#   BcLinuxSmokePlanningSeed.app
#
# Called standalone for inner-loop lint, by ./scripts/test-unit.sh before
# unit tests, and by ./scripts/test-integration.sh before container tests.
# The seed project is built but not used by either — it's invoked
# separately via ./scripts/seed-company.sh (ADR 0013).

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
PACKAGE_CACHE="$ROOT_DIR/.alpackages"

declare -A OUTPUT_NAMES=(
    [app]="BcLinuxSmoke.app"
    [test]="BcLinuxSmokeTests.app"
    [integration-test]="BcLinuxSmokeIntegrationTests.app"
    [seed]="BcLinuxSmokePlanningSeed.app"
)
ALL_PROJECTS=(app test integration-test seed)

if [[ $# -eq 0 ]]; then
    requested=("${ALL_PROJECTS[@]}")
else
    requested=("$@")
fi

needs_app=0
for proj in "${requested[@]}"; do
    case "$proj" in
        app) ;;
        test|integration-test|seed) needs_app=1 ;;
        *) echo "compile.sh: unknown project '$proj' (expected: app, test, integration-test, seed)" >&2; exit 2 ;;
    esac
done

declare -A seen=()
order=()
if (( needs_app )); then
    order+=("app")
    seen[app]=1
fi
for proj in "${requested[@]}"; do
    if [[ -z "${seen[$proj]:-}" ]]; then
        order+=("$proj")
        seen[$proj]=1
    fi
done

mkdir -p "$BUILD_DIR" "$PACKAGE_CACHE"

compile_project() {
    local proj="$1"
    local target="$BUILD_DIR/${OUTPUT_NAMES[$proj]}"

    echo "Compiling $proj..."
    pushd "$ROOT_DIR/$proj" >/dev/null
    rm -f -- *.app
    al-compile
    local produced
    produced=$(ls -- *.app 2>/dev/null | head -n1 || true)
    if [[ -z "$produced" ]]; then
        echo "compile.sh: $proj produced no .app" >&2
        popd >/dev/null
        exit 1
    fi
    mv -- "$produced" "$target"
    popd >/dev/null

    if [[ "$proj" == "app" ]]; then
        cp "$target" "$PACKAGE_CACHE/"
    fi
}

for proj in "${order[@]}"; do
    compile_project "$proj"
done
