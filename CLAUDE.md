# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A local AL development workspace that runs Microsoft Dynamics 365 Business Central on Linux for compile + test execution. The runtime itself lives in [`bc-linux/`](bc-linux/), a checkout of upstream [`StefanMaron/MsDyn365Bc.On.Linux`](https://github.com/StefanMaron/MsDyn365Bc.On.Linux) — do not edit it as a normal source dependency; it has its own `CLAUDE.md` describing how the BC service tier is patched at runtime via `DOTNET_STARTUP_HOOKS`. The two AL projects ([`app/`](app/) and [`test/`](test/)) are minimal smoke artifacts whose purpose is to prove the pipeline works end-to-end.

## Common commands

All paths below are relative to the workspace root.

```bash
# 1. Start the BC stack (run from bc-linux/, ~5–10 min on first boot)
cd bc-linux && docker compose up -d --wait

# 2. Pull Microsoft symbol packages into both AL projects' .alpackages/
./scripts/download-symbols.sh

# 3. Compile + publish prod app + publish & run tests, JUnit to .build/test-results.xml
./scripts/smoke.sh

# Verify BC is reachable
curl -sf -u BCRUNNER:Admin123! http://localhost:7048/BC/ODataV4/Company

# Run a narrower test slice (filters by codeunit ID range)
BC_TEST_CODEUNIT_RANGE=50100..50100 ./scripts/smoke.sh

# Run tests directly without recompiling (calls upstream runner)
./bc-linux/scripts/run-tests.sh \
    --app .build/BcLinuxSmokeTests.app \
    --codeunit-range 50100..50149 \
    --base-url http://localhost:7048/BC \
    --dev-url http://localhost:7049/BC/dev \
    --auth BCRUNNER:Admin123! \
    --junit-output .build/test-results.xml
```

There is no separate lint, type-check, or unit-test step beyond `al compile` (invoked by `smoke.sh`) and the AL tests themselves.

## Architecture & flow

The smoke pipeline is a fixed sequence in [`scripts/smoke.sh`](scripts/smoke.sh) and depends on conventions you must preserve when changing things:

- **Compile path**: `al compile` reads each project's `.alpackages/` for symbols. The production `.app` is copied into `test/.alpackages/` after build so the test app's dependency on `Bc Linux Smoke` resolves at compile time. If you add a new AL project, replicate this pattern rather than sharing a cache.
- **Publish path**: production app is published via `bc-linux/scripts/publish-app.sh` (sourced, exposes `bc_publish_app`). Tests are published *and* executed by `bc-linux/scripts/run-tests.sh`, which is a hybrid OData (suite + results) + WebSocket (test session) flow — TestPage support requires a real client session, which OData alone cannot provide.
- **ID ranges are load-bearing**: production codeunits live in `50000..50049` (per `app/app.json`), tests in `50100..50149` (per `test/app.json` and the default `BC_TEST_CODEUNIT_RANGE`). Adding tests outside that range silently excludes them from `smoke.sh`.
- **`BC_KEEP_APP_IDS` workaround**: the upstream entrypoint clears the Microsoft test framework apps on first boot and only reinstalls them when `BC_KEEP_APP_IDS` is non-empty. Locally this workspace pins the value in `bc-linux/.env`. In CI the keep-set is computed at setup time by `bc-linux/scripts/resolve-keep-app-ids.py`, written to `.bc-cache/env`, and appended into `bc-linux/.env` before BC boots. Either way, do not blank it — first boot will publish a test app against missing framework dependencies and fail.
- **Build outputs** land in `.build/` (`BcLinuxSmoke.app`, `BcLinuxSmokeTests.app`, `test-results.xml`). This dir plus both `.alpackages/` are gitignored.

## Environment overrides

Both scripts honor: `BC_BASE_URL`, `BC_DEV_URL`, `BC_AUTH`. `smoke.sh` additionally honors `BC_TEST_CODEUNIT_RANGE`. Defaults match the upstream BC stack (ports 7048/7049, `BCRUNNER:Admin123!`).

## VS Code

`/.vscode/launch.json` (workspace-level, not in `.vscode/` subdirs) contains a `BC Linux` launch profile pointed at the local dev endpoint. Each AL project also has its own `.vscode/launch.json`. For F5 publish, use `BCRUNNER` / `Admin123!`.
