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
  `./scripts/smoke.sh` for the first time, BC is usually healthy or
  nearly so. If it isn't, wait ~1–2 minutes and retry — the container
  stays up for the rest of your session.

## Your dev loop

The only command you need:

```bash
./scripts/smoke.sh
```

This compiles `app/`, then `test/` (with `app/` as a dependency),
publishes both `.app` files to the running BC instance via the dev
endpoint, and runs every `[Test]` codeunit in the `50100..50149` range
through the BC test runner. Results land in `.build/test-results.xml`
(JUnit).

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

Narrow the test slice while iterating:

```bash
BC_TEST_CODEUNIT_RANGE=50100..50100 ./scripts/smoke.sh
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
- **Do not add new top-level `app/` or `test/` directories.** The CI
  workflow `.github/workflows/bc-test.yml` and `scripts/smoke.sh` are
  both hard-coded to compile `app/` and `test/`; changing the layout
  means changing both.
- **Do not commit `.app` files**, dependency caches (`.alpackages/`),
  or anything in `.build/`. These are reproducible from source and
  already gitignored.

## Repository layout

```
app/                  ← production AL code, ID range 50000..50049
  app.json            ← extension manifest
  src/                ← .al files (objects)
test/                 ← test AL code, ID range 50100..50149
  app.json            ← test extension manifest, depends on app/
  src/                ← .al test codeunits ([Test] procedures)
scripts/
  smoke.sh            ← the dev loop you should run after edits
  download-symbols.sh ← pulls Microsoft symbol packages into .alpackages/
bc-linux/             ← upstream runtime (gitignored); has its own CLAUDE.md
.github/
  workflows/
    bc-test.yml             ← CI: re-runs smoke.sh on a clean runner on push
    copilot-setup-steps.yml ← what set up your environment (don't edit)
  copilot-instructions.md   ← this file
CLAUDE.md             ← canonical workspace documentation
```

## AL conventions in this repo

- Production codeunits use IDs **50000..50049**. Tests use **50100..50149**.
  These ranges are declared in the respective `app.json` files and are
  **load-bearing**: `smoke.sh` and the CI workflow both filter tests by
  the test range. Adding tests outside `50100..50149` silently excludes
  them from the run. If you need more, expand the range in `app.json`
  first.
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
this is your independent validation. If `smoke.sh` was passing locally
but CI fails, the most likely cause is a stale `.app` checked in or a
missing `.al` file; check your `git status` carefully.

## If something goes wrong

- **`smoke.sh` says "Checking Business Central availability..." and
  fails on curl**: BC isn't up yet. Run
  `(cd bc-linux && docker compose up -d --wait)` and retry.
- **AL compile fails on a missing symbol**: the symbol isn't staged in
  the relevant `.alpackages/`. Re-run `./scripts/download-symbols.sh`.
  If the symbol still isn't there, the BC artifact didn't ship it for
  this version/country combination — pick a different API or add the
  missing module to `dependencies` in `app.json`.
- **A test fails with a message you don't understand**: re-read the
  test, the production code, and the assertion message together. Do
  *not* delete or skip the test — fix the underlying issue.
- **Publish fails with AL1024 (dependency missing)**: the app you
  depend on wasn't kept in the selective filter. Verify the `dependencies`
  array in `app.json` / `test/app.json` is correct, then restart BC so
  the entrypoint re-resolves the keep set.

## The point of all this

This workspace exists to prove that an AI coding agent can do the full
compile-publish-test cycle on Business Central autonomously, with no
human in the loop. You are the test of that claim. Take your time,
iterate carefully, and let the test runner be your ground truth.
