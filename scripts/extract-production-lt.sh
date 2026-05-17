#!/usr/bin/env bash
set -euo pipefail

# Pull the Production LT extract from the running BC instance and land it
# as CSV for the planning-optimizer Python package to consume. Reads the
# API Query exposed by the production app at
# /api/fbakkensen/planningOptimizer/v1.0/productionLT (port 7052),
# paginates via @odata.nextLink, maps camelCase keys to the snake_case
# schema planning-optimizer/extracts/bc_files.read_production_lt expects,
# and writes .build/extracts/production-lt.csv.
#
# Long-format extract — one row per (finished prod order, ILE entry).
# Cancelled / scrapped prod orders are excluded server-side. Python
# derives `max(Output) − min(Consumption)` per ADR 0006 and falls back
# to header dates when no consumption ILE exists.
#
# Requires the BC stack to be running and the Bc Linux Smoke app published.
#
# Env overrides:
#   BC_API_BASE_URL     default http://localhost:7052/BC
#   BC_AUTH             default BCRUNNER:Admin123!
#   BC_COMPANY_NAME     default "CRONUS International Ltd."
#   BC_EXTRACT_OUTPUT   default <repo>/.build/extracts/production-lt.csv

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 "$ROOT_DIR/scripts/_extract_production_lt.py" "$@"
