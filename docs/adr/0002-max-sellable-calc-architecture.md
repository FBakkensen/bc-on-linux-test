# Max Sellable Quantity — calculation architecture and delivery

The Max Sellable Qty calculation is implemented as a pure compute proc on a
dedicated codeunit. Two delivery paths share the proc — a synchronous notification
path triggered from Sales Line `OnValidate`, and an asynchronous FactBox path
driven by a BC Page Background Task. No caching, no preemptive optimization.

## Calculation shape

For each `(Item, Variant, Location, ShipmentDate)` the proc:

1. Sets `Variant Filter` and `Location Filter` on the Item record.
2. Computes a starting on-hand at `min(ShipmentDate, WorkDate())` from Item
   Ledger Entries.
3. Collects signed events (Date, ±Qty in base UoM) per source, by calling
   each source table's standard `FilterLinesWithItemToPlan(Item)` method
   (Sales Line, Purchase Line, Transfer Line, Production Order Line + Component,
   Assembly Header + Line, Service Line, Job/Project Planning Line). The
   per-source filter logic is owned by BaseApp; we iterate the result.
4. Sweeps the merged event stream forward from `min(ShipmentDate, WorkDate())`,
   tracking the minimum running balance.
5. Returns `max(0, minBalance)`.

The line currently being edited is passed in as `ExcludingSalesLine` and
filtered out of the Sales Line collection step (self-exclusion at validate time).

## Why per-source `FilterLinesWithItemToPlan`, not direct enumeration

Each BaseApp source table exposes a canonical filter method —
`FilterLinesWithItemToPlan(Item)` (and variants like `(Item, IncludeFirmPlanned)`
for Prod. Order Line). Calling it inherits BC's current filter definitions for
that source automatically. If Microsoft adds a new Document Type or a Status
value in a future release, our calc picks up the change without us editing
filter lists in our own code. ADR 0001's inclusion policy is therefore
referenced from BaseApp, not duplicated in this project.

## Why not CU 99000854 *Inventory Profile Offsetting*

The MRP profile builder owns the equivalent enumeration but is built for
planning context — it materializes planning temp records, has side effects,
and includes sources we explicitly exclude (notably blanket assembly
components). Filtering its output to undo those quirks is uglier than
collecting events ourselves.

## Delivery — synchronous notification path

Sales Line `OnValidate` of `Quantity`, `Shipment Date`, `No.`, `Variant Code`,
`Location Code` calls a gated handler:

```
if "Max Sellable Warning" disabled                          → skip
if "Stockout Warning" enabled and CU 311 reports a hit      → skip (standard wins)
if MaxSellableCalc.Calculate(...) < entered Qty             → raise our notification
```

The notification flows through `NotificationLifecycleMgt`. Synchronous because
it must reach the user before they move off the line; latency is the user's
typing speed.

## Delivery — FactBox path via Page Background Task

The Max Sellable FactBox on the Sales Order page enqueues a Page Background
Task on selection change. The PBT calls the same `Calculate` proc, returns
the result via dictionary, and the page's `OnPageBackgroundTaskCompleted`
trigger updates the displayed value. The compute proc is therefore
PBT-safe: no `Confirm`, no `Message`, no `Notification`, no UI access.

## Why PBT, not synchronous FactBox

Hedge for a likely future redesign. If validate-time notifications turn out
to be too chatty in practice, the notification moves from `OnValidate` to
"on release of sales order" (single point, less noise). When that happens,
the FactBox becomes the user's only live signal during line entry — it must
update quickly and without blocking the page render. Using PBT now means
the FactBox is already on a non-blocking path; the future move requires no
redesign of the FactBox.

## No caching in v1

The ATP path runs only when the CU 311 inventory check passes (rare relative
to total validates), and the per-`(Item, Variant, Location)` event walk is
bounded by real DB rows. Caching would add invalidation complexity (e.g. a
co-worker posting a Purchase Receipt would have to invalidate cached values
across all sessions). We measure latency on real data before introducing
any cache.

## Consequences

- `MaxSellableCalc.Calculate` must remain a pure read-only function. Any
  side effect (logging, telemetry, lazy writes) breaks the PBT path and
  the parallel-session safety it relies on.
- The four deliberate-deviation points from ADR 0001 are implemented via
  *how we call* `FilterLinesWithItemToPlan` (e.g. `IncludeFirmPlanned := true`
  for Prod. Order Line; `Document Type = Order` only for Assembly Line so
  blanket-component demand is excluded) — not via post-filtering the result.
  Reviewers should check the *call sites* against ADR 0001, not the BaseApp
  filters themselves.
