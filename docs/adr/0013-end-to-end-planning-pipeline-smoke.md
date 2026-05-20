# End-to-end planning-pipeline smoke + seeded BC companies

The planning-optimizer math is exercised today only by unit tests against
small synthetic CSV fixtures (5 rows in `tests/fixtures/synthetic_ile_summary.csv`).
The AL integration tests exercise BC seams but synthesize their own
per-test data and never touch the Python pipeline. **Nothing tests the
full chain `BC → extracts/bc_api.py → planning-optimizer → recommendations`
end-to-end.** A regression that breaks the seam contract or the bc_api
mapping or the optimizer's handling of real-shaped data lands silently.

This ADR introduces an end-to-end pipeline smoke that runs against two
purpose-seeded BC companies with realistic multi-year history covering
the data shapes the 17 open planning-optimizer issues (#19–#34) consume.

## What

- Two BC companies (`PLANOPT-CO-A`, `PLANOPT-CO-B`) seeded with multi-year
  history by an AL extension (`seed/`, ID range `50200..50299`).
- A pipeline smoke script (`scripts/test-pipeline.sh`) that runs the full
  chain and asserts each phase produced non-empty output.
- A Python integration test (`planning-optimizer/tests/integration_test_seeded_data.py`)
  that asserts hard-shape expectations against the real BC extract.

The seeder is the **source of truth for the dataset**. There is no
`.bak`, no Docker volume, no derived image. Re-seeding is cheap (~6–10
minutes for both companies via Item Journal posting at ~500–1000
lines/sec). Container restart wipes everything and re-seeding restores
it; no persistence layer required.

## Why two companies

Issue #34's multi-company smoke explicitly requires *"two companies with
overlapping Item Nos but different demand patterns"* (per [ADR 0010](0010-per-company-silos-for-multi-company-tenants.md)).
Sizing for one company and revisiting later costs a rework of every
cohort. Two from day one.

**80% item-master overlap, 20% disjoint.** The overlap proves
recommendations are siloed per company even when Item Nos collide;
the disjoint 20% proves a company-only item doesn't bleed into the
other.

## Why 36 months of history

[ADR 0012](0012-per-sku-forecast-and-simulation-horizon.md) says a SKU's
horizon `H` can run up to 365 days (cap) and `≥ 2 × H` of clean ILE is
required to fit the forecaster + bootstrap. Issue #27's walk-forward
replay sets `T₀ = 12 months ago` and replays forward to today —
requiring history that covers at least `12 months + max(H)` ≈ 24 months
minimum, plus headroom for AutoETS to fit annual seasonality (which
needs `≥ 2 full seasonal cycles`). 24 months is the threshold; 36 gives
AutoETS comfortable headroom.

## Why journal-based posting (not document posting)

Posting full Sales / Purchase / Production orders through their normal
routines is slow (every doc walks GL / VAT / dimension validation).
Item Journal posting via `Codeunit "Item Jnl.-Post Line"` produces
canonical ILE entries — the same entries document posting produces
internally — at ~10–100× the throughput. For 36 months × ~100 items per
company × ~25k ILE rows, journal posting completes in minutes; document
posting would take hours.

**Open documents** (Sales / Purchase / Prod / Assembly / Transfer /
Service / Job headers + lines) are still needed for the Open S&D Query
to have anything to read — those are created via direct `Insert` in
their open state, not posted. Open S&D consumes them as-is.

## Dataset shape

| Axis | Per company | Driver |
|------|-------------|--------|
| Items | ~100 | Matrix of demand pattern × ABC × policy × constraints |
| Locations | 3 (`BLUE`, `RED`, `GREEN`) | Multi-location grain promotion (#25) |
| Variants | 0–3 per item | Variant-divergence cohort (#29) |
| Time depth | 36 months relative to `SEED_TODAY` | #27 walk-forward + AutoETS seasonal |
| Regime change | ~15–20 SKUs at month 12 | #28 comparative reason codes |
| Stockout-history cohort | ~5–10 SKUs with ≥5d zero inventory | #26 stockout cap, #27 lost-sales caveat |
| Make-to-Order subset | ~10 items | #24 third mismatch rule |
| Open docs at SEED_TODAY | ~50 SO, ~20 PO, ~5 prod, ~5 assembly, ~3 transfer, ~5 service, ~3 job | Open S&D coverage |
| Math Package Version drift | ~5 Model Run Log rows with old version | #33 stale badge — guarded until #30 + #33 land |
| Test users | `PLANNER_REVIEWER`, `PLANNER_APPROVER` | #32 permission tests — permission sets assigned when #32 lands |

Estimated volume: ~25k ILE rows per company, ~50k total. Posting time
~3–5 minutes per company at journal rates.

## Date strategy — relative, not absolute

`PO Seed Companies` captures `SEED_TODAY := Today()` once at the start
of a run. All date arithmetic in cohort sub-codeunits uses
`CalcDate('<-NM>', SEED_TODAY)` for history start, `CalcDate('<+ND>',
SEED_TODAY)` for future-dated open SOs, etc. Never reference `Today()`
outside the one capture point.

**Why not absolute?** With absolute dates, re-seeding in 12 months
produces stale data — open SOs look past-due, BC's WORKDATE-driven
default-fills (Expected Receipt Date on a PO) silently drift away from
what the planning-optimizer expects. The user-surfaced symptom would be
"the optimizer matches whatever as_of_date it was told but bc_api
returns dates that don't line up with that." Relative dates side-step
the whole class of issue.

**Determinism is preserved** by:

- `SEED_TODAY` captured once per run (no midnight-boundary drift)
- Single hardcoded `RNG_SEED := 42` constant in `PO Seed Companies`
- Cohort sub-codeunits use only the captured `SEED_TODAY` and
  `RNG_SEED` for all randomness

Shape assertions in `integration_test_seeded_data.py` are stated
relative to `SEED_TODAY` (e.g., "≥247 sales ILE in the 12 months ending
at SEED_TODAY") rather than to absolute calendar dates.

## Iteration loop + script flags

The seeder will go through many revisions — cohort sizes, demand pattern
tunings, regime-change shapes. The agent iteration is:

```
edit seed/src/*.al
  → ./scripts/seed-company.sh --reset
       1. compile seed/
       2. invoke PO Seed Companies.Teardown (Company.Delete(true) × 2)
       3. unpublish prior seed extension
       4. publish new seed extension
       5. invoke PO Seed Companies.SeedAll(Today())
       6. run bc_api.py + emit shape report
  → inspect .build/extracts/{CO-A,CO-B}/*.csv
  → if wrong: edit, loop
```

Full `--reset` cycle ≈ 2–3 minutes (publish dance dominates). Tolerable.

| Flag | Behavior |
|---|---|
| `(none)` | Idempotent: source hash matches + `SEED_TODAY` in marker < 14d old + companies present → exit 0; else seed |
| `--reset` | Teardown via codeunit + republish + re-seed unconditionally |
| `--nuke` | `docker compose -f bc-linux/docker-compose.yml restart bc` + `--reset` (escape hatch when `--reset` wedges) |
| `--verify` | Skip seeding; run `bc_api.py` + emit shape report (item counts per ABC, ILE row counts, time span, histograms, open-doc counts) |

## 14-day staleness check

The idempotency check has two gates: source hash match AND `SEED_TODAY`
in the marker is ≤ 14 days old. Even with no code changes, after 14 days
the open SO shipment dates have drifted into the past and the dataset
no longer represents "today + future" the way the optimizer expects.
Auto-detected to avoid silent drift; 14 days picks a balance between
churn and freshness.

## Pipeline smoke (`scripts/test-pipeline.sh`)

Orchestrates:

1. `seed-company.sh` (idempotent — usually no-op)
2. `bc_api.py` extracts for both companies → `.build/extracts/{CO-A,CO-B}/`
3. `planning-optimizer` runs against each extract → `.build/recommendations/{CO-A,CO-B}.json`
4. POST recommendations via `apiPlanningRecommendation` (once issue #30 lands) — until then writes JSON to `.build/recommendations/`
5. Assert each phase produced non-empty output

Runs as a parallel CI job alongside `test-integration.sh`. The two are
intentionally orthogonal — AL integration tests synthesize their own
per-test data, the pipeline smoke runs against the seeded companies.

## bc-linux container overrides — durable across re-clones

Upstream `StefanMaron/MsDyn365Bc.On.Linux` does not ship or document a
`docker-compose.override.yml` pattern, an FTS support story, or guidance
on bumping `MSSQL_MEMORY_LIMIT_MB`. The only documented downstream
extension surface is env-var interpolation in `docker-compose.yml`
(verified by exhaustive search of the upstream repo + issues +
README/CLAUDE.md/PERFORMANCE-IDEAS as of 2026-05). The reference
downstream consumer `StefanMaron/MsDyn365Bc.Copilot.OnLinux` never
touches the compose file — it consumes only the published bc-runner
image + the reusable workflow.

Our seed pipeline needs image-layer changes (FTS) plus a compose-layer
env override (memory). We resolve this with a self-bootstrap pattern:

- **Source of truth lives in our repo** at `scripts/bc-linux-overrides/`:
  - `sql-fts.Dockerfile` (derived SQL image with mssql-server-fts baked in)
  - `docker-compose.override.yml` (uses the derived image + bumps `MSSQL_MEMORY_LIMIT_MB`)
- **`scripts/seed-company.sh` syncs them into `bc-linux/`** on every
  invocation. `bc-linux/` is gitignored (treated as a vendored upstream
  checkout per its own `CLAUDE.md`); on fresh clones the files are
  absent there until the seed script writes them.
- **`docker compose up` auto-merges `docker-compose.override.yml`** that
  sits beside the main `docker-compose.yml` in `bc-linux/`. Compose
  also auto-builds the FTS image via the `build:` directive in the
  override (no separate `docker compose build` step needed).
- **`seed-company.sh` also handles the "container not running yet"
  case** — `ensure_bc_running` runs `docker compose up -d --wait` from
  `bc-linux/` if BC's ODataV4 endpoint isn't reachable. So a fresh
  `git clone` of this repo plus a fresh `bc-linux/` upstream clone
  reaches a fully-seeded BC with a single `./scripts/seed-company.sh`.

When upstream eventually adopts FTS + tenantid + memory defaults (no
issue filed there yet), `scripts/bc-linux-overrides/` and the
`sync_bc_overrides` step in `seed-company.sh` can be deleted. Until
then, the source-of-truth-in-our-repo + sync-on-invocation pattern
guarantees the override survives any `bc-linux/` re-clone.

## What this rules out

- **A `.bak` snapshot.** Tried; rejected. The seeder is the source of
  truth; a backup file is an opaque second source that drifts from
  source code and complicates the agent iteration loop.
- **A persistent Docker volume for SQL.** Tried; rejected. Forces every
  agent / CI run to manage the volume state; adds an external
  persistence layer the user explicitly didn't want.
- **A pre-baked Docker image with seeded SQL.** Tried; rejected.
  Couples seed lifecycle to derived-image rebuilds; opaque for agent
  inspection.
- **A contract-only test on the AL Query / bc_api.py seam.** Tried
  during grilling; rejected. The contract is verified as a side effect
  of the full pipeline run, and a contract-only test misses the
  end-to-end behaviors (lookback windows, ABC distribution, regime
  detection) that the dataset depth makes visible.
- **Mutating Cronus directly.** Couples test data to the demo data
  shipping with BC; loses isolation; conflicts with AL integration
  tests' synthesized-per-test pattern.
- **An absolute `SEED_TODAY` baked into source.** Drifts out of date;
  bc_api dates and optimizer "today" disagree silently.

## Consequences

- Two more BC companies live in the container, named `PLANOPT-CO-A` and
  `PLANOPT-CO-B`. Standard BC tooling sees them like any other company.
- One more AL project (`seed/`) for the workspace, compile.sh, and
  resolve-keep-app-ids.py to know about.
- Cohort-per-codeunit means seed/ grows file-count over time. Each PR
  touching the seeder typically adds or extends one sub-codeunit; the
  source-hash drift check then forces a re-seed.
- The planning-optimizer's `run()` entrypoint may grow an `as_of_date`
  parameter at some point if drift bites; for now it keeps its current
  wall-clock default, and `test-pipeline.sh` runs immediately after
  seeding so drift is negligible.
- Issue PRs that need new data shape extend the seeder as part of their
  delivery. The seed is a living artifact that grows with the feature
  work. CI's source-hash check forces re-seeding automatically when
  the seeder changes.

## Cross-references

- [ADR 0009](0009-python-package-with-api-and-file-seam.md) — establishes the BC seam the smoke runs against
- [ADR 0010](0010-per-company-silos-for-multi-company-tenants.md) — multi-company silo requirement that forces two companies
- [ADR 0011](0011-model-versioning-and-audit-lineage.md) — model run log + math version drift the seed must populate
- [ADR 0012](0012-per-sku-forecast-and-simulation-horizon.md) — horizon math that drives the 36-month time depth
- Open issues #19–#34 — consumer features whose data needs this seed satisfies
