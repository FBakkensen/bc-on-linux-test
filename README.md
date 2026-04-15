# Business Central On Linux Smoke Workspace

This workspace is a local consumer setup for running Business Central on Linux for AL development and test execution only. It is built around the upstream [`StefanMaron/MsDyn365Bc.On.Linux`](https://github.com/StefanMaron/MsDyn365Bc.On.Linux) project, which is checked out into [`bc-linux/`](/home/fbakkensen/repos/bc-on-linux-test/bc-linux).

## Workspace layout

- [`bc-linux/`](/home/fbakkensen/repos/bc-on-linux-test/bc-linux): upstream Linux BC runtime, Docker Compose stack, and test runner scripts
- [`app/`](/home/fbakkensen/repos/bc-on-linux-test/app): minimal production AL app
- [`test/`](/home/fbakkensen/repos/bc-on-linux-test/test): minimal AL test app that depends on `app/`
- [`scripts/download-symbols.sh`](/home/fbakkensen/repos/bc-on-linux-test/scripts/download-symbols.sh): pulls Microsoft symbol packages into both AL projects
- [`scripts/smoke.sh`](/home/fbakkensen/repos/bc-on-linux-test/scripts/smoke.sh): terminal-first compile, publish, and test flow

## Prerequisites

- Docker and Docker Compose access
- `python3`, `curl`, `unzip`
- `.NET 8 SDK`
- AL CLI tool available as `al`

## Start Business Central

The upstream repo defaults are used in this workspace:

- BC version: `27.5`
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

This fills:

- `app/.alpackages/`
- `test/.alpackages/`

## Run the smoke flow

From the workspace root:

```bash
./scripts/smoke.sh
```

The script will:

1. verify the BC instance is running
2. compile the production app to `.build/BcLinuxSmoke.app`
3. copy the production `.app` into `test/.alpackages/`
4. compile the test app to `.build/BcLinuxSmokeTests.app`
5. publish the production app
6. publish the test app through `bc-linux/scripts/run-tests.sh`
7. execute the test codeunits in the `50100..50149` range
8. write JUnit XML to `.build/test-results.xml`

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

Both scripts honor these optional environment variables:

- `BC_BASE_URL`
- `BC_DEV_URL`
- `BC_AUTH`
- `BC_TEST_CODEUNIT_RANGE` (smoke script only)
