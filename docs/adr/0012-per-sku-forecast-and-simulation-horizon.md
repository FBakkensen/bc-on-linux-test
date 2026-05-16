# Per-SKU forecast and simulation horizon

The forecaster and the Monte Carlo simulator share a single per-SKU
horizon `H`. The same window is used for forward projection and for the
historical replay backtest. Picking `H` per-SKU rather than globally
respects the wide spread of lead-time profiles in real BC data — daily
consumables coexist with overseas-shipped items in the same tenant; one
horizon does not fit both.

## Formula

```
H_sku = clip(60 days, p95(LT_sku) × 5, 365 days)
```

- **Floor 60 days.** Even daily-cycle consumables observe ~12 cycles in
  the sim window; below this floor the law of large numbers hasn't
  kicked in for fill rate `β` and the per-SKU estimate is too noisy.
- **`p95(LT) × 5`.** Five worst-case replenishment cycles. Brings the
  standard error of simulated `β` to roughly under 2 percentage points
  on most series. Using `p95(LT)` rather than `mean(LT)` is deliberate
  — the horizon needs to *cover* bad lead times, not the typical ones.
- **Cap 365 days.** Bounds compute. Items with `p95(LT) > 73 days` lose
  some cycles but stay practical. Customers running 90-day overseas
  shipping see ~4 cycles in the sim instead of 5; acceptable trade-off
  vs. running 600-day simulations on a small minority of items.

The three numbers `(floor, multiplier, ceiling)` are stored in the
per-company `Planning Optimizer Setup` and tunable, but unlike `α`
targets these are math-foundational — the setup page warns before
changing them.

## Why p95(LT), not mean(LT)

Lead-time distributions are right-skewed in nearly every real BC tenant.
A few late receipts pull the upper tail far above the mean. Sizing the
simulation horizon by mean systematically under-sizes the window for
items with skewed LT — the simulator never sees the cycles that drive
stockout risk. p95 is the smallest robust tail statistic that captures
the late-receipt regime without being thrown off by single outliers
(unlike `max(LT)`, which is one bad receipt away from blowing the
horizon up).

## Why the same H for forecaster and simulator

The forecaster only needs to project as far as the simulator looks. If
the simulator's horizon is `H`, projecting beyond `H` is wasted compute;
projecting below `H` leaves the simulator with no forecast at the tail
of its window. Shared `H` removes an off-by-one error class and means
forecast accuracy diagnostics map directly to simulator-window
performance.

## Downstream rules

- **History requirement: `≥ 2 × H_sku` of clean ILE.** Fitting the
  forecaster + bootstrap needs roughly twice the projected horizon
  worth of historical data. An item with `H_sku = 200 days` needs ≥ 400
  days of clean ILE history. Items below the requirement are classified
  `Insufficient data` and demoted via the grain-promotion rule (ADR
  0008). The recommendation row carries the explicit code; the engine
  does not synthesise from thin history.
- **New items (no LT history) inherit horizon from Vendor or Item
  Category** — mean `p95(LT)` across that vendor's items, falling back
  to the item's category. The recommendation row is automatically capped
  at Medium Recommendation Confidence via the cold-start factor in the
  confidence cascade.
- **Cap-hit visible on row.** When `H_sku` is hitting the 365-day
  ceiling, the recommendation row carries a quiet note
  *Horizon capped at 365d (LT p95 = 120d)*. Otherwise a planner
  investigating *"why does `β` look noisier on this SKU"* has no signal
  that the simulator only saw 3 cycles instead of 5.

## What this rules out

- **Single global horizon.** Tried; rejected. Over-sizes short-LT items
  (wasted compute) and under-sizes long-LT items (too few cycles
  observed). Per-SKU is the right grain.
- **Pure `mean(LT) × N` formula.** Tried; rejected. Under-sizes for
  most real items because of LT skew.
- **No-cap formula `p95(LT) × N`.** Tried; rejected. Items with
  `p95(LT) = 120 days` get a 600-day horizon and dominate batch
  runtime.

## Tuning order if compute becomes a constraint

If batch runtime becomes a problem at production scale:

1. **Drop the cycle multiplier from 5 to 4 first.** The variance hit on
   `β` is small (~0.5 pp standard error increase) and applies uniformly.
2. **Drop the ceiling from 365 to 270 days second.** Affects only the
   long-LT minority; visible to the planner via the cap-hit note.
3. **Reduce MC iterations from 10K to 5K last.** The variance hit is
   larger and harder to explain; only tune as a last resort.

The floor is the one number that should not be tuned — going below 60
days breaks the small-LT regime.

## Consequences

- The simulator and forecaster operate on a per-SKU horizon that
  reflects the SKU's own replenishment profile. Recommendations for
  daily-cycle items and overseas items use the same engine without
  parameter contention.
- Setup-page UX must surface `(floor, multiplier, ceiling)` with
  warnings rather than hide them — tuning them changes recommendation
  outputs across the entire portfolio.
- Compute cost is bounded but variable — long-LT items dominate batch
  time within the cap. The Model Run Log's `Total SKUs Processed`
  alongside run duration tells customers what their compute profile
  looks like.
