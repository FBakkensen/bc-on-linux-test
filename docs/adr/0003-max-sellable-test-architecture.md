# Max Sellable Quantity — test architecture

Unit tests for the Max Sellable Qty calculation must exercise *our* logic in
isolation from BC standard. We adopt a two-test-app split with dependency
inversion at the few BC integration points that `al-runner` cannot simulate.
Unit tests use stubs and never depend on BC test libraries; integration tests
verify the BC implementations against a real BC tier.

## Why dependency inversion only at the al-runner gaps

`al-runner` (`BusinessCentral.AL.Runner`, pinned via `dotnet-tools.json`)
runs AL out-of-process against an in-memory record store. It handles natively:

- All table CRUD against the in-memory store
- FlowField evaluation via `CalcFields`
- Filter expressions, `SetRange`/`SetFilter`, `FindSet`/`Next`
- `WorkDate()` (settable in tests)
- Event subscriber dispatch
- Setup tables (`Sales & Receivables Setup` etc. — they're just tables)

What al-runner does NOT handle: **methods on BaseApp objects** are
auto-generated as blank shells — right signature, returns type-default, does
nothing. This breaks any prod code path that depends on BaseApp method
*behavior*, even when the underlying tables work fine. For Max Sellable, the
breaking points are:

- `SalesLine.FilterLinesWithItemToPlan(Item)` (and equivalents on every source
  table) — no-op blank shell, applies zero filters
- `Item-Check Avail.` (CU 311) — no-op blank shell, never warns
- `NotificationLifecycleMgt.SendNotification(...)` — no-op blank shell

Every other BC touchpoint (ILE access, setup reads, `WorkDate()`, raw table
queries) is exercised directly in unit tests without abstraction.

## The three interfaces

1. **`IEventSource`** — given `(Item, Variant, Location, ExcludingSalesLine)`,
   returns a stream of `(Date, ±Qty in base UoM)` events.
   - Prod implementation calls `FilterLinesWithItemToPlan` on each source table
     and emits one event per remaining row.
   - Stub implementation exposes a setter to register fixture events; returns
     them verbatim.

2. **`IStockoutChecker`** — wraps `Item-Check Avail.` (CU 311).
   - Prod calls the real codeunit.
   - Stub exposes a setter for the pass/fail result.

3. **`INotificationDispatcher`** — wraps `NotificationLifecycleMgt.SendNotification`.
   - Prod calls the real BC notification plumbing.
   - Stub records each dispatch in an in-memory list so tests can assert
     "we would have notified with message X" without firing real notifications.

No interface is introduced for things al-runner already handles correctly
(raw table I/O, FlowFields, WorkDate, setup tables). Adding interfaces there
would be abstraction without testability payoff.

## App layout

- **`/app/`** — production app. Defines the three interfaces, the BC
  implementations, the calc codeunit, the validate handler, the FactBox page,
  and the `Sales & Receivables Setup` tableextension + pageextension. Object
  IDs in the existing 50000..50049 range.

- **`/test/`** — unit test app. Depends on `/app/` + `Library Assert` only.
  Contains the three stub implementations and the calc-algorithm tests. Runs
  via `al-runner`, no BC container required. Object IDs 50100..50149.

- **`/integration-test/`** — integration test app (new). Depends on `/app/` +
  `Library Assert` + the minimum BC test libraries needed to set up fixtures
  against real BC. Tests:
  (a) the BC implementations of the three interfaces against real BC tables;
  (b) end-to-end behaviour with the real composition root.
  Runs in the container via `test-integration.sh`. Object IDs 50150..50199.

## Pipeline changes that fall out

- `scripts/test-integration.sh` builds prod + integration-test, publishes both, runs
  integration-test in the container. It stops touching `/test/`.
- `scripts/test-unit.sh` keeps running `/test/` via al-runner. This is now
  the primary test path — most tests live there.
- `BC_TEST_CODEUNIT_RANGE` default shifts to 50150..50199 (integration tests).
  Unit tests at 50100..50149 are al-runner-only and never run in the container.
- `.code-workspace`, `download-symbols.sh` (the `APPS` array), and the
  workspace `al.packageCachePath` need entries for the new app and its
  library dependencies.

## Consequences

- Every production code path that touches a BaseApp codeunit must go through
  one of the three interfaces. Direct `Codeunit.Run` calls or hard-coded
  `Item-Check Avail.` calls in prod code are a bug — the unit tests cannot
  reach those paths.
- Adding a new BC integration to Max Sellable in the future means asking
  "is the touched object an `al-runner` blank shell? if yes, new interface;
  if no, direct call is fine."
- ILE-based fixtures in unit tests are explicitly allowed: tests insert
  Item Ledger Entry records directly and let our code call `CalcFields` —
  there is no `IOnHandReader` abstraction layered on top.
- The composition root (where prod implementations are wired into the calc
  and handler) lives in `/app/` and is exercised only by integration tests.
  Unit tests construct the calc with stub interfaces inline.
