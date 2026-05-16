# Recommendations live at the lowest viable grain, with promotion

Each recommendation row is computed at the lowest grain that has enough
historical data to support a stable bootstrap LTD estimate. The *intended
grain* is `(Item, Variant, Location)` — matching the Stockkeeping Unit.
When that grain has too few observations (default thresholds: < 30 demand
events or < 10 lead-time samples), the engine *promotes* the grain coarser:
`(Item, *, Location)`, then `(Item, *, *)`. The grain actually used is
recorded on the row alongside the intended grain; the planner sees when
SKU specificity is real evidence vs aggregation necessity.

## Why not strict SKU grain

The spec calls for SKU-level recommendations as the preferred output.
Real BC data fights this in three ways:

- Many items run most of their demand at `(Item, blank Variant, blank
  Location)`. BC's Variant feature is opt-in; most tenants under-use it.
  Legacy items often have blank Location Codes by setup choice.
- SKU records are created lazily. The default BC behaviour is to fall
  back to Item Card when no SKU exists. A real `(Item-1234, '', 'BLUE')`
  may have a year of demand but no SKU record.
- Slow-movers do not generate enough events per SKU to support stable
  bootstrap quantiles. A CZ-class item with 8 sales in 24 months at one
  location cannot be the unit of LTD estimation.

Strict SKU-grain recommendations would silently drop most slow-movers from
the output — exactly the items where the manual maintenance burden is
highest and where automation has the highest marginal value.

## Why not pure Item-card grain

Item-card-only recommendations contradict the spec's premise: items that
behave differently across Variants or Locations get a single recommendation
that fits no one. The grain hierarchy retains the ability to deliver SKU
specific recommendations *where the data supports them* without imposing
that grain *everywhere*.

## How "create new SKU" emerges naturally

When two location aggregates of the same item — say `(Item, *, PARIS)` and
`(Item, *, LYON)` — both pass the threshold *and* their LTD distributions
disagree materially (default: proposed ROP differs by > 25%), the engine
emits the reason code `Item behaves differently by location` and recommends
creating a new SKU at the location-specific grain. The hierarchy lets the
engine *discover* where SKU granularity is warranted, instead of demanding
it universally.

Symmetric behaviour applies to `(Item, *, Location) → (Item, Variant,
Location)` when variant-specific data passes the threshold and disagrees
materially (reason code `Variant-specific demand pattern detected`).

## Recommendation row schema implications

Two grain fields on every row:

- **Intended Grain** — `(Item, Variant, Location)` for the SKU the row is
  scoped at. Used as the natural key for the upsert recommendation
  lifecycle (one Pending row per Intended Grain per Model Run).
- **Computed Grain** — the coarsest aggregation actually used. May equal
  Intended Grain (no promotion) or a coarser tuple.

Where Computed Grain is coarser than Intended Grain, the planner sees an
explicit note on the review page (*Computed at Item-level — SKU has only
4 demand events*). The Recommendation Confidence cascade also caps at
Medium for promoted rows, so a planner filtering for High-confidence rows
never sees a promoted recommendation pretending to be SKU-specific.

## Apply-side interaction

Applying a recommendation at SKU Intended Grain when no SKU exists auto-
creates the SKU (toggleable per company in setup). Non-planning fields are
copied from the Item Card; planning fields are set from the recommendation.
Where Computed Grain is promoted, the planner sees the promotion note
before clicking Apply — the audit log records the creation of the SKU and
the applied planning parameter values as separate entries.

## Consequences

- Slow-movers receive recommendations at the coarsest grain where their
  aggregated data is sufficient, not silently dropped. Insufficient-data
  cases are flagged explicitly with the `Insufficient data` reason code,
  not synthesised.
- The setup-table thresholds (default: 30 demand events, 10 lead-time
  samples; per-ABC-class override allowed — looser for class A because
  the stakes are higher and aggregated recommendations still beat doing
  nothing) are tunable per company.
- The "create new SKU" recommendation is a structural output of the
  engine, not a separate analytical workflow. It rides the same Apply
  pipeline as any other recommendation; the audit log captures the SKU
  creation with full lineage back to the Model Run that emitted it.
