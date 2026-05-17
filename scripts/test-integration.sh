#!/usr/bin/env bash
set -euo pipefail

# Full BC-tier integration test flow.
#
# Verifies BC is reachable, compiles all three projects with analyzers (via
# ./scripts/compile.sh), publishes the production app to the dev endpoint,
# then publishes and runs the integration test app inside the running BC
# container via bc-linux/scripts/run-tests.sh (OData + WebSocket hybrid for
# TestPage support).
#
# Requires the BC stack to be running (cd bc-linux && docker compose up -d).
# Production codeunits live in 50000..50049; integration tests in 50150..50160
# plus 50163..50164 (AL Query suites: ILE Summary, Purchase Receipt LT) by
# default. 50161 is the stress-scale perf test, opt-in via
# BC_PERF_STRESS=1 per ADR 0004.
#
# Usage:
#   ./scripts/test-integration.sh
#   BC_TEST_CODEUNIT_RANGE=50150..50150 ./scripts/test-integration.sh
#   BC_PERF_STRESS=1 ./scripts/test-integration.sh
#
# Env overrides: BC_BASE_URL, BC_DEV_URL, BC_AUTH, BC_TEST_CODEUNIT_RANGE,
# BC_PERF_STRESS.
#
# Output: .build/test-integration.xml (JUnit).

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
APP_PACKAGE="$BUILD_DIR/BcLinuxSmoke.app"
INTEGRATION_TEST_PACKAGE="$BUILD_DIR/BcLinuxSmokeIntegrationTests.app"
JUNIT_OUTPUT="$BUILD_DIR/test-integration.xml"

BASE_URL="${BC_BASE_URL:-http://localhost:7048/BC}"
DEV_URL="${BC_DEV_URL:-http://localhost:7049/BC/dev}"
AUTH="${BC_AUTH:-BCRUNNER:Admin123!}"
if [[ "${BC_PERF_STRESS:-0}" == "1" ]]; then
    DEFAULT_RANGE="50150..50161|50163..50164"
else
    DEFAULT_RANGE="50150..50160|50163..50164"
fi
CODEUNIT_RANGE="${BC_TEST_CODEUNIT_RANGE:-$DEFAULT_RANGE}"

mkdir -p "$BUILD_DIR"

echo "Checking Business Central availability..."
curl -sf -u "$AUTH" "${BASE_URL}/ODataV4/Company" >/dev/null

"$ROOT_DIR/scripts/compile.sh"

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
    --junit-output "$JUNIT_OUTPUT"
