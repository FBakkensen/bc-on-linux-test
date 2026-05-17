#!/usr/bin/env bash
set -euo pipefail

# Pull the Transfer LT extract from the running BC instance and land it as
# CSV for the planning-optimizer Python package to consume. Reads the API
# Query exposed by the production app at
# /api/fbakkensen/planningOptimizer/v1.0/transferLT (port 7052), paginates
# via @odata.nextLink, maps camelCase keys to the snake_case schema
# planning-optimizer/extracts/bc_files.read_transfer_lt expects, and
# writes .build/extracts/transfer-lt.csv.
#
# Long-format extract — one row per ILE Transfer entry. Python pairs
# `quantity<0` (source) with `quantity>0` (destination) by (Document No.,
# Item, Variant) per ADR 0006. Unmatched in-flight transfers are excluded
# at parse time.
#
# Requires the BC stack to be running and the Bc Linux Smoke app published.
#
# Env overrides:
#   BC_API_BASE_URL     default http://localhost:7052/BC
#   BC_AUTH             default BCRUNNER:Admin123!
#   BC_COMPANY_NAME     default "CRONUS International Ltd."
#   BC_EXTRACT_OUTPUT   default <repo>/.build/extracts/transfer-lt.csv

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 "$ROOT_DIR/scripts/_extract_transfer_lt.py" "$@"
