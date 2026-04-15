#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEV_URL="${BC_DEV_URL:-http://localhost:7049/BC/dev}"
AUTH="${BC_AUTH:-BCRUNNER:Admin123!}"
TARGETS=(
    "$ROOT_DIR/app/.alpackages"
    "$ROOT_DIR/test/.alpackages"
)
APPS=(
    "System"
    "System Application"
    "Business Foundation"
    "Base Application"
    "Application"
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

echo "Symbol download complete."
