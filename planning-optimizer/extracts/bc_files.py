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
    """Read the ILE-summary CSV; empty variant_code is a valid no-variant SKU."""
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


_PURCHASE_RECEIPT_LT_STR_COLUMNS = (
    "item_no",
    "variant_code",
    "location_code",
    "vendor_no",
    "document_no",
)
_PURCHASE_RECEIPT_LT_DATE_COLUMNS = (
    "po_order_date",
    "receipt_posting_date",
    "expected_receipt_date",
)


def read_purchase_receipt_lt(extract_path: Path) -> pd.DataFrame:
    """Read the Purchase Receipt LT extract and derive both LT series.

    `order_to_receipt_days` = `receipt_posting_date − po_order_date`. Feeds
    the LTD bootstrap per ADR 0006.

    `plan_to_receipt_days` = `receipt_posting_date − expected_receipt_date`.
    Feeds the `Supplier reliability` reason codes; does NOT feed LTD bootstrap.
    Null where the PO carried no Expected Receipt Date at creation time.
    """
    df = pd.read_csv(
        extract_path,
        dtype={
            **dict.fromkeys(_PURCHASE_RECEIPT_LT_STR_COLUMNS, "string"),
            "quantity": "float64",
        },
        keep_default_na=False,
        # "" is the JSON-null path (left-outer-joined Purchase Header is
        # gone); "0001-01-01" is BC's uninitialised Date (0D) — both mean
        # "no value" and must collapse to NaT here so plan_to_receipt isn't
        # polluted with ~700,000-day deltas.
        na_values={c: ["", "0001-01-01"] for c in _PURCHASE_RECEIPT_LT_DATE_COLUMNS},
    )
    # Coerce explicitly (instead of relying on `parse_dates`) so the dtype is
    # datetime64 even when the CSV has zero data rows — downstream `.dt` math
    # would otherwise fail on an object-dtype empty column.
    for col in _PURCHASE_RECEIPT_LT_DATE_COLUMNS:
        df[col] = pd.to_datetime(df[col])
    df["order_to_receipt_days"] = (df["receipt_posting_date"] - df["po_order_date"]).dt.days
    df["plan_to_receipt_days"] = (df["receipt_posting_date"] - df["expected_receipt_date"]).dt.days
    return df
