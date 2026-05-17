#!/usr/bin/env bash
set -euo pipefail

# Pull the open Supply & Demand event stream from the running BC instance
# and land it as CSV for the planning-optimizer Python package to consume.
# Reads the 10 Open SD AL Queries exposed by the production app under
# /api/fbakkensen/planningOptimizer/v1.0/openSD* (port 7052), paginates
# each via @odata.nextLink, projects every per-source row into the
# unified (item_no, variant_code, location_code, event_date,
# signed_quantity, source_kind) shape, and writes
# .build/extracts/open-sd-events.csv.
#
# Seeds the Fidelity-B simulator's initial state per ADR 0007. ADR 0001
# inclusion / exclusion lives server-side in each Query's
# DataItemTableFilter (no policy re-encoding); deviation #3 (Job Planning
# double-count for Both Budget and Billable) is applied Python-side
# because a single SELECT can't emit a row twice.
#
# Requires the BC stack to be running and the Bc Linux Smoke app published.
#
# Env overrides:
#   BC_API_BASE_URL     default http://localhost:7052/BC
#   BC_AUTH             default BCRUNNER:Admin123!
#   BC_COMPANY_NAME     default "CRONUS International Ltd."
#   BC_EXTRACT_OUTPUT   default <repo>/.build/extracts/open-sd-events.csv

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 "$ROOT_DIR/scripts/_extract_open_sd.py" "$@"
