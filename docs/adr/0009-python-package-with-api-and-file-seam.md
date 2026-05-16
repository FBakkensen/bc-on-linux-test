# Compute lives in a Python package; BC seam is API + file exchange, never SQL

The numeric machinery (demand classifier, forecaster, lead-time extractor,
simulator, recommender, confidence calc) lives in a pure Python package.
The seam to Business Central is built on AL API pages, AL API queries, and
file-based import/export. **Direct SQL access to the BC database is not
used, even in sandbox.**

## Why Python, not AL

AL has no statistical libraries, no random number generator suitable for
Monte Carlo simulation, no time-series fitters, no exponential-smoothing or
intermittent-demand model implementations. Bootstrap LTD sampling (ADR
0006), the SBA / AutoETS forecaster dispatch, and the Fidelity-B simulator
(ADR 0007) all need the Python ecosystem (numpy, pandas, scipy,
statsmodels, statsforecast, or equivalents). Implementing the stack in AL
would be a multi-person-year project with no payoff vs the Python option,
and would leave the math untestable outside a running BC container.

## Why API + files, not SQL

BC SaaS does not permit direct SQL access to the tenant database. A
sandbox shortcut that uses Docker-container SQL would not generalise to
the production target and would bake a deployment-blocking dependency into
the math package. The seam shape must match what SaaS allows, even in
sandbox — the SQL escape hatch closes the *one* easy iteration speedup
the sandbox could legitimately offer, by design.

The data-shape split:

- **Small reads** — `Item`, `Stockkeeping Unit`, `Vendor`, `Location`,
  current planning parameters: AL API pages or API queries, called over
  OData with auth.
- **Bulk historical reads** — `Item Ledger Entry`, `Posted Purchase
  Receipt`, open supply documents: AL Query objects pre-aggregate to
  `(Item, Variant, Location, period)` granularity *server-side*, then
  export to file. In sandbox the file lands on the local filesystem; in
  production it lands in Azure Blob Storage (or equivalent). Python reads
  the file. Pushing aggregation server-side keeps the payload bounded
  even for tenants with multi-year ILE history.
- **Writes** — recommendation header / lines, simulation results, model
  run log: API page POST from Python. Planner sees them live in BC.

## Package layout

```
planning-optimizer/
├── pyproject.toml
├── src/bc_planning_optimizer/
│   ├── classifier.py          # ABC, Syntetos-Boylan
│   ├── forecaster.py          # SBA, AutoETS dispatch
│   ├── lead_time.py           # Order-to-Receipt extraction
│   ├── simulator.py           # Fidelity-B Monte Carlo (ADR 0007)
│   ├── recommender.py         # ROP, ROQ, policy logic
│   └── confidence.py          # min-of-factors aggregation
├── extracts/                  # swappable seam layer
│   ├── bc_api.py              # API page/query reads + writes
│   └── bc_files.py            # file-based bulk reads (local FS / Blob)
├── notebooks/                 # prototyping
└── tests/
```

The math package has no BC dependency. The `extracts/` layer is the only
code that talks to BC; swapping `bc_files.py`'s file backend from local
filesystem to Azure Blob is a one-call change. The math package's tests
run in milliseconds against fixture data with no BC container in the
loop. Notebook and service share the same math package, so prototype
results do not drift from productionised results.

## AL side at sandbox phase

Minimal. A recommendation table (header + lines), a planner review page,
an apply-approved-changes codeunit, an audit log table. Per the
established repo convention (see `app/src/logic` + `app/src/seams` split,
and the `IEventSource` / `INotificationDispatcher` / `IStockoutChecker`
interface pattern), the AL apply codeunit interfaces against the
SKU / Item write surface so that unit tests in `test/` can stub the BC
side without a live container — consistent with the project-wide rule
*test our logic, not BC, with interfaces at every BC seam*.

API page slate for sandbox (informative, not load-bearing):

- `apiItems`, `apiStockkeepingUnits`, `apiVendors`, `apiLocations`,
  `apiCurrentPlanningParams` — small dimension reads.
- `apiItemLedgerSummary`, `apiPurchaseReceiptSummary`,
  `apiOpenSupplyDemand` — bulk-aggregated reads (driven by AL Query
  objects, exported to file rather than streamed per row).
- `apiPlanningRecommendationHeader`, `apiPlanningRecommendationLine`,
  `apiPlanningSimulationResult`, `apiPlanningModelRunLog` — write-back
  surfaces.

## What this rules out

- Direct database queries against the running BC container, even for
  prototyping convenience. Doing so would create a one-way ratchet:
  shipping the same code against SaaS later would require a rewrite of
  the extract layer that is invisible to the math package's tests, with
  no test surface to catch the migration.
- Embedding the math in an AL codeunit, even a minimal one. The math
  package's pure-Python testability is foundational to the development
  loop and must not erode.
- Coupling the math to a specific external compute platform. The package
  runs equally well from a Jupyter notebook, a FastAPI service, an Azure
  Function, an Azure Container App, a Fabric notebook, or a Databricks
  job. The hosting decision is a v2 deployment concern, not a math
  concern.

## Consequences

- The math package is portable. Future re-hosting decisions only touch
  the entry point; the math itself does not move.
- Any need for data not exposed via API page or API query becomes a
  request to add an AL Query / API surface, not a SQL workaround.
- Prototyping iteration is fast: the file-based extract layer in sandbox
  is a CSV/Parquet dump from an AL Query, easy to regenerate and easy to
  diff between runs.
- The recommendation upsert lifecycle (weekly batch + on-demand per-SKU
  + Pending replacement) lives on the AL side, driven by API POSTs from
  Python. The math package is stateless across runs except for the
  `ModelRunId` recorded on each emitted recommendation.
