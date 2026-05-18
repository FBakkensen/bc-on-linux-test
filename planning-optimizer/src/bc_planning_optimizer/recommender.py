"""Per-SKU recommendation math.

Bootstrap-driven (ADR 0006): for each SKU, draw `N` joint `(LT, demand_window)`
samples via the shared sampler and compute Reorder Point = quantile_α(LTD),
Safety Stock = max(ROP − mean(LTD), 0). `α` per ABC class comes from the
setup config (ADR 0005); `Unclassified` and any cold-start SKU fall back to
the conservative default.
"""

from __future__ import annotations

import hashlib
from dataclasses import dataclass
from typing import TYPE_CHECKING, Any, cast

import numpy as np

from .simulator import sample_ltd

if TYPE_CHECKING:
    import pandas as pd

SKU_COLUMNS = ["item_no", "variant_code", "location_code"]

# Mirrors `classifier.ABC_UNCLASSIFIED`; redefined locally to break a circular
# import (classifier reads SKU_COLUMNS from this module).
ABC_UNCLASSIFIED = "Unclassified"
REASON_INSUFFICIENT_DATA = "Insufficient data"
REASON_ZERO_LEAD_TIME = "Zero lead time observed"


@dataclass(frozen=True)
class BootstrapConfig:
    """Per-run bootstrap settings: α per ABC class plus the RNG knobs."""

    service_level_by_abc: dict[str, float]
    n_draws: int
    model_run_id_seed: int


def recommend_with_bootstrap(
    *,
    lt_pairs: pd.DataFrame,
    lt_summary: pd.DataFrame,
    classifier: pd.DataFrame,
    config: BootstrapConfig,
) -> list[dict[str, Any]]:
    """Return one bootstrap-driven recommendation dict per SKU in `lt_summary`.

    SKUs flagged `insufficient_data` emit a null recommendation with
    `reason_code = "Insufficient data"`; the rest get ROP = quantile_α(LTD)
    and SS = max(ROP − mean(LTD), 0), with α driven by the SKU's ABC class.
    """
    pairs_by_sku = lt_pairs.groupby(SKU_COLUMNS, sort=False) if not lt_pairs.empty else None
    abc_by_sku = _abc_by_sku(classifier)
    default_alpha = config.service_level_by_abc[ABC_UNCLASSIFIED]

    recommendations: list[dict[str, Any]] = []
    for _, summary_row in lt_summary.iterrows():
        sku_key = (
            str(summary_row["item_no"]),
            str(summary_row["variant_code"]),
            str(summary_row["location_code"]),
        )
        if bool(summary_row["insufficient_data"]):
            recommendations.append(_insufficient_recommendation(sku_key))
            continue

        sku_pairs = pairs_by_sku.get_group(sku_key) if pairs_by_sku is not None else None
        if sku_pairs is None or sku_pairs.empty:
            # `insufficient_data=False` should imply pair count > 0, but a
            # mismatched pair/summary frame would otherwise crash the run.
            recommendations.append(_insufficient_recommendation(sku_key))
            continue

        if int(sku_pairs["lead_time_days"].max()) == 0:
            # Every observed receipt landed on the order date → LT samples
            # exist but carry no signal (typically dirty extract data where
            # PO Order Date wasn't populated). Bootstrap would faithfully
            # return ROP=0; surface the data-quality problem instead.
            recommendations.append(_null_recommendation(sku_key, REASON_ZERO_LEAD_TIME))
            continue

        alpha = _alpha_for_sku(sku_key, abc_by_sku, config.service_level_by_abc, default_alpha)
        seed = _per_sku_seed(*sku_key, salt=config.model_run_id_seed)
        ltd = sample_ltd(sku_pairs, n_draws=config.n_draws, seed=seed)
        reorder_point = float(np.quantile(ltd, alpha))
        safety_stock = max(reorder_point - float(ltd.mean()), 0.0)
        recommendations.append(
            {
                "item_no": sku_key[0],
                "variant_code": sku_key[1],
                "location_code": sku_key[2],
                "reorder_point": reorder_point,
                "safety_stock": safety_stock,
            },
        )
    return recommendations


def _abc_by_sku(classifier: pd.DataFrame) -> dict[tuple[str, str, str], str]:
    if classifier.empty:
        return {}
    return cast(
        "dict[tuple[str, str, str], str]",
        classifier.set_index(SKU_COLUMNS)["abc_class"].astype("string").to_dict(),
    )


def _alpha_for_sku(
    sku_key: tuple[str, str, str],
    abc_by_sku: dict[tuple[str, str, str], str],
    service_level_by_abc: dict[str, float],
    default_alpha: float,
) -> float:
    abc_class = abc_by_sku.get(sku_key, ABC_UNCLASSIFIED)
    return service_level_by_abc.get(abc_class, default_alpha)


def _per_sku_seed(item: str, variant: str, location: str, *, salt: int) -> int:
    """Deterministic per-SKU seed derived from the SKU triplet + ModelRunId salt.

    SHA-256 over the joined key; reproducible across Python processes, unlike
    `hash()` (which is salted by default).
    """
    payload = f"{item}|{variant}|{location}|{salt}".encode()
    digest = hashlib.sha256(payload).digest()
    return int.from_bytes(digest[:8], "little")


def _insufficient_recommendation(sku_key: tuple[str, str, str]) -> dict[str, Any]:
    return _null_recommendation(sku_key, REASON_INSUFFICIENT_DATA)


def _null_recommendation(sku_key: tuple[str, str, str], reason_code: str) -> dict[str, Any]:
    return {
        "item_no": sku_key[0],
        "variant_code": sku_key[1],
        "location_code": sku_key[2],
        "reorder_point": None,
        "safety_stock": None,
        "reason_code": reason_code,
    }
