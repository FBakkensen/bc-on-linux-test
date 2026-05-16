"""File-based bulk-read seam.

In sandbox the file lands on the local filesystem (CSV/Parquet dump from an AL
Query). In production the file lands in Azure Blob Storage — swapping the
backend is a one-call change at this seam. Walking-skeleton reads a CSV
aggregated to `(item_no, variant_code, location_code, daily_demand,
lead_time_days)` rows.
"""

from pathlib import Path

import pandas as pd


def read_extract(extract_path: Path) -> pd.DataFrame:
    return pd.read_csv(
        extract_path,
        dtype={
            "item_no": "string",
            "variant_code": "string",
            "location_code": "string",
            "daily_demand": "float64",
            "lead_time_days": "int32",
        },
        keep_default_na=False,
    )
