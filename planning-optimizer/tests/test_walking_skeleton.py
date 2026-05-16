"""Walking-skeleton smoke test for `bc_planning_optimizer.run`.

Drives the public interface only (no peeking at internal modules) so the test
survives the real-math swap in later slices.
"""

import json

from bc_planning_optimizer import run


def _load(output_path):
    return json.loads(output_path.read_text())


def test_run_writes_recommendations_json(synthetic_extract):
    output_path = run(synthetic_extract)

    assert output_path.exists(), "run() must produce a recommendations.json file"
    assert output_path.name == "recommendations.json"


def test_recommendation_carries_sku_triplet(synthetic_extract):
    output_path = run(synthetic_extract)
    payload = _load(output_path)

    assert len(payload["recommendations"]) == 1
    rec = payload["recommendations"][0]
    assert rec["item_no"] == "ITEM-A"
    assert rec["variant_code"] == ""
    assert rec["location_code"] == "BLUE"


def test_reorder_point_is_mean_demand_times_mean_lead_time(synthetic_extract):
    # fixture daily_demand = [10,20,30,40,50] → mean 30
    # fixture lead_time_days = [5,5,7,6,7]   → mean 6
    output_path = run(synthetic_extract)
    payload = _load(output_path)

    rec = payload["recommendations"][0]
    assert rec["reorder_point"] == 30.0 * 6.0


def test_safety_stock_is_half_reorder_point(synthetic_extract):
    output_path = run(synthetic_extract)
    payload = _load(output_path)

    rec = payload["recommendations"][0]
    assert rec["safety_stock"] == rec["reorder_point"] / 2


def test_multi_sku_extract_emits_independent_recommendations(tmp_path):
    extract = tmp_path / "multi.csv"
    extract.write_text(
        "item_no,variant_code,location_code,daily_demand,lead_time_days\n"
        "ITEM-A,,BLUE,10,5\n"
        "ITEM-A,,BLUE,20,5\n"
        "ITEM-B,RED,GREEN,40,3\n"
        "ITEM-B,RED,GREEN,60,7\n"
    )

    output_path = run(extract)
    payload = _load(output_path)

    by_sku = {
        (r["item_no"], r["variant_code"], r["location_code"]): r
        for r in payload["recommendations"]
    }
    assert set(by_sku) == {("ITEM-A", "", "BLUE"), ("ITEM-B", "RED", "GREEN")}

    a = by_sku[("ITEM-A", "", "BLUE")]
    assert a["reorder_point"] == 15.0 * 5.0  # mean(10,20) × mean(5,5)
    assert a["safety_stock"] == a["reorder_point"] / 2

    b = by_sku[("ITEM-B", "RED", "GREEN")]
    assert b["reorder_point"] == 50.0 * 5.0  # mean(40,60) × mean(3,7)
    assert b["safety_stock"] == b["reorder_point"] / 2
