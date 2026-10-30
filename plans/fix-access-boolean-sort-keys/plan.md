# Work plan: fix-access-boolean-sort-keys — Access boolean ORDER BY keys sort in .NET order

**Tier:** M  ·  **Status:** implemented  ·  **Branch:** fix/access-boolean-sort-keys (off origin/master `eb857b682`)  ·  **PR:** #6203 (draft, 6.6.0)
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

## P1 Problem

Jet/ACE evaluate True as -1, so an ascending ORDER BY on a boolean key (Yes/No column or predicate) puts the true rows first; .NET and every other provider put false first. Found by #6201's `Test_NullableComparisonAsOrderByItem` (CI run 40926564920, all 8 Access configs). #5969 (draft, stacked on #5956 → `feature/csharp15-runtime-async`) already carries the measured fix. User decision 2026-10-29: split it into its own PR off master, so native Access gets it independently of LibRed. #6201 gates its Access case on this PR until it merges.

## P2 Success criteria

- SC-1 A boolean ORDER BY key on native Access returns .NET's order, ascending and descending, for a column, a predicate over non-nullable operands and a DISTINCT query (A-3: a predicate over a nullable operand is #6209, P10).  → TO-1, TO-3
- SC-2 The ported code equals #5969's `AccessSqlExpressionConvertVisitor` block (`10f517d5f` + `817b052c2`) byte-for-byte, so #5969's later merge resolves trivially.  → G-06
- SC-3 No other provider's SQL moves (the change is Access-only).  → TO-2, TO-3

## P3 Constraints & anti-goals

- Port, don't redesign: #5969's design survived its critic rounds 2–3 and was measured on OleDb (DISTINCT rejects expression keys; flip + `({0})` accepted).
- Window-function test changes stay on #5969: native Access has no window functions; the override comes along only for parity.

## P4 Unknowns

- U-1 Is a predicate over a value-converted bool column (`r.Bool1 == true`, `!r.Bool1`) left alone by the converter guard, and so still sorting True first? — resolved-by scout: `QueryHelper.GetColumnDescriptorCore` (`Internal/SqlQuery/QueryHelper.cs:455-620`, master `eb857b682`) has arms for columns, fields, CTE fields, `{0}` expressions, binary / unary / cast / single-argument functions and aggregates, and none for a predicate or `SqlSearchCondition`, so a predicate yields no descriptor and is rewritten like any other Yes/No-valued key (reasoned from the code read, unprobed: no test orders by a predicate over a converted column). A bare converted column (`Issue3830OrderByTest`, `Bool1` as `Char(1)` + `BoolConverter`) is left alone: its baseline keeps `ORDER BY [r].[Bool1], [r].[Id]` on all four Access configs.
- U-2 Does the remote path's second convert pass rewrite an already rewritten key again? — resolved-by probe: `test-all` Azure 24940 green at `dd7c02011`, which on this base compares every direct baseline with its `.LinqService` twin (#6061); a double rewrite (`((key))`, a flipped flip) would differ. Local G-01 LinqService cases green as well.
- U-3 Do both Jet drivers accept `(key) DESC` under DISTINCT and `-[key]` under GROUP BY, which no local host can run? — resolved-by probe: CI 24940 green on the Jet OleDb / ODBC legs, with 11 baseline files (10 tests; `DistinctOrderByBooleanSequence` × 2) under `Access.Jet.OleDb/` and `Access.Jet.Odbc/` on `baselines/pr_6203`.
- U-4 Is the NULL-first half of the nullable-key arm reachable by an order-asserting test on the shared data? — resolved-by scout: `LinqDataTypes2` rows carry no NULL `BoolValue` (`Tests/Linq/Create/CreateData.cs:136-147`), and an Access Yes/No column stores none; an outer join produces one. A-3 adds `OrderByOuterJoinedBooleanKey` for it (`Types2` joined on `ParentID + 8`, NULL for ParentID 5–7).

## P5 Decisions

### D-1 — Port #5969's direction-flip design

- **chosen:** non-nullable key → direction flipped, key wrapped in an int-typed `({0})`; nullable key → int-typed unary minus, except under DISTINCT (flip); keys with a value converter or a DataType other than Boolean/Undefined are left alone.
- **rejected:** `Abs(key)` (#6201's E-20, A-5): native Jet rejects an expression key under a merged DISTINCT (critic round 7 on `feature-query-batches`, measured class on #5969). `IIF(p, 1, 0)`: same DISTINCT rejection (#5969 plan:31-34).
- **failure mode:** a nullable key under DISTINCT sorts NULL last (engine limit; Access stores no NULL Yes/No, so it is reachable only through an outer join or a computed key).

## P6 Edit-points

- E-1 `Source/LinqToDB/Internal/DataProvider/Access/AccessSqlExpressionConvertVisitor.cs` — `VisitSqlOrderByClause` / `VisitSqlOrderByItem` / `VisitSqlWindowOrderItem` / `IsBooleanSortKey` / `ToSortKey`, verbatim from #5969.
- E-2 `Tests/Linq/Linq/DistinctTests.cs` — #5969's `DistinctOrderByBoolean`, `DistinctOrderByNullableBoolean`, `GroupByNullableBooleanOrderByKey`, `ConcatOrderByBoolean`, `GroupByBooleanOrderByKey`, plus `DistinctOrderByBooleanSequence` (asserts the ID order; `AssertQuery` cannot see order).
- E-3 `Tests/Linq/Linq/ValueConversionTests.cs` — #5969's `Issue3830OrderByTest` (name kept for merge parity with #5969).
- E-4 `Tests/Linq/Linq/OrderByTests.cs` — `OrderByBooleanColumn`, `OrderByBooleanColumnDescending`, `OrderByBooleanPredicate` (moved from #6201 per user, plus a predicate key); `OrderByNullableBooleanColumn`, `OrderByNullableBooleanColumnDescending` (A-1: order over `Types2.BoolValue`, the nullable-key negate arm); `OrderByOuterJoinedBooleanKey` (A-3: Access-only, NULL first through an outer join) and `OrderByBooleanStoredAsInt16` with its `BoolAsInt16Table` (A-3: a bool mapped to `DataType.Int16`, excluded by the DataType clause alone).

## P7 Impact map

- Every native Access ORDER BY on a boolean key (searched: Grep `VisitSqlOrderByItem` overrides under `Internal/DataProvider`: none on master) — covered by E-1; CI baselines show the moved files.
- Behaviour change: an Access query ordering by a Yes/No column now gets .NET's order — deferred: release-note line, written through `/release-notes` at release, not by the implementer.
- #5969 / #5956 later merge master — deferred: resolved in #5969's merge. The visitor hunk is identical (SC-2); after A-2 the `Issue3830OrderByTest` body differs from #5969's, a one-test conflict to take this side of.
- Nullable-key arm (`-[key]`) with an order-asserting test — covered by E-4 (A-1). Searched: `git grep -l -E "^\s*-\[" origin/baselines/pr_6203 -- "Access.Ace.OleDb/*"` at `dd7c02011`: the one ORDER BY hit is `DistinctTests.GroupByNullableBooleanOrderByKey` (`AssertQuery`, order-blind); the other five are negations outside ORDER BY.

## P8 Test obligations

- TO-1 E-2 and E-4 green, direct + LinqService — providers: Access.Ace.OleDb, Access.Ace.Odbc — proof: red→green (red: the new tests without E-1, or with the arm or clause each one witnesses mutated; G-01).
- TO-4 E-3 `Issue3830OrderByTest`: a value-converted `Char(1)` bool column keeps CLR order — providers: Access.Ace.OleDb, Access.Ace.Odbc — proof: characterization (green with and without E-1; the column is excluded by both `IsBooleanSortKey` clauses, so it proves no new behaviour).
- TO-2 The same tests — providers: SQLite.MS — proof: characterization (no SQL change on a non-Access provider).
- TO-3 CI: the new tests on the Jet legs (not runnable locally), and modified baselines only under Access folders — providers: Access.Jet.OleDb, Access.Jet.Odbc, full test-all matrix — proof: characterization (proves the Jet drivers accept the emitted SQL and no other provider moved; no red arm on CI).

## P9 Verification gates

- G-01: pass (local, 2026-10-29, net10.0, worktree-test.ps1 -NoBuild):
  - Red: E-1 disabled by a temporary `L2DB_MUT` switch (removed). On ACE OleDb / ODBC, direct + LinqService, 20 of 95 failed: every order-asserting case (`OrderByBooleanColumn` / `…Descending` / `OrderByBooleanPredicate` / `DistinctOrderByBooleanSequence`). The `AssertQuery`-based #5969 tests stayed green (no order check; they guard the DISTINCT rejection).
  - Green: ACE OleDb / ODBC + SQLite.MS, direct + LinqService, 141/141.
  - Jet OleDb / ODBC are not runnable on this host; CI covers them.
  - A-1 (2026-10-30, `c9eb6ff23`, worktree-test.ps1): red with `ToSortKey`'s negate arm replaced by the bare key, `OrderByNullableBooleanColumn` / `…Descending` 4/4 failed on ACE OleDb and 4/4 on ACE ODBC (direct + LinqService); green at the head, ACE OleDb 6/6, ACE ODBC 6/6, SQLite.MS 5/5. The test data has no NULL `BoolValue`, so the NULL-first half of the negate arm stays unasserted.
  - test-diff-sweep.ps1 on the implemented tree (`c9eb6ff23`): 1 one-line chain, 1 nested chain (both `ValueConversionTests.cs` `Issue3830OrderByTest`, :894 / :896), 0 narrowed provider sets.
  - A-2 (2026-10-30, `d2bd22a9e`): `Issue3830OrderByTest` green on ACE OleDb 4/4, ACE ODBC 4/4, SQLite.MS 3/3 (characterization; the change is layout only). test-diff-sweep.ps1 `-IncludeWorkingTree` before the commit: 0 / 0 / 0.
  - A-3 (2026-10-30): `OrderByOuterJoinedBooleanKey` red with `flip` forced to `true` — `[2, 5, 6, 7, 1, 3, 4]` for `[5, 6, 7, 2, 1, 3, 4]`, ACE OleDb / ODBC, direct + LinqService (4/4 per driver); green at the head, 4/4 per driver, SQL `ORDER BY -[t].[BoolValue], [p].[ParentID]`. `OrderByBooleanStoredAsInt16` red with the DataType clause removed, direct + LinqService on both ACE drivers; green at the head on ACE OleDb, ACE ODBC and SQLite.MS. test-diff-sweep.ps1 `-IncludeWorkingTree` before the commit: 0 chains, 0 nested chains, 1 narrowed set (`OrderByOuterJoinedBooleanKey`, P10).
- G-02: blocked — the A-1 and A-3 tests have no CI run: `baselines/pr_6203` was written by test-all 24940 at `dd7c02011`, before them, so the Jet legs and the baselines of the new tests are unobserved until a test-all at the branch head (P12 O-2).
- G-05: pass — `Tests/Linq` Release net10.0 (builds `Source/LinqToDB` with analyzers): 0 warnings, 0 errors. Re-run after A-1 (`c9eb6ff23`), A-2 (`d2bd22a9e`) and A-3: 0 warnings, 0 errors each.
- G-06: pass — `git diff --stat`: 4 files, all in P6; the source hunk equals #5969's block.

## P10 Adjudicated

- A nullable key under DISTINCT sorts NULL last, where .NET sorts it first — reason: native Jet rejects every expression key under DISTINCT except a parenthesized select column (measured on #5969: `NOT key`, `-key` and `IIF` rejected, `(key)` accepted), so the flip is the only accepted rewrite; a Yes/No column stores no NULL, so only an outer-joined column reaches it (D-1).
- A predicate over a nullable operand (`p.Value1 > 1`) sorts its unknown rows last, where .NET puts them with false — reason: wrong on master and outside Access, filed as #6209 (Backlog). `SqlSearchCondition.CanBeNullable` is `false` (`SqlSearchCondition.cs:172`), so every predicate key takes the flip arm. Measured (P12 O-1): .NET `[1, 2, 4, 7, 3, 5, 6]`, ACE OleDb master `[2, 4, 3, 5, 6, 1, 7]`, PR `[1, 7, 3, 5, 6, 2, 4]`, SQLite.MS `[2, 4, 1, 7, 3, 5, 6]`.
- `OrderByOuterJoinedBooleanKey` runs on Access only — reason: the NULL position it asserts is .NET's (first), which other providers give only where their default NULL ordering agrees; the exclusion is read from the flags, not measured per provider (`SqlProviderFlags.DefaultNullsOrdering` is `Largest` on PostgreSQL, Oracle and DB2 and `AlwaysLast` on DuckDB and ClickHouse: `PostgreSQLDataProvider.cs:54`, `OracleDataProvider.cs:42`, `DB2DataProvider.cs:38`, `DuckDBDataProvider.cs:32`, `ClickHouseDataProvider.cs:56`).
- `VisitSqlWindowOrderItem` is unreachable on native Access — reason: native Access has no window functions; the override is kept for SC-2 parity with #5969, where LibRed reaches it (P3).
- `IsBooleanSortKey`'s `ValueConverter == null` clause has no isolating test — reason: user decision on P12 O-4 (2026-10-30) took the DataType-only witness; `Issue3830OrderByTest`'s column is excluded by both clauses, so removing the converter clause alone leaves the suite green.
- `Issue3830OrderByTest` keeps an `Issue<N>` name in a feature fixture — reason: merge parity with #5969 (E-3), next to the fixture's existing `Issue3830Test` group over the same `Issue3830TestTable`.

## P11 Amendments

- A-1 (2026-10-30, self-review SUG001: the nullable-key negate arm was reached only by `AssertQuery` tests, which do not check order) — E-4 gains `OrderByNullableBooleanColumn` / `…Descending` (`c9eb6ff23`). The approval of E-4 is void until re-confirmed.
  re-derives: P6 (E-4), P7 (nullable-key arm row), P9 (G-01, G-05)
  conventions: `testing.md` → *Test layout* rule 1 (one call per line); swept with `test-diff-sweep.ps1 -Ref fix/access-boolean-sort-keys` over `origin/master...` `Tests/`: 1 one-line chain and 1 nested chain, both in `Issue3830OrderByTest` (`ValueConversionTests.cs:894`, `:896`, ported verbatim from #5969 under E-3), 0 narrowed provider sets. The A-1 tests follow rule 1.
- A-2 (2026-10-30, user decision on the A-1 sweep hit) — E-3's `Issue3830OrderByTest` is rewritten one call per line (`d2bd22a9e`); its body now differs from #5969's. The approval of E-3 is void until re-confirmed.
  re-derives: P6 (E-3), P7 (#5969 merge row), P9 (G-01, G-05)
  conventions: `testing.md` → *Test layout* rule 1; swept with `test-diff-sweep.ps1 -IncludeWorkingTree` over `origin/master` `Tests/` before the commit: 0 one-line chains, 0 nested chains, 0 narrowed provider sets.
- A-3 (2026-10-30, user decisions on P12 O-1, O-3, O-4) — O-1 is filed as #6209 and SC-1 narrowed to predicates over non-nullable operands; E-4 gains `OrderByOuterJoinedBooleanKey` (O-3) and `OrderByBooleanStoredAsInt16` (O-4) in `e94ba90bb`; TO-1 splits, E-3 moving to TO-4 as characterization. The approval of E-4 is void until re-confirmed.
  re-derives: P2 (SC-1), P4 (U-4), P6 (E-4), P8 (TO-1, TO-4), P9 (G-01, G-02, G-05), P10
  conventions: `testing.md` → *Test layout* rule 1 and rule 2 (query syntax with one clause per line for the join), *A narrowed provider set is a claim*; swept with `test-diff-sweep.ps1 -IncludeWorkingTree` over `origin/master` `Tests/`: 0 chains, 0 nested chains, 1 narrowed set, the Access-only data source of `OrderByOuterJoinedBooleanKey`, adjudicated in P10.
- Same day: P4 and P10 added, P7 verdicts and P8 `providers:` / `proof:` fields filled, so the plan validates. These blocks were missing at approval; they record what the review measured (U-1..U-4) and the trade-offs D-1 and P3 already named.

## P12 Critic verdict

- Not run: the design is #5969's, already critiqued there (rounds 2–3) and by `feature-query-batches` round 7 against the alternative.
- Round 1 (2026-10-30, A-1 / A-2 and the added P4 / P10 blocks, plan-critic on fable): **weak**. Searched: the branch diff vs `eb857b682`, the visitor vs #5969's `817b052c2` (no hunk in the ORDER BY block), the baselines delta (28 M Access-only), `GetColumnDescriptorCore`, `Factory.Negate` and both convert passes, `DefaultNullsOrdering` per provider, #5969's plan. Objections, open:
  - O-1 A predicate key over a NULL operand always takes the flip arm (`SqlSearchCondition.CanBeNullable` is `false`, `SqlSearchCondition.cs:172`). Measured 2026-10-30 with a probe `Parent.OrderBy(p => p.Value1 > 1).ThenBy(p => p.ParentID)` (NULL `Value1` at 2 and 4): .NET `[1, 2, 4, 7, 3, 5, 6]`; ACE OleDb master `[2, 4, 3, 5, 6, 1, 7]`; ACE OleDb PR `[1, 7, 3, 5, 6, 2, 4]`; SQLite.MS `[2, 4, 1, 7, 3, 5, 6]`. Wrong on master and outside Access; the PR fixes true/false and moves the NULL rows from first to last. SC-1's "a predicate" and P10 entry 1 misstate this cell.
  - O-2 A-1's tests have no CI run on the Jet legs: `baselines/pr_6203` holds no `OrderByNullableBooleanColumn*` files; P9 needs a gate naming a run at the branch head.
  - O-3 P10 entry 2 suppresses the only test that tells the negate arm from the flip; an `[IncludeDataSources(TestProvName.AllAccess)]` outer-join test needs no other gates.
  - O-4 `Issue3830OrderByTest` is a control, not red→green (green without E-1 in G-01); and `Bool1` carries both `DataType.Char` and a converter, so neither `IsBooleanSortKey` guard clause has a mutant witness.
  - O-5 U-3 counted files as tests — fixed.
  - Dispositions (user, 2026-10-30): O-1 filed as #6209 (Backlog), SC-1 narrowed, P10 entry (A-3). O-2 open: G-02 blocked on a test-all at the branch head. O-3 answered by `OrderByOuterJoinedBooleanKey` (A-3). O-4: DataType clause witnessed by `OrderByBooleanStoredAsInt16` (A-3), the converter clause left unwitnessed (P10), E-3 relabelled characterization (TO-4). O-5 fixed. Not re-critiqued after A-3.
