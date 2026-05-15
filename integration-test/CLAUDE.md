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
- **ID range gap to watch.** `app.json` reserves `50150..50199`, but
  the runner default `BC_TEST_CODEUNIT_RANGE=50150..50160` only
  executes that subset. Tests outside `50150..50160` are silently
  skipped unless you override.
- **Codeunit `50161` is opt-in.** Stress-scale perf test
  (`MaxSellablePerfStressTests`). Run with
  `BC_PERF_STRESS=1 ./scripts/test-integration.sh` to include it.
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
- **Perf tests** share `MaxSellablePerfFixture` for setup; typical
  (`MaxSellablePerfTypicalTests`) and stress (`MaxSellablePerfStressTests`)
  differ only in scale.
- **`IT*Stub.Codeunit.al`** — keep narrow. Only stub what BC can't give
  you deterministically.
- **Run a slice**:
  `BC_TEST_CODEUNIT_RANGE=50150..50150 ./scripts/test-integration.sh`.
- **Skip recompile**: call `bc-linux/scripts/run-tests.sh` directly with
  the staged `.build/BcLinuxSmokeIntegrationTests.app`. Full args in
  root CLAUDE.md.
- **JUnit output**: `.build/test-integration.xml`.
