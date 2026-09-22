# Work plan: feature-1475-pivot-unpivot — drop native PIVOT/UNPIVOT emission and the static IPivotBuilder API

**Tier:** L  ·  **Status:** draft  ·  **Approved-at:** —  ·  **Branch:** feature/1475-pivot-unpivot
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

## P1 Problem

PR #5708 delivers PIVOT/UNPIVOT twice: once as native SQL emission behind a `SqlPivotTable`/`SqlUnpivotTable` AST,
and once as a portable lowering to `GROUP BY` + conditional aggregation / `UNION ALL`. The native half is
~1345 lines and is *all* of the PR's cross-cutting core surface. It buys nothing measurable and costs capability.

**Measured, this session** — both SQL shapes executed directly, median of 7 after 2 warm-ups, each side verified
to take the path it stands for, results asserted identical:

| Operator | Workload | Engine | Native | Portable | Native is |
|---|---|---|---|---|---|
| PIVOT | 1M rows → 100 groups, one `SUM`, 8 values | DuckDB | 68.0 ms | 39.6 ms | 1.72× slower |
| PIVOT | same | SQL Server 2017 | 1183.5 ms | 1243.5 ms | 1.05× faster |
| PIVOT | same | Oracle 23 | 521.9 ms | 402.4 ms | 1.30× slower |
| UNPIVOT | 200k rows × 8 cols → 1.6M values, `SUM` | DuckDB | 39.0 ms | 7.0 ms | 5.57× slower |
| UNPIVOT | same | SQL Server 2017 | 123.9 ms | 166.2 ms | 1.34× faster |
| UNPIVOT | same | Oracle 23 | 103.5 ms | 95.8 ms | 1.08× slower |

The keyword wins one cell of six. An earlier `COUNT(*)` version of the UNPIVOT run reported 5.0× / 1.15× and was
discarded: a count lets the optimizer satisfy the `UNION ALL` side per branch without producing values, so the two
sides were not doing the same work. Switching to `SUM(v)` moved SQL Server from 53.5/61.7 ms to 123.9/166.2 ms.

**The static `IPivotBuilder` API is an alias.** Measured on SQLite, `t.Pivot(p => new { p.Key.Category, Y2000 =
p.Sum(x => x.Amount, x => x.Year, 2000), … })` and
`t.GroupBy(x => x.Category).Select(g => new { Category = g.Key, Y2000 = g.Sum(x => x.Year == 2000 ? x.Amount : null), … })`
emit **byte-identical SQL** (probe printed `SHAPE-SQL-EQUAL True`) and return identical rows.

**The native path also caps the public API.** `PivotBuilder` reaches native only when all of: the provider flag is
set; there is exactly one distinct aggregate; the FOR side is one column (or the provider does multi-column); the
source resolves to a plain table; and the value selector is a **bare member access** — `TryGetSimpleMemberName`
returns null for anything computed. Because the emitter must write a SQL aggregate function *name*,
`PivotAggregate` is a closed enum of five and `PivotCell` exposes one factory per member. Anything outside that
intersection silently falls back, so the restriction buys no guarantee — it only narrows what users may write.

## P2 Success criteria

- SC-1 Every result currently asserted by `PivotTests`, `PivotDynamicTests` and `SelectDynamicTests` still holds, on SQLite + DuckDB + SQL Server + Oracle, direct and `LinqService`. → TO-1
- SC-2 The PR adds no SQL AST node, no `QueryElementType`/`SqlTableType` member, no `QueryElementVisitor` method, no `LinqServiceSerializer` case and no `SqlProviderFlags` member. → TO-2
- SC-3 A pivot cell can carry an aggregate outside `{Sum, Min, Max, Avg, Count}` — e.g. a distinct count or a string aggregate — and produce correct values. → TO-3
- SC-4 The six static-API test scenarios survive against the dynamic API, including the two shapes the dynamic API has no coverage for today (`Avg`/`Min`/`Max` cells, composing `Where`/`Select` after a pivot). → TO-4
- SC-5 `Tests/Linq` compiles for net462 and the Release net10.0 analyzer/XML-doc leg is clean. → TO-5
- SC-6 A filtered aggregate (`g.Where(p).Sum(s)`) emits parseable SQL on PostgreSQL 9.2/9.3, where master emits an unparseable `FILTER` clause. → TO-7, TO-8
- SC-7 An empty cell over a **non-nullable** value column still materializes `null`, not `default(T)`. → TO-9
- SC-8 A multi-value `Unpivot` keeps all-NULL rows on Oracle and DuckDB, matching its documented contract. → TO-10

## P3 Constraints & anti-goals (M/L)

- **No query result may change.** Every difference is in emitted SQL, never in rows.
- `Unpivot`'s public surface stays whole: both selector overloads, both multi-value overloads, both name-array overloads, and `UnpivotNulls`.
- The dynamic API stays: `SelectDynamic`, both `Pivot` overload pairs, `PivotRow<TKey>`, `PivotCellFactory`, `SelectDynamicBuilder`.
- No edit to `PublicAPI.Shipped.txt` and no `CompatibilitySuppressions.xml` entry — every affected API line is in `Unshipped`.
- **Anti-goal: do not re-plumb the dynamic API onto native PIVOT.** That was step 8 of the prior plan; the measurements above retire it.
- **Anti-goal: do not touch the window-function filtered-aggregate machinery.** `WindowFunctionsMemberTranslator.IsWindowFilterSupported` is a distinct concept from the grouped-aggregate `IsFilterSupported` this plan relies on.
- `Tests/Linq` must build for **net462**; `Enumerable.Append` is unavailable there (cost one red CI leg this session).

## P4 Unknowns (M/L)

- U-1 Does deleting `QueryElementType.SqlPivotTable`/`SqlUnpivotTable` shift the remote wire ids of other elements? — resolved-by scout: **no**. `LinqServiceSerializer` has no version stamp and writes `(int)e.ElementType`, so ordinals are load-bearing — but these two are values 84/85, the last members, parked there by an explicit in-code comment for exactly this reason. Ids 0–83 are untouched, and the deserializer's default arm throws a named error if an old peer sends 84/85.
- U-2 Is `SqlProviderFlags` a wire contract, so that removing four members breaks remote clients? — resolved-by scout: it **is** a `[DataContract]` inside `LinqServiceInfo` over WCF/gRPC/HttpClient/SignalR, but `[DataMember(Order = …)]` values are explicit and the four flags are 80–83, the highest. Removal frees those tags and shifts nothing; an old client against a new server reads `DefaultValue(false)`, which is the correct post-removal semantics.
- U-3 Does anything read `SqlTableType.Pivot`/`Unpivot`? — resolved-by scout: **no**. Written by the two node overrides, read nowhere; every other `SqlTableType` consumer tests `Table`/`SystemTable`/`Expression`/`Function` with a default arm.
- U-4 Is there a builder registry to update when `PivotBuilder` is deleted? — resolved-by scout: **no**. `BuildersGenerator` source-generates the dispatch from `[BuildsMethodCall]`; the generated `case "Pivot":` disappears with the file.
- U-5 Does `aggregate(g.Where(pred))` translate, or is the conditional-selector form the only supported shape? — resolved-by scout: it is a **first-class, already-modelled concept**. `Where` is accepted by `IsAllowedAggregationMethodName`, collected into `AggregationContext.FilterExpressions`, AND-ed in `AggregateFunctionBuilder`, and emitted as native `FILTER (WHERE …)` where `IsFilterSupported` (PostgreSQL only) or `SUM(CASE WHEN … THEN v ELSE NULL END)` everywhere else. Covered by `GroupByTests.SumInGroup`/`MinInGroup`/`MaxInGroup`/`AverageInGroup`/`CountInGroup` and `Aggregates4`, including HAVING position and `let`-bound filtered groupings.
- U-6 Does the design need `LinqExtensions.AggregateExecute` (whose signature is exactly the sketched one)? — resolved-by scout + design: **no**, and deliberately not. Its grouping branch (`AggregateExecuteBuilder.cs:27-36`) has no test exercising it from the public API. The design inlines the user's lambda over `g.Where(pred)` instead, which lands on the tested filtered-aggregate path.
- U-7 Does moving the five named cells from `agg(g, row => cond ? v : null)` to `agg(g.Where(cond))` change emitted SQL? — resolved-by scout: **yes, on two axes.** PostgreSQL gets a real `FILTER (WHERE …)`; `COUNT` becomes `COUNT(*) FILTER (…)` rather than `COUNT(CASE WHEN … THEN 1 END)`. Same results, different SQL ⇒ baseline churn. Adjudicated in P10.
- U-8 What does a user see when a custom aggregate body cannot be translated? — resolved-by scout: `[ActiveIssue(5787)]` — it surfaces as `InvalidOperationException: There is no method 'AggregateExecute' …` rather than a clean `LinqToDBException`. Pre-existing, inherited, not fixed here. Adjudicated in P10.
- U-9 Does the filtered form change **results** as well as SQL? — resolved-by probe (this session, SQLite): `g.Sum(x => cond ? (int?)x.V : null)` and `g.Where(cond).Sum(x => x.V)` emit **byte-identical SQL** (`SUM(CASE WHEN … ELSE NULL END)`), but materialize `null` vs `0` for an empty group. The divergence is entirely client-side, driven by the declared CLR type — the server returns NULL either way. So the nullability lift is load-bearing for **both** forms. Drives D-4.
- U-10 Is `FILTER (WHERE …)` faster than `CASE WHEN` on PostgreSQL? — **unmeasured**, and no claim of a speedup may appear in the PR body or release notes without one — resolved-by decision: D-3 and D-5 rest on one mechanism plus the defect fix, never on performance, so the answer cannot change the design.
- U-11 Do `pgsql92` / `pgsql93` start locally for verification? — resolved-by inspection: both exist but exited with status 255 weeks ago, so they may not. TO-7/TO-8 record `blocked` naming PostgreSQL 9.2/9.3 as locally unverified if so, and CI's PostgreSQL legs carry the gate instead. The gate's correctness does not depend on local containers.
- U-12 Does the native multi-value `Unpivot` path differ from the fallback in **rows**, not just SQL? — resolved-by critic, cited: `UnpivotBuilder.cs:110` builds the native node with `includeNulls: false` (EXCLUDE NULLS drops rows whose measures are all NULL) while the fallback filters nothing, and the XML doc promises "NULL rows are kept". Removing native therefore *corrects* a documented-contract violation on Oracle and DuckDB, at the cost of changed rows for all-NULL groups. Drives SC-8 / TO-10.

## P5 Decisions (M/L; rejected alternatives mandatory at L)

### D-1 — Remove native emission outright rather than gating it

- **chosen:** delete the AST nodes, the visitor methods, the serializer cases, the builder emission, the provider flags and both `TryBuildNative` paths.
- **rejected:** keep native behind an opt-in `DataOptions` switch — the 1345 lines and the whole cross-cutting surface survive, which is precisely the cost being removed; and P1 says the default would have to be *off* on two of three engines, so the switch would ship dead.
- **rejected:** keep native for SQL Server only (its one measured win, UNPIVOT 1.34×) — a per-provider fork of the emission path costs the same AST and serializer surface for one cell of a six-cell table.
- **why this:** the surface is the cost, not the emission; nothing short of deleting the nodes removes it.
- **failure mode of the choice:** if a provider later gains a genuinely faster PIVOT, restoring it is fresh work, not a revert — there will be no flag left to flip.

### D-2 — Remove the static `IPivotBuilder` API

- **chosen:** delete `IPivotBuilder`, `LinqExtensions.Pivot.cs` and `PivotBuilder.cs` entirely; document `GroupBy` + a ternary as the compile-time-shape spelling.
- **rejected:** keep it as sugar over the lowering — P1 measured its SQL as byte-identical to the hand-written form, so it is an alias that costs a public interface plus a 511-line builder, and it caps the aggregate vocabulary at five.
- **why this:** keep only what a user cannot write themselves. The runtime-shaped case genuinely cannot be hand-written — that is what `SelectDynamic` is for. The compile-time case already has an idiomatic spelling that ships today.
- **failure mode of the choice:** discoverability. Someone searching for "pivot" loses an entry point — mitigated because the dynamic `Pivot` keeps the name, and by the doc note in E-20.

### D-3 — `PivotCell` carries an arbitrary aggregate; the five named factories become wrappers

> **Superseded in part by A-13:** the arbitrary aggregate stays and becomes the *only* form — the five wrappers and
> the static-form overload pair are deleted.

- **chosen:** `PivotCell<TSource,TFor>.Custom<TCell>(Expression<Func<IEnumerable<TSource>, TCell>> aggregate, Func<TFor,string>? name = null)`, desugaring to `aggregate(g.Where(row => forColumn(row) == value))`. `Sum`/`Min`/`Max`/`Avg`/`Count` are kept as wrappers building the same shape, so there is one mechanism and five conveniences. `PivotAggregate` is deleted. **Requires D-5.**
- **rejected:** keep the enum and add `Custom` beside it (critic round 1's suggested repair) — it avoids all churn and all shared-engine risk, but the new capability then ships with a provider-shaped hole: `Custom` emits an unparseable `FILTER` clause on PostgreSQL < 9.4 while the five named cells work there. Shipping a capability that works on every provider is worth more than avoiding the churn.
- **rejected:** take the aggregate as `Expression<Func<IEnumerable<TCell>, TResult>>` over the projected values — it cannot express `Count()` over rows, or any aggregate reading more than one column.
- **why this:** U-5 establishes the filtered form is first-class and tested; it makes named and custom cells identical in mechanism; it lifts the five-function cap that existed only to feed the native emitter; and with D-5 the five base aggregates have no provider hole.
- **narrowed after critic round 2:** "no provider hole" holds for the five base aggregates only. `PostgreSQLMemberTranslator.StringMemberTranslator.TranslateStringJoin:423-435` passes `filter:` **unconditionally** — it is a different nested class and never consults `IsFilterSupported` — so a `Custom` cell whose body is a string aggregate still emits `STRING_AGG(…) FILTER (WHERE …)` on 9.2/9.3 after D-5. Recorded in P10; extending the tier split to `StringMemberTranslator` is out of scope here and belongs to the same follow-up PR as D-5.
- **failure mode of the choice:** U-7's baseline churn is unavoidable, and on PostgreSQL ≥ 9.4 the emitted SQL changes shape. If D-5's gate is wrong, every filtered aggregate on old PostgreSQL is affected, not just pivots.

### D-4 — The nullability lift survives, and extends to `Custom`

> **Superseded in part by A-13:** the lift survives, but there is now one mechanism (the result lift), not three.

- **chosen:** keep `MakeNullable`; the five wrappers lift the aggregated value to `TCell?` as today, and `Custom` lifts its **result** type when `TCell` is a non-nullable value type.
- **rejected:** drop the lift because `agg(g.Where(…))` is "the same shape" — U-9 probed this and it is false. The SQL is identical and the *materialization* differs: an empty cell over a non-nullable column reads `0` / `0001-01-01` instead of `null`, because `ConvertFromDataReaderExpression` maps `DBNull` through `GetDefaultValue(type)`.
- **why this:** P3 forbids result changes, and a cell with no matching rows reading `0` is silently wrong data rather than a visible failure.
- **failure mode of the choice:** a user whose custom aggregate legitimately returns a non-nullable value (`Count()`) now gets `int?`; the wrappers must special-case `Count` exactly as today.

### D-5 — Version-gate `IsFilterSupported`, proven in this branch, ported out before merge

- **chosen:** gate at the **9.5 tier, which is the only boundary this codebase can express.** `PostgreSQLVersion` has `v92, v93, v95, v11, …` and no `v94`, and `PostgreSQLProviderDetector.cs:131-132` maps `{Major: 9, Minor: > 4} => v95`, `{Major: 9, Minor: > 2} => v93` — so a real 9.4 server is detected as `v93` and takes the base translator. Concretely: flip `PostgreSQLMemberTranslator.cs:370` `IsFilterSupported` to `false` (**keep** the override — `PublicAPI.Shipped.txt:10411` tracks it and P3 forbids a Shipped edit), and have `PostgreSQL95MemberTranslator` override `CreateAggregateFunctionsMemberTranslator()` with a nested subclass returning `true`. **No `PostgreSQLDataProvider` edit** — `>= v95 => PostgreSQL95MemberTranslator` already exists. This is the boundary the codebase already uses for the same feature: `PostgreSQL95WindowFunctionsMemberTranslator.IsWindowFilterSupported => true`. Implement it **in this branch first** to prove the whole change works end to end, then port it to its own PR and rebase this branch onto it before merge.
- **consequence, stated rather than discovered:** a genuine PostgreSQL 9.4 server takes the `CASE WHEN` emulation, because the detector cannot distinguish it from 9.3. Conservative and correct; adding a `v94` member is a separate, larger change (enum member + detector arm + provider instance) and is not in scope.
- **rejected:** land the gate as a separate PR first and block this work on it — the user's call was to prove it here rather than serialize on an unmerged dependency.
- **rejected:** no gate (accept a PG 9.2/9.3 regression) — knowingly shipping unparseable SQL for a provider still in the test matrix.
- **tracked as [#5948](https://github.com/linq2db/linq2db/issues/5948)** (Bug, 6.6.0) — filed separately because it is a product defect with a standalone observable effect; this plan's D-5 is its fix, proven here and ported there.
- **why this:** the gate is a **live defect on master**, not a cost of this feature: `PostgreSQLMemberTranslator` returns `IsFilterSupported => true` unconditionally and `PostgreSQLDataProvider` hands every version below 9.5 that same translator, so any filtered aggregate on 9.2/9.3 emits SQL the server cannot parse today. The 25 `AllPostgreSQL93Minus` exclusions in `GroupByTests`, each commented `// PostgreSQL 9.4+ (FILTER clause)`, are that defect papered over.
- **failure mode of the choice:** the gate ships inside a pivot PR if the port is forgotten, which buries a shared-engine fix where nobody reviewing pivots will look for it. The port is a release-blocking item, not a nicety.

## P6 Edit-points

- E-1 `Source/LinqToDB/Internal/SqlQuery/SqlPivotTable.cs`, `SqlPivotTableBase.cs`, `SqlPivotValue.cs`, `SqlPivotAggregate.cs`, `SqlUnpivotTable.cs`, `SqlUnpivotItem.cs` — delete all six.
- E-2 `Source/LinqToDB/Internal/SqlQuery/QueryElementType.cs:140-144` — remove `SqlPivotTable`, `SqlUnpivotTable` and the wire-compat TODO comment that exists only for them.
- E-3 `Source/LinqToDB/Internal/SqlQuery/SqlTableType.cs:17-18` — remove `Pivot`, `Unpivot`.
- E-4 `Source/LinqToDB/Internal/SqlQuery/Visitors/QueryElementVisitor.cs:738-925` — remove `VisitSqlUnpivotTable`, `VisitSqlPivotTable`.
- E-5 `Source/LinqToDB/Internal/Remote/LinqServiceSerializer.cs:738-748,1669-1726,3005-3084` — remove both visitor overrides, both serialize cases, both deserialize cases.
- E-6 `Source/LinqToDB/Internal/SqlProvider/BasicSqlBuilder.cs:2093-2103,2114-2248` — remove the two `BuildPhysicalTable` cases and `BuildUnpivotTable`/`BuildPivotTable`/`BuildPivotInValue`.
- E-7 `Source/LinqToDB/Internal/DataProvider/SqlServer/SqlServerSqlBuilder.cs:496-503` — remove the `BuildPivotInValue` override.
- E-8 `Source/LinqToDB/Internal/SqlProvider/SqlProviderFlags.cs:723-751,884-887,972-975` — remove the four members with their XML docs and their `GetHashCode`/`Equals` arms.
- E-9 `Source/LinqToDB/Internal/DataProvider/{DuckDB/DuckDBDataProvider.cs:44-48, Oracle/OracleDataProvider.cs:60-65, SqlServer/SqlServerDataProvider.cs:92-95}` — remove the flag wiring and its comments.
- E-10 `Source/LinqToDB/Internal/Linq/Builder/UnpivotBuilder.cs` — remove `TryBuildMultiValueNative`, the whole `Native` region, `ResolveSourceField`, and the native gates at `:35` and `:72`; the lowering regions stay.
- E-11 `Source/LinqToDB/Internal/Linq/Builder/PivotBuilder.cs` — delete the file.
- E-12 `Source/LinqToDB/LinqExtensions/IPivotBuilder.cs`, `LinqExtensions.Pivot.cs` — delete both.
- E-13 `Source/LinqToDB/LinqExtensions/PivotAggregate.cs` — delete.
- E-14 `Source/LinqToDB/LinqExtensions/PivotCell.cs` — replace the enum-carrying shape with an aggregate `LambdaExpression`; add `Custom`, keep `Sum`/`Min`/`Max`/`Avg`/`Count` as wrappers.
- E-15 `Source/LinqToDB/LinqExtensions/PivotCellFactory.cs` — mirror E-14's surface.
- E-16 `Source/LinqToDB/LinqExtensions/LinqExtensions.PivotDynamic.cs:126-203` — rewrite `BuildCell` to `aggregate(g.Where(row => forColumn(row) == value))`; delete `GetAggregate` and `MakeNullable`.
- E-17 `Source/LinqToDB/PublicAPI/PublicAPI.Unshipped.txt` — remove lines 3-9, 10-51, **55-72**, **76-79**, 80-81 and 73; add the new `PivotCell`/`PivotCellFactory` members **and the nested translator + `CreateAggregateFunctionsMemberTranslator` override from E-21** (nested protected translators are tracked — see `PublicAPI.Shipped.txt:3195-3196,10383`). **Lines 2, 52-54, 74-75 and 82-83 must survive**: `UnpivotNulls` and all four `Unpivot` overloads, which P3 keeps. The blanket "remove by hunk" note does **not** apply to this file — the branch is add-only, so the whole file is one hunk and reverting it would wipe the surviving entries too.
- E-18 `Tests/Linq/Linq/PivotTests.cs` — port the six static-Pivot tests onto the dynamic API; delete `UnpivotEmitsNativeKeyword`, `UnpivotAliasedColumnEmitsNativeKeyword`, `UnpivotUnmappedColumnEmitsNativeKeyword` and every native-vs-fallback SQL assertion. **`CategorySales`/`RegionSales`/`QuarterAmounts` move with the tests that use them** — the composite-key and composite-FOR ports need them and `PivotDynamicTests` has no equivalent fixture, so they are relocated, not deleted.
- E-19 `Tests/Linq/Linq/PivotDynamicTests.cs` — add the custom-aggregate tests (TO-3).
- E-20 `Source/LinqToDB/LinqExtensions/LinqExtensions.PivotDynamic.cs` — XML-doc note on both `Pivot` overload families pointing the compile-time-known shape at `GroupBy` + a conditional aggregate.
- E-21 `Source/LinqToDB/Internal/DataProvider/PostgreSQL/Translation/PostgreSQLMemberTranslator.cs` + a versioned subclass + `PostgreSQLDataProvider.cs:105-110` — `IsFilterSupported` false below 9.4, true from 9.4 (D-5). **Ported to its own PR before merge.**
- E-22 `Source/LinqToDB/LinqExtensions/LinqExtensions.Unpivot.cs:21-25,92-93,167,191,216-217` — XML docs promise native `UNPIVOT` on SQL Server/Oracle/DuckDB and, for the multi-value overloads, both "every provider" and "NULL rows are kept". Rewrite to match post-removal behaviour. Same class: `UnpivotBuilder.cs:301-302` (the physical-name rationale outlives the native path that motivated it), and the native-keyword prose in `PivotTests.cs` / `PivotDynamicTests.cs`.
- E-23 `Tests/Linq/Linq/{PivotPerfScratch.cs, PivotShapeScratch.cs, UnpivotPerfScratch.cs}` — delete. Untracked, but compiled by the SDK glob and written against the static API, so they break the build the moment E-12 lands.

> **Line numbers above are indicative only.** Remove by `git diff -U0 origin/master...HEAD` hunk, never by the ranges written here — the critic found every range off by 1–3, one of which would have orphaned an XML doc comment into `CS1587` under `TreatWarningsAsErrors`. The branch is **add-only against master** (33 files, zero deletions), so E-1…E-9 are exactly "revert these hunks".

## P7 Impact map (M/L)

- `SqlPivotTable|SqlPivotTableBase|SqlPivotValue|SqlPivotAggregate|SqlUnpivotTable|SqlUnpivotItem` across the whole worktree — 124 hits in 13 files, **all under `Source/LinqToDB`**; zero in `Tests/`, zero in `*.tt`, zero in `*.md`, zero in `CompatibilitySuppressions.xml` — covered by E-1…E-7, E-10, E-11, E-17
- `QueryElementType\.Sql(Un)?[Pp]ivotTable` repo-wide — 8 sites: the two node overrides, 2 in `BasicSqlBuilder`, 4 in `LinqServiceSerializer` — covered by E-2, E-5, E-6
- `Dictionary<QueryElementType|HashSet<QueryElementType|QueryElementType\[\]|Enum\.GetValues|typeof\(QueryElementType\)` repo-wide — **zero matches**; no lookup-table dispatch and no reflective enumeration exists, so no silent-default site — out-of-scope
- `QueryHelper.GetDbDataTypeImpl` (type-keyed value mapping, 15 arms) and `SqlQueryColumnNestingCorrector.GetVisitMode` (~20 `QueryElementType` members) — **neither lists a pivot kind**; the native nodes were never wired into either. Deletion-neutral, and evidence the native path was under-integrated — out-of-scope
- `SqlTableType\.(Un)?[Pp]ivot` repo-wide — written at 2 sites, read at **none**; all other `SqlTableType` consumers have a default arm — covered by E-3
- `IsPivotSupported|IsMultiColumnPivotSupported|IsUnpivotSupported|IsMultiValueUnpivotSupported` repo-wide — 17 lines in 7 files: 4 declarations, 4 `GetHashCode` arms, 4 `Equals` arms, 3 provider setters, 3 consumer gates; **no test asserts them** (`RemoteContextTests.TestFlagsTransfered` names a hand-picked set and does not enumerate reflectively) — covered by E-8, E-9, E-10
- `[DataMember(Order` in `SqlProviderFlags.cs` + `LinqServiceInfo` consumers across WCF/gRPC/HttpClient/SignalR — orders 80-83 are the highest; removal frees tags without renumbering, old peers get `DefaultValue(false)` — covered by E-8, verified by TO-6
- `IPivotBuilder` repo-wide — 14 hits in 5 files: the interface, 3 in `LinqExtensions.Pivot.cs` (incl. 2 XML-doc crefs), 3 marker checks in `PivotBuilder.cs`, 7 `PublicAPI.Unshipped` lines, 1 scratch comment — covered by E-12, E-17
- `\.Pivot\s*[<(]` repo-wide, each hit classified static-vs-dynamic — 7 static call sites in `PivotTests.cs` across 6 tests (`:302`, `:337`, `:360`, `:380`, `:416`, `:464`, `:497`); the rest are dynamic and stay — covered by E-18
- `ParseAggregates|AggregateSpec|PivotValueSpec|FormatPivotValue|PivotContext` repo-wide — 17 hits, **all inside `PivotBuilder.cs`** — covered by E-11
- `BuildsMethodCall` over `Source` — 74 files, each carrying its own attribute; dispatch is source-generated by `BuildersGenerator`, no hand-maintained list — no registry edit needed, out-of-scope
- `BuildPivotTable|BuildUnpivotTable|BuildPivotInValue` repo-wide — 3 `protected virtual` in `BasicSqlBuilder`, exactly 1 override anywhere (`SqlServerSqlBuilder`); DuckDB and Oracle have no pivot builder code — covered by E-6, E-7
- `SqlSourceBase` repo-wide — `SqlPivotTableBase` and `SqlTableLikeSource` derive from it; it is **shipped** API and stays valid with one derived type left — out-of-scope
- `IsFilterSupported|IsCountDistinctSupported` across `Source` — `IsFilterSupported` overridden **only** by `PostgreSQLMemberTranslator:370`; everyone else takes the `CASE WHEN` emulation, which is why the existing filtered-group tests run on all providers — covered by E-21
- `g\.Where\(` across `Tests/Linq/` — 48 hits; the filtered-aggregate-over-grouping cluster is `GroupByTests.cs:787-1046` plus HAVING-position at `:1291-1346` — precedent for D-3, out-of-scope
- Provider exclusions on those existing filtered-group tests — Access throws `Error_OUTER_Joins`, `TestProvName.AllPostgreSQL93Minus` excluded everywhere, ClickHouse excluded from `Aggregates4`, `MinInGroup`/`MaxInGroup` need `UseGuardGrouping(false)` — covered by TO-3 (mirror them) and TO-8 (the PostgreSQL half becomes removable). Access's attribution is **unconfirmed**: `SumInGroup`/`CountInGroup` mix `Distinct()` into the same projection and Access has `IsAggregationDistinctSupported => false`, so its error may be the Distinct emulation rather than the filter — deferred: mirror the PostgreSQL and ClickHouse exclusions on TO-3, and probe `g.Where(p).Sum(v)` without `Distinct` before mirroring the Access one
- `IsFilterSupported` / `PostgreSQLDataProvider` version dispatch — `PostgreSQLMemberTranslator:42-45,370` returns true unconditionally; `PostgreSQLDataProvider.cs:105-110` gives every version below 9.5 that same base translator; the 9.5/11/13/18/19 subclasses override only **window** translators. So no version gate exists on the grouped-aggregate path — covered by E-21
- Prose consumers a symbol grep cannot see — `LinqExtensions.Unpivot.cs:21-25,92-93,167,191,216-217` (public XML docs promising native `UNPIVOT` and, for multi-value, both "every provider" and "NULL rows are kept"), `UnpivotBuilder.cs:301-302`, `PivotTests.cs:84-89,132-135,228-231,580-584`, `PivotDynamicTests.cs:365-368` — covered by E-22
- `includeNulls` on the native multi-value path — `UnpivotBuilder.cs:110` passes `false`; the fallback at `:79-98` filters nothing; the doc promises NULLs are kept. Removing native changes rows on Oracle and DuckDB, toward the documented contract — covered by E-10
- `WindowFunctionsMemberTranslator.IsWindowFilterSupported` / `IsOrderedSetFilterSupported` — a **distinct** filtered-aggregate concept with its own provider matrix (native on PostgreSQL and DuckDB); not the flag E-21 touches — out-of-scope, and named here so a reviewer does not conflate them

## P8 Test obligations (M/L)

- TO-1 `PivotTests` + `PivotDynamicTests` + `SelectDynamicTests` green on SQLite, DuckDB, SQL Server, Oracle, direct and `LinqService`. — proof: characterization; proves no new behaviour, which is the whole claim of D-1 and D-2. Discriminating input: the existing per-group cell values, which differ per provider only if the lowering is wrong.
- TO-2 A census, not a test: `git diff` against the merge base adds zero lines to `QueryElementType.cs`, `SqlTableType.cs`, `QueryElementVisitor.cs`, `LinqServiceSerializer.cs`, `SqlProviderFlags.cs` and `Internal/SqlQuery/*`. — proof: control; the mutation that turns it red is leaving any one E-1…E-9 unapplied.
- TO-3 A pivot cell carrying `rows => rows.Select(x => x.Amount).Distinct().Count()`. — proof: red→green; red today because `PivotAggregate` cannot express it. Discriminating input: a group whose distinct count differs from its row count (duplicate amounts within one pivoted value), so a plain `Count()` cannot pass by accident. Mirror `IsCountDistinctSupported => false` on Access and SQL CE, and the `AllPostgreSQL93Minus` / Access exclusions from P7. **The string-aggregate half is cut**: no test anywhere applies `StringAggregate` to a `g.Where(…)` inside a grouping — the two `.Where().StringAggregate()` hits in the corpus are correlated subqueries — so it would have been an obligation resting on an unexercised path. If a second aggregate is wanted, probe it first.
- TO-4 The six ported scenarios, one test each: basic shape, multi-aggregate, `Avg`/`Min`/`Max` cells, composite grouping key, composite FOR values, composing `Where`/`Select` after the pivot. — proof: **characterization, all six.** The earlier red→green label was wrong: `PivotDynamicTests` already composes `.Where` over a generated cell (`:297`, `:397`) and already exercises `Max`, and the dynamic API already supports `Avg`/`Min` — they were merely uncovered, not unsupported. Composite FOR is separately verified working (probe: `WHEN [Year] = @Year AND [Half] = @Half`, values 10/20 and 5/15).
- TO-5 `dotnet build Tests/Linq/Tests.csproj -c Debug -f net462` and `-c Release -f net10.0` both clean, **after E-23 deletes the scratch files**. — proof: control; the mutation is any BCL API newer than net462, which is how this branch already broke CI once.
- TO-6 A static census, not a run: `git diff origin/master...HEAD -- '*SqlProviderFlags.cs'` shows exactly four `[DataMember(Order = …)]` removals and no surviving member renumbered. — proof: control on U-2. The earlier form (LinqService legs pass) could not fail for the reason it named: both peers are the same build, so a renumbering would be symmetric and the round-trip would stay green.
- TO-7 A filtered aggregate over a grouping executes on PostgreSQL 9.2 and 9.3. — proof: red→green on the gate (D-5); red on master because the engine emits an unparseable `FILTER`. Records `blocked` naming those versions as locally unverified if `pgsql92`/`pgsql93` will not start (U-11), with CI's PostgreSQL legs as the covering run.
- TO-8 The `AllPostgreSQL93Minus` exclusions are removed from the **22** `GroupByTests` rows annotated `// PostgreSQL 9.4+ (FILTER clause)` and they pass. — proof: control; the mutation is reverting the gate, which turns those 22 red again. **Not 25**: `GroupByDate3:2037`, `Issue3761Test1:2727` and `Issue3761Test2:2752` are excluded for `make_timestamp` (and GROUPING SETS), which the gate never touches — un-excluding them would leave them red for an unrelated reason. The defect's full footprint is **37 FILTER-annotated exclusions across 5 files** (`GroupByTests` 22, `CountTests` 11, `BooleanTests` 1, `Issue1564Tests` 1, `StringJoinTests` 2); drive the wider sweep from the comment grep, not the file list, and leave the two `StringJoinTests` rows excluded — they route through the ungated `TranslateStringJoin` (see D-3's narrowing).
- TO-9 A pivot whose value column is a **non-nullable** `int` (and one a `DateTime`) reads `null`, not `0` / `0001-01-01`, for a group with no matching rows — asserted **once per lift mechanism**: a named `Sum` cell (selector lift, `Sum(x => (int?)x.V)` — today's proven path) *and* a `Custom` cell over the same column (result lift, `Convert(agg(g.Where(…)), int?)`). — proof: red→green against a build with D-4's lift removed. Discriminating input: exactly the empty cell; every existing fixture uses `decimal?`/`string?` and is structurally blind to it. **The two arms are not interchangeable**: the wrappers can only lift the selector and `Custom` can only lift the result, nothing in `Tests/Linq` exercises a result-lift over an aggregate today, and the `COALESCE` rewriter that might have masked it is `!IsGroupBy`-gated — so the `Custom` arm is the one carrying no prior evidence.
- TO-10 A multi-value `Unpivot` over a row whose measures are all NULL returns that row on Oracle and DuckDB. — proof: red→green; red on master, where the native path's `includeNulls: false` drops it. Discriminating input: a fixture row with every measure NULL — `MonthlySales.Data` has none, so it must be added.

## P9 Verification gates

All nine derived from P6 by `work-plan.ps1 -Action gates`. Re-recorded 2026-09-21 as E-1…E-21 landed; the
work is **uncommitted** in `C:\Worktrees\linq2db\5708-pivot-unpivot`.

- G-01: **pass** — TO-1 green on SQLite + DuckDB + SQL Server 2017 + Oracle 19, direct and `LinqService` (101 pivot/
  `SelectDynamic` tests; 39 each on SQL Server and Oracle). All four red→green obligations were observed
  red first: TO-3 (the distinct-count cell is inexpressible before D-3), TO-7 (`42601: syntax error at or near "("`
  on `COUNT(*) FILTER` against a real 9.2 server), TO-9 (both arms, each failing at its own assertion — `0` for the
  selector lift, `0001-01-01` for the result lift), TO-10 (native `UNPIVOT … EXCLUDE NULLS` returns 1 row where the
  lowering returns 2, proven in a detached probe worktree at the branch head). TO-2 and TO-6 pass in their strongest
  form: `git diff origin/master` over `Internal/SqlQuery`, `LinqServiceSerializer.cs`, `SqlProviderFlags.cs`,
  `BasicSqlBuilder.cs` and the three provider files is **empty** — byte-identical to master, so there is nothing to
  count.
  **Local env note:** `Oracle.23.Managed` is an `AzureConnectionStrings` name; `LocalConnectionStrings` carries only
  Oracle 11 and 19, and a worktree under `C:\Worktrees\` resolves no `UserDataProviders.json` by walk-up, so a local
  Oracle run there must use `Oracle.19.Managed`.
- G-02: **not run** — no local baselines diff; the `.sql` churn lands on the baselines PR at CI push. Expected wide
  per P10; read for shape.
- G-03: **pass** — `dotnet build Source/LinqToDB/LinqToDB.csproj -c Release -f net10.0 -p:RunApiAnalyzersDuringBuild=true`
  exits 0 with no RS0016/RS0017. The first run reported 58 RS0016 and 0 RS0017, which also established that the
  branch had **never** declared the dynamic API's surface (`PivotCell`, `PivotCellFactory`, `PivotRow`,
  `SelectDynamic`, all four `Pivot` overloads) nor two `Unpivot(…, params string[])` overloads — a pre-existing gap,
  not one E-17 created. `Unshipped` is now 42 lines and matches the code.
- G-04: **pass** — `git status` over 34 changed files shows no `PublicAPI.Shipped.txt` and no
  `CompatibilitySuppressions.xml` entry.
- G-05: **pass** — `Tests/Linq` builds clean for net462 and for Release net10.0 (the leg that validates XML doc
  `cref`s repo-wide), and `Source/LinqToDB` builds clean for netstandard2.0.
- G-06: **pass, after two repairs — both self-inflicted by whole-file writes, neither visible in a compile.**
  (1) The TO-8 sweep script wrote with `Set-Content -Encoding utf8NoBOM` and stripped the UTF-8 BOM from all three
  swept files, turning a 34-line change into a whole-file diff; fixed with `utf8BOM`. (2) `PivotTests.cs`,
  `PivotCell.cs` and `UnpivotBuilder.cs` — the three files rewritten wholesale — came out with bare **LF** endings in
  a CRLF repo; converted. The two repairs pull in opposite directions, so the convention is worth stating: the
  branch's own files (`PivotDynamicTests.cs`, `PivotRow.cs`, `SelectDynamicBuilder.cs`) are **CRLF, no BOM**, while
  older files like `GroupByTests.cs` / `BooleanTests.cs` are **CRLF with BOM** — match the file you are editing, not
  a repo-wide rule. `git diff --check origin/master` is now silent.
- G-07: **n/a** — the three scratch files E-23 names are not present in this worktree; they were session scratch in
  the worktree that produced the measurements, which no longer exists.
- G-08: **pass, and stronger than planned** — U-11 was wrong: `pgsql92` and `pgsql93` both start. The gate is verified
  in *both* directions: 9.2/9.3 take the `CASE WHEN` emulation and pass all **777** tests across `GroupByTests` +
  `CountTests` + `BooleanTests`, while PostgreSQL 19 still emits real `COUNT(*) FILTER (WHERE …)` and
  `COUNT(DISTINCT …) FILTER (WHERE …)`. So the tier split is correct, not merely conservative.
- G-09: **pass** — independent `code-reviewer` read on a different model, over the committed diff. `checked-clean` on
  all four priority areas with cited evidence; seven findings, none above MIN, all applied. See A-7.

## P10 Adjudicated (M/L)

- **Baseline churn is expected and is not a defect.** D-3 moves every cell from `agg(g, row => cond ? v : null)` to `agg(g.Where(cond))`. Results are identical; SQL is not — PostgreSQL gains a real `FILTER (WHERE …)` and `COUNT` becomes `COUNT(*) FILTER (…)` instead of `COUNT(CASE WHEN … THEN 1 END)`. Reviewers should expect a wide `.sql` diff on the baselines PR and read it for *shape*, not size.
- **The confusing error for an untranslatable custom aggregate is inherited, not introduced.** `[ActiveIssue(5787)]`: an aggregate body that cannot be translated inside a projection surfaces as `InvalidOperationException: There is no method 'AggregateExecute' …`. D-3 widens the set of user-supplied aggregates, so more users can reach it; fixing #5787 is out of scope here.
- **`GetDbDataTypeImpl` and `SqlQueryColumnNestingCorrector.GetVisitMode` never knew about the pivot nodes.** Found while scouting; moot once the nodes are deleted. Not a finding against this PR.
- **Native emission is not coming back behind a flag.** D-1's rejected alternatives are adjudicated, not open questions; re-raising "could we keep it for SQL Server" needs new measurements against P1's table.
- **`UnpivotMulti` returning all-NULL rows on Oracle/DuckDB is a fix, not a regression.** The native path dropped them via `includeNulls: false` while the XML doc promised they were kept; removing native makes the documented contract true. TO-10 pins it.
- **No performance claim is made for the filtered form.** U-10 is explicitly unmeasured. D-3/D-5 rest on one mechanism plus a defect fix; a speedup assertion must not appear in the PR body or release notes without a measurement.
- **`Custom` with a string-aggregate body remains broken on PostgreSQL 9.2/9.3 after D-5.** `TranslateStringJoin` emits `filter:` from a nested class the gate does not reach. Accepted for this PR; extending the 9.5 tier split to `StringMemberTranslator` belongs to the same follow-up PR that carries D-5 out of this branch. Users hitting it get a server syntax error, not a named exception — that is the cost of the acceptance.
- **The gate living in this branch is temporary and deliberate.** D-5 is implemented here to prove the change end to end, then ported to its own PR before merge. A reviewer seeing a PostgreSQL translator change inside a pivot PR is seeing the intended interim state, not scope creep — but the port is release-blocking.

## P11 Amendments (M/L)

- **A-1 (2026-09-21) — the `StringMemberTranslator` hole is 3 sites, not 2.** TO-8 counted
  `Issue1564Tests.CteTest1564` among the 35 sweepable rows because it carries the `// PostgreSQL 9.4+ (FILTER clause)`
  annotation. It is not sweepable: widening it to `AllPostgreSQL` fails on 9.2/9.3 with `42601`, because the query
  emits `STRING_AGG(…) FILTER (WHERE …)` through `TranslateStringJoin` — the ungated nested class D-3's narrowing
  already records. It belongs with the two `StringJoinTests` rows, so the follow-up PR that extends the 9.5 tier split
  to `StringMemberTranslator` un-excludes **three** tests. The site keeps its 9.5+ restriction with a comment naming
  the real mechanism. Swept total is therefore **34**, not 35.
- **A-2 (2026-09-21) — E-16's "delete `MakeNullable`" is superseded by D-4.** E-16 predates D-4; the lift is
  load-bearing on both arms (TO-9 proved each separately). `MakeNullable` stays, moved into `PivotCell` alongside the
  wrappers that use it.
- **A-3 (2026-09-21) — `Count` loses its value selector.** With the filter moved into `g.Where(…)`, the old
  `Count<TCell>(Expression<Func<TSource,TCell>> value, …)` selector is unused. The wrapper is now
  `Count(Func<TFor,string>? name = null)` on both `PivotCell` and `PivotCellFactory`. No call site outside the deleted
  static API used it.
- **A-4 (2026-09-21) — D-5's conservative arm catches more than "a genuine 9.4 server".**
  `PostgreSQLProviderDetector.cs:10` passes `PostgreSQLVersion.v92` as `DefaultVersion`, used when auto-detection is
  off (`:98`), when `DetectServerVersion` returns null (`:108`), and as the fallback arm (`:133`). Any such context
  emitted `FILTER` before this change — valid on whatever server it was actually talking to, which in practice is
  modern — and now takes the `CASE WHEN` emulation. Results identical, direction safe, but it is a SQL-shape change
  for a population D-5 describes only as a 9.4 server. Carry one sentence into #5948's description. Whether
  `DefaultVersion` should stay pinned at the oldest dialect is a separate decision, out of scope here.
- **A-5 (2026-09-21) — the two `Unpivot` families now have opposite NULL defaults, and only one has a knob.**
  The selector overloads exclude NULL cells with `UnpivotNulls` to opt in (`LinqExtensions.Unpivot.cs:21-23`); the
  tuple-group overloads keep them and take no `nulls` parameter (`:164`, `:188`). Both are documented and P3 freezes
  the surface, so this is not a defect — but the asymmetry existed because the native multi-value path forced
  `includeNulls: false`, and that path is gone. A follow-up adding `nulls` to the multi-value overloads would make
  the family symmetric.
- **A-6 (2026-09-21) — the pivot/unpivot tests run on every provider.** The `[IncludeDataSources(…)]` lists were an
  artifact of the native-versus-lowered split: tests were pinned to the providers with a native keyword so the
  SQL-text assertions meant something. Everything is translated SQL now, so the result-asserting tests are bare
  `[DataSources]` with **no exclusions** — a provider that cannot do it must surface as a real failure, not a
  pre-emptive gate. Nine stay narrow for non-provider reasons: two assert SQL text, five are call-site guards that
  throw before any SQL is built, and the rest are query-cache tests plus one embedding literal `FromSql` text.
  Supersedes the reviewer's narrower suggestion to add PostgreSQL only.
- **A-7 (2026-09-21) — G-09 ran and found nothing material.** An independent `code-reviewer` pass on a different
  model returned `checked-clean` on all four priority areas: the reflection-based `Enumerable` overload picks are
  unique on net462..net10.0 and identical to the pre-change bindings; the nullability lift cannot double-apply or
  miss, and both SQL-side paths that could re-inject a default are `!IsGroupBy`-gated; the deletions left no dangling
  reference anywhere under `Source/` or `Tests/`; and `PostgreSQL95AggregateFunctionsMemberTranslator` is reached by
  every `>= v95` dialect with no leaf re-overriding it. Seven findings, all MIN or below, all applied: a wrong type
  name in an exception, a missing `Custom`-over-`Sum` pin, two hand-rolled reflection scans replaced by
  `Methods.Enumerable`, and three prose corrections. The review is the source of A-4 and A-5.
- **A-8 (2026-09-21) — TO-3's Access attribution was wrong, and the real mechanism is the lateral join.** TO-3
  said to mirror `IsCountDistinctSupported => false` on Access *and SQL CE*. CI refutes both halves:
  `PivotsWithACustomAggregate` fails on all four Access configs with `LinqToDBException` /
  *"Provider does not support CROSS/OUTER/LATERAL joins"* — the distinct-count cell lowers to a lateral subquery —
  while SQL CE, which carries the same `IsCountDistinctSupported => false`
  (`SqlCeMemberTranslator.cs:366`, `AccessMemberTranslator.cs:452`), passes all 8716 of its tests. P7 had the
  answer and TO-3 did not use it: the existing filtered-group tests fail on Access with `Error_OUTER_Joins`, which
  is what the repo's `[ThrowsRequiredOuterJoins]` attribute exists for. The test now carries
  `[ThrowsRequiredOuterJoins(TestProvName.AllAccess)]`, which asserts the error rather than excluding the provider.
- **A-9 (2026-09-21) — A-6's "every provider" surfaced a YDB fixture requirement, not a pivot defect.** Every
  pivot/unpivot/`SelectDynamic` test failed on YDB — 24 tests × direct and `LinqService` — with
  *"Primary key is required for ydb tables"*, at `CreateLocalTable`'s DDL and before any pivot SQL ran. Seventeen
  fixtures across the three files gained `[PrimaryKey(Configuration = ProviderName.Ydb)]` (composite
  `[PrimaryKey(ProviderName.Ydb, n)]` where the natural key is more than one column), following the
  `Tests/Model/ParentChild.cs:23` precedent so no other provider's DDL moves. `CategorySales` needed a **surrogate
  `Id`**: `MultiRowData` and `DuplicateData` are deliberately non-unique — `DuplicateData` carries two
  byte-identical rows — so any natural key would have silently merged rows on insert and voided the very
  discrimination TO-3 relies on. Verified locally: 50/50 green on YDB.
- **A-10 (2026-09-21) — `PivotsRuntimeValuesIntoPivotRow` was a latent baseline flake, and CI had not caught it.**
  Its value set came from `t.Select(x => x.Year).Distinct().ToList()`, and the value set decides the generated cell
  order — so the emitted SQL, and the baseline recorded from it, differed with the row order the provider happened
  to return. It failed locally on `DuckDB.LinqService` with *"Baselines for remote context doesn't match direct
  access baselines"*, the two sides differing only in whether the `2000` or the `2010` `CASE` came first. Now
  `.OrderBy(y => y)`, which keeps the point of the test — the set is still built by a query and cannot fold to a
  constant — while making the SQL deterministic. Generalises: any runtime-valued pivot test that reads its set from
  an unordered query is baseline-nondeterministic by construction.
- **A-11 (2026-09-21) — Access.Jet.OleDb cannot read `AVG` over a `DECIMAL` column; pinned, not fixed.**
  `PivotsAvgMinMaxCells` fails only on `Access.Jet.OleDb`, inside `System.Data.OleDb.ColumnBinding.ValueDecimal()`.
  The SQL is correct, `MIN`/`MAX` over the same column in the same query succeed, and `SUM` over it succeeds in
  sibling tests — only the computed `AVG` fails. Access.Jet.**Odbc** and Access.**Ace**.OleDb both read the same
  query, so it is the Jet 4.0 OLE DB driver's DECIMAL binding, not linq2db's SQL. A workaround would be idiomatic —
  `AccessDataProvider.cs:69-83` already carries provider-split reader expressions keyed by OLE DB type name — but it
  would be keyed on the decimal type name and so would change **every** decimal read on Access OleDb, including ACE
  where reads work today; and the 32-bit `Jet.*` pair does not run on the development machine, so each attempt costs
  a full CI round-trip on a Windows-only leg. Pinned with
  `[ThrowsForProvider(typeof(InvalidOperationException), ProviderName.AccessJetOleDb, …)]`, which goes red the day
  it starts working. No linq2db issue exists for it and none was filed.

- **A-12 (2026-09-21) — A-11's failure is unpinnable; the test is split and the `AVG` case excluded.** Two
  successive `ThrowsForProvider` pins went red, because the Jet OLE DB failure is not stable. With byte-identical
  generated SQL in both logs, run
  [35587574130](https://github.com/linq2db/linq2db/actions/runs/35587574130/job/106297881756) raised
  `InvalidCastException` *"The numerical value is too large to fit into a 96 bit decimal"* and run
  [35612267776](https://github.com/linq2db/linq2db/actions/runs/35612267776/job/106385883561) raised
  `ArgumentException` out of `Decimal.SetBits` — both from `System.Data.OleDb`'s `DbBuffer.ReadNumeric`, so there is
  no stable type or message to assert. `PivotsAvgMinMaxCells` is split into `PivotsMinMaxCells` (bare
  `[DataSources]`) and `PivotsAvgCell` (`[DataSources(ProviderName.AccessJetOleDb)]`), keeping `MIN`/`MAX` covered
  on that provider; the driver defect is filed as [#5954](https://github.com/linq2db/linq2db/issues/5954) (Bug,
  6.6.0) and cited in the test comment. Two corrections to A-11: **ACE OLE DB was never evidence** — the
  `Win r_Access_MDB` leg runs only `Access.Jet.OleDb` and `Access.Jet.Odbc`, so A-11's "Access.Ace.OleDb reads the
  same query" was an unverified claim; and the differing exception *shape* (wrapped `LinqToDBConvertException` vs.
  raw `ArgumentException`) is linq2db's, not the driver's — the fast→slow mapper fallback at
  `Source/LinqToDB/Internal/Linq/QueryRunner.cs:98` catches `InvalidCastException` but not `ArgumentException`.

- **A-13 (2026-09-22) — D-3's five wrappers and the static-form overload pair are deleted; one factory member is
  the whole cell API.** Review of the shipped surface (2 public types, 12 members, 4 `Pivot` overloads, 18
  `PublicAPI.Unshipped.txt` lines) found most of it a verbose alias for the lambda the API generates anyway.
  Three findings, each independently sufficient:
  - `Sum`/`Min`/`Max`/`Avg`/`Count` are wrappers over `Custom`, implemented by ~50 lines of reflection
    (`PivotCell.Named` + `GetAggregate`) that re-derive at runtime what the compiler resolves in
    `rows => rows.Sum(x => x.Amount)`. `Sum`/`Avg` throw `LinqToDBException` at query-build time for a type
    `Enumerable.Sum` has no overload for; the lambda form makes that a **compile error**.
  - D-4's "two independent lift mechanisms" is a consequence of the wrappers, not a requirement. With one
    mechanism (`Custom`'s result lift) the observable behaviour is unchanged — the branch's own
    `AnEmptyCellOverANonNullableColumnReadsNull` already pinned the `Custom` arm reading `null` on every
    `[DataSources]` provider, so the wrapper arm was the redundant one. `Count`'s unlifted special case goes with it
    (`COUNT` never returns `NULL`, so reading it as `int?` is inert).
  - The `params PivotCell<TSource,TFor>[]` overload pair is strictly worse than its factory twin: C# cannot infer
    type arguments from a result used as an argument, so all 19 static-form references in the tests spelled
    `PivotCell<CategorySales, int>.` by hand, and the form cannot be used at all when `TSource`/`TFor` are anonymous
    — which the production-shape test needs.
  What survives is the **erasure carrier**, and only that: multi-cell is the one thing `Pivot` has over
  `GroupBy` + `SelectDynamic` (which takes a single `valueTemplate`, hence a single `TCell`), and C# cannot put
  differently-typed generic lambdas in one `params` array. The factory lambda is the idiom that recovers inference
  across the erasure, so the `params Func<PivotCellFactory<…>, PivotCell<…>>[]` shape is kept verbatim.
  **Supersedes D-3 and D-4's wrapper half. Amends E-14** (`PivotCell` keeps only an `internal static Cell<TCell>`;
  no reflection, no `Named`, no `GetAggregate` — the type is public with zero public members), **E-15**
  (`PivotCellFactory.Cell<TCell>` is the sole public member) and **E-17** (18 lines → 5).
  Test consequence, audited test-by-test: the tests were never testing the factory members, they are provider
  coverage for the aggregate vocabulary, so 15 convert mechanically and none is a duplicate.
  `AnEmptyCellOverANonNullableColumnReadsNull` is the only one that loses content (3 cells → 2, the wrapper arm
  being an exact duplicate of the `Custom` arm), and `PivotsWithACustomAggregate` → `PivotsWithADistinctCountCell`
  because "custom" stops being a category. `PivotsAvgCell` is kept deliberately: it is the only carrier of the
  #5954 Access-Jet exclusion.

- **A-14 (2026-09-22) — the cells move *into* the projection; both placements ship.** sdanyliv re-proposed an
  in-selector fluent cell API. Investigating it found the fluency is not what it buys: the cost of the `params`
  shape is that `SelectDynamicBuilder` appends the generated columns to **`TResult`'s own**
  `[DynamicColumnsStore]` member, so `TResult` must be a declared mutable class carrying the attribute — an
  anonymous projection, the idiomatic LINQ shape, is impossible, and `PivotRow<TKey>` exists only to paper over
  that. A second overload now takes `(g, p) => new { …, Cells = p.Cell(a, n).Cell(b, m) }` and nests the cells in
  the member the chain is assigned to, so the result type needs no store of its own. The user's call was to keep
  **both** families: the family-2 chain is read out of an expression tree, so its number of cell *templates* is
  fixed at compile time, while family 1's `Func` can build templates in a loop — that asymmetry is the documented
  reason both exist, not a transition state.
  - **One carrier type.** `PivotCellFactory<TSource,TFor>` and `PivotCell<TSource,TFor>` are deleted;
    `PivotCells<TSource,TFor>` is the lambda parameter, the chain result *and* the materialized store (`Values` /
    indexer / `Get<T>` lifted verbatim from `PivotRow<TKey>`). All three overloads take a
    `…PivotCells<TSource,TFor>…` lambda, so `params Func<…>[]` becomes a single chained
    `Func<PivotCells<,>, PivotCells<,>>`. **Supersedes A-13's closing "the `params Func<PivotCellFactory<…>,
    PivotCell<…>>[]` shape is kept verbatim"** — the erasure-carrier argument survives intact, but the chain
    carries the erasure just as well with one type instead of two.
  - **Deviation from the approved design: no `cellsMember` argument on `SelectDynamicCore`.** The design routed
    the target member's *name* through the marker. The implementation instead leaves an
    `Expression.Constant(null, typeof(PivotCells<,>))` where the chain was, and the builder finds it in the
    constructor's `Assignments` (or `Parameters`). Same result, unchanged marker signature, and it reaches
    projection shapes a member name cannot — a positional record's `NewExpression.Members` is null.
  - **U1 resolved positive.** `Sql.Property<decimal?>(r.Cells, "Y2010")` after the pivot is a *server-side*
    column: `ComposesOverANestedCell`'s baseline is a bare `GROUP BY` + `HAVING SUM(CASE WHEN … )`, with the
    unused second cell pruned. The fallback in the plan (document that composition goes through family 1) is
    not needed.
  - **U2 resolved: the change is SQL-neutral.** Pre/post snapshot of the whole local baselines tree over
    `PivotDynamicTests` on SQLite.Classic + DuckDB: **`changed: 0`, `unchanged: 10114`**, `added: 6` — the three
    new `[DataSources]` tests × two providers. `PivotsIntoAnAnonymousType`'s SQL is byte-identical to
    `PivotsMultipleCellsIntoUserType`'s, which is the nested form's whole claim.
  - **`PivotRow<TKey>` is deleted too, on the user's call** (`q: remove`), and with it the no-result-type
    `Pivot<TSource,TKey,TFor>` overload it existed to return: `(g, p) => new { g.Key, Cells = p.Cell(…) }` is the
    same thing without a library type. **Supersedes A-14's own first draft**, which kept it. That drops a public
    type with 5 members and removes the shadowing error mode's original subject — `CellNamedAfterARowMemberThrows`
    is deleted as a duplicate of `NestedCellNamedAfterACellsMemberThrows`, which pins the same mechanism against
    `PivotCells`. `SelectDynamicTests.ProjectsIntoBuiltInPivotRow` used `PivotRow<int>` as a convenient
    `SelectDynamic` store type; it is deleted (its store-machinery coverage duplicates
    `ProjectsRuntimeColumnSetIntoStore`) and its unique assertion — an ungenerated name reads absent rather than
    throwing — is carried into `PivotsProductionShapeWithoutAResultType`.
  - **The removal is byte-for-byte SQL-neutral, measured twice.** Converting all eleven no-result-type tests from
    `PivotRow` to the nested anonymous form: `changed: 0`, `removed: 0` over the whole baselines tree. The two
    renamed tests (`PivotsRuntimeValuesIntoPivotRow` → `PivotsRuntimeValues`, `PivotsProductionShapeIntoPivotRow`
    → `PivotsProductionShapeWithoutAResultType`) hash **identical** to their predecessors
    (`676C88F2…`, `E82F5A88…`), so the only baseline delta in the whole amendment is two file *names*.
  - Test consequence: nine multi-cell call sites convert to the chain, eleven no-result-type sites to the nested
    form, four tests deleted as duplicates, two renamed, four added (anonymous-type pivot plus three negatives — a
    cell name shadowing a `PivotCells` member, two chains in one projection, a projection with no chain).
    84/84 green on SQLite.Classic + DuckDB across `PivotDynamicTests` + `SelectDynamicTests`; Release net10.0,
    Release netstandard2.0, Tests Release net10.0 and Tests Release net462 all clean.
  - **Baselines-PR consequence:** the two renames make [#2139](https://github.com/linq2db/linq2db.baselines/pull/2139)'s
    keys stale, so it wants `close-stale-baselines.ps1` and a fresh CI regeneration rather than a merge.

## P12 Critic verdict (M/L)

**Round 1 — `refuted`** (Fable, dispatched with the measurements forwarded verbatim and the unprobed claims labelled).

Objections accepted and what changed:

1. *D-3 regresses PostgreSQL 9.2/9.3* — `IsFilterSupported => true` unconditionally, every version below 9.5 gets that translator, `FILTER` is 9.4+; 25 `GroupByTests` carry `// PostgreSQL 9.4+ (FILTER clause)` above an `AllPostgreSQL93Minus` exclusion, and TO-1's matrix could not observe it. → D-5 added (version gate), SC-6, TO-7, TO-8. Reframed: this is a **live defect on master**, not a cost of this feature.
2. *Deleting `MakeNullable` changes results* — `agg(g.Where(…))` types as `TCell`, and `DBNull` reads back through `GetDefaultValue`. → probed (U-9): SQL identical, materialization `null` vs `0`. D-4 added, SC-7, TO-9.
3. *TO-6 cannot fail for the reason it names* — both peers are the same build. → replaced with a static `Order` census.
4. *TO-4's red→green label is unfounded* — `PivotDynamicTests:297,397` already compose `.Where`, and `Max` is already exercised. → relabelled characterization, all six.
5. *TO-3's string-aggregate half rests on an unexercised path* — no test applies `StringAggregate` to a grouped `g.Where(…)`. → cut; distinct-count half retained with its discriminating input.
6. *No prose row in P7, and P6 under-scoped by one file* — public XML docs promise native `UNPIVOT`. → E-22 and a P7 prose row added.
7. *`UnpivotMulti` rows change on Oracle/DuckDB* — native `includeNulls: false` vs a fallback that filters nothing, against a doc promising NULLs are kept. → SC-8, TO-10, P10 entry.
8. *Scope defects* — E-18 deleted fixtures its own ports need (fixed: relocated); line ranges off by 1–3 at every hunk, one orphaning an XML doc into `CS1587` (fixed: remove by `git diff -U0` hunk, never by number); three untracked scratch files compiled by the SDK glob break the build (E-23).

Not accepted: none — every objection was either verified against source or probed.

Critic's strongest confirmation, retained as a verification handle: the branch is **add-only against master** (33 files, zero deletions), so E-1…E-9 revert core to master exactly and TO-2 is a genuine control.

**Round 2 — `weak`** (Fable). Verdict carried forward with the objections visible; the approach holds and the defects were in the text.

1. *The 9.4 boundary is not expressible* — `PostgreSQLVersion` has no `v94`, and the detector maps a real 9.4 server to `v93`. → D-5 rewritten to the **9.5 tier**, which the codebase already uses for window `FILTER`; the `PostgreSQLDataProvider` edit is dropped as unnecessary, the base override is kept (Shipped-tracked), and E-17 gains the nested-translator entries.
2. *The gate misses a second `FILTER` emitter* — `StringMemberTranslator.TranslateStringJoin` passes `filter:` unconditionally from a different nested class. → D-3's "no provider hole" **narrowed to the five base aggregates**; the string-aggregate hole is recorded in P10. This also falsified TO-3's cut rationale: the sweep looked for `StringAggregate` and missed `string.Join`, which routes through the same translator and *is* tested over a filtered grouping (`StringJoinTests.cs:193,347`).
3. *"all 25" is 22 + 3* — three exclusions are `make_timestamp`, not `FILTER`. → TO-8 scoped to 22, with the full 37-row / 5-file footprint named and driven by comment grep.
4. *E-17's range deletes API P3 keeps* — `Unshipped:74-75` are `Unpivot` overloads. → ranges corrected to `55-72` / `76-79`, with the surviving lines named and the blanket "remove by hunk" note explicitly disapplied for this file.
5. *TO-9 did not name which lift it exercises* — the wrappers lift the selector, `Custom` can only lift the result, and no test does a result-lift over an aggregate. → TO-9 now asserts both arms and names the `Custom` arm as the one without prior evidence.

Confirmed by round 2 and retained: D-4 is correct to leave `Count` unlifted (`COUNT(CASE …)` and `COUNT(*) FILTER` both return 0, never NULL); the round-1 fixes to TO-6, TO-4, E-18 and E-23 all landed; the branch is add-only (33 files, +4357, 0 deletions).

**Residual risk, unverified:** PostgreSQL 9.2/9.3 were never executed — the critic did not run them either, and U-11 records the containers as likely dead. TO-7/TO-8 carry that as `blocked` if they will not start.
