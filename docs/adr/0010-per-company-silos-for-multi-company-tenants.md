# Per-company silos for multi-company BC tenants

A BC tenant typically contains 1–N companies (legal entities, divisions,
country units). Every AL table is per-company by default — `Item`,
`Item Ledger Entry`, `Stockkeeping Unit`, planning parameters, posting
setup all silo per-company. The planning recommendation engine adopts this
shape: one Model Run per company per scheduled invocation. Cross-company
aggregation does not happen in MVP. `Item 1234` in Company A and
`Item 1234` in Company B are treated as unrelated time series for
forecasting purposes.

## What "per-company silo" means concretely

- `Model Run Id` is scoped within `Company Name`. Two companies running
  the same week each get their own Model Run record (ADR 0011 details the
  Run schema).
- All recommendation, audit, simulation-result, and model-run-log tables
  are standard per-company AL tables. No `DataPerCompany = false`.
- The Python service is invoked per-company per scheduled run.
  Orchestration: one Job Queue Entry per company per cadence, each
  calling the extract → service → write-back loop for that company. The
  Python math package itself is company-agnostic — it operates on a
  single extract per invocation and never sees the company boundary.
- The setup table holding `α` targets, ABC cuts, thresholds, and horizon
  parameters is per-company by default. Customers wanting consistent
  settings across companies copy the setup via Configuration Package —
  standard BC pattern, no special tooling.
- The `Strategic` override flag on Item / SKU is per-company (because
  Item and SKU are per-company). No cross-company sync.

## Why not cross-company aggregation

Three real alternatives were considered. Each lost on a specific concern:

**Cross-company forecasting (opt-in via item cross-reference).**
For items flagged as "same physical SKU" across companies, union demand
history across companies before fitting the forecaster. Recommendations
still apply per-company. Improves accuracy for items with thin per-company
history.

*Why deferred*: requires a maintained cross-reference table that most BC
tenants don't have. Building one is a substantial workstream in its own
right. Per-customer judgement on "is Item 1234 in Company A really the
same SKU as Item 1234 in Company B?" is needed — sometimes the answer is
yes (legal-entity wrappers around the same operation), sometimes no
(country-specific market entities with different demand patterns).
Deferring keeps the MVP scope contained without painting into a corner:
the Python math package operates on extracted data, so the extract layer
can union companies later without touching the math.

**Cross-company unified tenant.**
One Model Run produces recommendations across all companies. Vendors,
demand, supplier reliability tracked at corporate level.

*Why rejected for MVP*: BC-anti-idiomatic. Requires customers to confirm
items are truly comparable across companies — an organisation-level
business question. Most theoretically powerful, most risky.

**Single-company-only enforcement.**
Engine refuses to run on multi-company tenants.

*Why rejected*: cleanest scope at the cost of excluding a large class of
real BC customers from the sandbox. Not justifiable.

## Pitfalls planners and consultants will hit

- **Setup divergence between companies.** Once setup is per-company,
  customers can (and will) end up with different `α` targets in different
  companies of the same tenant. Eventually a planner asks *"why is the
  same SKU recommending different things in two of our companies?"* The
  answer ("setup differs") must be visible in the review page, not buried
  in a separate setup browse. A FactBox on the Recommendation Card
  surfaces the active setup values for the current company.
- **Cross-company review inbox.** A planner with access to multiple
  companies probably wants a single inbox of "recommendations needing my
  review across companies." BC's standard pattern is a per-company page;
  a cross-company filtered view is a separate Page object with explicit
  `Company Name` field. Deferred to v2.
- **Posting setup per-company is non-negotiable.** Apply must read
  `Inventory Posting Setup`, `Item Vendor`, `SKU Vendor` from the same
  company as the recommendation target. The math package never touches
  these — they're read by the AL apply codeunit. Crossing this line is
  a category of bug that breaks the BC posting pipeline.
- **Job Queue per-company.** Each company needs its own scheduled run
  trigger (or a single cross-company orchestration codeunit that loops
  through companies, which is its own pattern requiring `CompanyName`
  awareness throughout).

## Consequences

- The MVP architecture is BC-native: every table is per-company, every
  Run is per-company, every recommendation is per-company. No special
  infrastructure built around cross-company semantics.
- Cross-company aggregation (Model B) joins as a v2 opt-in feature
  toggled per-tenant in setup; the math package needs no changes, only
  the extract layer.
- Customers with legitimate cross-company SKU reuse and thin per-company
  history pay a forecasting-quality cost until v2 ships the cross-company
  opt-in. Documented honestly in the customer materials when they exist.
