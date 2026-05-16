# Domain glossary

Canonical language for this workspace. Terms here are load-bearing — when in
doubt, use these words and not synonyms.

## Available Inventory

The quantity of an item physically on hand (plus, depending on the asker, in
transit and on open documents in aggregate). Not date-aware. In BC, surfaced
via `Item.Inventory` and the date-less `Qty. on Sales Order`,
`Qty. on Purch. Order`, `Qty. in Transit`, `Qty. on Prod. Order`,
`Qty. on Asm. Order`, `Qty. on Service Order`, `Qty. on Job Order`, …
flow-fields. Answers *"do I have stock?"*.

## Projected Available Balance

The signed cumulative balance of an item at a specific future date `t`:

```
ProjectedAvailableBalance(t) = Inventory
                             + Σ(scheduled receipts dated ≤ t)
                             − Σ(gross requirements dated ≤ t)
```

across all signed event sources (item ledger, sales lines, purchase lines,
transfer in/out, prod. order output + components, asm. output + components,
service lines, job planning lines, …). Surfaced in BC by page 5530
*Item Availability by Date*. Answers *"what will the balance look like on
date t?"*.

## Available-to-Promise (ATP) Quantity

The quantity that can be committed to a new sales line on date `D` without
driving Projected Available Balance below zero at any `t ≥ D`:

```
ATP(D) = max(0, min over t ≥ D of ProjectedAvailableBalance(t))
```

Distinguished from Available Inventory: ATP respects already-committed future
demand; Available Inventory does not. Related BC code lives in
Codeunit 5790 *Available to Promise*.

## Max Sellable Quantity

This project's wrapper concept. The ATP Quantity for a specific
`(Item, Variant, Location, ShipmentDate)` tuple, exposed via a project-owned
codeunit. Intended for use at sales line entry/validation time.

---

# Planning parameter optimization (sandbox)

A separate workstream from Max Sellable. Targets recommending updated Reorder
Point, Safety Stock, Reorder Quantity, and Reordering Policy values on Items,
Stockkeeping Units, and Variants based on historical demand and lead-time
behaviour. Currently sandbox/R&D — math proven in a Python package before BC
integration. Vocabulary below is provisional and may move to a sibling
`CONTEXT-PLANNING.md` if the workstream graduates.

## Lead-Time Demand (LTD)

The random variable `LTD = Σ_{t=t₀..t₀+L} D_t` — demand summed over a single
realised replenishment lead time, where both `L` and `D_t` are random. The
α-quantile of the LTD distribution is the textbook formula for Reorder Point
under cycle-service-level targeting. In this project, LTD is estimated
empirically by bootstrap-sampling `(lead time, demand window)` pairs from
historical data — never closed-form (see ADR 0006).

## Cycle Service Level (α)

`P(no stockout during a replenishment cycle)`. The *targeting* input — the
recommendation engine accepts an `α` per ABC class (defaults A=98%, B=95%,
C=90%) and sets the Reorder Point to the α-quantile of the LTD distribution.
Distinct from Fill Rate; the two are not interchangeable.

## Fill Rate (β)

Expected fraction of demand *units* served from stock without backorder. The
*reported* output — Monte Carlo simulation reports `β` alongside `α` so the
planner sees the customer-facing consequence of the chosen `α`. `β ≠ α`:
spiky demand makes `β` lag `α` by 5–10 percentage points; smooth demand makes
`β` nearly equal `α`. Two distinct fields on every recommendation row;
conflating them is the failure mode this glossary exists to prevent.

## Recommendation Grain

The `(Item No., Variant Code, Location Code)` tuple a recommendation is
computed at. The *intended grain* matches the Stockkeeping Unit. The *computed
grain* is the coarsest aggregation actually used when the intended grain has
too few observations (default: < 30 demand events or < 10 lead-time samples).
Promotion path: `(Item, Variant, Location) → (Item, *, Location) →
(Item, *, *)`. Both grains are recorded on the row; the planner sees when SKU
specificity is real evidence vs aggregation necessity (see ADR 0008).

## Forecast Confidence

A scalar per `(Item, Variant, Location)` measuring the fit quality of the
upstream forecast model only. For smooth-demand series (AutoETS branch):
`1 − min(1, MASE)` on a rolling walk-forward window. For intermittent series
(SBA branch): scaled RMSE on cumulative demand over rolling windows of length
`max(LT)`. Cold-start series (< 6 months history) defined as 0. Bucketed
Low / Medium / High for the planner UI; raw scalar persisted for analytics.

## Recommendation Confidence

The bucketed minimum (cascade-cap) over five factors: Forecast Confidence,
data sufficiency for bootstrap LTD, replay-vs-MC agreement on `β`,
stockout-history cap, and grain-promotion cap. The row carries the *limiting*
factor so a Low rating is actionable. Distinct from Forecast Confidence
because forecast quality is one input among five — a perfect forecaster on a
SKU with 4 lead-time samples still produces an unreliable recommendation.
