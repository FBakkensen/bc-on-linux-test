# Model versioning and audit lineage from MVP

Every recommendation traces back through `Model Run Id → Math Package
Version + Setup Snapshot + Extract Window`, and every applied change in
the audit log carries the same lineage forward. The chain is end-to-end:

```
Planning Param Change Log entry
  → Planning Recommendation Hdr.
    → Planning Model Run Log entry
      → Math Package Version + Setup Snapshot + Extract Window
```

Versioning is not deferred. Sandbox-era recommendations get the same
lineage fields as v1 recommendations because retrofitting lineage onto
prior data is impossible — you cannot reconstruct a missing version field
after the fact.

## Three layers of versioning, three rates of change

1. **Math Package Version** — semver of `bc_planning_optimizer`. Changes
   on every release. Captures *the algorithm*. Discipline:
   - **Major** bump on math-correctness changes (forecaster swap,
     bootstrap definition change, simulator policy-replay rule change).
   - **Minor** bump on additive features (new reason code, new
     confidence factor).
   - **Patch** bump on bug fixes, performance, docs.
2. **Setup Snapshot** — values of the per-company setup table at run
   time (`α` targets per ABC class, ABC cuts, thresholds, cycle
   multiplier, ceiling, hysteresis values, the works). Changes when
   admins touch setup — low frequency, high reconstruction cost when
   missing.
3. **Extract Metadata** — BC company, history window start/end, last
   ILE row ID processed, run duration, total SKUs / failures / skips.
   Captures *the data window*.

## Schema, MVP-sized

`Planning Model Run Log` table — one row per scheduled batch or
on-demand single-SKU run:

- `Model Run Id` (GUID, primary key)
- `Company Name`
- `Run Timestamp`
- `Math Package Version` (text)
- `Setup Snapshot` (BLOB, JSON-encoded copy of the active setup record
  at run time)
- `Extract Window Start`, `Extract Window End`
- `Status` (Running / Completed / Failed)
- `Total SKUs Processed`, `Total Skipped`, `Total Failed`

A child `Planning Model Run SKU Status` table records *only* failures
and skips with error detail. Successes are implied by the existence of
a corresponding recommendation row — no need to write a row per success.

`Planning Recommendation Hdr.`:

- `Model Run Id` (FK to the Run that emitted this row)
- `Math Package Version` — denormalised from the Run record purely for
  list-page filtering speed. Single source of truth remains the Run.
- All recommendation content fields (current/proposed planning params,
  embedded MC + replay metrics, primary reason code, confidence
  fields).

`Planning Param Change Log` — append-only audit, one row per applied
field change:

- `Model Run Id` of the recommendation that was applied
- `Applied Math Version` (denormalised)
- `Applied At`, `Applied By User`
- `Field`, `Old Value`, `New Value`
- `Recommendation Value` — the original recommendation, *before* any
  inline override
- `Was Overridden` (bool, true when Applied ≠ Recommendation)

Override visibility falls out naturally: a query against the Change Log
filtering `Was Overridden = true` is the most useful diagnostic the
system produces — it tells the engine where it is systematically wrong.

## Stale-version UI

When a Pending recommendation row's `Math Package Version` differs from
the currently-installed engine version, the row carries a quiet badge in
the planner UI: *Math v1.2.1 → current v1.4.0*. No apply blocking — just
information. The planner can choose to re-run before applying (single-SKU
on-demand run is cheap), or proceed knowing the recommendation is from an
older engine.

Approved / Rejected / Applied rows do not show stale badges — they're
historical states; the math version at apply time is the answer of
record.

## Why JSON blob on the Run, not a separate snapshot table

Setup values are read-only after the run completes. Nobody queries
individual setup fields across runs (the use case is *"what setup
produced this specific recommendation"*, answered by reading the blob on
that recommendation's Run). Storing as JSON keeps the schema simple, and
storage cost is trivial: ~1 KB per run × 52 runs/year × N companies ×
N tenants = small even at scale.

The JSON blob is treated as a forward-compatible bag — readers tolerate
missing keys with documented defaults per math version. When the setup
table grows fields in v1.4 that didn't exist in v1.2, reading a v1.2
snapshot returns missing keys; the reader supplies the documented v1.2
defaults.

## Reproducibility honest scope

Even with Math Version + Setup Snapshot + Extract Window pinned,
regenerating the *exact* recommendation bit-for-bit also requires the
ILE rows as they were at run time. If BC data has been edited between
the original run and a replay attempt, replay won't reproduce. The
lineage shows *what was used*, not *what's still true*. This is
documented behaviour — the audit answer is *"on day D, the engine saw
data X and produced recommendation Y"*, not *"the engine would still
produce Y today"*.

## Consequences

- Schema discipline is fixed from MVP. Adding versioning later requires
  invalidating all prior recommendations (no version to fall back on),
  which the sandbox phase can absorb but the productionised phase
  cannot. Capture it now.
- The Math Package follows strict semver; planners learn to trust
  major-version-bump warnings.
- Override-rate analytics become available cheaply (a single Change
  Log query). The engine's blind spots surface without additional
  instrumentation.
- GDPR / data-retention: the Change Log references user IDs and is
  system-of-record for compliance. The Setup Snapshot blob does not
  contain personal data, only setup numbers, so retention rules apply
  only to the Change Log.
- The Run table grows roughly linearly with N companies × cadence.
  Pruning policy (e.g. retain detailed Run records for 24 months,
  archive older to summary form) is a v2 concern.
