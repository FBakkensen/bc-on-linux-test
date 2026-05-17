"""End-to-end walking-skeleton entry point.

`run(extract_path)` reads an Item Ledger Entry summary CSV, derives naive
per-SKU recommendations, and writes a `recommendations.json` file next to the
input. Real pipeline (classifier → forecaster → lead-time extractor →
simulator → recommender) lands in later slices.
"""

import json
from pathlib import Path

import pandas as pd
from extracts.bc_files import read_ile_summary

from .recommender import SKU_COLUMNS, recommend

DEFAULT_LEAD_TIME_DAYS = 7
"""Placeholder lead-time used by the walking skeleton. The real bootstrap
(purchase-receipt date deltas, prod-order output-minus-consumption, transfer
source→dest, assembly posting-minus-starting per ADR 0006) lands alongside
the lead-time extract in a later slice."""


def run(extract_path: Path) -> Path:
    """Read the ILE-summary CSV, write recommendations.json beside it, return that path."""
    extract_path = Path(extract_path)
    ile_summary = read_ile_summary(extract_path)
    observations = _aggregate_for_recommender(ile_summary, DEFAULT_LEAD_TIME_DAYS)
    recommendations = recommend(observations)

    output_path = extract_path.parent / "recommendations.json"
    output_path.write_text(json.dumps({"recommendations": recommendations}))
    return output_path


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
            }
        )
    return pd.DataFrame(rows)
