#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
APP_PROJECT="$ROOT_DIR/app"
TEST_PROJECT="$ROOT_DIR/test"
APP_PACKAGE="$BUILD_DIR/BcLinuxSmoke.app"
TEST_PACKAGE="$BUILD_DIR/BcLinuxSmokeTests.app"
BASE_URL="${BC_BASE_URL:-http://localhost:7048/BC}"
DEV_URL="${BC_DEV_URL:-http://localhost:7049/BC/dev}"
AUTH="${BC_AUTH:-BCRUNNER:Admin123!}"
CODEUNIT_RANGE="${BC_TEST_CODEUNIT_RANGE:-50100..50149}"

mkdir -p "$BUILD_DIR" "$APP_PROJECT/.alpackages" "$TEST_PROJECT/.alpackages"

echo "Checking Business Central availability..."
curl -sf -u "$AUTH" "${BASE_URL}/ODataV4/Company" >/dev/null

echo "Compiling production app..."
al compile "/project:$APP_PROJECT" \
    "/packagecachepath:$APP_PROJECT/.alpackages" \
    "/out:$APP_PACKAGE"

cp "$APP_PACKAGE" "$TEST_PROJECT/.alpackages/"

echo "Compiling test app..."
al compile "/project:$TEST_PROJECT" \
    "/packagecachepath:$TEST_PROJECT/.alpackages" \
    "/out:$TEST_PACKAGE"

echo "Publishing production app..."
. "$ROOT_DIR/bc-linux/scripts/publish-app.sh"
bc_publish_app "$APP_PACKAGE" "$DEV_URL" "$AUTH"

echo "Running AL tests..."
"$ROOT_DIR/bc-linux/scripts/run-tests.sh" \
    --app "$TEST_PACKAGE" \
    --codeunit-range "$CODEUNIT_RANGE" \
    --base-url "$BASE_URL" \
    --dev-url "$DEV_URL" \
    --auth "$AUTH" \
    --junit-output "$BUILD_DIR/test-results.xml"

echo "Smoke test flow completed."
