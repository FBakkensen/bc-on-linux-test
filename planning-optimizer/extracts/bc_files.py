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


def _read_extract_csv(
    extract_path: Path,
    *,
    str_cols: tuple[str, ...],
    date_cols: tuple[str, ...],
    extra_dtypes: dict[str, str] | None = None,
) -> pd.DataFrame:
    """Read a BC extract CSV with the BC-zero-date convention.

    BC's uninitialised Date OData-serialises as "0001-01-01" rather than
    JSON null; both that and empty cells collapse to NaT here so
    downstream `.dt` math doesn't see ~700,000-day-future events. The
    coercion runs as a separate `pd.to_datetime` loop (instead of
    `parse_dates=...`) so the column dtype is datetime64 even on a
    zero-row frame — `parse_dates` leaves an object-dtype column when
    nothing matched.
    """
    dtype: dict[str, str] = dict.fromkeys(str_cols, "string")
    if extra_dtypes:
        dtype.update(extra_dtypes)
    df = pd.read_csv(
        extract_path,
        dtype=dtype,  # type: ignore[arg-type]
        keep_default_na=False,
        na_values={c: ["", "0001-01-01"] for c in date_cols},
    )
    for col in date_cols:
        df[col] = pd.to_datetime(df[col])
    return df


def read_ile_summary(extract_path: Path) -> pd.DataFrame:
    """Read the ILE-summary CSV; empty variant_code is a valid no-variant SKU.

    `sales_amount` carries posted `Sales Amount Actual` for ABC revenue
    contribution per ADR 0005 / issue #16. Defaulted to 0.0 when the column
    is absent so older fixtures and the unit-quantity-only walking-skeleton
    still load.
    """
    df = pd.read_csv(
        extract_path,
        dtype={
            "item_no": "string",
            "variant_code": "string",
            "location_code": "string",
            "quantity": "float64",
            "sales_amount": "float64",
        },
        parse_dates=["posting_date"],
        keep_default_na=False,
    )
    if "sales_amount" not in df.columns:
        df["sales_amount"] = 0.0
    return df


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
    Null where the PO carried no Expected Receipt Date at creation time, or
    where the source PO has been deleted (left-outer join emits ""):
    `_read_extract_csv` collapses both forms to NaT.
    """
    df = _read_extract_csv(
        extract_path,
        str_cols=_PURCHASE_RECEIPT_LT_STR_COLUMNS,
        date_cols=_PURCHASE_RECEIPT_LT_DATE_COLUMNS,
        extra_dtypes={"quantity": "float64"},
    )
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
    df = _read_extract_csv(
        extract_path,
        str_cols=_PRODUCTION_LT_STR_COLUMNS,
        date_cols=_PRODUCTION_LT_DATE_COLUMNS,
    )
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
    df = _read_extract_csv(
        extract_path,
        str_cols=_ASSEMBLY_LT_STR_COLUMNS,
        date_cols=_ASSEMBLY_LT_DATE_COLUMNS,
    )
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
    df = _read_extract_csv(
        extract_path,
        str_cols=_TRANSFER_LT_STR_COLUMNS,
        date_cols=("posting_date",),
        extra_dtypes={"quantity": "float64"},
    )

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


_OPEN_SD_EVENT_STR_COLUMNS = (
    "item_no",
    "variant_code",
    "location_code",
    "source_kind",
)


def snapshot_from_ile_summary(ile_summary: pd.DataFrame, as_of_date: pd.Timestamp) -> pd.DataFrame:
    """Project today's on-hand per SKU by summing ILE up to `as_of_date`.

    The snapshot side of the simulator's initial state (ADR 0007). One row
    per `(item_no, variant_code, location_code)` with `snapshot_inventory =
    sum(quantity)` over `posting_date <= as_of_date`. Mirrors what
    `MaxSellableCalc.StartingOnHandAt` computes from ILE — no new AL
    surface needed; the summary extract already carries the rows.

    SKUs whose first ILE row is after `as_of_date` are excluded: there's
    no inventory yet, so they're not part of "today's projected balance."
    """
    sku_cols = ["item_no", "variant_code", "location_code"]
    if ile_summary.empty:
        return pd.DataFrame(
            {
                "item_no": pd.Series(dtype="string"),
                "variant_code": pd.Series(dtype="string"),
                "location_code": pd.Series(dtype="string"),
                "snapshot_inventory": pd.Series(dtype="float64"),
            },
        )
    eligible = ile_summary[ile_summary["posting_date"] <= as_of_date]
    return eligible.groupby(sku_cols, as_index=False).agg(
        snapshot_inventory=("quantity", "sum"),
    )


def read_open_sd_events(extract_path: Path) -> pd.DataFrame:
    """Read the open Supply & Demand event stream CSV.

    One row per open commitment line collected by the per-source Open SD
    Queries (ADR 0001 inclusion policy), seeding the Fidelity-B simulator's
    initial state per ADR 0007. `signed_quantity` is positive for supply,
    negative for demand. `source_kind` tags which BC source the row came
    from.
    """
    return _read_extract_csv(
        extract_path,
        str_cols=_OPEN_SD_EVENT_STR_COLUMNS,
        date_cols=("event_date",),
        extra_dtypes={"signed_quantity": "float64"},
    )
