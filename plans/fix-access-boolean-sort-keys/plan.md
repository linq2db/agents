# Work plan: fix-access-boolean-sort-keys — Access boolean ORDER BY keys sort in .NET order

**Tier:** M  ·  **Status:** implemented  ·  **Branch:** fix/access-boolean-sort-keys (off origin/master `eb857b682`)  ·  **PR:** #6203 (draft, 6.6.0)
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

## P1 Problem

Jet/ACE evaluate True as -1, so an ascending ORDER BY on a boolean key (Yes/No column or predicate) puts the true rows first; .NET and every other provider put false first. Found by #6201's `Test_NullableComparisonAsOrderByItem` (CI run 40926564920, all 8 Access configs). #5969 (draft, stacked on #5956 → `feature/csharp15-runtime-async`) already carries the measured fix. User decision 2026-10-29: split it into its own PR off master, so native Access gets it independently of LibRed. #6201 gates its Access case on this PR until it merges.

## P2 Success criteria

- SC-1 A boolean ORDER BY key on native Access returns .NET's order, ascending and descending, for a column, a predicate and a DISTINCT query.
- SC-2 The ported code equals #5969's `AccessSqlExpressionConvertVisitor` block (`10f517d5f` + `817b052c2`) byte-for-byte, so #5969's later merge resolves trivially.
- SC-3 No other provider's SQL moves (the change is Access-only).

## P3 Constraints & anti-goals

- Port, don't redesign: #5969's design survived its critic rounds 2–3 and was measured on OleDb (DISTINCT rejects expression keys; flip + `({0})` accepted).
- Window-function test changes stay on #5969: native Access has no window functions; the override comes along only for parity.

## P5 Decisions

### D-1 — Port #5969's direction-flip design

- **chosen:** non-nullable key → direction flipped, key wrapped in an int-typed `({0})`; nullable key → int-typed unary minus, except under DISTINCT (flip); keys with a value converter or a DataType other than Boolean/Undefined are left alone.
- **rejected:** `Abs(key)` (#6201's E-20, A-5): native Jet rejects an expression key under a merged DISTINCT (critic round 7 on `feature-query-batches`, measured class on #5969). `IIF(p, 1, 0)`: same DISTINCT rejection (#5969 plan:31-34).
- **failure mode:** a nullable key under DISTINCT sorts NULL last (engine limit; Access stores no NULL Yes/No, so it is reachable only through an outer join or a computed key).

## P6 Edit-points

- E-1 `Source/LinqToDB/Internal/DataProvider/Access/AccessSqlExpressionConvertVisitor.cs` — `VisitSqlOrderByClause` / `VisitSqlOrderByItem` / `VisitSqlWindowOrderItem` / `IsBooleanSortKey` / `ToSortKey`, verbatim from #5969.
- E-2 `Tests/Linq/Linq/DistinctTests.cs` — #5969's `DistinctOrderByBoolean`, `DistinctOrderByNullableBoolean`, `GroupByNullableBooleanOrderByKey`, `ConcatOrderByBoolean`, `GroupByBooleanOrderByKey`, plus `DistinctOrderByBooleanSequence` (asserts the ID order; `AssertQuery` cannot see order).
- E-3 `Tests/Linq/Linq/ValueConversionTests.cs` — #5969's `Issue3830OrderByTest` (name kept for merge parity with #5969).
- E-4 `Tests/Linq/Linq/OrderByTests.cs` — `OrderByBooleanColumn`, `OrderByBooleanColumnDescending`, `OrderByBooleanPredicate` (moved from #6201 per user, plus a predicate key).

## P7 Impact map

- Every native Access ORDER BY on a boolean key (searched: Grep `VisitSqlOrderByItem` overrides under `Internal/DataProvider`: none on master) — covered by E-1; CI baselines show the moved files.
- Behaviour change: an Access query ordering by a Yes/No column now gets .NET's order — release-note line.
- #5969 / #5956 later merge master: identical hunk (SC-2).

## P8 Test obligations

- TO-1 E-2..E-4 green on Access.Ace.OleDb / Access.Ace.Odbc, direct + LinqService — proof: red→green (red: run the new tests on the base build, without E-1).
- TO-2 The same tests on SQLite.MS — proof: characterization (no SQL change on a non-Access provider).
- TO-3 CI: Jet legs (not runnable locally) and the full matrix; baselines move only under Access folders.

## P9 Verification gates

- G-01: pass (local, 2026-10-29, net10.0, worktree-test.ps1 -NoBuild):
  - Red: E-1 disabled by a temporary `L2DB_MUT` switch (removed). On ACE OleDb / ODBC, direct + LinqService, 20 of 95 failed: every order-asserting case (`OrderByBooleanColumn` / `…Descending` / `OrderByBooleanPredicate` / `DistinctOrderByBooleanSequence`). The `AssertQuery`-based #5969 tests stayed green (no order check; they guard the DISTINCT rejection).
  - Green: ACE OleDb / ODBC + SQLite.MS, direct + LinqService, 141/141.
  - Jet OleDb / ODBC are not runnable on this host; CI covers them.
- G-05: pass — `Tests/Linq` Release net10.0 (builds `Source/LinqToDB` with analyzers): 0 warnings, 0 errors.
- G-06: pass — `git diff --stat`: 4 files, all in P6; the source hunk equals #5969's block.

## P12 Critic verdict

- Not run: the design is #5969's, already critiqued there (rounds 2–3) and by `feature-query-batches` round 7 against the alternative.
