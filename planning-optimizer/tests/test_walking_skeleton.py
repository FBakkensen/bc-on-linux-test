"""Walking-skeleton smoke test for `bc_planning_optimizer.run`.

Drives the public interface only (no peeking at internal modules) so the test
survives the real-math swap in later slices.
"""

import json

from bc_planning_optimizer import run


def _load(output_path):
    return json.loads(output_path.read_text())


def test_run_writes_recommendations_json(synthetic_ile_summary):
    output_path = run(synthetic_ile_summary)

    assert output_path.exists(), "run() must produce a recommendations.json file"
    assert output_path.name == "recommendations.json"


def test_recommendation_carries_sku_triplet(synthetic_ile_summary):
    output_path = run(synthetic_ile_summary)
    payload = _load(output_path)

    assert len(payload["recommendations"]) == 1
    rec = payload["recommendations"][0]
    assert rec["item_no"] == "ITEM-A"
    assert rec["variant_code"] == ""
    assert rec["location_code"] == "BLUE"


def test_reorder_point_uses_daily_demand_times_default_lead_time(synthetic_ile_summary):
    # Fixture: ITEM-A signed quantities [-10,-20,-30,-40,-50] across 5 daily
    # buckets → mean -30 → daily_demand 30. DEFAULT_LEAD_TIME_DAYS = 7 →
    # reorder_point = 30 × 7 = 210.
    output_path = run(synthetic_ile_summary)
    payload = _load(output_path)

    rec = payload["recommendations"][0]
    assert rec["reorder_point"] == 30.0 * 7.0


def test_safety_stock_is_half_reorder_point(synthetic_ile_summary):
    output_path = run(synthetic_ile_summary)
    payload = _load(output_path)

    rec = payload["recommendations"][0]
    assert rec["safety_stock"] == rec["reorder_point"] / 2


def test_positive_quantities_net_against_negative_demand(tmp_path):
    # ADR 0006: returns (positive ILE-Sale rows) net automatically against
    # demand at the SKU grain. Three demand buckets of -30 plus one return of
    # +15 → signed mean (-30·3 + 15) / 4 = -18.75 → daily_demand 18.75.
    extract = tmp_path / "ile_with_returns.csv"
    extract.write_text(
        "item_no,variant_code,location_code,posting_date,quantity\n"
        "ITEM-A,,BLUE,2026-05-01,-30\n"
        "ITEM-A,,BLUE,2026-05-02,-30\n"
        "ITEM-A,,BLUE,2026-05-03,-30\n"
        "ITEM-A,,BLUE,2026-05-04,15\n"
    )

    output_path = run(extract)
    payload = _load(output_path)
    rec = payload["recommendations"][0]
    assert rec["reorder_point"] == 18.75 * 7


def test_multi_sku_emits_independent_recommendations(tmp_path):
    extract = tmp_path / "multi_sku.csv"
    extract.write_text(
        "item_no,variant_code,location_code,posting_date,quantity\n"
        "ITEM-A,,BLUE,2026-05-01,-10\n"
        "ITEM-A,,BLUE,2026-05-02,-20\n"
        "ITEM-B,RED,GREEN,2026-05-01,-40\n"
        "ITEM-B,RED,GREEN,2026-05-02,-60\n"
    )

    output_path = run(extract)
    payload = _load(output_path)
    by_sku = {
        (r["item_no"], r["variant_code"], r["location_code"]): r for r in payload["recommendations"]
    }

    assert set(by_sku) == {("ITEM-A", "", "BLUE"), ("ITEM-B", "RED", "GREEN")}

    a = by_sku[("ITEM-A", "", "BLUE")]
    assert a["reorder_point"] == 15.0 * 7.0  # mean(-10,-20) = -15 → daily 15 → ROP 105
    assert a["safety_stock"] == a["reorder_point"] / 2

    b = by_sku[("ITEM-B", "RED", "GREEN")]
    assert b["reorder_point"] == 50.0 * 7.0  # mean(-40,-60) = -50 → daily 50 → ROP 350
    assert b["safety_stock"] == b["reorder_point"] / 2


def test_returns_exceeding_demand_clamp_daily_demand_to_zero(tmp_path):
    # Pathological SKU: more returns than sales in the window. Signed mean is
    # positive, but daily_demand must clamp at zero — a negative reorder
    # point is nonsense for the recommender.
    extract = tmp_path / "ile_returns_dominant.csv"
    extract.write_text(
        "item_no,variant_code,location_code,posting_date,quantity\n"
        "ITEM-A,,BLUE,2026-05-01,-5\n"
        "ITEM-A,,BLUE,2026-05-02,10\n"
    )

    output_path = run(extract)
    payload = _load(output_path)
    rec = payload["recommendations"][0]
    assert rec["reorder_point"] == 0
    assert rec["safety_stock"] == 0
