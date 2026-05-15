# Perf testing approach for Max Sellable Calc

Two integration tests pin `RunGatedFlow` latency. A typical-scale scenario
(50 mixed events, max < 300ms) enforces the typing-SLA on the synchronous
Sales Line `OnValidate` path — 300ms is the classic perceptual-lag
boundary, so a regression past it is a regression the user *feels*. A
stress-scale scenario (2000 mixed events, max < 2000ms) catches
algorithmic blowups — e.g., a quadratic regression in event collection
or `MinWalk`. Both run 1 warm-up call (discarded) plus 5 measured calls
and assert on the max of the 5.

Budgets were initially set blind (1000ms / 30000ms) and ratcheted down
once real timings landed — observed steady-state is ~30ms typical and
~500ms stress, so the current budgets give ~10× headroom over steady
state and ~4× over observed max. Wide enough to absorb Docker/CI noise
without flaking; tight enough that a 5-10× regression fails the build.
[ADR 0002](0002-max-sellable-calc-architecture.md) makes cache
introduction conditional on real-data measurements; these budgets are
the real-data measurements, and the steady-state numbers say cache is
not yet justified.

The harness times `RunGatedFlow` end-to-end (not `Calculate` alone) with
both `Stockout Warning` and `Max Sellable Warning` enabled and on-hand
seeded above demand so the gate's fast path runs through CU 311 and
into `Calculate`. This matches the synchronous typing path real customers
exercise on every Sales Line keystroke; `Calculate`-only measurement
would under-report our contribution to that latency and would miss
regressions in the gate code (`Setup.Get`, the stockout check, the
notification construction).

Stress runs only when `BC_PERF_STRESS=1` is set in the test-integration.sh
environment, so the typical-scale test runs every local cycle and CI
sees the full envelope. Failure messages embed all 5 timings;
on success JUnit's `<testcase time>` is sufficient drift signal — no
custom logging plumbing until real evidence shows we need it.

**Scope limitation — what this test does NOT cover.** The fixture seeds
all N events against a single freshly-created item; no background rows
exist for other SKUs. Source tables during the measurement contain
~N matching rows plus a small Cronus baseline, not the millions of rows
a real customer's tables would. This catches *algorithmic* regressions
in our code (a quadratic walk, a forgotten `SetCurrentKey`, a CalcFields
inside the sweep loop) because algorithmic cost scales with matching
rows, not total rows. It does NOT catch *index-scan* regressions — if
someone replaces a BaseApp `FilterLinesWithItemToPlan` call with a raw
`SetFilter` on a non-key field, our tiny baseline makes the resulting
table scan look free; a customer with 10M Sales Lines would feel it
immediately. The mitigation is small: only our `BCEventSource` and
`StartingOnHandAt` are at risk of introducing such a change, and both
should use BaseApp helpers or `CalcSums` on indexed key fields — review
that invariant on every change to those procedures.
