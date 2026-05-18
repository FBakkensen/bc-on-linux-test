"""ABC classification and Syntetos-Boylan demand-pattern classification.

Pure functions over a demand DataFrame. Public surface is `classify`; tests
exercise it through `bc_planning_optimizer.run` per CLAUDE.md so the seam
survives later math swaps (real bootstrap-LTD, SBA / AutoETS dispatch).
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import TYPE_CHECKING, Any, cast

import numpy as np
import pandas as pd

from .recommender import SKU_COLUMNS

if TYPE_CHECKING:
    from collections.abc import Iterable

ABC_DEFAULT_CUT_POINTS: dict[str, float] = {"A": 0.70, "B": 0.20, "C": 0.10}
DEFAULT_REVENUE_WINDOW_MONTHS = 12
DEFAULT_HISTORY_WINDOW_MONTHS = 6

SERVICE_LEVEL_DEFAULTS: dict[str, float] = {
    "A": 0.98,
    "B": 0.95,
    "C": 0.90,
    "Unclassified": 0.95,
}

SB_ADI_THRESHOLD = 1.32
SB_CV2_THRESHOLD = 0.49
MIN_SAMPLES_FOR_DISPERSION = 2

ABC_A = "A"
ABC_B = "B"
ABC_C = "C"
ABC_UNCLASSIFIED = "Unclassified"
PATTERN_SMOOTH = "Smooth"
PATTERN_INTERMITTENT = "Intermittent"
PATTERN_ERRATIC = "Erratic"
PATTERN_LUMPY = "Lumpy"
PATTERN_INSUFFICIENT = "Insufficient data"


@dataclass(frozen=True)
class ClassifierConfig:
    """Setup config governing both classifiers.

    Defaults match ADR 0005 (70/20/10 cuts, 12-month window) and ADR 0006
    (Syntetos-Boylan 1.32 / 0.49 thresholds, 6-month history floor).
    """

    abc_cut_points: dict[str, float] = field(
        default_factory=lambda: dict(ABC_DEFAULT_CUT_POINTS),
    )
    revenue_window_months: int = DEFAULT_REVENUE_WINDOW_MONTHS
    history_window_months: int = DEFAULT_HISTORY_WINDOW_MONTHS
    strategic_skus: frozenset[tuple[str, str, str]] = frozenset()
    service_level_by_abc: dict[str, float] = field(
        default_factory=lambda: dict(SERVICE_LEVEL_DEFAULTS),
    )

    @classmethod
    def from_json(cls, payload: dict[str, Any]) -> ClassifierConfig:
        """Build a config from the parsed JSON payload, applying defaults for missing keys."""
        strategic_raw: Iterable[Any] = payload.get("strategic_skus", ())
        strategic = frozenset(
            (str(item), str(variant), str(loc)) for item, variant, loc in strategic_raw
        )
        # A custom map overrides only the keys it specifies; missing classes
        # keep ADR 0005 defaults rather than falling out of the lookup.
        service_levels = dict(SERVICE_LEVEL_DEFAULTS)
        service_levels.update(payload.get("service_level_by_abc", {}))
        return cls(
            abc_cut_points=dict(payload.get("abc_cut_points", ABC_DEFAULT_CUT_POINTS)),
            revenue_window_months=int(
                payload.get("revenue_window_months", DEFAULT_REVENUE_WINDOW_MONTHS),
            ),
            history_window_months=int(
                payload.get("history_window_months", DEFAULT_HISTORY_WINDOW_MONTHS),
            ),
            strategic_skus=strategic,
            service_level_by_abc=service_levels,
        )


def classify(
    ile_summary: pd.DataFrame,
    *,
    asof_date: pd.Timestamp,
    config: ClassifierConfig,
) -> pd.DataFrame:
    """Return per-SKU classifier rows.

    Columns: SKU triplet plus `abc_class`, `demand_pattern_class`, `adi`,
    `cv_squared`, `revenue_window_total`, `is_strategic`. One row per
    `(item_no, variant_code, location_code)` present in `ile_summary`.
    """
    if ile_summary.empty:
        return _empty_classifier_frame()

    revenue = _revenue_per_sku(ile_summary, asof_date, config.revenue_window_months)
    abc = _assign_abc(revenue, config.abc_cut_points, config.strategic_skus)

    pattern = _demand_pattern_per_sku(
        ile_summary,
        asof_date=asof_date,
        history_window_months=config.history_window_months,
    )

    return abc.merge(pattern, on=SKU_COLUMNS, how="outer")


def _empty_classifier_frame() -> pd.DataFrame:
    return pd.DataFrame(
        {
            "item_no": pd.Series(dtype="string"),
            "variant_code": pd.Series(dtype="string"),
            "location_code": pd.Series(dtype="string"),
            "abc_class": pd.Series(dtype="string"),
            "demand_pattern_class": pd.Series(dtype="string"),
            "adi": pd.Series(dtype="float64"),
            "cv_squared": pd.Series(dtype="float64"),
            "revenue_window_total": pd.Series(dtype="float64"),
            "is_strategic": pd.Series(dtype="bool"),
        },
    )


def _revenue_per_sku(
    ile_summary: pd.DataFrame,
    asof_date: pd.Timestamp,
    window_months: int,
) -> pd.DataFrame:
    """Sum posted sales value per SKU over the configured window.

    Sales-class rows are negative-quantity ILE rows (sales, consumption,
    negative adjustments, source-side transfers per ADR 0006). Their
    `sales_amount` is what posted to revenue. Rows outside
    `(asof_date - window, asof_date]` are excluded.
    """
    window_start = asof_date - pd.DateOffset(months=window_months)
    in_window = ile_summary[
        (ile_summary["posting_date"] > window_start)
        & (ile_summary["posting_date"] <= asof_date)
        & (ile_summary["quantity"] < 0)
    ]
    all_skus = ile_summary[SKU_COLUMNS].drop_duplicates().reset_index(drop=True)
    if in_window.empty:
        all_skus["revenue_window_total"] = 0.0
        return all_skus
    grouped = in_window.groupby(SKU_COLUMNS, as_index=False).agg(
        revenue_window_total=("sales_amount", "sum"),
    )
    merged = all_skus.merge(grouped, on=SKU_COLUMNS, how="left")
    merged["revenue_window_total"] = merged["revenue_window_total"].fillna(0.0)
    return merged


def _assign_abc(
    revenue: pd.DataFrame,
    cut_points: dict[str, float],
    strategic_skus: frozenset[tuple[str, str, str]],
) -> pd.DataFrame:
    """Rank SKUs by descending revenue, slice into A/B/C by cumulative share.

    Defaults A=70 / B=20 / C=10 (ADR 0005). SKUs with zero / negative window
    revenue land in 'Unclassified'. Strategic SKUs pin to A regardless of
    rank.
    """
    idx = pd.MultiIndex.from_frame(revenue[SKU_COLUMNS])
    revenue = revenue.assign(is_strategic=idx.isin(strategic_skus))

    earning = revenue[revenue["revenue_window_total"] > 0].copy()
    no_revenue = revenue[revenue["revenue_window_total"] <= 0].copy()
    no_revenue["abc_class"] = ABC_UNCLASSIFIED

    if earning.empty:
        out = no_revenue
    else:
        total = earning["revenue_window_total"].sum()
        earning = earning.sort_values(
            "revenue_window_total",
            ascending=False,
        ).reset_index(drop=True)
        revenues = earning["revenue_window_total"].to_numpy()
        # Assign by cumulative share AT THE PREVIOUS row, not the current one,
        # so the boundary SKU that pushes cumulative across a cut still joins
        # the higher class — that's what makes a sole revenue earner land in A.
        prev_cum = revenues.cumsum() - revenues
        a_threshold = total * cut_points[ABC_A]
        b_threshold = total * (cut_points[ABC_A] + cut_points[ABC_B])
        epsilon = total * 1e-9
        earning["abc_class"] = np.where(
            prev_cum < a_threshold - epsilon,
            ABC_A,
            np.where(prev_cum < b_threshold - epsilon, ABC_B, ABC_C),
        )
        out = pd.concat([earning, no_revenue], ignore_index=True)

    out.loc[out["is_strategic"], "abc_class"] = ABC_A
    return out[[*SKU_COLUMNS, "revenue_window_total", "is_strategic", "abc_class"]]


def _demand_pattern_per_sku(
    ile_summary: pd.DataFrame,
    *,
    asof_date: pd.Timestamp,
    history_window_months: int,
) -> pd.DataFrame:
    """Compute ADI / CV² per SKU and dispatch to the Syntetos-Boylan quadrant.

    Daily bucket = one `posting_date` row per SKU. Non-zero buckets are those
    whose net quantity is negative (demand outweighs returns). ADI = mean
    gap in days between successive non-zero bucket dates. CV² = squared
    coefficient of variation of non-zero demand magnitudes.

    Cold-start (first-seen date is within `history_window_months` of
    `asof_date`) maps to 'Insufficient data' regardless of ADI / CV².
    """
    history_floor = asof_date - pd.DateOffset(months=history_window_months)
    daily = ile_summary.groupby([*SKU_COLUMNS, "posting_date"], sort=False, as_index=False)[
        "quantity"
    ].sum()
    first_seen = cast(
        "dict[tuple[Any, Any, Any], pd.Timestamp]",
        ile_summary.groupby(SKU_COLUMNS, sort=False)["posting_date"].min().to_dict(),
    )

    rows: list[dict[str, Any]] = []
    for (item_no, variant_code, location_code), group in daily.groupby(SKU_COLUMNS, sort=False):
        non_zero = group[group["quantity"] < 0]
        demand_sizes = (-non_zero["quantity"]).to_numpy(dtype="float64")

        adi = _compute_adi(list(non_zero["posting_date"]))
        cv2 = _compute_cv_squared(demand_sizes)

        first = first_seen[item_no, variant_code, location_code]
        pattern = PATTERN_INSUFFICIENT if first > history_floor else _sba_quadrant(adi, cv2)

        rows.append(
            {
                "item_no": item_no,
                "variant_code": variant_code,
                "location_code": location_code,
                "adi": adi,
                "cv_squared": cv2,
                "demand_pattern_class": pattern,
            },
        )

    return pd.DataFrame(rows)


def _compute_adi(non_zero_dates: list[pd.Timestamp]) -> float:
    """Mean day-gap between successive non-zero buckets; NaN when < 2 buckets."""
    if len(non_zero_dates) < MIN_SAMPLES_FOR_DISPERSION:
        return float("nan")
    sorted_dates = sorted(non_zero_dates)
    gaps = [(sorted_dates[i] - sorted_dates[i - 1]).days for i in range(1, len(sorted_dates))]
    return float(np.mean(gaps))


def _compute_cv_squared(demand_sizes: np.ndarray) -> float:
    """CV² of non-zero demand sizes; NaN if < 2 samples or zero mean."""
    if demand_sizes.size < MIN_SAMPLES_FOR_DISPERSION:
        return float("nan")
    mean = demand_sizes.mean()
    if mean == 0:
        return float("nan")
    return float((demand_sizes.std(ddof=1) / mean) ** 2)


def _sba_quadrant(adi: float, cv2: float) -> str:
    if np.isnan(adi) or np.isnan(cv2):
        return PATTERN_INSUFFICIENT
    if adi < SB_ADI_THRESHOLD and cv2 < SB_CV2_THRESHOLD:
        return PATTERN_SMOOTH
    if adi >= SB_ADI_THRESHOLD and cv2 < SB_CV2_THRESHOLD:
        return PATTERN_INTERMITTENT
    if adi < SB_ADI_THRESHOLD and cv2 >= SB_CV2_THRESHOLD:
        return PATTERN_ERRATIC
    return PATTERN_LUMPY
