"""Purchase Receipt LT OData → CSV extract.

Driven by scripts/extract-purchase-receipt-lt.sh. Thin orchestrator: pulls
rows via planning-optimizer's `extracts.bc_api` seam (the only BC-talking
layer per ADR 0009), then writes them as CSV at the agreed path for
planning-optimizer/extracts/bc_files.read_purchase_receipt_lt to consume.

Drop-shipments and special orders are excluded server-side by the AL
Query (per ADR 0006). The `expected_receipt_date` cell may be blank when
the source PO has been deleted or never carried an expected date at
creation time — that's a real signal, not bad data.
"""

import csv
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# Make planning-optimizer's extracts/ importable without requiring the
# package to be pip-installed in the calling Python.
sys.path.insert(0, str(ROOT / "planning-optimizer"))

from extracts.bc_api import (  # noqa: E402
    API_PATH,
    PURCHASE_RECEIPT_LT_COLUMNS,
    BcApiConfig,
    JsonRow,
    fetch_purchase_receipt_lt,
)

DEFAULT_OUTPUT = ROOT / ".build" / "extracts" / "purchase-receipt-lt.csv"
OUTPUT_FILE = Path(os.environ.get("BC_EXTRACT_OUTPUT", str(DEFAULT_OUTPUT)))


def _write_csv(rows: list[JsonRow]) -> None:
    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT_FILE.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh, lineterminator="\n")
        writer.writerow(PURCHASE_RECEIPT_LT_COLUMNS)
        for row in rows:
            writer.writerow([row[col] for col in PURCHASE_RECEIPT_LT_COLUMNS])


def _validate_output() -> None:
    if not OUTPUT_FILE.exists() or OUTPUT_FILE.stat().st_size == 0:
        sys.exit(f"ERROR: {OUTPUT_FILE} is missing or empty")
    with OUTPUT_FILE.open(encoding="utf-8") as fh:
        header = fh.readline().rstrip("\n")
    expected_header = ",".join(PURCHASE_RECEIPT_LT_COLUMNS)
    if header != expected_header:
        sys.exit(f"ERROR: header mismatch.\n  Expected: {expected_header}\n  Got:      {header}")


def main() -> int:
    config = BcApiConfig.from_env()
    print(
        f"Fetching purchaseReceiptLT from {config.base_url}{API_PATH} for {config.company_name}..."
    )
    rows = fetch_purchase_receipt_lt(config)
    print(f"Writing {OUTPUT_FILE} ({len(rows)} rows)...")
    _write_csv(rows)
    _validate_output()
    print(f"✓ Extract landed at {OUTPUT_FILE} ({len(rows)} data rows).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
