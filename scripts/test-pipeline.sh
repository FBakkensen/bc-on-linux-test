#!/usr/bin/env bash
set -euo pipefail

# End-to-end pipeline smoke per ADR 0013.
#
# Chain: seed → bc_api.py extract → planning-optimizer.run → recommendations
#
# Runs against the two seeded companies (PLANOPT-CO-A, PLANOPT-CO-B) and
# verifies each phase produced non-empty output. Tightens over time:
# - Phase 1 (now): every phase produces something; integration test asserts
#   shape against the seeded data.
# - Phase 2 (after issue #30): also POST recommendations back to BC and
#   verify rows landed in Planning Recommendation Hdr.
#
# Runs as a parallel CI job alongside test-integration.sh — they're
# intentionally orthogonal (AL integration tests synthesize their own data;
# the pipeline smoke runs against the seeded companies).
#
# Usage:
#   ./scripts/test-pipeline.sh           # default
#   ./scripts/test-pipeline.sh --no-seed # skip seed-company.sh (use existing data)
#
# Env overrides: BC_BASE_URL, BC_DEV_URL, BC_AUTH (same as seed-company.sh).

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
EXTRACTS_DIR="$BUILD_DIR/extracts"
RECS_DIR="$BUILD_DIR/recommendations"
BASE_URL="${BC_BASE_URL:-http://localhost:7048/BC}"
API_URL="${BC_API_URL:-http://localhost:7052/BC}"
AUTH="${BC_AUTH:-BCRUNNER:Admin123!}"
COMPANY_A="${COMPANY_A:-CRONUS-PLANOPT-A}"
COMPANY_B="${COMPANY_B:-CRONUS-PLANOPT-B}"
skip_seed=0
for arg in "$@"; do
    case "$arg" in
        --no-seed) skip_seed=1 ;;
        -h|--help) sed -n '6,25p' "$0"; exit 0 ;;
        *) echo "test-pipeline.sh: unknown argument '$arg'" >&2; exit 2 ;;
    esac
done

mkdir -p "$EXTRACTS_DIR" "$RECS_DIR"

if [ "$skip_seed" = "0" ]; then
    "$ROOT_DIR/scripts/seed-company.sh"
fi

extract_company() {
    local company="$1"
    local out="$EXTRACTS_DIR/$company"
    mkdir -p "$out"
    echo "Extracting $company → $out"
    BC_API_BASE_URL="$API_URL" \
    BC_AUTH="$AUTH" \
    BC_COMPANY_NAME="$company" \
        "$ROOT_DIR/.venv-python-check/bin/python3" -c "
import csv
import sys
from pathlib import Path
sys.path.insert(0, '$ROOT_DIR/planning-optimizer')
from extracts import bc_api

cfg = bc_api.BcApiConfig.from_env()
out = Path('$out')

def write(name, rows, columns):
    with (out / name).open('w', newline='') as fh:
        writer = csv.DictWriter(fh, fieldnames=columns)
        writer.writeheader()
        for r in rows:
            writer.writerow({k: r.get(k, '') for k in columns})
    print(f'  {name}: {len(rows)} rows')

write('ile_summary.csv', bc_api.fetch_item_ledger_summaries(cfg), bc_api.ILE_SUMMARY_COLUMNS)
write('purchase_lt.csv', bc_api.fetch_purchase_receipt_lt(cfg), bc_api.PURCHASE_RECEIPT_LT_COLUMNS)
write('open_sd.csv', bc_api.fetch_open_sd_events(cfg), bc_api.OPEN_SD_EVENT_COLUMNS)
"
}

run_optimizer() {
    local company="$1"
    local extract_dir="$EXTRACTS_DIR/$company"
    local recs_path="$RECS_DIR/${company}.json"
    echo "Optimizing $company → $recs_path"
    "$ROOT_DIR/.venv-python-check/bin/python3" -c "
import sys
from pathlib import Path
sys.path.insert(0, '$ROOT_DIR/planning-optimizer/src')
import bc_planning_optimizer
output = bc_planning_optimizer.run(Path('$extract_dir/ile_summary.csv'))
import shutil
shutil.copyfile(output, '$recs_path')
print(f'  → $recs_path')
"
    if [ ! -s "$recs_path" ]; then
        echo "test-pipeline.sh: $company produced empty recommendations" >&2
        exit 1
    fi
}

extract_company "$COMPANY_A"
extract_company "$COMPANY_B"
run_optimizer "$COMPANY_A"
run_optimizer "$COMPANY_B"

# Phase 1 assertion: every phase produced some output. Tighter assertions
# live in planning-optimizer/tests/integration_test_seeded_data.py.
for company in "$COMPANY_A" "$COMPANY_B"; do
    extract="$EXTRACTS_DIR/$company/ile_summary.csv"
    recs="$RECS_DIR/${company}.json"
    [ -s "$extract" ] || { echo "test-pipeline.sh: $extract is empty" >&2; exit 1; }
    [ -s "$recs" ]    || { echo "test-pipeline.sh: $recs is empty"    >&2; exit 1; }
done

echo "test-pipeline.sh: OK. Extracts in $EXTRACTS_DIR, recommendations in $RECS_DIR."
