# Perf testing approach for Max Sellable Calc

A single integration test pins `RunGatedFlow` latency. A typical-scale
scenario (50 mixed events, max < 300ms) enforces the typing-SLA on the
synchronous Sales Line `OnValidate` path — 300ms is the classic
perceptual-lag boundary, so a regression past it is a regression the
user *feels*. The test runs 1 warm-up call (discarded) plus 5 measured
calls and asserts on the max of the 5.

Budget was initially set blind (1000ms) and ratcheted down once real
timings landed — observed steady-state is ~30ms, so the current budget
gives ~10× headroom over steady state. Wide enough to absorb Docker/CI
noise without flaking; tight enough that a 5–10× regression fails the
build. [ADR 0002](0002-max-sellable-calc-architecture.md) makes cache
introduction conditional on real-data measurements; this budget is the
real-data measurement, and the steady-state number says cache is not
yet justified.

The harness times `RunGatedFlow` end-to-end (not `Calculate` alone) with
both `Stockout Warning` and `Max Sellable Warning` enabled and on-hand
seeded above demand so the gate's fast path runs through CU 311 and
into `Calculate`. This matches the synchronous typing path real customers
exercise on every Sales Line keystroke; `Calculate`-only measurement
would under-report our contribution to that latency and would miss
regressions in the gate code (`Setup.Get`, the stockout check, the
notification construction).

Failure messages embed all 5 timings; on success JUnit's
`<testcase time>` is sufficient drift signal — no custom logging
plumbing until real evidence shows we need it.

**Scope limitation — algorithmic vs index-scan regressions.** The
fixture seeds all N events against a single freshly-created item; no
background rows exist for other SKUs. Source tables during the
measurement contain ~N matching rows plus a small Cronus baseline, not
the millions of rows a real customer's tables would. A larger-scale
stress variant (2000 mixed events) existed during development and would
in principle catch *algorithmic* regressions — a quadratic walk, a
forgotten `SetCurrentKey`, a `CalcFields` inside the sweep loop — but
it was never wired into a regular run (CI or local) and was removed as
unused legacy. The current test catches the same class of regression
at the typical-scale signal: a quadratic blowup pushes 50 events past
the 300ms typing budget too, just with less headroom.

What the test does NOT catch is *index-scan* regressions — if someone
replaces a BaseApp `FilterLinesWithItemToPlan` call with a raw
`SetFilter` on a non-key field, our tiny baseline makes the resulting
table scan look free; a customer with 10M Sales Lines would feel it
immediately. The mitigation is small: only our `BCEventSource` and
`StartingOnHandAt` are at risk of introducing such a change, and both
should use BaseApp helpers or `CalcSums` on indexed key fields — review
that invariant on every change to those procedures.

## Revision history

- **2026-05-17** — Removed the opt-in stress-scale test (codeunit 50161,
  `BC_PERF_STRESS=1` gate). The dual-test framing was a development-time
  artefact: the stress variant was never run by CI or in the local
  loop, and its algorithmic-regression role is adequately covered by
  the typical-scale budget at lower headroom. Dropping it also removes
  the only reason `scripts/test-integration.sh` needed a hand-maintained
  codeunit range; the runner now auto-discovers tests from the `.app`.
