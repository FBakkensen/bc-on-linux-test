# Max Sellable Quantity inclusion policy follows BC standard

The Max Sellable Quantity calculation (the ATP-style number this project
exposes for a `(Item, Variant, Location, ShipmentDate)` tuple) sums the same
signed events that BC standard treats as committed future supply and demand —
the document-state filters baked into BC's Item FlowFields and CU 99000854
*Inventory Profile Offsetting*. We deliberately align with BC standard rather
than invent our own inclusion list, so that a sales rep's Max Sellable number
never diverges from what BC's own availability pages say about the same item.

## Decisions

**Included** (mirrors BC standard):

- Sales Lines — `Document Type ∈ {Order, Return Order}`, `Type = Item`
- Purchase Lines — `Document Type ∈ {Order, Return Order}`, `Type = Item`
- Transfer Lines — in-transit, receipt-side, shipment-side, all with `Derived From Line No. = 0`
- Production Order Lines (supply) and Components (demand) — `Status ∈ {Planned, Firm Planned, Released}`
- Assembly Headers and Lines — `Document Type = Order` only
- Service Lines — `Document Type = Order`, `Type = Item`
- Job (Project) Planning Lines — `Status = Order`, `Type = Item` (no `Line Type` filter)
- Item Ledger Entries — for the running on-hand baseline

**Excluded** (mirrors BC standard):

- All Quotes (sales, purchase)
- Blanket Order headers (BC has info-only FlowFields for them; the projection itself never sums them)
- Invoices, Credit Memos
- Production Orders with `Status ∈ {Simulated, Finished}`
- Requisition Lines and Planning Components (MRP suggestions, not commitments — BC keeps them in a separate bucket and so do we)
- Lot / serial item-tracking allocation (out of scope; this calc is SKU-level)

## Deliberate trade-off points

Four places BC standard itself is ambiguous or inconsistent, where we picked a side:

1. **Production status set: include Planned + Firm Planned + Released.** Matches
   `Qty. on Prod. Order` (`MfgItem.TableExt.al:229-243`) and CU 99000854. The
   narrower `Scheduled Receipt (Qty.)` flavor (Firm Planned + Released only;
   `MfgItem.TableExt.al:28-42`) is an MRP-internal view, not the right shape for
   "how much can I commit right now."

2. **Assembly Blanket Lines: exclude.** CU 99000854 special-cases them
   (`AssemblyLineInvtProfile.Codeunit.al:94`) but `Qty. on Asm. Component`
   does not. We follow the FlowField — symmetric with our treatment of all
   other blanket-order sources, and a blanket assembly component is not a
   real near-term demand commitment.

3. **Job Planning Line types: replicate BC, including the double-count.** BC
   filters only on `Status = Order` — no `Line Type` filter — so lines
   flagged as `Both Budget and Billable` are counted twice. De-duping would
   be a deviation from standard, and Max Sellable would diverge from BC's
   own availability views. We accept the BC behavior verbatim.

4. **SKU-level granularity only.** Item + Variant + Location, no lot / serial
   tracking. Lot-/serial-aware ATP is a substantively different problem
   (allocation of specific tracked units across competing demands over time)
   and is explicitly out of scope.

## Where the deviations live

Originally encoded in one place: `BCEventSource.CollectEvents` (the scalar
Max Sellable path). Slice #15 added the Open SD per-source AL Queries
(`Open SD Sales`, `Open SD Prod Order Line`, …) as the simulator's
initial-state extract per ADR 0007; those Queries serve a paginated OData
GET and therefore can't call back into `BCEventSource` server-side. The
result is that the inclusion policy now has two encodings:

- **Deviations #1 (production statuses) and #2 (assembly blanket)** —
  re-encoded in each Open SD Query's `DataItemTableFilter`, mirroring
  what `FilterLinesWithItemToPlan` / `SetItemToPlanFilters` apply on the
  scalar path.
- **Deviation #3 (job double-count)** — moved Python-side, in
  `extracts/bc_api.project_job_planning`. A SELECT can't emit a row
  twice, so the doubling can't live in AL.
- **Deviation #4 (SKU granularity)** — inherent in both paths; nothing
  to encode.

Drift between the two encodings is held by the
`OpenSDQueryTests` integration tests (one per Query, pinning each
deviation server-side) plus the projection-helper unit tests
(`tests/test_open_sd_projection.py`). A change to the inclusion policy
that lands in only one place fails CI loudly.
