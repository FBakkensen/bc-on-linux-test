#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
APP_PROJECT="$ROOT_DIR/app"
INTEGRATION_TEST_PROJECT="$ROOT_DIR/integration-test"
PACKAGE_CACHE="$ROOT_DIR/.alpackages"
APP_PACKAGE="$BUILD_DIR/BcLinuxSmoke.app"
INTEGRATION_TEST_PACKAGE="$BUILD_DIR/BcLinuxSmokeIntegrationTests.app"
BASE_URL="${BC_BASE_URL:-http://localhost:7048/BC}"
DEV_URL="${BC_DEV_URL:-http://localhost:7049/BC/dev}"
AUTH="${BC_AUTH:-BCRUNNER:Admin123!}"
CODEUNIT_RANGE="${BC_TEST_CODEUNIT_RANGE:-50150..50199}"

mkdir -p "$BUILD_DIR" "$PACKAGE_CACHE"

echo "Checking Business Central availability..."
curl -sf -u "$AUTH" "${BASE_URL}/ODataV4/Company" >/dev/null

echo "Compiling production app..."
al compile "/project:$APP_PROJECT" \
    "/packagecachepath:$PACKAGE_CACHE" \
    "/out:$APP_PACKAGE"

cp "$APP_PACKAGE" "$PACKAGE_CACHE/"

echo "Compiling integration-test app..."
al compile "/project:$INTEGRATION_TEST_PROJECT" \
    "/packagecachepath:$PACKAGE_CACHE" \
    "/out:$INTEGRATION_TEST_PACKAGE"

echo "Publishing production app..."
. "$ROOT_DIR/bc-linux/scripts/publish-app.sh"
bc_publish_app "$APP_PACKAGE" "$DEV_URL" "$AUTH"

echo "Running AL integration tests..."
"$ROOT_DIR/bc-linux/scripts/run-tests.sh" \
    --app "$INTEGRATION_TEST_PACKAGE" \
    --codeunit-range "$CODEUNIT_RANGE" \
    --base-url "$BASE_URL" \
    --dev-url "$DEV_URL" \
    --auth "$AUTH" \
    --junit-output "$BUILD_DIR/test-results.xml"

echo "Smoke test flow completed."
