"""Transfer LT OData → CSV extract.

Driven by scripts/extract-transfer-lt.sh. Thin orchestrator: pulls rows via
planning-optimizer's `extracts.bc_api` seam (per ADR 0009), then writes them
as CSV for planning-optimizer/extracts/bc_files.read_transfer_lt to consume.

Long-format extract — one row per ILE Transfer entry. The Python parser
pairs `quantity<0` (source) with `quantity>0` (destination) rows by
(document_no, item_no, variant_code) per ADR 0006.
"""

import csv
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "planning-optimizer"))

from extracts.bc_api import (  # noqa: E402
    API_PATH,
    TRANSFER_LT_COLUMNS,
    BcApiConfig,
    JsonRow,
    fetch_transfer_lt,
)

DEFAULT_OUTPUT = ROOT / ".build" / "extracts" / "transfer-lt.csv"
OUTPUT_FILE = Path(os.environ.get("BC_EXTRACT_OUTPUT", str(DEFAULT_OUTPUT)))


def _write_csv(rows: list[JsonRow]) -> None:
    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT_FILE.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh, lineterminator="\n")
        writer.writerow(TRANSFER_LT_COLUMNS)
        for row in rows:
            writer.writerow([row[col] for col in TRANSFER_LT_COLUMNS])


def _validate_output() -> None:
    if not OUTPUT_FILE.exists() or OUTPUT_FILE.stat().st_size == 0:
        sys.exit(f"ERROR: {OUTPUT_FILE} is missing or empty")
    with OUTPUT_FILE.open(encoding="utf-8") as fh:
        header = fh.readline().rstrip("\n")
    expected_header = ",".join(TRANSFER_LT_COLUMNS)
    if header != expected_header:
        sys.exit(f"ERROR: header mismatch.\n  Expected: {expected_header}\n  Got:      {header}")


def main() -> int:
    config = BcApiConfig.from_env()
    print(f"Fetching transferLT from {config.base_url}{API_PATH} for {config.company_name}...")
    rows = fetch_transfer_lt(config)
    print(f"Writing {OUTPUT_FILE} ({len(rows)} rows)...")
    _write_csv(rows)
    _validate_output()
    print(f"✓ Extract landed at {OUTPUT_FILE} ({len(rows)} data rows).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
