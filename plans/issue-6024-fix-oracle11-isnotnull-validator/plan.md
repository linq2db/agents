# Work plan: issue-6024-fix-oracle11-isnotnull-validator — Oracle 11 validator rejects IS NOT NULL on a column subquery's own table (#6024)

**Tier:** L  ·  **Status:** approved  ·  **Approved-at:** 2026-10-11 (user; critic round 1 weak, objections folded in; U-3/U-4/U-5/U-8 close during implementation) ·  **Branch:** issue/6024-fix-oracle11-isnotnull-validator
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

## P1 Problem

On Oracle 11 (`IsColumnSubqueryShouldNotContainParentIsNotNull = version < v12`, `OracleDataProvider.cs:50`), the final query validator rejects queries before any SQL is sent: `LinqToDBException: The LINQ expression could not be converted to SQL` / `Column expression should not contain parent's IS NOT NULL condition.` This happens whenever a column-position subquery carries `IS NOT NULL` over **its own** source, with no parent reference.

Measured red on master (`04a29c6a2`), `Oracle.11.Managed` and `Oracle.11.Managed.LinqService`; the same tests are green on SQLite.MS:
- `db.Parent.Where(p => p.Value1 != null).Any(p => p.Value1 > 1)`: a root `Any`, which becomes `SELECT CASE WHEN EXISTS(SELECT * FROM Parent p WHERE p.Value1 IS NOT NULL AND p.Value1 > 1) ... FROM SYS.DUAL`.
- The root `All` variant.
- A correlated `Any` in a projection.
- A correlated `Count(g => g.ParentID == p.ParentID && g.ChildID != null)` in a projection.

Mechanism, from code read; the critic verifies it:
- `SqlQueryValidatorVisitor.VisitIsNullPredicate` (`SqlQueryValidatorVisitor.cs:385-391`) calls `QueryHelper.IsDependsOnOuterSources(predicate, currentSources: _currentSources)`.
- `_currentSources` holds a source only while `VisitSqlTableSource` visits that source's own subtree: push, visit, pop (`:366-375`).
- `QueryElementVisitor` visits FROM before SELECT and WHERE (`QueryElementVisitor.cs:2456-2463`), and a join's `Table` before its `Condition` (`:2089-2094`).
- So by the time a query's WHERE, select list or ON condition is visited, that query's own sources have been popped, and every own-table field counts as "outer".
- Provenance per shape (from code read; not measured on an old build):
  - TO-1, TO-2 and TO-3 (`CASE WHEN EXISTS(...)` reached through a search condition) regressed in #5500 (`4f98a0233`, v6.3.0+). #5500 inlined the check with a `_columnSubqueryDepth` counter that, unlike `_columnSubqueryLevel`, is **not** reset by `VisitSqlSearchCondition`, so these positions are now checked. Pre-#5500 code skipped them.
  - TO-4 (a scalar `Count` directly in column position) was probably already rejected since the flag was introduced in 6.0 (`7ec71d530`). The nested `ValidateThatQueryHasNoIsNotNullParentReferenceVisitor` had the identical push/pop and the same visit order.
  - The PR body words this per shape and does not claim "regressed in 6.3.0" for all four.
- The check runs before `ExprExpr.Reduce` adds null-companion `IS NOT NULL` predicates (`SqlExpressionOptimizerVisitor.cs:1545/1626`, after `ExpressionBuilder.cs:297`). So it only ever sees user-written null checks. That is why `Issue1261Tests.TestLinqAll` (Oracle 11 SQL `CASE WHEN NOT EXISTS(... x."ChildID" IS NOT NULL ...)`) passes today.

Surfaced as `PivotTests.UnpivotOverAProjectionInASubQuery` failing on Oracle.11.Managed in [#5708](https://github.com/linq2db/linq2db/pull/5708), run 38108332138.

## P2 Success criteria

- SC-1 The four P1 repro shapes execute on Oracle 11 (direct and LinqService) and return the same result as LINQ-to-objects.  → TO-1, TO-2, TO-3, TO-4
- SC-2 An `IS NOT NULL` that really references a source outside the innermost column subquery is still rejected on Oracle 11.  → TO-5
- SC-3 No currently-passing Oracle 11 test regresses. Every test whose query shape changes because of the narrowed rule is enumerated (census U-3), and each one either passes or has its expectation updated with a verified reason.  → TO-6
- SC-4 `JoinAggregateArrayNotNull` and `Concat_OverGrouping_DistinctNullableValues` (`StringJoinTests.cs:419`, `StringConcatTests.cs:337`) carry an Oracle 11 expectation that matches observed post-fix behaviour, with the reason recorded. The census says D-1 no longer fires on either, so the possible outcomes are (a) passes; (b) throws a different validator error (critic's prediction for `JoinAggregateArrayNotNull`: `Error_OUTER_Joins` via `SupportedCorrelatedSubqueriesLevel = 1`, the pre-#5500 expectation); (c) runtime ORA-00904. (c) triggers P10's stop rule.  → TO-7, TO-8
- SC-6 (A-1) Oracle 11 tests with aggregate column subqueries that passed before the fix still pass, and the two A-1 shapes raise no ORA-00904.  → TO-10
- SC-5 Providers without the flag (everything except Oracle < 12) are untouched: no SQL or behaviour change.  → TO-9

## P3 Constraints & anti-goals (M/L)

- No new public members. `SqlQueryValidatorVisitor` is in `LinqToDB.Internal.*`. Its `VisitSqlTableSource` override is a shipped declared-API entry (`PublicAPI.Shipped.txt:12036`), and its fate is D-2. `SqlProviderFlags` is unchanged (it is serialized to LinqService with `[DataMember(Order = 44)]`).
- No change to the visit order of `QueryElementVisitor`, or to `QueryHelper.IsDependsOnOuterSources` semantics. Other callers depend on them (scout: `SelectQueryOptimizerVisitor.cs:1548/1635/1752/2915/4209`, `BasicSqlOptimizer.cs:1430`, `QueryHelper.cs:177`).
- No code change in the build-time fallback machinery (`IsSupportedSubquery`, `MoveSingleOuterJoinToSubQuery`, `TryMoveUpdateToSubQuery`). Their verdicts do change on Oracle 11 through the validator (D-1) and the flag (A-1/E-6). For example, `MoveSingleOuterJoinToSubQuery` now refuses to move an OUTER APPLY whose inner derived table is correlated, which is where `Error_OUTER_Joins` comes from. That is intended and covered by TO-7, TO-8 and TO-11.
- Not re-deciding which IS NOT NULL shapes genuinely break Oracle 11 beyond what the census and probes measure. The flag stays and its semantics narrow to "parent".
- Anti-goal: don't restore the pre-#5500 "not checked under search conditions" behaviour by resetting `_columnSubqueryDepth` in `VisitSqlSearchCondition`. That narrows by position, not by reference: a real parent reference inside `CASE WHEN EXISTS` would no longer be rejected.

## P4 Unknowns (M/L)

- U-1 Does the visit order make own-table predicates look outer? — resolved-by scout: `QueryElementVisitor.cs:2456-2463` (FROM, then SELECT, then WHERE) and `:2089-2094` (Table, then Condition), plus measured red on all 4 repro shapes.
- U-2 Does a rejection by this check get rescued by a fallback shape, or does it throw? — resolved-by scout + probe. On a provider without APPLY, `Query<T>` rebuilds with `ValidateSubqueries = true` (`Query{T}.cs:222-233`); if final validation still fails, it throws. Measured: all 4 repro shapes throw, so no fallback rescues them.
- U-3 Which existing Oracle 11 queries does the current check reject, and for which does the narrowed rule change the verdict? — resolved-by probe. The census completed over the full Tests.Linq run on Oracle.11.Managed + LinqService (10896 tests, `test-6024-census.log` / `census-6024.txt`). The check fired in exactly 6 tests: the 4 new tests plus `Concat_OverGrouping_DistinctNullableValues` and `JoinAggregateArrayNotNull`, all `newFires=False`. The critic checked by hand that D-1's scope is a superset of master's `_currentSources` at every position. So D-1 never fires where master does not, and the census, which logs master firings, is complete for verdict changes.
- U-8 Can the prototype report "parent" at all? (No `newFires=True` has been observed yet.) — resolved-by probe: TO-5's shape logged `newFires=True` 4× (`census-6024.txt` rows 25-28).
- U-4 Does the minimal-repro SQL execute on a real Oracle 11 once the validator lets it through? — resolved-by probe: TO-1..TO-4 pass on Oracle.11.Managed + LinqService (`test-6024-final.log`).
- U-5 `JoinAggregateArrayNotNull`: is its rejection a real Oracle 11 limitation? Its IS NOT NULL is on a VALUES/UNION derived table whose legs reference outer `t` two levels up, so it may fail at runtime (ORA-00904) or hit `SupportedCorrelatedSubqueriesLevel = 1` / `Error_OUTER_Joins` instead. — resolved-by probe. It is a real limit, but not an IS NOT NULL one. With D-1 alone it fails at runtime with ORA-00904 (correlation inside an inline view). With A-1/E-6 it raises `Error_OUTER_Joins`.
- U-6 Does `IsDependsOnOuterSources` treat a `SqlColumn` of a derived table, or a CTE field, as resolvable through `EnumerateAccessibleSources`? — resolved-by scout: `QueryHelper.cs:144-154` collects `field.Table`, `SqlCteTableField.Table` and `column.Parent`. `EnumerateAccessibleSources(SqlTableSource)` (`:1105-1121`) yields the derived `SelectQuery` itself (via `EnumerateAccessibleSources(q)`, `:1160-1169`) plus non-query sources and joins.
- U-9 Delete the `VisitSqlTableSource` override, or keep it as a pass-through (D-2)? — resolved-by user answer: delete.
- U-7 Do the build-time probes in `MoveSingleOuterJoinToSubQuery` and `TryMoveUpdateToSubQuery` run this check on the probed query's own body? — resolved-by scout: no. They pass the query as root with `_columnExpressionDepth = 0`, so `_columnSubqueryDepth` stays 0 for its own WHERE (`SelectQueryOptimizerVisitor.cs:3747-3802`, `BasicSqlOptimizer.cs:1196`). The fix does not change what those probes see, except for nested column subqueries.

## P5 Decisions (M/L; rejected alternatives mandatory at L)

### D-1 — "Parent" means outside the innermost column-subquery boundary

- **chosen:** Track a scope of accessible sources:
  - A **column-subquery boundary** is a `SelectQuery` reached from a column expression with no other `SelectQuery` entered in between. `VisitSqlColumnExpression` sets an "at column" flag, and `VisitSqlQuery` consumes and clears it, saving and restoring it.
  - At a boundary, start a fresh scope.
  - Every `SelectQuery` visited inside a scope (the boundary itself, its derived tables, set-operator legs, nested EXISTS/IN subqueries) appends `QueryHelper.EnumerateAccessibleSources(selectQuery)` for the duration of its visit.
  - `VisitIsNullPredicate` passes that scope as `currentSources`.
  - The push/pop in `VisitSqlTableSource` is removed, because the scope supersedes it. What happens to the override is D-2.
- **rejected:**
  - (a) Reset `_columnSubqueryDepth` in `VisitSqlSearchCondition`, restoring the pre-#5500 positional gate. Narrows by position, not reference, and drops real parent references inside `CASE WHEN EXISTS` (P3 anti-goal).
  - (b) Push each query's own sources onto the existing stack before visiting its children, with no boundary reset. The parent query of the column subquery is itself on the path, so its sources would be "current" too and nothing would ever be "outer". The check would become dead.
  - (c) Reset scope at the *outermost* column boundary only. Misses a reference from a nested column subquery to an intermediate column subquery's source, which the pre-#5500 per-subquery visitor did flag.
  - (d) Rewrite as a per-boundary `EnumerateAccessibleSources` check in `IsValidSubQuery`. Reintroduces the O(N²) walk #5500 removed (`SqlQueryValidatorVisitor.cs:236-239`).
- **why this:**
  - It matches the flag's documented contract (`SqlProviderFlags.cs:350-366`): a column-list scalar subquery whose body contains IS NOT NULL with a *parent* reference.
  - It mirrors how the sibling join check already resolves "outer" (`SqlQueryValidatorVisitor.cs:222-233`, `EnumerateAccessibleSources(selectQuery)`).
  - It keeps the single traversal.
- **failure mode of the choice:**
  - Queries the old rule rejected get through, and the validator becomes the only gate. If any of them hits a real Oracle 11 limit (ORA-00904 deep correlation) that the over-broad rule was hiding, it now fails at runtime instead of being rerouted to a fallback shape. Detected by the U-3 census plus the full Oracle 11 run (TO-6).
  - Cost: `EnumerateAccessibleSources` is called per `SelectQuery` inside column subqueries, only when the flag is set. That means Oracle 11 only, so other providers pay nothing.

### D-2 — The `VisitSqlTableSource` override

- **chosen:** (a) delete the override and add a `*REMOVED*` line (E-5). User decision, 2026-10-11.
- **rejected / alternatives:**
  - (a) Delete the override. Cleanest code. It is a shipped declared-API entry, so it needs a `*REMOVED*` line in `PublicAPI.Unshipped.txt`. ApiCompat may also report `CP0002` on pack, and then the PR regenerates `CompatibilitySuppressions.xml` via `/api-baselines` (unknown, not probed).
  - (b) Keep it as a pass-through (`base.VisitSqlTableSource(element); return element;`). No API or baseline churn, but it leaves a dead override.
- **failure mode of the choice:** (a) costs a pack and baseline cycle if ApiCompat flags it; (b) ships dead code that a reader has to puzzle over.

## P6 Edit-points

- E-1 `Source/LinqToDB/Internal/SqlQuery/Visitors/SqlQueryValidatorVisitor.cs:VisitIsNullPredicate/VisitSqlQuery/VisitSqlColumnExpression/VisitSqlTableSource/Cleanup` — replace the push/pop `_currentSources` stack with a boundary-scoped accessible-source list per D-1, gated on `IsColumnSubqueryShouldNotContainParentIsNotNull`; update the `:379-384` comment if its wording becomes false.
- E-2 `Tests/Linq/Linq/AllAnyTests.cs:Issue6024_*` — the four repro tests (TO-1..TO-4) and the parent-reference control (TO-5).
- E-3 `Tests/Linq/Linq/StringJoinTests.cs:JoinAggregateArrayNotNull` — adjust the Oracle 11 `ThrowsForProvider` only if TO-7 shows it changed.
- E-4 `Tests/Linq/Linq/StringConcatTests.cs:Concat_OverGrouping_DistinctNullableValues` — adjust the Oracle 11 `ThrowsForProvider` only if TO-8 shows it changed.
- E-5 `Source/LinqToDB/PublicAPI/PublicAPI.Unshipped.txt` — one `*REMOVED*` line for the deleted `SqlQueryValidatorVisitor.VisitSqlTableSource` override (D-2).
- E-6 `Source/LinqToDB/Internal/DataProvider/Oracle/OracleDataProvider.cs:ctor` — `CalculateSupportedCorrelatedLevelWithAggregateQueries = version < OracleVersion.v12` (A-1).
- E-7 `Tests/Linq/UserTests/Issue5256Tests.cs:NestedSubqueryWithGroupedAggregationsFilteredSumOfSums` — drop `AllOracle11` from the `DataSources` exclusion and add it to `ThrowsRequiredOuterJoins` (A-2).

## P7 Impact map (M/L)

- `Source/LinqToDB/Internal/DataProvider/SqlProviderHelper.cs:12` IsValidQuery — every validator entry goes through it — covered by E-1
- `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuilder.cs:297` final validation then `Query{T}.cs:222-233` / `CompiledTable{T}.cs:118-133` retry-and-throw — the path the repro dies on — covered by E-1
- `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuilder.SqlBuilder.cs:160-224` IsSupportedSubquery build-time probe (callers `ExpressionBuildVisitor.cs:5346`, `:1825`, `DefaultIfEmptyBuilder.cs:123`, `SelectManyBuilder.cs:146`) — may pick a different shape once the rule narrows; measured by the census — covered by E-1
- `Source/LinqToDB/Internal/SqlQuery/Visitors/SelectQueryOptimizerVisitor.cs:3747-3802` MoveSingleOuterJoinToSubQuery and `Source/LinqToDB/Internal/SqlProvider/BasicSqlOptimizer.cs:1196` TryMoveUpdateToSubQuery probes — the query's own body is not checked (U-7); nested column subqueries are — covered by E-1
- `Source/LinqToDB/Internal/SqlProvider/SqlProviderFlags.cs:368` flag + `OracleDataProvider.cs:50` — unchanged; searched `IsColumnSubqueryShouldNotContainParentIsNotNull` across Source+Tests, no other setter — out-of-scope
- `Source/LinqToDB/Remote/LinqServiceInfo.cs:16-17` flags serialized whole — no shape change — out-of-scope
- `Localized — searched Stack<ISqlTableSource>|_currentSources|override IQueryElement VisitSqlTableSource across Source/, only SqlQueryValidatorVisitor keeps a source stack; no lockstep sibling.`
- `Tests/Linq/Linq/StringJoinTests.cs:419` JoinAggregateArrayNotNull expects this error on AllOracle11 — covered by E-3
- `Tests/Linq/Linq/StringConcatTests.cs:337` Concat_OverGrouping_DistinctNullableValues expects this error on AllOracle11 — covered by E-4
- `Tests/Linq/Linq/AssociationTests.cs:1506` Issue3557Case1-3, cited by the flag doc; Oracle 11 baseline uses LEFT JOIN + ROW_NUMBER, not a scalar subquery; must stay green — covered by E-1
- Oracle 11 baselines (`linq2db.baselines` `origin/master`, `Oracle.11.Managed`, 5104 files) can't serve as a census: baselines exist only for queries the current rule let through. The only column-position IS NOT NULL hit, `Issue1261Tests.TestLinqAll`, is a post-validation null companion (P1) — out-of-scope
- `Source/LinqToDB/Internal/SqlQuery/Visitors/SqlQueryValidatorVisitor.cs:VisitSqlFromClause` — the only direct reader of `CalculateSupportedCorrelatedLevelWithAggregateQueries` (searched `CalculateSupportedCorrelatedLevelWithAggregateQueries` across Source: setters DB2/Access/MySql, reader VisitSqlFromClause, flag Equals/GetHashCode). Through it, every `IsValidQuery` caller is affected: `SelectQueryOptimizerVisitor.cs:3747/3760/3802`, `BasicSqlOptimizer.cs:1196`, `ExpressionBuilder.SqlBuilder.cs:217`, `ExpressionBuilder.cs:297`. #5168 (`9cc8fae38`) introduced the aggregate exemption as the default; E-6 restores Oracle 11's pre-6.3.0 level accounting — covered by E-6
- `Tests/Linq/UserTests/Issue5256Tests.cs:73` `NestedSubqueryWithGroupedAggregationsFilteredSumOfSums` — the A-1 shape with no IS NOT NULL, excluded on AllOracle11; every flag-on provider expects `Error_OUTER_Joins`. `:31` `SumOfSums` is the only Oracle 11 baseline with an uncorrelated aggregate over a derived table in column position (critic census of 4516 Oracle.11.Managed baselines) — covered by E-7
- `Source/LinqToDB/PublicAPI/PublicAPI.Shipped.txt:12036` `SqlQueryValidatorVisitor.VisitSqlTableSource` override — fate decided by D-2 — covered by E-5
- Census U-3 result rows — the six firing tests (interim) — covered by E-2, E-3, E-4

## P8 Test obligations (M/L)

- TO-1 `AllAnyTests.Issue6024_RootAnyOwnIsNotNull` — root `Any` over a filtered source with own-table `IS NOT NULL` equals LINQ-to-objects on Oracle.11.Managed(+LinqService) — proof: red→green (measured red: "parent's IS NOT NULL")
- TO-2 `AllAnyTests.Issue6024_RootAllOwnIsNotNull` — root `All` variant — proof: red→green (measured red, same message)
- TO-3 `AllAnyTests.Issue6024_CorrelatedAnyOwnIsNotNull` — correlated `Any` in a projection whose own filter is `IS NOT NULL`; the correlated form of TO-1 — proof: red→green (measured red, same message)
- TO-4 `AllAnyTests.Issue6024_CorrelatedCountOwnIsNotNull` — correlated `Count` with own-table `IS NOT NULL` in the predicate — proof: red→green (measured red, same message)
- TO-5 `AllAnyTests.Issue6024_CorrelatedParentIsNotNull` — projection subquery whose `IS NOT NULL` is on the parent (`p.Value1 != null` inside `db.Child.Count(c => c.ParentID == p.ParentID && p.Value1 != null)`). The discriminating input is a predicate whose only field belongs to the parent row. `[ThrowsForProvider(LinqToDBException, AllOracle11, Error_ColumnSubqueryShouldNotContainParentIsNotNull)]`; other providers return the LINQ-to-objects result — proof: control (mutation: force `VisitIsNullPredicate`'s check to `false`; Oracle 11 stops throwing this error, so the expectation goes red). Also run through the census to observe `newFires=True` (U-8)
- TO-6 Full Tests.Linq on Oracle.11.Managed + LinqService, before vs after: no new failures; every census row with `newFires=False` maps to a test that passes after the fix — proof: characterization
- TO-7 `StringJoinTests.JoinAggregateArrayNotNull` on Oracle 11 after the fix — the attribute matches observed behaviour with a recorded reason — proof: characterization
- TO-8 `StringConcatTests.Concat_OverGrouping_DistinctNullableValues` on Oracle 11 after the fix — same as TO-7 — proof: characterization
- TO-10 (A-1) StringConcatTests, StringJoinTests, AllAnyTests, SubQueryTests and AssociationTests on Oracle.11.Managed + LinqService after the fix. No failure that the pre-fix full run (`test-6024-census.log`) shows as passed. TO-7 and TO-8 raise no ORA-00904 — proof: characterization (mutation for TO-7/TO-8: without E-6 they hit ORA-00904, measured)
- TO-11 (A-2) `Issue5256Tests` on Oracle.11.Managed + LinqService: `NestedSubqueryWithGroupedAggregationsFilteredSumOfSums` (previously excluded on Oracle 11) raises `Error_OUTER_Joins`, and `NestedSubqueryWithGroupedAggregationsSumOfSums` (uncorrelated inline view under an aggregate column subquery, the only existing exercise of the new level bump) still passes — proof: characterization
- TO-9 TO-1..TO-5 also pass on SQLite.MS, and on Oracle 12 if available; the change is flag-gated, so no SQL change is expected — proof: characterization

## P9 Verification gates

- G-01: pass (2026-10-11, uncommitted tree). Filtered local runs, net10.0 Debug:
  - TO-1 Issue6024_RootAnyOwnIsNotNull — red on master (`test-6024-red.log`: "parent's IS NOT NULL", Oracle.11.Managed + LinqService), green after the fix (`test-6024-final.log`).
  - TO-2 Issue6024_RootAllOwnIsNotNull — red→green, same logs.
  - TO-3 Issue6024_CorrelatedAnyOwnIsNotNull — red→green, same logs.
  - TO-4 Issue6024_CorrelatedCountOwnIsNotNull — red→green, same logs.
  - TO-5 Issue6024_CorrelatedParentIsNotNull — passes. Oracle 11 throws the expected error; the census showed `newFires=True`. Mutation run (check forced to false, `test-6024-mutation.log`): red on both contexts.
    - LinqService: the expected exception was not thrown, and the query ran successfully on Oracle 11.
    - Direct: `ORA-00942 "Child"` on plain, valid SQL (`SELECT p."ParentID", (SELECT COUNT(*) FROM "Child" c_1 WHERE c_1."ParentID" = p."ParentID" AND p."Value1" IS NOT NULL) FROM "Parent" p`). This is most likely a concurrent session using the shared Oracle 11 schema.
    - Side finding: this simple parent-IS-NOT-NULL shape executes on Oracle 11. The rule may be broader than the real limit, but that is out of scope (P3) and a follow-up candidate.
    - The mutation was reverted.
  - TO-6 — the local "before" is the full pre-fix run (only Issue6024 red plus 2 unrelated LinqService failures). The "after" breadth is CI's.
  - TO-7 JoinAggregateArrayNotNull — Oracle 11 `Error_OUTER_Joins` (`test-6024-a1.log`); the expectation was updated (E-3).
  - TO-8 Concat_OverGrouping_DistinctNullableValues — Oracle 11 `Error_OUTER_Joins`; the expectation was updated (E-4).
  - TO-9 — TO-1..TO-5 pass on SQLite.MS. Oracle 12 was not run (container stopped); the change is flag-gated to v11.
  - TO-10 — StringConcatTests, StringJoinTests, AllAnyTests, SubQueryTests and AssociationTests on Oracle.11.Managed + LinqService: 417 tests, the only failures being TO-7/TO-8 before their expectation update (`test-6024-a1.log`).
  - TO-11 Issue5256Tests on Oracle.11.Managed + LinqService (`test-6024-5256.log`): `FilteredSumOfSums` raises `Error_OUTER_Joins` (both contexts); `SumOfSums` passes (both contexts). 14/14 including SQLite.MS.
- G-02: skipped — `BaselinesPath` is not set in the worktree's UserDataProviders.json, so no local baselines were written. CI's baselines PR will carry new Oracle 11 baselines for TO-1..TO-4.
- G-03: pass — E-5 `*REMOVED*` line added for the deleted override. No new public members.
- G-05: pass — `dotnet build Source/LinqToDB -c Release -f netstandard2.0` and `-f net10.0`: 0 warnings, 0 errors.
- G-06 / G-07: pass — `git diff` touches only E-1..E-6. The census instrumentation was reverted with `git checkout` before implementing. No playground files.
- G-08: pass (local) — TO-1..TO-4 red→green on Oracle 11. The full Oracle 11 legs are pending CI.
- TO-6 breadth gate: the full Tests.Linq run on Oracle.11.Managed + LinqService is CI's (user rule: full runs only on CI); the local pre-fix census run serves as the "before" side

## P10 Adjudicated (M/L)

- If TO-7 or TO-8 (or any CI Oracle 11 leg) hits a runtime ORA-00904 after the fix: stop and bring it to the user. That is a real Oracle 11 limit the over-broad rule was hiding, and the remedy (widen D-1 to look through derived columns, or gate) is a design decision that needs a P11 amendment, not a silent `ThrowsForProvider(OracleException)`.

## P11 Amendments (M/L)

### A-1 — Oracle 11 counts correlation depth through aggregate subqueries (E-6)

- **trigger:** the P10 stop rule fired. After D-1, `JoinAggregateArrayNotNull` and `Concat_OverGrouping_DistinctNullableValues` hit runtime ORA-00904 on Oracle.11.Managed(+LinqService):
  - `ORA-00904: "T"."NullableValue": invalid identifier`
  - `ORA-00904: "G_2"."Key_1": invalid identifier`
  - Log: `.build/.agents/test-6024-green.log`.
- **mechanism:** both correlate to the outer row from inside a derived table nested in an aggregate column subquery (`(SELECT LISTAGG(...) FROM (SELECT DISTINCT ... WHERE g_2.Key_1 = e.GrpId ...) t1)`). Oracle 11 cannot resolve outer aliases inside an inline view.
  - The check meant for this is `SupportedCorrelatedSubqueriesLevel = 1` (`OracleDataProvider.cs:49`). `VisitSqlFromClause` skips the level bump for aggregation queries unless `CalculateSupportedCorrelatedLevelWithAggregateQueries` is set (`SqlQueryValidatorVisitor.cs` `VisitSqlFromClause`). DB2, Access and MySQL set it; Oracle does not.
  - The old IS NOT NULL rule caught these two shapes only through the own-table false positive.
- **change:** E-6 sets the flag for Oracle < 12. Oracle 12+ is unaffected, because `IsApplyJoinSupported` skips the level check there (`SqlQueryValidatorVisitor.cs:151-152`).
- **re-derives:**
  - SC-4: the expected outcome is now (b), a validator error or a fallback shape, with no ORA-00904.
  - TO-7 and TO-8: expectations are set from the observed post-A-1 behaviour.
  - New SC-6 → TO-10: Oracle 11 tests that use aggregate column subqueries and passed before the fix still pass. Local filtered fixtures: StringConcatTests, StringJoinTests, AllAnyTests, SubQueryTests, AssociationTests. Compared against the pre-fix full-run log `.build/.agents/test-6024-census.log`. Breadth is left to CI's Oracle 11 legs.
  - P7: new row for flag consumers. P9: G-01 widened to the TO-10 fixture set.
- **rejected:**
  - (a) Widen D-1 to look through derived columns. That is the wrong instrument: `Issue5256Tests.NestedSubqueryWithGroupedAggregationsFilteredSumOfSums` has the same failing shape with no IS NOT NULL at all.
  - (b) Expect `OracleException` in the two tests. That degrades a clean LinqToDB error into a server error.
- **approval:** user approved this approach on 2026-10-11. The critic re-ran on this delta: round 2, weak (see P12).

### A-2 — Issue5256 joins TO-10 (critic round 2)

- Adds E-7 and TO-11 for `Issue5256Tests`: the A-1 shape without IS NOT NULL, plus the uncorrelated `SumOfSums` control.
- **re-derives:** TO-10 (the fixture set gains `Issue5256Tests`), SC-6.

## P12 Critic verdict (M/L)

Round 1 (`plan-critic`, model fable): **weak**. Mechanism survives: boundary detection checked through `QueryElementVisitor.cs:474-482/1647-1655/2089-2094/2456-2472`; rejected alternative (b) confirmed dead; D-1 scope ⊇ master's `_currentSources` at every position, so the census is complete.

Objections and changes:
1. TO-5 couldn't prove what it claimed: on Oracle 11 the parent shape throws, so there is no `LastQuery`. → Rewritten as a `ThrowsForProvider` control with a mutation. U-8 added: observe `newFires=True` once.
2. P3 "no public API change" was contradicted by removing the shipped `VisitSqlTableSource` override. → D-2, U-9 and E-5 added. P3 reworded.
3. P1 provenance overclaimed: TO-4's shape was probably rejected since 6.0. → P1 is now per shape, plus a note on the post-validation null-companion phase.
4. SC-4's outcome set was open. → Three outcomes named; P10 stop rule for ORA-00904.
5. The P7 baseline row implied a census it can't be. → Reworded.
6. P9 was empty. → Gates listed; the breadth gate is CI's.

Round 2 (A-1 delta, `plan-critic`, model fable): **weak**. E-6 is at the right altitude: the flag is already set by DB2, Access and MySQL, and it restores the pre-#5168 accounting. The critic's independent trace (`SqlQueryValidatorVisitor.cs:152/298/433/462`, `QueryHelper.cs:121-166`, the optimizer loop order at `SelectQueryOptimizerVisitor.cs:239-300`, and a census of 4516 Oracle.11 baselines) found no Oracle 11 shape that executes today and that E-6 newly rejects.

Objections and changes:
1. TO-10 missed `Issue5256Tests` (the A-1 shape without IS NOT NULL, plus the uncorrelated control). → A-2, E-7, TO-11.
2. P3's fallback-machinery anti-goal contradicted A-1's mechanism. → P3 reworded; the P7 E-6 row now lists every `IsValidQuery` caller.
3. TO-7/TO-8 expectations were written before the measurement. → They were measured in `test-6024-a1.log` (`Provider does not support CROSS/OUTER/LATERAL joins.` on Oracle.11.Managed and LinqService), then the expectations were set.
4. A-1 had no rejected alternatives. → Added.

Searched by the critic (round 1): `IsColumnSubqueryShouldNotContainParentIsNotNull`, `IsValidQuery\(|ValidateSubqueries` (5 entry points), `_currentSources` in HEAD and the prototype, `QueryHelper.cs:121-166/1105-1169`, `git log -S` for flag provenance, `linq2db.baselines` Oracle.11/12 shapes, `PublicAPI.Shipped.txt` (18 `SqlQueryValidatorVisitor` entries), the CI `with_api_analyzers` gating.
