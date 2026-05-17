# Instructions for GitHub Copilot Coding Agent

You are working in a Business Central AL extension repository. Unlike most
AL repos you've seen, **this one is wired so you can actually run BC and
verify your work** — not just compile it. Read this whole file before you
start a task. The authoritative description of the workspace lives in
[`CLAUDE.md`](../CLAUDE.md); this file is the Copilot-specific distillation.

## What's running in your environment

Before you started, the `copilot-setup-steps.yml` workflow already:

- Cloned `StefanMaron/MsDyn365Bc.On.Linux` into `bc-linux/` (gitignored —
  do **not** modify or commit anything in there).
- Downloaded BC artifacts (~3 GB) into `.bc-artifacts/`.
- Pulled the `bc-runner` and SQL Server docker images.
- Installed the .NET 8 SDK and the Linux AL compiler. The `al` command is
  on your `PATH`.
- Populated `app/.alpackages/` and `test/.alpackages/` with the BC
  platform + test framework symbols your AL projects need.
- Resolved which baseline BC apps to keep in the database and wrote them
  to `.bc-cache/env`.
- Fired `docker compose up -d` on the BC stack. By the time you run
  `./scripts/test-integration.sh` for the first time, BC is usually healthy or
  nearly so. If it isn't, wait ~1–2 minutes and retry — the container
  stays up for the rest of your session.

## Your dev loop

The only command you need:

```bash
./scripts/test-integration.sh
```

This compiles all three projects (`app/`, `test/`, `integration-test/`)
with the full analyzer set via `./scripts/compile.sh`, publishes the
production app and the integration test app to the running BC instance
via the dev endpoint, and runs every `[Test]` codeunit in the
`50150..50160` range (integration tests) through the BC test runner.
Results land in `.build/test-integration.xml` (JUnit).

For pure-logic changes you can also use `./scripts/test-unit.sh` — it
compiles `app/` + `test/` with analyzers and runs the unit tests in
`/test/` via al-runner out-of-process (no BC traffic). Output:
`.build/test-unit.xml`.

**Run it after every meaningful edit.** Read the output. If compilation
fails, fix the AL. If a test fails, read the assertion message and fix
either the production code or the test (whichever is wrong). Re-run.
The container persists across iterations — you do not need to restart
anything.

If the first invocation errors with "BC not reachable", BC is still
booting. Bring it up and wait:

```bash
(cd bc-linux && docker compose up -d --wait)
```

## What NOT to do

- **Do not run `docker compose down`, `docker stop`, or anything else
  that would tear down BC.** Killing the container forces a 1–2 minute
  cold start on the next iteration. There is no scenario in a normal
  task where you should restart BC.
- **Do not edit anything under `bc-linux/`, `.bc-artifacts/`,
  `.bc-cache/`, `.build/`, or either `.alpackages/`.** These are runtime
  state or vendored upstream. If something there looks broken, the
  answer is *not* to fix it by hand — describe the symptom in your PR
  and stop.
- **Do not blank `BC_KEEP_APP_IDS`** in `bc-linux/.env`. The upstream
  entrypoint clears the Microsoft test framework apps on first boot and
  only reinstalls them when that var is non-empty. Blanking it breaks
  the test publish on the next cold start.
- **Do not add new top-level `app/`, `test/`, or `integration-test/`
  directories.** The CI workflow `.github/workflows/bc-test.yml`,
  `scripts/compile.sh`, and `scripts/test-integration.sh` all know about
  this three-project layout; changing it means changing every reference.
- **Do not commit `.app` files**, dependency caches (`.alpackages/`),
  or anything in `.build/`. These are reproducible from source and
  already gitignored.

## Repository layout

```
app/                  ← production AL code, ID range 50000..50049
  app.json            ← extension manifest
  src/                ← .al files (objects)
test/                 ← unit test AL code (al-runner, no container), ID range 50100..50149
  app.json            ← unit test manifest, depends on app/
  src/                ← .al test codeunits ([Test] procedures)
integration-test/     ← integration test AL code (runs in container), ID range 50150..50160
  app.json            ← integration test manifest, depends on app/
  src/                ← .al test codeunits ([Test] procedures)
scripts/
  compile.sh          ← compile all 3 projects with analyzers (called by test-*.sh)
  test-integration.sh ← full BC-tier dev loop (compile + publish + container tests)
  test-unit.sh        ← fast unit-test loop (compile + al-runner, no container)
  test-mutation.sh    ← mutation testing via al-mutate
  download-symbols.sh ← pulls Microsoft symbol packages into .alpackages/
bc-linux/             ← upstream runtime (gitignored); has its own CLAUDE.md
.github/
  workflows/
    bc-test.yml             ← CI: re-runs test-integration.sh on a clean runner on push
    copilot-setup-steps.yml ← what set up your environment (don't edit)
  copilot-instructions.md   ← this file
CLAUDE.md             ← canonical workspace documentation
```

## AL conventions in this repo

- Production codeunits use IDs **50000..50049**. Unit tests (in `/test/`)
  use **50100..50149**. Integration tests (in `/integration-test/`) use
  **50150..50199**. These ranges are declared in the respective `app.json`
  files and are **load-bearing**: `test-unit.sh` filters by the unit
  range; `test-integration.sh` passes no range and lets the upstream
  runner auto-discover every `Subtype=Test` codeunit from the compiled
  `.app`, so new integration tests anywhere in `50150..50199` are picked
  up without script edits. Adding tests outside the right `app.json`
  range silently excludes them. If you need more, expand the range in
  `app.json` first.
- One AL object per file. Filename pattern: `<Name>.<Type>.al`
  (e.g. `Customer.Table.al`, `HelloWorld.Codeunit.al`).
- Test codeunits must declare `Subtype = Test;` and use the `[Test]`
  attribute on each test procedure. Use `Codeunit "Library Assert"` for
  assertions — it ships with the BC test framework already staged in
  `test/.alpackages/`.
- Follow the pattern in `test/src/HelloWorldTest.Codeunit.al`: GIVEN /
  WHEN / THEN comment structure, descriptive procedure names, one logical
  assertion per test.

## When you're done

Commit your changes and open a PR as usual. The `bc-test.yml` workflow
will re-run the full compile + publish + test cycle on a clean runner —
this is your independent validation. If `test-integration.sh` was passing locally
but CI fails, the most likely cause is a stale `.app` checked in or a
missing `.al` file; check your `git status` carefully.

## If something goes wrong

- **`test-integration.sh` says "Checking Business Central availability..." and
  fails on curl**: BC isn't up yet. Run
  `(cd bc-linux && docker compose up -d --wait)` and retry.
- **AL compile fails on a missing symbol**: your `.alpackages/` is
  missing the symbol. Re-run the CI-path staging directly from the BC
  artifact bundle (no running BC needed):
  ```bash
  python3 bc-linux/scripts/stage-symbols.py \
      --app-json app/app.json --app-json test/app.json \
      --artifact-dir ".bc-artifacts/$(ls .bc-artifacts | head -1)" \
      --out-dir .symbols
  cp .symbols/*.app app/.alpackages/
  cp .symbols/*.app test/.alpackages/
  ```
  If the symbol still isn't there, the BC artifact didn't ship it for
  this version/country combination — pick a different API or add the
  missing module to `dependencies` in `app.json`. Do **not** run
  `./scripts/download-symbols.sh` here — that's a local-dev tool which
  hits a running BC dev endpoint and is the wrong path in this
  environment.
- **A test fails with a message you don't understand**: re-read the
  test, the production code, and the assertion message together. Do
  *not* delete or skip the test — fix the underlying issue.
- **Publish fails with AL1024 (dependency missing)**: the app you
  depend on wasn't kept in the selective filter. Verify the `dependencies`
  array in `app.json` / `test/app.json` is correct, then restart BC so
  the entrypoint re-resolves the keep set.

## Known pitfalls

- **AL runtime / compiler pairing.** Both `app.json` files declare a
  `runtime` value that the pinned AL compiler must support. The CI pins
  AL `16.2.28.57946` (`.github/workflows/copilot-setup-steps.yml`).
  Runtime `16.0` works; `16.1` fails with AL1043. If you need a newer
  runtime, bump `AL_TOOL_VERSION` in `copilot-setup-steps.yml` in the
  same PR as the `app.json` change — the two are coupled.

## The point of all this

This workspace exists to prove that an AI coding agent can do the full
compile-publish-test cycle on Business Central autonomously, with no
human in the loop. You are the test of that claim. Take your time,
iterate carefully, and let the test runner be your ground truth.
