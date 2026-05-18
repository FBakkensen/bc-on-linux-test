"""Tests for `bc_files.read_transfer_lt`.

ADR 0006: transfer LT = source-ILE (negative quantity, source location) →
destination-ILE (positive quantity, destination location), matched by
`(Document No., Item, Variant)`. The result row carries the destination
location — that's where the inventory becomes available, so it's the LT for
replenishment at that location.

CSV shape (long format — one row per ILE Transfer entry):

    document_no, item_no, variant_code, location_code, posting_date, quantity

`quantity < 0` = source; `quantity > 0` = destination. The AL Query already
filters `Entry Type = Transfer`. Unmatched source-only or dest-only rows
(e.g. transfer-in-transit at extract time) are excluded.
"""

from pathlib import Path

import pandas as pd
from extracts.bc_files import read_transfer_lt

HEADER = "document_no,item_no,variant_code,location_code,posting_date,quantity\n"


def _write(tmp_path: Path, *rows: str) -> Path:
    extract = tmp_path / "transfer-lt.csv"
    extract.write_text(HEADER + "".join(rows))
    return extract


def test_matched_pair_yields_dest_minus_source_lt(tmp_path):
    # Source posted 2026-04-01 at BLUE (qty -5), destination posted 2026-04-04
    # at GREEN (qty +5). LT = 3 days, dest location is BLUE→GREEN's GREEN.
    extract = _write(
        tmp_path,
        "TR-001,ITEM-A,,BLUE,2026-04-01,-5\n",
        "TR-001,ITEM-A,,GREEN,2026-04-04,5\n",
    )

    df = read_transfer_lt(extract)

    assert len(df) == 1
    row = df.iloc[0]
    assert row["item_no"] == "ITEM-A"
    assert row["variant_code"] == ""
    assert row["location_code"] == "GREEN"
    assert row["lead_time_days"] == 3
    assert row["replenishment_system"] == "transfer"
    assert row["source"] == "transfer"
    assert row["shared_sample_key"] == "TR-001"


def test_source_without_destination_is_excluded(tmp_path):
    # In-transit at extract time: the (+) destination row hasn't posted yet,
    # so no LT can be computed. ADR 0006 says exclude — these are unfinished
    # transfers and contribute nothing to the historical sample.
    extract = _write(
        tmp_path,
        "TR-INFLIGHT,ITEM-A,,BLUE,2026-04-01,-5\n",
    )

    df = read_transfer_lt(extract)

    assert len(df) == 0


def test_destination_without_source_is_excluded(tmp_path):
    # Mirror case: dest ILE present, source missing (corrupt history /
    # data export cut-off). Exclude — no LT computable.
    extract = _write(
        tmp_path,
        "TR-HALF,ITEM-A,,GREEN,2026-04-04,5\n",
    )

    df = read_transfer_lt(extract)

    assert len(df) == 0


def test_pairing_respects_item_and_variant(tmp_path):
    # Same Document No., two items — each gets its own pair. Mismatched
    # variants on the same document do NOT pair across each other.
    extract = _write(
        tmp_path,
        "TR-002,ITEM-A,RED,BLUE,2026-04-01,-5\n",
        "TR-002,ITEM-A,RED,GREEN,2026-04-04,5\n",
        "TR-002,ITEM-B,,BLUE,2026-04-02,-3\n",
        "TR-002,ITEM-B,,GREEN,2026-04-05,3\n",
    )

    df = read_transfer_lt(extract)

    assert len(df) == 2
    pairs = {(row["item_no"], row["variant_code"]): row for _, row in df.iterrows()}
    assert pairs[("ITEM-A", "RED")]["lead_time_days"] == 3
    assert pairs[("ITEM-B", "")]["lead_time_days"] == 3


def test_trigger_date_is_source_posting_date(tmp_path):
    # Transfer's order-trigger date is the source-side posting date — when
    # stock left the source location. lead_time.py pairs each LT sample with
    # a demand window ending immediately before this date.
    extract = _write(
        tmp_path,
        "TR-001,ITEM-A,,BLUE,2026-04-01,-5\n",
        "TR-001,ITEM-A,,GREEN,2026-04-04,5\n",
    )

    df = read_transfer_lt(extract)

    assert df.iloc[0]["trigger_date"] == pd.Timestamp("2026-04-01")


def test_empty_extract_returns_empty_frame_with_schema(tmp_path):
    extract = _write(tmp_path)  # header only

    df = read_transfer_lt(extract)

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
        "trigger_date",
    ):
        assert col in df.columns
