"""Fidelity-B Monte Carlo simulator (ADR 0007).

Bootstrap LTD sampling, simplified policy replay, reports cycle service level
and fill rate alongside each other. Sampler-only mode is wired today;
inventory-dynamics replay lands on top of the same engine later.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

import numpy as np

if TYPE_CHECKING:
    import pandas as pd


def sample_ltd(lt_pairs: pd.DataFrame, n_draws: int, seed: int) -> np.ndarray:
    """Bootstrap-sample the Lead-Time Demand distribution from joint (LT, window) pairs.

    Each draw picks one historical pair uniformly at random and emits the sum
    of its demand window. Joint sampling preserves the demand-LT correlation
    that independent sampling would discard (ADR 0006).
    """
    rng = np.random.default_rng(seed)
    pair_count = len(lt_pairs)
    indices = rng.integers(0, pair_count, size=n_draws)
    # `demand_sum` is precomputed by `lead_time.extract_lt_series`; when a
    # test passes a raw frame without it, fall back to summing in-place.
    if "demand_sum" in lt_pairs.columns:
        window_sums = lt_pairs["demand_sum"].to_numpy(dtype="float64", copy=False)
    else:
        window_sums = np.fromiter(
            (w.sum() for w in lt_pairs["demand_window"]),
            dtype="float64",
            count=pair_count,
        )
    return window_sums[indices]
