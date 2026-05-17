"""Tests for `bc_files.read_production_lt`.

The file seam reads the CSV produced by `scripts/extract-production-lt.sh` and
exposes the production lead-time series the LTD bootstrap (ADR 0006) consumes,
plus the separate plan-to-actual series feeding the future `Production
reliability` reason codes.

CSV shape is long-form, one row per `(prod_order, ILE entry)`:

    prod_order_no, item_no, variant_code, location_code,
    entry_kind ∈ {output, consumption},
    posting_date,
    prod_order_starting_date,
    prod_order_finishing_date,
    prod_order_ending_date

The AL Query filters Status=Finished server-side; cancelled / scrapped prod
orders never appear in the CSV, so the Python parser does not police for them.

The reader returns one row per `(prod_order, item, variant, location)` output
combination, in the unified `(lead_time_days, replenishment_system, source,
shared_sample_key, plan_to_actual_days)` shape.
"""

from pathlib import Path

from extracts.bc_files import read_production_lt

HEADER = (
    "prod_order_no,item_no,variant_code,location_code,entry_kind,posting_date,"
    "prod_order_starting_date,prod_order_finishing_date,prod_order_ending_date\n"
)


def _write(tmp_path: Path, *rows: str) -> Path:
    extract = tmp_path / "production-lt.csv"
    extract.write_text(HEADER + "".join(rows))
    return extract


def test_ile_primary_lt_is_max_output_minus_min_consumption(tmp_path):
    # Consumption posted 2026-04-01, output posted 2026-04-08 → LT = 7 days.
    # The "primary" path per ADR 0006 — event-record dates beat planning-field
    # dates when both are available.
    extract = _write(
        tmp_path,
        "PO-100,ITEM-A,,BLUE,consumption,2026-04-01,2026-03-30,2026-04-08,2026-04-07\n",
        "PO-100,ITEM-A,,BLUE,output,2026-04-08,2026-03-30,2026-04-08,2026-04-07\n",
    )

    df = read_production_lt(extract)

    assert len(df) == 1
    row = df.iloc[0]
    assert row["item_no"] == "ITEM-A"
    assert row["variant_code"] == ""
    assert row["location_code"] == "BLUE"
    assert row["lead_time_days"] == 7
    assert row["replenishment_system"] == "production"
    assert row["source"] == "ile"
    assert row["shared_sample_key"] == "PO-100"


def test_header_fallback_when_no_consumption_rows(tmp_path):
    # Raw extraction / no-BOM prod orders post outputs but never any
    # consumption ILE. ADR 0006 says fall back to `Finishing Date −
    # Starting Date` from the prod order header in that case, and the row
    # carries `source=header_fallback` so the bootstrap can flag it.
    extract = _write(
        tmp_path,
        "PO-200,ITEM-B,RED,GREEN,output,2026-05-10,2026-05-01,2026-05-09,2026-05-08\n",
    )

    df = read_production_lt(extract)

    assert len(df) == 1
    row = df.iloc[0]
    assert row["lead_time_days"] == 8  # 2026-05-09 - 2026-05-01
    assert row["source"] == "header_fallback"
    assert row["shared_sample_key"] == "PO-200"


def test_multi_output_prod_order_emits_row_per_output_line_with_shared_key(tmp_path):
    # ADR 0006: a prod order that outputs two items shares one prod-order-level
    # LT — bootstrap must dedupe via `shared_sample_key` so we don't double-count.
    # max_output = 2026-06-12 (the later of the two outputs).
    # min_consumption = 2026-06-01. LT = 11 days for both rows.
    extract = _write(
        tmp_path,
        "PO-300,RAW-X,,BLUE,consumption,2026-06-01,2026-05-28,2026-06-12,2026-06-10\n",
        "PO-300,ITEM-A,,BLUE,output,2026-06-10,2026-05-28,2026-06-12,2026-06-10\n",
        "PO-300,ITEM-B,,BLUE,output,2026-06-12,2026-05-28,2026-06-12,2026-06-10\n",
    )

    df = read_production_lt(extract)

    assert len(df) == 2
    assert set(df["item_no"]) == {"ITEM-A", "ITEM-B"}
    assert list(df["lead_time_days"]) == [11, 11]
    assert list(df["shared_sample_key"]) == ["PO-300", "PO-300"]
    assert all(df["source"] == "ile")


def test_plan_to_actual_days_is_max_output_minus_header_ending(tmp_path):
    # ADR 0006 secondary series — feeds the future `Production reliability`
    # reason codes, does NOT feed LTD bootstrap. Late production: header
    # Ending Date 2026-04-05, actual max output 2026-04-08 → +3 days.
    extract = _write(
        tmp_path,
        "PO-400,ITEM-A,,BLUE,consumption,2026-04-01,2026-03-30,2026-04-08,2026-04-05\n",
        "PO-400,ITEM-A,,BLUE,output,2026-04-08,2026-03-30,2026-04-08,2026-04-05\n",
    )

    df = read_production_lt(extract)

    assert df.iloc[0]["plan_to_actual_days"] == 3


def test_multiple_prod_orders_kept_independent(tmp_path):
    # Two unrelated finished prod orders. ILE aggregation must not bleed
    # across `prod_order_no` boundaries — PO-501's max output stays inside
    # PO-501's row.
    extract = _write(
        tmp_path,
        "PO-500,ITEM-A,,BLUE,consumption,2026-07-01,2026-06-25,2026-07-05,2026-07-05\n",
        "PO-500,ITEM-A,,BLUE,output,2026-07-05,2026-06-25,2026-07-05,2026-07-05\n",
        "PO-501,ITEM-B,RED,GREEN,consumption,2026-08-01,2026-07-20,2026-08-12,2026-08-12\n",
        "PO-501,ITEM-B,RED,GREEN,output,2026-08-12,2026-07-20,2026-08-12,2026-08-12\n",
    )

    df = read_production_lt(extract)

    by_po = {row["prod_order_no"]: row for _, row in df.iterrows()}
    assert by_po["PO-500"]["lead_time_days"] == 4  # 2026-07-05 - 2026-07-01
    assert by_po["PO-501"]["lead_time_days"] == 11  # 2026-08-12 - 2026-08-01


def test_empty_extract_returns_empty_frame_with_schema(tmp_path):
    extract = _write(tmp_path)  # header only

    df = read_production_lt(extract)

    assert len(df) == 0
    for col in (
        "item_no",
        "variant_code",
        "location_code",
        "lead_time_days",
        "replenishment_system",
        "source",
        "shared_sample_key",
        "plan_to_actual_days",
    ):
        assert col in df.columns
