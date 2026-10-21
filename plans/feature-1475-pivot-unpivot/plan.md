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
- **A-17: cells always land in a nested `PivotCells` member, never in `TResult`'s own `[DynamicColumnsStore]`** (D-9's failure mode). A flat DTO reads its cells through `Sql.Property(r.Cells, …)` or the dictionary view.
- **A-17: the pivot is no longer an `IQueryable` operator.** Someone looking for `.Pivot` on a table finds `Unpivot` and not `Pivot` (sdanyliv: top-level sugar can be added later if discoverability matters). Not added here.
- **A-17: no performance claim, either way, for the expose-time expansion** (U-25). Mechanism, not timed: a pivot query runs the full expose pass and the expansion on every execution, because its raw tree can never hit the cache. Each inline or method-group name factory is compiled once per execution. The PR body must state it this way, not as "one extra lookup".
- **A-17: the `Select` terminal does not lift** (D-9). An empty cell reads what the user's member type materializes from `NULL`, so the same data can read `null` through `AsDictionary` and `0` through a non-nullable `Select` member. Documented on `Select`; pinned by TO-14.
- **A-17: `AssertQuery` cannot drive a pivot test.** Its expected side runs the query in memory, where U-28 (a) throws; the ported tests assert values directly.
- **A-17: F# is not claimed** (U-22). The XML docs and the PR body speak about C# query and method syntax only.
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
