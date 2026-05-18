"""ABC + Syntetos-Boylan classifier tests driven through `bc_planning_optimizer.run`.

Per CLAUDE.md, math-seam tests drive the public `run` interface only — they
must survive the bootstrap-LTD / SBA / AutoETS / simulator swap without
rewriting. The new fields per issue #16 are `abc_class`, `demand_pattern_class`,
`adi`, `cv_squared`, `revenue_window_total`, `is_strategic`.
"""

import json
from pathlib import Path
from typing import Any

from bc_planning_optimizer import run


def _load(output_path: Path) -> dict[str, Any]:
    payload: dict[str, Any] = json.loads(output_path.read_text())
    return payload


def test_recommendation_carries_classifier_fields(tmp_path):
    extract = tmp_path / "ile.csv"
    extract.write_text(
        "item_no,variant_code,location_code,posting_date,quantity,sales_amount\n"
        "ITEM-A,,BLUE,2026-05-01,-10,1000\n"
        "ITEM-A,,BLUE,2026-05-02,-20,2000\n",
    )

    output_path = run(extract)
    rec = _load(output_path)["recommendations"][0]

    for field in (
        "abc_class",
        "demand_pattern_class",
        "adi",
        "cv_squared",
        "revenue_window_total",
        "is_strategic",
    ):
        assert field in rec, f"missing {field}"


def test_abc_default_cut_points_partition_three_sku_revenue(tmp_path):
    # Three SKUs with revenues 700 / 200 / 100. Under defaults A=70/B=20/C=10:
    # cumulative shares 0.70, 0.90, 1.00 → A / B / C respectively.
    extract = tmp_path / "ile.csv"
    extract.write_text(
        "item_no,variant_code,location_code,posting_date,quantity,sales_amount\n"
        "ITEM-A,,BLUE,2026-05-01,-1,700\n"
        "ITEM-B,,BLUE,2026-05-01,-1,200\n"
        "ITEM-C,,BLUE,2026-05-01,-1,100\n",
    )

    output_path = run(extract)
    by_sku = {r["item_no"]: r for r in _load(output_path)["recommendations"]}

    assert by_sku["ITEM-A"]["abc_class"] == "A"
    assert by_sku["ITEM-B"]["abc_class"] == "B"
    assert by_sku["ITEM-C"]["abc_class"] == "C"
    assert by_sku["ITEM-A"]["revenue_window_total"] == 700
    assert by_sku["ITEM-B"]["revenue_window_total"] == 200
    assert by_sku["ITEM-C"]["revenue_window_total"] == 100


def test_abc_custom_cut_points_via_setup_config(tmp_path):
    # Config tightens to A=50% / B=30% / C=20%. Revenues 500/300/200 total 1000;
    # walking sorted-desc, prev-cumulative is 0 / 500 / 800. Thresholds 500 / 800.
    # → ITEM-A (prev=0<500) A; ITEM-B (prev=500≮500) B; ITEM-C (prev=800≮800) C.
    extract = tmp_path / "ile.csv"
    extract.write_text(
        "item_no,variant_code,location_code,posting_date,quantity,sales_amount\n"
        "ITEM-A,,BLUE,2026-05-01,-1,500\n"
        "ITEM-B,,BLUE,2026-05-01,-1,300\n"
        "ITEM-C,,BLUE,2026-05-01,-1,200\n",
    )
    config_path = tmp_path / "setup.json"
    config_path.write_text(
        '{"abc_cut_points": {"A": 0.5, "B": 0.3, "C": 0.2}}',
    )

    output_path = run(extract, config_path=config_path)
    by_sku = {r["item_no"]: r for r in _load(output_path)["recommendations"]}

    assert by_sku["ITEM-A"]["abc_class"] == "A"
    assert by_sku["ITEM-B"]["abc_class"] == "B"
    assert by_sku["ITEM-C"]["abc_class"] == "C"


def test_abc_unclassified_for_sku_without_posted_revenue(tmp_path):
    # ITEM-NEW has only a positive (returns) row in window — no negative ILE
    # rows means no posted-sales revenue, which per ADR 0005 maps to
    # 'Unclassified' rather than silently dropping into class C.
    extract = tmp_path / "ile.csv"
    extract.write_text(
        "item_no,variant_code,location_code,posting_date,quantity,sales_amount\n"
        "ITEM-A,,BLUE,2026-05-01,-10,1000\n"
        "ITEM-NEW,,BLUE,2026-05-01,5,0\n",
    )

    output_path = run(extract)
    by_sku = {r["item_no"]: r for r in _load(output_path)["recommendations"]}

    assert by_sku["ITEM-A"]["abc_class"] == "A"
    assert by_sku["ITEM-NEW"]["abc_class"] == "Unclassified"
    assert by_sku["ITEM-NEW"]["revenue_window_total"] == 0


def test_strategic_flag_pins_low_revenue_sku_to_class_a(tmp_path):
    # ITEM-LOW would otherwise fall to C under default cuts; listing it
    # strategic forces class A regardless of rank per ADR 0005.
    extract = tmp_path / "ile.csv"
    extract.write_text(
        "item_no,variant_code,location_code,posting_date,quantity,sales_amount\n"
        "ITEM-A,,BLUE,2026-05-01,-1,700\n"
        "ITEM-B,,BLUE,2026-05-01,-1,200\n"
        "ITEM-LOW,,BLUE,2026-05-01,-1,100\n",
    )
    config_path = tmp_path / "setup.json"
    config_path.write_text('{"strategic_skus": [["ITEM-LOW", "", "BLUE"]]}')

    output_path = run(extract, config_path=config_path)
    by_sku = {r["item_no"]: r for r in _load(output_path)["recommendations"]}

    assert by_sku["ITEM-LOW"]["abc_class"] == "A"
    assert by_sku["ITEM-LOW"]["is_strategic"] is True
    assert by_sku["ITEM-A"]["is_strategic"] is False


def test_strategic_flag_pins_unclassified_sku_to_class_a(tmp_path):
    # Strategic-but-no-revenue SKU should still pin to A — overrides
    # 'Unclassified' too, not just rank-based assignments.
    extract = tmp_path / "ile.csv"
    extract.write_text(
        "item_no,variant_code,location_code,posting_date,quantity,sales_amount\n"
        "ITEM-NEW,,BLUE,2026-05-01,5,0\n",
    )
    config_path = tmp_path / "setup.json"
    config_path.write_text('{"strategic_skus": [["ITEM-NEW", "", "BLUE"]]}')

    output_path = run(extract, config_path=config_path)
    by_sku = {r["item_no"]: r for r in _load(output_path)["recommendations"]}

    assert by_sku["ITEM-NEW"]["abc_class"] == "A"
    assert by_sku["ITEM-NEW"]["is_strategic"] is True


def test_revenue_window_excludes_rows_before_window(tmp_path):
    # 3-month window with asof 2026-05-01 → window-start 2026-02-01.
    # Old row at 2025-12-01 contributes 999 but is pre-window and dropped.
    # New row at 2026-04-01 contributes 100 — that's the only revenue.
    extract = tmp_path / "ile.csv"
    extract.write_text(
        "item_no,variant_code,location_code,posting_date,quantity,sales_amount\n"
        "ITEM-A,,BLUE,2025-12-01,-50,999\n"
        "ITEM-A,,BLUE,2026-04-01,-10,100\n",
    )
    config_path = tmp_path / "setup.json"
    config_path.write_text('{"revenue_window_months": 3}')

    output_path = run(extract, config_path=config_path, asof_date="2026-05-01")
    rec = _load(output_path)["recommendations"][0]

    assert rec["revenue_window_total"] == 100


# ---- Syntetos-Boylan quadrants ------------------------------------------
# Fixtures span > 6 months of history (asof 2026-05-01 → history floor
# 2025-11-01) so the cold-start guard doesn't fire. The first-seen date is
# 2025-10-31 in every quadrant fixture.


def test_demand_pattern_smooth(tmp_path):
    # Daily -10 across consecutive days → ADI=1.0 (<1.32), CV²=0 (<0.49).
    extract = tmp_path / "ile.csv"
    extract.write_text(
        "item_no,variant_code,location_code,posting_date,quantity,sales_amount\n"
        "ITEM-A,,BLUE,2025-10-31,-10,1\n"
        "ITEM-A,,BLUE,2025-11-01,-10,1\n"
        "ITEM-A,,BLUE,2025-11-02,-10,1\n"
        "ITEM-A,,BLUE,2025-11-03,-10,1\n",
    )

    output_path = run(extract, asof_date="2026-05-01")
    rec = _load(output_path)["recommendations"][0]

    assert rec["demand_pattern_class"] == "Smooth"
    assert rec["adi"] == 1.0
    assert rec["cv_squared"] == 0.0


def test_demand_pattern_intermittent(tmp_path):
    # Two-day gap between same-size buckets → ADI=2.0 (≥1.32), CV²=0 (<0.49).
    extract = tmp_path / "ile.csv"
    extract.write_text(
        "item_no,variant_code,location_code,posting_date,quantity,sales_amount\n"
        "ITEM-A,,BLUE,2025-10-31,-10,1\n"
        "ITEM-A,,BLUE,2025-11-02,-10,1\n"
        "ITEM-A,,BLUE,2025-11-04,-10,1\n",
    )

    output_path = run(extract, asof_date="2026-05-01")
    rec = _load(output_path)["recommendations"][0]

    assert rec["demand_pattern_class"] == "Intermittent"
    assert rec["adi"] == 2.0
    assert rec["cv_squared"] == 0.0


def test_demand_pattern_erratic(tmp_path):
    # Daily buckets, alternating tiny/huge magnitudes → ADI=1.0 (<1.32),
    # CV²≈1.3 (≥0.49). Demand sizes [1,100,1,100] mean 50.5, stdev ≈ 57.16.
    extract = tmp_path / "ile.csv"
    extract.write_text(
        "item_no,variant_code,location_code,posting_date,quantity,sales_amount\n"
        "ITEM-A,,BLUE,2025-10-31,-1,1\n"
        "ITEM-A,,BLUE,2025-11-01,-100,1\n"
        "ITEM-A,,BLUE,2025-11-02,-1,1\n"
        "ITEM-A,,BLUE,2025-11-03,-100,1\n",
    )

    output_path = run(extract, asof_date="2026-05-01")
    rec = _load(output_path)["recommendations"][0]

    assert rec["demand_pattern_class"] == "Erratic"
    assert rec["adi"] == 1.0
    assert rec["cv_squared"] >= 0.49


def test_demand_pattern_lumpy(tmp_path):
    # Sparse + variable: gaps of 2/3/2 days with magnitudes [1,100,1,100].
    # ADI = (2+3+2)/3 ≈ 2.33 (≥1.32). CV² as before (≥0.49). → Lumpy.
    extract = tmp_path / "ile.csv"
    extract.write_text(
        "item_no,variant_code,location_code,posting_date,quantity,sales_amount\n"
        "ITEM-A,,BLUE,2025-10-31,-1,1\n"
        "ITEM-A,,BLUE,2025-11-02,-100,1\n"
        "ITEM-A,,BLUE,2025-11-05,-1,1\n"
        "ITEM-A,,BLUE,2025-11-07,-100,1\n",
    )

    output_path = run(extract, asof_date="2026-05-01")
    rec = _load(output_path)["recommendations"][0]

    assert rec["demand_pattern_class"] == "Lumpy"
    assert rec["adi"] >= 1.32
    assert rec["cv_squared"] >= 0.49


def test_demand_pattern_insufficient_data_under_six_months(tmp_path):
    # First-seen 2026-03-01 with asof 2026-05-01 → 2 months of history,
    # below the 6-month default floor. ADI/CV² are computable but the
    # cold-start guard wins per ADR 0006 / issue #16.
    extract = tmp_path / "ile.csv"
    extract.write_text(
        "item_no,variant_code,location_code,posting_date,quantity,sales_amount\n"
        "ITEM-NEW,,BLUE,2026-03-01,-10,1\n"
        "ITEM-NEW,,BLUE,2026-03-02,-10,1\n"
        "ITEM-NEW,,BLUE,2026-03-03,-10,1\n",
    )

    output_path = run(extract, asof_date="2026-05-01")
    rec = _load(output_path)["recommendations"][0]

    assert rec["demand_pattern_class"] == "Insufficient data"


def test_demand_pattern_insufficient_data_when_too_few_buckets(tmp_path):
    # 6+ months span but only one non-zero bucket → ADI undefined → falls
    # back to Insufficient. Catches the degenerate-history edge case so
    # downstream forecaster dispatch never sees NaN ADI as 'Smooth'.
    extract = tmp_path / "ile.csv"
    extract.write_text(
        "item_no,variant_code,location_code,posting_date,quantity,sales_amount\n"
        "ITEM-A,,BLUE,2025-10-31,-10,1\n",
    )

    output_path = run(extract, asof_date="2026-05-01")
    rec = _load(output_path)["recommendations"][0]

    assert rec["demand_pattern_class"] == "Insufficient data"
    assert rec["adi"] is None
    assert rec["cv_squared"] is None
