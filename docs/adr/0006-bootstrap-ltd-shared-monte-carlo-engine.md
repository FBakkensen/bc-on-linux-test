# Lead-Time Demand from bootstrap, sharing one Monte Carlo engine

The recommendation engine estimates the Lead-Time Demand (LTD) distribution
by bootstrap-sampling `(lead time, demand window)` pairs from historical
data, not by closed-form parametric formula. The same stochastic engine is
used for two roles: (1) estimating the LTD distribution (sampler only, no
inventory dynamics) so the Reorder Point can be set to its α-quantile, and
(2) validating current-vs-proposed parameter sets via the Fidelity-B
inventory-dynamics loop (see ADR 0007). The forecaster supplies expected
demand per period; bootstrap supplies the distribution's shape.

## What "demand" and "lead time" actually source from

- **Demand**: all *negative-quantity* Item Ledger Entry rows at the
  `(Item, Variant, Location)` grain — no `Entry Type` filter. Sale,
  Consumption, Assembly Consumption, Negative Adjustment, and source-side
  Transfer rows all count as demand on the location holding the stock.
  Returns (positive ILE-Sale rows) net automatically against demand.
- **Lead time**: per replenishment system. Event-record dates beat
  planning-field dates wherever both are available — the LTD bootstrap
  needs historical truth, not planner intent.
  - **Purchase items**: `(Posted Purchase Receipt Posting Date − Purchase
    Order Header Order Date)` per receipt line. Drop-shipments and special
    orders excluded.
  - **Produced items**: `max(ILE Output Posting Date) − min(ILE
    Consumption Posting Date)` keyed by
    `(Prod. Order No., Item, Variant, Location)` on finished orders.
    Falls back to Production Order Header `(Finishing Date − Starting
    Date)` when no ILE Consumption rows exist for the prod order (items
    with no BOM consumption, raw extraction, etc.); fallback samples are
    flagged in extract metadata. Multi-output prod orders emit the same
    prod-order-level LT for each output line — a shared sample, not
    double-counted in bootstrap. Cancelled / scrapped prod orders
    (Status never reached Finished) are excluded.
  - **Transferred items**: ILE Transfer (−) at source → ILE Transfer (+)
    at destination, matched by Document No. + Item + Variant.
  - **Assembly items**: Posted Assembly Header
    `(Posting Date − Starting Date)`.

Two secondary lead-time series are computed alongside, feeding reason
codes rather than the LTD bootstrap:

- `(Posting Date on Receipt − Expected Receipt Date on PO Line, as
  recorded at PO creation)` → supplier-reliability signal for the
  `Supplier reliability worsened/improved` reason codes.
- For produced items, `(max(ILE Output Posting Date) − Production Order
  Header.Ending Date)` → planned-vs-actual production delta, feeding a
  future `Production reliability worsened/improved` reason code (v2).

Neither feeds the LTD bootstrap — they measure deviation from
*commitments*, not realised wait times.

## Why not closed-form

The textbook formula
`ROP = μ_D·μ_L + z_α · √(μ_L·σ_D² + μ_D²·σ_L²)`
assumes Normal demand and Normal lead time, independent. Both assumptions
fail systematically on BC data: slow-movers have intermittent demand with
many zero periods (Normality impossible); demand variance is dominated by
fat-tail order events (lognormal at best); lead-time distributions are
right-skewed (a few late receipts pull p95 well above the mean). The formula
can produce negative Reorder Points on slow-movers — a tell that the model
is misapplied. Class-dependent parametric switching (Normal for AX, Poisson
for intermittent, etc.) compounds the problem with three code paths and
three test surfaces.

## Why share the engine with current-vs-proposed validation

Bootstrap LTD estimation and current-vs-proposed validation are
structurally identical operations on the same sampler — only the consumer
differs. LTD estimation runs the sampler with the inventory-dynamics loop
turned off; validation runs the same sampler with the loop turned on. Two
consumers, one stochastic engine, one set of bugs to find, one calibration
to verify. Splitting them across two implementations creates an undetected
drift hazard: the ROP set by one method may not deliver the service level
measured by the other.

## The role of the forecaster under bootstrap

Pure bootstrap reuses past demand patterns; an item with a trend or
seasonality won't be served by it alone. The forecaster — SBA for series
classified as intermittent by Syntetos-Boylan (`ADI ≥ 1.32 OR CV² ≥ 0.49`),
AutoETS otherwise — supplies expected demand per period: the *location* of
the distribution. The bootstrap supplies the *shape*. At sample time, a
sampled demand window is scaled or shifted by the forecast's mean-per-period
relative to the historical mean-per-period in that window. The
distribution's shape and tail behaviour ride from history; the level rides
from the forecast.

ARIMA / SARIMA, Croston-original, TSB, and global ML forecasters are
deliberately out of scope. Two branches keep the test surface small;
backtests against real data can promote alternatives if they show clear
gains.

## Consequences

- The recommendation engine has one stochastic core; tests, calibration
  reports, and reproducibility seeds apply equally to ROP setting and to
  validation. Same seed per `(Item, Variant, Location, ModelRunId)` =
  same recommendation, every time.
- Items with regime changes (new product, supplier switch, channel
  shutdown) under-represent their new uncertainty because bootstrap samples
  only from observed history. These items receive a `Low` Recommendation
  Confidence via the cascade cap.
- Items with significant stockout history under-estimate true demand
  (suppressed-demand effect: customers couldn't buy what wasn't in stock,
  so ILE shows less than the true demand the recommended parameters would
  unmask). The recommendation row carries an explicit caveat code; the
  bootstrap is not corrected. A lost-sales journal — which most BC tenants
  do not maintain — would be required for a clean correction.
- **Degenerate lead-time data emits an explicit row-killed reason code,
  not a misleading ROP.** If every observed LT sample for a SKU is zero
  days (typically because the source extract didn't populate PO Order
  Date, so `receipt_posting_date − po_order_date` collapses to zero),
  the bootstrap would faithfully return `ROP=0` on a zero-length demand
  window — a value a planner could mistake for "no buffer needed". The
  recommender intercepts this case and emits a null recommendation with
  reason code `Zero lead time observed`, surfacing the data-quality
  problem instead of hiding behind a numerically-valid but operationally
  meaningless answer. SKUs with no LT samples at all remain on the
  `Insufficient data` reason code.
