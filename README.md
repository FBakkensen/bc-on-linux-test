# Business Central On Linux Smoke Workspace

This workspace is a local consumer setup for running Business Central on Linux for AL development and test execution only. It is built around the upstream [`StefanMaron/MsDyn365Bc.On.Linux`](https://github.com/StefanMaron/MsDyn365Bc.On.Linux) project, which is checked out into [`bc-linux/`](/home/fbakkensen/repos/bc-on-linux-test/bc-linux).

## Workspace layout

- [`bc-linux/`](/home/fbakkensen/repos/bc-on-linux-test/bc-linux): upstream Linux BC runtime, Docker Compose stack, and test runner scripts
- [`app/`](/home/fbakkensen/repos/bc-on-linux-test/app): minimal production AL app
- [`test/`](/home/fbakkensen/repos/bc-on-linux-test/test): AL unit tests (al-runner, stub-based, no container)
- [`integration-test/`](/home/fbakkensen/repos/bc-on-linux-test/integration-test): AL integration tests (run inside the BC container)
- [`scripts/download-symbols.sh`](/home/fbakkensen/repos/bc-on-linux-test/scripts/download-symbols.sh): pulls Microsoft symbol packages into `.alpackages/`
- [`scripts/compile.sh`](/home/fbakkensen/repos/bc-on-linux-test/scripts/compile.sh): compiles AL projects with full analyzer set
- [`scripts/test-unit.sh`](/home/fbakkensen/repos/bc-on-linux-test/scripts/test-unit.sh): fast unit-test loop (compile + al-runner)
- [`scripts/test-integration.sh`](/home/fbakkensen/repos/bc-on-linux-test/scripts/test-integration.sh): full BC-tier compile, publish, and test flow
- [`scripts/test-mutation.sh`](/home/fbakkensen/repos/bc-on-linux-test/scripts/test-mutation.sh): AL mutation testing via al-mutate

## Prerequisites

- Docker and Docker Compose access
- `python3`, `curl`, `unzip`
- `.NET 8 SDK`
- AL CLI tool available as `al`

## Start Business Central

The upstream repo defaults are used in this workspace:

- BC version: `28.1`
- Country: `w1`
- Dev endpoint: `http://localhost:7049/BC/dev`
- Base URL: `http://localhost:7048/BC`
- Credentials: `BCRUNNER` / `Admin123!`

This workspace also sets `BC_KEEP_APP_IDS` in `bc-linux/.env` as a workaround for an upstream startup mismatch: in this environment the entrypoint cleared the Microsoft test framework apps on first boot but did not reinstall them unless `BC_KEEP_APP_IDS` was non-empty. Keeping the framework IDs in that set makes first boot reliably install the core test framework and common test libraries before the custom `TestRunnerExtension` publish step.

Start the container stack from the upstream checkout:

```bash
cd bc-linux
docker compose up -d --wait
```

Verify the instance is reachable:

```bash
curl -sf -u BCRUNNER:Admin123! http://localhost:7048/BC/ODataV4/Company
```

## Download symbols

From the workspace root:

```bash
./scripts/download-symbols.sh
```

This fills the shared `.alpackages/` at the repo root.

## Run the integration test flow

From the workspace root:

```bash
./scripts/test-integration.sh
```

The script will:

1. verify the BC instance is running
2. run `./scripts/compile.sh` (all three projects, full analyzers)
3. publish the production app to the dev endpoint
4. publish the integration test app through `bc-linux/scripts/run-tests.sh`
5. execute every `Subtype=Test` codeunit found in the integration test `.app` (the runner auto-discovers them from `SymbolReference.json`)
6. write JUnit XML to `.build/test-integration.xml`

## Run the fast unit-test loop

No BC container required:

```bash
./scripts/test-unit.sh
```

Compiles `app/` + `test/` with full analyzers, then runs unit tests via al-runner. JUnit lands at `.build/test-unit.xml`.

## VS Code

[`/.vscode/launch.json`](/home/fbakkensen/repos/bc-on-linux-test/.vscode/launch.json) contains a `BC Linux` launch profile pointed at the local dev endpoint. On the first publish, use:

- Username: `BCRUNNER`
- Password: `Admin123!`

For a VS Code-first flow:

1. run `./scripts/download-symbols.sh`
2. open this folder in VS Code
3. use `AL: Download Symbols` if needed
4. publish with `F5` or `Ctrl+F5`

## Environment overrides

- `BC_BASE_URL`, `BC_DEV_URL`, `BC_AUTH` — honored by `download-symbols.sh` and `test-integration.sh`
