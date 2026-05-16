# Service-level targeting per ABC class, not total-cost minimization

The planning parameter recommendation engine optimizes for a service-level
target — Reorder Point = α-quantile of lead-time demand, where `α` comes from
a target Cycle Service Level set per ABC class. The engine does **not**
optimize a total-cost objective (carrying + stockout + ordering + setup +
expediting + obsolescence). Recommendations for Reorder Quantity use EOQ
where the required cost inputs are reliably populated and fall back to a
coverage-period rule (POQ) otherwise.

## Why not total-cost minimization

The classical "minimize expected total cost subject to constraints" framing
needs per-SKU stockout cost, lost-sales cost, expediting premium, and
obsolescence write-off rate. None of these are reliably present in BC tenants.
`Item.Order Cost` is sometimes populated; annual carrying-cost rate is
universally absent (it is a finance assumption, not a BC field). A total-cost
engine looks mathematically rigorous but runs on guessed coefficients —
recommendations are confidently wrong rather than transparently uncertain.

Service-level targeting is honest about what BC tenants actually know: how
much service they want. The customer sets `α` per ABC class (defaults
A=98%, B=95%, C=90%) and the engine produces parameters that hit it.
Stockout probability and fill rate are reported as Monte Carlo metrics so
the planner sees the consequence of the chosen `α` — but they are outputs,
not optimization inputs.

## ABC classification basis

Annual revenue contribution (posted sales value over a configurable window,
default 12 months) with a manual `Strategic` override flag on the Item / SKU
that pins a record to class A regardless of revenue rank. Reasons in order:
revenue data is the cleanest of the four candidate inputs (margin / cost of
consumption / business importance) in a typical BC tenant; the Pareto cut
is what every planner already understands; the override handles the 30
strategic-but-low-volume items that don't fit the curve without forcing the
engine to model "business importance."

New items (no posted revenue history) are tagged `Unclassified` and given a
conservative default `α`, not silently dropped to class C.

## Two service-level metrics, two distinct fields

Cycle Service Level (`α`) is the targeting input. Fill Rate (`β`) is the
reported output, computed via Monte Carlo simulation (see ADR 0007). They
are **not interchangeable**: a 95% `α` corresponds to roughly 98–99% `β` on
smooth demand and 85–90% `β` on spiky demand. The recommendation row stores
both in distinct, distinctly-labelled fields so planners and consultants
cannot conflate them.

## Consequences

- The cost-input fields named in the wider spec (stockout cost, expediting
  cost, obsolescence rate, lost-sales cost) are not engine inputs. The
  recommendation engine does not read them, does not validate them, and
  does not surface recommendations driven by them.
- Reorder Quantity is decoupled from the service-level math. It is computed
  via EOQ-when-`Order Cost`-populated / POQ-otherwise (default coverage
  A=1mo, B=2mo, C=3mo), then clipped to MOQ / Max Order Qty / Order
  Multiple. A reason code on each row records which method was used.
- A future move to total-cost minimization would require populated cost
  inputs across the customer's item master and is not a sandbox-phase
  concern. The engine architecture does not preclude it; the math just
  picks the simpler honest stance.
