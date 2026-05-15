# CLAUDE.md — app/

Production AL code for the `Bc Linux Smoke` app. Ports-and-adapters
shape: pure logic + AL interfaces in `src/logic/`, BC-specific
implementations and UI in `src/seams/`. Tests in `/test/` stub the
interfaces; tests in `/integration-test/` exercise the real seams.

## Rules-of-the-land

- **`src/logic/` is BC-free.** Pure logic and AL interfaces only. No BC
  tables, no `Library *` codeunits, no UI types. If you need to talk
  to BC from logic, declare an `interface` here and put the
  implementation in `src/seams/`.
- **`src/seams/` is the BC boundary.** Every concrete BC interaction
  (`BCEventSource`, `BCNotificationDispatcher`, `BCStockoutChecker`),
  every table, page, page-ext, table-ext, subscriber codeunit, and
  Page Background Task lives here. New BC-touching code goes here,
  never in `logic/`.
- **ID range `50000..50049`.** Outside the range = silently excluded.
- **Every BC seam has an interface.** Production code depends on the
  interface, not the BC implementation. Composition root wires `BC*`
  for prod; tests wire `*Stub`.
- **Page Background Tasks live in `seams/`.** PBT is a BC platform
  feature, so the PBT codeunit is a seam. The logic the PBT invokes
  belongs in `logic/`.

## Patterns

- **Interface naming**: `I<Concept>.Interface.al`. Implementations:
  `BC<Concept>.Codeunit.al` (seam) or `<Concept>Stub.Codeunit.al`
  (test).
- **EventSource pattern**: one interface (`IEventSource`), many BC
  implementations — one BC codeunit per document type. Adding a new
  doc-type implementation = new `BC*EventSource.Codeunit.al` here
  *and* matching `*BCEventSourceTests.Codeunit.al` in
  `/integration-test/`.
- **Subscribers go through logic.** `MaxSellableSubscribers` is the
  thin BC-event handler — delegate work to `logic/` codeunits, don't
  inline it in the handler.
- **FactBox + PBT pattern**: `MaxSellableFactBox.Page.al` +
  `MaxSellablePBT.Codeunit.al` is the canonical "compute and display
  without blocking the form" recipe (commit `6df7bc0`).
