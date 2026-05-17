# CLAUDE.md — integration-test/

BC-tier integration tests. Publishes to the running container and
exercises the real composition root + production BC interface
implementations against a live service tier. The only path that
exercises real BC behaviour end-to-end.

## Rules-of-the-land

- **Real BC for the BC seam — stub only non-BC collaborators.** The
  `IT*Stub` codeunits in this folder (e.g. `ITNotificationDispatcherStub`,
  `ITStockoutCheckerStub`) stub *non-BC* dependencies we still want
  deterministic. Anything that talks to BC tables/codeunits goes
  through the real implementation.
- **ID range.** `app.json` reserves `50150..50199`. `test-integration.sh`
  passes no `--codeunit-range`; the upstream runner discovers every
  `Subtype=Test` codeunit from the compiled `.app` and runs all of them.
  Adding a new test codeunit anywhere in `50150..50199` just works.
  Fixture codeunits (no `Subtype = Test;`, e.g. `MaxSellablePerfFixture`)
  and stub codeunits (`IT*Stub`) are skipped automatically.
- **TestPage is fine here.** Real client session via OData + WebSocket —
  the only place you can choreograph pages, real DB state, permissions,
  and full BC lifecycle events. If a `test/` unit test needs any of
  these, port it here.
- **Container must be up before running.**
  `cd bc-linux && docker compose up -d --wait`. Verify with
  `curl -sf -u BCRUNNER:Admin123! http://localhost:7048/BC/ODataV4/Company`.

## Patterns

- **`*BCEventSourceTests.Codeunit.al`** — one codeunit per document
  type (`SalesLine`, `PurchaseLine`, `Assembly`, `ProdOrder`,
  `TransferLine`, `ServiceLine`, `JobPlanning`). Add a new one when the
  `EventSource` interface gains a BC implementation.
- **Perf test** — `MaxSellablePerfTypicalTests` (50160) pins the typing-SLA
  envelope per ADR 0004; setup lives in `MaxSellablePerfFixture` (50162,
  not a test codeunit). Scope is algorithmic regressions only — see ADR
  0004 for the index-scan caveat and the code-review mitigation.
- **`IT*Stub.Codeunit.al`** — keep narrow. Only stub what BC can't give
  you deterministically.
- **Skip recompile**: call `bc-linux/scripts/run-tests.sh` directly with
  the staged `.build/BcLinuxSmokeIntegrationTests.app`. Full args in
  root CLAUDE.md.
- **JUnit output**: `.build/test-integration.xml`.
