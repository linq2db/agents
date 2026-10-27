# Work plan: issue-6035-fix-correlated-distinct-count — Fall back to a sub-query for Distinct aggregates that COUNT(DISTINCT) cannot express

**Tier:** L  ·  **Status:** approved  ·  **Approved-at:** 2026-10-26  ·  **Branch:** issue/6035-fix-correlated-distinct-count
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

## P1 Problem

[#6035](https://github.com/linq2db/linq2db/issues/6035): a correlated sub-query in a projection ending in `Distinct()` plus an aggregate throws `ArgumentException: must be reducible node` at mapper compile time, after running `SELECT … FROM Parent` and a full `SELECT … FROM GrandChild` scan (eager-load fallback). Repro (SQLite.MS, master `c82e21c35`):

```csharp
from p in db.Parent
select new { p.ParentID, Cnt = db.GrandChild.Where(g => g.ParentID == p.ParentID).Select(g => new { g.ChildID }).Distinct().Count(x => x.ChildID != null) }
```

Measured on master (SQLite.MS, playground matrix): of the issue's 9 shapes only `Select(g => g.ChildID).Distinct().Count()` (→ `COUNT(DISTINCT ChildID)`) and the no-`Distinct` form pass; every shape `COUNT(DISTINCT x)` cannot express throws. Same root also reached by association (`p.Children.Select(new{..}).Distinct().Count()` → `InvalidOperationException: no method 'AggregateExecute'`), predicate (`where … .Distinct().Count(pred) > 0` → "could not be converted"), and grouped anonymous/entity `g.Select(new{..}).Distinct().Count()` / `g.Distinct().Count()` (→ `ArgumentException: Argument type … does not match`).

Two causes, both "untranslatable" where a sub-query fallback exists:

1. `ExpressionBuilder.BuildAggregationFunction` (`Source/LinqToDB/Internal/Linq/Builder/ExpressionBuilder.Aggregation.cs:647-653`): when `Distinct` is not the outermost chain call (a `Where`, or the `Where` that `TranslateCount` rewrites `Count(pred)` into at `AggregateFunctionsMemberTranslatorBase.cs:71-86`) it does `return null`; the disallowed-`Distinct` branch right above (`:638-645`) instead sets `buildRoot` and falls back to `AggregateExecute` over the `Distinct` sub-sequence.
2. `AggregateFunctionsMemberTranslatorBase.TranslateCount` (`:105-116`): `IsDistinct` with a value that is not a scalar (anonymous object, entity) → `SetError`, where `TranslateMinMaxSumAverage` (`:272-279`) uses `SetFallback(c => c.AllowDistinct(false))` for the analogous case.

Right SQL (measured with the probe fix, SQLite.MS): `SELECT p.ParentID, (SELECT COUNT(*) FROM (SELECT DISTINCT x.ChildID FROM GrandChild x WHERE x.ParentID = p.ParentID AND x.ChildID IS NOT NULL) t1) FROM Parent p`.

## P2 Success criteria

- SC-1 The issue's 9 correlated-projection shapes return the LINQ-to-objects result in one SQL statement on providers that support a correlated derived table (measured set: SQLite, SQL Server 2022, SqlCe, PostgreSQL 18, Firebird 2.5 / 5, Informix). → TO-1
- SC-2 The association, `Where`-predicate, `LongCount` and two-member anonymous shapes return the LINQ-to-objects result on the same set. → TO-2
- SC-3 Grouped anonymous / entity `Distinct().Count()` returns the LINQ-to-objects result on the same set. → TO-3
- SC-4 Grouped `g.Select(x).Distinct().Where(pred).Count()` keeps master's behaviour and SQL (eager load) on every provider, including Oracle 11 / MySQL 5.7 / DB2 where it works on master. → TO-4
- SC-5 On providers that cannot run the correlated derived table, the new shapes refuse with `LinqToDBException` "could not be converted to SQL" instead of crashing (Oracle 11, MySQL 5.7, MariaDB, DB2, Access measured). → TO-5
- SC-7 A correlated `string.Join` over `Distinct().Where(…)` returns the LINQ-to-objects result on PostgreSQL 18 and SQLite. → TO-7
- SC-6 Shapes that pass on master keep passing with unchanged SQL: scalar `Distinct().Count()` → `COUNT(DISTINCT)`, grouped `Distinct().Count(pred)` → `COUNT(DISTINCT CASE …)`, top-level `Select(new{..}).Distinct().Count(pred)`, `Distinct().OrderBy().Count()`, and the existing `GroupByTests` `*InGroup` / `DistinctTests` / `EagerLoadingTests.TestAggregate*` / `StringJoinTests` Distinct fixtures. → TO-6

## P3 Constraints & anti-goals (M/L)

- No public API change; no `SqlProviderFlags`, SQL AST or translator-interface change.
- Grouped aggregates (`contextRef.BuildContext is GroupByContext`) keep master's `return null` for a non-outermost `Distinct` (D-2).
- Plain/array-mode twin `BuildArrayAggregationFunction` (`ExpressionBuilder.Aggregation.cs:205-222`) is not changed (D-3).
- Anti-goals, filed separately: the eager-load mapper that leaves a `ContextRefExpression` in the client lambda (own issue + own PR, per user); `COUNT(DISTINCT x)` dropping NULL where LINQ `Distinct().Count()` counts it (own issue); Sybase validator letting a correlated derived table through (`SybaseDataProvider.cs:54` sets `SupportedCorrelatedSubqueriesLevel = 1` without `CalculateSupportedCorrelatedLevelWithAggregateQueries`; own issue).
- No change to nullable `Sum()` over an empty set returning `null` (pre-existing, measured on master without `Distinct`).

## P4 Unknowns (M/L)

- U-1 Does the fallback produce correct results, not just SQL? — resolved-by probe: 22 shapes × 12 providers compared against LINQ-to-objects (`TestTemplate.Variation` / `NeighbourShape`); all green on SQLite.MS, SqlServer.2022, SqlCe, PostgreSQL.18, Firebird.2.5, Firebird.5, Informix.DB2.
- U-2 Is the fallback route itself proven? — resolved-by probe: SqlCe (`IsCountDistinctSupported => false`, `SqlCeMemberTranslator.cs:363`) passes all 22 shapes on master already via the disallowed-`Distinct` branch, the route E-1 / E-2 open to every provider.
- U-3 Which shapes that pass on master could regress? — resolved-by probe: without D-2, grouped `Distinct().Where().Count()` regressed on Oracle.11.Managed / MySql.5.7 / DB2 (master: eager load, correct; fix: refused). With D-2, the failing set equals master's per provider on all 12 providers (Oracle 11 / MySQL 5.7 / DB2: 16, Sybase: 16, Access: 19, the rest: 0 with fix vs 15 on master).
- U-4 Sybase behaviour — resolved-by probe: master crashes (`must be reducible node`) on the same 16 shapes that, with the fix, reach ASE and fail with `AseException: The column prefix 'p' does not match …`; not a regression, a validator flag gap (P3 anti-goal).
- U-5 Providers not measured locally: ClickHouse, YDB, MariaDB, MySQL 8, Oracle 12+, SAP HANA, DuckDB, SQL Server 2005-2019 — resolved-by CI: the new tests run on `[DataSources]` with gates only where measured (TO-5); unmeasured reds are triaged from the test-all run, each new gate needs its measured failure.
- U-6 Does E-2 change the grouped COUNT path for a translatable scalar? — resolved-by probe: grouped `Distinct().Count(pred)` SQL identical master vs fix (`COUNT(DISTINCT CASE WHEN ChildID > 20 THEN ChildID ELSE NULL END)`); E-2 fires only when `TranslateExpression(info.ValueExpression)` fails.
- U-8 Does an association root eager-load on master like a group, so E-1 regresses it (critic lead)? — resolved-by probe: `p.Children.Select(c => c.ChildID).Distinct().Where(x => x > 20).Count()` throws `InvalidOperationException: no method 'AggregateExecute'` on master on SQLite.MS, PostgreSQL.18, Oracle.11.Managed, MySql.5.7, MariaDB.11; with the fix it passes on SQLite.MS / PostgreSQL.18 and refuses on the other three. No regression; D-2 stays scoped to `GroupByContext`.
- U-9 Grouped anonymous `g.Select(x => new { x.ChildID }).Distinct().Where(x => x.ChildID > 20).Count()` (critic lead: E-2 unreachable behind D-2's early return) — resolved-by probe: passes on master and with the fix on all five providers above (eager load, D-2).
- U-10 Correlated `string.Join(",", ….Distinct().Where(x => x != "11"))` (critic lead: StringJoin registrations with `AllowDistinct()` + `AllowFilter()`) — resolved-by probe: master passes on SQLite.MS only, throws "no method 'AggregateExecute'" on PostgreSQL.18 / MySql.5.7 / MariaDB.11, refuses on Oracle.11.Managed; with the fix it passes on SQLite.MS / PostgreSQL.18 and refuses on the other three. SQL Server 2017+ not measured (container down mid-run, not session-owned).
- U-11 HAVING `GroupBy(…).Where(g => g.Select(x => new { x.ChildID }).Distinct().Count() > 1)` (critic lead: E-2 opens an APPLY into the grouped query) — resolved-by probe: master refuses ("could not be converted") on all five; with the fix it returns the LINQ-to-objects keys on SQLite.MS / PostgreSQL.18 and refuses on Oracle.11.Managed / MySql.5.7 / MariaDB.11.
- U-12 Do the TO predicates separate on the shared fixture (critic)? — resolved-by scout + probe: `GrandChild` has no NULL `ChildID` (`Tests/Linq/Create/CreateData.cs:199-220`), so `!= null` predicates select every row; `ChildID > 20` separates (measured `CorrAnonDistinctCountSeparating`: master crash, fix = LINQ result).
- U-7 Is the `return null` a deliberate design choice? — resolved-by provenance: introduced in [#5168](https://github.com/linq2db/linq2db/pull/5168) (`9cc8fae38`, string.Join / DistinctBy) together with the identical plain-mode check; the aggregate-mode disallowed branch got a fallback, the not-outermost branch kept the plain-mode `return null`.

## P5 Decisions (M/L; rejected alternatives mandatory at L)

### D-1 — Not-outermost `Distinct` falls back to `AggregateExecute` over the `Distinct` sub-sequence

- **chosen:** at `ExpressionBuilder.Aggregation.cs:652`, `buildRoot = method; break;` — the same route as the disallowed-`Distinct` branch, so the aggregate runs as `COUNT(*)` over `SELECT DISTINCT …` with the outer filter applied to the sub-sequence.
- **rejected:** fold the post-`Distinct` filter into `COUNT(DISTINCT CASE WHEN pred THEN x END)` — valid only for a scalar value and a predicate over that value; anonymous values and multi-member keys still need the sub-query, so it is a second path, not a replacement.
- **rejected:** reorder `Distinct().Where(p)` into `Where(p).Distinct()` — only equivalent when `p` reads the distinct projection alone; adds a semantic rewrite for no shape the fallback does not already cover.
- **why this:** reuses an existing, already-exercised fallback (U-2); one-line change; result proven per provider (U-1).
- **failure mode of the choice:** providers whose validator refuses the correlated derived table now throw "could not be converted" for shapes that, on master, crashed or — for grouped shapes — worked via eager load; the grouped half is D-2.

### D-2 — Grouped aggregates keep master's `return null` (user-chosen option (a))

- **chosen:** guard D-1 with `contextRef.BuildContext is GroupByBuilder.GroupByContext → return null`, so a group keeps the eager-load fallback.
- **rejected:** apply D-1 to groups too — regresses grouped `Distinct().Where().Count()` on Oracle 11 / MySQL 5.7 / DB2 (U-3).
- **rejected:** apply D-1 to groups and make a refused `AggregateExecute` sub-query fall back to eager load — changes the `HandleSubquery` / `IsSupportedSubquery` decline mechanism shared by every sub-query; wider blast radius than the issue.
- **rejected:** gate D-1 on a provider capability flag in the builder — builder-level provider dispatch duplicates the validator.
- **why this:** zero regression across 12 measured providers; the correlated / association shapes, which crash on master everywhere, are fixed.
- **failure mode of the choice:** grouped `Distinct().Where().Count()` stays an eager load on providers that could run it server-side (SQLite, SQL Server, PostgreSQL); a performance gap, not a correctness one — measured for both the scalar (U-3) and the anonymous (U-9) value; E-2 never reaches the grouped not-outermost case because the guard returns first.

### D-3 — Plain/array-mode twin unchanged

- **chosen:** leave `BuildArrayAggregationFunction`'s `return null` (`:212`, `:221`).
- **rejected:** mirror D-1 — plain mode has no `AggregateExecute` fallback at all (scout: it returns null at `:137 … :300`, ignores `FallbackExpression` at `:303-311`), so the mirror would be new machinery, not a parity fix.
- **why this:** the two `return null` sites are consistent within plain mode; aggregate mode was the inconsistent one.
- **failure mode of the choice:** `string.Join` over a correlated `Distinct().Where()` stays unsupported, as on master.

### D-4 — Untranslatable `Distinct` value falls back instead of erroring

- **chosen:** `TranslateCount` `IsDistinct` + `TranslateExpression` failure → `composer.SetFallback(c => c.AllowDistinct(false))`, which re-runs the chain walk with `Distinct` disallowed → D-1's sibling branch → `AggregateExecute`.
- **rejected:** translate an anonymous single-member value as its member (`COUNT(DISTINCT ChildID)`) — does not cover multi-member keys or entities, and widens the NULL-semantics gap (P3).
- **why this:** mirrors `TranslateMinMaxSumAverage` (`:277`); covers anonymous, multi-member and entity values in one place, grouped included (grouped anonymous/entity crashes on master on every provider, U-3).
- **failure mode of the choice:** any other `TranslateExpression` failure under `IsDistinct` (a genuinely untranslatable scalar) now takes the sub-query route and surfaces the inner failure there instead of at the aggregate; the error text may differ.

## P6 Edit-points

- E-1 `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuilder.Aggregation.cs:BuildAggregationFunction` — not-outermost `Distinct`: grouped → `return null` (unchanged), otherwise `buildRoot = method; break;` (D-1, D-2).
- E-2 `Source/LinqToDB/Internal/DataProvider/Translation/AggregateFunctionsMemberTranslatorBase.cs:TranslateCount` — `IsDistinct` value translation failure → `SetFallback(c => c.AllowDistinct(false))` instead of `SetError` (D-4).
- E-3 `Tests/Linq/Linq/DistinctTests.cs:DistinctTests` — new regression tests (P8), on the shared `Parent` / `Child` / `GrandChild` model.

## P7 Impact map (M/L)

- `ExpressionBuilder.Aggregation.cs:497 BuildAggregationFunction` callers — searched `BuildAggregationFunction\(` across the worktree: only `AggregateFunctionBuilder.cs:93` (`Build`) and `:333` (`Combine` fallback) via `ExpressionBuildVisitor.cs:6059`; a non-null `AggregateExecute` result is returned through `FromFallback` (`AggregateFunctionBuilder.cs:350`) and rebuilt by `AggregateExecuteBuilder.cs:71-76` — covered by E-1
- Aggregate-mode registrations reaching E-1 — searched `ConfigureAggregate|AllowDistinct\(`: Count/LongCount (`AggregateFunctionsMemberTranslatorBase.cs:56`), Sum/Avg/Min/Max (`:228`), percentile / hypothetical-set (`WindowFunctionsMemberTranslator.cs:1063`, `:1283`, Distinct never allowed), provider `TranslateStringJoin` aggregate configs (ClickHouse `:312`, YDB `:160`, MySQL `:275`, PostgreSQL `:378`, DuckDB `:233`, Firebird `:286`, SqlServer2017 `:45`, DB2 `:317`, SQLite `:284`, SapHana `:332`, Oracle `:358`) — the ones that allow `Distinct` (SQLite's StringJoin config `SQLiteMemberTranslator.cs:284` does not) now get the fallback for a non-outermost `Distinct` on a non-grouped root — covered by E-1 (Sum probed: TO-2; correlated StringJoin probed: U-10, TO-7; grouped `StringJoinTests` forms unchanged by D-2)
- `BuildArrayAggregationFunction` plain-mode twin `ExpressionBuilder.Aggregation.cs:205-222` — searched `BuildArrayAggregationFunction\(`: sole caller `AggregateFunctionBuilder.cs:63` — out-of-scope (D-3)
- `TranslateCount` callers — searched `TranslateCount\b`: registrations `AggregateFunctionsMemberTranslatorBase.cs:27-35` only (Count / LongCount, IEnumerable + IQueryable); `WindowFunctionsMemberTranslator.TranslateCount` is a separate method — covered by E-2
- `IsCountDistinctSupported` overrides — searched `IsCountDistinctSupported`: Access `AccessMemberTranslator.cs:452`, SqlCe `SqlCeMemberTranslator.cs:363` (false; already on the fallback route) — covered by E-2 (no behaviour change for them: Distinct already disallowed)
- Existing tests on the touched paths — searched `Distinct\(\)\s*\.\s*(Count|LongCount|Sum|Average|Min|Max|Where)\(` + multiline variants across `Tests/`: `GroupByTests.cs:869,901,938,966,994,1022`, `DistinctTests.cs:88,107,395`, `EagerLoadingTests.cs:1238,1271`, `Issue2662Tests.cs:35`, `MicrosoftODataTests.cs:234,281`, `StringJoinTests.cs:107,285,391,422`, `StringConcatTests.cs:338`; none puts `Where`/`Count(pred)` after `Distinct` on a non-grouped root, none uses an anonymous `Distinct` value — covered by E-3 (TO-6 runs them)
- Provider validator for correlated derived tables — searched `SupportedCorrelatedSubqueriesLevel|CalculateSupportedCorrelatedLevelWithAggregateQueries|IsApplyJoinSupported\s*=` under `Internal/DataProvider`: Oracle `:49-50`, DB2 `:41-42`, MySQL `:54-55`, Access `:58-59` count aggregate levels and refuse (TO-5); Sybase `:54` does not (P3 anti-goal) — out-of-scope
- Gated tests for the refusing providers on this mechanism — searched `ThrowsRequiresCorrelatedSubquery|ThrowsRequiredOuterJoins|Error_OUTER_Joins` in `DistinctTests.cs`, `GroupByTests.cs`, `EagerLoadingTests.cs`: gates on Access / Oracle11 / MySql57 / DB2 / Sybase / Informix / MariaDB stay (D-2 leaves grouped paths unchanged; the correlated `EagerLoadingTests.TestAggregate*` keep `Distinct` outermost) — out-of-scope
- Remote (`LinqService`) — no serialized shape or contract touched (no AST / flags change); remote cases run in TO-1..TO-6 via `[DataSources]` — covered by E-3

## P8 Test obligations (M/L)

Conventions embedded: `testing.md` → *Test layout* (one call per line, query syntax for joins, `AssertQuery` where it applies — scalar `Count` results and navigation aggregates use `AreEqual` with a stated reason), *A narrowed provider set is a claim* (every exclusion/gate below has a measured failure), *Gating an assertion failure* (gate messages from a local raw-message run). Test names describe behaviour; issue URL only in `[Test(Description = …)]`.

Separating predicates: every `Where` / `Count(pred)` after `Distinct` uses `ChildID > 20` (or `ParentID > 2`), never `!= null` — the fixture has no NULL `ChildID` (U-12), so a mutant dropping the post-`Distinct` filter (`allowedBody` → `null` in `BuildAggregateExecuteExpression`) must turn each such cell red; the issue's literal `!= null` repro stays as one cell of TO-1.

- TO-1 Correlated projection `Select(new{..}).Distinct().Count(x => x.ChildID > 20)` / `Count()` / `Where(x => x.ChildID > 20).Count()`, scalar `Distinct().Count(x => x > 20)` / `Where(x => x > 20).Count()`, two-member anonymous, plus the issue's literal repro; discriminating input: master crashes `must be reducible node` on SQLite.MS — providers: `[DataSources]` — proof: red→green
- TO-2 Association `p.Children.Select(new{..}).Distinct().Count()`, `.Select(c => c.ChildID).Distinct().Count(x => x > 20)` and `.Distinct().Where(x => x > 20).Count()`, `Where`-predicate `… .Distinct().Count(x => x.ChildID > 20) > 0`, correlated `LongCount`, correlated `Distinct().Where(x => x > 20).Sum()` over `ChildID ?? 0`; discriminating input: master throws (`no method 'AggregateExecute'` / "could not be converted" / `must be reducible node`) on SQLite.MS — providers: `[DataSources]` — proof: red→green
- TO-3 Grouped `g.Select(x => new { x.ChildID }).Distinct().Count()`, `g.Distinct().Count()`, and the HAVING form `GroupBy(…).Where(g => g.Select(x => new { x.ChildID }).Distinct().Count() > 1)`; discriminating input: master `ArgumentException: Argument type … does not match` / "could not be converted" on SQLite.MS — providers: `[DataSources]` — proof: red→green
- TO-4 Grouped `g.Select(x => x.ChildID).Distinct().Where(x => x > 20).Count()` and the anonymous variant return the LINQ result on Oracle 11 / MySQL 5.7 / DB2 / MariaDB; mutation that turns it red: drop E-1's GroupByContext guard (measured: refused on Oracle.11.Managed / MySql.5.7 / DB2) — providers: `[DataSources]` — proof: control
- TO-5 Refusal gates on TO-1..TO-3 and TO-7: the `LinqToDBException` "could not be converted to SQL" form (attribute and message pinned from a local raw-message run) for Access, Oracle 11, MySQL 5.7, MariaDB, DB2 — all measured; Sybase `[ActiveIssue]` on the Sybase validator issue with `ErrorTypeName = "AdoNetCore.AseClient.AseException"`; YDB / ClickHouse / others only after a measured CI failure — providers: Access, Oracle11, MySql57, MariaDB, DB2, Sybase — proof: characterization
- TO-7 Correlated `string.Join(",", db.Child.Where(c => c.ParentID == p.ParentID).Select(c => c.ChildID.ToString()).Distinct().Where(x => x != "11"))`, order-insensitive comparison; discriminating input: master throws "no method 'AggregateExecute'" on PostgreSQL.18 — providers: `[DataSources]` — proof: red→green
- TO-6 Unchanged path: scalar correlated `Distinct().Count()` keeps `COUNT(DISTINCT …)` (SQL asserted), plus the existing fixtures in P7 run green on SQLite.MS, SqlServer.2022, PostgreSQL.18 with no baseline change — providers: SQLite.MS, SqlServer.2022, PostgreSQL.18 — proof: characterization

## P9 Verification gates

Note: the first gate's run is the combined `X` + `X.LinqService` run with `BaselinesPath` set, so the remote-vs-direct baselines check fires.

- G-01: pass — `worktree-test.ps1 Tests/Linq net10.0 -Filter DistinctTests -PerProvider` on SQLite.MS, PostgreSQL.18, SqlCe, Access.Ace.OleDb, Oracle.11.Managed, MySql.5.7, MariaDB.11, DB2, Informix.DB2, Sybase.Managed, Firebird.2.5, Firebird.5, ClickHouse.Driver, YDB (direct + `.LinqService`, `BaselinesPath` set): all green after three gate corrections (Access runs and Sybase passes the `string.Join` shape; Access refuses grouped `Distinct().Where().Count()` on master too; the SQL assertion reads `ToSqlQuery()`); red arm with E-1/E-2 reverted: SQLite.MS 18, PostgreSQL.18 20, Oracle.11.Managed 14 failures, each with the master exception from P1; TO-4 control mutation (guard disabled) red on Oracle.11.Managed / MySql.5.7 with "could not be converted", green on SQLite.MS. Tests per obligation — TO-1: `DistinctCountOfAnonymousInCorrelatedSubquery`, `DistinctCountWithPredicateInCorrelatedSubquery`, `DistinctCountAfterWhereInCorrelatedSubquery`, `DistinctCountOfMultiMemberAnonymousInCorrelatedSubquery`; TO-2: `DistinctCountOverAssociation`, `DistinctCountInCorrelatedPredicate`, `DistinctSumAfterWhereInCorrelatedSubquery` (LongCount in `DistinctCountOfMultiMemberAnonymousInCorrelatedSubquery`); TO-3: `DistinctCountOfAnonymousInGroup`, `DistinctCountOfAnonymousInHaving`; TO-4: `DistinctCountAfterWhereInGroup`; TO-5: the `ThrowsCannotBeConverted` / `ThrowsRequiresCorrelatedSubquery` / `[ActiveIssue(6166)]` attributes on the TO-1..TO-3 / TO-7 tests, each satisfied on its provider in the 14-provider run (a declared throw that does not happen fails the test); TO-6: `DistinctCountOfScalarInCorrelatedSubquery` (green on master and branch, gates re-measured on 10 providers after A-1) plus the G-08 characterization fixtures; TO-7: `DistinctStringJoinAfterWhereInCorrelatedSubquery`
- G-02: pass — baselines PR linq2db.baselines#2223: 665 files, all `added`, every one under `DistinctTests.<one of the 12 new methods>`; no existing baseline modified or deleted (filtered `status != added` or path outside `DistinctTests.` → empty). CI on `a40ebdc68`: `tests [oracle.all]`, `tests [postgresql.all]`, `tests [sqlserver.all]` and Azure `test-sqlserver` 24781 green; GH run 40393593813 (on `c11c8b28a`) green except the two legs since gated (#6173, #6175)
- G-05: pass — `dotnet build Source/LinqToDB/LinqToDB.csproj -c Release -f netstandard2.0`: 0 warnings, 0 errors
- G-06: pass — `git diff -- Source` is the two E-1 / E-2 hunks only (19 lines)
- G-07: pass — `Tests/Tests.Playground/TestTemplate.cs` restored with `git restore`; `git status` shows only the two E-1 / E-2 files and `DistinctTests.cs`
- G-08: pass — `Source/LinqToDB` and `Tests/Linq` Release net10.0 builds: 0 warnings, 0 errors; TO-6 characterization `GroupByTests` `*InGroup`, `EagerLoadingTests.TestAggregate*`, `StringJoinTests`, `StringConcatTests`, `Issue2662Tests`, `MicrosoftODataTests`, `AggregationTests`, `CountTests` on SQLite.MS 282 / PostgreSQL.18 278 / Oracle.11.Managed 258 / SqlCe 242 — 0 failures
- G-09: pass — `/code-review high` on the working-tree diff: 10 candidates. Probed or settled from existing measurements: association / grouped-anonymous / `AggregateRootContext` / StringJoin-gate / root-cause candidates (U-8, U-9, U-3, the 14-provider `DistinctTests` run); "discarding the translation error reroutes client-only Distinct values" — probed master vs fix: correlated and grouped `Select(g => IsBig(g.ChildID)).Distinct().Count()` fail on master on SQLite.MS / PostgreSQL.18 / Oracle.11.Managed and pass with the fix on the first two; "uncorrelated / top-level shapes change SQL" — top-level `Distinct().Where().Sum()` / `Count()` SQL identical master vs fix, uncorrelated projection `Distinct().Where().Count()` fails on master everywhere and passes with the fix. Accepted: the `COUNT(DISTINCT` pin (A-1) and the "on master" comment. Declined: merging the two `buildRoot = method; break;` branches (style)

## P10 Adjudicated (M/L)

- Grouped `Distinct().Where().Count()` stays an eager load on providers that could run it server-side — D-2, user's choice (a); measured regression of the alternative on Oracle 11 / MySQL 5.7 / DB2 (U-3).
- Sybase fails the new shapes with an ASE server error instead of a linq2db refusal — the validator flag gap is filed separately (P3); master crashes the same shapes (U-4).
- Nullable `Sum()` over an empty correlated set returns `null` — pre-existing convention, measured on master without `Distinct`.
- Oracle 12 returns wrong counts (not a refusal) for grouped anonymous / entity `Distinct().Count()` — #6175, user's option (a): gated, fix deferred to that issue; master crashed on the same shapes, and grouped `Take` / `Skip` already return wrong values there.

## P11 Amendments (M/L)

- A-1 (2026-10-26, pre-PR code review) — TO-6's SQL assertion (`COUNT(DISTINCT`) is dropped: it pins the translation [#6165](https://github.com/linq2db/linq2db/issues/6165) reports as wrong for nullable values. The scalar test becomes `DistinctCountOfScalarInCorrelatedSubquery` on `[DataSources]` (characterization of the unchanged path, gates measured), and the grouped-guard comment loses its branch-relative "on master". No edit-point changes; the approval stands.
  re-derives: P8 (TO-6)
  conventions: (see A-2)
- A-2 (2026-10-27, first CI round) — TO-5 gains two measured gates, each a pre-existing defect reproduced on master's own path and filed: `DistinctStringJoinAfterWhereInCorrelatedSubquery` `[ActiveIssue(6173, AllPostgreSQL93Minus)]` (the PostgreSQL `string.Join` translator emits `FILTER` on 9.2/9.3; grouped `string.Join` over a filtered group fails the same way on master), and `DistinctCountOfAnonymousInGroup` / `DistinctCountOfAnonymousInHaving` `[ActiveIssue(6175, AllOracle12)]` (Oracle 12 evaluates a correlated derived table under a grouping sub-query as uncorrelated; grouped `Take` / `Skip` aggregates return the same wrong values on master). Both gates verified locally (PostgreSQL.9.2, Oracle.12.Managed, direct + remote) and on CI. No edit-point changes.
  re-derives: P8 (TO-5), P10
  conventions: `testing.md` → *Test layout*, *A narrowed provider set is a claim*, *Gating an assertion failure*; swept `git diff origin/master -- Tests/` (one file, `Tests/Linq/Linq/DistinctTests.cs`, every new chain one call per line, every narrowed set carries a measured gate)

## P12 Critic verdict (M/L)

**weak** — plan-critic on `fable` (2026-10-26, round 1; fable did not contribute to the design). Searched: `BuildAggregationFunction\(|BuildArrayAggregationFunction\(`, `ConfigureAggregate\(|AllowDistinct\(`, `IsAllowedAggregationMethodName` (found a second chain walker `TranslationContextExtensions.GetAggregationInfo` `:187-279` with its own Distinct-first rule — no callers, not a live mirror), `GroupByContext` in `ExpressionBuilder.Aggregation.cs`, `IsCountDistinctSupported|IsAggregationDistinctSupported`, the correlated-level flags, test sweeps for `Distinct()` + `Where`/aggregate and association `Distinct` aggregates, `new SqlEagerLoadExpression\(`.

Objections and disposition (each probed, master vs fix):

- Association root regresses like a group (lead) — disproved by measurement, U-8: master throws on every provider; no regression; D-2 unchanged.
- TO predicates cannot separate — accepted: P8 now uses `> 20` predicates (U-12); `!= null` kept only for the issue's literal repro.
- MariaDB missing from TO-5 — accepted: measured refusal on MariaDB.11, added to SC-5 / TO-5.
- D-2 failure-mode line wrong for anonymous grouped values (lead) — disproved by measurement, U-9: works via eager on master and with the fix.
- StringJoin row justified by a property (lead) — accepted: probed (U-10), now an improvement on PostgreSQL.18, TO-7 added; P7 row corrected (SQLite StringJoin has no `AllowDistinct()`).
- HAVING opens an APPLY into the grouped query (lead) — probed, U-11: master refuses everywhere; fix returns the correct keys on SQLite.MS / PostgreSQL.18, refuses elsewhere; covered in TO-3.
- G-01 must be the combined direct + remote run with baselines — accepted into P9.

Not re-dispatched: every objection was settled by a measurement rather than by argument, and none changed an edit-point.
