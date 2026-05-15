#!/usr/bin/env bash
set -euo pipefail

# Pull Microsoft symbol packages into the shared .alpackages/ at the repo
# root so AL projects can compile against the BC test framework.
#
# Requires the BC dev endpoint to be reachable (cd bc-linux && docker
# compose up -d). Downloads the six apps every AL project in this repo
# depends on either directly or transitively: System, System Application,
# Business Foundation, Base Application, Application, Library Assert.
#
# Run once after each fresh BC stack boot, then call ./scripts/compile.sh
# or any of the test-*.sh scripts.
#
# Env overrides: BC_DEV_URL, BC_AUTH.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEV_URL="${BC_DEV_URL:-http://localhost:7049/BC/dev}"
AUTH="${BC_AUTH:-BCRUNNER:Admin123!}"
TARGETS=(
    "$ROOT_DIR/.alpackages"
)
APPS=(
    "System"
    "System Application"
    "Business Foundation"
    "Base Application"
    "Application"
    "Library Assert"
)

urlencode() {
    python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$1"
}

for target in "${TARGETS[@]}"; do
    mkdir -p "$target"
    for app in "${APPS[@]}"; do
        encoded_name="$(urlencode "$app")"
        echo "Downloading $app into ${target#$ROOT_DIR/}"
        curl -sf -u "$AUTH" \
            "${DEV_URL}/packages?publisher=Microsoft&appName=${encoded_name}&appVersion=0.0.0.0" \
            -o "$target/${app}.app"
    done
done
