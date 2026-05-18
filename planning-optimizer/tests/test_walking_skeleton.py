"""Smoke tests for `bc_planning_optimizer.run` after the bootstrap LTD swap.

End-to-end shape + presence of the public output, not the specific math
behind ROP / SS (covered in `test_bootstrap_recommender` and `test_simulator`).
"""

from __future__ import annotations

from bc_planning_optimizer import run

from .conftest import ILE_HEADER, PURCHASE_LT_HEADER, load_recommendations


def test_run_writes_recommendations_json(synthetic_ile_summary):
    output_path = run(synthetic_ile_summary)

    assert output_path.exists(), "run() must produce a recommendations.json file"
    assert output_path.name == "recommendations.json"


def test_recommendation_carries_sku_triplet(synthetic_ile_summary):
    output_path = run(synthetic_ile_summary)
    payload = load_recommendations(output_path)

    assert len(payload["recommendations"]) == 1
    rec = payload["recommendations"][0]
    assert rec["item_no"] == "ITEM-A"
    assert rec["variant_code"] == ""
    assert rec["location_code"] == "BLUE"


def test_multi_sku_emits_independent_recommendations(tmp_path):
    extract = tmp_path / "multi_sku.csv"
    extract.write_text(
        ILE_HEADER
        + "".join(f"ITEM-A,,BLUE,2026-04-{1 + i:02d},-2,20\n" for i in range(7))
        + "".join(f"ITEM-B,RED,GREEN,2026-04-{1 + i:02d},-6,60\n" for i in range(7)),
    )
    (tmp_path / "purchase_lt.csv").write_text(
        PURCHASE_LT_HEADER
        + "ITEM-A,,BLUE,V-001,2026-04-08,2026-04-15,2026-04-15,1,PR-A\n"
        + "ITEM-B,RED,GREEN,V-002,2026-04-08,2026-04-15,2026-04-15,1,PR-B\n",
    )

    output_path = run(extract, asof_date="2026-05-01", seed=42, n_draws=1_000)
    payload = load_recommendations(output_path)
    by_sku = {
        (r["item_no"], r["variant_code"], r["location_code"]): r for r in payload["recommendations"]
    }

    assert set(by_sku) == {("ITEM-A", "", "BLUE"), ("ITEM-B", "RED", "GREEN")}
    for rec in by_sku.values():
        assert rec["reorder_point"] is not None
        assert rec["safety_stock"] is not None
        assert rec["reorder_point"] >= 0.0
        assert rec["safety_stock"] >= 0.0


def test_sku_without_lt_samples_emits_null_recommendation(tmp_path):
    extract = tmp_path / "no_lt.csv"
    extract.write_text(ILE_HEADER + "ITEM-COLD,,BLUE,2026-03-25,-2,20\n")

    output_path = run(extract, asof_date="2026-05-01")
    rec = load_recommendations(output_path)["recommendations"][0]

    assert rec["item_no"] == "ITEM-COLD"
    assert rec["reorder_point"] is None
    assert rec["safety_stock"] is None
    assert rec["reason_code"] == "Insufficient data"
