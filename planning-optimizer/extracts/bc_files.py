"""File-based bulk-read seam.

In sandbox the file lands on the local filesystem (CSV dump from an AL
Query). In production the file lands in Azure Blob Storage — swapping the
backend is a one-call change at this seam. The first real extract is the
Item Ledger Summary, grouped server-side to (item, variant, location,
posting_date, signed_quantity) per ADR 0006 + ADR 0009.
"""

from pathlib import Path

import pandas as pd


def read_ile_summary(extract_path: Path) -> pd.DataFrame:
    return pd.read_csv(
        extract_path,
        dtype={
            "item_no": "string",
            "variant_code": "string",
            "location_code": "string",
            "quantity": "float64",
        },
        parse_dates=["posting_date"],
        keep_default_na=False,
    )
