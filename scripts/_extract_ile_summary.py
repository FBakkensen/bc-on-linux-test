"""Item Ledger Summary OData → CSV extract.

Driven by scripts/extract-ile-summary.sh. Thin orchestrator: pulls rows via
planning-optimizer's `extracts.bc_api` seam (the only BC-talking layer per
ADR 0009), then writes them as CSV at the agreed path for
planning-optimizer/extracts/bc_files.read_ile_summary to consume.
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
    ILE_SUMMARY_COLUMNS,
    BcApiConfig,
    JsonRow,
    fetch_item_ledger_summaries,
)

DEFAULT_OUTPUT = ROOT / ".build" / "extracts" / "ile-summary.csv"
OUTPUT_FILE = Path(os.environ.get("BC_EXTRACT_OUTPUT", str(DEFAULT_OUTPUT)))


def _write_csv(rows: list[JsonRow]) -> None:
    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT_FILE.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh, lineterminator="\n")
        writer.writerow(ILE_SUMMARY_COLUMNS)
        for row in rows:
            writer.writerow([row[col] for col in ILE_SUMMARY_COLUMNS])


def _validate_output() -> None:
    if not OUTPUT_FILE.exists() or OUTPUT_FILE.stat().st_size == 0:
        sys.exit(f"ERROR: {OUTPUT_FILE} is missing or empty")
    with OUTPUT_FILE.open(encoding="utf-8") as fh:
        header = fh.readline().rstrip("\n")
    expected_header = ",".join(ILE_SUMMARY_COLUMNS)
    if header != expected_header:
        sys.exit(f"ERROR: header mismatch.\n  Expected: {expected_header}\n  Got:      {header}")


def main() -> int:
    config = BcApiConfig.from_env()
    print(
        f"Fetching itemLedgerSummaries from {config.base_url}{API_PATH} "
        f"for {config.company_name}..."
    )
    rows = fetch_item_ledger_summaries(config)
    print(f"Writing {OUTPUT_FILE} ({len(rows)} rows)...")
    _write_csv(rows)
    _validate_output()
    print(f"✓ Extract landed at {OUTPUT_FILE} ({len(rows)} data rows).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
