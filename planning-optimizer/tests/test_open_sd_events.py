"""Tests for `bc_files.read_open_sd_events`.

The file seam reads the CSV produced by `scripts/extract-open-sd.sh` and
exposes the open Supply & Demand event stream that seeds the Fidelity-B
simulator's initial state per ADR 0007. Rows are signed events (positive
= supply, negative = demand), one per open commitment line collected by
`BCEventSource` (ADR 0001 inclusion policy).

CSV shape:

    item_no, variant_code, location_code, event_date, signed_quantity,
    source_kind

`source_kind` discriminates which BC source the row came from
(sales_order, purchase_order, prod_order_line, …). The simulator does
not branch on it today, but the field is load-bearing for debugging
extracts and for the future Production reliability reason code.
"""

from pathlib import Path

import pandas as pd
from extracts.bc_files import read_open_sd_events

HEADER = "item_no,variant_code,location_code,event_date,signed_quantity,source_kind\n"


def _write(tmp_path: Path, *rows: str) -> Path:
    extract = tmp_path / "open-sd-events.csv"
    extract.write_text(HEADER + "".join(rows))
    return extract


def test_emits_row_with_raw_columns(tmp_path):
    extract = _write(
        tmp_path,
        "ITEM-A,,BLUE,2026-05-20,-10,sales_order\n",
    )

    df = read_open_sd_events(extract)

    assert len(df) == 1
    row = df.iloc[0]
    assert row["item_no"] == "ITEM-A"
    assert row["variant_code"] == ""
    assert row["location_code"] == "BLUE"
    assert row["event_date"] == pd.Timestamp("2026-05-20")
    assert row["signed_quantity"] == -10.0
    assert row["source_kind"] == "sales_order"


def test_supply_and_demand_signs_preserved(tmp_path):
    # ADR 0001: supply rows (purchase orders, prod outputs, transfer inbound,
    # sales returns) come through positive; demand rows (sales orders,
    # prod components, transfer outbound, service lines) come through
    # negative. The simulator sums these against today's snapshot.
    extract = _write(
        tmp_path,
        "ITEM-A,,BLUE,2026-05-20,-10,sales_order\n",
        "ITEM-A,,BLUE,2026-05-25,50,purchase_order\n",
    )

    df = read_open_sd_events(extract)

    by_kind = {row["source_kind"]: row["signed_quantity"] for _, row in df.iterrows()}
    assert by_kind["sales_order"] == -10.0
    assert by_kind["purchase_order"] == 50.0


def test_multi_sku_keeps_rows_independent(tmp_path):
    extract = _write(
        tmp_path,
        "ITEM-A,RED,BLUE,2026-05-20,-10,sales_order\n",
        "ITEM-B,,GREEN,2026-06-01,7,assembly_header\n",
    )

    df = read_open_sd_events(extract)

    assert len(df) == 2
    by_item = {row["item_no"]: row for _, row in df.iterrows()}
    assert by_item["ITEM-A"]["variant_code"] == "RED"
    assert by_item["ITEM-A"]["location_code"] == "BLUE"
    assert by_item["ITEM-B"]["variant_code"] == ""
    assert by_item["ITEM-B"]["location_code"] == "GREEN"
    assert by_item["ITEM-B"]["source_kind"] == "assembly_header"


def test_empty_extract_returns_empty_frame_with_schema(tmp_path):
    extract = _write(tmp_path)  # header only

    df = read_open_sd_events(extract)

    assert len(df) == 0
    for col in (
        "item_no",
        "variant_code",
        "location_code",
        "event_date",
        "signed_quantity",
        "source_kind",
    ):
        assert col in df.columns


def test_bc_zero_date_is_treated_as_missing(tmp_path):
    # BC's uninitialised Date OData-serialises as "0001-01-01"; an event with
    # no date is meaningless to the simulator (where does it sit in the walk?)
    # — coerce to NaT so downstream code can drop or flag it explicitly
    # rather than seeing a ~700,000-day-in-the-future event.
    extract = _write(
        tmp_path,
        "ITEM-A,,BLUE,0001-01-01,-10,sales_order\n",
    )

    df = read_open_sd_events(extract)

    assert pd.isna(df.iloc[0]["event_date"])
