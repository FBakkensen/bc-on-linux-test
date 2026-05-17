"""Shared orchestrator for all OData → CSV extract wrappers.

Each `scripts/_extract_*.py` resolves its (entity label, columns, fetcher,
default output path) and hands them to `run_extract`. The CSV writing and
the header-and-size validation live here so the BC-zero-date and column-
ordering conventions stay single-sourced.
"""

import csv
import os
import sys
from collections.abc import Callable
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# Make planning-optimizer's extracts/ importable without requiring the
# package to be pip-installed in the calling Python.
sys.path.insert(0, str(ROOT / "planning-optimizer"))

from extracts.bc_api import API_PATH, BcApiConfig, JsonRow  # noqa: E402

Fetcher = Callable[[BcApiConfig], list[JsonRow]]


def run_extract(
    *,
    entity_label: str,
    columns: list[str],
    fetcher: Fetcher,
    default_output: Path,
) -> int:
    """Run one extract end-to-end: fetch via OData, write CSV, validate."""
    output_file = Path(os.environ.get("BC_EXTRACT_OUTPUT", str(default_output)))
    config = BcApiConfig.from_env()
    print(f"Fetching {entity_label} from {config.base_url}{API_PATH} for {config.company_name}...")
    rows = fetcher(config)
    print(f"Writing {output_file} ({len(rows)} rows)...")
    _write_csv(output_file, columns, rows)
    _validate_output(output_file, columns)
    print(f"✓ Extract landed at {output_file} ({len(rows)} data rows).")
    return 0


def _write_csv(output_file: Path, columns: list[str], rows: list[JsonRow]) -> None:
    output_file.parent.mkdir(parents=True, exist_ok=True)
    with output_file.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh, lineterminator="\n")
        writer.writerow(columns)
        for row in rows:
            writer.writerow([row[col] for col in columns])


def _validate_output(output_file: Path, columns: list[str]) -> None:
    if not output_file.exists() or output_file.stat().st_size == 0:
        sys.exit(f"ERROR: {output_file} is missing or empty")
    with output_file.open(encoding="utf-8") as fh:
        header = fh.readline().rstrip("\n")
    expected_header = ",".join(columns)
    if header != expected_header:
        sys.exit(f"ERROR: header mismatch.\n  Expected: {expected_header}\n  Got:      {header}")
