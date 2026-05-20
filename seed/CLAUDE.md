# CLAUDE.md — seed/

AL extension that seeds two BC companies (`PLANOPT-CO-A`, `PLANOPT-CO-B`)
with multi-year history for the planning-optimizer pipeline smoke. Per
[ADR 0013](../docs/adr/0013-end-to-end-planning-pipeline-smoke.md).

This is **test infrastructure**, not production. It runs rarely (when the
seed code changes or when `SEED_TODAY` in the marker goes stale by more
than 14 days), populates two companies through normal BC posting routines
(Item Journal for ILE, direct insert for open documents), and exists only
to give `scripts/test-pipeline.sh` a realistic dataset to run the chain
`BC → extracts/bc_api.py → planning-optimizer → recommendations` against.

## Rules-of-the-land

- **ID range `50200..50299`.** Outside the range = silently excluded.
- **Seed is the source of truth for the dataset.** No `.bak`, no Docker
  volume, no derived image. The seeder runs and the data appears; if
  you want a fresh dataset you re-run the seeder. See ADR 0013.
- **Relative dates anchored to `SEED_TODAY := Today()`** captured once
  per seed run. All date math uses `CalcDate('<-NM>', SEED_TODAY)` etc.;
  never reference `Today()` outside the one capture point in `PO Seed
  Companies`. Determinism comes from this discipline plus the hardcoded
  RNG seed.
- **Two companies, 80% item-master overlap, 20% disjoint.** Overlapping
  Item Nos must produce different demand patterns per company to
  exercise the multi-company smoke from issue #34.
- **Cohort-per-codeunit.** As cohorts land, they each get their own
  sub-codeunit (`PO Seed Items`, `PO Seed Demand History`, `PO Seed
  Open Documents`, `PO Seed Regime Change Cohort`, `PO Seed Stockout
  History Cohort`, `PO Seed Teardown`). Keeps each cohort independently
  testable and the orchestrator small.

## Patterns

- **Idempotency marker.** `PO Seed Companies.SeedAll` writes a marker
  row (`PO Seed Marker` table, future phase) recording `seed_today`,
  `source_hash`, `rng_seed` so `scripts/seed-company.sh` can skip
  re-seeding when nothing has drifted.
- **Posting via journals.** Item Journal (`Codeunit "Item Jnl.-Post
  Line"`) for ILE history — fast (~500–1000 lines/sec), BC-validated,
  produces canonical entries. Production Journal / Assembly equivalent
  for those event sources.
- **Open docs via direct insert.** Sales / Purchase / Prod / Assembly /
  Transfer / Service / Job headers and lines inserted directly in their
  open state — not posted; Open S&D Query consumes them as-is.
- **Phase 1 is shell only.** Procedures currently `Error` with a clear
  message pointing back to ADR 0013. Cohort implementations land in
  later phases.

## Invocation

```bash
./scripts/seed-company.sh           # idempotent: skip if companies present + hash matches + < 14d
./scripts/seed-company.sh --reset   # tear down + republish + re-seed
./scripts/seed-company.sh --nuke    # docker compose restart bc + --reset
./scripts/seed-company.sh --verify  # skip seeding; emit shape report from bc_api.py
```

## Not in scope

- AL integration tests for cohort correctness — those live in
  `integration-test/` if/when they need to exercise BC seams. The seeder
  itself is verified via `scripts/seed-company.sh --verify` + the Python
  integration test `planning-optimizer/tests/integration_test_seeded_data.py`.
- Permission sets `Planning Optimizer Reviewer` / `Planning Optimizer
  Approver` — those are defined by issue #32. The seeder creates the
  users and assigns the permission sets only when they exist.
