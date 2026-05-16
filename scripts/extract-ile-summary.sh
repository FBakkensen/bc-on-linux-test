#!/usr/bin/env bash
set -euo pipefail

# Pull the Item Ledger Summary extract from the running BC instance and land
# it as CSV for the planning-optimizer Python package to consume. Reads the
# API Query exposed by the production app at
# /api/fbakkensen/planningOptimizer/v1.0/itemLedgerSummaries (port 7052),
# paginates via @odata.nextLink, maps camelCase keys to the snake_case
# schema planning-optimizer/extracts/bc_files.read_ile_summary expects, and
# writes .build/extracts/ile-summary.csv.
#
# Requires the BC stack to be running and the Bc Linux Smoke app published.
#
# Env overrides:
#   BC_API_BASE_URL     default http://localhost:7052/BC
#   BC_AUTH             default BCRUNNER:Admin123!
#   BC_COMPANY_NAME     default "CRONUS International Ltd."
#   BC_EXTRACT_OUTPUT   default <repo>/.build/extracts/ile-summary.csv

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 "$ROOT_DIR/scripts/_extract_ile_summary.py" "$@"
