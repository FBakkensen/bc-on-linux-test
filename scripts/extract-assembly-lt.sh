#!/usr/bin/env bash
set -euo pipefail

# Pull the Assembly LT extract from the running BC instance and land it as
# CSV for the planning-optimizer Python package to consume. Reads the API
# Query exposed by the production app at
# /api/fbakkensen/planningOptimizer/v1.0/assemblyLT (port 7052), paginates
# via @odata.nextLink, maps camelCase keys to the snake_case schema
# planning-optimizer/extracts/bc_files.read_assembly_lt expects, and
# writes .build/extracts/assembly-lt.csv.
#
# One row per finished Posted Assembly Header. ADR 0006 defines
# `lead_time_days = posting_date − starting_date`.
#
# Requires the BC stack to be running and the Bc Linux Smoke app published.
#
# Env overrides:
#   BC_API_BASE_URL     default http://localhost:7052/BC
#   BC_AUTH             default BCRUNNER:Admin123!
#   BC_COMPANY_NAME     default "CRONUS International Ltd."
#   BC_EXTRACT_OUTPUT   default <repo>/.build/extracts/assembly-lt.csv

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 "$ROOT_DIR/scripts/_extract_assembly_lt.py" "$@"
