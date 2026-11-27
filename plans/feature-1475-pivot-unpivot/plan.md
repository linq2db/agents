# Work plan: feature-1475-pivot-unpivot — drop native PIVOT/UNPIVOT emission and the static IPivotBuilder API

**Tier:** L  ·  **Status:** approved  ·  **Approved-at:** 2026-10-22 (A-17, after critic round 8 re-check `weak`)  ·  **Branch:** feature/1475-pivot-unpivot
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
- SC-7 An empty cell over a **non-nullable** value column still materializes `null`, not `default(T)`. → TO-9. **A-17 scope:** holds for the `Cell`-fed terminals (`AsDictionary`, `AsDynamic`, `Cells`), where the expander owns the cell type. The `Select` terminal's member types are the user's, and its rule is D-9's (TO-14, TO-27).
- SC-8 A multi-value `Unpivot` keeps all-NULL rows on Oracle and DuckDB, matching its documented contract. → TO-10

**A-17 re-maps SC-1** to `PivotTests` + the ported `PivotDynamicTests` (`SelectDynamicTests` leaves the branch with D-8), and **SC-4** to the ported fixture. New criteria:

- SC-9 `g.Pivot(for, values).Cell(…).AsDictionary()` written inside `GroupBy(…).Select(g => …)` returns the cell values today's `(g, p)` overload returns, as one `GROUP BY` with N×M filtered aggregates, on every `[DataSources]` provider, direct and `LinqService`. → TO-11
- SC-10 The pivot is expressible in query syntax over a join with an anonymous `TSource`, and two pivots over different FOR columns sit in one projection. → TO-12, TO-13
- SC-11 `Select((value, rows) => T)` returns one statically typed item per pivoted value, in value order. → TO-14
- SC-12 `AsDynamic()` reads a cell as `row.Cells.Y2010`; `Cells(templates)` takes a cell set decided at run time. → TO-15, TO-16
- SC-13 Cache identity holds by construction: a changed value set, a list mutated in place, or a changed name-factory output is a different query, and identical inputs hit — direct, inside a sub-query, and in a compiled query. → TO-17, TO-18, TO-19
- SC-14 The branch carries no top-level `Pivot` overload, no `PivotCells<TSource,TFor>`, no `SelectDynamic*`, and no `Pivot` arm in a sugar builder. → TO-20
- SC-15 A `MemberInitExpression` binding a `DynamicColumnInfo` materializes into the type's dynamic-columns store, and one over a type without a store fails with a named error. → TO-23

**A-19 adds SC-16 and SC-17** (review round 3, sdanyliv MAJ002 / MAJ003; reshaped by critic round A-19):

- SC-16 `Unpivot`'s name column reads a member the source's mapping does not carry — a pivot cell, a member of a projected object — by its own member name, unless another column would read the same name, in which case it reads its path; a mapped complex column keeps its physical name. → TO-29, TO-34
- SC-17 Where SQL is required — `Where`, `OrderBy`, a grouping key, `Distinct`, an aggregate, an `Unpivot` column — `PivotCells.Get<T>(name)` and `cells[name]` on a member typed `PivotCells` read the cell's column converted to the read's type, a name no cell carries is a named error, and a changed captured name is a different query; a row-dependent name compiles and re-executes; a plain projection keeps the members' in-memory contract (absent → `null`, another type → `default`); cells the client holds stay a value. A-21: the Unpivot column converts too, a cast receiver over an interface-typed member keeps its path, a read type the cell has no conversion to is a named error, and the absent-name error is named in `Where`, `OrderBy`, `Distinct` and a grouping key, not in a top-level aggregate's selector (P10). → TO-30…TO-33 (A-19), TO-35…TO-39 (A-20), TO-42…TO-51 (A-21)

## P3 Constraints & anti-goals (M/L)

- **No query result may change.** Every difference is in emitted SQL, never in rows.
- `Unpivot`'s public surface stays whole: both selector overloads, both multi-value overloads, both name-array overloads, and `UnpivotNulls`.
- The dynamic API stays: `SelectDynamic`, both `Pivot` overload pairs, `PivotRow<TKey>`, `PivotCellFactory`, `SelectDynamicBuilder`. **Superseded by A-13/A-14:** `PivotRow<TKey>`, `PivotCell` and `PivotCellFactory` are deleted; `PivotCells<TSource,TFor>` and two `Pivot` overloads are the surface.
- No edit to `PublicAPI.Shipped.txt` and no `CompatibilitySuppressions.xml` entry — every affected API line is in `Unshipped`.
- **Anti-goal: do not re-plumb the dynamic API onto native PIVOT.** That was step 8 of the prior plan; the measurements above retire it.
- **Anti-goal: do not touch the window-function filtered-aggregate machinery.** `WindowFunctionsMemberTranslator.IsWindowFilterSupported` is a distinct concept from the grouped-aggregate `IsFilterSupported` this plan relies on.
- `Tests/Linq` must build for **net462**; `Enumerable.Append` is unavailable there (cost one red CI leg this session).
- **A-17:** the dynamic-API line above is superseded again. The surface is `IGrouping<TKey,TSource>.Pivot`, `PivotBuilder<TSource,TFor>`, `PivotCell<TSource,TFor>`, non-generic `PivotCells` (D-9). `SelectDynamic` leaves the branch (D-8).
- **A-17:** `Unpivot`'s surface and behaviour are untouched; extracting the shared argument reader (E-51) must leave every `PivotTests` result and cache assertion as it is (TO-28).
- **A-17:** the expose branch fires only on a call whose declaring type is `PivotBuilder<,>`, and the `VisitMemberInit` branch only when a binding's member `IsDynamicColumnProperty`. Neither may change what any other query sees.
- **A-17 anti-goal:** no `[NotParameterized]` on any `PivotBuilder` parameter — EF's `TransformExpressionVisitor.cs:288-317` wraps such arguments in `ToSql(...)`.
- **A-17 anti-goal:** the pivot does not route through `SelectDynamicCore` / `SelectDynamicBuilder`, and adds no SQL AST node.

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

A-17 rows. Probes ran 2026-10-22 in the worktree at 4dddec407 (scratch fixture, SQLite.Classic + `.LinqService`, net10.0, deleted after):

- U-13 Does a projection `MemberInit(new Store(), Bind(DynamicColumnInfo(Store, decimal?, "Y2000"), g.Where(row => row.Year == 2000).Sum(x => x.Amount)), …)` materialize? — resolved-by probe, **measured: no.** `InvalidProgramException` from `Mapper<T>.GetMapperInfo` → `CompileExpression` (`QueryRunner.cs:148`), direct and `LinqService`. The raw `MemberInit` reaches compilation and `DynamicColumnInfo.GetSetMethod` is a dummy setter (`DynamicColumnInfo.cs:118-131`). **The same tree composed with `.Where(r => Sql.Property<decimal?>(r.Cells, "Y2010") >= 16).OrderByDescending(…)` passed** and emitted `HAVING SUM(CASE …)` with an `ORDER BY` over the cell: the composed path parses the projection into a `SqlGenericConstructorExpression`, whose construction routes dynamic assignments through `ed.DynamicColumnSetter` (`EntityConstructorBase.cs:560-563,610-624`). Drives D-7.
- U-14 Does routing such a `MemberInit` through `SqlGenericConstructorExpression` fix materialization? — resolved-by probe, **measured: yes**, with a scratch branch at the top of `ExpressionBuildVisitor.VisitMemberInit`: `if (_buildPurpose is not BuildPurpose.Sql && node.Bindings.Any(b => b.Member.IsDynamicColumnProperty)) return Visit(new SqlGenericConstructorExpression(node).WithMappingSchema(MappingSchema));`. 11/11 probes green, direct + `LinqService`: plain materialization, composition, cache identity, a `DynamicObject`-derived store. The probe condition was **broader than intended** — "not `Sql`" also covers `Traverse`/`Expand`/`Root`/`AssociationRoot`/`AggregationRoot`/`SubQuery`/`Extract` (`BuildPurpose.cs:6-22`, scout) — so D-7 narrows it. **Round-8 re-measure (critic objections 6–7), same harness:** the narrowed form — guard first for every purpose (`DynamicColumnSetter == null` → named error), then convert only when `_buildPurpose is BuildPurpose.Expression` — passed 13/13, direct + `LinqService`, on six cases: plain materialization; composition; **zero values** (`MemberInit(new Store())` with no bindings, each row getting its own store instance); **constructor-argument placement** (`new KeyValuePair<string, Store>(g.Key, MemberInit(…))`, where `NewExpression.Members == null`); a **store-less type** (the named error); and **`Concat`** of two such projections (the `ForSetProjection` path). **Control, same cases on the unfixed engine:** plain, constructor-argument and store-less fail with `InvalidProgramException`; composition, zero values and `Concat` already pass. So E-43 is needed exactly where the raw `MemberInit` reaches the materializer.
- U-15 Does a `NewArrayInit` of objects whose members are filtered aggregates materialize inside a grouped projection, as the typed `Select` terminal needs? — resolved-by probe, **measured: yes.** `Years = (IReadOnlyList<ProbeItem>)new[] { new ProbeItem { Year = 2000, Amount = g.Where(x => x.Year == 2000).Sum(x => x.Amount) }, … }` is one `GROUP BY` statement with two `SUM(CASE …)` columns, values correct, direct + `LinqService`. No engine change needed.
- U-16 Does the expanded tree carry cache identity? — resolved-by probe, **measured** on a hand-built expanded tree under `[QueryCacheTest]`: same values + names → hit (1 miss); names `Y…` → `Z…` → miss; fewer values → miss; two value sets under one value-blind name `_ => "C"` → a miss each (5 misses for 5 distinct trees), each reading its own value. The scalar filter literal stays in tree equality (`ExpressionCacheHelpers.cs:10-24`, scout). **Caveat, reasoned, unprobed:** the probe tree was already expanded, so expose left it unchanged and it was looked up in the un-exposed bucket. The real expansion is looked up after expose under `QueryFlags.ExpandedQuery` (`Query{T}.cs:173-188,208-210`, scout), comparing exposed against exposed. Same comparer, different phase; TO-17 measures the real path.
- U-17 Can anything consume or evaluate the `g.Pivot(…).Cell(…).AsDictionary()` chain before a branch placed right after the `Sql.Property` check? — resolved-by scout: **no.** `_memberConverter` matches only `TrimLeft`/`TrimRight`/`ToValue` by exact `MethodInfo` (`LegacyMemberConverterBase.cs:47-83`). `ConvertExpressionMethodAttribute` needs `[ExpressionMethod]`. `ConvertMethod` → `Expressions.ConvertMember` is a keyed lookup (`Linq/Expressions.cs:292-379`). `TryConvertIQueryable` needs an `IQueryable` type (`ExposeExpressionVisitor.cs:451`). `TryEvaluateArguments` runs later and only folds `Expression<>`-typed non-quote arguments (`:283-309`). Pre-expose passes leave an unknown type's calls alone: `BinaryExpressionAggregatorVisitor`, `IExpressionPreprocessor` (no in-box implementation), EF `TransformExpressionVisitor` (`[NotParameterized]` only, `:288-317`), and `ComputeChainHash` (`QueryCache.cs:525-553`, hashes only along `Arguments[0]`). `origin/master` adds `ConvertRawSqlString` after `ConvertMethod` (#6003/#6008), which is also after the insertion point.
- U-18 Is the branch reached inside sub-queries, and how often does expose run? — resolved-by scout. **Reached:** a built-in queryable whose `Arguments[0]` is not a member/constant falls through to `base.VisitMethodCall` (`:524-528,177`), which visits quoted lambdas. **Re-run** in three ways: (1) an `ExposedQuery` interceptor that changes the tree re-exposes it, up to 10 times (`Query{T}.cs:65-104`), and the EF interceptor runs on every kind (`LinqToDBForEFToolsDataConnection.cs:95-100`); (2) `CompiledTable{T}.cs:110`, `AssociationHelper`, `TableBuilder` filters and `ConvertExpressionTree` (`MethodChainBuilder`, `PivotSugarBuilder`, calculated columns) expose subtrees; (3) `ConvertSingleExpression` runs the visitor with `isSingleConvert: true` at build time (`ExpressionBuilder.SqlBuilder.cs:235-242`; callers `ExpressionBuildVisitor.cs:868,1182,1675,3106`). So the expansion must be **idempotent**: its output contains no `PivotBuilder` call and is stable under a second expose (stock `VisitMemberInit` / `MemberAssignment.Update`). The branch must sit **before** the `_isSingleConvert` early return (`:167`), and it rewrites the whole chain from the terminal down, because a top-down visit reaches the terminal before its receiver. — resolved-by scout
- U-19 How does a value set read from a compiled query's argument array stay in the key? — resolved-by scout. Compiled-query arguments arrive as `Convert(ps[i])` (`CompiledQuery.cs:232-248`) and `IsCompilable` rejects `ParametersParam` (`ExposeExpressionVisitor.cs:1030-1036`). The expander resolves them with `ResolveCompiledQueryArguments` and records the slot with `RecordMaterializedArgumentSlots`, as `HandleSqlDependentParameters` does (`:201-210`). `CompiledTable{T}.cs:107-112` keys its cache on the materialized slots' values. Without the record, a compiled pivot replays the first call's columns (the trap `ExpandOverSource` documents at `:605`). The origin × shape grid is TO-19.
- U-20 How is a name factory (a `Func<TFor,string>` lambda, method group or captured delegate) evaluated at expose? — resolved-by scout + decision. `IsCompilable(lambda)` returns false for a bare lambda (`CanBeEvaluatedOnClientCheckVisitorBase.cs:37-43`), so the expander evaluates the factory argument directly with the visitor's `ps`-substituting `EvaluateExpression` (`:411-447`) and calls it once per value. A factory that references the lambda parameter `g` cannot be evaluated: named error. Consequence for A-16's guarded-read problem: the factory now runs only on the actual values, as a direct call does, so nothing is evaluated eagerly behind a guard. `MarkGuardedValue` has no Pivot counterpart.
- U-21 Does the pivot work over an EF Core `DbSet`? — resolved-by scout: **only through `.ToLinqToDB()`.** Today's top-level operator reaches linq2db through `ProcessIQueryable` (`LinqInternalExtensions.cs:140-143`; hook `LinqToDBForEFTools.cs:56-77`). `g.Pivot` sits inside `Queryable.GroupBy`/`Select`, which EF executes. That is the existing convention for every linq2db-only member in an EF projection (`Tests/EntityFrameworkCore/Tests/IssueTests.cs:381-419`). Recorded in P10; TO-24.
- U-22 Does the F# query-expression interceptor (`FSharpQueryExpressionInterceptor.fs:413-419`) pass the chain through? — resolved-by decision: **not claimed.** F# is untested for this API, and the XML docs make no F# claim. P10 narrows the claim to C#.
- U-23 What happens when a dynamic-binding `MemberInit` targets a type with no dynamic-columns store? — resolved-by scout. `EntityConstructorBase.cs:602-610` counts the assignment and then **drops it silently** when `ed.DynamicColumnSetter == null`; `SelectDynamicBuilder.cs:47-48` guarded this for its own path. D-7's branch throws `Error_NoDynamicColumnsStore` instead. `PivotCells` always has a store, so this guard serves only a hand-built tree. TO-23.
- U-24 Which expression shapes must the expander's chain reader accept? (reader-shape rule.) Each gets a cell in TO-25: `Cell` aggregate as an inline lambda; `PivotCell.Create` over an `Expression<>` held in a variable; name factory as an inline lambda, a method group (`Convert(CreateDelegate)`) and a captured `Func`; `Cells(…)` over an inline array, a captured list and a method result; values as a captured list, an array, a method call, a mutated list and a compiled-query slot; a composite `forColumn` (`new { x.Year, x.Half }`); the terminal assigned to an interface-typed member (`Convert` to `IReadOnlyDictionary<string, object?>`); the terminal nested in an inner object; and the terminal used outside a member position (in `Where`, as a method argument), which is a named error. Round 8 adds four shapes that D-9's delegate-typed parameters invite: (i) a `Cell` aggregate or (ii) a `forColumn` passed as a captured `Func` or a method group — a delegate cannot be spliced, so this is a named error pointing at an inline lambda or `PivotCell.Create`; today's `PivotsWithAPrebuiltAggregate` (`PivotDynamicTests.cs:971-996`) migrates to `Cells(PivotCell.Create(expr))`; (iii) `values` that read `g` or an outer lambda parameter (correlated) — a named error, since the value set must be client-evaluable; (iv) a `g.Pivot(…).Cell(…)` chain with **no terminal** — E-42 also recognises a `Pivot` or `PivotBuilder<,>` non-terminal call that no terminal consumed, and raises a named error rather than letting it reach the builder as an unknown method. Plus (v) an `[ExpressionMethod]` member inside a cell body and a `Sql.Property` in `forColumn`, which are exposed only if E-42 re-visits its output. — resolved-by decision + critic round 8
- U-25 What does the expansion cost per execution? **Unmeasured, and no claim is made.** Mechanism, corrected by critic round 8: an ordinary query that hits on the raw tree never runs expose again (`Query{T}.cs:146-164`); a pivot query misses the raw-tree bucket every time, because the flags are in the bucket key (`QueryCache.cs:338-353`), so it runs the **whole** expose pass on every execution, plus the expansion; each inline or method-group name factory is evaluated by compiling a wrapper per execution (`ExpressionEvaluator.cs:112-124`), the cost A-16 measured for the inline path; a captured `Func` factory is invoked without compilation. Today's top-level method rebuilds its tree on every call too, but its cache lookup then hits. P10. — resolved-by decision
- U-26 `TryEvaluateArguments` assigns `evaluatedArgs[i]` only inside `if (evaluatedArgs == null)` (`ExposeExpressionVisitor.cs:298`), so one pass substitutes only the first `Expression<>`-typed argument. — resolved-by probe: **not observable.** The caller re-visits the updated node (`:170-175`), and `MethodCallExpression.Update` auto-quotes the substituted lambda, so the later arguments are filled in on later passes. A correlated `Join` with three captured `Expression<>` variables returned correct rows, direct + `LinqService`. A temporary throw on the second argument fired at index 3, so the case was reached. Cost: one extra visit per additional argument. Off this branch's path; the user had the cleanup done on its own branch by another session.
- U-27 Does the expansion survive projection paths that bypass `VisitMemberInit`'s `Sql` arm? — resolved-by scout. Expression + `ForSetProjection` callers reach the non-`Sql` path (`MergeProjectionHelper.cs:49`, `ExpressionBuilder.EagerLoadUnion.cs:203,313,471,904`), so D-7 covers them. The other `MemberInit` → generic-constructor sites go through `ParseGenericConstructor` and keep dynamic assignments (`SequenceHelper.cs:387,600,719`; `ProjectionPathHelper.cs:127`; `BuildProxyBase{TOwner}.cs:204`; `TableLikeQueryContext.cs:416`; `UpdateBuilder.cs:335,659`). Reasoned, unprobed for set operations and eager load: TO-26.
- U-28 **What does `PivotBuilder` do when it runs in memory (LINQ to Objects, or `AssertQuery`'s expected side)?** — resolved-by user answer 2026-10-22: **(a)**. `Pivot(...)` and every `PivotBuilder` member throw a named `LinqToDBException` when invoked, for all three terminals. `PivotCell.Create` is a template factory, not a query member: it works anywhere. Critic round 8 (objection 10) noted that the options were framed for the `Cell`-fed terminals only. For `Select` the in-memory body is the user's own lambda, so the divergence there would be `Min`/`Max` throwing on an empty non-nullable selector; (a) makes that moot. Consequence: the ported tests cannot use `AssertQuery` (its expected side runs in memory); they assert values directly, as the fixture already does. Original question, kept for the record: SQL reads an empty `SUM`/`MIN`/`MAX`/`AVG` cell as `null` and an empty count as `0` (the A-13 contract). In-memory, `Enumerable.Sum` over no rows gives `0`, and `Min`/`Max` over a non-nullable selector throws. The client cannot tell a count from a sum without inspecting the delegate. Options: **(a)** throw a named `LinqToDBException`, the server-side-only convention; **(b)** run the aggregate over the matching rows and return `null` when none match (an empty count then diverges: `null` vs `0`); **(c)** run the aggregate literally (an empty `SUM` diverges: `0` vs `null`). The approved session plan said "each member also gets an in-memory implementation", which assumed this divergence away. User decision; the recommendation was (a), because both (b) and (c) ship a client that disagrees with the server on the cell users read most.

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

### D-6 — Pivot is an aggregate over a group, expanded in `ExposeExpressionVisitor` (A-17)

- **chosen:** sdanyliv's proposal ([#5708 comment 6152165147](https://github.com/linq2db/linq2db/pull/5708#issuecomment-6152165147)). `g.Pivot(forColumn, values)` on `IGrouping<TKey,TSource>` returns a `PivotBuilder<TSource,TFor>`. A terminal (`AsDictionary` / `AsDynamic` / `Select`) is rewritten by a new branch in `ExposeExpressionVisitor.VisitMethodCall`, placed after the `Sql.Property` check and before the `_isSingleConvert` return (U-17, U-18), and delegated to an internal `PivotExpander`. `PivotExpander`:
  - evaluates the values, templates and name factories (U-19, U-20);
  - validates names with today's rules;
  - emits today's `BuildCell` shape, `aggregate(g.Where(row => for(row) == value))` with the nullable lift.

  The expanded tree is what the cache compares (U-16), so a changed input is a different tree and nothing is marked by value.
- **rejected:** keep the top-level operators (A-14's shape). It keeps the `(g, p)` two-parameter selector and the `TResult` store contract. It is unusable in query syntax and with two pivots in one projection (`TwoNestedCellSetsThrow` pins the throw). It needs `PivotSugarBuilder`'s after-the-key marking, which took four critic rounds in A-16 and still left an eager-evaluation limitation.
- **rejected:** expand in a `MethodCallBuilder` for the terminals. A builder runs after the cache key is taken (`architecture.md` → *Values a builder reads after the cache key*), so it needs the same `MarkAsValue` machinery D-6 removes.
- **rejected:** `[ExpressionMethod]` on the terminals. An expression method's body has a fixed shape; it cannot grow one member per runtime value.
- **why this:** the value set changes the *shape* of the query, and expose is the last stage whose output is the key. `Sql.Property` already resolves runtime member names here (`HandleSqlProperty`, `:233-266`). The SQL is unchanged: the cells are today's filtered aggregates.
- **failure mode of the choice:** a branch in a visitor every query passes through. Its blast radius is bounded by the declaring-type test, but a mistake in it is product-wide. Every pivot query permanently takes the expanded cache path (U-25). An F# or third-party interceptor that rewrites projection calls before expose could hide the chain (U-22).

### D-7 — Materialize a dynamic-column `MemberInit` through `SqlGenericConstructorExpression` (A-17)

- **chosen:** at the top of `ExpressionBuildVisitor.VisitMemberInit`, when any binding's member `IsDynamicColumnProperty`:
  - **for every build purpose**, throw `Error_NoDynamicColumnsStore` if the type has no `DynamicColumnSetter` (U-23). This also covers the `Sql` arm, where `ParseGenericConstructor` would otherwise carry the assignment to `EntityConstructorBase.cs:602-610` and drop it silently (critic round 8, objection 6);
  - then, **only when `_buildPurpose is BuildPurpose.Expression`**, return `Visit(new SqlGenericConstructorExpression(node).WithMappingSchema(MappingSchema))`.

  The predicate is the purpose alone. The `ForSetProjection` callers (`MergeProjectionHelper.cs:48-49`, four `EagerLoadUnion` sites) already pass `BuildPurpose.Expression` (critic-verified), so they are included without testing the flag. A lingering `ForSetProjection` under `Sql` therefore does not pre-empt the `Sql` arm's `HandleValue`/`HandleSqlRelated`. This is the shape `SelectDynamicBuilder` already hands to construction. Measured in this narrowed form on six cases (U-14, round 8).
- **rejected:** have expose emit a `SqlGenericConstructorExpression` directly. That puts an extension node into the tree the cache compares and that a later expose re-visits (U-18); neither path is known to handle it.
- **rejected:** emit an opaque client factory call (`PivotCells.Create(names, new object[] { … })`). It would materialize, but `Sql.Property(r.Cells, …)` composition needs member assignments the builder can see through. Reasoned, unprobed.
- **why this:** U-13 shows the defect is general rather than pivot-specific: any `MemberInit` binding a `DynamicColumnInfo` compiles to invalid IL today, and the composed path already handles the same tree. The fix is a projection-layer correction where the defect lives, and it gets a core-layer test (TO-23) beside the consumer tests.
- **failure mode of the choice:** a hand-built tree that bound a dynamic column used to crash with `InvalidProgramException` and now materializes or throws a named error. The bindings are visited inside a generic constructor rather than a `MemberInit`, so any purpose-specific handling of `MemberInit` children is bypassed for those trees only.

### D-8 — `SelectDynamic` leaves this branch for its own PR (A-17)

- **chosen (user's call):** `LinqExtensions.SelectDynamic.cs`, `SelectDynamicBuilder.cs`, `SelectDynamicTests.cs`, their `ErrorHelper.Pivot` constants and `PublicAPI.Unshipped.txt` lines move to a new branch off `origin/master`. The build-time argument reader both PRs need (`ReadArgument`, `RegisterBuildTimeValues`, `MarkGuardedValue`, `Snapshot`) is extracted into one internal helper file, **byte-identical in both PRs**, so the second merge is a clean add/add. Each PR keeps its own small sugar builder: here `UnpivotSugarBuilder` (Unpivot only; `RegisterCellArguments` goes, being Pivot-only); there a `SelectDynamic` one.
- **rejected:** stack the SelectDynamic PR on #5708. That couples an independent feature to this PR's review.
- **rejected:** keep `PivotSugarBuilder`'s name and file in both PRs. Two divergent edits of one file guarantee a conflict.
- **why this:** with D-6, nothing in Pivot uses `BuildSelectDynamic` / `SelectDynamicCore` (scout: the only other caller was `BuildPivot`, `LinqExtensions.PivotDynamic.cs:235`). `SelectDynamic` is then a separate feature with its own issues (#4992, #4248, #2953).
- **failure mode of the choice:** the helper can drift if one PR edits it before the other merges. The second PR to merge must re-sync it.

### D-9 — Public surface and terminals (A-17)

- **chosen:**
  - `Pivot<TKey,TSource,TFor>(this IGrouping<TKey,TSource>, Func<TSource,TFor> forColumn, IEnumerable<TFor> values)`.
  - `PivotBuilder<TSource,TFor>` with `Cell<TCell>(Func<IEnumerable<TSource>,TCell>, Func<TFor,string>? name = null)`, `Cells(IEnumerable<PivotCell<TSource,TFor>>)`, `AsDictionary()` → `PivotCells`, `AsDynamic()` → `dynamic`, and `Select<T>(Func<TFor,IEnumerable<TSource>,T>)` → `IReadOnlyList<T>`.
  - `PivotCell<TSource,TFor>.Create<TCell>(Expression<Func<IEnumerable<TSource>,TCell>>, Func<TFor,string>? name = null)`.
  - `PivotCells` is non-generic: it derives from `DynamicObject`, implements `IReadOnlyDictionary<string, object?>`, and keeps A-15/A-16's indexer, `Get<T>` and `[DynamicColumnsStore] Store`.

  Delegate (`Func`) parameters, not `Expression<>`, because the calls live inside an expression tree, which quotes them anyway, and that matches `g.Sum(x => …)`. Consequence: the aggregate and `forColumn` must be written inline; a captured delegate or method group is a named error (U-24 (i)–(ii)). `Create` takes an `Expression<>` because it is called outside a tree, and it is the route for a prebuilt aggregate.
- **in memory (U-28 = (a)):** `Pivot(...)` and every `PivotBuilder` member throw a named `LinqToDBException` when invoked, whatever the terminal. `PivotCell.Create` works anywhere.
- **empty-cell rule per terminal (critic round 8, objection 1):** `AsDictionary` / `AsDynamic` / `Cells` follow A-13's contract: the expander lifts a non-nullable `TCell` to `TCell?` (E-41), so an empty `SUM`/`MIN`/`MAX`/`AVG` cell reads `null` and an empty count reads `0`. `Select` splices the user's `(value, rows) => T` body; its member types are the user's, so nothing is lifted. An empty cell reads what the declared member type materializes from `NULL`: `default` for a non-nullable member, `null` for a nullable one (U-9's mechanism). The user lifts by writing `rows.Sum(x => (decimal?)x.Amount)`. The same data can therefore read `null` through `AsDictionary` and `0` through a non-nullable `Select` member. P10 records this; the XML doc on `Select` says it.
- **rejected:** keep `PivotCells<TSource,TFor>`. A DTO cannot name an anonymous `TSource`, which is why A-15 had to add the `IReadOnlyDictionary` escape.
- **rejected:** a separate store type for `AsDynamic`. It would be two store types for one cell set; measured (U-14) that one `DynamicObject` store materializes like the plain one.
- **why this:** this is the surface sdanyliv listed, and the user chose all three terminals.
- **failure mode of the choice:** four public types where today there is one type and two overloads (session-plan downside 5). Cells can no longer land in `TResult`'s own store (downside 6, P10).

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
- E-24 `Source/LinqToDB/Internal/DataProvider/PostgreSQL/Translation/PostgreSQL95MemberTranslator.cs` — D-5's 9.5-tier aggregate translator (`CreateAggregateFunctionsMemberTranslator` override). Base-PR (#5949) content, recorded by A-15.
- E-25 `Tests/Linq/Linq/BooleanTests.cs` — TO-8 FILTER-exclusion sweep. Base-PR content.
- E-26 `Tests/Linq/Linq/CountTests.cs` — TO-8 FILTER-exclusion sweep. Base-PR content.
- E-27 `Tests/Linq/Linq/GroupByTests.cs` — TO-8 FILTER-exclusion sweep. Base-PR content.
- E-28 `Tests/Linq/UserTests/Issue1564Tests.cs` — A-1's comment naming `StringAggregate`. Base-PR content.
- E-29 `Source/LinqToDB/Internal/Linq/Builder/SelectDynamicBuilder.cs` — A-14 placeholder splice; A-15: placeholder found at any depth, store built through the non-public constructor, operator-neutral errors.
- E-30 `Source/LinqToDB/LinqExtensions/LinqExtensions.SelectDynamic.cs` — A-15: identifier-character check removed, shadowing guard narrowed to fields/properties, `[InstantHandle]` on `nameSelector`, materialization comment corrected.
- E-31 `Source/LinqToDB/LinqExtensions/PivotCells.cs` — A-14 carrier type; A-15: explicit `IReadOnlyDictionary<string, object?>` (CA1710 suppressed), never-null `Values`, internal constructor, `[Pure]` `Cell`, count-cell doc.
- E-32 `Source/LinqToDB/LinqExtensions/UnpivotNulls.cs` — A-15 doc: both consumers and the multi-value default.
- E-33 `Tests/Linq/Linq/SelectDynamicTests.cs` — `SelectDynamic` coverage; A-15 round-trip and guard-message tests.
- E-34 `Source/LinqToDB/Internal/Linq/Builder/PivotSugarBuilder.cs` — A-16: builds a public `Unpivot` (non-5-arg) / `Pivot` / `SelectDynamic` call reached unevaluated inside a lambda by running it over a stand-in queryable carrying its source expression.
- E-35 `Source/LinqToDB/Internal/Common/ErrorHelper.cs` — A-16: `ErrorHelper.Pivot` message constants for the three operators.
- E-36 `Tests/EntityFrameworkCore/Tests/ToolsTests.cs` — A-16: `Pivot` / `Unpivot` directly on an EF Core `DbSet`.
- E-37 `Source/LinqToDB/LinqExtensions/LinqExtensions.PivotDynamic.cs` → renamed `LinqExtensions.Pivot.cs` — A-17: delete both top-level `Pivot` overloads, `BuildPivot`, `ReadTemplates`, `IsConstructedWith`, `IsCellCall`; add `Pivot(this IGrouping<TKey,TSource>, …)` (D-9). `BuildCell`'s lowering moves to E-41.
- E-38 `Source/LinqToDB/LinqExtensions/PivotBuilder.cs` (new) — A-17: `PivotBuilder<TSource,TFor>` and its five members (D-9). The in-memory behaviour depends on U-28.
- E-39 `Source/LinqToDB/LinqExtensions/PivotCell.cs` (new) — A-17: `PivotCell<TSource,TFor>.Create` (D-9).
- E-40 `Source/LinqToDB/LinqExtensions/PivotCells.cs` — A-17: becomes non-generic, derives from `DynamicObject` (`TryGetMember` over `Store`), and drops `Cell`/`Template`. Supersedes E-31's generic carrier.
- E-41 `Source/LinqToDB/Internal/Linq/Builder/PivotExpander.cs` (new, internal) — A-17: reads the chain from the terminal down, evaluates the inputs with `ps` resolution and records slots, validates them, and emits a `MemberInit` with `DynamicColumnInfo` bindings or a `NewArrayInit` (D-6, U-19, U-20, U-24).
- E-42 `Source/LinqToDB/Internal/Linq/Builder/Visitors/ExposeExpressionVisitor.cs` — A-17: a `VisitMethodCall` branch after the `Sql.Property` check and before `_isSingleConvert` (D-6). It has two parts:
  - a terminal on `PivotBuilder<,>` is expanded, and the branch returns **`Visit(expanded)`**, as the sibling arms do (`:104,112,157`), so `[ExpressionMethod]` members and `Sql.Property` inside cell bodies and `forColumn` are exposed (critic round 8, objection 5);
  - a non-terminal `PivotBuilder<,>` call, or `LinqExtensions.Pivot` over a grouping, that is reached directly (no terminal consumed it) is a named error (U-24 (iv)).

  The branch exposes `ResolveCompiledQueryArguments` / `RecordMaterializedArgumentSlots` / `EvaluateExpression` to the expander.
- E-43 `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuildVisitor.cs` — A-17: `VisitMemberInit`'s dynamic-binding branch: the store guard for every purpose, then the conversion for `BuildPurpose.Expression` only (D-7).
- E-44 `Source/LinqToDB/Internal/Linq/Builder/PivotSugarBuilder.cs` → `UnpivotSugarBuilder.cs` — A-17: `[BuildsMethodCall(nameof(LinqExtensions.Unpivot))]` only; `RegisterCellArguments` removed; the reader moves to E-51 (D-8). Supersedes E-34's Pivot and SelectDynamic arms.
- E-45 `Source/LinqToDB/Internal/Linq/Builder/SelectDynamicBuilder.cs`, `Source/LinqToDB/LinqExtensions/LinqExtensions.SelectDynamic.cs`, `Tests/Linq/Linq/SelectDynamicTests.cs` — A-17: removed from this branch, carried by the SelectDynamic PR (D-8). Supersedes E-29, E-30, E-33 here.
- E-46 `Source/LinqToDB/Internal/Common/ErrorHelper.cs` — A-17:
  - remove the `SelectDynamic`-only constants and the `(g, p)` / Func-form-only ones (`Error_ProjectionBuildsNoCell`, `Error_CellSetUsedMoreThanOnce`, `Error_CellSetNotAMember`, `Error_CellSetNotFromParameter`, `Error_CellSetNotBuilt`);
  - keep `Error_NoDynamicColumnsStore` for E-43, and the name-rule constants for E-41;
  - add the expander's errors:
    - terminal outside a member position;
    - receiver not a `Pivot` call;
    - a chain with no terminal;
    - a factory, `values` or template list that reads `g` or an outer parameter;
    - an aggregate or `forColumn` passed as a delegate rather than an inline lambda;
    - a `PivotBuilder` member invoked in memory (U-28).
- E-47 `Source/LinqToDB/PublicAPI/PublicAPI.Unshipped.txt` — A-17: swap the `Pivot`/`PivotCells`/`SelectDynamic` lines for D-9's surface and the `ErrorHelper.Pivot` delta. The Unpivot and `UnpivotNulls` lines survive untouched.
- E-48 `Tests/Linq/Linq/PivotDynamicTests.cs` (name kept) — A-17:
  - port the 41 tests to the new API (36 `(g, p)`, 4 Func-form, 1 mixed);
  - delete the 7 `InlinePivot*` tests, which are replaced by TO-18's ported scenarios;
  - convert `TwoNestedCellSetsThrow` and `AProjectionWithoutACellThrows` to the new contract;
  - add TO-11…TO-27;
  - house rules apply in full, since the file is rewritten wholesale.
- E-49 `Tests/EntityFrameworkCore/Tests/ToolsTests.cs` — A-17: the `Pivot` half of `PivotOperatorsOverADbSet` becomes `ctx.Products.GroupBy(…).Select(g => … g.Pivot(…) …).ToLinqToDB()` (U-21).
- E-50 `Tests/Linq/Linq/PivotTests.cs` — A-17: no API change (Unpivot only). It is the TO-28 control for E-44/E-51, and gains a mutate-in-place arm in `InlineUnpivotRereadsCapturedColumns`.
- E-51 `Source/LinqToDB/Internal/Linq/Builder/BuildTimeArgumentReader.cs` (new, internal) — A-17: `ReadArgument`, `RegisterBuildTimeValues`, `MarkGuardedValue`, `Snapshot` moved out of `PivotSugarBuilder` unchanged, except that `MarkGuardedValue`'s sentinel field reference `typeof(PivotSugarBuilder)` (`PivotSugarBuilder.cs:132`) becomes the new type; `UnpivotInfo.Parse` (`UnpivotBuilder.cs:194-201`, under E-10) switches its four calls to it. Byte-identical copy in the SelectDynamic PR (D-8).
- E-52 `Tests/Linq/Linq/DynamicColumnsTests.cs` — A-19 (records A-17's TO-23 edits, never listed): the six `ProjectionBindingDynamicColumns*` / `ProjectionWithoutDynamicBindingsCreatesAStorePerRow` core tests; E-57 repoints its error constant.
- E-53 `Source/LinqToDB/Internal/Linq/Builder/UnpivotBuilder.cs` — A-19: `GetColumnName` returns the member path and the leaf member name; `GetPhysicalColumnNames` looks each path up, falls back to the leaf, and keeps the path for an unmapped column whose leaf another column also reads (SC-16). `ReadCellAsColumn` turns a `Get<T>` / converted-indexer selector into the `DynamicColumnInfo` access `Sql.Property` builds, before naming and lowering.
- E-54 `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuildVisitor.cs` — A-19 (critic round A-19 moved it out of `ExposeExpressionVisitor`, whose arms were reverted): `TryGetPivotCellRead` in `VisitMethodCall` (`Get<T>`, and a bare indexer, which `OrderByBuilder`'s `Unwrap` leaves) and `VisitUnary` (converted indexer), for `BuildPurpose.Sql` only, a receiver not evaluable on the client and an evaluable name; it builds the `DynamicColumnInfo` member access (SC-17).
- E-55 `Source/LinqToDB/LinqExtensions/PivotCells.cs` — A-19: `[SqlQueryDependent]` on `Get<T>`'s and the indexer's `name`; the class remark names the SQL positions, the projection's in-memory read and the `IReadOnlyDictionary` limit.
- E-56 `Source/LinqToDB/Internal/Linq/Builder/BuildTimeArgumentReader.cs` — A-19: trimmed to the quote, `NewArrayInit` and evaluated-value branches (`Snapshot` kept); supersedes E-51's "byte-identical" — #6110 adds the rest beside its callers.
- E-57 `Source/LinqToDB/Internal/Common/ErrorHelper.cs` and its callers (`ExpressionBuildVisitor.cs`, `PivotExpander.cs`, `LinqExtensions.Pivot.cs`, `LinqExtensions.Unpivot.cs`, `PivotBuilder.cs`, `PublicAPI.Unshipped.txt`, `PivotDynamicTests.cs`) — A-19: `Error_QueryMarkerInvoked` → `ErrorHelper`; `Error_DynamicColumnShadowsMember` / `Error_NoDynamicColumnsStore` → new `ErrorHelper.DynamicColumns`; the store message reworded for the initializer it guards. Supersedes E-46's placement of those three.
- E-58 `Source/LinqToDB/Internal/Linq/Builder/PivotExpander.cs` — A-19: `GetConstructor` → `GetConstructorEx` (master's ban list).
- E-59 `Tests/Linq/Linq/PivotTests.cs`, `Tests/Linq/Linq/PivotDynamicTests.cs` — A-19: TO-29 / TO-30 tests.
- E-60 `Source/LinqToDB/Internal/Expressions/SqlQueryDependentValueAttribute.cs` (new, internal) — A-20: a `SqlQueryDependentAttribute` that compares an argument reading a `ParameterExpression` structurally and any other by value; it replaces E-55's `[SqlQueryDependent]` on `Get<T>`'s and the indexer's `name` (SC-17).
- E-61 `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuildVisitor.cs` — A-20: `TryGetPivotCellRead` reads the cell as an `object`-typed `DynamicColumnInfo` access converted to the read's type (the converted-indexer cast path) and returns a named `Error_PivotCellNotFound` when the read resolves to no SQL; supersedes E-54's typed access.
- E-62 `Source/LinqToDB/Internal/Linq/Builder/UnpivotBuilder.cs` — A-20: `ReadCellAsColumn` replaces only the `Get<T>` call or the conversion directly over the indexer, keeping the selector's other conversions; supersedes E-53's strip-and-rewrap.
- E-63 `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuilder.SqlBuilder.cs` — A-20: `Project`'s `MemberInit` branch retargets a `DynamicColumnInfo` declared on a type the constructed type implements (an interface-typed member) to the constructed type.
- E-64 `Source/LinqToDB/Internal/Common/ErrorHelper.cs`, `Source/LinqToDB/PublicAPI/PublicAPI.Unshipped.txt`, `Source/LinqToDB/LinqExtensions/LinqExtensions.Unpivot.cs`, `Source/LinqToDB/LinqExtensions/PivotCells.cs` — A-20: `Error_UnpivotColumnSelector` names the cell-read forms; the selector overloads' `resultSelector` doc states the naming rule; the `PivotCells` remark lists every SQL position, the cast to `T`, the named error and the interface cast.
- E-65 `Tests/Linq/Linq/PivotDynamicTests.cs`, `Tests/Linq/Linq/PivotTests.cs`, `Tests/Linq/Linq/DynamicColumnsTests.cs`, `Tests/EntityFrameworkCore/Tests/ToolsTests.cs` — A-20: TO-35…TO-41, TO-34's value arm, and the round-4 layout pass (one-line and nested chains, reason lines, `Assert.That` exception form, the `#region`).
- E-66 `Source/LinqToDB/Internal/Linq/Builder/UnpivotBuilder.cs` — A-21: `ReadCellAsColumn` reads the cell as an `object`-typed `DynamicColumnInfo` access, converted to `T` for `Get<T>` and under the selector's own conversions for an indexer, as E-61 does in a filter (supersedes E-62's typed access). `GetColumnName`'s parent walk steps through conversions, so a cast receiver keeps its path (SC-16).
- E-67 `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuilder.SqlBuilder.cs` — A-21: `Project`'s `SqlGenericConstructorExpression` branch retargets a `DynamicColumnInfo` declared on a type the constructed type implements, as E-63's `MemberInit` branch does (the `Concat` path).
- E-68 `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuildVisitor.cs`, `Source/LinqToDB/Internal/Common/ErrorHelper.cs` — A-21: `TryGetPivotCellRead` reads through `ReadPivotCellAs`. That helper resolves the cell in `Sql` purpose: no column gives `Error_PivotCellNotFound`; a resolved type with no CLR conversion to `T` (`Expression.Convert` fails) gives the new `Error_PivotCellType`; otherwise it casts the resolved column in SQL. Both errors are critical. The mark makes a grouping key report the named absent-cell message (measured). A top-level aggregate's selector still reports "could not be converted": `IsCritical` is read only for set projections (`ExpressionBuildVisitor.cs:3542`, `DeclinedForSetProjection`), and the aggregate path retries past the error. That arm is narrowed (P10) rather than reshaping engine error handling. Critic round A-21 replaced the first pass's `IsScalarType` gate, a closed list, with the conversion check.
- E-69 `Tests/Linq/Linq/PivotDynamicTests.cs` — A-21: TO-38's rewrite, TO-42…TO-51, a fractional `CategorySales` data set and a row type with two interface-typed members.
- E-70 `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuildVisitor.cs` — A-21: `VisitUnary`, in the `Sql` and `Expression` purposes, reads a method-less `Convert` / `ConvertChecked` through `ReadPivotCellAs` (E-68). Any other pass returns the node unchanged. An instrumented run (the branch throwing its purpose) found that only `Extract` reaches it, in TO-40, TO-49's `Get<Uri>` arm and TO-50. Falling through to `base.VisitUnary` there measured TO-40 red on all three providers ("Rewriting child expression from type 'System.Object' …"). Rebuilding the conversion over the visited operand (the `b0194aceb` form) measured identical to returning the node on all 133 `PivotDynamicTests` cases, the SQL-text test included, so the simpler form is kept. It applies when the conversion is over an `object`-typed `DynamicColumnInfo` declared on `PivotCells` or on an interface it implements, and the receiver is not client-evaluable. Such an interface is `IReadOnlyDictionary<string, object?>` and its bases, reached through `Sql.Property` over an interface-typed member. `DynamicObject` and `object` are not admitted (close round, objection 2). Re-check objections C and D set the purpose gate and the interface admission, covered by TO-40, TO-48, TO-49, TO-50 and TO-51. The read therefore gets the same SQL cast and named errors as a filter's. Without it, the projection resolves the access to the cell's own type and the BCL's `VisitUnary` validation rejects that ("Rewriting child expression from type 'System.Object' to type 'decimal?' is not allowed" / "… calls operator method 'op_Explicit' …", measured on TO-40 and TO-42 with E-66 alone). The `Sql` purpose hits the same validation through the Unpivot `!= null` filter ("No coercion operator", measured for `Get<Uri>`). `ReadPivotCellAs` casts the resolved column, not the access, so it does not re-enter this arm. Critic round A-21 replaced the first pass, a client-side `Expression.Convert` excluded from `Sql`. Two attempts before this one failed. E-62's typed access plus a `Project`-level conversion of a matched binding (`AsDynamicColumnType`) left TO-42 red unchanged, so the read does not resolve through either `Project` constructor branch's return; it was reverted.
- E-71 `Source/LinqToDB/Internal/Expressions/SqlQueryDependentValueAttribute.cs` — A-21: `ExpressionsEqual` always compares structurally; the value branch E-60 kept for a non-row-dependent argument is removed (critic round A-20, objection 8: no witness; the always-structural mutant is green on TO-33…TO-37).
- E-72 `Tests/Linq/Linq/PivotDynamicTests.cs` — A-22: TO-52, the sub-query-wrap reader shape the postmortem re-run found unpinned.

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

A-17 rows, from two scouts on the worktree at 4dddec407 (and `git diff 4dddec407 origin/master` for drift):

- `BuildSelectDynamic|SelectDynamicCore` across `Source/` — 2 callers: `LinqExtensions.SelectDynamic.cs:87` and `LinqExtensions.PivotDynamic.cs:235`; the marker's only consumer is `SelectDynamicBuilder.cs:13` — covered by E-37, E-45
- `PivotCells<,>` placeholder logic in `SelectDynamicBuilder.cs` (`:40-43,61-70,81-85,96-99`) — Pivot-only, leaves with the file — covered by E-45
- `PivotSugarBuilder` branches by operator, read from `PivotSugarBuilder.cs:16-161`: quote and array-init branches serve all three operators; the lambda branch (`RegisterBuildTimeValues` / `MarkGuardedValue`) serves only `SelectDynamic`'s `nameSelector` and Pivot's `cells`; `RegisterCellArguments` is Pivot-only. `UnpivotInfo.Parse` calls `ReadArgument` at `UnpivotBuilder.cs:194,195,200,201` — covered by E-44, E-51
- `ErrorHelper\.Pivot\.\w+` repo-wide — 22 constants (`ErrorHelper.cs:169-193`), referenced by operator per the scout table: 6 Unpivot-only, 2 SelectDynamic-only, 5 `(g,p)`/Func-form-only, 4 Pivot name rules, `Error_PivotCellNotFound`, 3 shared (`Error_QueryMarkerInvoked` also used by `UnpivotMulti`, `Unpivot.cs:262`) — covered by E-46
- `PublicAPI.Unshipped.txt` PR lines — 40: 22 `ErrorHelper.Pivot` consts + class, 5 `PivotCells`, 3 `UnpivotNulls`, 2 `Pivot`, 1 `SelectDynamic`, 6 `Unpivot` — covered by E-47
- `PivotCells|SelectDynamic|\.Pivot\(|Pivot<` repo-wide outside `bin`/`obj` — no hit outside the PR's own files and `.claude/` (no LINQPad, analyzer, EF, template or `*.md` consumer) — out-of-scope; the corpus hits (`code-design.md:114,323`, `dead-ends.md:65,67`, `github-authoring.md:143`, `work-plan.md:226`) are history, not instructions to update
- `IMemberConverter` implementations / `ConvertMember(` / `[ExpressionMethod]` lookup — none can match a `PivotBuilder<,>` method (U-17) — out-of-scope
- `ExposeExpression\(|ExposeExpressionVisitor|ConvertExpressionTree\(|ConvertSingleExpression|isSingleConvert` — expose entry points `Query{T}.cs:72` (in an interceptor loop), `CompiledTable{T}.cs:110`, `Internals.cs:47`, `AssociationHelper.cs:68,237,387`, `TableBuilder.cs:141,192`, `ExpressionBuilder.cs:538-543`, `ExpressionBuilder.SqlBuilder.cs:235-242` — covered by E-42 (idempotence, U-18) and TO-24 (re-expose through the EF interceptor)
- `IQueryExpressionInterceptor` implementations — EF (`LinqToDBForEFToolsImplDefault.cs:608-611` → `TransformExpressionVisitor.cs`, `[NotParameterized]` wrapping at `:288-317`) and F# (`FSharpQueryExpressionInterceptor.fs:413-419`, not audited) — covered by E-49 for EF (with the P3 `[NotParameterized]` anti-goal); F# out-of-scope, narrowed in P10 (U-22)
- `MemberInitExpression|VisitMemberInit|ExpressionType\.MemberInit` + `ParseGenericConstructor(` + `ForSetProjection` across `Internal/Linq/Builder` — Expression + `ForSetProjection` callers reach the non-`Sql` `VisitMemberInit` path (`MergeProjectionHelper.cs:49`, `ExpressionBuilder.EagerLoadUnion.cs:203,313,471,904`); every other `MemberInit` → generic-constructor site uses `ParseGenericConstructor` (list in U-27); finalization (`ExpressionBuilder.QueryBuilder.cs:197-238,476-491`) constructs only generic constructors and passes a raw `MemberInit` through untouched — covered by E-43, TO-23, TO-26
- `DynamicColumnInfo(` / `IsDynamicColumnProperty` under `Source/` — constructed at `MemberHelper.cs:150` (`Sql.Property`), `SelectDynamicBuilder.cs:57`, `EFCoreMetadataReader.cs:963,966`; **no existing code binds one in a `MemberBinding`**, so E-43's branch is dead for every tree linq2db builds today except the expander's — covered by E-43; a regression in it can reach only hand-built trees and pivots
- `EntityConstructorBase.cs:547-638` — dynamic assignments dropped silently with no `DynamicColumnSetter` (`:602-610`) — covered by E-43's guard (U-23)
- `TryEvaluateArguments` (`ExposeExpressionVisitor.cs:283-309`) — first-argument-only defect at `:298` — out-of-scope (U-26)
- `ProcessIQueryable` / `ProcessSourceQueryable` — `LinqInternalExtensions.cs:140-143`, EF hook `LinqToDBForEFTools.cs:56-77`; no EF `IMethodCallTranslatorPlugin` / `IQueryTranslationPreprocessor` registration (`LinqToDBOptionsExtension.cs:49-51`) — covered by E-49 and P10 (U-21)
- Drift on `origin/master` for E-42/E-43's files — `ExposeExpressionVisitor.cs` gains `ConvertRawSqlString` after `ConvertMethod` (#6003/#6008), after the insertion point; `ExpressionBuildVisitor.cs` +758 lines (#5983), `VisitMemberInit` untouched but shifted ~+34; `EntityConstructorBase.cs` unchanged — deferred: absorbed by the master sync that precedes implementation (stack: master → #5949 → #5708); E-42/E-43 are written against the synced files
- The 25 `[IncludeDataSources(TestProvName.AllSQLite)]` attributes in the Pivot files with no reason line above (`test-diff-sweep.ps1`, `narrowedSets`) — covered by E-48 (each ported narrowed test states its reason, `testing.md` → *A narrowed provider set is a claim*)

A-19 rows, searched on the worktree at `2cad4e701`:

- `GetColumnName|GetPhysicalColumnName` under `Source/` — callers only in `UnpivotBuilder.cs:117,149,156`; the entity-descriptor lookup keyed by member path is the one `b201268c9` added — covered by E-53
- `nameof\(PivotCells\.Get\)|"get_Item"` under `Source/LinqToDB/Internal/Linq/Builder` — E-54's `TryGetPivotCellRead` callers in `ExpressionBuildVisitor` (`VisitMethodCall`: `Get<T>` and a bare indexer; `VisitUnary`: a converted indexer) and E-53's `ReadCellAsColumn` in `UnpivotBuilder`; each builds the `DynamicColumnInfo(typeof(PivotCells), T, name)` access that `MemberHelper.cs:150` builds for `Sql.Property` — covered by E-53, E-54. Positions: `OrderByBuilder.cs:114` builds keys with `BuildPurpose.Sql` after `Unwrap()` strips the key's conversion (hence the bare-indexer arm); `Where` predicates and Unpivot's `!= null` filter are `Sql`; projections are `Expression` and stay in memory. A receiver typed `IReadOnlyDictionary<string, object?>` or `dynamic`, or a cast `((PivotCells)r.Cells)` over one, is not translated (probe 7: "could not be converted" under the expose rewrite and with it off; unprobed under the build-visitor E-54) — narrowed in E-55's remark
- `[SqlQueryDependent]` readers — `SqlQueryDependentAttributeHelper.GetQueryDependentAttributes` in `ExposeExpressionVisitor.VisitMethodCall` (`:184`) applies it to any method; `PrepareForCache` (`SqlQueryDependentAttribute.cs:86-120`) evaluates only an evaluable argument, so a row-dependent name stays as written (and E-54 declines it) — covered by E-55, TO-33

A-20 rows (review round 4, three `code-reviewer` passes at `bf00c3547`, each claim probed on SQLite.Classic direct + remote with the SQL-position translation on and off):

- `SqlQueryDependentAttribute` readers, `git grep -n SqlQueryDependent origin/pr/5708 -- Source` — `ExposeExpressionVisitor.HandleSqlDependentParameters` (`:184/:204`, folds an evaluable argument), `EqualsToVisitor` (`:382`, the query-cache compare: `ExpressionsEqual`, whose base evaluates both sides — the row-dependent throw), `CompiledQuery.cs:104` (compiled-slot keying) — covered by E-60 (overrides `ExpressionsEqual` only), TO-35, TO-36, TO-37. `ExpressionBuilder.QueryBuilder.cs:474` (`RegisterExtensionAccessors`) and `QueryExtensionBuilder.cs:109` also read the attribute but serve extension builders, which no `PivotCells` read reaches (critic round A-20)
- `DynamicColumnInfo` equality and resolution, `DynamicColumnInfo.cs:51-70` (Name + `DeclaringType`) and `ExpressionBuilder.SqlBuilder.cs` `Project` — the `MemberInit` branch (`GetMemberEx`, then `IsSameOrParentOf`) is where an interface-declared read meets the bindings; the generic-constructor branch was tried and is not reached by TO-41's shape (removing it left TO-41 green) — covered by E-63. The retarget fires only for a `DynamicColumnInfo` whose declaring type is a parent of the constructed type, which before E-63 never matched a binding
- `TryGetPivotCellRead` positions, `BuildPurpose.Sql` callers — `OrderByBuilder.cs:114`, `Where` predicates, `DistinctBuilder.cs:47` (builds the projection as SQL), aggregate selectors and grouping keys; probes D/E measured `Where` and `Distinct` — covered by E-61, TO-38, TO-39
- Client-held cells copied into a query row then filtered (`t.Select(x => new { Cells = held }).Where(x => x.Cells.Get<…>(…) > 1)`) — "could not be converted" with the translation off, so not a regression; now the named error of E-61 — out-of-scope (no shape on master reads it)
- `ReadArgument\(` under `Source/` — `UnpivotBuilder.cs:196,197,202,203`, `UnpivotSugarBuilder.cs:27`; every argument is a quote, an array initializer or an evaluated array/enum — covered by E-56
- `ErrorHelper\.Pivot\.(Error_QueryMarkerInvoked|Error_DynamicColumnShadowsMember|Error_NoDynamicColumnsStore)` repo-wide — 5 source sites (`ExpressionBuildVisitor.cs:1081`, `PivotExpander.cs:155`, `LinqExtensions.Pivot.cs:51`, `LinqExtensions.Unpivot.cs:262`, `PivotBuilder.cs:91`) and 4 test sites (`DynamicColumnsTests.cs:470`, `PivotDynamicTests.cs:875,1817,1836`); the same two messages in `ErrorHelper.SelectDynamic` on `origin/feature/4992-select-dynamic` (`LinqExtensions.SelectDynamic.cs:133,171`) — covered by E-57, and on #6110 by its own stacked merge
- `GetConstructor\(` in the branch's files — `PivotExpander.cs:27`, banned by master's `BannedSymbols.txt` after the 2026-11-25 master merge (RS0030 in the Release build) — covered by E-58

A-21 rows (critic round A-20's leads, probed at `8f2029f35` on SQLite.Classic + DuckDB, direct + `LinqService`):

- `ReadCellAsColumn` / `GetColumnName` (`UnpivotBuilder.cs:154-235`) — the only Unpivot readers of a cell; the column's lambda feeds both the projection branch and the `!= null` filter (`:125`, `:133`), so the typed read reaches both, and `Project` (`ExpressionBuilder.SqlBuilder.cs`) resolves it against the pivot's binding. `VisitNew` (`ExpressionBuildVisitor.cs:1072`) rebuilds the result's constructor over what it resolved to — covered by E-66, E-70, TO-42, TO-43
- `VisitUnary` reach of E-70: a method-less conversion over an `object`-typed `DynamicColumnInfo` declared on `PivotCells` or an interface it implements (not `DynamicObject`), with a receiver from the query, in `Sql` / `Expression` purpose. Under `Traverse`, `Expand`, `Extract`, `Root`, `AggregationRoot`, `SubQuery` and `Table` it forces no `Sql` build and no named error. It returns the node unchanged. Measured (instrumented run): only `Extract` reaches it, from TO-40, TO-49 and TO-50. Returning the node and rebuilding it measured identical on those three. The reason is that `SelectBuilder.cs:39` discards the `Extract` result (close round, objection 1). Where the result is consumed (`SelectManyBuilder.cs:97`, `UpdateBuilder.cs:199`, `MergeProjectionHelper.cs:61`), the node returned as written is what the building pass meets. TO-51 is green on the `SelectMany` route; `Update` / `Merge` over a converted cell read are not tested. `PivotCells`-declared accesses are built only by `ReadPivotCellAs`'s callers (E-61 / E-68, which pass the access directly and never wrap it in a `Convert` that reaches `VisitUnary`), by E-66 (Unpivot) and by `Sql.Property<object>(x, name)` under a cast, whose access is declared on the receiver's static type (`MemberHelper.cs:150`). An entity's dynamic column is declared on the entity, so it is out of reach. A member typed `IReadOnlyDictionary<string, object?>`, `IReadOnlyCollection<…>`, `IEnumerable<…>` or `IEnumerable` that is not a pivot's is in reach, and reads `Error_PivotCellNotFound` (critic round A-21 final delta, objection 5; unprobed, no test) — covered by E-70, TO-40, TO-42, TO-45, TO-46, TO-48, TO-49, TO-50, TO-51
- `Project`'s two constructor branches (`ExpressionBuilder.SqlBuilder.cs:1378-1449` generic constructor, `:1611` `MemberInit`) — `Concat` reaches the generic one (probe: `AsSubQuery()` and `Take` read `A`, `Concat` "could not be converted") — covered by E-67, TO-44
- `TryGetPivotCellRead` callers (`VisitMethodCall` `Get<T>` / bare indexer, `VisitUnary` converted indexer) — a grouping key and an aggregate selector read a present cell correctly (`GroupBy` and `Sum` probes) and an absent one as "could not be converted"; `IsCritical` is read only at `ExpressionBuildVisitor.cs:3542` (`DeclinedForSetProjection`) — covered by E-68, TO-45
- Provider conversion semantics for a fractional cell read as `int` — the cast is linq2db's own SQL conversion of a column: the engine's `CAST` on SQLite, and a `FLOOR` before the cast where the provider emulates truncation (`FloorBeforeConvert`: DuckDB, MySQL, Firebird, DB2, Oracle, PostgreSQL, SQL Server); SQLite and DuckDB both read 20.6 as 20 (critic round A-21 re-check, objection A) — covered by E-68, TO-38, TO-46

A-22 row (the postmortem's reader-shape re-run):

- `AsSubQuery` in `PivotDynamicTests.cs` — no call site before `b29e48f24`, so no cell reader was tested under a wrap; `AsSubQueryBuilder.cs:15-21` always wraps the sequence (`DoNotRemove`), so an outer read resolves through `AsSubqueryContext` (critic round A-22) — covered by E-72, TO-52

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

A-17 obligations. `conventions:` *Test layout*, *A narrowed provider set is a claim* and *Gating an assertion failure* (`testing.md`) bind every test below.

- TO-11 The 41 ported `PivotDynamicTests` (values asserted directly, not through `AssertQuery`, whose expected side runs in memory and would hit U-28's throw) on every `[DataSources]` provider their predecessors ran on, direct + `LinqService`, with unchanged values and gates (`ThrowsRequiredOuterJoins(AllAccess)` on the distinct-count cell, `#5954` Access-Jet on `PivotsAvgCell`, `#6028` on the production-shape cache test). — proof: characterization, plus a **baselines control**: a pre/post snapshot of the local baselines tree over the ported tests on SQLite.Classic + DuckDB, as A-14 measured. Expected: changed SQL **0** for every ported test whose query shape is unchanged; any change is read for cause before acceptance. The renamed tests' hashes are compared as A-14 did.
- TO-12 Query syntax: `from e in … join a in … on … group new { e, a } by e.Dept into g select new { g.Key, Hours = g.Pivot(x => x.a.Kind, kinds).Cell(rows => rows.Sum(x => x.a.Hours)).AsDictionary() }`, `[DataSources]`. — proof: red→green; red today because no top-level operator can be written inside query syntax (compile-level red, stated as such). Discriminating input: two departments with disjoint kinds, so a cell reading the wrong group is visible.
- TO-13 Two pivots in one projection (by year, by region), `[DataSources]`. — proof: red→green; red today, where `TwoNestedCellSetsThrow` pins `Error_CellSetUsedMoreThanOnce`. That test is converted to this assertion. Discriminating input: a region value equal to a year's string form, so a column-name collision across the two stores would surface.
- TO-14 `Select((year, rows) => new { Year = year, Amount = rows.Sum(x => (decimal?)x.Amount), Note = rows.Max(x => x.Note) })`, `[DataSources]`: count = value count, order = value order, an empty cell reads `null` through the user's own lift. Plus a non-nullable member `rows.Sum(x => x.IntValue)` reading `0` for an empty cell, which pins D-9's rule rather than A-13's. — proof: red→green (no current overload can express it), with the non-nullable arm a characterization of D-9.
- TO-15 `AsDynamic()`: `((object)row.Cells.Y2010).ShouldBe(…)` and a missing name returning `false` from `TryGetMember` (a `RuntimeBinderException`), on SQLite + `LinqService`. — proof: red→green.
- TO-16 `Cells(templates)` with a template list built conditionally at run time (`includeNotes`), plus a template whose aggregate is an `Expression<>` held in a variable. — proof: characterization of today's Func-form capability (`PivotsMultipleCellsIntoUserType`) on the new API.
- TO-17 Direct-path cache identity, `[QueryCacheTest]`, SQLite: same inputs → 1 miss; widened value set → miss; list mutated in place → miss and new cells; captured name-prefix change → miss and new names; value-blind names over two value sets → a miss each, each reading its own value. — proof: control; the mutation is an expander that memoizes its expansion per call-site tree (keyed on the un-expanded node), which must turn the mutated-list and prefix arms red.
- TO-18 Sub-query cache identity: every scenario of the 7 deleted `InlinePivot*` tests (captured values, static and instance value-set methods, list mutated in place, guarded name capture `y => y > 3000 ? cfg!.Prefix : "V"` with `cfg == null`, runtime cell set, name-factory capture) re-expressed with `g.Pivot` inside `Any` / a correlated `Select`. — proof: characterization of A-16's behaviour. **Plus one red→green:** the guarded-capture arm must not throw and must not evaluate `cfg!.Prefix` for values below 3000. A counter in the factory's guarded branch reads 0, where A-16's eager evaluation read it at build *and* at every lookup.
- TO-19 Compiled-query grid (U-19), SQLite, `[QueryCacheTest]`. Each cell calls the compiled delegate with the value set changed and then restored, and asserts rows **and** build identity through `GetCompiledQueryInfo()`: `ShouldNotBeSameAs` across different value sets, `ShouldBeSameAs` for a repeated one. That is master's instrument (`FromSqlTests.FromSql_Compiled_ArgumentArray`), available after the master sync. Every cell compiles a `Func<…, IQueryable<T>>` and enumerates outside the delegate: `GetCompiledQueryInfo` reads the returned queryable's `Info` (master `Tests/Base/QueryUtils.cs:141-152`, set by `CompiledTable{T}.Create`), which an `Execute`-shaped delegate does not expose. `GetCacheMissCount` cannot see a `CompiledTable` build: it counts only `Query{T}.cs:194` (critic round 8, objection 2). Shapes compare within a shape only: on master, `DependentArgumentValues.ValuesEqual` treats `int[]` vs `List<int>` as different by type. Cells: origin {compiled-query argument slot, closure captured by the compiled lambda, literal array in the lambda} × shape {`int[]`, `List<int>`, empty}; plus `null` from a slot, which must be a named error rather than a replayed build; plus a **mixed** cell (`slotArray ?? capturedList`). — proof: red→green per slot cell under the mutation "drop `RecordMaterializedArgumentSlots` from the expander", which must replay the first call's columns; closure and literal cells are controls.
- TO-20 Census, not a test: on the branch diff, no `IQueryable`-receiver `Pivot`, no `PivotCells<`, no `SelectDynamic`, no `nameof(LinqExtensions.Pivot)` in a `[BuildsMethodCall]`; `PublicAPI.Unshipped.txt` matches the code under a Release `-p:RunApiAnalyzersDuringBuild=true` build (0 RS0016/RS0017). — proof: control.
- TO-21 In memory (U-28 = (a)): `group.Pivot(…)` over an `Enumerable.GroupBy` result, and each terminal, throw the named `LinqToDBException`; `PivotCell.Create` outside a query does not throw. — proof: red→green (no `PivotBuilder` exists before E-38).
- TO-22 Composition after the pivot (`ComposesAfterAConstantPivot`, `ComposesOverANestedCell`, ported): `Where`/`OrderBy` over `Sql.Property(r.Cells, …)` emits `HAVING` / `ORDER BY` over the cell, and an unused cell is pruned. — proof: characterization (U-13 measured the composed shape).
- TO-23 Core-layer test, outside the Pivot fixtures (`Tests/Linq/Linq/DynamicColumnsTests.cs`, the owner of dynamic-column behaviour): a hand-built `GroupBy(…).Select` whose projection is a `MemberInit` binding `DynamicColumnInfo`s materializes into the store; the same over a type with no `[DynamicColumnsStore]` throws `Error_NoDynamicColumnsStore` (use `DynamicColumnsTests.cs:403-417`'s `PersonWithDynamicStore` / `PersonWithoutDynamicStore`). Plus the four other round-8 cells as core cases: constructor-argument placement, zero bindings, `Concat`, composition. — proof: red→green, measured red (U-13, U-14 round-8 control: plain, constructor-argument and store-less fail on the unfixed engine). **Plus a misfire sweep:** `DynamicColumnsTests`, `SelectTests`, `ConcatUnionTests` and `EagerLoadingTests` green on SQLite.Classic before and after E-43. No existing tree binds a `DynamicColumnInfo` (P7), so this sweep shows only that the predicate does not fire elsewhere; it cannot go red for E-43's conversion.
- TO-24 EF Core (E-49): the `ToLinqToDB()` form on EF10 SQLite.MS returns one row per supplier with both cells. Without `ToLinqToDB()`, EF's own error is asserted by type **and** by a message fragment naming the untranslatable `Pivot` call, since `InvalidOperationException` alone is EF's type for every untranslatable call. The requirement is pinned rather than documented only. — proof: characterization + the interceptor's re-expose path (U-18).
- TO-25 Reader-shape grid (U-24), SQLite: one assertion per shape, including round 8's (i)–(v). (i)/(ii) a captured-`Func` aggregate and `forColumn` assert the named error; (iii) correlated `values` asserts the named error; (iv) a chain with no terminal asserts the named error; (v) an `[ExpressionMethod]` member in the aggregate body plus `Sql.Property` in `forColumn` return correct cells (red if E-42 returns the expansion un-visited). A shape that must throw asserts the named message. — proof: red→green for any shape that fails on first run (each failure gets a fix or a named error, never a skip).
- TO-26 Projection paths (U-27): a pivot projection under `Concat` with a second pivot over the same values, and a pivot inside an eager-loaded collection (`db.Categories.Select(c => new { c.Id, Y = c.Sales.GroupBy(…).Select(g => g.Pivot(…)…).ToList() })`), on SQLite + PostgreSQL (`APPLY`/`LATERAL`). — proof: characterization for the `Concat` arm, because U-14's round-8 control measured it passing on the unfixed engine; red→green for the eager-load arm if it fails with E-43's conversion removed; it is unprobed, and the `EagerLoadUnion` sites pass `BuildPurpose.Expression`, so they reach the conversion.
- TO-27 Empty-cell contract (`AnEmptyCellOverANonNullableColumnReadsNull`, `AnEmptyCountCellReadsZero`, `AnEmptyValueSetYieldsNoCells`), ported to the `Cell`-fed terminals (`AsDictionary`, `AsDynamic`, `Cells`). `Select`'s empty-cell rule is D-9's and is pinned by TO-14. `AnEmptyValueSetYieldsNoCells` also covers zero bindings (U-14 round 8). — proof: characterization; plus the D-4 mutation (drop the lift in E-41), which must turn the non-nullable arm red on each `Cell`-fed terminal.
- TO-28 `PivotTests` (26 Unpivot tests, including the 5 `InlineUnpivot*` cache tests) green before and after E-44/E-51 on SQLite.Classic + DuckDB + `LinqService`. — proof: control, with two mutant/witness pairs: dropping the `MarkAsValue` on `ReadArgument`'s evaluated-value branch must turn `InlineUnpivotRereadsColumnNamesFromAMethod` red, and dropping `Snapshot` must turn `InlineUnpivotRereadsCapturedColumns` red. That test (`PivotTests.cs:345-360`) only reassigns `cols`, so E-50 **extends it with a mutate-in-place arm** (`cols[0] = x => x.Q3`); without the arm, `Snapshot` cannot reach it. Critic round 8: `Snapshot` alone does not reach the method-result witness.

A-19 obligations. `conventions:` as A-17's.

- TO-29 `UnpivotsTheCellsUnderTheirOwnNames` (pivot cells via `Sql.Property`) and `UnpivotNameColumnOfAProjectedMemberUsesTheMemberName` (`x => x.Inner.Q1` over a projection), `[DataSources]`, with `UnpivotNameColumnUsesTheNestedColumnsName` as the mapped-complex control. — providers: `[DataSources]`, run on SQLite.Classic/MS + DuckDB (direct + `LinqService`), the rest via CI — proof: red→green; red at `608048304` (the head before E-53) with `Cells.Y2000` / `Inner.Q1`.
- TO-30 `ComposesThroughTheCellsMembers` (`Where(Get<decimal?>("Y2010") > 16)` keeps `A` only; `OrderBy((decimal?)cells["Y2000"])` reads `B, A`, against the grouping order `A, B`) and `UnpivotsTheCellsThroughTheIndexer`, `[DataSources]`. — providers: `[DataSources]`, run on SQLite.Classic/MS + DuckDB (direct + `LinqService`), the rest via CI — proof: red→green; red before E-54 with "could not be converted" and `Error_UnpivotColumnSelector`. Separates: a wrong cell (`Y2000 > 16` keeps none), a no-op filter (keeps both) and a no-op ordering (`A, B`).
- TO-31 `CapturedCellsAreAValue`, `[DataSources]`: cells read back and captured by a later `Where` (`Get<T>` and converted indexer) select row 2. — providers: `[DataSources]`, run on SQLite.Classic/MS + DuckDB (direct + `LinqService`), the rest via CI — proof: red→green against critic round A-19's first E-54 (expose rewrite), which threw "Dynamic column getter is not to be called."; green with E-54 off.
- TO-32 `AProjectedCellReadKeepsItsInMemoryContract`, `[DataSources]`: projected absent name (`Get` and indexer) → `null`, `Get<int>` / `Get<string>` over a decimal cell → `0` / `null`, a present cell → its value. — providers: `[DataSources]`, run on SQLite.Classic/MS + DuckDB (direct + `LinqService`), the rest via CI — proof: red→green against the expose rewrite (threw; `Get<int>` read 20); green with E-54 off.
- TO-33 `ACapturedCellNameKeysTheQuery`, `[DataSources]`: `Where(Get<decimal?>(name) > 12)` reads no group for `Y2000` and `A, B` after the capture changes to `Y2010`. — providers: `[DataSources]`, run on SQLite.Classic/MS + DuckDB (direct + `LinqService`), the rest via CI — proof: control; mutation: drop `[SqlQueryDependent]` from `Get<T>`'s `name`, which must replay the first column.
- TO-35 `ARowDependentCellNameReadsOnEveryExecution`, `[DataSources]` — providers: `[DataSources]`, run on SQLite.Classic/MS + DuckDB (direct + `LinqService`), the rest via CI: a projected `Get<T>` and indexer whose name reads the row, executed twice, both read `10, 15`. — proof: red→green; red at `bf00c3547` (second execution threw "variable 'r' … not defined", also with the SQL-position translation off).
- TO-36 `ACapturedCellNameKeysAnIndexerRead`, `[DataSources]` — providers: `[DataSources]`, run on SQLite.Classic/MS + DuckDB (direct + `LinqService`), the rest via CI: TO-33 through `(decimal?)cells[name]`. — proof: control; the attribute-drop mutation of TO-33 applied to the indexer's `name`.
- TO-37 `ACompiledCellNameKeysTheBuild`, `[IncludeDataSources(true, AllSQLite)]` — providers: SQLite (compiled-query identity is provider-agnostic): a compiled query's `Get<T>(name)` argument reads none for `Y2000` and `A, B` for `Y2010`. — proof: characterization.
- TO-38 `AGetInASqlPositionReadsTheCellAsItsType`, `[DataSources]` — providers: `[DataSources]`, run on SQLite.Classic/MS + DuckDB (direct + `LinqService`), the rest via CI. A-21 rewrite (critic round A-20, objection 1): over a fractional cell (`A` Y2010 = 20.6), `Select(Get<int>("Y2010")).Distinct()` equals the same provider's `(int)` read of the same amounts. The control is `t.Where(x => x.Year == 2010).Select(x => (int)x.Amount!.Value).Distinct()`, which `Distinct` builds as SQL (critic round A-21: without `Distinct` the cast stays on the client). A `Where(Get<int>("Y2010") == <the control's value for A>)` reads `A`, and a projection reads `0` for `A`, which is the in-memory contract. — proof: characterization of the cast-to-`T` rule (the user's round-4 decision). The control absorbs the provider's truncate-or-round, so the test asserts agreement with linq2db's own cast rather than a value. With the translation off, `Distinct` read `0, 0`.
- TO-39 `AnAbsentCellNameInASqlPositionIsNamed`, `[DataSources]` — providers: `[DataSources]`, run on SQLite.Classic/MS + DuckDB (direct + `LinqService`), the rest via CI: a `Where` and a `Distinct` over an absent name throw `Error_PivotCellNotFound`. — proof: red→green; red at `bf00c3547` ("Dynamic column getter is not to be called." on `Distinct`).
- TO-40 `UnpivotKeepsTheConversionsOverACellRead`, `[DataSources]` — providers: `[DataSources]`, run on SQLite.Classic/MS + DuckDB (direct + `LinqService`), the rest via CI: `x => (int?)(decimal?)x.Cells["Y2000"]` unpivots and a later `Where(u.Value == 10)` reads `A`. — proof: red→green; red at `bf00c3547` (`ArgumentException`: `decimal?` vs member type `int?`).
- TO-41 `FiltersAnInterfaceTypedMember`, `[DataSources]` — providers: `[DataSources]`, run on SQLite.Classic/MS + DuckDB (direct + `LinqService`), the rest via CI: `Sql.Property` over an `IReadOnlyDictionary`-typed member and `((PivotCells)r.Cells).Get<T>` filter to `A`. — proof: red→green for the `Sql.Property` arm (could not be converted at `bf00c3547` and with the translation off).
- TO-42 `UnpivotConvertsACellReadToItsType`, `[DataSources]` — providers: `[DataSources]`, run on SQLite.Classic/MS + DuckDB (direct + `LinqService`), the rest via CI: `x => x.Cells.Get<int>("Y2000")` and `x => (int?)x.Cells["Y2000"]` over `decimal?` cells unpivot to `A` 10, `B` 5. — proof: red→green; red at `8f2029f35` (`ArgumentException`: `decimal?` vs member type `int` / `int?`, probe P2/P3).
- TO-43 `UnpivotsCastInterfaceMembersUnderTheirPaths`, `[DataSources]` — providers: `[DataSources]`, run on SQLite.Classic/MS + DuckDB (direct + `LinqService`), the rest via CI: two `IReadOnlyDictionary`-typed members read through `((PivotCells)x.Total).Get<decimal?>("Y2000")` / `((PivotCells)x.Top)…` unpivot as `Top.Y2000` 30 / `Total.Y2000` 40 for `A`. — proof: red→green; red at `8f2029f35` (both `Y2000`, probe P4a).
- TO-44 `FiltersAnInterfaceTypedMemberUnderConcat`, `[DataSources]` — providers: `[DataSources]`, run on SQLite.Classic/MS + DuckDB (direct + `LinqService`), the rest via CI: `query.Concat(query).Where(r => Sql.Property<decimal?>(r.Cells, "Y2010") > 16)` over an interface-typed member reads `A, A`. — proof: red→green; red at `8f2029f35` ("'r.Cells.Y2010' could not be converted", probe P7b).
- TO-45 `ACellReadSqlCannotTranslateIsNamed`, `[DataSources]` — providers: `[DataSources]`, run on SQLite.Classic/MS + DuckDB (direct + `LinqService`), the rest via CI: `Where(Get<Uri>("Y2010") != null)` throws `Error_PivotCellType`, as does `Unpivot(…, x => x.Cells.Get<Uri>("Y2010"))` (critic round A-21, objection 4), with and without `IncludeNulls` (without a filter only the column's `Expression`-purpose read reports it: re-check objection E); an absent name in a `GroupBy` key and in an IncludeNulls Unpivot column (`Get<int>("Y2099")`) throws `Error_PivotCellNotFound`. — proof: red→green; red at `8f2029f35` (an unnamed `InvalidOperationException` for `Uri`; "could not be converted" for the absent name, probes P5/P6e). The `Sum` arm was written and stayed red after E-68 (P10).
- TO-46 `UnpivotCastsACellReadAsTheProviderDoes`, `[DataSources]` — providers: `[DataSources]`, run on SQLite.Classic/MS + DuckDB (direct + `LinqService`), the rest via CI: over `FractionalData` and pivot values `2000, 2010, 2020` (no 2020 rows), `Get<int>("Y2000")` and `Get<int>("Y2010")` unpivot to `A` 10 / `castOfA`, `B` 5 / 15, where `castOfA` is the provider's own SQL cast of 20.6 (a `Distinct` control). IncludeNulls over the empty `Y2020` reads `null` through `(int?)cells[…]` and `0` through `Get<int>`. — proof: characterization of the cast rule (critic round A-21, objections 2, 3). The two converting columns go through the set operation's projection.
- TO-47 `UnpivotValueFeedsASubquery`, `[DataSources]` — providers: `[DataSources]`, run on SQLite.Classic/MS + DuckDB (direct + `LinqService`), the rest via CI: `(row, name, value) => new { row.Key, Rows = t.Count(o => o.Amount == value) }` over `Get<decimal?>("Y2000")` reads `A` 1, `B` 1. — proof: characterization. The value is read inside a subquery the result selector builds. The instrumented run shows this test never reaches E-70's non-building branch, so it witnesses the result selector, not E-70's purpose gate (final delta, objection 3).
- TO-48 `ReadsACellThroughAnObjectProperty`, `[DataSources]` — providers: `[DataSources]`, run on SQLite.Classic/MS + DuckDB (direct + `LinqService`), the rest via CI: `(decimal?)Sql.Property<object>(r.Cells, "Y2010")` in a projection reads `20, 15` through a `PivotCells`-typed member and through an `IReadOnlyDictionary`-typed one, and `(int)` through the interface-typed one reads `20, 15` (a read as another type on that route; close round, objection 5). — proof: red→green for the interface arm. Under the `== typeof(PivotCells)` gate (mutation M2) it fails with the BCL "Rewriting child expression from type 'System.Object' to type 'decimal?'", which is the pre-E-70 path. The `PivotCells` arm is characterization.
- TO-49 `UnpivotsAConvertedCellThroughLaterOperators`, `[DataSources]` — providers: `[DataSources]`, run on SQLite.Classic/MS + DuckDB (direct + `LinqService`), the rest via CI: an IncludeNulls Unpivot of `Get<int>("Y2010")` (fractional) and `Get<int>("Y2020")` (empty), then `Where(u => u.Value == castOfA)` reads `A`, `Select(u => u.Value)` reads `castOfA, 15` and `0, 0`. A `Get<Uri>` column under a later `Where` and under a later `Select` throws `Error_PivotCellType`. — proof: characterization of the route through later operators (final delta, objection 2). Its `Get<Uri>` arm reaches E-70's `Extract` branch (instrumented run).
- TO-50 `UnpivotConvertsACellReadInSql`, `[IncludeDataSources(TestProvName.AllSQLite)]` — providers: SQLite (the SQL text differs per provider; SQLite's is a plain `CAST`): `Select(u => u.Value)` after a one-column `Get<int>` Unpivot emits `CAST(`. — proof: control on where the conversion runs, since rows cannot tell on any flooring provider. Mutation M3 (`ReadPivotCellAs` converts the resolved cell on the client) turns it red, with no `CAST(` in the SQL. M1 (rebuild in `Extract`) keeps it green, because `SelectBuilder.cs:39` discards that result.
- TO-51 `UnpivotsAConvertedCellAsASelectManyCollection`, `[DataSources]` — providers: `[DataSources]`, run on SQLite.Classic/MS + DuckDB (direct + `LinqService`), the rest via CI: a one-column `Get<int>` Unpivot as a `SelectMany` collection, with a result selector (`A` 10, `B` 5), without one (`5, 10`), and under `DefaultIfEmpty` (`0, 0`); `Get<Uri>` there throws `Error_PivotCellType`. — proof: characterization of the route that consumes the `Extract` result (`SelectManyBuilder.cs:97`; close round, objection 1).
- TO-52 `ReadsCellsUnderASubQuery`, `[DataSources]` — providers: `[DataSources]`, run on SQLite.Classic/MS + DuckDB (direct + `LinqService`), the rest via CI. Three reader arms and one consumer arm, each under `AsSubQuery()`. The reader arms: `Where(Sql.Property<decimal?>(r.Cells, "Y2010") > 16)` over an `IReadOnlyDictionary`-typed member reads `A`; `Where(r.Cells.Get<decimal?>("Y2010") > 16)` over a `PivotCells` member, and `((PivotCells)r.Cells).Get<decimal?>(…)` over the interface-typed one, read `A` (the `TryGetPivotCellRead` route; critic round A-22); a wrapped pivot unpivoted through `x => x.Cells.Get<int>("Y2000")` reads `A` 10, `B` 5. The consumer arm: an Unpivot of `Get<int>("Y2000")`, wrapped, then `Where(u => u.Value == 10)` reads `A`; it pins the Unpivot output under a wrap, not a cell reader. — proof: characterization. Every arm asserts rows, so it goes red on a throw or a wrong or missing column under the wrap, not on how the wrap is rendered. `AsSubQueryBuilder` always wraps (`DoNotRemove`), per critic round A-22.
- TO-34 `UnpivotsSameNamedCellsOfTwoPivotsUnderTheirPaths`, `[DataSources]`: two pivots' `Y2000` cells unpivot as `Total.Y2000` / `Top.Y2000`. — providers: `[DataSources]`, run on SQLite.Classic/MS + DuckDB (direct + `LinqService`), the rest via CI — proof: red→green; red at `2cad4e701` (both `Y2000`).

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
  **Per-obligation record (A-19, 2026-11-26).** Runs: A-18's local matrix at `07af8c439` (584/585 + the #6028 fix,
  SQLite.Classic/MS + DuckDB, direct + `LinqService`); at the A-19 tree, `Pivot|DynamicColumns` 221/221 on SQLite.Classic
  direct + `LinqService` (Testing net11.0), Release net10.0 `Tests` build clean at `2cad4e701`, and #6110's stacked merge
  265 pass / 5 skip (#5953) / 0 fail (Release net10.0, SQLite.Classic). CI: `test-all` 26006 / GH 45721959517 on
  `2cad4e701`, not yet read.
  - TO-4 pass — `PivotsMultipleAggregatesOfOneValue`, `PivotsMinMaxCells`, `PivotsAvgCell`, `PivotsOnACompositeKey`, `PivotsOnACompositeValue`, `ComposesAfterAConstantPivot`.
  - TO-5 pass — builds, not tests: `Tests` net462 and Release net10.0 (A-18); Release net10.0 again at `2cad4e701`. The leg's red was observed on a real defect of the mutation's class: RS0030 on `PivotExpander.cs:27` (banned `GetConstructor`) before E-58.
  - TO-8 pass — moved with D-5 to #5949 (merged `3d8bcb841`); the `GroupByTests` / `CountTests` rows are master's since the 2026-11-25 merge. The reverted-gate state is master before #5949, red `42601` on 9.2 (TO-7 above).
  - TO-11 pass — `PivotDynamicTests` whole fixture (51 methods at `2cad4e701`): SQLite.Classic/MS + DuckDB at A-18, SQLite.Classic at A-19; the container providers rest on CI 26006, not yet read.
  - TO-12 pass — `PivotsInQuerySyntaxOverAJoin`.
  - TO-13 pass — `TwoPivotsInOneProjection`.
  - TO-14 pass — `SelectsAnItemPerValue`.
  - TO-15 pass — `ReadsCellsAsDynamicMembers`.
  - TO-16 pass — `PivotsARuntimeCellSet`, `PivotsWithAPrebuiltAggregate`.
  - TO-17 pass — `QueryIdentityFollowsTheInputs`, `SameNamesOverDifferentValuesReadTheirOwnValues`. Mutation (A-19, SQLite.Classic): an `Expand` memoized per terminal under `ExpressionEqualityComparer` turns `QueryIdentityFollowsTheInputs` red, but with `variable 'g' … not defined` — the memo replays a lambda across queries — before the mutated-list and prefix arms are reached; `SameNamesOverDifferentValuesReadTheirOwnValues` stays green. The named arms' discrimination is therefore not shown by this mutant.
  - TO-18 pass — `InASubQueryEachExecutionRereadsItsInputs`, `NameFactoryGuardIsNotEvaluatedEagerly`, `PivotInlineInASubQuery`, `PivotOverACorrelatedSource`.
  - TO-19 pass — `CompiledPivotKeysOnItsValueSet`, `CompiledPivotOverAValueSetItHolds`. Mutation drop `RecordMaterializedArgumentSlots` from the expander: red, `array2` / `mixed2` read 10 instead of 20 (A-18).
  - TO-20 pass — census: Release net10.0 API analyzers 0 RS0016/RS0017 at `2cad4e701`; no `SelectDynamic`, `PivotCells<` or top-level `Pivot` in the diff. The instrument's red is G-03's first run: 58 RS0016 on undeclared surface.
  - TO-21 pass — `ThrowsWhenInvokedInMemory`.
  - TO-22 pass — `ComposesAfterAConstantPivot`, `CompositionKeepsTheCellServerSide`.
  - TO-23 pass — `ProjectionBindingDynamicColumnsMaterializesIntoTheStore`, `ProjectionBindingDynamicColumnsAsAConstructorArgument`, `ProjectionBindingDynamicColumnsWithoutAStoreThrows`, `ProjectionWithoutDynamicBindingsCreatesAStorePerRow`, `ProjectionBindingDynamicColumnsUnderConcat`, `ProjectionBindingDynamicColumnsComposes`.
  - TO-24 pass — `ToolsTests.PivotOperatorsOverADbSet`, EF10 SQLite.MS (A-18).
  - TO-25 pass — `ReadsEveryArgumentShape`, `RejectsShapesItCannotRead`.
  - TO-26 pass — `PivotsUnderConcat`, `PivotsInAnEagerLoadedCollection`.
  - TO-27 pass — `AnEmptyCellOverANonNullableColumnReadsNull`, `AnEmptyCountCellReadsZero`, `AnEmptyValueSetYieldsNoCells`.
  - TO-28 pass — `PivotTests` (27 methods at `2cad4e701`). Both mutant pairs red (A-18): dropping `Snapshot` fails the mutate-in-place arm, dropping the evaluated-value `MarkAsValue` fails four inline tests.
  - TO-29 pass — `UnpivotsTheCellsUnderTheirOwnNames`, `UnpivotNameColumnOfAProjectedMemberUsesTheMemberName`; red first on SQLite.Classic direct + remote (`Cells.Y2000`, `Inner.Q1`).
  - TO-30 pass — `ComposesThroughTheCellsMembers`, `UnpivotsTheCellsThroughTheIndexer`; red first ("could not be converted", `Error_UnpivotColumnSelector`). The tightened filter / ordering arms were also red on the first build-visitor draft (the ordering key reached it as a bare indexer through `OrderByBuilder`'s `Unwrap`).
  - TO-31 pass — `CapturedCellsAreAValue`; red under the expose-rewrite E-54 ("Dynamic column getter is not to be called."), green with it off and with the build-visitor E-54.
  - TO-32 pass — `AProjectedCellReadKeepsItsInMemoryContract`; red under the expose rewrite (absent name threw, `Get<int>` read 20, `Get<string>` threw), green with it off and with the build-visitor E-54.
  - TO-33 pass — `ACapturedCellNameKeysTheQuery`. Mutation drop `[SqlQueryDependent]` from `Get<T>`'s `name`: red, the second name replays the first column (`[]` instead of `A, B`).
  - TO-34 pass — `UnpivotsSameNamedCellsOfTwoPivotsUnderTheirPaths`; red at `2cad4e701` (both `Y2000`), and on the first fallback draft (`Total.Y2000`, `Y2000`).
  - A-19 tree runs (uncommitted): `Pivot|DynamicColumns` SQLite.Classic 229/229, SQLite.MS 224/224, DuckDB 206/206, each direct + `LinqService` (Testing net11.0); Release net10.0 build clean (one [MA0006] in E-53 fixed first) and SQLite.Classic 229/229 on it.
  - test-diff-sweep (`-Repo` the worktree at `2cad4e701`): chains 84, nestedChains 4, narrowedSets 25, narrowedWithoutReason 5, localModels 1, shouldlySubjectGates 0, typeOnlyShouldlyGates 0, continuationIndents 0, unanchoredAssertionGates 0, narrowedContinuations 0, cacheMissOutsideQueryCacheTest 0, handDuplicatedAreEqual 0, invisibleChars 0, issueNamedMembers 0, attributePadding 0. None falls in E-59's added tests. The rest predate A-19 and were fixed in A-20 (`8f2029f35`: chains 0, nestedChains 0, narrowedWithoutReason 0).
  **Per-obligation record (A-20, 2026-11-26).** Runs at `8f2029f35` (Testing net11.0, direct + `LinqService`):
  `Pivot|DynamicColumns` SQLite.Classic 243/243, SQLite.MS 237 pass + 1 skip (#6028), DuckDB 218/218; EF10 SQLite.MS
  `PivotOperatorsOverADbSet` 1/1. Release net10.0 `Tests` build at `8f2029f35`: clean, 0 warnings. CI on a head containing E-60…E-65: pending.
  - TO-34 pass — value arm added (`Top.Y2000` 30 / `Total.Y2000` 40 for `A`), so two branches reading one pivot's column fail it.
  - TO-35 pass — `ARowDependentCellNameReadsOnEveryExecution`; red at `bf00c3547` (second execution: "variable 'r' … not defined").
  - TO-36 pass — `ACapturedCellNameKeysAnIndexerRead`. Mutation drop `[SqlQueryDependentValue]` from the indexer's `name`: red on SQLite.Classic direct + `LinqService`, the second name replays the first column (`[]` instead of `A, B`); `ACapturedCellNameKeysTheQuery` (the `Get<T>` arm, attribute kept) stayed green in the same run.
  - TO-37 pass — `ACompiledCellNameKeysTheBuild` (SQLite family).
  - TO-38 pass — `AGetInASqlPositionReadsTheCellAsItsType`; `Distinct` read `0, 0` with the translation off.
  - TO-39 pass — `AnAbsentCellNameInASqlPositionIsNamed`; red at `bf00c3547` ("Dynamic column getter is not to be called." on `Distinct`).
  - TO-40 pass — `UnpivotKeepsTheConversionsOverACellRead`; red at `bf00c3547` (`ArgumentException`, `decimal?` vs `int?`).
  - TO-41 pass — `FiltersAnInterfaceTypedMember`; the `Sql.Property` arm red at `bf00c3547` ("could not be converted").
  - test-diff-sweep (`-Repo` the worktree at `8f2029f35`, A-20; A-21's record follows): chains 0, nestedChains 0, narrowedSets 26, narrowedWithoutReason 0, localModels 1, shouldlySubjectGates 0, typeOnlyShouldlyGates 0, continuationIndents 0, unanchoredAssertionGates 0, narrowedContinuations 0, cacheMissOutsideQueryCacheTest 0, handDuplicatedAreEqual 0, invisibleChars 0, issueNamedMembers 0, attributePadding 0, issueFixtureFiles 0.
  **Per-obligation record (A-21, 2026-11-27).** Runs on the A-21 working tree (Testing net11.0, direct + `LinqService`):
  `Pivot|DynamicColumns` SQLite.Classic 251/251, SQLite.MS 245 pass + 1 skip (#6028), DuckDB 226/226 (counts include
  `CreateDatabase`), before E-71. After E-71, `PivotDynamicTests` on SQLite.Classic 124/124. Two earlier SQLite.Classic
  runs each lost one `LinqService` case to a gRPC `Unavailable` (an HTTP/2 handshake failure, then an SSL EOF) while the
  box was saturated (52- and 29-minute runs). Neither recurred in the matrix runs. Final, at `5b93d343a` (Testing net11.0, direct + `LinqService`): `Pivot|DynamicColumns` SQLite.Classic 260/260, SQLite.MS 254 + 1 skip (#6028), DuckDB 234/234 (`b0194aceb`: 257 / 251 + 1 / 232). Release net10.0 `Tests` build at `21936d936`: clean, 0 warnings, 0 errors. CI: pending.
  - TO-38 pass — rewritten (fractional cell, provider-cast control); the projection arm reads `0, 0`. Characterization: green before E-66…E-71 too.
  - TO-42 pass — `UnpivotConvertsACellReadToItsType`; red at `8f2029f35` and under E-66 alone (BCL `VisitUnary` validation), green with E-70. TO-40 was red under E-66 alone and is green with E-70.
  - TO-43 pass — `UnpivotsCastInterfaceMembersUnderTheirPaths`; red at `8f2029f35` (both `Y2000`).
  - TO-44 pass — `FiltersAnInterfaceTypedMemberUnderConcat`; red at `8f2029f35` ("'r.Cells.Y2010' could not be converted").
  - TO-45 pass — `ACellReadSqlCannotTranslateIsNamed`; red at `8f2029f35` on both arms (assertion message mismatch). Its `Sum` arm stayed red after E-68 and was dropped (P10). The Unpivot `Get<Uri>` arm was red (BCL `No coercion operator`) while E-70 excluded `Sql`; the IncludeNulls `Get<Uri>` and absent-name column arms are green at `b0194aceb`.
  - TO-46 pass — `UnpivotCastsACellReadAsTheProviderDoes` (SQLite.Classic/MS, DuckDB; on DuckDB the `Distinct` control and the aggregate cell agree, re-check objection B). Characterization.
  - TO-47 pass — `UnpivotValueFeedsASubquery`. Characterization.
  - TO-48 pass — `ReadsACellThroughAnObjectProperty`, both arms. Mutation M2 (`== typeof(PivotCells)`): the interface arm red (BCL `Rewriting child expression …`).
  - TO-49 pass — `UnpivotsAConvertedCellThroughLaterOperators`; its `Get<Uri>` arm reaches E-70's `Extract` branch.
  - TO-50 pass — `UnpivotConvertsACellReadInSql` (SQLite family); reaches the `Extract` branch. Mutation M3 (client-side convert in `ReadPivotCellAs`): red, no `CAST(` (and 28 more cases red).
  - TO-51 pass — `UnpivotsAConvertedCellAsASelectManyCollection` (at `21936d936`: `Pivot|DynamicColumns` SQLite.Classic 262/262, SQLite.MS 256 + 1 skip, DuckDB 236/236, direct + `LinqService`).
  - TO-48 `int` arm (close round, objection 5) — green at `21936d936`.
  - TO-52 pass — `ReadsCellsUnderASubQuery` (A-22), every arm (`b29e48f24`, plus the `Get<T>` arms in `b26ab1b30`): SQLite.Classic, SQLite.MS, DuckDB, direct + `LinqService`, Testing net11.0; Release net10.0 `Tests` build clean. Characterization; green on the first run.
  - E-70 instrument and M1 (final delta, objection 2): only `Extract` reaches the non-building branch (5 cases); the `b0194aceb` rebuild form is green on 133/133 `PivotDynamicTests` cases, so the branch returns the node.
  - TO-33 / TO-36 (A-21 mutation, objection 8) — compare every argument structurally: green on TO-33…TO-37 (10/10), so the value branch was removed (E-71).
  - test-diff-sweep (`-Repo` the worktree at `21936d936`): chains 2, nestedChains 0, narrowedSets 27, narrowedWithoutReason 0, localModels 1, shouldlySubjectGates 0, typeOnlyShouldlyGates 0, continuationIndents 0, unanchoredAssertionGates 0, narrowedContinuations 0, cacheMissOutsideQueryCacheTest 0, handDuplicatedAreEqual 0, invisibleChars 0, issueNamedMembers 0, attributePadding 0, issueFixtureFiles 0. The 2 chains are false positives, resolved in A-21's `conventions:` line.
- G-02: **blocked** on CI regenerating the baselines for f550159e9 (the 2026-10-10 delta, linq2db.baselines#2141, predates A-15; its real content was new-test files plus the 68 PostgreSQL 9.2/9.3 files of the base PR). Originally not run — no local baselines diff; the `.sql` churn lands on the baselines PR at CI push. Expected wide
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
- **`ExcludeNulls` dropping a NULL read through an outer join into a non-nullable member is a fix, not a P3 violation.** A-15 lifts the filter to `TValue?`; the rows that disappear were returned as `default(TValue)` against the documented "NULL value cells are excluded" contract, on API that exists only in `PublicAPI.Unshipped.txt` — the same adjudication as the `UnpivotMulti` entry above.
- **The gate living in this branch is temporary and deliberate.** D-5 is implemented here to prove the change end to end, then ported to its own PR before merge. A reviewer seeing a PostgreSQL translator change inside a pivot PR is seeing the intended interim state, not scope creep — but the port is release-blocking.
- **A-17: over EF Core, the pivot needs `.ToLinqToDB()`.** Today's top-level operator works directly on a `DbSet` because it calls `ProcessIQueryable`. `g.Pivot` lives inside `Queryable.GroupBy`/`Select`, which EF executes (U-21). This is a narrowing of shipped-in-PR behaviour, on API that exists only in `PublicAPI.Unshipped.txt`, and it matches how every other linq2db-only projection member is used from EF. Pinned by TO-24 in both directions.
- **A-17: cells always land in a nested `PivotCells` member, never in `TResult`'s own `[DynamicColumnsStore]`** (D-9's failure mode). A flat DTO reads its cells through `Sql.Property(r.Cells, …)` or the dictionary view (A-19: in a query also `r.Cells.Get<T>(name)` / `(T)r.Cells[name]`, on a member typed `PivotCells`).
- **A-17: the pivot is no longer an `IQueryable` operator.** Someone looking for `.Pivot` on a table finds `Unpivot` and not `Pivot` (sdanyliv: top-level sugar can be added later if discoverability matters). Not added here.
- **A-17: no performance claim, either way, for the expose-time expansion** (U-25). Mechanism, not timed: a pivot query runs the full expose pass and the expansion on every execution, because its raw tree can never hit the cache. Each inline or method-group name factory is compiled once per execution. The PR body must state it this way, not as "one extra lookup".
- **A-17: the `Select` terminal does not lift** (D-9). An empty cell reads what the user's member type materializes from `NULL`, so the same data can read `null` through `AsDictionary` and `0` through a non-nullable `Select` member. Documented on `Select`; pinned by TO-14.
- **A-17: `AssertQuery` cannot drive a pivot test.** Its expected side runs the query in memory, where U-28 (a) throws; the ported tests assert values directly.
- **A-17: F# is not claimed** (U-22). The XML docs and the PR body speak about C# query and method syntax only.
- **A-20: a captured cell name in a projection-only `Get<T>` / indexer read is part of the cache key.** `[SqlQueryDependentValue]` folds an evaluable name to a constant even where the read stays in memory, so each distinct name is its own cache entry and build where a non-dependent argument would be one entry re-read per execution. Results are correct and the cost is bounded by the number of distinct names; unmeasured. Accepted at review round 4 (user decision); same class as the expansion-cost line above.
- **A-21: a cell read as another type in a SQL position follows the provider's conversion and NULL semantics.** `Get<int>` over a 20.6 cell reads what linq2db's own SQL conversion of a column gives: the engine's `CAST` (SQLite: 20; an engine whose cast rounds reads 21), or `FLOOR` before the cast where the provider emulates truncation (`FloorBeforeConvert`: DuckDB, MySQL, Firebird, DB2, Oracle, PostgreSQL, SQL Server: 20). Those providers floor or truncate, so no provider run separates a SQL cast from a client one by rows. The fractional arms of TO-38 / TO-46 pin the agreement of the cell with linq2db's own conversion, not the place it runs (critic round A-21 final delta, objection 1). An empty cell is NULL, so `Where(Get<int>(name) == 0)` matches no empty cell, while a projection of the same read gives `0`. This follows from the round-4 cast-to-`T` decision and is not a divergence this branch introduces. TO-38 pins agreement with the provider's cast.
- **A-21: an absent cell name inside a top-level aggregate's selector reports "could not be converted to SQL"**, not `Error_PivotCellNotFound` (`pivoted.Sum(r => r.Cells.Get<decimal?>("Y2099"))`, measured after E-68). The aggregate path discards the critical error and retries; only set projections read `IsCritical`. The query still fails at build, so only the message is affected, and no result changes. Fixing it means changing shared error propagation, which belongs on its own branch. SC-17's named-error clause therefore covers `Where`, `OrderBy`, `Distinct` and a grouping key.
- **A-21: E-70 admits a dynamic column declared on any interface `PivotCells` implements** (`IReadOnlyDictionary<string, object?>`, `IReadOnlyCollection<…>`, `IEnumerable<…>`, `IEnumerable`, `IDynamicMetaObjectProvider`; not `DynamicObject` or `object`). So `(T)Sql.Property<object>(x.Member, name)` over such a member that is not a pivot's would read `Error_PivotCellNotFound` (final delta, objection 5). Reach, searched rather than probed: `Sql.Property` declares the access on the receiver's static type (`MemberHelper.cs:150`), so the member would have to come from the query typed as one of those interfaces. linq2db maps no column to them; an entity's dynamic store is `IDictionary<string, object>`, which `PivotCells` does not implement; and a client-held value is excluded by the receiver check. The only producer found is a pivot. Accepted without a test.
- **A-17: `TryEvaluateArguments`' one-argument-per-pass substitution (`ExposeExpressionVisitor.cs:298`) is not a defect** (U-26, probed): later passes fill in the rest, at the cost of extra visits. It is not touched here; its cleanup runs on its own branch.

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
    *(Superseded by A-15: the top-level scan missed nested and `Convert`-wrapped placements; the builder now
    finds the placeholder anywhere in the projection.)*
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

- **A-15 (2026-10-11) — round-1 review walk; P6 widened to E-24…E-33.** The review of head fe655cf93 produced
  22 findings, all resolved as commits df7a56733…e0935d57f; the attribution is in `gaps.md` (9 of 22 sit in what
  A-13/A-14 introduced without a re-derived P4/P7/P8 or a critic round). **The approval this plan never recorded
  is in any case void for the widened surface.** What changed, each red first where it is a behaviour change:
  - **Placement:** `SelectDynamicBuilder` finds the `PivotCells<,>` placeholder anywhere in the projection, not
    only among the top-level constructor's members — a nested object or a `Convert`-wrapped member was either a
    misleading "SelectDynamic result" error or, with a root store on `TResult`, cells silently written there.
    `Pivot` rejects a chain that is not a member value (method argument, whole projection) at the call site.
    `PivotCells` implements `IReadOnlyDictionary<string, object?>` explicitly, so a named result type can declare
    the member without spelling an anonymous `TSource`; CA1710 is suppressed (name chosen for its role).
  - **`ReadTemplates`** evaluates a non-lambda aggregate argument (captured `Expression` local, helper result)
    instead of casting it — previously `InvalidCastException`.
  - **`UnpivotBuilder`** reuses its mapping-schema probe as the first branch (`ContextRefExpression`) **at the
    root only**; the throwaway build had re-registered builder-scoped query tags and hints, so they appeared N+1
    times for N columns and now appear N times — once per branch, as a hand-written `Concat` gives (pinned for
    N=1 and N=2). In sub-query position (`Any`, the collection side of `SelectMany`) the first branch rebuilds
    the source as before (f550159e9): a context reference is re-resolved there through `GetContext`, which a
    `SelectContext` cannot answer for a projected source — the reuse as first committed (51511d587) failed with
    "could not be converted to SQL", red-proven by `UnpivotOverAProjectionInASubQuery`.
  - **`ExcludeNulls`** lifts its filter to `TValue?` for a non-nullable value type instead of skipping it: a
    member from the outer side of a join returned NULL cells as `default(TValue)` rows. Contract unchanged; the
    code now meets it.
  - **Names:** `SelectDynamic`'s identifier-character check is removed — a generated name reaches SQL only as an
    alias, which `IIdentifierService.CorrectAlias` reduces to `[A-Za-z0-9_]`, so the check guarded nothing. The
    shadowing guard matches public fields and non-indexer properties only (methods and the indexer never shadow a
    dynamic column; measured). The real quoting gaps are in the column-reference path: #6022 (7.0.0), #6023.
  - **`PivotCells`:** `Values` never null (lazy), constructor internal (builder uses the non-public one; one
    `PublicAPI.Unshipped.txt` line removed), `Cell` is `[Pure]`, the doc says an empty count cell reads 0.
  - **Messages:** the shared builder's two errors no longer name `SelectDynamic` when reached from `Pivot`.
  - **Measured, no defect:** value-blind names over different value sets do not share a cache entry — the inlined
    pivot literals discriminate the key — so each value order reads its own cells (pinned by test).
  - Verification: 333/333 pivot/`SelectDynamic` tests on SQLite.Classic, SQLite.MS, DuckDB, SqlCe (direct +
    LinqService); Release net10.0, Release netstandard2.0, Tests Release net10.0 and Tests net462 build clean.
    Container providers left to CI: `test-all` build 24106 covers e0935d57f only; f550159e9 still needs its own
    run before this amendment's verification is complete.

- **A-16 (2026-10-11) — round-2 review walk; P6 widened to E-34…E-36.** The review of head 413eaa7be produced 12
  findings plus 4 out-of-scope observations; all findings were fixed as commits 24bb696de…abe28281e, attribution in
  `gaps.md` Round 2. **The approval this plan never recorded stays void for the widened surface.** What changed, each
  red first where it is a behaviour change:
  - **Inline in a sub-query (E-34).** The public overloads rewrite themselves into markers only when they run; inside
    a lambda over a query-chain source the exposer leaves them unevaluated (`ExposeExpressionVisitor:495`), so
    `t.Where(…).Unpivot(…)` inside `Any` / `SelectMany` failed "could not be converted" — red-proven for all three
    operators. `[EagerEvaluation]` was tried and rejected: its compilability check rejects server-side-only calls
    inside quoted lambdas, so every `Sql.Property` template failed. A builder now runs the call over
    `ExpressionQueryImpl.CreateQuery(…, source expression)`, passing quoted lambdas through uncompiled, so a
    correlated source is never evaluated and works where the provider supports lateral joins (`Unpivot` correlated
    is `[ThrowsRequiredOuterJoins]` on the no-apply providers; correlated `Pivot` decorrelates and runs everywhere
    tested). `SelectDynamic` with a `Sql.Property` template still fails inline: the exposer evaluates the template's
    name before any builder runs — #5953, tests gated.
  - **Pivot cells** may read the selector's grouping parameter (`BuildCell` declares the cell lambda over it);
    `Pivot` routes through `ProcessIQueryable`, so it works directly on an EF Core `DbSet` (E-36, red on EF10).
  - **Unpivot** names a nested/complex column by its full member path (red: `Ship.Amount` read `ROOT_AMT`);
    multi-value overloads validate empty groups / names / selectors.
  - **API:** `PivotCells.Values` → `Store` (the IReadOnlyDictionary view's `Values` meant something else), nullable
    values, private setter; messages to `ErrorHelper.Pivot` (E-35).
  - **Tests:** two-column multi-value pin; production-shape cache assertions split SQLite-only, SQLite.MS repeat
    execution gated on pre-existing #6028; `UnpivotOverAProjectionInASubQuery` gated on Oracle 11 behind #6024
    (pinned type + message; fix PR #6027 may turn it into `Error_OUTER_Joins` rather than a pass).
  - Measured, no change: an inline or method-group name factory costs one `CompileExpression` per execution
    (captured `Func` costs none); no retained-memory growth attributable to it.
  - Verification: pivot classes green on SQLite.Classic + DuckDB (direct + LinqService) and Oracle 11; EF10 SQLite.MS;
    Release net10.0 (Source, Tests, EF10), netstandard2.0, Tests net462 build clean. `test-all` build 24141 queued
    on abe28281e.
  - **Revision after critic round 4 (refuted), commit 26c0f993f.** E-34 folded closure-held arguments after the cache
    key was taken: measured stale rows (captured `Unpivot` columns `{Q2}`→`{Q3}` still answered `EU`), the inline
    name-array overloads threw the selector error, and the inline marker `Unpivot` dropped a params array passed as a
    variable. Chosen fix (user's option b over rejecting non-literal arguments): every closure-held value in the
    operator's arguments, quoted selectors included, is registered with `ParametersContext.MarkAsValue` — the
    by-value comparison `RegisterExtensionAccessors` uses for extension builders — in both `PivotSugarBuilder` and
    `UnpivotBuilder`; the desugared tree goes through `ConvertExpressionTree` before building; `UnpivotInfo.Parse`
    evaluates a non-`NewArrayInit` params argument. Rejected: `[SqlQueryDependent]` on the public parameters (#6003's
    route for `FromSql`) — `PrepareForCache` would fold quoted column lambdas into reference-compared constants and
    miss on every execution. Cost: on the inline path a captured `Func` (name factory, `cells`) compiles to a new
    delegate per evaluation and therefore never hits the cache; the direct path is unchanged. Pinned SQLite-only
    (cache identity is provider-agnostic): `InlineUnpivotRereadsCapturedColumns` / `…ColumnNames` /
    `InlineUnpivotWithAColumnArrayVariable` (red before, measured) and `InlinePivotRereadsCapturedValues` (not run red).
    A-15's "value-blind names over different value sets do not share a cache entry" holds for the direct path; the
    inline path now holds it through the by-value marks.
  - **Revision after critic round 5 (refuted 26c0f993f; uncommitted on top of it).** Round 4's leaf marking was wrong
    in both directions, and its "the direct path is unchanged" was false: `UnpivotBuilder` marked closures inside the
    quoted selectors of *every* `Unpivot`, so `Amount = a * rate` missed per distinct `rate` on the direct path. Leaf
    marking also missed values not rooted at a closure member (`GetYears()`, `source.GetYears()`: the call compared
    structurally, the object by reference → stale rows), and a captured `List<int>` mutated in place compared
    `ReferenceEquals` → stale. Now, in `PivotSugarBuilder.ReadArgument` (shared by `UnpivotInfo.Parse`):
    - **Argument granularity**, as `RegisterExtensionAccessors`: an argument that is not a quote / array-init / lambda is
      evaluated **once**, that value is both marked (unless a constant the key keeps) and handed to the call — so a
      `DateTime.Now`-derived set cannot differ between the mark and the build. Array-init is read element-wise.
    - **Quoted lambdas become SQL**, so their captures stay ordinary parameters and are never marked; the only
      build-time reads inside one are the non-quoted arguments of a `PivotCells.Cell` call (aggregate held in a
      variable, name factory). A lambda argument run at build time (`cells`, `nameSelector`, an in-place name factory)
      is compared structurally by the key, and every value its body reads outside a nested quote is marked — so
      `y => y == current ? "V" : "W"` re-reads `current` (a scalar: the critic's delegate/Expression-only rule would
      have missed it).
    - **Snapshot**: a marked non-string, non-`IQueryable` sequence is copied at mark time and compared element-wise.
    - `UnpivotInfo.Parse` reads `Arguments[1..4]` through the same reader. The direct path's marker carries only a
      constant `nulls`, quotes and an array-init of quotes, so it marks nothing.
    - Critic item 3 (`x => x.Q1` held in a local → `InvalidCastException`) **did not reproduce** on 26c0f993f: the
      extended `InlineUnpivotWithAColumnArrayVariable` passed before the change. Kept as a pin.
    - Tests, SQLite-only, each run red on 26c0f993f's source for the stated reason: `InlinePivotRereadsAValueSetMethod`
      (static call, provider-keyed dictionary — `[ThreadStatic]` is banned), `…InstanceMethod`, `…AValueListMutatedInPlace`,
      `InlineUnpivotRereadsColumnNamesFromAMethod` (stale rows); `UnpivotSelectorCaptureReusesTheCachedQuery` (direct)
      and `InlineUnpivotSelectorCaptureReusesTheCachedQuery` (2 misses, expected 1). `InlinePivotRereadsANameFactoryCapture`
      is green on 26c0f993f, red only against abe28281e's design (not run).
    - Verification: pivot / `SelectDynamic` classes on SQLite.Classic, SQLite.MS, DuckDB (+ `.LinqService` for the
      `[DataSources]` tests): 334 pass, 1 fail — `PivotsProductionShapeIntoUserType` on SQLite.MS, which fails
      identically without this change: pre-existing #6028 reached through test order (`PivotsProductionShapeQueryCache`
      caches the same direct-path shape first). Release net10.0 + netstandard2.0 (Source) and Release net10.0 (Tests)
      build clean.
    - Cost unchanged from round 4 for build-time delegates: a captured `Func` compares by delegate equality (hit when
      the same instance); a value the call reads through a method compares by result, so it re-runs the method on
      every cache lookup.
  - **Revision after critic round 6 (refuted round 5; user chose "evaluate as value-or-threw").**
    - **Guarded reads.** A read inside a build-time lambda can sit behind a test on the lambda's own parameter
      (`y => y > 3000 ? cfg!.Prefix : "V"`); marking evaluated it eagerly → `TargetException` with `cfg == null`, where
      the direct path never reaches it. Measured red on both 26c0f993f and round 5 (`InlinePivotNameFactoryWithAGuardedCapture`).
      A guard *not* using the parameter (`cfg != null ? … : …`) is folded by the exposer with the current value before
      the builder runs, so it never failed — the critic's own example did not reproduce until rewritten. Now
      `MarkGuardedValue` evaluates the read under try/catch and registers `TryCatch(read, catch → sentinel)` as the
      accessor: compared as "the value, or that it threw", at mark time and at every lookup, so a later null is a miss,
      not an exception out of `QueryCache.TryFind`. Top-level arguments are not wrapped: the call reads them
      unconditionally, so a throw there is the call's own.
    - **Critic round 7: `weak`** — design held (fold explanation verified, `TryCatch` accessor sound through
      `ApplyAccessors` / `CorrectAccessorExpression`, direct path marks nothing). Asks applied: the guarded test is now
      a `[QueryCacheTest]` pinning the sentinel's hit/miss arms (null → 1 miss, null → hit, `{W}` → miss, null → hit);
      eager-evaluation and `cells` delegate-identity limitations recorded (below).
    - **Inline lambda arguments** now have obligations, each red on 26c0f993f (stale rows):
      `InlinePivotCellSetRereadsWhatItReads` (`cells:` lambda) and `InlineSelectDynamicRereadsWhatTheNameSelectorReads`
      (template without `Sql.Property`, clear of #5953).
    - **Sequences.** A non-array sequence argument is enumerated once into an array that both the mark and the call
      use. Limitation: the comparison enumerates the *live* argument at every lookup, so a sequence that can be
      enumerated only once is unsupported inline (the lookup consumes it before a rebuild) — unfixable while the value
      is compared by content.
    - **Limitations recorded** (XML docs of `PivotCells.Cell` `name`, `SelectDynamic` `nameSelector`, `Pivot` `cells`):
      written in a sub-query, a captured delegate or object counts as unchanged while it is the same instance; and
      (critic round 7) every client-evaluable read in a build-time lambda runs at build and at each cache lookup,
      whether or not the lambda's guard reaches it — so a side-effecting or expensive read runs anyway, and a sequence it
      reads is enumerated then (same one-shot caveat as a top-level argument). 26c0f993f touched only closure-rooted
      leaves, so this eager evaluation is new with the argument-granularity design. **Compiled queries:**
      the public overloads written inline under `CompiledQuery.Compile` receive `ArrayIndex(ps, i)` arguments the raw
      evaluator cannot resolve — not a regression against 26c0f993f, out of scope for this PR (P10).
    - Verification: pivot / `SelectDynamic` classes, SQLite.Classic + SQLite.MS + DuckDB (+ `.LinqService` for
      `[DataSources]`): 340 pass, 1 fail = `PivotsProductionShapeIntoUserType` on SQLite.MS (#6028, see below).
    - **#6028 mechanism, measured (probe, SQLite.MS):** Microsoft.Data.Sqlite reports `GetFieldType` /
      `GetDataTypeName` per row, and inconsistently for NULL — row 0's NULL is `Byte[]`/`BLOB`, row 1's NULL is
      `String`/`BLOB`. Execution 1: the fast mapper is compiled on row 0, throws on row 1 → `ReMapOnException` stores a
      slow-mode mapper (`IsFaulted`) in the cached query's `Mapper<T>`. Its `ColumnReader` caches converters keyed by
      `GetFieldType` alone, while `GetReaderExpression` also chooses by type name / provider type; the first cell it sees
      for the failing column is row 1's NULL (`String`/`BLOB`), so a BLOB reader is cached under `String` (harmless on a
      NULL; the BLOB → `byte[]` reader choice is inferred from the exception, not traced). Execution 2 is a correct cache hit; the faulted mapper reads row 0's TEXT under `String` → `String → Byte[]`
      and, being faulted, rethrows. A cache miss (new value set) builds a fresh mapper and succeeds. So: correct hit,
      poisoned materializer state inside the cached query — independent of the pivot.

- **A-17 (2026-10-22) — Pivot becomes an aggregate over a group; `SelectDynamic` leaves the branch. Supersedes A-14's
  two top-level families, the Pivot arm of A-16's E-34, and E-29/E-30/E-31/E-33's role here; adds public types.**
  **The approval this plan never recorded is void for the whole Pivot surface; a new critic round (P12 round 8) and
  a fresh user approval are required.**

  Trigger: sdanyliv's [proposal](https://github.com/linq2db/linq2db/pull/5708#issuecomment-6152165147) (2026-10-13). The
  user adopted it in session on 2026-10-22, chose to split `SelectDynamic` out, to expand in expose, and to ship all three
  terminals plus `Cells(templates)`. The problem it answers is the API, not the SQL:
  - the `(g, p)` two-parameter selector;
  - the `TResult` `[DynamicColumnsStore]` contract;
  - `PivotCells<TSource,TFor>` doubling as builder and result;
  - the operator being unusable in query syntax and with two pivots per projection;
  - cache identity bought after the key by `PivotSugarBuilder`'s marking (A-16, four critic rounds).

  The SQL is today's `BuildCell` output, which TO-11's baselines control checks.

  What changed in the plan:
  - Decisions D-6 (expose-time expansion), D-7 (dynamic-binding `MemberInit` materialization, a projection-layer fix with
    a core-layer test), D-8 (`SelectDynamic` split, shared reader as a byte-identical file), D-9 (surface).
  - Edit-points E-37…E-51. P3 constraints and anti-goals. SC-9…SC-15, with SC-1/SC-4 re-mapped.
  - Unknowns U-13…U-28, of which U-13…U-16 are measured probes and U-28 is **OPEN** (in-memory semantics; user decision).
  - P7 rows from two scouts, P10 entries, and TO-11…TO-28.

  re-derives: P4 U-13…U-28 (new), the A-17 P7 rows (new), P8 TO-11…TO-28 (new), and the earlier rows below:
  - **SC-1/SC-4** re-mapped to the ported fixture.
  - **TO-1** loses `SelectDynamicTests`.
  - **TO-4/TO-9** become TO-11/TO-27 on the new API, keeping D-4's lift as a mutation-tested obligation.
  - **SC-7 / D-4** are scoped to the `Cell`-fed terminals. The `Select` terminal carries D-9's own empty-cell rule, because the user's member type decides it (critic round 8, objection 1).
  - **A-14's U1** (composition stays server-side) is re-measured by U-13's composed probe and pinned by TO-22.
  - **A-15's "value-blind names do not share a cache entry"** is re-measured by U-16 and pinned by TO-17.
  - **A-16's inline marking** for Pivot is replaced by construction (D-6). Its 7 `InlinePivot*` scenarios carry over as
    TO-18. Its guarded-read limitation is retired, and TO-18 now asserts the factory is *not* read behind its guard.
  - **A-16's compiled-query note** ("public overloads written inline under `CompiledQuery.Compile` receive `ArrayIndex(ps,
    i)` arguments … out of scope") is **reversed for Pivot**. The expander resolves slots, and TO-19's grid pins it. For
    `Unpivot` the note stands unchanged.
  - **A-16's `Unpivot` marking** is unchanged and moves file only (E-51), controlled by TO-28.
  - **E-34/E-35/E-17** are narrowed by E-44/E-46/E-47.

  conventions: `testing.md` → *Test layout*, *A narrowed provider set is a claim — re-derive it…*, *Gating an assertion
  failure*, embedded for E-48/E-49/E-50 and TO-11…TO-28. The swept diff is `test-diff-sweep.ps1 -Repo
  C:/Worktrees/linq2db/1475-pivot-unpivot` against `origin/master...`: 125 one-line chains and 65 narrowed sets on the
  branch's tests, including the #5949 base's `GroupBy`/`Count`/`Boolean` rows. Of those sets, 25 are
  `[IncludeDataSources(TestProvName.AllSQLite)]` in the Pivot / `SelectDynamic` files with no reason line. E-48 rewrites
  `PivotDynamicTests` wholesale under these rules. The sweep is re-run on the implemented tree before commit, and its counts
  are recorded in G-01.

  Sequencing:
  1. Sync the stack with `origin/master` (master → #5949 → #5708). The worktree is 2026-10 master-behind: NuGet audit
     NU1902/NU1903 fails its build until #6043/#6095 arrive (measured this session; the probes ran with `NuGetAudit=false`
     as a per-run environment variable).
  2. Branch the SelectDynamic PR off `origin/master` (D-8).
  3. Implement E-37…E-51 here.

  **Revision after critic round 8 (refuted).**
  - U-28 was answered (a) by the user.
  - U-26 was probed: not a defect.
  - D-7's predicate is narrowed and its guard covers every purpose. Re-measured on six cases with a control (U-14).
  - SC-7 is scoped, and D-9 gains the `Select` empty-cell rule and the in-memory rule.
  - E-42 re-visits its output and errors on an unconsumed chain.
  - U-24 gains five shapes. U-25's cost mechanism is corrected.
  - TO-14, TO-19 (instrument: `GetCompiledQueryInfo()`), TO-21, TO-23, TO-24, TO-25, TO-27 and TO-28 are rewritten.
  - Three P10 lines are added and one corrected.

- **A-18 (2026-10-22) — A-17 implemented; deviations and measurements.** Pushed: `45847489e` (E-43), `0c22609a6` (A-17),
  `d74874b08` (TO-28 arm), `beceff21f` (compiled-query doc), `23caaaac4` (shared models), after two stack syncs
  (#5949 → `a17f3384e`, this branch → `07af8c439`). `test-all` build 24543.
  - **Errors (E-46).** In-memory invocation reuses `Error_QueryMarkerInvoked` rather than a new constant. Added:
    `Error_PivotTerminalNotAMember`, `Error_PivotChainNotFromGroup`, `Error_PivotNoTerminal`, `Error_PivotSelectAfterCells`
    (Select after Cell/Cells, a shape D-9 left undefined), `Error_PivotReadsQueryParameter`, `Error_PivotLambdaNotInline`,
    `Error_PivotAggregateNotInline`, `Error_PivotArgumentNull`. Every expander error is a `LinqToDBException`; the name
    rules threw `ArgumentException` at call time before.
  - **Member position (E-42).** Expose tracks where a terminal may stand: a member assignment's value, a constructor
    argument, a lambda body, through `Convert`/`TypeAs`. Anything else is `Error_PivotTerminalNotAMember` (pinned as a
    method argument and inside `Where`). A lambda body counts, so the cells can be the whole projection
    (`PivotsAsTheWholeProjection`, and the eager-load arm of TO-26).
  - **TO-25 (v) premise refuted.** With E-42 returning the expansion un-visited, the `[ExpressionMethod]` + `Sql.Property`
    arm stays green (two runs): the builder resolves both later. `Visit(expanded)` is kept to match the sibling arms; no
    test can witness it.
  - **TO-19.** Slot cells red under "drop `RecordMaterializedArgumentSlots`" (`array2`, `mixed2` read 10 instead of 20),
    green with it. A closure-held set is read at the first build and keyed on nothing, so a later change is not seen.
    Probe (SQLite.Classic, compiled, capture changed between calls): scalar in `Where` re-read; `Sql.Property` name,
    `FromSql` text and the `Pivot` value set all reuse the first build. That is #6045's compiled-table key gap, wider than
    its raw-SQL scope; widened by comment. **User decision (option A):** the fix is an engine PR on #6045; #5708 documents
    "pass the value set as an argument" on `Pivot`'s `values` and pins the stale arm with a comment naming #6045.
  - **TO-27.** Split per cell-fed terminal (`[Values] CellFeed`); each arm red under the lift mutation.
  - **TO-28.** Both pairs red: dropping `Snapshot` fails the new mutate-in-place arm; dropping the evaluated-value
    `MarkAsValue` fails four inline tests including `InlineUnpivotRereadsColumnNamesFromAMethod`.
  - **TO-11.** Against the branch's previous baselines (baselines/pr_5708): SQLite.Classic 20 same / 8 changed, DuckDB 18 / 6;
    every change is an alias rename or follows a test edit (`ComposesAfterAConstantPivot` gained an `OrderByDescending`).
    No shape change.
  - **#6028 reached by test order.** `AnEmptyCellOverANonNullableColumnReadsNull(SQLite.MS, Templates)` failed only after
    the `Cell` arm: both expand to one tree, so it hit the cached query with the faulted mapper. Alone it passes. The test
    clears the query caches. The coincidence is itself evidence that `Cells(templates)` and `Cell` lower identically.
  - **TO-12 / TO-26 on shared models** (`testing.md` → *Core behaviour is tested on the common models*): parents 2 and 3
    of `Parent`/`Child`, pivoted by `ChildID`, expected from the shared data; the fixture-local `Staff`/`Shift`/category
    tables are gone.
  - **TO-23.** Red on plain / constructor argument / store-less exactly as U-14's control; misfire sweep 687 pass, 0 fail,
    6 skipped (SQLite.Classic).
  - **TO-24.** EF10 SQLite.MS green in both directions.
  - **G-01 (local).** 584/585 on SQLite.Classic/MS + DuckDB (direct + LinqService) before the #6028 fix, then green; the one
    skip is the #6028 gate. Release net10.0 (API analyzers), netstandard2.0, Tests net462, Tests and EF10 Release clean.
  - **D-8.** SelectDynamic PR branch `feature/4992-select-dynamic` (`e88ce53a7`, milestone 6.6.0). Its errors live in
    `ErrorHelper.SelectDynamic`, not a second `ErrorHelper.Pivot` with divergent members; three constants are duplicated
    across the two classes once both merge. `BuildTimeArgumentReader.cs` is byte-identical.

- **A-19 (2026-11-26) — review round 3 (sdanyliv, 2026-10-22) fixed; master merged; #6110 stacked on this branch.**
  Local commits, pushed 2026-11-26: `608048304` (merge `origin/master`; conflicts only in `PublicAPI.Unshipped.txt`, kept as
  master's file + the branch's 47 pivot lines, and in `CountTests` / `GroupByTests`, taken from master since #5949 owns
  them), `4569339e4` (E-53, E-54, E-55, E-59: MAJ002 + MAJ003), `6f7f3ac43` (E-56: MIN208), `ccd0c27a1` (E-57: MIN209),
  `2cad4e701` (E-58: RS0030 after the merge). E-52 records A-17's `DynamicColumnsTests.cs` edits, which P6 never listed
  (`-Action reconcile` reported it unplanned). The approval of record is void for E-52…E-59 until the P12 A-19 round.
  - **SC-16 / SC-17 added.** sdanyliv's MAJ002 and MAJ003 both reproduced as stated (TO-29, TO-30 red first).
  - **Critic round A-19 (`weak`) refuted the first E-54 by probe.** Pushed in `4569339e4`, it rewrote `Get<T>` /
    `(T)cells[name]` in `ExposeExpressionVisitor` for any receiver of static type `PivotCells`. Measured against a control
    with the arms off (SQLite.Classic, direct + remote): cells the client holds, captured by a later `Where`, threw
    "Dynamic column getter is not to be called." (control: row 2); a projected absent name threw (control: `null`);
    `Get<int>` over a decimal cell read 20 (control: `0`) and `Get<string>` threw (control: `null`). The captured-name
    cache lead did not reproduce at that head (both executions correct). User decision: keep the translation, but only
    where SQL is required and only for a receiver from the query; projections keep the in-memory contract. E-54 moved to
    `ExpressionBuildVisitor` (`BuildPurpose.Sql` only), the expose arms were reverted, `[SqlQueryDependent]` keys the
    name (E-55, TO-33's mutant red without it), and Unpivot reads a `Get` / indexer selector itself (E-53).
  - **Leaf collision (critic round A-19, measured).** Two pivots' `Y2000` cells unpivoted as `Y2000` twice. User
    decision: the leaf unless another column reads the same name, then the path (TO-34).
  - **E-56 supersedes E-51's byte-identical copy.** #6110 (`feature/4992-select-dynamic`, merged with this branch at
    `025f1e20f`, base switched to `feature/1475-pivot-unpivot`) restores the lambda and sequence branches and makes its
    `parameterName` optional, so the "argument is a query" refusal applies to `SelectDynamic` callers only.
  - **E-57 supersedes E-46's placement** of three constants; `Error_NoDynamicColumnsStore`'s thrower is the generic
    `VisitMemberInit` check (E-43), which a pivot never reaches.
  - **Body.** The PR body was rewritten for the current scope (MIN207); round-3 threads replied and resolved.
  - re-derives: P2 (SC-16, SC-17), P7 (A-19 rows), P8 (TO-29, TO-30), P9 (G-01 per-obligation record), P10 (the flat-DTO read line).
  - conventions: `testing.md` → *Test layout*, *A narrowed provider set is a claim*, *Gating an assertion failure*, embedded before E-59's tests were written; `test-diff-sweep.ps1 -Repo <worktree> -IncludeWorkingTree` on the A-19 tree: chains 84, nestedChains 4, narrowedSets 25, narrowedWithoutReason 5, localModels 1, shouldlySubjectGates 0, typeOnlyShouldlyGates 0, continuationIndents 0, unanchoredAssertionGates 0, narrowedContinuations 0, cacheMissOutsideQueryCacheTest 0, handDuplicatedAreEqual 0, invisibleChars 0, issueNamedMembers 0, attributePadding 0, issueFixtureFiles 0.
    The redesign's tests first added 5 one-line chains (89); split, back to 84, so E-59's lines carry none. The 84 chains,
    4 nested chains, 5 narrowed sets without a reason line and the `QuarterlyKeys` local model predate A-19; each is
    named as a review item for this round rather than fixed unasked.

- **A-20 (2026-11-26) — review round 4 (`/review-pr 5708`, three `code-reviewer` passes at `bf00c3547`) fixed.**
  Local commits, unpushed at writing: `28c9baef2` (E-60: MAJ, a row-dependent cell name threw on the second execution),
  `f6c79e56e` (E-61: `Get<T>` in a SQL position casts to `T`; an absent name is `Error_PivotCellNotFound`), `389f41b28`
  (E-62: MIN310, a cast chain over a cell read in an Unpivot selector), `c21463507` (E-63: MIN411, `Sql.Property` over an
  `IReadOnlyDictionary`-typed member), `b2a1db833` (E-64, part of E-65: SUG001, MIN412-414, SUG202), `8f2029f35` (E-65's
  layout pass: NIT001, NIT201-211). Every finding was probed with the SQL-position translation on and off before its fix;
  each walk disposition was **fix here** (user). The approval of record is void for E-60…E-65 until the P12 A-20 round.
  - **SC-17 reworded**: the SQL-position read casts to `T` (user decision at the walk: a `Get<int>` over a decimal cell
    reads the cell converted, not `0`), and an absent name in a SQL position is a named error rather than the getter's
    "Dynamic column getter is not to be called." Projections keep A-19's in-memory contract unchanged.
  - **E-60 supersedes E-55's attribute.** `[SqlQueryDependent]` compared a row-dependent name by evaluating it at the
    cache compare (`EqualsToVisitor` → `ExpressionsEqual`), which threw for a name reading the row parameter; the internal
    attribute compares such an argument structurally and keeps value comparison for everything else (TO-35).
  - **E-63's `Project` branch only.** The `SqlGenericConstructorExpression` branch was tried and is not reached by TO-41's
    shape (removing it left TO-41 green), so it was not kept.
  - **Held cells copied into a query row** (finding F): "could not be converted" with the translation off, so not a
    regression; now E-61's named error. No change.
  - **Cache cost of a captured name** in a projection-only read: P10 line, accepted (user).
  - re-derives: P2 (SC-17), P7 (A-20 rows), P8 (TO-35…TO-41), P9 (G-01 per-obligation record, A-20), P10 (the captured-name cache-cost line).
  - conventions: `testing.md` → *Test layout*, *A narrowed provider set is a claim*, *Gating an assertion failure*, embedded for E-65's tests; `test-diff-sweep.ps1 -Repo <worktree>` at `8f2029f35`: chains 0, nestedChains 0, narrowedSets 26, narrowedWithoutReason 0, localModels 1, shouldlySubjectGates 0, typeOnlyShouldlyGates 0, continuationIndents 0, unanchoredAssertionGates 0, narrowedContinuations 0, cacheMissOutsideQueryCacheTest 0, handDuplicatedAreEqual 0, invisibleChars 0, issueNamedMembers 0, attributePadding 0, issueFixtureFiles 0.
    The layout pass cleared A-19's review items (84 chains, 4 nested chains, 5 unreasoned narrowed sets → 0). The one
    added narrowed set is TO-37's, with its reason line. `QuarterlyKeys` (`PivotTests.cs:113`) remains the local model:
    two key columns over `MonthlySales`, which no shared model carries.

- **A-21 (2026-11-26) — critic round A-20's measured defects fixed here** (user: fix before pushing round 4). The approval of
  record is void for E-66…E-71 until the P12 A-21 round.
  - **Unpivot read type (objection 2).** E-62 typed the access as the read's type, while the pivot binds the cell as
    its aggregate's type, and the projection rebuilt the result's constructor over the cell's type (`VisitNew`,
    `ExpressionBuildVisitor.cs:1072`). E-66 reads the cell as `object` and converts it, and E-70 lets that conversion
    survive the projection's visit (TO-42; TO-40 regressed under E-66 alone and is green with E-70).
  - **Cast receiver (objection 3).** `GetColumnName` stopped its path walk at the `Convert` around the receiver (TO-43).
  - **`Concat` (objection 7).** The generic-constructor branch E-63 dropped is reached by a set operation (TO-44).
  - **Named errors (objections 4, 5).** A `T` the cell has no conversion to and an absent name in a grouping key or an aggregate (TO-45).
  - **TO-38 (objection 1)** is rewritten against a self-calibrating provider control. The provider semantics it exposes get a P10 line.
  - **Objection 8 (E-60's value-compare clause has no witness): confirmed, and the clause is removed (E-71).** Measured
    on SQLite.Classic, direct and `LinqService`: with every argument compared structurally, TO-33, TO-35, TO-36 and
    TO-37 stay green (10/10). Expose folds a known name to a constant before the cache compare, so the value branch never
    decides anything. My prediction (TO-33 red, via a closure-field access) was wrong. Dropping the attribute altogether
    is still red (TO-36's mutant), so what the attribute does is the folding; the compare is plain structural.
  - **Aggregate absent-name (objection 5, partly).** A grouping key now names the cell. A top-level aggregate does not,
    and that limit is a P10 line.
  - re-derives: P2 (SC-17), P7 (A-21 rows), P8 (TO-38, TO-42…TO-51), P10 (the three A-21 lines).
  - conventions: `testing.md` → *Test layout*, *A narrowed provider set is a claim*, *Gating an assertion failure*, embedded before E-69's tests were written; `test-diff-sweep.ps1 -Repo <worktree>` at `21936d936`: chains 2, nestedChains 0, narrowedSets 27, narrowedWithoutReason 0, localModels 1, shouldlySubjectGates 0, typeOnlyShouldlyGates 0, continuationIndents 0, unanchoredAssertionGates 0, narrowedContinuations 0, cacheMissOutsideQueryCacheTest 0, handDuplicatedAreEqual 0, invisibleChars 0, issueNamedMembers 0, attributePadding 0, issueFixtureFiles 0.
    The 2 chains are TO-43's selector arguments (`PivotDynamicTests.cs:1445-1446` at `5b93d343a`,
    `x => ((PivotCells)x.Total).Get<decimal?>("Y2000")`). Each is one call over a cast receiver, which the sweep reads
    as a continuation after `)`, so they are a false positive: the cast receiver is the shape under test. One narrowed set
    is added (TO-50, SQLite-only for its SQL text, with its reason line); `QuarterlyKeys` is A-20's.

- **A-22 (2026-11-27) — the gap the round-4 postmortem's reader-shape re-run found (P12, *Postmortem*).** No `TO-n` pinned
  the sub-query wrap, so E-72 adds TO-52 for it. The edit is test-only; the approval of record is void for E-72 until the
  P12 A-22 round.
  - re-derives: P7 (A-22 row), P8 (TO-52).
  - conventions: `testing.md` → *Test layout*, *A narrowed provider set is a claim*, the exception-assertion form and *Test Patterns*, embedded before E-72's test was written; `test-diff-sweep.ps1 -Repo <worktree> -IncludeWorkingTree` on the A-22 tree: chains 2, nestedChains 0, narrowedSets 27, narrowedWithoutReason 0, localModels 1, shouldlySubjectGates 0, typeOnlyShouldlyGates 0, continuationIndents 0, unanchoredAssertionGates 0, narrowedContinuations 0, cacheMissOutsideQueryCacheTest 0, handDuplicatedAreEqual 0, invisibleChars 0, issueNamedMembers 0, attributePadding 0, issueFixtureFiles 0, shouldlyThrowAssertions 0, regionBlocks 0.
    The 2 chains are A-21's TO-43 false positives; TO-52 adds none.

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

**Round 3 (A-15 delta) — `refuted`** (Fable). Searched: the full 916ce0eeb..e0935d57f diff; every `CreateSubQuery = ` setter and every `GetContext` override; `[BuildsExpression]`/`[BuildsAny]` builders; all `.Unpivot(` call shapes in the corpus; `CorrectAlias` and its call sites; `VisitIsNullPredicate`; `IsCollectionType` consumers and `TypeAccessor` member enumeration for the new `IReadOnlyDictionary`; remaining `SelectDynamic` wording.

1. *The probe reuse breaks `Unpivot` in sub-query position over a projected source* — `ContextRefBuilder` re-resolves through `GetContext` when `CreateSubQuery` is set, and `SelectContext` cannot build its projection body as a sequence. → probed red (SQLite, direct + LinqService), fixed root-only (f550159e9), test added; A-15 re-recorded.
2. *The tag fix is overstated* — branches 2..N still rebuild the source. → A-15 now says N per N columns; N=2 pinned.
3. *The `ExcludeNulls` row change has no P10 line* — → added.

Checked clean by the critic: the placement fix (`Find`+`Replace` before the generic-constructor wrap, mirrored by `IsConstructedWith`), alias sanitization covering every generated name, the lifted `IS NOT NULL` folding away for non-nullable columns, `PivotCells` as a collection type reaching no eager-load/association path, explicit interface members not colliding with cell names.

**Round A-19 — `weak`** (Fable, delta only: E-52…E-59, SC-16/17, TO-29/30, the A-19 rows; read-only). Searched: the four commits `608048304..2cad4e701` in full, the merge's three conflict files, the moved constants repo-wide, the `Unpivot` signatures, `GetConstructorEx`, `PivotCells`' members, `IsCompilable` sites in expose, `ReplaceDynamicColumnGetters`, every Pivot test's data-source attribute. Objections and what changed:

1. *E-54 rewrites a captured, materialized `PivotCells`* → probed red (TO-31); E-54 redesigned (A-19).
2. *The name is not query-dependent* → did not reproduce against the expose rewrite; the redesign reads the name after the key, so `[SqlQueryDependent]` was added and TO-33's mutant proves it necessary.
3. *E-53's leaf fallback collides* → probed (two `Y2000`); fallback to the path on collision (TO-34).
4. *TO-30's data does not separate* → accepted; filter `> 16` and an ascending order that differs from the grouping order.
5. *Projection semantics changed* → probed red (TO-32); the redesign keeps projections in memory.
6. *`ConvertChecked` and a cast receiver unprobed* → `checked` probed green; the cast receiver fails "could not be converted" in both earlier arms, unprobed under the redesign (P7).
7. *Provider evidence is one provider* → SQLite.Classic/MS + DuckDB run on the A-19 tree; container providers rest on CI.
8. *Fact sheet vs P9* → P9 records the per-provider runs.

Confirmed clean: E-56 (no `Unpivot` overload reaches the removed branches), E-57 (no stale reference), E-58 (equivalent), the merge resolution (+47 Unshipped lines over master; `CountTests` / `GroupByTests` identical to master), E-53's mapped-column path.

**Round A-20 — `weak`** (Fable, delta only: E-60…E-65, SC-17, TO-35…TO-41, TO-34's value arm, the A-20 P7 rows, the A-20 P10 line; read-only, nothing run). Searched: `bf00c3547..8f2029f35` in full; every `SqlQueryDependent(Value)?Attribute` / `ExpressionsEqual` / `PrepareForCache` reader at `8f2029f35`; `ExpressionBuildVisitor.cs:2713-2763,2862-2977`; `UnpivotBuilder.cs:149-235`; both `Project` branches (`ExpressionBuilder.SqlBuilder.cs:1395-1483,1573-1678`); every `Cells.Get<` / `Cells[` read under `Tests/`. Every lead was then probed (scratch fixture, SQLite.Classic + DuckDB, direct + `LinqService`, Testing net11.0, at `8f2029f35`; all four contexts agree). Data: `A` Y2000 10 / Y2010 20.6, `B` 5 / 15, `C` 7 / no Y2010.

1. *TO-38's whole amounts cannot tell the cast from a typed read.* → measured: `Where(Get<int>("Y2010") == 20)` reads `A` and `== 21` reads none on both providers (the cell is 20.6); `Distinct` reads `0, 15, 20`; a projection reads `0, 0, 0` (the in-memory contract). `Where(Get<int>("Y2010") == 0)` reads none for `C`, whose cell is NULL (SQL NULL semantics; the projection reads `0`). Open: TO-38's input.
2. *(lead) E-62 does not convert an Unpivot cell read to the read's type.* → **measured defect**: `x => x.Cells.Get<int>("Y2010")` and `x => (int?)x.Cells["Y2010"]` over a `decimal?` cell throw `ArgumentException` ("Argument type 'decimal?' does not match the corresponding member type 'int'" / "'int?'"). TO-40 passed only because it writes the `decimal?` conversion itself.
3. *(lead) A cast receiver loses its path in Unpivot.* → **measured defect**: `((PivotCells)x.Total).Get<decimal?>("Y2000")` and `((PivotCells)x.Top)…` over two `IReadOnlyDictionary` members unpivot both as `Y2000` (SC-16's collision fallback does not fire); `Sql.Property` over the same members reads `Top.Y2000` / `Total.Y2000`.
4. *E-61 names an existing cell as absent when `T` has no DB type.* → not as predicted: `Where(Get<Uri>("Y2010") != null)` throws an unnamed `InvalidOperationException` ("No coercion operator is defined between types 'decimal?' and 'Uri'"). Open: named error or accepted.
5. *A grouping key and an aggregate have no obligation.* → measured: `GroupBy(Get<decimal?>(…))`, `GroupBy(Get<int>(…))`, `Sum(Get<decimal?>(…))` and `Sum(Get<int>(…))` read correctly (`Sum(Get<int>)` 35). **An absent name there is not the named error**: "… could not be converted to SQL" in both positions, against SC-17's "an absent name in a SQL position is a named error".
6. *Provider sweep is SQLite + DuckDB only.* → not answered by probe; container providers, Access and SqlCe rest on CI.
7. *(lead) E-63's dropped generic-constructor branch.* → **measured defect**: `Sql.Property` over an interface-typed member after `Concat` fails "'r.Cells.Y2010' could not be converted to SQL"; after `AsSubQuery()` and after `OrderBy().Take()` it reads `A`.
8. *E-60's value-compare clause has no witness that reddens alone.* → measured: a mixed name (`r.Key == "A" ? first : "Y2010"`, `first` a method argument changed between calls) re-reads correctly in a projection (`10, 15, null` then `20.6, 15, null`); in a `Where` it is "could not be converted" (a row-dependent name is declined in a SQL position, A-19's design). The clause's own witness stays open.
9. *P7 row cites `ExpressionBuilder.QueryBuilder.cs:474` as covered; it is `RegisterExtensionAccessors`, and `QueryExtensionBuilder.cs:109` is unlisted.* → accepted; P7 row corrected.

Critic's strongest confirmation: E-60 gives a row-dependent name the structural compare an unattributed argument gets and leaves an evaluable name to the constant folding that already keys the cache (TO-35 red→green).

Disposition (user, 2026-11-26): fix before pushing. Objections 1-5, 7 and 8 are answered in A-21 (E-66…E-71, TO-38's rewrite, TO-42…TO-45) and go to round A-21. Objection 6 rests on CI.

**Round A-21 — `weak`** (Fable, delta only: E-66…E-71, SC-17's A-21 sentence, the A-21 P7 rows, TO-38 / TO-42…TO-45, G-01's A-21 record, the two A-21 P10 lines; read-only, nothing run). Searched: `8f2029f35..0b1e2bb9b` in full; `IsCritical` across `Source/LinqToDB`; `SqlQueryDependentValue|ExpressionsEqual(` and `GetQueryDependentAttributes`; `DynamicColumnInfo` producers and both `Project` branches; `RegisterUnary|op_Explicit`; `ForSetProjection` in `Linq/Builder`; `Sql.Property<object>` / `Sql.Property(x, ` under `Tests`; every converting cell read in `Tests/Linq`. Objections and what changed (A-21, second pass, on the uncommitted tree over `0b1e2bb9b`):

1. *TO-38's control is not a provider cast*: `(int)x.Amount!.Value` in a plain projection stays on the client (`ExpressionBuildVisitor.cs:2895-2898`), so the test compared the cell's SQL cast with C# truncation. → Accepted. The control is `Select((int)x.Amount!.Value).Distinct()`, which `DistinctBuilder` builds as SQL; `castOfA` the same over category `A`.
2. *E-70 also fires under `ForSetProjection` (a multi-column Unpivot), untested with a type-changing read.* → Accepted, together with 3: E-70 no longer converts on the client (below), and TO-46 unpivots two converting columns.
3. *The Unpivot conversion is a C# conversion, not the provider's; TO-42's whole amounts cannot tell; IncludeNulls × non-nullable `T` is unwitnessed; the `!= null` filter casts in SQL while the value casts in C#.* → Accepted. E-61's read and E-70 now share `ReadPivotCellAs`, which resolves the cell in `Sql` purpose and casts the resolved column in SQL, in every purpose, so the value, the filter and a `Where` read the same cast for the conversion directly over the cell; a further conversion the selector writes (TO-40's outer `(int?)`) stays on the client, as over any column. TO-46: a fractional cell over two columns against the provider's own SQL cast, and IncludeNulls over an empty cell (`(int?)cells[…]` → `null`, `Get<int>` → `0`).
4. *The unnamed-error class survives on the Unpivot path.* → Accepted, and measured: `Unpivot(…, x => x.Cells.Get<Uri>(…))` threw the BCL "No coercion operator" from the `!= null` filter's `Sql`-purpose visit, which E-70 excluded. E-70 now applies in every purpose, so `ReadPivotCellAs`'s conversion check names it (TO-45's Unpivot arm).
5. *The misfire check for E-70 cannot say no.* → Answered by narrowing: E-70 fires only for a `DynamicColumnInfo` declared on `PivotCells` over a receiver from the query, so an entity's dynamic column never reaches it.
6. *E-68's `IsScalarType` gate is a closed list.* → Accepted. The gate is now "the resolved cell's type has a CLR conversion to `T`" (`Expression.Convert` succeeds), which is exactly the operation that threw. A type with a user conversion is read as before.
7. *Stale citation `:3490`.* → Corrected to `:3515` (`DeclinedForSetProjection`).

Confirmed clean by the critic: E-71 is behaviour-neutral by construction (a client-evaluable argument is folded to a constant before the compare, `ExposeExpressionVisitor.cs:204-219`); E-67 cannot unmatch a base-declared assignment (`IsEqualMembers` → `EqualsTo`, `ExpressionBuilder.SqlBuilder.cs:1863-1877`); E-66's path walk.

Not re-attacked: the second-pass revision of E-68 / E-70 and TO-38 / TO-45 / TO-46 goes to round A-21 re-check.

**Round A-21 re-check — `weak`** (Fable, scope: the second pass `0b1e2bb9b..47d9b9f29`, E-68 / E-70, the E-70 reach row, TO-38 / TO-45 / TO-46; read-only). Searched: the two commits in full; `new DynamicColumnInfo(` across `Source/` (8 sites); `TryGetPivotCellRead|ReadPivotCellAs|Error_PivotCell*`; purpose gates around `VisitUnary`; `FloorBeforeConvert`; `Sql.Property<object>` under `Tests/`. Objections 1-6 of round A-21 resolved by reading; the re-check's own, and what changed (`b0194aceb`):

- A. *"The provider's CAST" is wrong for DuckDB / MySQL / Firebird / DB2*, which `FLOOR` before the cast (`FloorBeforeConvert`). So the fractional arms cannot tell a SQL cast from a client one there. → Accepted; P7 and P10 reworded, and the separation is stated to rest on a rounding engine's CI leg.
- B. *(lead) Control vs aggregate cell may floor differently.* → Measured equal on DuckDB at `47d9b9f29` and `b0194aceb`. MySQL / Firebird / DB2 rest on CI.
- C. *The arm forced a `Sql` build in every purpose*, unwalked outside `Sql` / `Expression` / `ForSetProjection`. → Accepted. `ReadPivotCellAs` runs in `Sql` / `Expression` only; other passes visit the operand in their own purpose and rebuild the conversion. A fall-through gate was tried first and measured TO-40 red. TO-47 reads the value inside a result-selector subquery.
- D. *`Sql.Property<object>` over cells under a cast has no test; the `PivotCells`-only gate excluded an interface-declared read.* → Accepted. The gate admits interfaces `PivotCells` implements (never `object`). TO-48 covers both arms.
- E. *Named errors in the `Expression`-purpose Unpivot column unwitnessed.* → Accepted. TO-45 gains the IncludeNulls `Get<Uri>` arm and an absent name in a column.
- F. *Stale rows* ("no scalar mapping", TO-46 missing from SC-17 / E-69 / `re-derives:`, `:3515`). → Corrected; `:3530-3532`.
- G. *"Same cast" holds for the innermost conversion only.* → Scoped in objection 3's answer above.

Strongest confirmation (critic): the helper resolves the cell in `Sql` purpose and casts the resolved placeholder. That removes the client/SQL split and the BCL validation path together, and re-entry is impossible by node type.

Not re-attacked: `b0194aceb` goes to round A-21 final delta.

**Round A-21 final delta — `weak`** (Fable, scope `47d9b9f29..b0194aceb` and the E-70 / TO-45 / TO-47 / TO-48 / provider-semantics rows; read-only). Searched: `git show b0194aceb`; `ReadPivotCellAs|HasConversion\(|TryGetPivotCellRead`; `FloorBeforeConvert` across `Source` (seven provider callers); `bool IsFloatType`; `new DynamicColumnInfo(` producers; `BuildPurpose.(Expand|Extract)` / `UsingBuildPurpose`; `IsCritical`. Re-check objections B, E and G resolved; A, C, D and F partly. Open:

1. *The `FloorBeforeConvert` list is short by Oracle, PostgreSQL and SQL Server*, so no named CI leg rounds. → Accepted; P7 / P10 corrected. The SQL-vs-client separation is not pinned by rows on any provider.
2. *(lead) The non-`Sql`/`Expression` branch's rebuilt conversion has no separating witness.* TO-40 and TO-47 rebuild `decimal?` → `decimal?` (an identity), and nothing reaches the "through `object`" clause. If a later building pass sees the rebuilt node, it no longer matches E-70, so it would convert on the client, throw for IncludeNulls `(int)`, or fail unnamed for `Uri`. Which pass reaches the branch is unprobed. → **Open.**
3. *TO-47 has no recorded red* (not run at `47d9b9f29`, nor under the fall-through mutant). → **Open.**
4. *TO-48's interface arm has no mutation* (`== typeof(PivotCells)` may stay green), and its `(decimal?)` over a decimal cell cannot show a conversion. → **Open.**
5. *The interface admission reopens the misfire class*: `(T)Sql.Property<object>(x.AnyDictionaryMember, n)` over a non-pivot `IReadOnlyDictionary` / `IEnumerable` member reads `Error_PivotCellNotFound`. Low reach. → Recorded in P7, unprobed. **Open.**
6. *Stale rows* (`:3542`, P7 "covered by", the producer sentence). → Corrected.

Strongest confirmation (critic): the non-fall-through form of the purpose gate is backed by a measured red on three providers, and TO-45's IncludeNulls arms isolate the `Expression`-purpose column read.

Disposition (user, 2026-11-27): one more pass. What it measured (SQLite.Classic, direct + `LinqService`):
- Objection 2: an instrumented run (the branch throwing its purpose and flags) puts only `Extract` in the branch, from TO-40, TO-49's `Get<Uri>` arm and TO-50. The branch now returns the node unchanged. Mutation M1 (the `b0194aceb` rebuild) is green on all 133 `PivotDynamicTests` cases, SQL text included. So the rebuilt node does not reach the building pass, the lead does not reproduce, and the simpler form is kept. TO-49 and TO-50 add the type-changing route through later operators and the SQL-text control.
- Objection 3: TO-47 does not reach the branch; it is relabelled a characterization of the result selector.
- Objection 4: mutation M2 (`== typeof(PivotCells)`) turns TO-48's interface arm red with the BCL validation error. TO-48 is red→green.
- Objection 5: reach searched, P10 line, no test.

Not re-attacked: E-70's final branch, TO-47's relabel and TO-48 / TO-49 / TO-50 go to round A-21 close.

**Round A-21 close — `weak`** (Fable, scope `b0194aceb..5b93d343a` and the E-70 / reach / TO-47…TO-50 / interface-admission rows; read-only). Searched: `git show 5b93d343a`; `BuildPurpose.Extract|BuildExtractExpression|IsExtractProjection` (five callers, each read for whether the result is consumed); `BuildPurpose.(Traverse|Expand)`; `new DynamicColumnInfo(`; `class PivotCells`; `SelectMany|.Update(|.Merge(|.Join(` in the Pivot tests. Final-delta objections 2 and 3 resolved, 4 half and 5 not; its own, and what changed (`21936d936`):

1. *"The `Extract` result is not what the building pass converts" holds only where it is discarded* (`SelectBuilder.cs:39`, `MergeBuilder.Using.cs:30`). It is consumed at `SelectManyBuilder.cs:97`, `UpdateBuilder.cs:199` and `MergeProjectionHelper.cs:61`, and no Pivot test has a `SelectMany`. → Accepted. The sentence is narrowed. TO-51 runs the `SelectMany` route (with and without a result selector, under `DefaultIfEmpty`, and `Get<Uri>`) green with the node returned. `Update` / `Merge` are stated untested.
2. *The admission also takes `DynamicObject` and `IDynamicMetaObjectProvider`.* → Accepted. The gate is now `PivotCells` or an interface it implements, so `DynamicObject` is out. P10 lists the admitted interfaces.
3. *Stale coverage: TO-47 is still cited for the purpose gate, and TO-49 / TO-50 are omitted.* → Corrected.
4. *TO-50 is a control with no red.* → Mutation M3 (`ReadPivotCellAs` converts on the client) turns it red with no `CAST(`. In the same run M3 reddens 28 more cases, filters and Unpivot NULL filters among them ("could not be converted").
5. *TO-48 does not change type.* → An `(int)` arm through the interface-typed member was added.

Strongest confirmation (critic): M2 reddens TO-48's interface arm with the exact pre-E-70 BCL error, and returning the node is correct by construction where `SelectBuilder.cs:39` discards the `Extract` result.

Not re-attacked: the `21936d936` revision (the gate narrowing, TO-48's `int` arm, TO-51), recorded here as measured. This was the round the user budgeted as final.

Not re-attacked: `db434dc32`. It declares `Error_PivotCellType` in `PublicAPI.Unshipped.txt` after the master merge `033cef246` and changes no behaviour.

**Postmortem (gap ledger round 4) — the three accepted rules re-run over this plan** (`/work-plan` postmortem step 4; run 2026-11-27 on the plan as it stands):
- Fold-in naming (`work-plan.ps1` `-Done` error; `work-plan.md` → *A critic objection folded in after the verdict*): **hit.** `db434dc32` was unnamed after the last critic-reviewed commit `21936d936`, and is now named above. Resolved from the primary clone, the check now reads the `feature/1475-pivot-unpivot` worktree rather than master.
- Test conventions (`shouldlyThrowAssertions` / `regionBlocks`, the "dispositioned in A-n" deferral, the review-item option for adopted commits only): **hit.** A-19's G-01 sweep line deferred its own 84 chains as "dispositioned in A-19"; it now records that A-20 (`8f2029f35`) fixed them. The new categories read 28 / 2 at `bf00c3547`, the round-4 head, and 0 / 0 at `db434dc32`.
- Reader shapes (`SKILL.md` step 5 and *Mode: amend*, `plan-critic.md` vector 4), over D-6 / D-7 / D-9 and the readers E-53, E-54, E-61, E-62, E-66 and E-70: **one gap.** Conversions above and below the match (TO-40, TO-42), the cast receiver (TO-43, TO-41), the interface-typed member (TO-41, TO-44, TO-48), a read as another type (TO-38, TO-42, TO-46, TO-49) and set operation / `SelectMany` (TO-44, TO-46, TO-51) are each pinned. The sub-query wrap is not: `AsSubQuery()` over an interface-typed member was probed green in critic round A-20's probe P7a, but has no `TO-n`.

**Round A-22 — `weak`** (Fable, scope A-22 / E-72 / TO-52 and the *Postmortem* block, test-only `b29e48f24`; read-only). Searched: `AsSubQuery` across `Linq/Builder` (`AsSubQueryBuilder.cs:15-21` always wraps, with `DoNotRemove`); `AsSubQuery` across `PivotDynamicTests.cs` (only the new call sites, which confirms the gap); the reader routes (`ExpressionBuildVisitor.cs:832`, `:2715`, `:2787`; `UnpivotBuilder.cs:152-181`); the correlated `Any` cell read at `PivotDynamicTests.cs:269`. Objections and what changed:

1. *The `Get<T>` filter route (`TryGetPivotCellRead`) has no arm under the wrap.* → Accepted. TO-52 gains `Where(r.Cells.Get<decimal?>(…))` over a `PivotCells` member and `((PivotCells)r.Cells).Get<decimal?>(…)` over the interface-typed one, both under `AsSubQuery()`.
2. *Arm 3 puts no cell reader under the wrap.* → Accepted; TO-52 now counts it as a consumer arm.
3. *Row assertions cannot see the wrap itself.* → Accepted as stated: TO-52 is characterization, red on a throw or a wrong or missing column under the wrap.
4. *Stale "the other two are unprobed".* → Removed.

Not checked by the critic: emitted SQL, container providers, an implicit wrap (`Take` / `Distinct`, then a filter), and a cast receiver × wrap in an Unpivot column.

Not re-attacked: `b26ab1b30` (the added `Get<T>` arms), recorded as measured in G-01.

**Round 3 re-check — `holds`** (Fable, same session). Re-traced every `CreateSubQuery = true` entry point against f550159e9: the branch choice is made before the lowering, so `ContextRefBuilder` is only reached with the flag clear and returns the probe directly; no intermediate builder sets it. Pending, not a defect: the container-provider matrix has not run on f550159e9.

**Round 8 (A-17 delta) — `refuted`** (Fable). Searched:
- `ExposeExpressionVisitor.cs:99-310`, plus the master drift;
- `LegacyMemberConverterBase` and the interceptor / preprocessor implementations (EF `TransformExpressionVisitor.cs:304-310`, F# `FSharpQueryExpressionInterceptor.fs:395-419`);
- `QueryCache.TryFind`/`BuildKey`, `ExpressionCacheHelpers`, `ExpressionCacheManager`, `ExpressionEqualityComparer.cs:746-780`, `DynamicColumnInfo.Equals`;
- `CompiledQuery.cs:70-130`, `DependentArgumentValues`, every `IncrementMissCount` site;
- `ExpressionBuildVisitor.cs:911-1049,2441-2452`, `ParseGenericConstructor` with its 17 call sites, `MergeProjectionHelper`, `EagerLoadUnion`, `EntityConstructorBase.cs:545-641`, `SqlGenericConstructorExpression(MemberInitExpression)`;
- `ExpressionEvaluator.cs:112-124`;
- the `PivotDynamicTests` shapes, `DynamicColumnsTests.cs:403-417`, `BannedSymbols.txt`.

Objections and what changed:

1. *(refuting) SC-7/TO-14/TO-27 cannot hold for `Select`.* The user's lambda fixes the member type, so there is nothing to lift, and U-9 says a non-nullable member reads `0`. → Accepted. SC-7 is scoped to the `Cell`-fed terminals; D-9 states `Select`'s rule; TO-14 is rewritten (user lift + a non-nullable arm); TO-27 is scoped; there is a P10 line.
2. *TO-19's `GetCacheMissCount` cannot see a `CompiledTable` build* (`Query{T}.cs:63,194`). → Accepted. The instrument is now `GetCompiledQueryInfo()` same-instance, master's `FromSql_Compiled_ArgumentArray` idiom.
3. *Reader shapes missing* (captured-`Func` aggregate / `forColumn`, correlated `values`, a chain with no terminal). → Accepted. U-24 (i)–(iv), TO-25 cells, E-46 constants; E-42 errors on an unconsumed chain.
4. *U-25 cost prose wrong.* A pivot misses the raw bucket every time and runs the whole expose; inline factories compile per execution. → Accepted. U-25 and P10 are rewritten.
5. *E-42 does not say it re-visits.* → Accepted. `return Visit(expanded)`, with TO-25 (v) for an `[ExpressionMethod]` in the cell body.
6. *SC-15's guard is Expression-arm only, and the predicate is loose.* → Accepted, and **probed**: the guard runs for every purpose, the conversion only under `BuildPurpose.Expression`.
7. *Constructor-argument and zero-value reaches unmeasured.* → **Probed** (U-14 round 8): with the narrowed edit 13/13 pass on six cases. The control on the unfixed engine shows constructor-argument, plain and store-less failing, and zero values, composition and `Concat` already passing.
8. *TO-28's mutant does not reach its witness; E-51 cannot be literally verbatim* (`PivotSugarBuilder.cs:132`). → Accepted. Two mutant/witness pairs; E-51 names the one changed reference.
9. *TO-24 type-only; TO-23's sweep cannot go red.* → Accepted. The message is pinned; the sweep is relabelled "misfire check".
10. *U-28 was terminal-blind.* → Recorded in U-28 / D-9; (a) applies to all terminals, and `PivotCell.Create` works anywhere.
11. *Master's `ValuesEqual` type check.* → Noted in TO-19.

Not accepted: none.

Critic's strongest confirmation: cache identity by construction is real. The flags are in the bucket key, scalar literals are keyed by value, non-scalar constants get path accessors into the incoming tree, and `DynamicColumnInfo` equality is name-keyed. The compiled path records slots through the `[SqlQueryDependent]` mechanism.

Could not verify (critic): whether Access's `ThrowsRequiredOuterJoins` gate survives the `SelectDynamicBuilder` → `SelectBuilder` route change (TO-11's baselines control is the instrument); the F# interceptor beyond its dispatch.

**Round 8 re-check — `weak`** (Fable). All eleven objections answered, each checked against code. It searched:
- the revised blocks;
- `GetCompiledQueryInfo` on master (`QueryUtils.cs:141-152`) and `CompiledTable{T}.cs:46-105,163-203`;
- `PivotTests.cs:340-361`;
- the `ForSetProjection` callers against the new D-7 predicate;
- `PivotSugarBuilder.cs:42-83,159-161`.

It confirmed that the unconsumed-chain error has no false positive: expose is top-down and the terminal consumes its chain first. Three residual items, all applied:
1. *TO-26 named a `ForSetProjection` arm D-7 no longer has, and its `Concat` red premise contradicted U-14's control.* → `Concat` is now characterization; eager load is red→green against "E-43's conversion removed".
2. *TO-19's instrument needs `IQueryable<T>`-returning compiled lambdas.* → Stated.
3. *TO-28's second witness never mutates in place.* → The extension is unconditional and is listed under E-50.

Unverified by the critic: the round-8 probe results themselves (taken as measured), and TO-26's eager-load arm.
