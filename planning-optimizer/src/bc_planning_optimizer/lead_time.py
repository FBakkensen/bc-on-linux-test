"""Unified lead-time series across the four BC replenishment systems.

Consumes the four LT extracts (Purchase Receipt, Production, Assembly,
Transfer per slices #13 + #14) and the Item Ledger Summary, and produces the
`(LT_days, demand_window, replenishment_system, source_flag)` sample series
the bootstrap LTD sampler (slice #18, per ADR 0006) consumes — plus the
secondary Plan-to-Receipt / Plan-to-Actual series feeding reliability reason
codes, and per-SKU summary statistics for downstream display.
"""

from __future__ import annotations

from dataclasses import dataclass
from functools import partial
from typing import Final

import numpy as np
import pandas as pd

REPLENISHMENT_PURCHASE: Final = "purchase"
SOURCE_PURCHASE_RECEIPT: Final = "purchase_receipt"

SKU_COLUMNS = ["item_no", "variant_code", "location_code"]


@dataclass(frozen=True)
class LtSeriesResult:
    """Output of `extract_lt_series`.

    `pairs` is the per-sample series the bootstrap LTD sampler consumes —
    one row per historical LT sample, carrying `lead_time_days`,
    `demand_window`, the `replenishment_system` / `source` tags, and the
    secondary `plan_to_receipt_days` / `plan_to_actual_days` series kept
    distinct from the bootstrap input (ADR 0006).

    `summary` is one row per SKU known to the system (i.e. present in the
    ILE summary or any LT extract), carrying per-SKU LT distribution
    statistics. SKUs with zero LT samples carry `insufficient_data=True`
    and NaN stats — the cold-start signal downstream consumes.
    """

    pairs: pd.DataFrame
    summary: pd.DataFrame


def extract_lt_series(
    *,
    purchase_lt: pd.DataFrame,
    production_lt: pd.DataFrame,
    transfer_lt: pd.DataFrame,
    assembly_lt: pd.DataFrame,
    ile_summary: pd.DataFrame,
) -> LtSeriesResult:
    """Build the unified LT-pair series from the four per-system extracts.

    Each extract is already shaped per its replenishment system (see
    `extracts/bc_files.py`); we map per-system columns onto the unified
    schema, concatenate, then attach the matching pre-trigger demand
    window per sample from `ile_summary` (sampled jointly preserves the
    demand-LT correlation that independent sampling would discard).
    """
    pairs = pd.concat(
        [
            _purchase_pairs(purchase_lt),
            _non_purchase_pairs(production_lt),
            _non_purchase_pairs(assembly_lt),
            _non_purchase_pairs(transfer_lt),
        ],
        ignore_index=True,
    )
    windows = _pair_demand_windows(pairs, ile_summary)
    pairs["demand_window"] = pd.Series(windows, index=pairs.index, dtype="object")
    # Precompute window sums so the bootstrap sampler reads a flat float64
    # column instead of summing every window on each `sample_ltd` call.
    pairs["demand_sum"] = np.fromiter(
        (w.sum() for w in windows),
        dtype="float64",
        count=len(windows),
    )
    summary = _summarize(pairs, ile_summary)
    return LtSeriesResult(pairs=pairs, summary=summary)


_SUMMARY_PERCENTILES: Final = (0.50, 0.75, 0.90, 0.95)


def _quantile_at(series: pd.Series, *, p: float) -> float:
    return float(series.quantile(p))


def _summarize(pairs: pd.DataFrame, ile_summary: pd.DataFrame) -> pd.DataFrame:
    """Per-SKU LT distribution stats. Cold-start SKUs flagged, no stats raised."""
    sku_universe = _sku_universe(pairs, ile_summary)
    if sku_universe.empty:
        return _empty_summary()
    if pairs.empty:
        # Empty stats frame still needs the lt_count column so the merge below
        # produces a NaN-filled `lt_count` for every SKU — fillna(0) then flips
        # them all into the `insufficient_data=True` cold-start signal.
        stats = pd.DataFrame(columns=[*SKU_COLUMNS, "lt_count"])
    else:
        # Single groupby pass that computes count/mean/std plus all four
        # percentiles, instead of one groupby per percentile.
        stats = pairs.groupby(SKU_COLUMNS, as_index=False, sort=False).agg(
            lt_count=("lead_time_days", "count"),
            lt_mean=("lead_time_days", "mean"),
            lt_sigma=("lead_time_days", "std"),
            **{
                f"lt_p{int(p * 100)}": ("lead_time_days", partial(_quantile_at, p=p))
                for p in _SUMMARY_PERCENTILES
            },
        )

    merged = sku_universe.merge(stats, on=SKU_COLUMNS, how="left")
    merged["lt_count"] = merged["lt_count"].fillna(0).astype("int64")
    merged["insufficient_data"] = merged["lt_count"] == 0
    return merged


def _sku_universe(pairs: pd.DataFrame, ile_summary: pd.DataFrame) -> pd.DataFrame:
    """Every SKU we know about — union of LT-sample SKUs and ILE-known SKUs."""
    frames = []
    if not pairs.empty:
        frames.append(pairs[SKU_COLUMNS])
    if not ile_summary.empty:
        frames.append(ile_summary[SKU_COLUMNS])
    if not frames:
        return pd.DataFrame(columns=SKU_COLUMNS)
    return pd.concat(frames, ignore_index=True).drop_duplicates().reset_index(drop=True)


def _empty_summary() -> pd.DataFrame:
    return pd.DataFrame(
        {
            "item_no": pd.Series(dtype="string"),
            "variant_code": pd.Series(dtype="string"),
            "location_code": pd.Series(dtype="string"),
            "lt_count": pd.Series(dtype="int64"),
            "lt_mean": pd.Series(dtype="float64"),
            "lt_p50": pd.Series(dtype="float64"),
            "lt_p75": pd.Series(dtype="float64"),
            "lt_p90": pd.Series(dtype="float64"),
            "lt_p95": pd.Series(dtype="float64"),
            "lt_sigma": pd.Series(dtype="float64"),
            "insufficient_data": pd.Series(dtype="bool"),
        },
    )


def _pair_demand_windows(pairs: pd.DataFrame, ile_summary: pd.DataFrame) -> list[np.ndarray]:
    """Carve each LT sample's pre-trigger demand window from the ILE summary.

    Per-SKU daily net demand = `-sum(quantity)` grouped by posting_date.
    Returns naturally net through positive quantities. Each window is a
    length-`lead_time_days` numpy array indexed by day-offset from
    `trigger_date - lead_time_days` up to `trigger_date - 1` inclusive.
    """
    if ile_summary.empty:
        return [np.zeros(int(lt), dtype="float64") for lt in pairs["lead_time_days"]]
    # Sum across same-day rows so positive returns net against negative
    # demand; negate so positive = demand magnitude. Indexed by
    # (item, variant, location, date) for O(1) per-day lookup.
    keyed = (
        -ile_summary.groupby([*SKU_COLUMNS, "posting_date"], sort=False)["quantity"]
        .sum()
        .astype("float64")
    )

    windows: list[np.ndarray] = []
    for _, row in pairs.iterrows():
        lt = int(row["lead_time_days"])
        sku_key = (row["item_no"], row["variant_code"], row["location_code"])
        windows.append(_carve_window(keyed, sku_key, lt, pd.Timestamp(row["trigger_date"])))
    return windows


def _carve_window(
    keyed: pd.Series,
    sku_key: tuple[str, str, str],
    lt: int,
    trigger: pd.Timestamp,
) -> np.ndarray:
    window = np.zeros(lt, dtype="float64")
    if lt <= 0:
        return window
    item, variant, location = sku_key
    for offset in range(lt):
        date = trigger - pd.Timedelta(days=lt - offset)
        try:
            window[offset] = float(keyed.loc[item, variant, location, date])
        except KeyError:
            window[offset] = 0.0
    return window


_UNIFIED_COLUMNS = [
    "item_no",
    "variant_code",
    "location_code",
    "lead_time_days",
    "replenishment_system",
    "source",
    "shared_sample_key",
    "trigger_date",
    "plan_to_receipt_days",
    "plan_to_actual_days",
]


def _purchase_pairs(purchase_lt: pd.DataFrame) -> pd.DataFrame:
    pairs = purchase_lt[
        [
            "item_no",
            "variant_code",
            "location_code",
            "order_to_receipt_days",
            "plan_to_receipt_days",
            "document_no",
            "trigger_date",
        ]
    ].rename(
        columns={
            "order_to_receipt_days": "lead_time_days",
            "document_no": "shared_sample_key",
        },
    )
    pairs["replenishment_system"] = REPLENISHMENT_PURCHASE
    pairs["source"] = SOURCE_PURCHASE_RECEIPT
    pairs["plan_to_actual_days"] = pd.NA
    return pairs[_UNIFIED_COLUMNS]


def _non_purchase_pairs(lt: pd.DataFrame) -> pd.DataFrame:
    """Production / Assembly / Transfer extracts already share the unified shape."""
    if not len(lt):
        return lt.reindex(columns=_UNIFIED_COLUMNS).copy()
    out = lt.copy()
    out["plan_to_receipt_days"] = pd.NA
    return out[_UNIFIED_COLUMNS]
