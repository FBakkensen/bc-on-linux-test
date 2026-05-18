"""End-to-end walking-skeleton entry point.

`run(extract_path)` reads an Item Ledger Entry summary CSV, derives naive
per-SKU recommendations, attaches ABC + Syntetos-Boylan classifier fields
per issue #16, and writes a `recommendations.json` file next to the input.
Real pipeline (forecaster → lead-time extractor → simulator → recommender)
lands in later slices.
"""

from __future__ import annotations

import json
import math
from pathlib import Path
from typing import Any, cast

import pandas as pd
from extracts.bc_files import read_ile_summary

from .classifier import ClassifierConfig, classify
from .recommender import SKU_COLUMNS, recommend

DEFAULT_LEAD_TIME_DAYS = 7
"""Placeholder lead-time used by the walking skeleton. The real bootstrap
(purchase-receipt date deltas, prod-order output-minus-consumption, transfer
source→dest, assembly posting-minus-starting per ADR 0006) lands alongside
the lead-time extract in a later slice."""


def run(
    extract_path: Path,
    *,
    config_path: Path | None = None,
    asof_date: pd.Timestamp | str | None = None,
) -> Path:
    """Read the ILE-summary CSV, write recommendations.json beside it, return that path.

    `config_path` points at a JSON setup file with `abc_cut_points`,
    `revenue_window_months`, `history_window_months`, and `strategic_skus`
    keys; absent keys take the ADR-default values. `asof_date` overrides the
    windowing anchor (defaults to `max(posting_date)` for deterministic
    fixture-driven tests).
    """
    extract_path = Path(extract_path)
    ile_summary = read_ile_summary(extract_path)
    config = _load_config(config_path)
    resolved_asof = _resolve_asof(asof_date, ile_summary)

    classifier_df = classify(ile_summary, asof_date=resolved_asof, config=config)
    observations = _aggregate_for_recommender(ile_summary, DEFAULT_LEAD_TIME_DAYS)
    recommendations = recommend(observations)
    enriched = _enrich_with_classifier(recommendations, classifier_df)

    output_path = extract_path.parent / "recommendations.json"
    output_path.write_text(json.dumps({"recommendations": enriched}))
    return output_path


def _load_config(config_path: Path | None) -> ClassifierConfig:
    if config_path is None:
        return ClassifierConfig()
    return ClassifierConfig.from_json(json.loads(Path(config_path).read_text()))


def _resolve_asof(
    asof_date: pd.Timestamp | str | None,
    ile_summary: pd.DataFrame,
) -> pd.Timestamp:
    if asof_date is not None:
        return pd.Timestamp(asof_date)
    if ile_summary.empty:
        return pd.Timestamp.utcnow().normalize()
    return pd.Timestamp(ile_summary["posting_date"].max())


def _aggregate_for_recommender(ile_summary: pd.DataFrame, lead_time_days: int) -> pd.DataFrame:
    """Roll signed ILE bucket quantities into per-SKU rows the recommender consumes.

    Daily demand is the mean signed bucket quantity, negated and clamped at zero —
    negatives are demand, positives are returns netting against it (ADR 0006).
    """
    grouped = ile_summary.groupby(SKU_COLUMNS, sort=False)
    rows = []
    for (item_no, variant_code, location_code), group in grouped:
        signed_mean = float(group["quantity"].mean())
        daily_demand = max(-signed_mean, 0.0)
        rows.append(
            {
                "item_no": item_no,
                "variant_code": variant_code,
                "location_code": location_code,
                "daily_demand": daily_demand,
                "lead_time_days": lead_time_days,
            },
        )
    return pd.DataFrame(rows)


def _enrich_with_classifier(
    recommendations: list[dict[str, Any]],
    classifier_df: pd.DataFrame,
) -> list[dict[str, Any]]:
    """Merge classifier columns onto each recommendation dict by SKU triplet."""
    classifier_rows = cast(
        "list[dict[str, Any]]",
        classifier_df.to_dict(orient="records"),
    )
    by_sku: dict[tuple[str, str, str], dict[str, Any]] = {
        (
            cast("str", row["item_no"]),
            cast("str", row["variant_code"]),
            cast("str", row["location_code"]),
        ): row
        for row in classifier_rows
    }
    enriched: list[dict[str, Any]] = []
    for rec in recommendations:
        key = (rec["item_no"], rec["variant_code"], rec["location_code"])
        row = by_sku.get(key)
        if row is None:
            enriched.append(rec)
            continue
        enriched.append(
            {
                **rec,
                "abc_class": str(row["abc_class"]),
                "demand_pattern_class": str(row["demand_pattern_class"]),
                "adi": _nan_to_none(float(row["adi"])),
                "cv_squared": _nan_to_none(float(row["cv_squared"])),
                "revenue_window_total": float(row["revenue_window_total"]),
                "is_strategic": bool(row["is_strategic"]),
            },
        )
    return enriched


def _nan_to_none(value: float) -> float | None:
    """JSON has no NaN; emit null instead so consumers don't choke on `NaN`."""
    return None if math.isnan(value) else value
