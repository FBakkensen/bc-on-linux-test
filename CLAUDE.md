# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A local AL development workspace that runs Microsoft Dynamics 365 Business Central on Linux for compile + test execution. The runtime itself lives in [`bc-linux/`](bc-linux/), a checkout of upstream [`StefanMaron/MsDyn365Bc.On.Linux`](https://github.com/StefanMaron/MsDyn365Bc.On.Linux) — do not edit it as a normal source dependency; it has its own `CLAUDE.md` describing how the BC service tier is patched at runtime via `DOTNET_STARTUP_HOOKS`. The three AL projects are [`app/`](app/) (production), [`test/`](test/) (unit tests, stub-based via al-runner — no container), and [`integration-test/`](integration-test/) (integration tests run inside the BC container).

## Per-subfolder context

[`app/`](app/CLAUDE.md), [`test/`](test/CLAUDE.md), and [`integration-test/`](integration-test/CLAUDE.md) each carry their own `CLAUDE.md` with hyper-local rules (folder-specific ID ranges, stub vs real-BC conventions, runner constraints, naming patterns). They load on-demand when Claude touches files in those folders — this root file stays canonical for repo-wide concerns.

## Common commands

All paths below are relative to the workspace root.

```bash
# 1. Start the BC stack (run from bc-linux/, ~5–10 min on first boot)
cd bc-linux && docker compose up -d --wait

# 2. Pull Microsoft symbol packages into the shared .alpackages/ at the repo root
./scripts/download-symbols.sh

# 3. Compile all 3 projects with full analyzer set (no BC container needed)
./scripts/compile.sh                       # all three projects
./scripts/compile.sh app test              # subset (app auto-included for deps)

# 4. Fast unit-test loop — compiles app + test with analyzers then runs al-runner.
#    JUnit to .build/test-unit.xml. Append --run <Proc>, --coverage, etc.
./scripts/test-unit.sh

# 5. Full BC-tier flow — compile (all 3, full analyzers) + publish + run integration
#    tests in the running container. JUnit to .build/test-integration.xml.
./scripts/test-integration.sh

# Verify BC is reachable
curl -sf -u BCRUNNER:Admin123! http://localhost:7048/BC/ODataV4/Company

# Run a narrower test slice (filters by codeunit ID range)
BC_TEST_CODEUNIT_RANGE=50150..50150 ./scripts/test-integration.sh

# Run integration tests directly without recompiling (calls upstream runner)
./bc-linux/scripts/run-tests.sh \
    --app .build/BcLinuxSmokeIntegrationTests.app \
    --codeunit-range 50150..50160 \
    --base-url http://localhost:7048/BC \
    --dev-url http://localhost:7049/BC/dev \
    --auth BCRUNNER:Admin123! \
    --junit-output .build/test-integration.xml
```

Pick the right tool for the loop you're in:

- **Inner loop** (no BC container needed): `./scripts/compile.sh` for full-analyzer-set lint across all three projects (wraps `al-compile` / al-smart-compile, at `~/.local/bin/al-compile`); `./scripts/test-unit.sh` (BusinessCentral.AL.Runner, pinned in [`dotnet-tools.json`](dotnet-tools.json)) for transpile-and-run unit tests in ~6s warm. `al-runner` runs AL out-of-process by transpiling to C#/IL — fast, but doesn't fully simulate the BC platform (complex `TestPage` choreography, real DB state, permissions, lifecycle integration events beyond `--init-events`). Use it for pure-logic / library tests.
- **Outer loop** (full BC tier): `./scripts/test-integration.sh` runs `compile.sh` (analyzers on) then `bc-linux/scripts/run-tests.sh` to publish + execute tests inside the running container — the only path that exercises real BC behaviour end-to-end.
- **Mutation testing**: `./scripts/test-mutation.sh` (al-mutate). Currently flaky due to upstream issues; check the project notes before relying on it.

## Architecture & flow

The integration test pipeline is a fixed sequence in [`scripts/test-integration.sh`](scripts/test-integration.sh) and depends on conventions you must preserve when changing things:

- **Compile path**: all three projects share `/.alpackages/` at the repo root (`al.packageCachePath: "../.alpackages"` in the workspace settings, and [`scripts/compile.sh`](scripts/compile.sh) wraps `al-compile` which auto-detects the workspace cache). `download-symbols.sh` fills `.alpackages/` with the six Microsoft apps the test framework needs (`System`, `System Application`, `Business Foundation`, `Base Application`, `Application`, `Library Assert`). `compile.sh` builds `app` first and stages its `.app` into `.alpackages/` so dependents (`test`, `integration-test`) resolve the `Bc Linux Smoke` symbol. If you add a new Microsoft dep to any project's `app.json` (e.g. `Test Runner`, `Any`), append its name to `download-symbols.sh`'s `APPS` array.
- **Publish path** (test-integration.sh): production app is published via `bc-linux/scripts/publish-app.sh` (sourced, exposes `bc_publish_app`). Integration tests are published *and* executed by `bc-linux/scripts/run-tests.sh`, which is a hybrid OData (suite + results) + WebSocket (test session) flow — TestPage support requires a real client session, which OData alone cannot provide.
- **Unit test path** (`scripts/test-unit.sh`): runs `./scripts/compile.sh app test` for a fresh analyzer-clean gate, then wraps `al-runner` with the canonical args — `--packages .alpackages --output-junit .build/test-unit.xml app/src test/src`. Extra flags pass through (`--run`, `--coverage`, `--verbose`, …). al-runner downloads the BC Service Tier DLLs on first run and caches them; no container traffic. Failures exit 1, runner limitations exit 2 — use `--strict` in CI to escalate (2 → 1) so regressions in al-runner support don't silently look like passes.
- **ID ranges are load-bearing**: production codeunits live in `50000..50049` (per `app/app.json`), unit tests in `50100..50149` (per `test/app.json`), integration tests in `50150..50160` (per `integration-test/app.json` and the default `BC_TEST_CODEUNIT_RANGE`), with `50161` reserved for the opt-in stress-scale perf test (`BC_PERF_STRESS=1`). Adding tests outside the active range silently excludes them.
- **`BC_KEEP_APP_IDS` workaround**: the upstream entrypoint clears the Microsoft test framework apps on first boot and only reinstalls them when `BC_KEEP_APP_IDS` is non-empty. Locally this workspace pins the value in `bc-linux/.env`. In CI the keep-set is computed at setup time by `bc-linux/scripts/resolve-keep-app-ids.py`, written to `.bc-cache/env`, and appended into `bc-linux/.env` before BC boots. Either way, do not blank it — first boot will publish a test app against missing framework dependencies and fail.
- **Build outputs** land in `.build/`: `BcLinuxSmoke.app`, `BcLinuxSmokeTests.app`, `BcLinuxSmokeIntegrationTests.app` from `compile.sh`; `test-unit.xml` from `test-unit.sh`; `test-integration.xml` from `test-integration.sh`; `mutation/{mutations.json,report.md}` from `test-mutation.sh`. That dir, the shared `/.alpackages/`, and any per-project `.dev/` (al-compile diagnostics) are gitignored.

## Environment overrides

`test-integration.sh` and `download-symbols.sh` honor `BC_BASE_URL`, `BC_DEV_URL`, `BC_AUTH`; `test-integration.sh` additionally honors `BC_TEST_CODEUNIT_RANGE` and `BC_PERF_STRESS` (set to `1` to include codeunit 50161 in the default range). Defaults match the upstream BC stack (ports 7048/7049, `BCRUNNER:Admin123!`). `compile.sh`, `test-unit.sh`, and `test-mutation.sh` run out-of-process and take no BC env vars — they talk only to the local `.alpackages/`.

## VS Code

Open [`bc-on-linux-test.code-workspace`](bc-on-linux-test.code-workspace) at the repo root — a multi-root workspace with `app/`, `test/`, and `integration-test/` as folders. The workspace settings point `al.packageCachePath` at the shared `../.alpackages/` and wire `al.codeAnalyzers` to the Microsoft analyzers (`CodeCop`, `UICop`, `PerTenantExtensionCop`) plus the ALCops set (`Common`, `LinterCop`, `ApplicationCop`, `FormattingCop`, `PlatformCop`, `DocumentationCop`, `TestAutomationCop`). Recommended extensions are `ms-dynamics-smb.al` and `arthurvdv.alcops` — the latter auto-downloads the ALCops analyzer DLLs from the [`ALCops.Analyzers`](https://www.nuget.org/packages/ALCops.Analyzers) NuGet package into the AL extension's `bin/Analyzers/` folder on first activation. If you need them without launching VS Code (e.g. a fresh CLI-only setup), pull the `lib/net8.0/` DLLs from that NuGet package into the same folder by hand.

Each AL project has its own `.vscode/launch.json` with a `BC Linux` profile pointed at the local dev endpoint. For F5 publish, use `BCRUNNER` / `Admin123!`.

## Agent skills

### Issue tracker

Issues live in this repo's GitHub Issues (`FBakkensen/bc-on-linux-test`). Use the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Canonical role names used verbatim (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — one `CONTEXT.md` + `docs/adr/` at the repo root (neither exists yet; produced lazily by `/grill-with-docs`). See `docs/agents/domain.md`.
