"""Item Ledger Summary OData → CSV extract.

Driven by scripts/extract-ile-summary.sh. Hits the API Query that the
production app exposes, paginates, and lands a CSV that matches the schema
planning-optimizer/extracts/bc_files.read_ile_summary consumes.
"""

import base64
import csv
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUTPUT = ROOT / ".build" / "extracts" / "ile-summary.csv"

API_BASE_URL = os.environ.get("BC_API_BASE_URL", "http://localhost:7052/BC")
AUTH = os.environ.get("BC_AUTH", "BCRUNNER:Admin123!")
COMPANY_NAME = os.environ.get("BC_COMPANY_NAME", "CRONUS International Ltd.")
OUTPUT_FILE = Path(os.environ.get("BC_EXTRACT_OUTPUT", str(DEFAULT_OUTPUT)))

CAMEL_TO_SNAKE = {
    "itemNo": "item_no",
    "variantCode": "variant_code",
    "locationCode": "location_code",
    "postingDate": "posting_date",
    "quantity": "quantity",
}
CSV_COLUMNS = list(CAMEL_TO_SNAKE.values())
API_PATH = "/api/fbakkensen/planningOptimizer/v1.0"


def _auth_header() -> str:
    token = base64.b64encode(AUTH.encode("utf-8")).decode("ascii")
    return f"Basic {token}"


def _get_json(url: str) -> dict:
    req = urllib.request.Request(url, headers={"Authorization": _auth_header()})
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        sys.stderr.write(f"HTTP {exc.code} on {url}\n{body}\n")
        sys.exit(1)


def _resolve_company_id() -> str:
    data = _get_json(f"{API_BASE_URL}{API_PATH}/companies")
    for company in data["value"]:
        if company["name"] == COMPANY_NAME:
            return company["id"]
    sys.exit(f"Company not found: {COMPANY_NAME}")


def _fetch_all_rows(company_id: str) -> list[dict]:
    url = f"{API_BASE_URL}{API_PATH}/companies({company_id})/itemLedgerSummaries"
    rows: list[dict] = []
    while url:
        data = _get_json(url)
        rows.extend(data["value"])
        url = data.get("@odata.nextLink", "")
    return rows


def _write_csv(rows: list[dict]) -> None:
    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT_FILE.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh, lineterminator="\n")
        writer.writerow(CSV_COLUMNS)
        for row in rows:
            writer.writerow([row[camel] for camel in CAMEL_TO_SNAKE])


def main() -> int:
    print(f"Resolving company id for {COMPANY_NAME}...")
    company_id = _resolve_company_id()

    print(f"Fetching itemLedgerSummaries from {API_BASE_URL}{API_PATH}...")
    rows = _fetch_all_rows(company_id)

    print(f"Writing {OUTPUT_FILE} ({len(rows)} rows)...")
    _write_csv(rows)

    if not OUTPUT_FILE.exists() or OUTPUT_FILE.stat().st_size == 0:
        sys.exit(f"ERROR: {OUTPUT_FILE} is missing or empty")

    with OUTPUT_FILE.open(encoding="utf-8") as fh:
        header = fh.readline().rstrip("\n")
    expected_header = ",".join(CSV_COLUMNS)
    if header != expected_header:
        sys.exit(
            f"ERROR: header mismatch.\n  Expected: {expected_header}\n  Got:      {header}"
        )

    print(f"✓ Extract landed at {OUTPUT_FILE} ({len(rows)} data rows).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
