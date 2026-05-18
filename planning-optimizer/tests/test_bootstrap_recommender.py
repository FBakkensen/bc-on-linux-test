"""Bootstrap-LTD recommender tests driven through `bc_planning_optimizer.run`.

LT extracts ride alongside the ILE-summary CSV by file-name convention:
`purchase_lt.csv`, `production_lt.csv`, `transfer_lt.csv`, `assembly_lt.csv`.
Missing files default to empty (cold-start signal).
"""

from __future__ import annotations

from bc_planning_optimizer import run

from .conftest import load_recommendations, write_ile, write_purchase_lt


def test_bootstrap_recommendation_emits_numeric_rop_for_sku_with_lt_samples(tmp_path):
    # Single pair → every bootstrap draw is the same window sum, so ROP is
    # the constant 35 regardless of α and SS = ROP − mean(LTD) = 0.
    extract = write_ile(
        tmp_path,
        *(f"ITEM-A,,BLUE,2026-04-{1 + i:02d},-5,50\n" for i in range(7)),
    )
    write_purchase_lt(
        tmp_path,
        "ITEM-A,,BLUE,V-001,2026-04-08,2026-04-15,2026-04-15,1,PR-0001\n",
    )

    output_path = run(extract, asof_date="2026-05-01", seed=42)
    rec = load_recommendations(output_path)["recommendations"][0]

    assert rec["item_no"] == "ITEM-A"
    assert rec["reorder_point"] == 35.0
    assert rec["safety_stock"] == 0.0


def test_insufficient_data_sku_emits_null_recommendation_with_reason_code(tmp_path):
    extract = write_ile(tmp_path, "ITEM-COLD,,BLUE,2026-03-25,-2,20\n")

    output_path = run(extract, asof_date="2026-05-01", seed=42)
    rec = load_recommendations(output_path)["recommendations"][0]

    assert rec["item_no"] == "ITEM-COLD"
    assert rec["reorder_point"] is None
    assert rec["safety_stock"] is None
    assert rec["reason_code"] == "Insufficient data"


def test_all_zero_lead_time_samples_emit_zero_lead_time_reason_code(tmp_path):
    # Degenerate live-extract shape (observed in CRONUS): every Purchase
    # Receipt has `po_order_date == receipt_posting_date`, so every LT
    # sample is 0 days. The bootstrap would faithfully return ROP=0 — a
    # number the planner could mistake for "no buffer needed". Emit a
    # null recommendation + explicit reason instead.
    extract = write_ile(tmp_path, "ITEM-A,,BLUE,2026-04-01,-5,50\n")
    write_purchase_lt(
        tmp_path,
        "ITEM-A,,BLUE,V-001,2026-04-01,2026-04-01,2026-04-01,1,PR-0001\n",
        "ITEM-A,,BLUE,V-001,2026-04-02,2026-04-02,2026-04-02,1,PR-0002\n",
    )

    output_path = run(extract, asof_date="2026-05-01", seed=42)
    rec = load_recommendations(output_path)["recommendations"][0]

    assert rec["reorder_point"] is None
    assert rec["safety_stock"] is None
    assert rec["reason_code"] == "Zero lead time observed"


def test_a_class_sku_quantile_higher_than_c_class_sku_with_identical_samples(tmp_path):
    # Two SKUs share an identical LT-sample shape; only revenue differs. With
    # C-class α pushed down to the median, ROP(A @ 0.98) lands at the top
    # window (35), ROP(C @ 0.50) at the middle (21) — so α flows from ABC
    # class through config to the bootstrap quantile.
    ile_rows: list[str] = []
    purchase_rows: list[str] = []
    for sku, revenue_per_sale in (("ITEM-A", 10_000.0), ("ITEM-C", 100.0)):
        for sample_idx in range(1, 6):
            month = sample_idx
            ile_rows.extend(
                f"{sku},,BLUE,2026-{month:02d}-{d:02d},-{sample_idx},{revenue_per_sale}\n"
                for d in range(1, 8)
            )
            purchase_rows.append(
                f"{sku},,BLUE,V-001,2026-{month:02d}-08,2026-{month:02d}-15,"
                f"2026-{month:02d}-15,1,PR-{sku}-{sample_idx}\n",
            )
    extract = write_ile(tmp_path, *ile_rows)
    write_purchase_lt(tmp_path, *purchase_rows)
    config_path = tmp_path / "setup.json"
    config_path.write_text(
        '{"service_level_by_abc": {"A": 0.98, "B": 0.95, "C": 0.50, "Unclassified": 0.95}}',
    )

    output_path = run(
        extract,
        config_path=config_path,
        asof_date="2026-07-01",
        seed=42,
        n_draws=20_000,
    )
    by_sku = {r["item_no"]: r for r in load_recommendations(output_path)["recommendations"]}

    assert by_sku["ITEM-A"]["abc_class"] == "A"
    assert by_sku["ITEM-C"]["abc_class"] == "C"
    assert by_sku["ITEM-A"]["reorder_point"] > by_sku["ITEM-C"]["reorder_point"]


def test_same_seed_produces_identical_recommendations_json(tmp_path):
    extract = write_ile(
        tmp_path,
        "ITEM-A,,BLUE,2026-04-01,-3,30\n",
        "ITEM-A,,BLUE,2026-04-02,-7,70\n",
        "ITEM-A,,BLUE,2026-04-03,-2,20\n",
        "ITEM-A,,BLUE,2026-04-04,-9,90\n",
        "ITEM-A,,BLUE,2026-04-05,-4,40\n",
    )
    write_purchase_lt(
        tmp_path,
        "ITEM-A,,BLUE,V-001,2026-04-06,2026-04-11,2026-04-11,1,PR-1\n",
        "ITEM-A,,BLUE,V-001,2026-04-13,2026-04-20,2026-04-20,1,PR-2\n",
    )

    first = run(extract, asof_date="2026-05-01", seed=42, n_draws=2_000).read_text()
    second = run(extract, asof_date="2026-05-01", seed=42, n_draws=2_000).read_text()

    assert first == second


def test_intermittent_demand_rop_far_above_mean_ltd(tmp_path):
    # Intermittent demand: long runs of zeros with occasional spikes. The
    # 0.95-quantile lands on a high-demand window while the mean LTD is
    # dragged down by zero windows — so ROP / mean(LTD) is substantially > 1.
    extract = write_ile(
        tmp_path,
        "ITEM-A,,BLUE,2026-01-01,-100,1000\n",
        "ITEM-A,,BLUE,2026-01-15,-100,1000\n",
        "ITEM-A,,BLUE,2026-02-01,-100,1000\n",
        "ITEM-A,,BLUE,2026-02-15,-100,1000\n",
    )
    write_purchase_lt(
        tmp_path,
        "ITEM-A,,BLUE,V-001,2026-01-02,2026-01-09,2026-01-09,1,PR-1\n",
        "ITEM-A,,BLUE,V-001,2026-01-08,2026-01-15,2026-01-15,1,PR-2\n",
        "ITEM-A,,BLUE,V-001,2026-01-10,2026-01-17,2026-01-17,1,PR-3\n",
        "ITEM-A,,BLUE,V-001,2026-01-12,2026-01-19,2026-01-19,1,PR-4\n",
        "ITEM-A,,BLUE,V-001,2026-01-13,2026-01-20,2026-01-20,1,PR-5\n",
    )

    output_path = run(extract, asof_date="2026-03-01", seed=42, n_draws=20_000)
    rec = load_recommendations(output_path)["recommendations"][0]

    assert rec["reorder_point"] is not None
    assert rec["reorder_point"] >= 100.0


def test_bootstrap_returns_non_negative_when_closed_form_would_be_negative(tmp_path):
    # The closed-form ROP `μ_D·μ_L − z_α·σ_LTD` can underflow on slow movers;
    # the bootstrap is non-negative by construction (sum of non-negative
    # demand windows), so every quantile is ≥ 0.
    extract = write_ile(tmp_path, "ITEM-A,,BLUE,2026-04-01,-1,5\n")
    write_purchase_lt(
        tmp_path,
        "ITEM-A,,BLUE,V-001,2026-04-02,2026-04-04,2026-04-04,1,PR-1\n",
        "ITEM-A,,BLUE,V-001,2026-04-03,2026-04-05,2026-04-05,1,PR-2\n",
    )

    output_path = run(extract, asof_date="2026-05-01", seed=42, n_draws=2_000)
    rec = load_recommendations(output_path)["recommendations"][0]

    assert rec["reorder_point"] >= 0.0
    assert rec["safety_stock"] >= 0.0


def test_smooth_demand_rop_close_to_mean_ltd(tmp_path):
    # Flat demand + constant LT → every bootstrap draw is identical, so ROP
    # collapses to mean LTD and SS to zero.
    extract = write_ile(
        tmp_path,
        *(
            f"ITEM-A,,BLUE,2025-{m:02d}-{d:02d},-5,50\n"
            for m in range(10, 13)
            for d in range(1, 29)
        ),
        *(f"ITEM-A,,BLUE,2026-{m:02d}-{d:02d},-5,50\n" for m in range(1, 5) for d in range(1, 29)),
    )
    write_purchase_lt(
        tmp_path,
        "ITEM-A,,BLUE,V-001,2026-01-08,2026-01-15,2026-01-15,1,PR-1\n",
        "ITEM-A,,BLUE,V-001,2026-02-08,2026-02-15,2026-02-15,1,PR-2\n",
        "ITEM-A,,BLUE,V-001,2026-03-08,2026-03-15,2026-03-15,1,PR-3\n",
    )

    output_path = run(extract, asof_date="2026-05-01", seed=42, n_draws=2_000)
    rec = load_recommendations(output_path)["recommendations"][0]

    assert rec["reorder_point"] == 35.0
    assert rec["safety_stock"] == 0.0
