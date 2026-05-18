"""Tests for `simulator.sample_ltd`.

The bootstrap LTD sampler is the math primitive shared by ROP estimation
(slice #18, this slice) and the inventory-dynamics simulator (slice #20+).
Tests drive the function directly — same posture as `test_lead_time.py`,
since this is the data-prep / math-primitive seam, not the public `run`
output shape (which is covered through `test_walking_skeleton.py`).
"""

from __future__ import annotations

import numpy as np
import pandas as pd
from bc_planning_optimizer.simulator import sample_ltd


def _pairs(*rows: tuple[int, list[float]]) -> pd.DataFrame:
    """Build an LT-pairs frame in the shape `lead_time.extract_lt_series` emits."""
    return pd.DataFrame(
        {
            "lead_time_days": [r[0] for r in rows],
            "demand_window": [np.asarray(r[1], dtype="float64") for r in rows],
        },
    )


def test_sample_ltd_returns_ndarray_of_length_n_draws():
    pairs = _pairs((2, [3.0, 4.0]))

    draws = sample_ltd(pairs, n_draws=5, seed=42)

    assert isinstance(draws, np.ndarray)
    assert draws.shape == (5,)


def test_sample_ltd_is_deterministic_given_seed():
    pairs = _pairs((2, [3.0, 4.0]), (3, [1.0, 2.0, 3.0]))

    first = sample_ltd(pairs, n_draws=100, seed=42)
    second = sample_ltd(pairs, n_draws=100, seed=42)

    assert np.array_equal(first, second)


def test_sample_ltd_each_draw_is_sum_of_a_sampled_pair():
    # Two disjoint pairs: window sums are 7 (=3+4) and 30 (=10+20). Any
    # joint sample must emit one of those two totals — that's the bootstrap
    # picking a historical pair as a unit, per ADR 0006.
    pairs = _pairs((2, [3.0, 4.0]), (2, [10.0, 20.0]))

    draws = sample_ltd(pairs, n_draws=500, seed=0)

    assert set(np.unique(draws).tolist()) <= {7.0, 30.0}
    # Both pairs should actually appear over 500 draws (probability of
    # missing either is 2 * 0.5^500, negligible — a seeded smoke test).
    assert {7.0, 30.0}.issubset(set(np.unique(draws).tolist()))


def test_sample_ltd_does_not_split_lt_and_window_independently():
    # Joint-sampling guard: if LT and demand_window were sampled
    # independently, a draw could pair LT=2 with window=[5,5,5] (sum 15)
    # — that combination never occurs in the historical pairs, so its sum
    # must never appear in the LTD distribution.
    pairs = _pairs((2, [3.0, 4.0]), (3, [5.0, 5.0, 5.0]))

    draws = sample_ltd(pairs, n_draws=1_000, seed=1)

    # Allowed sums = {7, 15}. Cross-pollinated sums like 10 (=3+4 + extra)
    # or 8 (=5+3) must not appear.
    assert set(np.unique(draws).tolist()) == {7.0, 15.0}
