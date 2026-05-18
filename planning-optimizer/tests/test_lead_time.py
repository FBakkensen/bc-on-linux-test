"""Tests for `lead_time.extract_lt_series`.

The math seam that consumes the four LT extracts (Purchase, Production,
Assembly, Transfer) plus the ILE Summary, and produces the unified
`(LT_days, demand_window, replenishment_system, source_flag)` series the
bootstrap LTD sampler (slice #18, per ADR 0006) consumes — alongside the
secondary Plan-to-Receipt / Plan-to-Actual series and per-SKU summary
statistics.

Tests build the per-extract DataFrames inline via the existing readers, so
they double as integration tests against the extract schema: a future
column rename or dtype change in `extracts/bc_files.py` shows up here.
"""

from pathlib import Path

import numpy as np
import pandas as pd
import pytest
from bc_planning_optimizer.lead_time import extract_lt_series
from extracts.bc_files import (
    read_assembly_lt,
    read_ile_summary,
    read_production_lt,
    read_purchase_receipt_lt,
    read_transfer_lt,
)


def _empty_purchase(tmp_path: Path) -> pd.DataFrame:
    extract = tmp_path / "purchase.csv"
    extract.write_text(
        "item_no,variant_code,location_code,vendor_no,po_order_date,"
        "receipt_posting_date,expected_receipt_date,quantity,document_no\n",
    )
    return read_purchase_receipt_lt(extract)


def _empty_production(tmp_path: Path) -> pd.DataFrame:
    extract = tmp_path / "production.csv"
    extract.write_text(
        "prod_order_no,item_no,variant_code,location_code,entry_kind,posting_date,"
        "prod_order_starting_date,prod_order_finishing_date,prod_order_ending_date\n",
    )
    return read_production_lt(extract)


def _empty_assembly(tmp_path: Path) -> pd.DataFrame:
    extract = tmp_path / "assembly.csv"
    extract.write_text(
        "assembly_doc_no,item_no,variant_code,location_code,starting_date,posting_date\n",
    )
    return read_assembly_lt(extract)


def _empty_transfer(tmp_path: Path) -> pd.DataFrame:
    extract = tmp_path / "transfer.csv"
    extract.write_text("document_no,item_no,variant_code,location_code,posting_date,quantity\n")
    return read_transfer_lt(extract)


def _write_purchase(tmp_path: Path, *rows: str) -> pd.DataFrame:
    extract = tmp_path / "purchase.csv"
    extract.write_text(
        "item_no,variant_code,location_code,vendor_no,po_order_date,"
        "receipt_posting_date,expected_receipt_date,quantity,document_no\n" + "".join(rows),
    )
    return read_purchase_receipt_lt(extract)


def _write_production(tmp_path: Path, *rows: str) -> pd.DataFrame:
    extract = tmp_path / "production.csv"
    extract.write_text(
        "prod_order_no,item_no,variant_code,location_code,entry_kind,posting_date,"
        "prod_order_starting_date,prod_order_finishing_date,prod_order_ending_date\n"
        + "".join(rows),
    )
    return read_production_lt(extract)


def _write_assembly(tmp_path: Path, *rows: str) -> pd.DataFrame:
    extract = tmp_path / "assembly.csv"
    extract.write_text(
        "assembly_doc_no,item_no,variant_code,location_code,starting_date,posting_date\n"
        + "".join(rows),
    )
    return read_assembly_lt(extract)


def _write_transfer(tmp_path: Path, *rows: str) -> pd.DataFrame:
    extract = tmp_path / "transfer.csv"
    extract.write_text(
        "document_no,item_no,variant_code,location_code,posting_date,quantity\n" + "".join(rows),
    )
    return read_transfer_lt(extract)


def _write_ile(tmp_path: Path, *rows: str) -> pd.DataFrame:
    extract = tmp_path / "ile.csv"
    extract.write_text(
        "item_no,variant_code,location_code,posting_date,quantity,sales_amount\n" + "".join(rows),
    )
    return read_ile_summary(extract)


def test_purchase_lt_sample_appears_in_unified_pairs(tmp_path):
    # Tracer bullet: one Purchase Receipt LT sample. The unified series
    # emits one pair per LT sample, labelled `replenishment_system=purchase`
    # and `source=purchase_receipt`, carrying the Order-to-Receipt LT.
    purchase = _write_purchase(
        tmp_path,
        "ITEM-A,,BLUE,V-001,2026-04-01,2026-04-08,2026-04-08,10,PR-0001\n",
    )
    ile = _write_ile(tmp_path)

    result = extract_lt_series(
        purchase_lt=purchase,
        production_lt=_empty_production(tmp_path),
        transfer_lt=_empty_transfer(tmp_path),
        assembly_lt=_empty_assembly(tmp_path),
        ile_summary=ile,
    )

    assert len(result.pairs) == 1
    row = result.pairs.iloc[0]
    assert row["item_no"] == "ITEM-A"
    assert row["variant_code"] == ""
    assert row["location_code"] == "BLUE"
    assert row["lead_time_days"] == 7
    assert row["replenishment_system"] == "purchase"
    assert row["source"] == "purchase_receipt"
    assert row["shared_sample_key"] == "PR-0001"
    assert row["trigger_date"] == pd.Timestamp("2026-04-01")


def test_assembly_sample_appears_in_unified_pairs(tmp_path):
    # Assembly LT 2026-04-01 → 2026-04-05 = 4 days. Single source path
    # (`source=assembly_header`) — Posted Assembly Header always has both
    # dates, so no fallback (ADR 0006).
    assembly = _write_assembly(tmp_path, "ASM-001,KIT-A,,BLUE,2026-04-01,2026-04-05\n")
    ile = _write_ile(tmp_path)

    result = extract_lt_series(
        purchase_lt=_empty_purchase(tmp_path),
        production_lt=_empty_production(tmp_path),
        transfer_lt=_empty_transfer(tmp_path),
        assembly_lt=assembly,
        ile_summary=ile,
    )

    assert len(result.pairs) == 1
    row = result.pairs.iloc[0]
    assert row["lead_time_days"] == 4
    assert row["replenishment_system"] == "assembly"
    assert row["source"] == "assembly_header"
    assert row["shared_sample_key"] == "ASM-001"
    assert row["trigger_date"] == pd.Timestamp("2026-04-01")


def test_transfer_sample_appears_in_unified_pairs(tmp_path):
    # Transfer source 2026-04-01 at BLUE → dest 2026-04-04 at GREEN = 3 days.
    # Replenishment location is the destination (where stock becomes
    # available); trigger is the source-side posting date.
    transfer = _write_transfer(
        tmp_path,
        "TR-001,ITEM-A,,BLUE,2026-04-01,-5\n",
        "TR-001,ITEM-A,,GREEN,2026-04-04,5\n",
    )
    ile = _write_ile(tmp_path)

    result = extract_lt_series(
        purchase_lt=_empty_purchase(tmp_path),
        production_lt=_empty_production(tmp_path),
        transfer_lt=transfer,
        assembly_lt=_empty_assembly(tmp_path),
        ile_summary=ile,
    )

    assert len(result.pairs) == 1
    row = result.pairs.iloc[0]
    assert row["lead_time_days"] == 3
    assert row["replenishment_system"] == "transfer"
    assert row["source"] == "transfer"
    assert row["location_code"] == "GREEN"
    assert row["trigger_date"] == pd.Timestamp("2026-04-01")


def test_production_header_fallback_keeps_source_flag(tmp_path):
    # No consumption rows → header-fallback path. ADR 0006 says samples
    # taken from header dates flag `source=header_fallback` so the bootstrap
    # / downstream UI can surface that this LT is "planner intent", not
    # observed work time.
    production = _write_production(
        tmp_path,
        "PO-200,ITEM-B,RED,GREEN,output,2026-05-10,2026-05-01,2026-05-09,2026-05-08\n",
    )
    ile = _write_ile(tmp_path)

    result = extract_lt_series(
        purchase_lt=_empty_purchase(tmp_path),
        production_lt=production,
        transfer_lt=_empty_transfer(tmp_path),
        assembly_lt=_empty_assembly(tmp_path),
        ile_summary=ile,
    )

    row = result.pairs.iloc[0]
    assert row["lead_time_days"] == 8  # 2026-05-09 - 2026-05-01
    assert row["source"] == "header_fallback"
    assert row["trigger_date"] == pd.Timestamp("2026-05-01")


def test_multi_output_prod_order_emits_shared_sample_key_per_output(tmp_path):
    # ADR 0006: a multi-output prod order shares one LT across all output
    # SKUs. The unified series emits one row per output (so each SKU gets
    # its sample) but the `shared_sample_key` is identical so the bootstrap
    # can deduplicate at sampling time.
    production = _write_production(
        tmp_path,
        "PO-300,RAW-X,,BLUE,consumption,2026-06-01,2026-05-28,2026-06-12,2026-06-10\n",
        "PO-300,ITEM-A,,BLUE,output,2026-06-10,2026-05-28,2026-06-12,2026-06-10\n",
        "PO-300,ITEM-B,,BLUE,output,2026-06-12,2026-05-28,2026-06-12,2026-06-10\n",
    )
    ile = _write_ile(tmp_path)

    result = extract_lt_series(
        purchase_lt=_empty_purchase(tmp_path),
        production_lt=production,
        transfer_lt=_empty_transfer(tmp_path),
        assembly_lt=_empty_assembly(tmp_path),
        ile_summary=ile,
    )

    assert len(result.pairs) == 2
    by_item = {row["item_no"]: row for _, row in result.pairs.iterrows()}
    assert by_item["ITEM-A"]["lead_time_days"] == 11
    assert by_item["ITEM-B"]["lead_time_days"] == 11
    assert by_item["ITEM-A"]["shared_sample_key"] == "PO-300"
    assert by_item["ITEM-B"]["shared_sample_key"] == "PO-300"


def test_demand_window_covers_lt_days_ending_before_trigger(tmp_path):
    # Trigger 2026-04-08, LT 7 → window = [2026-04-01 .. 2026-04-07] (7 days).
    # Daily demand of 5 units on every window day; per ADR 0006 demand is
    # the negated net quantity (positive = demand, returns net through). The
    # paired demand_window is a length-7 array of per-day net demand.
    purchase = _write_purchase(
        tmp_path,
        "ITEM-A,,BLUE,V-001,2026-04-08,2026-04-15,2026-04-15,10,PR-0001\n",
    )
    ile = _write_ile(
        tmp_path,
        "ITEM-A,,BLUE,2026-04-01,-5,50\n",
        "ITEM-A,,BLUE,2026-04-02,-5,50\n",
        "ITEM-A,,BLUE,2026-04-03,-5,50\n",
        "ITEM-A,,BLUE,2026-04-04,-5,50\n",
        "ITEM-A,,BLUE,2026-04-05,-5,50\n",
        "ITEM-A,,BLUE,2026-04-06,-5,50\n",
        "ITEM-A,,BLUE,2026-04-07,-5,50\n",
    )

    result = extract_lt_series(
        purchase_lt=purchase,
        production_lt=_empty_production(tmp_path),
        transfer_lt=_empty_transfer(tmp_path),
        assembly_lt=_empty_assembly(tmp_path),
        ile_summary=ile,
    )

    window = result.pairs.iloc[0]["demand_window"]
    assert isinstance(window, np.ndarray)
    assert window.shape == (7,)
    assert (window == 5.0).all()


def test_demand_window_zero_fills_missing_days(tmp_path):
    # Sparse demand inside the window: ILE row only on the second day. The
    # other days fill with 0.0 — the window is always length=LT, not the
    # count of populated buckets, so the bootstrap sampler can sum without
    # length checks.
    purchase = _write_purchase(
        tmp_path,
        "ITEM-A,,BLUE,V-001,2026-04-08,2026-04-15,2026-04-15,10,PR-0001\n",
    )
    ile = _write_ile(
        tmp_path,
        "ITEM-A,,BLUE,2026-04-02,-12,120\n",
    )

    result = extract_lt_series(
        purchase_lt=purchase,
        production_lt=_empty_production(tmp_path),
        transfer_lt=_empty_transfer(tmp_path),
        assembly_lt=_empty_assembly(tmp_path),
        ile_summary=ile,
    )

    window = result.pairs.iloc[0]["demand_window"]
    # Day offsets 0..6 → dates 2026-04-01..2026-04-07. Demand on 2026-04-02
    # = offset 1 = 12. Other offsets = 0.
    expected = np.array([0.0, 12.0, 0.0, 0.0, 0.0, 0.0, 0.0])
    assert np.array_equal(window, expected)


def test_demand_window_nets_returns_against_demand(tmp_path):
    # ADR 0006 explicitly: returns (positive ILE-Sale rows) net automatically
    # against demand. A day with -10 sale and +3 return nets to 7 demand.
    purchase = _write_purchase(
        tmp_path,
        "ITEM-A,,BLUE,V-001,2026-04-03,2026-04-10,2026-04-10,10,PR-0001\n",
    )
    ile = _write_ile(
        tmp_path,
        "ITEM-A,,BLUE,2026-04-01,-10,100\n",
        "ITEM-A,,BLUE,2026-04-01,3,0\n",
        "ITEM-A,,BLUE,2026-04-02,-4,40\n",
    )

    result = extract_lt_series(
        purchase_lt=purchase,
        production_lt=_empty_production(tmp_path),
        transfer_lt=_empty_transfer(tmp_path),
        assembly_lt=_empty_assembly(tmp_path),
        ile_summary=ile,
    )

    window = result.pairs.iloc[0]["demand_window"]
    # Window = [2026-04-01, 2026-04-02], 2 days (LT=7-day PO with trigger
    # 2026-04-03 → window [2026-03-27..2026-04-02] of length 7).
    # Last two offsets carry net 7 and 4; earlier days have no ILE → 0.
    assert window.shape == (7,)
    assert window[5] == 7.0  # 2026-04-01 = trigger - 2 days
    assert window[6] == 4.0  # 2026-04-02 = trigger - 1 day
    assert window[:5].sum() == 0.0


def test_demand_window_isolates_by_sku(tmp_path):
    # ITEM-A's window must NOT pull demand from ITEM-B at the same location,
    # nor from ITEM-A at a different location. SKU grain = (item, variant,
    # location) per ADR 0006.
    purchase = _write_purchase(
        tmp_path,
        "ITEM-A,,BLUE,V-001,2026-04-04,2026-04-11,2026-04-11,10,PR-0001\n",
    )
    ile = _write_ile(
        tmp_path,
        "ITEM-A,,BLUE,2026-04-01,-2,20\n",
        "ITEM-B,,BLUE,2026-04-02,-99,990\n",  # different item
        "ITEM-A,RED,BLUE,2026-04-03,-77,770\n",  # different variant
        "ITEM-A,,GREEN,2026-04-03,-55,550\n",  # different location
    )

    result = extract_lt_series(
        purchase_lt=purchase,
        production_lt=_empty_production(tmp_path),
        transfer_lt=_empty_transfer(tmp_path),
        assembly_lt=_empty_assembly(tmp_path),
        ile_summary=ile,
    )

    item_a = result.pairs[result.pairs["item_no"] == "ITEM-A"].iloc[0]
    window = item_a["demand_window"]
    # LT=7, trigger=2026-04-04 → window [2026-03-29..2026-04-03]; only
    # 2026-04-01 carries 2 units of demand for ITEM-A/BLUE.
    assert window.sum() == 2.0


def test_purchase_plan_to_receipt_kept_distinct_from_primary_lt(tmp_path):
    # ADR 0006: Plan-to-Receipt feeds the `Supplier reliability` reason
    # code, NOT the LTD bootstrap. The unified row carries both — primary
    # `lead_time_days` is Order-to-Receipt; `plan_to_receipt_days` rides
    # along as a sidecar field.
    purchase = _write_purchase(
        tmp_path,
        "ITEM-A,,BLUE,V-001,2026-04-01,2026-04-08,2026-04-05,10,PR-0001\n",
    )

    result = extract_lt_series(
        purchase_lt=purchase,
        production_lt=_empty_production(tmp_path),
        transfer_lt=_empty_transfer(tmp_path),
        assembly_lt=_empty_assembly(tmp_path),
        ile_summary=_write_ile(tmp_path),
    )

    row = result.pairs.iloc[0]
    assert row["lead_time_days"] == 7  # primary
    assert row["plan_to_receipt_days"] == 3  # secondary (late receipt)
    assert pd.isna(row["plan_to_actual_days"])  # production-only field


def test_production_plan_to_actual_kept_distinct_from_primary_lt(tmp_path):
    # ADR 0006 secondary: Plan-to-Actual = max(Output) - Header.Ending Date.
    # Late production by 3 days; primary LT (ILE pairing) is 7 days.
    production = _write_production(
        tmp_path,
        "PO-100,ITEM-A,,BLUE,consumption,2026-04-01,2026-03-30,2026-04-08,2026-04-05\n",
        "PO-100,ITEM-A,,BLUE,output,2026-04-08,2026-03-30,2026-04-08,2026-04-05\n",
    )

    result = extract_lt_series(
        purchase_lt=_empty_purchase(tmp_path),
        production_lt=production,
        transfer_lt=_empty_transfer(tmp_path),
        assembly_lt=_empty_assembly(tmp_path),
        ile_summary=_write_ile(tmp_path),
    )

    row = result.pairs.iloc[0]
    assert row["lead_time_days"] == 7  # primary
    assert row["plan_to_actual_days"] == 3  # secondary
    assert pd.isna(row["plan_to_receipt_days"])  # purchase-only field


def test_mixed_system_sku_keeps_both_historical_systems(tmp_path):
    # Issue #17 acceptance: an SKU that moved between Purchase and Production
    # replenishment has history under both systems. The unified series emits
    # one row per sample, each labelled with its source system — downstream
    # (slice #18 bootstrap) is responsible for filtering by current Item
    # state if desired.
    purchase = _write_purchase(
        tmp_path,
        "ITEM-A,,BLUE,V-001,2026-04-01,2026-04-08,2026-04-08,10,PR-0001\n",
    )
    production = _write_production(
        tmp_path,
        "PO-100,ITEM-A,,BLUE,consumption,2026-05-01,2026-04-28,2026-05-10,2026-05-10\n",
        "PO-100,ITEM-A,,BLUE,output,2026-05-10,2026-04-28,2026-05-10,2026-05-10\n",
    )

    result = extract_lt_series(
        purchase_lt=purchase,
        production_lt=production,
        transfer_lt=_empty_transfer(tmp_path),
        assembly_lt=_empty_assembly(tmp_path),
        ile_summary=_write_ile(tmp_path),
    )

    same_sku = result.pairs[result.pairs["item_no"] == "ITEM-A"]
    systems = set(same_sku["replenishment_system"])
    assert systems == {"purchase", "production"}
    assert len(same_sku) == 2


def test_cold_start_sku_returns_empty_pairs_for_that_sku(tmp_path):
    # Issue #17 acceptance: cold-start SKU — present in ILE history but no
    # LT samples in any extract — appears nowhere in the pairs series (the
    # bootstrap has nothing to sample). Existence is preserved via the
    # summary series (separate cycle).
    purchase = _write_purchase(
        tmp_path,
        "ITEM-A,,BLUE,V-001,2026-04-01,2026-04-08,2026-04-08,10,PR-0001\n",
    )
    ile = _write_ile(
        tmp_path,
        # ITEM-A has both an LT sample (above) and demand:
        "ITEM-A,,BLUE,2026-03-25,-5,50\n",
        # ITEM-COLD is in the ILE but has never been replenished (cold-start):
        "ITEM-COLD,,BLUE,2026-03-25,-2,20\n",
    )

    result = extract_lt_series(
        purchase_lt=purchase,
        production_lt=_empty_production(tmp_path),
        transfer_lt=_empty_transfer(tmp_path),
        assembly_lt=_empty_assembly(tmp_path),
        ile_summary=ile,
    )

    assert "ITEM-COLD" not in set(result.pairs["item_no"])
    assert "ITEM-A" in set(result.pairs["item_no"])


# ---- Per-SKU summary statistics -----------------------------------------
# Issue #17 acceptance: per-SKU mean(LT), p50/75/90/95, σ(LT), sample count.
# Quantiles use pandas/numpy linear interpolation (default), matching what
# downstream notebook reports rely on.


def test_summary_computes_basic_statistics_for_sku_with_samples(tmp_path):
    # Five purchase samples for ITEM-A with LTs 4,6,7,9,12 days. Stats:
    # mean=7.6, p50=7, σ (ddof=1)≈3.05, count=5.
    purchase = _write_purchase(
        tmp_path,
        "ITEM-A,,BLUE,V-001,2026-04-01,2026-04-05,2026-04-05,1,PR-1\n",
        "ITEM-A,,BLUE,V-001,2026-04-02,2026-04-08,2026-04-08,1,PR-2\n",
        "ITEM-A,,BLUE,V-001,2026-04-03,2026-04-10,2026-04-10,1,PR-3\n",
        "ITEM-A,,BLUE,V-001,2026-04-04,2026-04-13,2026-04-13,1,PR-4\n",
        "ITEM-A,,BLUE,V-001,2026-04-05,2026-04-17,2026-04-17,1,PR-5\n",
    )

    result = extract_lt_series(
        purchase_lt=purchase,
        production_lt=_empty_production(tmp_path),
        transfer_lt=_empty_transfer(tmp_path),
        assembly_lt=_empty_assembly(tmp_path),
        ile_summary=_write_ile(tmp_path),
    )

    assert len(result.summary) == 1
    row = result.summary.iloc[0]
    assert row["item_no"] == "ITEM-A"
    assert row["lt_count"] == 5
    assert row["lt_mean"] == 7.6
    assert row["lt_p50"] == 7.0
    assert row["lt_sigma"] == pytest.approx(3.04959, abs=1e-4)
    assert not bool(row["insufficient_data"])


def test_summary_p75_p90_p95_match_numpy_linear_interpolation(tmp_path):
    # Ten samples with LT = 1..10 → mean=5.5, p50=5.5, p75=7.75, p90=9.1, p95=9.55.
    purchase = _write_purchase(
        tmp_path,
        *(
            f"ITEM-A,,BLUE,V-001,2026-04-01,2026-04-{1 + i:02d},2026-04-{1 + i:02d},1,PR-{i}\n"
            for i in range(1, 11)
        ),
    )

    result = extract_lt_series(
        purchase_lt=purchase,
        production_lt=_empty_production(tmp_path),
        transfer_lt=_empty_transfer(tmp_path),
        assembly_lt=_empty_assembly(tmp_path),
        ile_summary=_write_ile(tmp_path),
    )

    row = result.summary.iloc[0]
    assert row["lt_p75"] == pytest.approx(7.75)
    assert row["lt_p90"] == pytest.approx(9.1)
    assert row["lt_p95"] == pytest.approx(9.55)


def test_summary_flags_cold_start_sku_with_insufficient_data(tmp_path):
    # ITEM-COLD is in the ILE summary (we know it exists) but has zero LT
    # samples. The summary row carries `insufficient_data=True` and the LT
    # stats are NaN — downstream pipeline applies the conservative default
    # α / Unclassified treatment.
    purchase = _write_purchase(
        tmp_path,
        "ITEM-A,,BLUE,V-001,2026-04-01,2026-04-08,2026-04-08,1,PR-1\n",
    )
    ile = _write_ile(
        tmp_path,
        "ITEM-A,,BLUE,2026-03-25,-5,50\n",
        "ITEM-COLD,,BLUE,2026-03-25,-2,20\n",
    )

    result = extract_lt_series(
        purchase_lt=purchase,
        production_lt=_empty_production(tmp_path),
        transfer_lt=_empty_transfer(tmp_path),
        assembly_lt=_empty_assembly(tmp_path),
        ile_summary=ile,
    )

    by_item = {row["item_no"]: row for _, row in result.summary.iterrows()}
    assert bool(by_item["ITEM-COLD"]["insufficient_data"]) is True
    assert by_item["ITEM-COLD"]["lt_count"] == 0
    assert pd.isna(by_item["ITEM-COLD"]["lt_mean"])
    assert bool(by_item["ITEM-A"]["insufficient_data"]) is False
    assert by_item["ITEM-A"]["lt_count"] == 1
    # Production ILE-primary: consumption 2026-04-01, output 2026-04-08 → LT
    # 7 days. The unified series carries `replenishment_system=production`
    # and `source=ile`, with the prod order number as `shared_sample_key`
    # so bootstrap can deduplicate multi-output samples (ADR 0006).
    production = _write_production(
        tmp_path,
        "PO-100,ITEM-A,,BLUE,consumption,2026-04-01,2026-03-30,2026-04-08,2026-04-07\n",
        "PO-100,ITEM-A,,BLUE,output,2026-04-08,2026-03-30,2026-04-08,2026-04-07\n",
    )
    ile = _write_ile(tmp_path)

    result = extract_lt_series(
        purchase_lt=_empty_purchase(tmp_path),
        production_lt=production,
        transfer_lt=_empty_transfer(tmp_path),
        assembly_lt=_empty_assembly(tmp_path),
        ile_summary=ile,
    )

    assert len(result.pairs) == 1
    row = result.pairs.iloc[0]
    assert row["lead_time_days"] == 7
    assert row["replenishment_system"] == "production"
    assert row["source"] == "ile"
    assert row["shared_sample_key"] == "PO-100"
    assert row["trigger_date"] == pd.Timestamp("2026-04-01")
