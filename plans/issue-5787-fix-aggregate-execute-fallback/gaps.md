# Gap ledger: issue-5787-fix-aggregate-execute-fallback

## Round 1 — reviewed HEAD cbeffd0356e136b518030e687c598c1b1f137a62

### Attribution

- **SUG001** — GAP-02 — `P8 TO-4` recorded the red arm as "*no exception at all* (`But was: null`) — the untranslatable aggregate is silently dropped from the `ORDER BY` and the query runs" without checking whether the result was actually wrong (a rows/`LastQuery` check would have shown it was not). The plan's own `P3` constraint ("the fix only fires on a path that currently ends in a runtime `InvalidOperationException`, so no query that succeeds today may change shape") is contradicted by that very red arm — the OrderBy shape is a query that *succeeded* on master — and neither the author nor the `P12` critic reconciled the two. The behaviour change was visible inside the plan; the test XML summary (`Tests/Linq/Linq/AggregationTests.cs:351-354`) and the PR body's "Also fixed" section inherited the unchecked claim. — preventable: yes
- **SUG002** — GAP-05 — `P8` contains no `TO-n` for a correlated aggregate (`db.Types.Where(t => t.ID == x.ID).Min(...)`) in either a projection or `Where`; every obligation (TO-1, TO-2, TO-4, TO-6) and every probe (`U-1`, `U-2`, `U-4`) used the uncorrelated `db.Types.Min(...)` shape inherited from the issue repro. `P2` SC-1/SC-2 enumerate the aggregate-operator axis (Min/Max/Sum/Average/direct `AggregateExecute`) but not the correlation axis, which is exactly where master's behaviour differs (`must be reducible node` after a query is sent; a refusal message leaking the `AggregateExecute(source => source.AsQueryable()…)` marker). Secondary class GAP-01 (P2 never named the correlated shape as a requirement). — preventable: yes

### Aggregate

Both findings trace to one design-pass blind spot: the issue's uncorrelated repro was treated as representative, and correlation was never varied. A single `P4` unknown — "does correlating the aggregate to the outer row change the route or the master-side outcome?" — probed once would have caught both: it would have shown the correlated OrderBy already refused on master (exposing that TO-4's "silent drop" was the constant-key case), and surfaced the correlated projection's distinct failure as its own TO. Not an even spread — one probe-discipline change covers 2 of 2.

### Recommended durable fixes

- GAP-02 ×1 (+GAP-05 ×1 indirectly) → `plan-critic.md` attack vector: when a `TO-n` red arm is "no exception / query runs", demand evidence the result was wrong (rows or SQL), and cross-check it against any `P3` claim that the change only touches already-failing paths — a red arm that contradicts a `P3` constraint is an objection on its own.
- GAP-05 ×1 (+GAP-02 ×1 indirectly) → `work-plan.md` `P8` semantics (and `testing.md` if it recurs): for fixes in subquery / aggregate building, enumerate test shapes over both correlated and uncorrelated variants of the issue repro; an obligation set built only on the uncorrelated form is incomplete unless `P4` records why correlation cannot change the route.
