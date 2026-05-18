---
title: "Planning Parameter Optimisation for Business Central"
subtitle: "Design walkthrough and open questions"
date: "May 2026"
titlepage: true
titlepage-rule-color: "555555"
toc: true
toc-own-page: true
book: true
listings-disable-line-numbers: true
disable-header-and-footer: false
header-includes:
  - \usepackage{fontspec}
  - \usepackage{newunicodechar}
  - \newfontfamily{\notosym}{Noto Sans Symbols}
  - \newfontfamily{\notomath}{Noto Sans Math}
  - \newunicodechar{→}{{\notosym →}}
  - \newunicodechar{≥}{{\notomath ≥}}
  - \newunicodechar{≤}{{\notomath ≤}}
  - \newunicodechar{⌈}{{\notomath ⌈}}
  - \newunicodechar{⌉}{{\notomath ⌉}}
  - \newunicodechar{α}{{\notomath α}}
  - \newunicodechar{β}{{\notomath β}}
  - \newunicodechar{μ}{{\notomath μ}}
  - \newunicodechar{σ}{{\notomath σ}}
  - \newunicodechar{√}{{\notomath √}}
  - \newunicodechar{Δ}{{\notomath Δ}}
  - \newunicodechar{Σ}{{\notomath Σ}}
---

# 1. Executive summary

This document describes the design of a Business Central extension
that recommends improved planning parameters — Reorder Point, Safety
Stock, Reorder Quantity, Maximum Inventory, Reordering Policy, and
related fields — on `Item`, `Stockkeeping Unit`, and Variant records.

The system is **not** a replacement for the BC planning worksheet or
MRP. It does not generate supply orders. It does not auto-update
planning parameters. Its scope is a controlled, auditable
recommendation process that suggests parameter changes, validates them
via simulation, and lets a planner approve before any value is
written back to the Item or SKU.

The numeric engine uses probabilistic demand forecasting and
stochastic inventory parameter optimisation: demand classification,
classical-and-intermittent-demand forecasting, empirical lead-time
modelling, and Monte Carlo simulation. It does not use generative AI
for the recommendation math.

## 1.1 Pipeline at a glance

![End-to-end pipeline.](diagrams/01-pipeline.png)

The engine reads posted history and current forward commitments out
of Business Central, classifies each `(Item, Variant, Location)`
series, forecasts its demand, models its lead-time uncertainty,
computes proposed planning parameters, and validates them against the
current parameters via Monte Carlo simulation and historical replay.
The output for each `(Item, Variant, Location)` is a recommendation
row holding the current and proposed values for every planning
parameter, paired with the simulated and replayed performance metrics
(cycle service level, fill rate, stockout probability, average
inventory, working-capital impact). A planner reviews the row, may
edit the suggested values inline, and approves and applies it. Every
applied change is logged with the engine version, the configuration
state at run time, and the data window used.

## 1.2 What this document covers

The chapters walk through the design choices that shape every
recommendation, grouped by where the choice bites:

- **Optimisation core** (chapter 4) — the service-level targeting
  stance, the ABC basis, the cycle-service-level versus fill-rate
  split, Reorder Point and Safety Stock derivation, Reorder Quantity,
  Reordering Policy mismatch rules.
- **Data layer** (chapter 5) — how demand is defined from posted
  history; how lead time is measured per replenishment system; the
  manufactured-item lead-time mechanic; the recommendation grain.
- **Forecasting** (chapter 6) — the Syntetos-Boylan classification
  and the two-branch SBA / AutoETS choice.
- **Validation** (chapter 7) — the simulator's fidelity choices, the
  historical replay backtest, the two confidence fields, the eighteen
  reason codes.
- **Business Central integration** (chapter 8) — multi-company
  isolation, recommendation lifecycle, audit lineage, the apply
  workflow, run cadence.

Chapter 9 collects the **ten open questions** where the reviewer's
experience and theoretical expertise would most usefully shape the
design. The decision register in appendix A indexes every choice the
document makes against the chapter that discusses it and the open
question (if any) that puts it back on the table.

# 2. Problem framing and non-goals

Business Central customers maintain Reordering Policy, Reorder Point,
Safety Stock Quantity, Reorder Quantity, Maximum Inventory, Minimum
Order Quantity, Maximum Order Quantity, Order Multiple, Safety Lead
Time, Lead Time Calculation, Time Bucket, Lot Accumulation Period,
Dampener Period, Dampener Quantity, and Overflow Level by hand. The
values are typically set once at master-data creation, occasionally
revisited during an MRP-tuning exercise, and otherwise left untouched
for years. They therefore drift out of alignment with real demand
patterns, seasonality, intermittent-demand events, lead-time changes,
supplier-reliability shifts, stockouts, and the location- or
variant-specific behaviour that emerges over time.

The engine addresses this drift by analysing posted history,
forecasting demand, modelling lead-time uncertainty, simulating
proposed parameters against current ones, and presenting the
comparison to a planner for approval.

## 2.1 Recommendation grain

The recommendation grain is `Item No. + Variant Code + Location Code`
— matching the Stockkeeping Unit. Where the SKU has insufficient data,
recommendations are aggregated up the grain hierarchy and the row
reports the computed grain explicitly. Where two finer-grain aggregates
of the same item disagree materially on the proposed Reorder Point, the
engine recommends *creating* an SKU at the finer grain rather than
leaving the variation hidden behind the Item Card. The mechanics are
described in section 5.4.

## 2.2 Non-goals

The first version of the engine deliberately does **not**:

- Replace BC's planning worksheet or MRP run.
- Generate supply orders. The output is parameter recommendations only;
  generation of `Requisition Line` / `Purchase Order` / `Production
  Order` records remains with BC's planning engine.
- Auto-update planning parameters. Approval is mandatory; no rule
  short-circuits the planner.
- Use generative AI to calculate Reorder Points or Safety Stock.
- Solve full production capacity planning or warehouse capacity
  constraints. Both are noted as v2+ scope.
- Optimise vendor consolidation, vendor group order grouping, or
  budget-constrained ordering across the master schedule.
- Provide a chatbot as the core planning interface.

# 3. Glossary

**Lead-Time Demand (LTD).** The random variable describing total demand
arriving during a single replenishment lead time. Formally,
`LTD = Σ_{t=t₀..t₀+L} D_t` where `L` is the realised lead time and
`D_t` is per-period demand, both random. The α-quantile of the LTD
distribution is the textbook formula for Reorder Point under cycle-service-level
targeting. In this engine the distribution is estimated empirically
via bootstrap; see section 4.4.

**Cycle Service Level (α).** `P(no stockout during a replenishment
cycle)`. The *targeting* input: customers set `α` per ABC class in the
setup table, and the engine produces parameters that hit it. Not the
same as Fill Rate.

**Fill Rate (β).** Expected fraction of demand *units* served from
stock without backorder. The *reported* output: Monte Carlo simulation
returns `β` alongside `α` so the planner sees the customer-facing
consequence of the chosen `α`. `β ≠ α`: spiky demand makes `β` lag `α`
by 5–10 percentage points; smooth demand makes `β` approach `α`.

**Syntetos-Boylan classification.** A two-feature classification
distinguishing smooth from intermittent demand series, based on `ADI`
(average bucketed inter-arrival interval between non-zero demand
buckets) and `CV²` (squared coefficient of variation of non-zero demand
sizes). Threshold: a series is intermittent when `ADI ≥ 1.32 OR
CV² ≥ 0.49`. The thresholds are not arbitrary — they are the empirical
break-even points where intermittent methods overtake classical
exponential smoothing on mean-squared error.

**SBA — Syntetos-Boylan Approximation.** A bias-corrected variant of
Croston's intermittent-demand forecasting method. SBA applies a
`(1 − p/2)` correction where `p` is the inter-arrival rate, eliminating
Croston-original's upward bias on slow movers.

**AutoETS.** Automatic selection of the `(Error, Trend, Seasonal)`
state-space exponential-smoothing tuple over `{N, A, M, Ad} ×
{N, A, Ad} × {N, A, M}` via AIC. Subsumes Holt, Holt-Winters, simple
exponential smoothing, and damped-trend variants as special cases.

**Recommendation Grain.** The `(Item, Variant, Location)` tuple a
recommendation row is computed at. *Intended grain* matches the SKU;
*computed grain* is the coarsest aggregation actually used when the
intended grain has insufficient observations. Promotion path:
`(Item, Variant, Location) → (Item, *, Location) → (Item, *, *)`.

**Forecast Confidence.** A scalar per `(Item, Variant, Location)`
measuring the fit quality of the upstream forecaster only. Bucketed
Low / Medium / High for the planner UI.

**Recommendation Confidence.** The bucketed minimum over five factors:
Forecast Confidence, data sufficiency for bootstrap LTD,
replay-vs-Monte-Carlo agreement on `β`, stockout-history cap, and
grain-promotion cap. The row carries the *limiting* factor so a Low
rating is actionable.

**Fidelity-B simulator.** The Monte Carlo simulator that replays BC's
reordering policy logic at a deliberately simplified fidelity:
continuous review for `Fixed Reorder Qty.` and `Maximum Qty.`, periodic
review for `Lot-for-Lot` (honouring `Lot Accumulation Period`), 1:1
pegging for `Order`, MOQ / Multiple / Max enforcement strict,
`Dampener Period / Quantity` treated as a noise floor. It does not
re-implement `Codeunit 99000854 Inventory Profile Offsetting`.

**Model Run.** One execution of the engine over one company's extract.
Carries a GUID `ModelRunId`, the math package version, a JSON snapshot
of the active setup, and the data window. Every recommendation row and
every applied audit-log entry traces back through `ModelRunId`.

# 4. Optimisation core

## 4.1 Service-level targeting per ABC class

The engine optimises for a target Cycle Service Level set per ABC
class. The Reorder Point falls out as the α-quantile of the Lead-Time
Demand distribution; the Safety Stock is `ROP − E[LTD]`. The Reorder
Quantity is computed separately (section 4.5) and does not enter the
service-level math.

We considered total-cost minimisation — the classical *"minimise
expected (carrying + stockout + ordering + setup + expediting +
obsolescence) cost subject to constraints"* framing. We rejected it for
this engine for one specific reason: per-SKU stockout cost, lost-sales
cost, expediting premium, and obsolescence write-off rate are almost
never reliably present in BC tenants. `Item.Order Cost` is sometimes
populated; the annual carrying-cost rate is universally absent — it is
a finance assumption, not a BC field. A total-cost engine looks
mathematically rigorous but would in practice run on guessed
coefficients and produce recommendations that are confidently wrong
rather than transparently uncertain.

Service-level targeting is honest about what BC tenants actually know.
The customer sets `α` per class; the engine produces parameters that
hit it; stockout probability and fill rate are reported as Monte Carlo
metrics so the planner sees the customer-facing consequence, but they
are outputs, not optimisation inputs.

The engine does not preclude a future migration to total-cost
minimisation if a customer turns up with reliably-populated cost
fields. The recommender for that customer would gain a cost-aware
objective alongside the service-level-targeting one; the data
definitions, simulator, audit pipeline, and planner workflow do not
change.

## 4.2 ABC classification basis

ABC class is computed from posted sales value over a configurable
window (default 12 months). Cut points are stored per company in the
setup table; defaults `A = top 70% of revenue`, `B = next 20%`,
`C = last 10%`. A manual `Strategic` flag on the Item or SKU pins a
record to class A regardless of revenue rank, handling the
strategic-but-low-volume items (regulatory must-stock parts, OEM
contractual minimums, customer-specific items) that the curve misses.
New items with no posted revenue history are tagged `Unclassified` and
receive a conservative default `α` rather than being silently demoted
to class C.

We considered margin-based ABC (revenue × margin %) and cost-of-consumption ABC.
Margin-based ABC is theoretically more aligned with profit protection,
but BC margin data is unreliable in practice: `Standard Cost` lags
`Last Direct Cost`, `Profit %` is sometimes maintained and sometimes
left at zero, and the cost cutover from `Standard` to `Average` mid-window
breaks the time series. Revenue is the cleanest of the candidate
inputs.

## 4.3 Cycle service level α versus fill rate β

The engine treats `α` and `β` as **two distinct, distinctly labelled
fields** on every recommendation row. `α` is the targeting input (set
per ABC class in setup); `β` is the reported output (computed from the
simulator and reported alongside `α`).

The two numbers are not interchangeable. A 95% `α` corresponds to
roughly 98–99% `β` on smooth demand and 85–90% `β` on spiky demand.
The customer-facing intuition is usually `β`-shaped ("we filled 96% of
order lines on time"), but the math falls out cleanly only for `α`.
Storing one number labelled "Target Service Level" and letting
consultants and planners argue about which definition it represents is
the failure mode this decision exists to prevent.

The planner UI surfaces both numbers per row. When the gap is large
(spiky demand, low `β` for a given `α`), the planner can choose to
raise `α` to recover `β`. The engine does not do this automatically —
the trade-off between higher service level and higher inventory belongs
to the planner.

## 4.4 Reorder Point and Safety Stock from bootstrap LTD

For each `(Item, Variant, Location)`:

1. Draw `N` joint samples (default `N = 10 000`) of
   `(lead-time, demand-window)` from history. The pair is sampled
   jointly to preserve any correlation between lead time and demand
   visible in the data.
2. For each draw, scale the sampled demand window by the forecaster's
   mean-per-period relative to the historical mean-per-period in that
   window (level-shift). Sum demand over the LT-day window to obtain
   one LTD draw.
3. After `N` draws, the empirical LTD distribution is in hand. Compute:
   - `Reorder Point = quantile_α(LTD)` where `α` is the per-class
     target from setup.
   - `Safety Stock = ROP − E[LTD]`, clipped at 0.

![LTD bootstrap flow.](diagrams/02-ltd-bootstrap.png)

We considered three alternatives:

**Closed-form parametric formula.** The textbook
`ROP = μ_D·μ_L + z_α · √(μ_L·σ_D² + μ_D²·σ_L²)` assumes Normal demand
and Normal lead time, independent. Both assumptions fail systematically
on BC data: slow-movers have intermittent demand with many zero periods
(Normality impossible); demand variance is dominated by fat-tail order
events (lognormal at best); lead-time distributions are right-skewed (a
few late receipts pull p95 well above the mean). The formula can
produce negative Reorder Points on slow-movers — a tell that the model
is misapplied.

**Class-dependent parametric switching.** Normal for AX (high value,
stable demand), Poisson or Compound-Poisson for intermittent, bootstrap
for everything else. Theoretically more correct than the unconditional
closed form. Adds three code paths, three test surfaces, and three
calibration questions; loses the simplicity argument for bootstrap.

**Bootstrap on the shared Monte Carlo engine.** Chosen. The same
sampler that drives the LTD estimation also drives the current-vs-proposed
validation simulator (section 7.1); the two roles share one engine,
one set of bugs to find, one calibration to verify.

Two consequences worth flagging:

- *Regime changes are under-represented.* Bootstrap samples only from
  observed history. An item going through a regime change (new product,
  supplier switch, channel shutdown) carries old uncertainty into the
  new world. These items receive a low Recommendation Confidence via
  the cascade (section 7.4).
- *Historical stockouts suppress the bootstrap.* When the actual
  inventory hit zero, customers could not buy. The ILE rows we
  bootstrap from under-represent the demand that *would* have arrived
  under non-stockout conditions. The engine flags this rather than
  estimates the suppression; section 4.4 lists the flag and the open
  question (9.5) asks whether estimation is appropriate.

## 4.5 Reorder Quantity via EOQ when clean, POQ otherwise

The engine decouples Reorder Quantity from the service-level math.
Service level is set by Reorder Point and Safety Stock; the Reorder
Quantity controls ordering frequency and cycle inventory, which trade
off ordering cost against carrying cost.

Two methods:

**EOQ** when `Item.Order Cost` is populated and a company-level carrying-cost
rate exists in setup:
`Q* = √(2·D·K / h)`
where `D = annual_forecasted_demand`, `K = Order Cost`, `h = carrying_rate · Unit Cost`.

**POQ** (Period Order Quantity) otherwise, by ABC class:
`Q = ⌈forecasted_demand_per_day · coverage_days(class)⌉`
with defaults `A = 30, B = 60, C = 90` days.

Both methods round up to `Order Multiple`, then clip to
`[Min Order Qty, Max Order Qty]`. A reason code on each row records
which method was used so the customer can see which side of the
EOQ-vs-POQ split each recommendation came from — and where to invest in
cost-master cleanup if they want more EOQ-grade recommendations later.

EOQ on missing inputs misbehaves badly. With `Order Cost = 0`, `Q*`
blows up to infinity. Detecting the missing input and falling back to
POQ — rather than substituting a guessed default — keeps the
recommendation interpretable.

Manufactured items are treated identically to purchased items via POQ
for the first version. Economic Production Quantity (EPQ) generalisation
needs setup-cost data BC tenants rarely maintain reliably; we defer it.

## 4.6 Reordering Policy mismatch rules

The engine is conservative about recommending changes to the
Reordering Policy itself. Changing the policy field changes which other
fields are even meaningful and forces operational adaptation (planner
habits, MRP behaviour, buyer workflows). A recommendation engine that
casually toggles policies destroys trust faster than it earns it.

Three named-rule mismatches trigger a policy change:

1. `Reordering Policy = blank` and ≥6 months of demand history exists
   → recommend `Fixed Reorder Qty.` (BC's most general default).
2. `Reordering Policy ∈ {Fixed Reorder Qty., Maximum Qty.}` and the
   Syntetos-Boylan classification is `Intermittent`, `Lumpy`, or
   `Erratic`, and ABC class is `B` or `C` → recommend `Lot-for-Lot`.
3. `Reordering Policy ∈ {Fixed Reorder Qty., Maximum Qty.}` and
   `Manufacturing Policy = Make-to-Order` → recommend `Order`.

Outside these three cases, the engine keeps the current policy and
only suggests new values for the fields the current policy actually
uses.

**Policy-aware output nulling.** The recommendation row's suggested-field
columns are conditionally populated based on the *recommended* policy:

- `Lot-for-Lot` → `Suggested Reorder Quantity` and `Suggested Maximum
  Inventory` set to `null` (BC ignores these fields under L4L).
- `Order` → `Suggested Reorder Point`, `Suggested Reorder Quantity`,
  `Suggested Maximum Inventory` all `null`.
- `Maximum Qty.` → `Suggested Reorder Point` and `Suggested Maximum
  Inventory` populated; `Suggested Reorder Quantity` `null`.
- `Fixed Reorder Qty.` → `Suggested Reorder Point` and
  `Suggested Reorder Quantity` populated; `Suggested Maximum
  Inventory` `null`.

**Ignored-fields diagnostic.** When the *current* policy has fields
that it ignores but are populated on the Item or SKU (e.g.
`Lot-for-Lot` with a hand-populated Reorder Point), the engine emits a
diagnostic reason code without proposing a policy change. The fields
are inert under that policy; the diagnostic surfaces the contradiction
for the planner to clean up.

# 5. Data layer

## 5.1 Demand from signed Item Ledger Entries

Historical demand is defined as the sum of *negative-quantity* `Item
Ledger Entry` rows at `(Item, Variant, Location, posting-date bucket)`.
**There is no `Entry Type` filter.** Sale, Consumption, Assembly
Consumption, Negative Adjustment, and source-side Transfer rows all
count as demand on the location holding the stock. Returns —
positive-quantity ILE-Sale rows — net automatically against demand.

The defining principle is that the Reorder Point's job is to keep
stock above zero against *all* outflows, not only customer sales. A
component used inside a BOM ages and reorders by total consumption; a
feeder location that ships to a downstream location ages and reorders
by total outflows. Filtering by `Entry Type` would systematically
under-size buffers for items where most demand is internal.

Subtleties:

- **Negative adjustments and scrap.** Real outflows but often
  unpredictable (count corrections, write-offs). Default behaviour:
  include in history without weighting. A future setup-table option to
  down-weight a specific adjustment-reason code is a v2 concern.
- **Transfers.** A transfer out is real demand *at the source
  location*; the corresponding transfer in is real supply *at the
  destination*. The per-location grain handles both sides naturally.
- **Returns.** Positive ILE-Sale rows reduce historical demand for the
  period they occur in. The signed approach handles this without
  special logic.

## 5.2 Lead time per replenishment system

Lead-time samples are drawn from BC history using event-record dates
wherever both event dates and planning fields are available. The
planning fields (`Item.Lead Time Calculation`, `SKU.Lead Time
Calculation`) are precisely the parameters the engine is recommending
changes to — they cannot also be the historical source. Per
replenishment system:

**Purchase replenishment.**
`LT = Posted Purchase Receipt Line.Posting Date − Purchase Order
Header.Order Date`, per receipt line. Drop-shipments and special orders
are excluded — both are item-specific demand, not replenishment lead
time.

**Production replenishment.** See section 5.3 — the mechanic differs
enough to warrant its own decision.

**Transfer replenishment.**
ILE Transfer (−) at source → ILE Transfer (+) at destination, matched
by `Document No.` plus `Item No.` plus `Variant Code`. The result is a
route-specific lead time, which is what the per-location recommendation
grain needs.

**Assembly replenishment.**
`Posted Assembly Header.Posting Date − Posted Assembly Header.Starting
Date`, per finished assembly. Cancelled assemblies excluded.

A **second, secondary** lead-time series is computed alongside but does
*not* feed the LTD bootstrap:
`Posted Purchase Receipt Line.Posting Date − Purchase Order Line.Expected Receipt Date (as set at PO creation)`.
This is the **supplier reliability** signal — Plan-to-Receipt deviation
rather than total wait time. It feeds the `Supplier reliability
worsened` / `improved` reason codes only.

## 5.3 Manufactured-item lead time mechanics

For produced items, the primary lead-time measurement is
`max(ILE Output Posting Date) − min(ILE Consumption Posting Date)`,
keyed by `(Prod. Order No., Item, Variant, Location)`, on finished
production orders. This is the event-record-driven measurement: when
components actually started flowing through the prod order, and when
finished output actually landed in stock.

Where the prod order has no ILE Consumption rows — for raw extraction
items, intermediate phantom production, or BOM-less make-to-order — the
engine falls back to
`Production Order Header.Finishing Date − Production Order Header.Starting Date`.
Fallback samples are flagged in extract metadata so analysis can
distinguish event-driven from header-driven measurements.

Multi-output prod orders pose a special case. A single production
order produces several output lines (different items or variants).
Each output line emits its own lead-time sample at the same
prod-order-level value (`max(Output) − min(Consumption)`). They are
shared samples, not independent — the bootstrap layer carries a key
that prevents double-counting them within one draw.

Cancelled and scrapped prod orders (Status never reached `Finished`)
are excluded.

A **third secondary series** is computed for production reliability
analysis:
`max(ILE Output Posting Date) − Production Order Header.Ending Date`
where `Ending Date` is the planned finish. This planned-vs-actual
production delta feeds a future `Production reliability` reason code
(v2 scope) and does not feed the LTD bootstrap.

## 5.4 Hierarchical grain with promotion

Each recommendation row carries two grain fields:

- **Intended Grain** — `(Item, Variant, Location)`, matching the SKU
  the row is scoped at. The natural key for the upsert recommendation
  lifecycle (one Pending row per Intended Grain per Model Run).
- **Computed Grain** — the coarsest aggregation actually used.

Promotion logic at extract / classification time:

1. Try `(Item, Variant, Location)`.
2. If below threshold (defaults: <30 demand events or <10 lead-time
   samples; thresholds loosened by ABC class for class A items), fall
   back to `(Item, *, Location)`.
3. If still below threshold, fall back to `(Item, *, *)`.
4. If the coarsest grain still fails, emit the row with `null`
   recommendations and the reason code `Insufficient data`.

The Recommendation Confidence cascade caps at Medium for any row whose
Computed Grain is coarser than its Intended Grain — a planner
filtering for high-confidence rows never sees a promoted recommendation
masquerading as SKU-specific.

**Create new SKU detection.** When two finer-grain aggregates of the
same item — say `(Item, *, PARIS)` and `(Item, *, LYON)` — both pass
the threshold *and* their proposed Reorder Points differ by more than
the material-difference threshold (default 25%), the engine emits a
recommendation at the finer location-specific grain with reason code
`Item behaves differently by location`. If the SKU record does not yet
exist, the apply step (section 8.4) creates it. Symmetric logic
applies for variant splits: reason code `Variant-specific demand
pattern detected`.

This makes "create new SKU" an emergent output of the engine, not a
separate analytical workflow. The hierarchy lets the engine *discover*
where SKU granularity is warranted instead of assuming it everywhere.

# 6. Forecasting

## 6.1 Syntetos-Boylan classification drives method choice

Before any forecasting happens, each `(Item, Variant, Location)` series
is classified by `(ADI, CV²)`:

- `ADI < 1.32 AND CV² < 0.49` → **Smooth**.
- Otherwise → **Intermittent** (further sub-classified as `Intermittent
  / Erratic / Lumpy` for diagnostic purposes; the engine dispatches the
  same forecaster regardless of sub-class).

The Syntetos-Boylan thresholds are not arbitrary. They are the
empirical break-even points where intermittent-demand methods overtake
exponential smoothing on mean-squared error across a large variety of
demand series. They are the standard reference for "should I be using
Croston-family methods on this series?".

Cold-start series (less than 6 months of history) are classified
`Insufficient data` and bypass the forecaster entirely. The
recommendation row's Recommendation Confidence cascade caps at Low for
these via the data-sufficiency factor.

## 6.2 Two-branch forecaster: SBA for intermittent, AutoETS for smooth

**Intermittent branch: SBA (Syntetos-Boylan Approximation).** A
bias-corrected Croston-family method. Croston-original produces a
mean-biased upward estimate of roughly `p` (the inter-arrival rate); SBA
applies a `(1 − p/2)` correction. SBA converges to standard exponential
smoothing as `ADI → 1`, so a series mistakenly classified intermittent
still gets a graceful result. Chosen over TSB on grounds of stability
on long zero-runs (idle SKUs) typical in BC tenants.

**Smooth branch: AutoETS.** Automatic selection of the
`(Error, Trend, Seasonal)` tuple from `{N, A, M, Ad} × {N, A, Ad} ×
{N, A, M}` via AIC. Subsumes Holt, Holt-Winters, simple exponential
smoothing, and damped-trend variants as special cases. Seasonality
detection is guarded: a seasonal model is only allowed to win if at
least two full seasonal cycles of history are present (24 months for
monthly seasonality). Below that, the seasonal axis is forced to `N`
to prevent fitting noise.

**The forecaster's role under the bootstrap framework** is narrower
than the general forecasting literature implies. The forecast produces
only the *expected demand per period* — the mean. The LTD distribution's
*shape* is supplied by the bootstrap (section 4.4); the forecast
supplies only the *location*. This means prediction-interval calibration
of the forecaster does not feed back into the Reorder Point — the
quantile comes from the bootstrap, not from the forecaster's interval.

ARIMA and SARIMA were considered and deliberately excluded from the
first version: differencing-order selection, stationarity testing, and
seasonal differencing add substantial complexity to the test surface,
with marginal accuracy gain over AutoETS in inventory contexts.
Global ML forecasters (LightGBM, XGBoost, CatBoost) require cross-SKU
training data, which raises per-tenant data-isolation questions that
the first release does not engage with. Either family can be added
later if a customer's data demonstrates clear gains.

# 7. Validation

## 7.1 Fidelity-B simulator

The Monte Carlo simulator that produces current-vs-proposed comparison
metrics replays BC's reordering policy logic at *simplified* fidelity.
It does not re-implement `Codeunit 99000854 Inventory Profile
Offsetting` and downstream. The trade-off is a small modelling error
in exchange for unbounded engineering cost: a full BC-MRP replica
would be a multi-person-year project, fragile to BC platform updates,
and would require its own re-validation against every BC release.

What the simulator does:

1. **Seeds initial state from BC's open supply-and-demand stream.** The
   simulator does not invent today's projected inventory or its
   commitment list — it reads the same signed-event stream that BC's
   own availability views use, via the inclusion policy already
   established for this workspace's Max Sellable feature.
2. **Samples future demand** per period via the level-shifted bootstrap
   of section 4.4.
3. **Walks forward** day by day, tracking projected balance and
   applying the per-policy replay rules:
   - **Fixed Reorder Qty.**: continuous review; projected balance hits
     ROP → place order of Reorder Quantity. Round to `Order Multiple`,
     clip to `[Min Order Qty, Max Order Qty]`.
   - **Maximum Qty.**: continuous review; ROP trigger places an order
     for `Maximum Inventory − Projected Balance`.
   - **Lot-for-Lot**: periodic review honouring `Lot Accumulation
     Period`. Each period boundary, sum net demand and place one
     order.
   - **Order**: 1:1 pegging — one supply event per demand event.
   - `Safety Lead Time` shifts the order trigger forward by that many
     days.
4. **Honours existing scheduled receipts** (open POs, planned
   production output, in-transit transfers) as *deterministic* supplies
   on their planned dates. Lead-time risk is sampled only on new
   orders the simulator places.
5. **Aggregates per-run metrics** across `N` runs (`N = 10 000` for
   forward MC; `N = 1 000` for the historical replay backtest in
   section 7.2): stockout days, units short, average and maximum
   inventory, orders placed, fill rate `β`.

What the simulator deliberately does *not* do:

- `Dampener Period` and `Dampener Quantity` are treated as a noise
  floor — projected supply changes below the threshold are ignored.
  The Dampener-driven *reschedule* logic of BC's planning engine is
  not modelled.
- `Time Bucket` is approximated by continuous review for Fixed and
  Maximum Qty. policies. Order *timing* is therefore approximate, but
  service-level and inventory metrics — which depend on whether the
  policy triggers and how much it orders, not on which bucket the
  order lands in — are well-captured.
- `Overflow Level` and `Reschedule Tolerance` are not modelled.

The simulator is reproducible: seeded per
`(Item, Variant, Location, ModelRunId)`. Same inputs always produce
the same recommendation. This is required for the audit trail
(chapter 8) and for the on-demand recompute workflow (section 8.5).

The simulator is read-only against BC. It has no side effects on
business data and never holds locks during a run — a precondition for
running it in batch and on demand without contention.

## 7.2 Walk-forward replay backtest (B+D)

Every recommendation row carries *two* sets of metrics, not one:

- **Forward Monte Carlo**: `β_MC_current` and `β_MC_proposed`
  (alongside stockout probability, average inventory, working-capital
  impact) — computed by the simulator running forward from today
  against sampled future demand.
- **Historical replay**: `β_replay_current` and `β_replay_proposed` —
  computed by the same simulator running over the last 12 months of
  actual demand history. The recommendation that would have been
  generated *at the start* of the replay window is taken as fixed
  (strict temporal cutoff — the classifier, forecaster, lead-time
  extractor, and bootstrap all forbidden from reading post-cutoff
  data); the simulator then replays actual demand events through both
  the *current* and *proposed* parameter sets.

The planner sees both sets of `β` values side by side. Disagreement
between MC and replay is itself a signal — it tells the planner
whether the forward-looking model agrees with what would have happened
on real data. When the gap on `β_proposed` exceeds 15 percentage
points, the engine raises the `Replay diverges from forward
simulation` reason code and the Recommendation Confidence cascade caps
at Medium via the replay-agreement factor (section 7.4).

Two honest caveats this backtest carries:

- **The counterfactual demand problem.** Bootstrap samples from
  observed ILE-Sale demand. Demand was *suppressed* by historical
  stockouts — when stock hit zero, customers couldn't buy, didn't
  generate ILE rows. If the recommended parameters would have
  prevented those stockouts, real demand would have been higher than
  ILE shows. Bootstrap therefore *under-estimates* true demand for
  items with stockout history. The engine flags this via the
  `Forecast may under-estimate due to historical stockouts` reason
  code; it does not estimate the suppression. Open question 9.5 asks
  whether estimation is appropriate.
- **Insufficient history.** Items with less than `2 × H` of clean ILE
  history (where `H` is the per-SKU horizon from section 7.1) cannot
  support replay. The row carries `Replay unavailable: insufficient
  history`, the recommendation still ships with forward MC only, and
  the planner sees the explicit gap rather than a fabricated replay
  number.

## 7.3 Forecast Confidence

A scalar per `(Item, Variant, Location)` measuring fit quality of the
upstream forecaster only:

- **Smooth branch (AutoETS):** `1 − min(1, MASE)` on a rolling
  walk-forward window. MASE less than 1 means the model beats a naïve
  seasonal forecast; clip to `[0, 1]`.
- **Intermittent branch (SBA):** MASE is degenerate when many target
  values are zero. Use scaled RMSE on cumulative demand over rolling
  windows of length `max(LT_sku)`.
- **Cold-start (< 6 months history):** defined as 0.

Bucketed `Low < 0.4 / Medium 0.4–0.7 / High > 0.7` for UI. The raw
scalar is persisted for analytics — population-level forecast quality
trends are a useful operational signal even if the planner never
queries them directly.

## 7.4 Recommendation Confidence (min-of-factors cascade)

The bucketed *minimum* over five factors. The row carries the
**limiting factor** (the factor that pulled the cascade down) so a Low
rating is actionable rather than mysterious.

![Confidence cascade.](diagrams/03-confidence-cascade.png)

The five factors:

1. **Forecast Confidence bucket** — carries through directly.
2. **Data sufficiency** for bootstrap LTD: `< 10 LT samples OR
   < 30 demand events → Low`; `10–30 LT and 30–100 demand → Medium`;
   else `High`.
3. **Replay-vs-MC agreement** on `β`: `|β_replay − β_MC| < 5pp → High`;
   `5–15pp → Medium`; `> 15pp → Low`.
4. **Stockout-history cap**: actual inventory hit zero on ≥5 days in
   the history window → cap at Medium.
5. **Grain-promotion cap**: Computed Grain coarser than Intended
   Grain → cap at Medium.

Why `min` rather than weighted average: a weighted average lets one
good factor mask two bad ones. A SKU with a beautiful forecast fit but
only 4 lead-time samples gets a misleadingly high "confidence" — the
forecast is great; the LTD estimate is mush; the recommendation is
mush. The cascade is honest about the weakest link.

Defaults bias slightly toward Medium so High is earned, not assumed.

## 7.5 Reason codes (all 18)

Each recommendation row carries a **single Primary Reason Code** plus
an ordered list of **contributing reason codes**. Each code instance
records its quantified delta (`Old`, `New`, `Δ`, `Δ%`) so the planner
sees, for example, *"Lead time p95 increased: 14d → 21d (+50%)"*
rather than *"Lead time increased"*.

Two codes sit **outside** this list of 18: `Insufficient data` (no
recommendation possible at any grain — see section 5 cascade exit) and
`Zero lead time observed` (lead-time samples exist but every observed
LT is zero days, typically a missing PO Order Date in the source data).
These are row-killing codes: they appear *instead of* a recommendation,
not alongside one, with `null` ROP / Safety Stock fields. They surface
data-quality problems rather than hiding them behind a numerically-valid
but operationally-meaningless `ROP=0`.

The 18 codes fall into four families with different mechanics:

**Demand pattern (comparative — needs baseline):**
- `Demand increased` / `Demand decreased`
- `Demand variance increased` / `Demand variance decreased`
- `Intermittent demand detected`

**Lead time / supplier (comparative):**
- `Lead time increased` / `Lead time decreased`
- `Supplier reliability worsened` / `Supplier reliability improved`

**Risk (forward-looking, from MC + replay):**
- `Stockout risk too high`
- `Excess inventory risk too high`

**Setup / constraint (deterministic, no baseline):**
- `Reorder quantity below efficient order size`
- `Order multiple not respected`
- `MOQ impact detected`
- `Item behaves differently by location` (from the SKU-split trigger
  in section 5.4)
- `Variant-specific demand pattern detected`
- `Current reordering policy does not match demand pattern`
- `Forecast confidence too low, planner review required`

![Reason-code attribution.](diagrams/05-reason-code-attribution.png)

**Baseline rule** for comparative codes: prior applied recommendation's
snapshot if one exists and is recent (≤12 months old), else a rolling
12-month moving window prior to the current run. Where no baseline can
be established, the comparative codes do not fire and the row instead
carries `First recommendation, no baseline available`.

**Primary attribution** uses a two-axis decomposition: the recommender
is re-run twice with isolated inputs (`current demand + new LT`,
`new demand + current LT`). The axis whose isolated change contributes
more to the proposed ROP delta yields the Primary Reason; within that
axis, the code with the largest `|Δ%|` wins. Setup / constraint codes
become Primary only when no value-driving comparative code fires.

The contribution split is two-axis rather than per-code because
attributing fine-grained contribution to individual comparative codes
(e.g. separating *demand mean* from *demand variance* contribution to
ROP) requires more isolated recommender runs than the value justifies
at this version.

# 8. Business Central integration

This chapter covers the BC-side semantics — what the system does for
a planner, how it isolates per-company state, how it records what was
applied — at the level a domain reviewer needs to evaluate the
business behaviour.

## 8.1 Per-company silos

A BC tenant typically contains 1 to N companies (legal entities,
divisions, country units). BC's standard data model already silos
`Item`, `Item Ledger Entry`, `Stockkeeping Unit`, planning parameters,
and posting setup per company. The engine adopts the same shape: one
analytical run per company per scheduled invocation. `Item No. 1234`
in Company A and `Item No. 1234` in Company B are treated as
unrelated time series for forecasting purposes — even when they
refer to the same physical SKU at the corporate level.

Cross-company aggregation is **deferred to v2** as an opt-in feature.
The customer-side question of "is `Item 1234` in Company A really the
same physical SKU as `Item 1234` in Company B?" is an organisation-level
data question that most BC tenants have not answered. Building a cross-company
item cross-reference is a substantial workstream that is independent
of the math.

Practical consequences:

- The configuration holding `α` targets, ABC cuts, thresholds, and
  horizon parameters is per-company. Customers wanting consistent
  settings across companies copy the configuration via Configuration
  Package — the standard BC pattern.
- A planner with access to multiple companies sees a per-company
  review surface. A unified cross-company review inbox is a v2
  capability.
- Scheduled runs are configured per company; the weekly batch runs
  once per company.

## 8.2 Recommendation lifecycle

Each recommendation has an explicit lifecycle:

![Recommendation lifecycle.](diagrams/04-recommendation-lifecycle.png)

States:

- **Pending** — emitted by a Model Run. Replaceable: a subsequent
  Model Run for the same Intended Grain replaces a prior Pending row
  *if* the change in suggested values exceeds the hysteresis
  threshold; below threshold, the prior Pending row remains
  untouched. Replaced rows are preserved with a `Superseded By Model
  Run Id` reference for audit, but only the latest is shown for
  review.
- **Reviewed** — planner has seen the row, neither approved nor
  rejected yet. Used by planners triaging a large batch.
- **Approved** — planner has approved. In the first version, Approved
  and Applied are bundled (one click). A future *split* (approve now,
  apply later via a scheduled job) is reserved for v2 if a customer's
  governance pattern requires it.
- **Rejected** — planner has declined the recommendation. Immutable
  from this point; the next Model Run will produce a new Pending row
  if appropriate.
- **Applied** — the recommendation's values have been written to the
  `Item` or `Stockkeeping Unit`. Immutable.

**Hysteresis** prevents recommendation churn. A subsequent Model Run
emits a new Pending row only when the change versus the prior Pending
exceeds the threshold (defaults: >10% on Reorder Point, >1 day on
Safety Lead Time, policy change always emits regardless of magnitude).
Below the threshold the prior Pending remains the planner's current
view, even though internal calculations did re-run. This avoids the
"the number changed again this week" fatigue that erodes planner
trust.

## 8.3 Audit lineage and engine versioning

Every applied change traces back to the analytical run that produced
the recommendation. Each run carries:

- A unique run identifier (the chain's primary key).
- The company the run was scoped to.
- The run timestamp.
- The engine version, recorded with strict semantic versioning so
  forecaster swaps or simulator-rule changes bump the major version
  and additive features bump the minor.
- A snapshot of the configuration values that were active at run time
  — `α` targets, ABC cut points, thresholds, hysteresis values,
  horizon parameters, and every other tunable. Read-only after the
  run completes; treated as forward-compatible so engine upgrades
  remain able to read older snapshots.
- The data window the engine read from (historical period start and
  end), so a reader can tell *what data the engine saw*.
- Per-SKU success / failure / skip counts.

The recommendation row references its run; the audit log entry (one
per applied field change) references the same run. A reviewer asking
*"what value of `α` was in effect when this Reorder Point change was
applied fourteen months ago?"* gets a precise answer from the
recorded snapshot — not a reconstruction.

When the *currently installed* engine version differs from a row's
recorded version, the planner sees an inline note (*"Engine v1.2.1 →
current v1.4.0"*) on the row. The note is informational, not
apply-blocking: a planner who chooses to apply an older-version
recommendation can do so, and the audit captures both the row's
version and the apply timestamp. A planner who wants fresh
calculations can trigger an on-demand single-SKU recompute (section
8.5) before applying.

Reproducibility is honest. Even with engine version, configuration
snapshot, and data window pinned, regenerating the *exact*
recommendation also requires the ILE rows as they were at run time.
If BC data has been edited between the original run and a replay
attempt (returns posted, adjustments applied, cancelled documents),
the replay will diverge. The lineage answer is *"on date D, the
engine saw data X and produced recommendation Y"*, not *"the engine
would still produce Y today"*.

## 8.4 Approve & apply workflow

The first version uses **bundled Approve & Apply**: a single action
on each recommendation, with the change written to the `Item` or
`Stockkeeping Unit` immediately. The decoupled *"approve now, apply
later via a nightly job"* shape is a real governance pattern for some
customers and is reserved for a later release.

**Inline override.** The planner can edit the suggested values
in-place on the card before clicking Approve & Apply. The audit log
records *both* the original recommendation value and the
actually-applied value, with a `Was Overridden` boolean. Override-rate
analytics — a saved query against the audit log filtered by
`Was Overridden = true`, grouped by Item Category or Vendor — is the
single most useful diagnostic the system produces. It tells the
engine where it is systematically wrong without requiring additional
instrumentation.

**Bulk Approve & Apply** is available via the standard BC multi-select
on the list page. Per-row atomicity: one failure does not abort the
batch; failed rows stay `Pending` with the error captured. Inline
override is not available in the bulk path — a planner overriding
values should use the single-row card view.

**Conflict detection.** On apply, the engine re-reads the current
`Item.Reorder Point` (or whichever field). If the value has drifted
from the recommendation's stored "current value at recommendation
time" — for example, because a planner manually edited the Item Card
between the recommendation being generated and the planner clicking
Apply — the engine surfaces a confirmation dialog requiring explicit
acknowledgement. The recommendation's snapshot of *what current was*
is part of the row's data so this check is local and cheap.

**SKU auto-create on apply.** When the recommendation's Intended Grain
is SKU and no `Stockkeeping Unit` record exists for that
`(Item, Variant, Location)`, applying the recommendation creates one.
Non-planning fields are copied from the Item Card following BC's
standard "Get from Item" behaviour; planning fields are written from
the recommendation. The audit log records the SKU creation explicitly,
separate from the planning-field changes.

This auto-create behaviour is **toggleable per company** in setup
(`Allow recommendations to auto-create SKUs on apply`, default ON).
Customers with strict master-data governance can set it OFF, in which
case applying a recommendation at SKU Intended Grain without an
existing SKU is blocked with a directive to create the SKU manually
first.

**No structured rollback.** The audit log is append-only. To "revert"
an applied change, a planner manually edits the `Item` or `SKU` back —
that edit is itself audited as a new entry. A dedicated rollback
action would imply transactional semantics across an immutable
history; the workspace does not pretend that semantic exists.

**Permissions** are split into two roles:

- *Planning Optimizer Reviewer* — read recommendations, set
  `Reviewed`, `Rejected`. Cannot Apply.
- *Planning Optimizer Approver* — above plus Approve & Apply.

The change log is append-only; entries cannot be edited or deleted
once written. The four-eyes split of *Approve* (status change)
versus *Apply* (write to Item or SKU) is reserved for a later release
if a customer's governance requires it.

## 8.5 Run cadence

Two complementary triggers:

**Weekly scheduled run per company.** A scheduled run per company per
cadence triggers the full pipeline: the active configuration is
snapshotted, history is read, the engine produces recommendations,
and Pending rows are upserted into the review surface. Status and
per-SKU counts are recorded against the run. A single-SKU failure
does not abort the batch; failed SKUs are recorded with an error
reason and processing continues.

**On-demand single-SKU recompute.** An action on the Item Card and the
SKU Card triggers a single-SKU run via the same pipeline. Returns
within seconds for one SKU. Reuses the most recent batch's replay
numbers unless the planner explicitly selects "re-run replay too" —
replay over 12 months is expensive enough to be worth deferring to the
weekly batch in routine cases.

The on-demand workflow is the planner's deep-dive tool: a planner
investigating an anomaly on Item X clicks Recompute on the Item Card
and gets a fresh recommendation a few seconds later, with fresh
Model Run lineage.

# 9. Open questions for review

Prompts where the reviewer's experience and theoretical expertise
would most directly shape the design. Each is self-contained — there
is no need to flip back to the relevant chapter.

## 9.1 Defaults for α per ABC class

*We propose default service-level targets of A = 98%, B = 95%, C = 90%
(with an Unclassified default of 95%), per company, customer-tunable.
A is `Strategic`-flagged or top-revenue items by Pareto cut; C is the
long-tail. Are these defaults sensible for the BC tenants you have
seen across distributors, manufacturers, and project-driven
businesses? Are industry-specific overrides worth promoting from
"customer-tunable" to "ship-with-different-defaults"?*

## 9.2 Material-difference threshold for SKU split

*The engine recommends creating a new SKU at the location-specific
grain when two location aggregates of the same item disagree on
proposed Reorder Point by more than 25%. This threshold drives one of
the engine's more consequential outputs — a new master-data record.
Is 25% the right starting point? In your experience, what magnitude
of behavioural difference between locations or variants justifies an
SKU-level planning override versus a planner accepting the Item-level
default?*

## 9.3 Bootstrap honesty versus textbook familiarity

*We deliberately chose empirical bootstrap of historical
`(lead-time, demand-window)` pairs over the textbook closed-form
formula `ROP = μ_D·μ_L + z_α · √(μ_L·σ_D² + μ_D²·σ_L²)`. The bootstrap
is more correct on BC-typical data (intermittent demand, right-skewed
lead times), but the closed form is what most planning consultants
and Microsoft training material reach for. Does this trade-off
preserve enough textbook recognisability for planners doing
back-of-envelope sanity-checks against our recommendations? Should we
display the closed-form result alongside the bootstrap result as a
diagnostic, or is that confusing?*

## 9.4 SBA over Croston-original and TSB

*For intermittent demand series, we chose SBA (the Syntetos-Boylan
bias-corrected variant of Croston) as the single forecaster, with no
runtime switching to Croston-original or TSB. SBA wins on stability
across long zero-runs. Does this match the practice you have seen, or
do specific demand patterns in your experience clearly favour Croston
or TSB?*

## 9.5 Suppressed demand: flag or estimate?

*When the historical inventory hit zero on multiple days, customers
could not buy. The ILE rows we bootstrap from under-represent the
demand that would have arrived under non-stockout conditions. We flag
this rather than estimate the suppression (`Forecast may under-estimate
due to historical stockouts` reason code), capping the Recommendation
Confidence at Medium. Is there an acceptable approach you have used to
estimate the suppression — for example, interpolation from ATP gaps,
or comparison against demand patterns at peer SKUs that did not
stockout in the same window — that we should consider, or is flagging
the right honest answer?*

## 9.6 All-sign ILE as the definition of demand

*Historical demand is defined as the sum of every negative-quantity
`Item Ledger Entry` row at the location grain — no `Entry Type`
filter. Sale, Consumption, Assembly Consumption, Negative Adjustment,
and source-side Transfer rows all count. Returns net automatically.
This is more inclusive than the typical BC tenant's analytics view of
"demand". Does this match the practice you would recommend for
parameter-recommendation analytics, or are there `Entry Type` or
`Source Type` values you would deliberately exclude (for example,
specific adjustment reason codes for cycle-count corrections that
look like demand but are not)?*

## 9.7 Conservative policy-change ruleset

*The engine recommends changing the `Reordering Policy` field only in
three named cases: (a) policy is blank but ≥6 months of demand history
exists; (b) policy is `Fixed Reorder Qty.` or `Maximum Qty.` and the
Syntetos-Boylan class is intermittent / lumpy / erratic and ABC class
is B or C; (c) policy is push-type but `Manufacturing Policy =
Make-to-Order`. Outside these three cases the engine keeps the
current policy and only suggests new values for the policy's active
fields. Too conservative? Too aggressive? Are there additional named
cases you would recommend triggering a policy change?*

## 9.8 SKU auto-create on apply: default ON or OFF?

*When the recommendation's Intended Grain is SKU and no
`Stockkeeping Unit` record exists, applying the recommendation
auto-creates the SKU. We default this behaviour to ON, with a
per-company setup toggle to turn it OFF. Customers with strict
master-data governance can opt out. Is ON the right default for the
broad BC market in your experience, or would OFF — explicit planner
action to create the SKU first, then apply — be the safer default?*

## 9.9 Multi-company silos as the default

*A BC tenant typically contains multiple companies. We default to
per-company isolation: each company gets its own Model Run, its own
recommendations, no cross-company aggregation. Cross-company
aggregation (when an item exists in multiple companies and the
customer maintains a cross-reference) is reserved for v2. Does this
match your experience of typical multi-company BC implementations, or
do you see customer patterns where cross-company aggregation should
be the default rather than an opt-in?*

## 9.10 Override-rate analytics as the primary diagnostic

*A query against the Change Log filtered by `Was Overridden = true`,
grouped by Item Category or Vendor, surfaces where the engine is
systematically wrong: planners agreeing with the direction but
disagreeing with the magnitude. We treat this as the single most
valuable diagnostic the system produces and surface it via a saved
query rather than a dashboard. Is this the right primary diagnostic in
your experience, or are there other queries (rejection-rate by reason
code, apply-time-since-emission distributions, replay-divergence
volume) that you would rank higher?*

# Decision register (appendix A)

Index of every choice the document makes, the chapter it is discussed
in, and the open question that places it back on the table for
review. Quick reference for per-decision comments.

| §    | Choice described in the document | Open question |
|------|----------------------------------|---------------|
| 4.1  | Service-level targeting per ABC class, not total-cost minimisation | 9.1 |
| 4.2  | ABC basis = revenue Pareto + Strategic override | — |
| 4.3  | Cycle service level α as targeting input, fill rate β as reported output | — |
| 4.4  | Reorder Point and Safety Stock from bootstrap LTD | 9.3, 9.5 |
| 4.5  | Reorder Quantity via EOQ-when-clean / POQ-otherwise | — |
| 4.6  | Conservative Reordering Policy mismatch rules | 9.7 |
| 5.1  | Demand defined as all signed ILE, no Entry Type filter | 9.6 |
| 5.2  | Lead time per replenishment system, Order-to-Receipt primary | — |
| 5.3  | Manufactured-item LT: ILE Output–Consumption pairing primary, Header fallback | — |
| 5.4  | Hierarchical grain with promotion; new-SKU material-difference trigger | 9.2 |
| 6.1  | Syntetos-Boylan classification with ADI = 1.32 / CV² = 0.49 thresholds | — |
| 6.2  | Two-branch forecaster: SBA intermittent, AutoETS smooth | 9.4 |
| 7.1  | Fidelity-B simulator (simplified policy replay) | — |
| 7.2  | Walk-forward replay backtest per recommendation | — |
| 7.3  | Forecast Confidence from walk-forward MASE / scaled RMSE | — |
| 7.4  | Recommendation Confidence as min-of-factors cascade with limiting factor | — |
| 7.5  | All eighteen reason codes; single Primary + contributing list; two-axis attribution | 9.10 |
| 8.1  | Per-company silos; cross-company aggregation deferred | 9.9 |
| 8.2  | Recommendation lifecycle: Pending → Reviewed → Approved/Rejected → Applied, with upsert + hysteresis | — |
| 8.3  | Audit lineage with engine version, configuration snapshot, and data window from the first release | — |
| 8.4  | Row-level Approve & Apply, inline override, bulk via multi-select, SKU auto-create, conflict detection, no structured rollback | 9.8 |
| 8.5  | Weekly scheduled run per company plus on-demand single-SKU recompute | — |

# References (appendix B)

**Inventory theory.**

- Silver, E. A., Pyke, D. F., and Thomas, D. J. *Inventory and
  Production Management in Supply Chains.* 4th edition, CRC Press,
  2017. Reference for the cycle service level / fill rate distinction,
  EOQ derivation, and continuous- versus periodic-review policy
  treatment.
- Axsäter, S. *Inventory Control.* 3rd edition, Springer, 2015.
  Reference for the closed-form `ROP = μ_D·μ_L + z_α · √(...)`
  formula and its Normal-Normal assumption space.

**Intermittent demand forecasting.**

- Croston, J. D. *Forecasting and Stock Control for Intermittent
  Demands.* Operational Research Quarterly, 23(3), 1972.
- Syntetos, A. A., and Boylan, J. E. *The Accuracy of Intermittent
  Demand Estimates.* International Journal of Forecasting, 21(2),
  2005. Reference for the SBA bias correction and the
  `(ADI = 1.32, CV² = 0.49)` classification thresholds.
- Teunter, R. H., Syntetos, A. A., and Babai, M. Z. *Intermittent
  Demand: Linking Forecasting to Inventory Obsolescence.* European
  Journal of Operational Research, 214(3), 2011. Reference for TSB
  (considered and not chosen for this version).

**State-space exponential smoothing.**

- Hyndman, R. J., Koehler, A. B., Ord, J. K., and Snyder, R. D.
  *Forecasting with Exponential Smoothing: The State Space Approach.*
  Springer, 2008. Reference for the ETS `(Error, Trend, Seasonal)`
  taxonomy and the AutoETS AIC-based selection used in this engine.

**Forecast evaluation.**

- Hyndman, R. J., and Koehler, A. B. *Another Look at Measures of
  Forecast Accuracy.* International Journal of Forecasting, 22(4),
  2006. Reference for the MASE metric used in Forecast Confidence
  scoring.

**Business Central standard objects.**

- *Codeunit 99000854 Inventory Profile Offsetting.* The reference
  implementation for forward supply-and-demand profile construction in
  BC's planning engine. Cited as the *not-re-implemented* reference
  for the Fidelity-B simulator (section 7.1).
- *Codeunit 5790 Available to Promise.* BC's standard ATP calculation.
  Cited in the workspace's existing Max Sellable feature (out of scope
  for this review) and reused for the open-supply-and-demand seed of
  the Fidelity-B simulator.
- Microsoft Dynamics 365 Business Central documentation on
  *Reordering Policy*, *Reorder Point*, *Reorder Quantity*,
  *Maximum Inventory*, *Safety Stock Quantity*, *Safety Lead Time*,
  *Lead Time Calculation*, *Lot Accumulation Period*, *Dampener
  Period*, *Dampener Quantity*, and *Overflow Level*. Cited
  throughout chapter 4 and section 7.1.

— *End of document* —
