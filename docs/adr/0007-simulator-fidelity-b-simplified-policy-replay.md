# Monte Carlo simulator replays BC reordering at simplified fidelity

The Monte Carlo simulator that produces current-vs-proposed comparison
metrics (service level, fill rate, stockout probability, inventory level,
ordering frequency) replays BC's reordering policy logic at *simplified*
fidelity. It does not re-implement the BC planning engine (CU 99000854
*Inventory Profile Offsetting* + downstream). The trade-off is a small
modelling error vs unbounded engineering cost — a re-implementation would
be a multi-person-year project, fragile to BC version updates, and
re-validating it against each platform release would be its own ongoing
workstream.

## What the simulator does

For each `(Item, Variant, Location, parameter set)`:

1. **Seeds initial state from the existing Max Sellable event stream**
   (ADR 0001 inclusion policy). Today's projected balance, scheduled
   supplies, and committed demand land in the simulator's start state
   unchanged — same code, same inclusion list, no parallel implementation
   of "what is supply / what is demand right now".
2. **Samples future demand** per period via bootstrap-shift-by-forecast
   (ADR 0006).
3. **Walks forward**, applying the BC reordering policy:
   - **Fixed Reorder Qty.**: continuous review; projected balance hits ROP
     → place order of ROQ. Round to Order Multiple, clip to
     [Min Order Qty, Max Order Qty].
   - **Maximum Qty.**: continuous review; projected balance hits ROP →
     order to fill to Maximum Inventory. Same rounding and clipping.
   - **Lot-for-Lot**: periodic review honouring `Lot Accumulation Period`.
     At each period boundary, sum net demand over the period and place one
     order, MOQ/Multiple-rounded.
   - **Order**: 1:1 pegging. Each demand event triggers one supply event
     with a sampled lead time.
   - `Safety Lead Time` shifts the order trigger forward by that many
     days.
4. **Honours existing scheduled receipts as deterministic** supplies on
   their planned dates. Only orders the simulator itself places are
   subject to sampled lead time.
5. **Tracks metrics**: stockout days, units short, average inventory, max
   inventory, orders placed, fill rate `β`. Aggregates across `N` runs —
   10K for forward MC (the published current-vs-proposed numbers), 1K for
   the historical replay backtest (the second sanity-check number that
   ships on every recommendation row).

## What the simulator does not do

- **`Dampener Period` and `Dampener Quantity`** are treated as a noise
  floor — projected supply changes below the dampener threshold are
  ignored. The Dampener-driven *exact* reschedule logic of BC's planning
  engine is not modelled.
- **`Time Bucket`** is approximated by continuous review for Fixed Reorder
  Qty. and Maximum Qty. policies. BC's actual planning runs in buckets,
  not continuously, so simulated order *timing* is approximate.
- **`Overflow Level`** is not modelled.
- **`Reschedule Tolerance`** is not modelled — orders the simulator
  places arrive on their sampled date, not on a snapped bucket boundary.

## Calibration via backtest, not via more fidelity

The gap between simulator output and actual BC behaviour is measured by
the B+D backtest (each recommendation row ships with a forward Monte Carlo
result *and* a 12-month historical replay result for both current and
proposed parameters; large divergence raises a `Replay diverges from
forward simulation` flag and caps Recommendation Confidence at Medium via
one of the five cascade factors). A systematic gap becomes a calibration
task — adjust the simplified replay's parameters, not a re-architecture.

## Why not textbook continuous-review

A purely theoretical `(s, Q)` or `(s, S)` simulator that ignores BC's
planning bucket, dampeners, and lot accumulation entirely would diverge
visibly from what the planner sees in BC's worksheet — destroying the
credibility of the current-vs-proposed comparison. Fidelity B sits
deliberately between "textbook" and "BC-exact": close enough to BC that
planners recognise the behaviour, simple enough to ship.

## Consequences

- Recommended ROP and ROQ values will produce the simulated service-level
  metrics in the simulator's world. The gap between simulator-world and
  BC-world is the modelling error backtests measure; recommendations
  carrying a large gap are flagged for planner review.
- Customers running heavily Dampener-tuned planning configurations may see
  larger gaps than typical. The replay-vs-MC agreement factor in the
  Recommendation Confidence cascade surfaces this without the engine
  needing to know which customer.
- The simulator is reproducible: seeded by `(Item, Variant, Location,
  ModelRunId)`. Same inputs always produce the same recommendation. The
  audit log captures `ModelRunId` on every applied change so a historical
  recommendation can be regenerated bit-for-bit at any time.
- The simulator does not write to BC and has no UI side-effects. Same
  pure-compute-proc invariant as `MaxSellableCalc.Calculate` (ADR 0002) —
  a precondition for running it under Page Background Task or in batch
  without contention.
