# `bc-planning-optimizer`

Sandbox planning-parameter optimizer. Recommends updated **Reorder Point**, **Safety Stock**, **Reorder Quantity**, and **Reordering Policy** values for `(Item, Variant, Location)` SKUs based on historical demand and lead-time behaviour.

Pure-Python package. **No BC container required** for tests, notebooks, or local iteration. Talks to Business Central only through the `extracts/` seam layer (API page reads + file-based bulk extracts on the read side, API page POSTs on the write side). **No direct SQL access**, even in sandbox.

## Why this lives outside AL

See [ADR 0009](../docs/adr/0009-python-package-with-api-and-file-seam.md). Short version: the math stack needs `numpy`, `pandas`, `scipy`, `statsmodels`, and `statsforecast` (or equivalents) — none of which AL provides. The BC seam is API + file exchange specifically so the same code that runs in sandbox runs against BC SaaS later.

## Vocabulary

Domain terms used in the public interface (`Recommendation Grain`, `Lead-Time Demand`, `Cycle Service Level`, `Fill Rate`, `Forecast Confidence`, `Recommendation Confidence`) are load-bearing — see the planning glossary in [`CONTEXT.md`](../CONTEXT.md) for the canonical definitions.

## Current state — walking skeleton

This commit is a walking skeleton. `run(extract_path) → recommendations.json` reads a CSV of `(item_no, variant_code, location_code, daily_demand, lead_time_days)` observations and emits recommendations using **deliberately-naive math**:

```
reorder_point = mean(daily_demand) × mean(lead_time_days)
safety_stock  = reorder_point / 2
```

No policy change. No bootstrap LTD. No simulator. No confidence calc. Real math lands in subsequent slices — the stub modules (`classifier.py`, `forecaster.py`, `lead_time.py`, `simulator.py`, `confidence.py`) reserve their seams.

## Install

```bash
pip install -e ./planning-optimizer        # production deps only
pip install -e './planning-optimizer[dev]' # adds pytest
```

## Run the smoke test

```bash
pytest planning-optimizer/tests
```

## Run the walking-skeleton notebook

```bash
jupyter notebook planning-optimizer/notebooks/walking_skeleton.ipynb
```

## Layout

```
planning-optimizer/
├── pyproject.toml
├── src/bc_planning_optimizer/
│   ├── pipeline.py            # run(extract_path) → recommendations.json
│   ├── recommender.py         # ROP / SS / ROQ / policy logic — naive today
│   ├── classifier.py          # ABC, Syntetos-Boylan          (stub)
│   ├── forecaster.py          # SBA, AutoETS dispatch         (stub)
│   ├── lead_time.py           # Order-to-Receipt extraction   (stub)
│   ├── simulator.py           # Fidelity-B Monte Carlo        (stub) — ADR 0007
│   └── confidence.py          # min-of-factors aggregation    (stub)
├── extracts/                  # swappable seam layer — only code that talks to BC
│   ├── bc_files.py            # file-based bulk reads (local FS / Blob)
│   └── bc_api.py              # API page/query reads + writes (stub)
├── notebooks/
│   └── walking_skeleton.ipynb
└── tests/
    ├── fixtures/synthetic_extract.csv
    └── test_walking_skeleton.py
```
