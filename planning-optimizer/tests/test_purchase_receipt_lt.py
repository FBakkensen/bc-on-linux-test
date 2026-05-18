"""Tests for `bc_files.read_purchase_receipt_lt`.

The file seam reads the CSV produced by `scripts/extract-purchase-receipt-lt.sh`
and exposes the two lead-time series the LTD bootstrap (per ADR 0006) and the
supplier-reliability reason codes consume. Tests drive the public function
only — they survive a future swap to a different on-disk format or to the
API-page seam.
"""

from pathlib import Path

import pandas as pd
from extracts.bc_files import read_purchase_receipt_lt

HEADER = (
    "item_no,variant_code,location_code,vendor_no,po_order_date,"
    "receipt_posting_date,expected_receipt_date,quantity,document_no\n"
)


def _write(tmp_path: Path, *rows: str) -> Path:
    extract = tmp_path / "purchase-receipt-lt.csv"
    extract.write_text(HEADER + "".join(rows))
    return extract


def test_emits_one_row_per_input_with_raw_columns(tmp_path):
    extract = _write(
        tmp_path,
        "ITEM-A,,BLUE,V-001,2026-04-01,2026-04-08,2026-04-08,10,PR-0001\n",
    )

    df = read_purchase_receipt_lt(extract)

    assert len(df) == 1
    row = df.iloc[0]
    assert row["item_no"] == "ITEM-A"
    assert row["variant_code"] == ""
    assert row["location_code"] == "BLUE"
    assert row["vendor_no"] == "V-001"
    assert row["quantity"] == 10.0
    assert row["document_no"] == "PR-0001"
    assert row["po_order_date"] == pd.Timestamp("2026-04-01")
    assert row["receipt_posting_date"] == pd.Timestamp("2026-04-08")
    assert row["expected_receipt_date"] == pd.Timestamp("2026-04-08")


def test_order_to_receipt_days_is_receipt_minus_po_order(tmp_path):
    # 2026-04-01 → 2026-04-08 = 7 days. Feeds the LTD bootstrap per ADR 0006.
    extract = _write(
        tmp_path,
        "ITEM-A,,BLUE,V-001,2026-04-01,2026-04-08,2026-04-08,10,PR-0001\n",
    )

    df = read_purchase_receipt_lt(extract)

    assert df.iloc[0]["order_to_receipt_days"] == 7


def test_plan_to_receipt_days_is_receipt_minus_expected(tmp_path):
    # Late receipt: planner expected 2026-04-05, arrived 2026-04-08 → +3 days.
    # Feeds the `Supplier reliability` reason codes; does NOT feed LTD bootstrap.
    extract = _write(
        tmp_path,
        "ITEM-A,,BLUE,V-001,2026-04-01,2026-04-08,2026-04-05,10,PR-0001\n",
    )

    df = read_purchase_receipt_lt(extract)

    assert df.iloc[0]["plan_to_receipt_days"] == 3


def test_missing_expected_receipt_date_nulls_plan_to_receipt_only(tmp_path):
    # PO created without an Expected Receipt Date → CSV emits an empty cell.
    # Acceptance criteria: plan_to_receipt nulls, order_to_receipt still emitted.
    extract = _write(
        tmp_path,
        "ITEM-A,,BLUE,V-001,2026-04-01,2026-04-08,,10,PR-0001\n",
    )

    df = read_purchase_receipt_lt(extract)

    assert len(df) == 1
    row = df.iloc[0]
    assert row["order_to_receipt_days"] == 7
    assert pd.isna(row["plan_to_receipt_days"])
    assert pd.isna(row["expected_receipt_date"])


def test_multi_row_csv_keeps_lt_calcs_independent(tmp_path):
    extract = _write(
        tmp_path,
        "ITEM-A,,BLUE,V-001,2026-04-01,2026-04-08,2026-04-08,10,PR-0001\n",
        "ITEM-B,RED,GREEN,V-002,2026-04-10,2026-04-20,2026-04-15,5,PR-0002\n",
    )

    df = read_purchase_receipt_lt(extract)

    assert len(df) == 2
    by_doc = {row["document_no"]: row for _, row in df.iterrows()}
    assert by_doc["PR-0001"]["order_to_receipt_days"] == 7
    assert by_doc["PR-0001"]["plan_to_receipt_days"] == 0
    assert by_doc["PR-0002"]["order_to_receipt_days"] == 10
    assert by_doc["PR-0002"]["plan_to_receipt_days"] == 5


def test_bc_zero_date_is_treated_as_missing(tmp_path):
    # BC's uninitialised Date ("0D") OData-serialises as "0001-01-01" rather
    # than JSON null. CRONUS demo data hits this — a PO with Expected Receipt
    # Date never filled in shows up as 0001-01-01, which would otherwise turn
    # into a 700,000-day plan_to_receipt. Treat it as the null it represents
    # in BC so the supplier-reliability signal isn't polluted.
    extract = _write(
        tmp_path,
        "ITEM-A,,BLUE,V-001,2026-04-01,2026-04-08,0001-01-01,10,PR-0001\n",
    )

    df = read_purchase_receipt_lt(extract)

    row = df.iloc[0]
    assert pd.isna(row["expected_receipt_date"])
    assert pd.isna(row["plan_to_receipt_days"])
    assert row["order_to_receipt_days"] == 7


def test_trigger_date_is_po_order_date(tmp_path):
    # The order-trigger date for a purchase receipt is the PO Order Date —
    # when the supplier commitment was placed. lead_time.py pairs each LT
    # sample with a demand window ending immediately before this date, so
    # the seam exposes it under a uniform `trigger_date` column.
    extract = _write(
        tmp_path,
        "ITEM-A,,BLUE,V-001,2026-04-01,2026-04-08,2026-04-08,10,PR-0001\n",
    )

    df = read_purchase_receipt_lt(extract)

    assert df.iloc[0]["trigger_date"] == pd.Timestamp("2026-04-01")


def test_empty_extract_returns_empty_frame_with_schema(tmp_path):
    extract = _write(tmp_path)  # header only

    df = read_purchase_receipt_lt(extract)

    assert len(df) == 0
    assert "order_to_receipt_days" in df.columns
    assert "plan_to_receipt_days" in df.columns
    assert "trigger_date" in df.columns
