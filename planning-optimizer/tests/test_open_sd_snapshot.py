"""Tests for `bc_files.snapshot_from_ile_summary`.

The snapshot inventory side of the simulator's initial state (ADR 0007):
today's projected on-hand per SKU, derived from the existing Item Ledger
Summary extract by summing posting_date ≤ as_of_date. No new AL surface
needed — the math is one pandas groupby.
"""

from pathlib import Path

import pandas as pd
from extracts.bc_files import read_ile_summary, snapshot_from_ile_summary


def _write_ile(tmp_path: Path, *rows: str) -> Path:
    extract = tmp_path / "ile.csv"
    extract.write_text("item_no,variant_code,location_code,posting_date,quantity\n" + "".join(rows))
    return extract


def test_sums_quantity_per_sku_up_to_as_of_date(tmp_path):
    # One SKU, three days of ILE; only the rows on or before as_of_date count.
    df = read_ile_summary(
        _write_ile(
            tmp_path,
            "ITEM-A,,BLUE,2026-05-15,100\n",
            "ITEM-A,,BLUE,2026-05-17,-30\n",
            "ITEM-A,,BLUE,2026-05-20,50\n",  # after cutoff
        ),
    )

    snap = snapshot_from_ile_summary(df, as_of_date=pd.Timestamp("2026-05-17"))

    assert len(snap) == 1
    row = snap.iloc[0]
    assert row["item_no"] == "ITEM-A"
    assert row["snapshot_inventory"] == 70  # 100 - 30


def test_one_row_per_sku_even_when_multiple_dates_exist(tmp_path):
    df = read_ile_summary(
        _write_ile(
            tmp_path,
            "ITEM-A,,BLUE,2026-05-15,100\n",
            "ITEM-A,,BLUE,2026-05-16,10\n",
            "ITEM-B,RED,GREEN,2026-05-15,5\n",
        ),
    )

    snap = snapshot_from_ile_summary(df, as_of_date=pd.Timestamp("2026-05-17"))

    assert len(snap) == 2
    by_item = {
        (r["item_no"], r["variant_code"], r["location_code"]): r["snapshot_inventory"]
        for _, r in snap.iterrows()
    }
    assert by_item[("ITEM-A", "", "BLUE")] == 110
    assert by_item[("ITEM-B", "RED", "GREEN")] == 5


def test_separates_sku_by_variant_and_location(tmp_path):
    df = read_ile_summary(
        _write_ile(
            tmp_path,
            "ITEM-A,,BLUE,2026-05-15,10\n",
            "ITEM-A,RED,BLUE,2026-05-15,20\n",  # different variant → distinct SKU
            "ITEM-A,,GREEN,2026-05-15,30\n",  # different location → distinct SKU
        ),
    )

    snap = snapshot_from_ile_summary(df, as_of_date=pd.Timestamp("2026-05-15"))

    assert len(snap) == 3


def test_empty_ile_returns_empty_frame_with_schema(tmp_path):
    df = read_ile_summary(_write_ile(tmp_path))

    snap = snapshot_from_ile_summary(df, as_of_date=pd.Timestamp("2026-05-15"))

    assert len(snap) == 0
    for col in ("item_no", "variant_code", "location_code", "snapshot_inventory"):
        assert col in snap.columns


def test_excludes_skus_whose_first_ile_is_after_as_of_date(tmp_path):
    # ITEM-A's first transaction is after the cutoff → it's a "future" item
    # in the snapshot's view, so it should not appear in the projected
    # balance. Adjacent ITEM-B (which has older history) survives.
    df = read_ile_summary(
        _write_ile(
            tmp_path,
            "ITEM-A,,BLUE,2026-05-20,100\n",
            "ITEM-B,,BLUE,2026-05-10,40\n",
        ),
    )

    snap = snapshot_from_ile_summary(df, as_of_date=pd.Timestamp("2026-05-15"))

    items = set(snap["item_no"])
    assert items == {"ITEM-B"}
