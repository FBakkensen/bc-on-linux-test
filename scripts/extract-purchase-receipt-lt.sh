#!/usr/bin/env bash
set -euo pipefail

# Pull the Purchase Receipt LT extract from the running BC instance and
# land it as CSV for the planning-optimizer Python package to consume.
# Reads the API Query exposed by the production app at
# /api/fbakkensen/planningOptimizer/v1.0/purchaseReceiptLT (port 7052),
# paginates via @odata.nextLink, maps camelCase keys to the snake_case
# schema planning-optimizer/extracts/bc_files.read_purchase_receipt_lt
# expects, and writes .build/extracts/purchase-receipt-lt.csv.
#
# Drop-shipments and special orders are excluded server-side by the AL
# Query. Rows with a blank `expected_receipt_date` cell are intentional
# — they mean the source PO carried no Expected Receipt Date at creation
# time (or the PO has since been deleted).
#
# Requires the BC stack to be running and the Bc Linux Smoke app published.
#
# Env overrides:
#   BC_API_BASE_URL     default http://localhost:7052/BC
#   BC_AUTH             default BCRUNNER:Admin123!
#   BC_COMPANY_NAME     default "CRONUS International Ltd."
#   BC_EXTRACT_OUTPUT   default <repo>/.build/extracts/purchase-receipt-lt.csv

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 "$ROOT_DIR/scripts/_extract_purchase_receipt_lt.py" "$@"
