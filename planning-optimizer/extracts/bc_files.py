"""File-based bulk-read seam.

In sandbox the file lands on the local filesystem (CSV dump from an AL
Query). In production the file lands in Azure Blob Storage — swapping the
backend is a one-call change at this seam. The first real extract is the
Item Ledger Summary, grouped server-side to (item, variant, location,
posting_date, signed_quantity) per ADR 0006 + ADR 0009.
"""

from pathlib import Path
from typing import Final, Literal

import numpy as np
import pandas as pd

# Unified-shape literals shared by every LT reader. The downstream
# bootstrap (ADR 0006) joins these by exact string match — a typo here
# silently drops samples, so we centralise them and give mypy
# `Literal[...]` types to make typos a type error at the call site.
ReplenishmentSystem = Literal["production", "assembly", "transfer"]
LtSource = Literal["ile", "header_fallback", "assembly_header", "transfer"]

REPLENISHMENT_PRODUCTION: Final[ReplenishmentSystem] = "production"
REPLENISHMENT_ASSEMBLY: Final[ReplenishmentSystem] = "assembly"
REPLENISHMENT_TRANSFER: Final[ReplenishmentSystem] = "transfer"
SOURCE_ILE: Final[LtSource] = "ile"
SOURCE_HEADER_FALLBACK: Final[LtSource] = "header_fallback"
SOURCE_ASSEMBLY_HEADER: Final[LtSource] = "assembly_header"
SOURCE_TRANSFER: Final[LtSource] = "transfer"

ENTRY_KIND_OUTPUT: Final = "output"
ENTRY_KIND_CONSUMPTION: Final = "consumption"


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


_PRODUCTION_LT_STR_COLUMNS = (
    "prod_order_no",
    "item_no",
    "variant_code",
    "location_code",
    "entry_kind",
)
_PRODUCTION_LT_DATE_COLUMNS = (
    "posting_date",
    "prod_order_starting_date",
    "prod_order_finishing_date",
    "prod_order_ending_date",
)


def read_production_lt(extract_path: Path) -> pd.DataFrame:
    """Read the Production LT extract and derive the LTD-bootstrap series.

    Returns one row per `(prod_order_no, item_no, variant_code, location_code)`
    output combination, in the unified shape
    `(item_no, variant_code, location_code, lead_time_days,
    replenishment_system, source, shared_sample_key, plan_to_actual_days)`.

    `lead_time_days` is `max(ILE Output Posting Date) − min(ILE Consumption
    Posting Date)` across the whole prod order — multi-output prod orders
    share the same sample (per ADR 0006). `shared_sample_key = prod_order_no`
    so the bootstrap can deduplicate.
    """
    df = pd.read_csv(
        extract_path,
        dtype=dict.fromkeys(_PRODUCTION_LT_STR_COLUMNS, "string"),
        keep_default_na=False,
        na_values={c: ["", "0001-01-01"] for c in _PRODUCTION_LT_DATE_COLUMNS},
    )
    for col in _PRODUCTION_LT_DATE_COLUMNS:
        df[col] = pd.to_datetime(df[col])
    # BC's ILE "Entry Type" enum serialises as "Output" / "Consumption"; we
    # match against lowercase literals so the seam is tolerant of either
    # casing from upstream.
    df["entry_kind"] = df["entry_kind"].str.lower()

    if df.empty:
        # Short-circuit: groupby-then-map on a zero-row frame yields an
        # object-dtype Series that breaks `.dt.days`. Returning a typed
        # empty frame keeps downstream `.dt` math safe.
        return pd.DataFrame(
            {
                "prod_order_no": pd.Series(dtype="string"),
                "item_no": pd.Series(dtype="string"),
                "variant_code": pd.Series(dtype="string"),
                "location_code": pd.Series(dtype="string"),
                "lead_time_days": pd.Series(dtype="int64"),
                "source": pd.Series(dtype="string"),
                "replenishment_system": pd.Series(dtype="string"),
                "shared_sample_key": pd.Series(dtype="string"),
                "plan_to_actual_days": pd.Series(dtype="int64"),
            },
        )

    outputs = df[df["entry_kind"] == ENTRY_KIND_OUTPUT]
    consumption = df[df["entry_kind"] == ENTRY_KIND_CONSUMPTION]
    max_output = outputs.groupby("prod_order_no")["posting_date"].max()
    min_consumption = consumption.groupby("prod_order_no")["posting_date"].min()
    # Pre-compute per-prod-order series so `np.where` only does row-aligned
    # selection — keeps the dataflow linear (group → derive → assemble row).
    ile_td = max_output - min_consumption
    header_td = (
        outputs.groupby("prod_order_no")["prod_order_finishing_date"].first()
        - outputs.groupby("prod_order_no")["prod_order_starting_date"].first()
    )
    plan_to_actual_td = (
        max_output - outputs.groupby("prod_order_no")["prod_order_ending_date"].first()
    )

    output_combos = outputs.drop_duplicates(
        subset=["prod_order_no", "item_no", "variant_code", "location_code"],
    )[["prod_order_no", "item_no", "variant_code", "location_code"]].copy()
    po_no = output_combos["prod_order_no"]
    has_consumption = po_no.isin(min_consumption.index)

    output_combos["lead_time_days"] = np.where(
        has_consumption,
        po_no.map(ile_td).dt.days,
        po_no.map(header_td).dt.days,
    )
    output_combos["source"] = np.where(has_consumption, SOURCE_ILE, SOURCE_HEADER_FALLBACK)
    output_combos["replenishment_system"] = REPLENISHMENT_PRODUCTION
    output_combos["shared_sample_key"] = po_no
    output_combos["plan_to_actual_days"] = po_no.map(plan_to_actual_td).dt.days
    return output_combos


_ASSEMBLY_LT_STR_COLUMNS = (
    "assembly_doc_no",
    "item_no",
    "variant_code",
    "location_code",
)
_ASSEMBLY_LT_DATE_COLUMNS = ("starting_date", "posting_date")


def read_assembly_lt(extract_path: Path) -> pd.DataFrame:
    """Read the Assembly LT extract: one row per finished posted assembly.

    `lead_time_days = posting_date - starting_date` per ADR 0006. Always uses
    the assembly header dates — no ILE fallback path.
    """
    df = pd.read_csv(
        extract_path,
        dtype=dict.fromkeys(_ASSEMBLY_LT_STR_COLUMNS, "string"),
        keep_default_na=False,
        na_values={c: ["", "0001-01-01"] for c in _ASSEMBLY_LT_DATE_COLUMNS},
    )
    for col in _ASSEMBLY_LT_DATE_COLUMNS:
        df[col] = pd.to_datetime(df[col])
    df["lead_time_days"] = (df["posting_date"] - df["starting_date"]).dt.days
    df["replenishment_system"] = REPLENISHMENT_ASSEMBLY
    df["source"] = SOURCE_ASSEMBLY_HEADER
    df["shared_sample_key"] = df["assembly_doc_no"]
    df["plan_to_actual_days"] = pd.NA
    return df.drop(columns=["starting_date", "posting_date"])


_TRANSFER_LT_STR_COLUMNS = (
    "document_no",
    "item_no",
    "variant_code",
    "location_code",
)


def read_transfer_lt(extract_path: Path) -> pd.DataFrame:
    """Read the Transfer LT extract and pair source / destination ILE rows.

    Source rows carry negative Quantity (stock leaving), destination rows
    carry positive Quantity. Pairing is by `(document_no, item_no,
    variant_code)` per ADR 0006. The result row's `location_code` is the
    destination — that's where the inventory becomes available, so it's the
    LT for replenishment at that location.

    Unmatched rows (source without dest, or dest without source — typical for
    transfer-in-transit at extract time) are excluded.
    """
    df = pd.read_csv(
        extract_path,
        dtype={
            **dict.fromkeys(_TRANSFER_LT_STR_COLUMNS, "string"),
            "quantity": "float64",
        },
        keep_default_na=False,
        na_values={"posting_date": ["", "0001-01-01"]},
    )
    df["posting_date"] = pd.to_datetime(df["posting_date"])

    source = df[df["quantity"] < 0].rename(columns={"posting_date": "_source_date"})[
        ["document_no", "item_no", "variant_code", "_source_date"]
    ]
    dest = df[df["quantity"] > 0].rename(columns={"posting_date": "_dest_date"})[
        ["document_no", "item_no", "variant_code", "location_code", "_dest_date"]
    ]

    paired = dest.merge(
        source,
        on=["document_no", "item_no", "variant_code"],
        how="inner",
    )
    paired["lead_time_days"] = (paired["_dest_date"] - paired["_source_date"]).dt.days
    paired["replenishment_system"] = REPLENISHMENT_TRANSFER
    paired["source"] = SOURCE_TRANSFER
    paired["shared_sample_key"] = paired["document_no"]
    paired["plan_to_actual_days"] = pd.NA
    return paired.drop(columns=["_source_date", "_dest_date"])
