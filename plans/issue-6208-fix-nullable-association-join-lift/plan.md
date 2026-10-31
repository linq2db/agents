# Work plan: issue-6208-fix-nullable-association-join-lift — keep OUTER APPLY rows when its subquery has an inner join

**Tier:** L  ·  **Status:** approved  ·  **Approved-at:** 2026-10-31 (after critic round 2, weak, objections in P12)  ·  **Branch:** issue/6208-fix-nullable-association-join-lift
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

## P1 Problem

[#6208](https://github.com/linq2db/linq2db/issues/6208): a nullable (`CanBeNull = true`) association whose query expression is `T.Where(...).Take(1)` joined to another table drops outer rows on SQL Server whenever the `Take(1)` side or the join has no match — both through `LoadWith(...).ThenLoad(...)` and through a plain projection of the association entity. Measured on master (`965f63450`), SqlServer.2022.MS, shared `Parent`/`Child`/`GrandChild` data: 8 rows returned, 17 expected (children 43, 44, 61–66, 77 have no `GrandChild` row and are dropped). Emitted SQL:

```sql
OUTER APPLY (
	SELECT TOP (1) [g_1].[ParentID] FROM [GrandChild] [g_1] WHERE [g_1].[ChildID] = [d].[ChildID]
) [a_LinkedParent]
	INNER JOIN [Parent] [p] ON [a_LinkedParent].[ParentID] = [p].[ParentID]
```

The AST nests the `INNER JOIN` under the apply's table source, but SQL Server has no `ON` for `OUTER APPLY`, so `BasicSqlBuilder.BuildJoinTable` (`BasicSqlBuilder.cs:2378-2381`) writes the nested join flat and the server parses it as an outer-level inner join. Right SQL (5.4.1.9 shape): the join stays inside the apply's subquery.

Cause: `SelectQueryOptimizerVisitor.JoinMoveSubQueryUp` (`SelectQueryOptimizerVisitor.cs:2614`) flattens the apply's subquery `SELECT p.* FROM (TOP 1 …) a INNER JOIN Parent p` and moves its joins onto the apply's table (`:2763`). The only guard on nested inner joins is `!IsOuterJoinSupportsInnerJoin` (`:2696`, Access only). 5.x's equivalent (`RemoveSubQuery`, `Source/LinqToDB/SqlQuery/SelectQueryOptimizer.cs` at `v5.4.1` ~`:1090-1113`) refused any non-inner parent whose subquery had joins of a different type.

## P2 Success criteria

- SC-1 `LoadWith(p => p.Children).ThenLoad(c => c.LinkedParent)` over the nullable `Take(1)`+join association returns all 17 children, with `LinkedParent == null` exactly for 43, 44, 61–66, 77, on every `[DataSources]` provider  → TO-1
- SC-2 Projecting the same association entity (`select new { c.ChildID, c.LinkedParent }`) returns all 17 rows with the same nulls on every provider  → TO-2
- SC-3 Providers that were already correct (PostgreSQL.17, DuckDB for TO-1/TO-2) stay correct with the subquery kept  → TO-3
- SC-4 The non-nullable twin (`CanBeNull = false`, `CROSS APPLY` / `INNER JOIN LATERAL`) returns exactly the 8 matched children on every provider, MySQL 8 included (red there on master)  → TO-4
- SC-5 A nullable association whose nested join is a `LEFT JOIN` on the outer key keeps `NULL` for unmatched rows on ON-less apply providers  → TO-5

## P3 Constraints & anti-goals (M/L)

- No public API change; `SqlProviderFlags` gains no member — the guard reuses `IsOuterApplyJoinSupportsCondition`.
- Generated SQL changes only for an `OUTER APPLY` / `CROSS APPLY` on an apply-capable provider whose subquery's first table carries a join. Inner, Left, Right, Full lifts and every no-apply provider are untouched.
- No SQL-builder change; no AST shape change.
- Anti-goal: restoring 5.x's broad "same join type only" rule for all non-inner joins (D-1 rejected alternative).

## P4 Unknowns (M/L)

- U-1 Does `IsOuterApplyJoinSupportsCondition` coincide exactly with "the builder emits `ON` for `OUTER APPLY`" on every provider? — resolved-by scout: per-provider table of `BuildJoinType` vs the flag; every provider setting it true returns `buildOn = true` for OuterApply (Firebird4SqlBuilder.cs:32, PostgreSQLSqlBuilder.cs:280, MySql80SqlBuilder.cs:46, SapHanaSqlBuilder.cs:250, DuckDBSqlBuilder.cs:241), every other one uses base `OUTER APPLY` / false (BasicSqlBuilder.cs:2438); no mismatch.
- U-2 Which nested join types are safe to render flat after an ON-less `OUTER APPLY`? — resolved-by critic counterexample: none. `INNER JOIN` / `CROSS APPLY` drop rows (measured, TO-1/TO-2); a nested `LEFT JOIN o ON f` whose `f` does not read the apply's source matches `o` in the flat form where the nested form yields NULL (e.g. a `DefaultIfEmpty` join on the outer key); a nested aggregate `OUTER APPLY` returns a row for NULL input. Hence D-2 refuses every nested join. The suite has no existing case of any nested join under an apply (U-4), so the refusal's churn is measured zero there.
- U-3 Is `JoinMoveSubQueryUp:2763` the only site that moves joins under an apply's table, and does any later pass un-nest them? — resolved-by scout: sole site; `MoveSubQueryUp:2012` targets top-level FROM tables only (caller `OptimizeSubQueries:2794`); `JoinsOptimizer.UnnestJoins` acts only under Inner/Left parents (`JoinsOptimizer.cs:62`); `UndoNestedJoins` (`JoinsOptimizer.cs:159`) runs only when `!IsNestedJoinsSupported` (YDB, ClickHouse — no apply there anyway).
- U-4 Does any existing test produce the affected shape (baseline churn)? — resolved-by scout: `git grep` over `linq2db.baselines` `origin/master` `8d570bf8c10`, 5918 `(OUTER|CROSS) APPLY (` blocks, 0 with a nested join one indent deeper after the closing alias. Expected churn: none beyond the new tests.
- U-5 After the refusal, does a later pass reshape the kept apply? — resolved-by critic reading: `OptimizeApplyJoin` (`SelectQueryOptimizerVisitor.cs:1535`) sees the outer dependency, finds no modifier on the kept body (`:1552`) and returns at `:1662` because the outer reference sits in `sql.From`; `UnnestJoins` (`JoinsOptimizer.cs:62`) and `MoveSingleOuterJoinToSubQuery` (`:3734`, bails on `join.Table.HasJoins`) leave it. Post-fix SQL still recorded in G-02.
- U-6 Oracle 12+ / SqlCe share the ON-less base rendering — resolved-by scout (OracleDataProvider.cs:61-62, SqlCeDataProvider.cs:34 set only `IsApplyJoinSupported`). SqlCe is file-based: measured locally (U-9). Oracle 12+ via CI test-all (G-08).
- U-8 What does the guard do on providers without apply (`IsApplyJoinSupported = false`, where the condition flag is vacuously false: SQLite, MySQL 5.7/MariaDB, Firebird 2.5/3, Access, DB2, Informix, Sybase, Oracle 11, ClickHouse, YDB)? — resolved-by critic reading + measurement: there the lifted shape is emulated by `OptimizeApplyJoin` (`:1572-1644`, `ROW_NUMBER`) and measured green on SQLite.MS; keeping the subquery instead routes to `MoveSingleOuterJoinToSubQuery:3718` and can end in a validator rejection for `SupportedCorrelatedSubqueriesLevel = 1` providers (`SqlQueryValidatorVisitor.cs:149-172`). Hence D-1 carries `IsApplyJoinSupported`; SQLite.MS re-run post-fix in G-01.
- U-9 Master on the other apply providers runnable without a container — resolved-by probe: measured on master, DuckDB (ON-carrying, no parentheses) passes TO-1/TO-2 (+ .LinqService); SqlCe (ON-less) fails all four cases with the SQL Server result (8 rows of 17).
- U-11 TO-5 on master — measured: SqlServer.2022.MS and SqlCe return 17 rows with a **non-null** parent for 43, 44, 61–66, 77 (flat `OUTER APPLY (…) a LEFT JOIN [Parent] [p] ON [p].[ParentID] = [c_1].[ParentID]`), confirming U-2's counterexample; TO-4 passes on all four providers. SQLite.MS throws `no such column: c_1.ParentID` (ROW_NUMBER emulation, nested `LEFT JOIN … ON [p].[ParentID] = [c_1].[ParentID]` inside the parenthesised join group); DuckDB throws `Non-inner join on correlated columns not supported` (`LEFT JOIN LATERAL (…) a LEFT JOIN Parent p ON p.ParentID = c_1.ParentID ON 1=1`). Those two are a different mechanism — a lifted nested join whose condition reads the outer query — and E-1 as written does not reach them. Regression check, measured with a scratch console on NuGet linq2db over the same `TestDataMS` / `TestData.MS.sqlite` data (`.build/.agents/probe6208`): SQL Server — both the issue shape and the outer-key shape correct on 5.4.1.9 (17 rows, 9 nulls), wrong on 6.0.0 and 6.5.1 (8 rows / 0 nulls) → regression, fixed by E-1. SQLite — 5.4.1.9 throws `near "(": syntax error` for **both** shapes, 6.0.0 returns the outer-key shape with 0 nulls (silent), 6.5.1 throws `no such column` → not a regression against 5.x, and DuckDB has no 5.x provider. — resolved-by user answer (2026-10-31): out of #6208's scope; a separate issue (drafted for approval) and an `[ActiveIssue]` gate on the providers still red after E-1.
- U-10 MySQL 8 / SAP HANA (ON-carrying but `IsNestedJoinParenthesisRequired`, `MySqlSqlBuilder.cs:29`, `SapHanaSqlBuilder.cs:64`) render the lifted shape as `LEFT JOIN LATERAL ((SELECT …) a INNER JOIN p ON …) ON 1=1`; MySQL's grammar wants a subquery right after `LATERAL` — is master red there, which E-1 (flag true) would not fix? — resolved-by probe: measured on master, MySqlConnector.8.0 (+ .LinqService) fails **all four** tests, TO-4's `CanBeNull = false` twin included, with `You have an error in your SQL syntax … near '`a_LinkedParent`'`; SQL `LEFT JOIN LATERAL ((SELECT … LIMIT 1) `a_LinkedParent` INNER JOIN `Parent` `p` ON …) ON 1=1`. The flag-keyed E-1 does not reach it; D-1 must be re-decided. HANA (same builder property) presumed identical, CI only.
- U-7 Is master red on PostgreSQL.17 too (would widen the defect beyond the flag)? — resolved-by probe: measured on master, TO-1/TO-2 pass on PostgreSQL.17 and .LinqService; SQL is `LEFT JOIN LATERAL (… LIMIT 1) "a_LinkedParent" INNER JOIN "Parent" p ON … ON 1=1` — the nested join is grouped by the trailing `ON`. (`CreateDatabase("PostgreSQL.17")` timed out transiently in that run; the data from the earlier session was intact, as the 17-row asserts show.)

## P5 Decisions (M/L; rejected alternatives mandatory at L)

### D-1 — Where the fix goes

- **chosen (revised after U-10, user-approved direction 2026-10-31):** a guard in `JoinMoveSubQueryUp` refusing the lift for `JoinType.OuterApply` **and** `JoinType.CrossApply` when `_providerFlags.IsApplyJoinSupported` and `subQuery.From.Tables[0]` carries any join (D-2). Covers ON-less applies (SQL Server, Oracle 12+, SqlCe: flat rendering) and parenthesised `LATERAL ((…))` (MySQL 8, SAP HANA: syntax error, all four tests incl. the CROSS twin). `IsApplyJoinSupported` keeps the measured-green emulation path of no-apply providers (U-8).
- **rejected:** key on `!IsOuterApplyJoinSupportsCondition` (the first draft) — misses MySQL 8 / HANA, where the flag is true and the lifted shape is a syntax error (U-10, measured).
- **rejected:** key on the builder's `IsNestedJoinParenthesisRequired` in addition — a `BasicSqlBuilder` property the optimizer cannot see; mirroring it needs a new `SqlProviderFlags` member (P3) to save a derived table on two providers.
- **rejected:** restore 5.x's rule for every non-inner parent (Left/Right/Full included) — Left/Full joins carry `ON` and nest correctly on every provider; no defect measured there, wider surface.
- **rejected:** fix in `BasicSqlBuilder.BuildJoinTable` by re-wrapping nested joins of an ON-less apply into a derived table at render time — the builder would have to synthesise a column list and re-point column references, an AST reshape inside the renderer.
- **rejected:** a post-pass in `JoinsOptimizer` (like `UndoNestedJoins`) that wraps an ON-less apply's nested joins back into a subquery — undoes a move that should not have happened, more code, and would also re-wrap shapes built nested on purpose.
- **why this:** an apply's source is a lateral subquery, and only the subquery itself can carry joins portably; every provider renders `APPLY (SELECT … FROM a JOIN b …)` correctly (5.4.1.9 SQL Server shape, measured correct). It costs PostgreSQL / DuckDB / Firebird 4+ a derived table where their nested `LATERAL … ON` form was already correct.
- **failure mode of the choice:** a slower plan on ON-carrying providers for these shapes (no wrong rows); and any test whose baseline captured a nested join under `LATERAL` moves — local `linq2db.bls` census by the critic found none besides this branch's PostgreSQL.17 files.

### D-2 — Which nested join types stay liftable

- **chosen:** none — any join on the subquery's first table blocks the lift under an ON-less `OUTER APPLY`.
- **rejected:** exempt `Left` / `OuterApply` nested joins — U-2's counterexamples (a `LEFT JOIN` on the outer key, an aggregate apply) change values in the flat form.
- **why this:** no nested join type is equivalent when flattened after an ON-less apply; U-4 measured zero existing cases, so the wider refusal costs no baseline.
- **failure mode of the choice:** a future shape where flattening was harmless keeps a derived table — slower SQL, never wrong rows.

## P6 Edit-points

- E-1 `Source/LinqToDB/Internal/SqlQuery/Visitors/SelectQueryOptimizerVisitor.cs:JoinMoveSubQueryUp` — add the D-1 guard (OuterApply / CrossApply, `IsApplyJoinSupported`, subquery table has joins) beside the `IsOuterJoinSupportsInnerJoin` check inside `if (joinTable.JoinType != JoinType.Inner)`.
- E-2 `Tests/Linq/Linq/LoadWithTests.cs:ThenLoadNullableJoinedAssociationKeepsUnmatchedRows` / `SelectNullableJoinedAssociationKeepsUnmatchedRows` / `SelectRequiredJoinedAssociationKeepsOnlyMatchedRows` / `SelectNullableLeftJoinedAssociationKeepsNulls` tests plus fixture-local `ParentWithLinkedChildren` / `ChildWithLinkedParent` mapped onto the shared `Parent` / `Child` tables.

## P7 Impact map (M/L)

- `SelectQueryOptimizerVisitor.cs:2763` `joinTable.Table.Joins.AddRange` — the only site moving joins under a joined table (searched `\.Joins\.(AddRange|InsertRange|Insert|Add)\(` and `Table\.Joins` under `Source/LinqToDB/Internal/`) — covered by E-1
- `SelectQueryOptimizerVisitor.cs:2862` `OptimizeJoinSubQueries` — sole caller of `JoinMoveSubQueryUp` (searched `JoinMoveSubQueryUp`), top-level joins only, every join type — covered by E-1
- `SelectQueryOptimizerVisitor.cs:2012` `MoveSubQueryUp` — targets top-level FROM tables (caller `:2794`), never an apply's table — out-of-scope
- `JoinsOptimizer.RemoveDuplicates.cs:242` `TryMergeSources2` — no-op when `join2.Table.Joins.Count != 0` (`:103`) — out-of-scope
- `JoinsOptimizer.cs:47-157` `UnnestJoins` / `:159-207` `UndoNestedJoins` — don't un-nest under apply on apply-capable providers — out-of-scope
- `BasicSqlBuilder.cs:2364-2428` `BuildJoinTable` and every `BuildJoinType` override (searched `BuildJoinType|IsNestedJoinSupported|IsNestedJoinParenthesisRequired`) — renderer unchanged; flag/renderer agreement in U-1 — out-of-scope
- `SqlProviderFlags` initialisers of `IsOuterApplyJoinSupportsCondition` (searched `IsOuterApplyJoinSupportsCondition` under `Source/`): Firebird 4+, PostgreSQL, MySQL 8, SAP HANA, DuckDB set true; `DistinctByBuilder.cs:179` also reads it — read only, no change — out-of-scope
- PR [#6157](https://github.com/linq2db/linq2db/pull/6157) (open, 6.6.0) adds `if (!_providerFlags.IsComplexJoinConditionSupported && subQuery.From.Tables[0].Joins.Count > 0)` inside `JoinMoveSubQueryUp` (hunk `@@ -2685,6 +2685,11 @@`, searched `gh pr diff 6157 --patch` for `JoinMoveSubQueryUp|IsComplexJoinConditionSupported`) plus `MoveJoinConditionsToWhere` at `:2893+`; its plan `.claude/plans/issue-6148-fix-ydb-left-join-outer-predicate/plan.md:156` (A-5) — independent condition (YDB/Access), textual conflict expected beside E-1 — out-of-scope; whichever merges second resolves by keeping both guards
- Baselines: 0 existing files with a nested join under an apply (U-4) — out-of-scope
- `SelectQueryOptimizerVisitor.cs:2724-2727` `#5413` guard (lift an `IsSubqueryExpression` apply only when every nested join `IsLimitedToOneRecord`) — same shape, now pre-empted by E-1 on apply providers (round-2 critic) — covered by E-1 (comment updated), P10

## P8 Test obligations (M/L)

- TO-1 `ThenLoadNullableJoinedAssociationKeepsUnmatchedRows` asserts the 17-row `(ChildID, LinkedParentID?)` list; discriminating input: children with no `GrandChild` row (43, 44, 61–66, 77) — providers: `[DataSources]` (measured red SqlServer.2022.MS + LinqService, green SQLite.MS) — proof: red→green
- TO-2 `SelectNullableJoinedAssociationKeepsUnmatchedRows` asserts the same list via projection of the association entity; discriminating input as TO-1 — providers: `[DataSources]` (measured red SqlServer.2022.MS + LinqService) — proof: red→green
- TO-3 TO-1/TO-2 on PostgreSQL.17 and DuckDB pass on master and after the fix — providers: PostgreSQL.17, DuckDB — proof: characterization (correct before and after; the SQL shape change is read in G-02)
- TO-4 `SelectRequiredJoinedAssociationKeepsOnlyMatchedRows`: a `CanBeNull = false` twin (built `CrossApply`, `FirstSingleBuilder.cs:278`) returns exactly the 8 matched children; discriminating input: MySQL 8's `INNER JOIN LATERAL ((…))` syntax error — providers: `[DataSources]` (measured red MySqlConnector.8.0 + LinqService, green SqlServer.2022.MS / SqlCe / SQLite.MS / DuckDB) — proof: red→green on MySQL 8 (E-1's CrossApply arm), characterization elsewhere
- TO-5 `SelectNullableLeftJoinedAssociationKeepsNulls`: nullable association `GrandChild.Where(ChildID).Take(1)` then `Parent` joined via `DefaultIfEmpty` on the **outer** key; asserts `LinkedParent == null` for 43, 44, 61–66, 77 — providers: `[DataSources]` (measured red SqlServer.2022.MS / SqlCe: wrong non-null parents; MySqlConnector.8.0: syntax error; SQLite.MS, DuckDB: separate errors, U-11) — proof: red→green on apply providers (measured post-fix green SqlCe, MySqlConnector.8.0, PostgreSQL.17); DuckDB still red post-fix → `[ThrowsForProvider]` per `JoinTests.cs:3272`; SQLite.MS still red → `[ActiveIssue(6224)]` ([#6224](https://github.com/linq2db/linq2db/issues/6224))

## P9 Verification gates

- G-01: pass — `worktree-test.ps1` net10.0 post-fix: TO-1/TO-2/TO-4/TO-5 green on SqlServer.2022.MS, SqlCe, MySqlConnector.8.0, PostgreSQL.17 (+ LinqService), red→green observed on SqlServer.2022.MS / SqlCe (TO-1, TO-2, TO-5) and MySqlConnector.8.0 (all four); SQLite.MS / DuckDB green with TO-5 gated (6 passed / 2 skipped, 8 passed). Sweep `AssociationTests|QueryableAssociationTests|LoadWithTests|EagerLoadingTests|JoinTests|ApplyJoinTests`: SqlCe 531 (0 failed, 6 skipped), SqlServer.2022.MS 649 (0 failed, 4 skipped).
- G-02: skipped — local `linq2db.bls` is not a git repo and the canonical baselines clone is empty, so no pre/post diff; post-fix SqlServer.2022.MS / SqlCe SQL read by hand (the 5.4.1.9 shape: join inside the APPLY subquery). Unverified: baseline moves on PostgreSQL / DuckDB / Firebird 4+ / Oracle 12+ / HANA — read on the CI baselines PR.
- G-05: pass — `dotnet build Source/LinqToDB/LinqToDB.csproj -c Release -f netstandard2.0` exit 0.
- G-06: pass — diff is the E-1 guard + one comment line and the E-2 tests.
- G-07: pass — nothing under `Tests/Tests.Playground/` changed.
- G-08: blocked — CI test-all (Oracle 12+, Firebird 4+, SAP HANA, no-apply families) pending a push.
- G-09: pass — `/code-review high` over the diff, 10 findings. Fixed: guard moved to the top of the non-inner block (cost), the outer-key test's expected value derived from `Child.ParentID`, branch rebased on `origin/master` (stale base). Declined with evidence:
  - The guard is too wide for `CROSS APPLY` and nested `LEFT` — both measured red on master (MySQL 8; the TO-5 counterexample on SQL Server).
  - Baseline churn — the U-4 census found 0 cases, and the sweeps show 0 failures.
  - `#5413` lift now unused — the `UpdateFromSubquery` tests pass on SqlServer.2022.MS / SQLite.MS (P10).
  - Builder-level fix — D-1 rejected alternative.
  - `DefaultIfEmpty` never null-extends and `Take(1)` has no order — both mirror the issue's shape over the shared data's invariants.
  - `FullApply` / `RightApply` — no producer measured.
  - Extend the guard to providers without APPLY — probed: SQLite TO-5 went green, `EagerLoadingTests.TestSelectGroupBy` went red, Access red either way (master too).

## P10 Adjudicated (M/L)

- Gating rule, pre-decided before the post-fix runs (round-2 objection): a red on a provider family where E-1 does not fire (`IsApplyJoinSupported = false`) or a server-side rejection of the kept correlated derived table on an apply provider is a pre-existing limitation, not this PR's regression. It is gated with `[ThrowsForProvider(...)]` naming the measured exception and message (precedent `JoinTests.cs:3272-3274`, `Issue3311Test3`: DuckDB `Non-inner join on correlated columns not supported`, the no-apply `Error_OUTER_Joins` family list, `[ThrowsRequiresCorrelatedSubquery]`) when the repo already records the mechanism, and with `[ActiveIssue]` on the new issue otherwise. Every gated family is either measured locally or named as CI-only (SAP HANA, Oracle 12+ unless its container is started).
- The `#5413` one-record exception (`SelectQueryOptimizerVisitor.cs:2724-2727`) becomes unreachable for apply joins on apply providers once E-1 refuses earlier — intended: a nested join of any cardinality is unsafe there (U-2, U-10). The `:2724` comment is updated by E-1 to say so.

## P11 Amendments (M/L)

_None._

## P12 Critic verdict (M/L)

- Round 1 (plan-critic, model `fable`): **weak**. Objections and dispositions:
  - MySQL 8 / SAP HANA parenthesised `LATERAL ((…))` rendering not covered by U-1 — accepted, U-10 (OPEN pending measurement).
  - The guard fires vacuously on no-apply providers, displacing their measured-green emulation — accepted, D-1 now carries `IsApplyJoinSupported`, U-8.
  - U-2's equivalence for nested `Left` / `OuterApply` is false (outer-key `LEFT JOIN`, aggregate apply) — accepted, D-2 refuses every nested join, TO-5 added.
  - U-2 contradicted U-4 ("exercised by the suite") — fixed.
  - P7 row on #6157 wrong: it does add a refusal in `JoinMoveSubQueryUp` — accepted, row corrected (re-checked with `gh pr diff`).
  - SqlCe is file-based — accepted, U-6/U-9.
  - No obligation reddens on E-1's boundary clauses — accepted, TO-4 relabelled; boundary mutants visible only through baselines (G-02).
  - U-5 closable by reading — accepted, closed.
  - Round 1 critic searched: `.Joins.(AddRange|InsertRange|Insert|Add)(` across `Source/LinqToDB` (25 sites, `:2763` sole nesting site confirmed); nested-join renderer properties; apply / correlation / subquery provider flags; all seven `BuildJoinType` overrides; `OptimizeApplyJoin` `:1527-1726`, `JoinMoveSubQueryUp`, `OptimizeJoins`, `MoveSingleOuterJoinToSubQuery`; the association's apply-type choice in `FirstSingleBuilder.cs`; local `linq2db.bls` baselines for `LATERAL ((` and nested joins under apply.
- Round 2 (plan-critic, model `fable`, on the D-1 revision): **weak**. The mechanism holds (pass order traced: `OptimizeApplyJoin(doNotEmulate: true)` at `:3306` runs before `OptimizeJoinSubQueries`, the kept shape returns at `:1662` and `MoveSingleOuterJoinToSubQuery:3772-3776`; depth-exact census of 19,438 local captures finds only this branch's files). Objections and dispositions:
  - DuckDB TO-5 stays red after E-1 — the kept shape is exactly `JoinTests.cs:3272` `Issue3311Test3`, already `[ThrowsForProvider(DuckDBException, "Non-inner join on correlated columns not supported")]` — accepted, P10 rule; gate with that precedent, not a new issue.
  - Oracle 12+ predicted red on TO-5 (`OracleDataProvider.cs:48` `IsSubqueryWithParentReferenceInJoinConditionSupported = false`, validator enforces only in column position `SqlQueryValidatorVisitor.cs:120`) — accepted; measure if the Oracle container is started, else CI, gated per P10.
  - No-apply families unmeasured for all `[DataSources]` tests — accepted, P10 rule pre-decided; post-fix run widened to every locally runnable provider.
  - The kept correlated derived table inside an apply is unprobed on Oracle 12+ / Firebird 4+ / HANA / DuckDB — accepted, G-01 measures what is local; HANA CI-only.
  - U-4's census pattern misses `JOIN LATERAL (` / `LATERAL ((` on the canonical baselines — accepted; the canonical clone's working tree is empty locally, so the post-fix baselines diff (G-02) is the instrument.
  - `#5413` guard missing from P7 — accepted, row and P10 entry added.
  - Critic searched: pass order `SelectQueryOptimizerVisitor.cs:280-345, 1527-1726, 2614-2773, 3292-3360, 3718-3877`; `IsApplyJoinSupported\s*=` (9 initialisers); correlation / take / subquery-column flags across `DataProvider/`; validator `_columnSubqueryLevel`; `Non-inner join on correlated` across `Tests/`; `IsSubqueryExpression` producers; `BasicSqlBuilder.cs:2364-2443`, `SapHanaSqlBuilder.cs:240-250`; depth-exact nested-join-under-apply/LATERAL census of `linq2db.bls`. Blocked for it: canonical `linq2db.baselines` grep (empty working tree, Bash `add_item`), any server run.
