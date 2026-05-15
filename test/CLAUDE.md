# CLAUDE.md — test/

Unit tests for AL logic. Transpiled to C#/IL by al-runner and executed
out-of-process — no BC container, no real DB. Use this folder for
pure-logic and library tests; for TestPage choreography, real DB state,
permissions, or full BC lifecycle events, write an `integration-test/`
test instead.

## Rules-of-the-land

- **Stubs only — no `Library Sales` / `Manufacturing` / `Purchase`.**
  Test our logic, not BC's. Every BC boundary in production code has an
  AL interface; the test wires up a stub implementation.
- **ID range `50100..50149`.** Anything outside is silently excluded.
- **al-runner, not the BC container.** Driver is `./scripts/test-unit.sh`
  (~6s warm). Transpiled execution means **no `TestPage`, no real DB,
  no permission engine, limited lifecycle events beyond `--init-events`.**
  If a test needs any of those, it belongs in `integration-test/`.
- **Codeunit-scope isolation.** Each test codeunit owns its own setup
  and teardown. Do not introduce cross-codeunit state.
- **Exit code 2 ≠ pass.** It signals an al-runner limitation. CI uses
  `--strict` to escalate `2 → 1` so regressions in al-runner support
  don't masquerade as green.

## Patterns

- **Stub naming**: `<Concept>Stub.Codeunit.al`. Existing examples:
  `EventSourceStub`, `NotificationDispatcherStub`, `StockoutCheckerStub`.
  Each implements the same AL interface as the production seam.
- **Extra al-runner flags pass through** `test-unit.sh`: `--run <Proc>`,
  `--coverage`, `--verbose`.
- **JUnit output**: `.build/test-unit.xml`.
- **First run is slow** — al-runner downloads the BC Service Tier DLLs
  on first invocation and caches them.
