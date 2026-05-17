"""Production LT OData → CSV extract.

Driven by scripts/extract-production-lt.sh. Thin orchestrator: pulls rows
via planning-optimizer's `extracts.bc_api` seam (the only BC-talking layer
per ADR 0009), then writes them as CSV at the agreed path for
planning-optimizer/extracts/bc_files.read_production_lt to consume.

Long-format extract — one row per (finished prod order, ILE entry).
Cancelled / scrapped prod orders are excluded server-side. The Python
parser derives `max(Output) − min(Consumption)` per ADR 0006 and falls
back to `Finishing Date − Starting Date` when no consumption ILE exists.
"""

import csv
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "planning-optimizer"))

from extracts.bc_api import (  # noqa: E402
    API_PATH,
    PRODUCTION_LT_COLUMNS,
    BcApiConfig,
    JsonRow,
    fetch_production_lt,
)

DEFAULT_OUTPUT = ROOT / ".build" / "extracts" / "production-lt.csv"
OUTPUT_FILE = Path(os.environ.get("BC_EXTRACT_OUTPUT", str(DEFAULT_OUTPUT)))


def _write_csv(rows: list[JsonRow]) -> None:
    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT_FILE.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh, lineterminator="\n")
        writer.writerow(PRODUCTION_LT_COLUMNS)
        for row in rows:
            writer.writerow([row[col] for col in PRODUCTION_LT_COLUMNS])


def _validate_output() -> None:
    if not OUTPUT_FILE.exists() or OUTPUT_FILE.stat().st_size == 0:
        sys.exit(f"ERROR: {OUTPUT_FILE} is missing or empty")
    with OUTPUT_FILE.open(encoding="utf-8") as fh:
        header = fh.readline().rstrip("\n")
    expected_header = ",".join(PRODUCTION_LT_COLUMNS)
    if header != expected_header:
        sys.exit(f"ERROR: header mismatch.\n  Expected: {expected_header}\n  Got:      {header}")


def main() -> int:
    config = BcApiConfig.from_env()
    print(
        f"Fetching productionLT from {config.base_url}{API_PATH} for {config.company_name}..."
    )
    rows = fetch_production_lt(config)
    print(f"Writing {OUTPUT_FILE} ({len(rows)} rows)...")
    _write_csv(rows)
    _validate_output()
    print(f"✓ Extract landed at {OUTPUT_FILE} ({len(rows)} data rows).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
