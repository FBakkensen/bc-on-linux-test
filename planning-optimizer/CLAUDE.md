# CLAUDE.md — planning-optimizer/

Sandbox planning-parameter optimizer. **Python, not AL.** Pure math package +
swappable BC seam layer per [ADR 0009](../docs/adr/0009-python-package-with-api-and-file-seam.md).
Domain vocabulary in [`CONTEXT.md`](../CONTEXT.md) (planning glossary section).

## Rules-of-the-land

- **No BC container.** Tests, notebooks, and local iteration run pure-Python
  against fixture data. If a test needs a live BC tier, it belongs in
  `integration-test/`, not here.
- **No direct SQL against BC, even in sandbox.** The seam is API page reads,
  `QueryType = API` Query reads over paginated OData (then persisted as CSV
  by `extracts/bc_api.py`), and API page POSTs. SQL would not generalise to
  SaaS and would bake a deployment-blocking dependency into the math package.
- **`extracts/` is the only code that talks to BC.** Math modules
  (`recommender`, `classifier`, `forecaster`, `lead_time`, `simulator`,
  `confidence`) must not import from `extracts/`. Dependency direction is
  one-way: `extracts/` adapts BC to the core schema; the core does not reach
  into the seam.
- **Stub modules are intentional.** `classifier.py`, `forecaster.py`,
  `lead_time.py`, `simulator.py`, and `confidence.py` are docstring-only
  placeholders reserving named seams for later slices. Don't delete them
  and don't flag them as dead code. `extracts/bc_api.py` now hosts the
  OData fetch + paginate + transform helpers (see slice #12); it grows
  one fetcher per AL API Query.
- **TDD on the math seam.** Tests drive the public `bc_planning_optimizer.run`
  interface only — no poking at internal modules. Survives the bootstrap-LTD /
  SBA / AutoETS / simulator swap without rewriting.
- **Walking-skeleton math is deliberately naive.** `ROP = mean(daily_demand)
  × mean(lead_time_days)`, `Safety Stock = ROP / 2`. Real math (bootstrap-LTD
  α-quantile, simulator-verified policy) lands in subsequent slices per
  [ADR 0006](../docs/adr/0006-bootstrap-ltd-shared-monte-carlo-engine.md) and
  [ADR 0007](../docs/adr/0007-simulator-fidelity-b-simplified-policy-replay.md).

## Common commands

```bash
# Editable install (from repo root)
pip install -e ./planning-optimizer

# With dev extras
pip install -e './planning-optimizer[dev]'

# Run the smoke test
pytest planning-optimizer/tests

# Run the walking-skeleton notebook end-to-end
jupyter nbconvert --to notebook --execute --inplace \
    planning-optimizer/notebooks/walking_skeleton.ipynb
```

## Patterns

- **Public entry point**: `bc_planning_optimizer.run(extract_path: Path) -> Path`.
  Reads a CSV next to `extract_path`, writes `recommendations.json` in the
  same directory, returns the output path.
- **Schema constants** live with the consumer that owns the concept
  (e.g. `SKU_COLUMNS` in `recommender.py`). Promote to a shared module only
  when a third caller appears.
- **CSV dtype**: spell out `dtype=` for every column in `read_extract` so
  pandas skips inference. `keep_default_na=False` is required — the empty
  `variant_code` cell is a real value (no-variant SKU), not `NaN`.
- **Recommendation JSON shape**: `{"recommendations": [{"item_no", "variant_code",
  "location_code", "reorder_point", "safety_stock"}, ...]}`. Real slices will
  add `model_run_id`, `recommendation_grain` (intended vs computed per
  [ADR 0008](../docs/adr/0008-hierarchical-grain-with-promotion.md)), confidence
  buckets, and policy fields.
