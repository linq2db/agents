# Work plan: feature-1404-query-batch — QueryBatch: several reads in one round trip

**Tier:** L  ·  **Status:** approved  ·  **Approved-at:** 2026-10-22 (user, after critic round 2)  ·  **Branch:** feature/1404-query-batch
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

Stacked on PR #5673 (`feature/query-batches` @ `7fb8f933d9`); every `-Action reconcile` runs with `-Base origin/feature/query-batches`. Probe evidence below was measured on 2026-10-22 against this worktree with a scratch Playground fixture (`Tests/Tests.Playground/QueryBatchProbe.cs`, never committed) on SQLite.MS, SQLite.MS.LinqService, SqlServer.2019.MS, PostgreSQL.16 and DuckDB.

## P1 Problem

Absent capability, [#1404](https://github.com/linq2db/linq2db/issues/1404): linq2db has no way to send several independent reads in one round trip. The headline case — a page plus its total count — costs two round trips today: `var total = q.Count(); var page = q.Skip(s).Take(n).ToList();`. Measured: the closest existing shape, `db.Select(() => new { Total = q.Count(), Page = q.Skip(s).Take(n).ToList() })`, already builds as one main query (`Total` a scalar subquery) plus one detached eager child (`DetachedHarvester<T>`, `ExpressionBuilder.EagerLoad.cs:404-423`), and sends **2** commands under the 6.x default (`UseCombinedCommands = false`) on SQLite, SQL Server and PostgreSQL; **1** only when the context opts into combined commands. There is no per-query way to ask for the one-command form, no named API a user would find, and the shape is refused outright under `ImplicitCollectionLoading.Throw` (measured: `LinqToDBException` "Implicit eager loading is not allowed" on all four providers).

## P2 Success criteria

- SC-1 `QueryBatch` returns, for each result, the same value the user would get by running that part alone, on every provider family.  → TO-1
- SC-2 On a `DataConnection` whose provider sets both `IsMultiStatementBatchSupported` and `IsMultipleResultSetsSupported` (SQLite, SQL Server, PostgreSQL, MySQL), a `QueryBatch` holding at least one collection sends exactly one command whatever `UseCombinedCommands` is.  → TO-2, TO-3
- SC-3 A plain `db.Select` of the same shape keeps its current behaviour — 2 commands with the option off — and does not share a cache entry with the `QueryBatch` form.  → TO-4, TO-5
- SC-4 Where combining cannot run — a provider without both flags, a `DataContext`, a `.LinqService` context, pending query hints — `QueryBatch` falls back to the existing sequential eager path with the same values.  → TO-6, TO-7, TO-8, TO-9
- SC-5 Every element terminal kind works inside `QueryBatch`: Any, All, Contains, Sum, Min, Max, Average, LongCount, First (scalar member), First (entity), FirstOrDefault over an empty set, Single, SingleOrDefault over an empty set, two collections, scalars only.  → TO-10 … TO-24
- SC-6 The tuple overloads of arity 2 … 7 return each result at its own position.  → TO-25 … TO-30
- SC-7 The async overloads match the sync ones in values and in command count.  → TO-31
- SC-8 `ImplicitCollectionLoading.Throw` does not refuse a collection inside `QueryBatch`, while it still refuses the same projection through `db.Select`.  → TO-32
- SC-9 A second call with different captured values reuses the cached query and returns the new values.  → TO-33
- SC-10 With a collection present, the batch runs inside one implicit transaction at `DefaultMultiQueryIsolationLevel`; none is opened inside a `TransactionScope` or an existing transaction; a scalars-only batch is one statement and opens none.  → TO-34, TO-35, TO-36, TO-37
- SC-11 A `QueryBatch` node nested inside another query does not switch that query to combined commands.  → TO-38
- SC-12 A user-configured `DefaultEagerLoadingStrategy` (KeyedQuery, CteUnion) does not stop a `QueryBatch` from combining — including a body whose collection carries its own nested correlated collection.  → TO-39
- SC-13 Both execution backends produce the same values with `UseCombinedCommands` off: DbBatch (SQL Server / PostgreSQL, no interceptor) and concat (SQLite, or any provider with a command interceptor registered).  → TO-40, TO-41
- SC-14 Existing behaviour is unchanged: eager-loading and combined-command suites stay green and baselines do not move for tests that do not call `QueryBatch`.  → TO-42
- SC-15 An explicit `With*LoadStrategy()` inside a `QueryBatch` body is overridden by the batch's Default (outermost marker wins), and the XML remarks say so.  → TO-43

## P3 Constraints & anti-goals (M/L)

- Public API is additive only: `LinqExtensions.QueryBatch` / `QueryBatchAsync` overloads and the `Methods.LinqToDB.QueryBatch` handle (internal namespace). No existing public member changes signature.
- No SQL change for any query that does not contain a `QueryBatch` node; no change to `UseCombinedCommands` semantics for those queries; no change to eager-loading strategies outside a `QueryBatch` context.
- Query-cache keys of existing queries unchanged.
- Anti-goal — narrowing of #1404's stated scope, disclosed in the PR body ("Part of #1404", not `Fixes`): the issue also asks for deferred writes with a value from one statement feeding the next (the insert-graph prototype), subset flushing ("groups"), and handles registered across call sites (`DeferValue` / `CompleteDefer`). None is in this PR; the statement-lambda `Scenario` direction is the recorded future home for writes and forwarding.
- Anti-goal: no pending state on the context — no registry, no flush, no Dispose behaviour.
- User-visible deltas vs the parent branch (#5673): one new API family. No existing call changes behaviour. Master's shipped prose: none restates a contract this changes (searched `<summary>` of `LinqExtensions.Select` / `SelectAsync`, `LinqExtensions.cs:30-99`).

## P4 Unknowns (M/L)

- U-1 Does the FROM-less `db.Select` path build a scalar plus a collection as main query + detached child, and how many commands does it send? — resolved-by probe: SQLite.MS / SqlServer.2019.MS / PostgreSQL.16 send 1 command with `UseCombinedCommands(true)` and 2 without; DuckDB sends 2 either way; values `Total=10 Page=[3,4,5]` on all.
- U-2 Does a programmatically built `Expression.New(ValueTuple<int, List<T>>)` over two lambda bodies take the same path, with and without member bindings? — resolved-by probe: both forms give the same counts and values as U-1 on all four providers.
- U-3 Can the tuple overloads use a tuple literal inside `Expression<Func<…>>`? — resolved-by probe: no, `error CS8143: An expression tree may not contain a tuple literal` (net10.0, LangVersion preview, scratchpad compile).
- U-4 Does each element terminal translate inside such a projection? — resolved-by probe: all 15 kinds of SC-5 return correct values on SQLite.MS, SqlServer.2019.MS, PostgreSQL.16 and DuckDB, 1 command on the three combined-capable providers.
- U-5 Does `ImplicitCollectionLoading.Throw` refuse a top-level collection here? — resolved-by probe: yes, on all four providers, with `Error_ImplicitEagerLoadingNotAllowed`.
- U-6 Where can a marker become a per-query flag? — resolved-by scout: `db.Select` uses its own public method as the expression node (`Methods.LinqToDB.Select = dc.Select(() => 1)`, `Methods.cs:212`; `LinqExtensions.cs:48-53`); `ScalarSelectBuilder` dispatches on it (`ScalarSelectBuilder.cs:11-16`); `[BuildsMethodCall]` takes up to eight names (`Attributes.cs:38-45`); `ExpressionBuilder` owns `_query` (`ExpressionBuilder.cs:53`) and fills it in `BuildQuery` (`:254-275`).
- U-7 Does a second call with different captured values hit the cache? — resolved-by probe: `Query<T>.CacheMissCount` delta 0, values follow the new `take` (2 then 4) on all four providers.
- U-8 Is the implicit read transaction already there? — resolved-by probe: with a collection, one `BeginTransaction` traced on every direct provider; scalars only, none and one command.
- U-9 Which backend runs? — resolved-by probe: DbBatch (`-- Batch` markers) on SqlServer.2019.MS and PostgreSQL.16 with no interceptor; concat on SQLite.MS.
- U-10 What do `DataContext` and remote do? — resolved-by probe: `DataContext` sends 2 commands with one transaction; SQLite.MS.LinqService sends 2 and opens no transaction (the remote client never starts the load transaction, `Query.cs:243-269`) — pre-existing eager behaviour, recorded in P10.
- U-11 Is `QueryBatch` free as a name? — resolved-by scout: no occurrence in `Source/`, `Tests/` or `PublicAPI*.txt` of this worktree; nearest names are remote `BeginBatch`/`CommitBatch` (`RemoteDataContextBase.cs:556-597`) and `DbBatch`.
- U-12 Does an explicit eager strategy on the modifier skip the implicit-load guard? — resolved-by scout: the guard runs only when `context.TranslationModifier.EagerLoadingStrategy == null` (`ExpressionBuilder.QueryBuilder.cs:210`), read from the root context; `TranslationModifier.WithEagerLoadingStrategy` exists (`TranslationModifier.cs:135`). TO-32 proves it end to end.
- U-13 Which other code recognises the `db.Select` node and so must also recognise `QueryBatch`? — resolved-by scout: by `MethodInfo` — searched `Methods.LinqToDB.Select` and `IsSameGenericMethod(Methods.LinqToDB.` across `Source/`: consumers are `ExpressionTreeOptimizationContext.cs:196` and `ScalarSelectBuilder.cs:11-16`; by declaring type — `typeof(LinqExtensions)` checks (`InternalExtensions.cs:249`, `JoinBuilder.cs:24`) are not name-specific; by name — the `nameof(Queryable.Select)` / `nameof(Enumerable.Select)` recognisers (`ExpressionBuilder.Aggregation.cs:226,609,658`, `ExpressionBuilder.EagerLoad.cs:182,311`, `ExpressionBuilder.EagerLoadKeyedQuery.cs:676`, `InternalExtensions.cs:267`, `TranslationContextExtensions.cs:280`) match a `db.Select` node only as an eager-load sequence, which `ScalarSelectContext.IsSingleElement => true` (`ScalarSelectBuilder.cs:35`) prevents at the sole `new SqlEagerLoadExpression` site (`ExpressionBuildVisitor.cs:3211-3214`), so neither node reaches them (critic search, 2026-10-22).
- U-16 How do the child builds of a `QueryBatch` get their eager strategy, and what happens to a nested correlated collection under a non-default global strategy? — resolved-by probe + scout: children are built after `BuildMethodCall` returns (`ExpressionBuilder.EagerLoadDefault.cs:65`) and take `builder.GetTranslationModifier()` (`ExpressionBuilder.SqlBuilder.cs:1132-1137`), which `ResolveStrategy` reads (`ExpressionBuilder.EagerLoad.cs:546-549`). Measured with `UseCombinedCommands(true)` on SQLite.MS, SqlServer.2019.MS, PostgreSQL.16, body `Page = deps.Select(d => new { d.Id, Items = emps.Where(e => e.DepId == d.Id).ToList() }).ToList()`: Default readers=1, KeyedQuery readers=3, CteUnion readers=1 begins=0 (one statement); the flat body readers=1 under all three; values identical. A modifier pushed with `isTemporary: false` on an empty stack becomes `_globalModifier` (`ExpressionBuilder.SqlBuilder.cs:1115-1123`) and so reaches every later context — the `InlineParametersBuilder` precedent (`InlineParametersBuilder.cs:16`).
- U-17 Is MySQL combined-capable as SC-2 claims? — resolved-by scout: both flags set (`MySqlDataProvider.cs:68-69`, with a multi-statement connection-string note at `:62-67`); the parent's `CombinedEagerLoad_HonoursDbBatchBackend` runs `AllMySql` on both backends (`EagerLoadingTests.cs:3950-3959`). Not measured locally; CI is the measurement, and TO-2 takes its expectation from `UsesCombinedQueryBatch()` rather than a provider list.
- U-18 Does DbBatch run when combining is forced with `UseCombinedCommands` off? — resolved-by scout: the combined eager executor reads `CanUseDbBatch` directly (`QueryRunner.cs:946`), which does not consult the option (`DataConnection.cs:1114-1121`); U-9 was measured with the option on, so TO-40 is the measurement.
- U-14 Can the builder tell a root-level `QueryBatch` from one nested in another query? — resolved-by scout: `BuildInfo.IsSubQuery => Parent != null` (`BuildInfo.cs:39`).
- U-15 Can the harness count round trips on both backends? — resolved-by probe: tracing `BeforeExecute` with `TraceOperation.ExecuteReader` counted 1 on DbBatch and on concat; an interceptor forces concat (`DataConnection.cs:1114-1121`).

## P5 Decisions (M/L; rejected alternatives mandatory at L)

### D-1 — `QueryBatch` is a transformation into the `db.Select` path

- **chosen:** `QueryBatch<T>(IDataContext, Expression<Func<T>>)` builds the same call shape as `db.Select` (`LinqExtensions.cs:41-99`) with its own public method as the node; the arity-2…7 overloads fuse their lambda bodies into one `Expression.New(ValueTuple<…>)` and call it. Results come back through the existing eager machinery.
- **rejected:** context-level futures (`DeferValue` / `CompleteDefer`, the 2019 prototype) — needs a pending registry, Dispose behaviour, flush triggers and failure fan-out, and independent builds collide on `AccessorId` in one `SqlParameterValues` (scout: `ParametersContext.cs:21`, `SqlParameterValues.cs:11,27-32`, `OptimizationContext.cs:69,80-88`); a tuple literal (CS8143, U-3); an explicit batch object in the Marten style — only needed to register queries across call sites, which no requirement here asks for; an `IQueryable`-returning form over the shipped sibling `DataExtensions.SelectQuery` (`DataExtensions.cs:1601-1614`, `SelectQueryBuilder.cs:7-31`) — it would compose with `ToListAsync` and save the async overloads, but a batch is consumed once for its results, tuple deconstruction needs a value, and a composable node could be wrapped by `Where`/`Select` into a non-root position where D-6 silently turns combining off.
- **why this:** one builder means one `ParametersContext`, the query cache (U-7), the implicit transaction (U-8) and plain exception semantics for free.
- **failure mode of the choice:** every limit of a projection is a limit of `QueryBatch` — a body linq2db cannot project fails as that projection would, and queries cannot be added from another method.

### D-2 — `QueryBatch` forces combined commands for its own query

- **chosen:** `ScalarSelectBuilder`, on a root-level `QueryBatch` node, sets a builder flag that `BuildQuery` copies to `Query.CombinedCommandsRequested`; `TryGetCombinedEagerEnumerable` (`QueryRunner.cs:1083`) proceeds when `UseCombinedCommands || query.CombinedCommandsRequested`. Every other gate condition (`DataConnection`, both provider flags, no hints, `IsProcessQueryOverridden`, combinable and order-safe harvesters, `QueryRunner.cs:1069-1116`) still applies.
- **rejected:** honouring `UseCombinedCommands` only — the headline case would still cost two round trips under the 6.x default; a public per-query opt-in usable on any eager load — wider surface and test matrix, can follow later; toggling the option per call — options are per context, not per query.
- **why this:** calling `QueryBatch` is itself the request to combine (user decision 2026-10-22). The node is a different method from `db.Select`, so the flag is part of the query-cache key and a plain `db.Select` of the same shape is unaffected.
- **failure mode of the choice:** a flag set from a nested `QueryBatch` would leak into the enclosing query — prevented by D-6. Separating input for the gate: the same projection through `db.Select` (2 commands) and through `QueryBatch` (1) with the option off.

### D-3 — a root-level `QueryBatch` sets a build-wide Default eager strategy

- **chosen:** before building the root `ScalarSelectContext`, `ScalarSelectBuilder` pushes `GetTranslationModifier().WithEagerLoadingStrategy(EagerLoadingStrategy.Default)` with `isTemporary: false` (and pops the stack afterwards). On the root the stack is empty, so the modifier becomes `_globalModifier` (`ExpressionBuilder.SqlBuilder.cs:1115-1123`) and every later context — the root, the detached children built in `FinalizeProjection`, and their nested children — resolves Default through `ResolveStrategy` (`ExpressionBuilder.EagerLoad.cs:546-549`). The same move `InlineParametersBuilder` makes for `InlineParameters` (`InlineParametersBuilder.cs:16`). The root context's modifier also skips the implicit-load guard (`ExpressionBuilder.QueryBuilder.cs:210`) — the collections are explicit by construction.
- **rejected:** the modifier on the root context only — measured (U-16): a nested correlated collection under a global KeyedQuery then resolves KeyedQuery, is buffered and non-combinable (`ExpressionBuilder.EagerLoadKeyedQuery.cs:863,1185`, `ExpressionBuilder.EagerLoadDefault.cs:170`), 3 commands; tagging collections `MarkerType.ExplicitEagerLoad` the way `LoadWith` does (`EntityConstructorBase.cs:258`) — exempts the guard but leaves the user's strategy in charge; leaving the strategy unset — same 3 commands; pinning only when the global strategy is KeyedQuery — CteUnion's one-statement form is also one round trip, but a per-strategy rule is one more thing to document and test for a choice the user did not ask to keep.
- **why this:** one existing mechanism, applied at the scope the problem lives at; the strategy every child resolves is the combinable one.
- **failure mode of the choice:** a user who set CteUnion or KeyedQuery globally gets Default inside `QueryBatch` (still one round trip; CteUnion's would have been one statement). An explicit `With*LoadStrategy()` written inside a body is **overridden**: `WithLoadStrategyBuilder` skips its push whenever a strategy is already set ("the outermost marker wins", `WithLoadStrategyBuilder.cs:27-30`), and after the root push it always is. That is the existing precedence rule applied to an outer marker, and it is what keeps the batch combinable, so it is the intended behaviour: stated in E-1's XML remarks and pinned by TO-43. Separating input: the nested-collection body of U-16 under `DefaultEagerLoadingStrategy = KeyedQuery` — 1 command with the build-wide modifier, 3 with a context-only one (TO-39).

### D-4 — Allowed bodies

- **chosen:** anything linq2db can project: terminals over linq2db queryables (scalar → subquery of the main SELECT, collection → detached eager child) and client arithmetic over them.
- **rejected:** a dedicated validator restricting bodies to terminal calls — duplicates the projection builder's own errors and blocks useful shapes such as `(q.Count() + 9) / 10`.
- **why this:** the projection builder already defines what is translatable.
- **failure mode of the choice:** a correlated body (one referencing another body's row) cannot occur — the bodies have no shared row — but a body referencing a server-only function in client arithmetic fails at build like any projection.

### D-5 — Arity and naming

- **chosen:** `QueryBatch<T>` / `QueryBatchAsync<T>` for one selector (anonymous types and DTOs for named results), plus tuple overloads of arity 2…7, sync and async. Seven is the flat `ValueTuple` limit; beyond it the anonymous-type form applies. Name `QueryBatch` (U-11).
- **rejected:** `Defer*` names — nothing is deferred any more; overloading `db.Select` — would make combining implicit and change the meaning of an existing method; arity 8+ — `ValueTuple` nests `TRest`.
- **why this:** deconstruction `var (total, page) = db.QueryBatch(…)` covers the headline case; named results stay available.
- **failure mode of the choice:** an eighth result forces a switch of form.

### D-6 — Only a root-level `QueryBatch` requests combining

- **chosen:** `ScalarSelectBuilder` sets the flag only when `!buildInfo.IsSubQuery` (`BuildInfo.cs:39`); a nested `QueryBatch` builds as a plain scalar select.
- **rejected:** setting it unconditionally — a `QueryBatch` inside a larger query would switch that whole query to combined commands; throwing on nesting — `db.Select` is legal nested (`ScalarSelectBuilder.cs:33-35`), so `QueryBatch` should not be stricter.
- **why this:** the opt-in belongs to the call the user made.
- **failure mode of the choice:** none known beyond the nested batch running uncombined. Separating input: a query with a `QueryBatch` node in its projection and the option off — TO-38.

## P6 Edit-points

- E-1 `Source/LinqToDB/LinqExtensions/LinqExtensions.QueryBatch.cs` — new partial: `QueryBatch<T>` / `QueryBatchAsync<T>` with the self-referential node (pattern: LinqExtensions.cs lines 41-99), arity-2…7 tuple overloads fusing bodies via `Expression.New(ValueTuple<…>)`; XML docs restate SC-2, SC-4, SC-8, SC-15 and D-3's override of `DefaultEagerLoadingStrategy`.
- E-2 `Source/LinqToDB/Internal/Reflection/Methods.cs:Methods.LinqToDB.QueryBatch` — MethodInfo beside `Select` (`:212`).
- E-3 `Source/LinqToDB/Internal/Linq/Builder/ScalarSelectBuilder.cs:ScalarSelectBuilder` — `[BuildsMethodCall("Select", "QueryBatch")]`, `CanBuildMethod` accepts both; for a root-level `QueryBatch` node (`!buildInfo.IsSubQuery`) request combined commands on the builder (D-2, D-6) and push the Default-strategy modifier with `isTemporary: false` around building the context (D-3).
- E-4 `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuilder.cs:Build` — builder flag, copied onto the root `_query` in `Build<T>` (`:254-275`), not in `BuildQuery<T>` (`:283`), which also runs per harvester child query.
- E-5 `Source/LinqToDB/Internal/Linq/Query.cs:Query.CombinedCommandsRequested` — internal flag.
- E-6 `Source/LinqToDB/Internal/Linq/QueryRunner.cs:TryGetCombinedEagerEnumerable` — gate at `:1083` accepts the flag.
- E-7 `Source/LinqToDB/Internal/Linq/Builder/ExpressionTreeOptimizationContext.cs:VisitMethodCall` — treat the `QueryBatch` node like `Select` at `:196` (not client-evaluable).
- E-8 `Source/LinqToDB/PublicAPI/PublicAPI.Unshipped.txt` — the new public members.
- E-9 `Tests/Linq/Linq/QueryBatchTests.cs` — new fixture, namespace `Tests.Linq`.
- E-10 `Tests/Base/TestExtensions.cs:UsesCombinedQueryBatch` — predicate: `DataConnection`, both provider flags, no pending hints (mirrors `UsesCombinedEagerLoading` at TestExtensions.cs lines 45-60, minus the option).

## P7 Impact map (M/L)

- `Source/LinqToDB/LinqExtensions/LinqExtensions.cs:41-99` (`Select` / `SelectAsync`) — the template E-1 copies; unchanged — out-of-scope
- `Source/LinqToDB/Internal/Reflection/Methods.cs:212` (`Methods.LinqToDB.Select`, public static field in an internal namespace, `PublicAPI.Shipped.txt:15915`) — sibling handle added — covered by E-2
- `Source/LinqToDB/Internal/Linq/Builder/ScalarSelectBuilder.cs:11-16` — the only builder for the node; searched `Methods.LinqToDB.Select` across `Source/` — covered by E-3
- `Source/LinqToDB/Internal/Linq/Builder/ExpressionTreeOptimizationContext.cs:196` — second and last consumer of `Methods.LinqToDB.Select` (same search) — covered by E-7
- `Source/LinqToDB/Internal/Linq/Builder/SelectBuilder.cs:14` — `[BuildsMethodCall("Select")]` for `Queryable.Select`, keyed by method, not name; unaffected — out-of-scope
- `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuilder.QueryBuilder.cs:210` — implicit-load guard reads the modifier's strategy; D-3 relies on it, no edit — covered by E-3
- `Source/LinqToDB/Internal/Linq/QueryRunner.cs:1069-1116` — all eight fallback conditions of the combined gate; only `:1083` changes — covered by E-6
- `Source/LinqToDB/Data/DataConnection.QueryRunner.cs:326`, `Source/LinqToDB/Internal/SqlProvider/ScenarioCommandRenderer.cs:266`, `Source/LinqToDB/Remote/RemoteDataContextBase.QueryRunner.cs:98`, `Source/LinqToDB/LinqOptions.cs:387` — the other readers of `UseCombinedCommands` (searched `UseCombinedCommands` across `Source/LinqToDB`, 5 readers): DML pre-render, scenario planning, remote GetSqlText plan and the configuration ID; none is on the combined eager path, whose executor reads `CanUseDbBatch` directly (`QueryRunner.cs:946`) and renders `_query.QueryInfo.Statement` (`:877-880`) — out-of-scope
- `Source/LinqToDB/DataExtensions.cs:1601-1614` + `Source/LinqToDB/Internal/Linq/Builder/SelectQueryBuilder.cs:7-31` (`db.SelectQuery`, the `IQueryable` sibling of `db.Select`) — not reused, recorded as a rejected alternative in D-1 — out-of-scope
- `nameof(Queryable.Select)` / `nameof(Enumerable.Select)` recognisers (`ExpressionBuilder.Aggregation.cs:226,609,658`, `ExpressionBuilder.EagerLoad.cs:182,311`, `ExpressionBuilder.EagerLoadKeyedQuery.cs:676`, `InternalExtensions.cs:267`, `TranslationContextExtensions.cs:280`) — match by name; unreachable for a scalar-select node because `ScalarSelectContext.IsSingleElement` stops eager wrapping at `ExpressionBuildVisitor.cs:3211-3214` (U-13) — out-of-scope
- `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuilder.SqlBuilder.cs:1115-1137` (`PushTranslationModifier` / `GetTranslationModifier`) — D-3 relies on the `isTemporary: false` global path, no edit — covered by E-3
- `Source/LinqToDB/Internal/Linq/Builder/WithLoadStrategyBuilder.cs:27-34` — a `With*LoadStrategy()` inside a body finds the batch's strategy already set and skips its push ("outermost marker wins"), so the batch's Default overrides it; intended per D-3, documented in E-1's remarks, pinned by TO-43 — covered by E-1
- `Source/LinqToDB/Internal/Linq/Query.cs:215-269` (`StartLoadTransaction` / `GetTransactionOwner`) — supplies SC-10 unchanged (U-8) — out-of-scope
- `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuilder.cs:254-275` (`Build<T>`, the root `_query` only; `BuildQuery<T>` at `:283` runs per harvester child and is not where the flag is copied) — covered by E-4
- `Source/LinqToDB/Remote/RemoteDataContextBase.QueryRunner.cs` — remote eager runs sequentially; the client never sees the flag's gate (`QueryRunner.cs:1086` requires `DataConnection`) — deferred: remote combining is outside #5673 and this PR
- `Source/LinqToDB/DataContext.cs` — `DataContext` never reaches the combined gate (`QueryRunner.cs:1086`) — deferred: same limit as eager loading; P10
- Query cache key — the node is a different `MethodInfo`, so cache entries separate by construction; searched `QueryCache`/`ExpressionCacheManager` for method-specific key logic, none — Localized — searched `Methods.LinqToDB.Select` and `IsSameGenericMethod(Methods.LinqToDB.` across `Source/LinqToDB/Internal/Linq/`, no key-specific handling.
- Serialized / wire shapes — the node never crosses the wire (remote serializes the built statement, not the expression); no enum or contract added — Localized — searched `QueryElementType`, `SqlProviderFlags` and `LinqServiceSerializer` for any change this design needs, none.
- `Source/LinqToDB/PublicAPI/PublicAPI.Unshipped.txt` — additions only — covered by E-8
- User-facing docs — XML docs on the new overloads only; no readme or wiki row lists `db.Select`-style APIs — covered by E-1

## P8 Test obligations (M/L)

Conventions (`.claude/docs/testing.md` → *Test layout*, *A narrowed provider set is a claim*, *Gating an assertion failure*): fixture `Tests/Linq/Linq/QueryBatchTests.cs`; one call per line in chains; scalar results compared with `ShouldBe` against an in-memory expected; every narrowed provider set states its reason on the line above; counts are asserted only on direct contexts. Round trips are counted with tracing `BeforeExecute` + `TraceOperation.ExecuteReader`, transactions with `TraceOperation.BeginTransaction` (`InterceptorsTests.cs:1500-1559`); the combined expectation comes from `UsesCombinedQueryBatch()` (E-10), the two-arm pattern of `CombinedDmlTests.cs:59-96`.

- TO-1 values: `(q.Count(), q.OrderBy(Id).Skip(2).Take(3).ToList())` equals the separately run parts on a 10-row seed with NULLs — providers: [DataSources] — proof: red→green (red: API absent, compile failure first; then value mismatch under mutation "swap Item1/Item2 binding order")
- TO-2 one command with `UseCombinedCommands(false)` when `UsesCombinedQueryBatch()`: `readers == 1` — providers: [DataSources(false)] — proof: red→green (mutation "drop `|| query.CombinedCommandsRequested` from the gate" → 2)
- TO-3 one command with `UseCombinedCommands(true)` as well — providers: [DataSources(false)] — proof: characterization
- TO-4 control: the same projection through `db.Select` with the option off sends 2 where `UsesCombinedQueryBatch()` — providers: [DataSources(false)] — proof: control (mutation "set the flag for every ScalarSelect node" → 1)
- TO-5 cache separation: `db.Select` then `QueryBatch` of the same shape in one test both keep their counts (2 then 1) — providers: SQLite (concat discriminates the flag as well as DbBatch does) — proof: control (mutation "key the flag off `Methods.LinqToDB.Select` too")
- TO-6 non-capable provider: DuckDB / Firebird / Access legs send 2 with correct values — providers: [DataSources(false)] filtered by `!UsesCombinedQueryBatch()` — proof: characterization
- TO-7 `DataContext`: correct values, 2 commands — providers: SQLite, SqlServer (the gate's `DataConnection` check is provider-independent) — proof: characterization
- TO-8 remote: correct values on `.LinqService` legs — providers: [DataSources] remote legs — proof: characterization
- TO-9 pending `NextQueryHints`: on the sequential fallback the child harvester runs first (`Query{T}.cs:67`), so the hint is asserted on the FIRST traced command and `NextQueryHints` is empty afterwards; values correct, 2 commands — providers: SqlServer (a provider where hints render) — proof: control (mutation "remove the hints condition from the gate" → 1 command, hint absent from every command text)
- TO-10 Any — providers: [DataSources] — proof: characterization (U-4 measured green; guards the shape)
- TO-11 All — providers: [DataSources] — proof: characterization
- TO-12 Contains — providers: [DataSources] — proof: characterization
- TO-13 Sum over a nullable column — providers: [DataSources] — proof: characterization
- TO-14 Min — providers: [DataSources] — proof: characterization
- TO-15 Max — providers: [DataSources] — proof: characterization
- TO-16 Average — providers: [DataSources] — proof: characterization
- TO-17 LongCount — providers: [DataSources] — proof: characterization
- TO-18 First, scalar member — providers: [DataSources] — proof: characterization
- TO-19 First, entity — providers: [DataSources] (APPLY/LATERAL providers included: SqlServer, PostgreSQL) — proof: characterization
- TO-20 FirstOrDefault over an empty set → null — providers: [DataSources] — proof: characterization
- TO-21 Single — providers: [DataSources] — proof: characterization
- TO-22 SingleOrDefault over an empty set → null — providers: [DataSources] — proof: characterization
- TO-23 two collections → one command where combined — providers: [DataSources(false)] — proof: characterization
- TO-24 scalars only → one command and no transaction on every provider — providers: [DataSources(false)] — proof: characterization
- TO-25 arity 2: distinct types per position (int, List<T>) — providers: SQLite (positions are builder-level, provider-independent) — proof: red→green (mutation "pass bodies in reverse order")
- TO-26 arity 3 (int, string, List<T>) — providers: SQLite — proof: red→green (same mutation)
- TO-27 arity 4 — providers: SQLite — proof: red→green (same mutation)
- TO-28 arity 5 — providers: SQLite — proof: red→green (same mutation)
- TO-29 arity 6 — providers: SQLite — proof: red→green (same mutation)
- TO-30 arity 7 — providers: SQLite — proof: red→green (same mutation)
- TO-31 async: `QueryBatchAsync` arity 1 and 2 match sync values and counts — providers: [DataSources(false)] — proof: red→green (mutation "async overload calls the sync Select path" → count unchanged but `IsAsync` false in trace)
- TO-32 `ImplicitCollectionLoading.Throw`: `QueryBatch` succeeds, `db.Select` of the same shape throws `Error_ImplicitEagerLoadingNotAllowed` — providers: [DataSources(false)] — proof: control (mutation "omit `WithEagerLoadingStrategy`" → `QueryBatch` throws)
- TO-33 cache: two calls with `take` 2 then 4 → `CacheMissCount` delta 0, page sizes 2 and 4 — providers: SQLite, SqlServer (concat and DbBatch) — proof: characterization
- TO-34 transaction with a collection: `begins == 1` — providers: [DataSources(false)] — proof: characterization (U-8)
- TO-35 inside `TransactionScope`: `begins == 0`, values correct — providers: SqlServer, SQLite — proof: characterization
- TO-36 inside an explicit transaction: `begins == 0` — providers: [DataSources(false)] — proof: characterization
- TO-37 scalars only: `begins == 0`, one command — providers: [DataSources(false)] — proof: characterization
- TO-38 a scalar `QueryBatch` nested in a query that eager-loads its own collection, option off — `parents.Select(p => new { p.Id, N = db.QueryBatch(() => children.Count()), Kids = p.Children.ToList() })` — sends the same 2 commands, with the same texts, as the query with `db.Select(() => children.Count())` in that position (the enclosing collection gives `TryGetCombinedEagerEnumerable` harvesters to gate, `QueryRunner.cs:1077-1078`; a scalar body is what a nested scalar select translates) — providers: SQLite — proof: control (mutation "drop the `IsSubQuery` check" → 1 command; mutation "drop the E-7 branch" → the nested node is evaluated on the client, an extra command)
- TO-39 nested correlated collection (the U-16 body) under `DefaultEagerLoadingStrategy = KeyedQuery` and `= CteUnion`, option off: `QueryBatch` sends 1 command where `UsesCombinedQueryBatch()`, values equal to the Default run — providers: SQLite, SqlServer, PostgreSQL — proof: red→green (mutation "push the Default modifier with `isTemporary: true`" → 3 commands under KeyedQuery, the count measured in U-16)
- TO-40 DbBatch backend with `UseCombinedCommands(false)`: no interceptor, 1 command, trace text carries `-- Batch` — providers: SqlServer, PostgreSQL — proof: characterization (U-18)
- TO-41 concat backend: a command interceptor registered → no `-- Batch`, same values, 1 command — providers: SqlServer, PostgreSQL, SQLite — proof: characterization
- TO-42 characterization: `EagerLoadingTests`, `EagerLoadingStrategy*Tests`, `CombinedDmlTests`, `CombinedCommandsExtensibilityTests` green and their baselines unchanged — providers: SQLite.MS, SqlServer.2019.MS, PostgreSQL.16 direct + remote — proof: characterization
- TO-43 an explicit `WithKeyedLoadStrategy()` inside a body (`Page = deps.WithKeyedLoadStrategy().Select(d => new { d.Id, Items = emps.Where(e => e.DepId == d.Id).ToList() }).ToList()`) is overridden: 1 command where `UsesCombinedQueryBatch()`, no keyed-buffer shape in the SQL, values equal to the Default run — providers: SQLite, SqlServer, PostgreSQL — proof: characterization (pins D-3's stated override; the same body through `db.Select` with the option on sends 3, the U-16 KeyedQuery count)

E-n → TO-n: E-1 → TO-1, TO-25…TO-31, TO-43; E-2 → TO-1; E-3 → TO-2, TO-32, TO-38, TO-39, TO-43; E-4 → TO-2; E-5 → TO-2; E-6 → TO-2, TO-4; E-7 → TO-38 (the client-evaluability verdict is consumed in nested positions, `ExpressionBuildVisitor.cs:1451,2965,3048,3112`; the root accepts `SqlQueryRootExpression` regardless, `ExpressionTreeOptimizationContext.cs:227-233`); E-8 → G-03; E-9 → all; E-10 → TO-2, TO-6.

## P9 Verification gates

- G-01: skipped — red stage (E-1, E-2, E-7, E-10 in place, no flag, no modifier) failed 21 tests per provider on SQLite.MS / PostgreSQL.16 / SqlServer.2019.MS, every one a count assert or the `ImplicitCollectionLoading.Throw` refusal; green after E-3…E-6. Mutations run on SQLite.MS: M1 TO-2 (gate disjunct dropped → 2), M5 TO-32 (no `WithEagerLoadingStrategy` → throws), M2 TO-39 (`isTemporary: true` → 3 under KeyedQuery, also TO-43 → 3), M3 TO-38 (no `IsSubQuery` → command texts differ), M4 TO-38 (no E-7 branch → `() => 1` fails to translate). Unverified: the named mutations of TO-1, TO-4, TO-5, TO-9, TO-25…TO-31 were not run, so those arms are proven green only.
- G-02: pass — TO-42 filter (QueryBatch + EagerLoading* + CombinedDml + CombinedCommandsExtensibility) on SQLite.MS 621/7 skipped, PostgreSQL.16 536/7, SqlServer.2019.MS 550/7, direct + remote, 0 failed; `snap-baselines` / `diff-baselines`: 0 changed of 16059 existing files, 269 added (eager / combined baselines absent from the local clone before the run, no local reference). Fixture baselines: `ReturnsTheValuesOfEachPart` read before A-1; the rest not individually read.
- G-03: pass — `dotnet build Source/LinqToDB/LinqToDB.csproj -c Release -f net10.0 -p:RunApiAnalyzersDuringBuild=true`; control: removing the `Methods.LinqToDB.QueryBatch` line → RS0016 on that symbol. The same build also reported #5673's stale `QueryElementType.SqlObjectNameExpression` / `SqlFragmentStatement` ordinals (RS0016 / RS0017), fixed on `feature/query-batches` in c9ce13336e. XML docs on every new public member.
- G-04: skipped — `/api-baselines` not run; ApiCompat on the new members is unverified (additions only, no suppression expected).
- G-05: pass — Release `-f net10.0` and `-f netstandard2.0` both succeeded with 0 warnings, binaries rewritten by the run (timestamps checked); `Tests/Base/Tests.Base.csproj -c Release -f net10.0` succeeded (the E-10 `cref`).
- G-06: n/a
- G-07: pass — `Tests/Tests.Playground/QueryBatchProbe.cs` deleted before the commit; 3319460afd lists 10 files, none under `Tests/Tests.Playground/`.
- G-08: pass — TO-2 (M1), TO-38 (M3, M4), TO-39 (M2) each red under its mutation, green on the final tree; see G-01.
- G-09: skipped — no adversarial read of the diff ran before the draft PR #6111.

Delivery path (stacked PR, user-approved 2026-10-22): B-1 local rename to `feature/1404-query-batch` (done); B-2 at the first implementation commit push and `gh pr create --draft --base feature/query-batches --milestone 6.6.0 --assignee @me`, body "Part of #1404" + "Stacked on #5673", title and body confirmed first; B-3 the user links the stack in the GitHub UI, then check the diff shape; B-4 `test-all` only after `baselines/pr_5673` exists; B-5 sync by merging `origin/feature/query-batches`, never rebasing; B-6 on #5673's squash-merge re-cut onto `origin/master` and cherry-pick this branch's own commits.

## P10 Adjudicated (M/L)

- `DataContext` runs a `QueryBatch` sequentially (2 commands): the combined gate requires `DataConnection` (`QueryRunner.cs:1086`), the same limit eager loading has; widening it is a #5673-level change.
- Remote contexts run sequentially and open no read-consistency transaction (measured U-10): the remote client never starts the load transaction for eager queries today (`Query.cs:243-269`); not introduced here.
- No cross-call-site registration (`DeferValue` handles), no deferred writes, no forwarding, no groups — #1404 scope narrowed per P3, disclosed in the PR body.
- Render templates for a `QueryBatch` are cached like any eager query's (`QueryInfo.EagerCommandCache`); no separate cache work.
- A compiled `QueryBatch` runs sequentially: `CompiledTable<T>.Execute` reads the element through `GetElement` with pre-initialised harvesters, never the combined enumerable. This is the same path a compiled `First()` with eager children takes on #5673.
- MySQL multi-statement combining (review item 13) is not measured locally; the `test-all` MySQL legs are the measurement.
- Under mutation M2 (Default pushed temporary) a KeyedQuery-default batch splits as predicted, and a CteUnion-default one fails on SQLite with `near "(": syntax error`: the detached child combines while its nested correlated collection still resolves to CteUnion. The shipped build-wide push never produces that mix. Three natural shapes without `QueryBatch` (option on, CteUnion default, `WithSeparateLoadStrategy()` on a scalar-root collection, on a query root, on a query root with a detached child) were probed on SQLite.MS / PostgreSQL.16 / SqlServer.2019.MS: all return correct values, none reaches it. Unmeasured: a shape that does reach it on #5673 alone.

## P11 Amendments (M/L)

- A-1 (2026-10-22, during implementation; no `E-n` or `D-n` changed) — test mechanics the plan did not foresee.
  - TO-1 / TO-8: `ReturnsTheValuesOfEachPart` runs with tracing, so it writes no SQL baseline. A remote context runs the batch as separate commands (P10), so its baseline differs from the direct one by design and `BaselinesWriter` rejects the pair ("Baselines for remote context doesn't match direct access baselines"). Values are still asserted on every `[DataSources]` context, remote included; the combined SQL shape stays pinned by the `TupleArity*`, `ChangedValuesReuseTheCachedQuery` and `CollectionsAreExplicitLoads` baselines.
  - TO-38: the nested projection also carries a table-free body, `One = db.Select(() => 1)` vs `db.QueryBatch(() => 1)`. With `items.Count()` alone the E-7 mutation stayed green: a body that reads a table is not client-evaluable on its own. With the table-free body M4 is red, as a translation error rather than the extra command the plan predicted.
  - TO-39: the CteUnion arm is characterization, not red→green. CteUnion already sends one statement before the change, so only KeyedQuery shows the override in the command count.
  - re-derives: TO-1, TO-8, TO-38, TO-39 (rewritten above in this entry); G-01 records the observed mutation outcomes. No `SC-n` premise changes.
- A-2 (2026-10-22) — delivery: B-3 done through the Stacks REST API instead of the GitHub UI. `POST repos/linq2db/linq2db/stacks` with `pull_requests: [5673, 6111]` created stack 6112 (trunk `master`). re-derives: none (delivery path only).
- A-3 (2026-10-23) — `/review-pr 6111` round, dispositions by the user in the interactive walk.
  - D-3 (MAJ004): Default is pushed build-wide only where `QueryRunner.CanCombineCommands` holds — `DataConnection` and both provider flags, which the query-cache bucket pins through the context type and configuration. Elsewhere only the root context carries the configured strategy. That keeps SC-8's explicit-load exemption without overriding inner markers. Measured with CteUnion configured, on a SQLite `DataContext` and on DuckDB: `db.Select` 1 reader; `QueryBatch` 3 before the change, 1 after. Pending hints and `IsProcessQueryOverridden` are still checked per execution, so such a build pushes Default and then runs sequentially. SC-12 and SC-15 now hold where the batch combines, and E-1's remarks say so. First cut set no strategy off the combining path: `CollectionsAreExplicitLoads` went red on DuckDB and SqlCe (the U-12 guard), fixed by the root-only strategy.
  - E-3 / E-7 (MIN001): the tuple overloads are nodes of their own: `ScalarSelectBuilder.IsQueryBatch` covers every arity, and `ExpressionTreeOptimizationContext` uses the same predicate. They reach the builder as written when nested or compiled. Bodies are fused by `LinqExtensions.NewQueryBatchTuple`, shared with `Combine`. Mutation (arity 1 only): nested tuple 5 readers instead of 1; compiled tuple fails to translate.
  - MAJ003 (master bug; the user chose to fix it here): `ScalarSelectContext` keeps `buildInfo.Parent`, and a nested context builds its body in the parent's scope for Expression flags. Red before the fix: nested `db.Select(() => db.Child.Count())` returned the enclosing `ParentID` (`SelectScalarTests.NestedInQuery`), and the nested single-form `QueryBatch` read `g.Id`. The Sql-flag `(SELECT body)` path is unchanged; `SubQueryTests.PreserveOrderInSubqueryWithWindowFunction_WithOrder` is green on SqlServer.2019.MS.
  - Item 11 (master bug): `ScalarSelectContext.SetElementSelection` assigns `GetElement`. A compiled `db.Select` or `QueryBatch` with a collection no longer throws an NRE (`CompileTests.CompiledScalarSelectWithCollection`, `CompiledQueryBatch`).
  - Tests: TO-34 counts begins by `TransactionsSupported` (MAJ001). TO-26…TO-30 add `[Values] bool async` (MAJ005). `SkipWithoutTake` pins MAJ002, whose fix is on #5673 (fcfdff1c30). TO-39 and TO-43 are `[DataSources(false)]` (MIN004): on providers that do not combine, they expect the `db.Select` reader count. TO-41 adds `AllMySql`. New: `NestedQueryBatchReturnsItsValue`, `CompiledQueryBatch`, `ConfiguredStrategyStaysWhereNothingCombines`.
  - Access (the user's call, 2026-10-23): excluded from the 11 tests that read a scalar over a table, through a `NoFromlessSubquery` const. Access refuses a FROM-less SELECT holding a subquery ("Query input must contain at least one table or query"; 31 failures on Access.Ace.Odbc, all from tests that existed before this round). `SelectScalarTests.SubQueryAggregate` excludes `AllAccess` for the same shape. Not measured on the commit before this round. After the exclusion: Access.Ace.Odbc 163 passed, 0 failed.
  - Commits: 3ff793e156 (the `db.Select` fixes and their tests, built on its own from an exported tree) and f7afd51105 (the QueryBatch fixes).
  - Sybase (the user's call, 2026-10-23; ae7f6e2340): the first `test-all` on #6111 (GitHub run 39860408293, leg `Lin u_YdbSybase`) failed `EveryTerminalReadsItsValue` for `FirstMember` / `FirstEntity` (`Error_Correlated_Subqueries`) and `FirstOrDefaultEmpty` (`Sybase.Error_JoinToDerivedTableWithTakeInvalid`), direct and remote. The other 12 terminals passed. For those three terminals the test now asserts the refusal on `AllSybase`; the last one is the refusal `SelectScalarTests.SubQueryTest` declares for `db.Select`. Not run locally (no Sybase container); the rerun of `test-all` is the measurement. Azure 24589 and every other GitHub leg were green; #5673's run at 825f99d640 was green on both halves.
  - re-derives: D-3, E-3, E-7, SC-12, SC-15, TO-34, TO-39, TO-41, TO-43; SC-1 / SC-5 hold on every provider except Access.

## P12 Critic verdict (M/L)

Round 1 (plan-critic, model fable, 2026-10-22): **refuted.** Objections and what changed:
- D-3's modifier lived on the root context only; children resolve their strategy from the builder's modifier, so a nested correlated collection under a global KeyedQuery goes sequential and TO-39 could not redden. Probed before accepting (U-16): confirmed, KeyedQuery 3 commands vs Default 1. D-3 rewritten to a build-wide modifier (`isTemporary: false`, the `InlineParametersBuilder` precedent); SC-12 and TO-39 now name the nested body and the measured 3-vs-1 mutation.
- P7 lacked the other `UseCombinedCommands` readers, `db.SelectQuery` and the name-keyed `Select` recognisers: rows added with their searches; `db.SelectQuery` added to D-1's rejected alternatives; U-13 extended.
- E-7 mapped to the wrong obligation: re-mapped to TO-38 with the mutation "drop the E-7 branch".
- G-08 missing: added.
- MySQL named on flags alone: U-17 records that CI is the measurement; TO-2 takes its expectation from `UsesCombinedQueryBatch()`.
- TO-40 never measured with the option off: SC-13 / TO-40 now say so; U-18 records the code path.
- TO-9 did not say which command carries the hint: now the first command.
- E-4 placement unspecified: `Build<T>` on the root `_query`.

What the critic searched is listed in its report (method-keyed, type-keyed and name-keyed `Select` consumers; all `UseCombinedCommands` / `CanUseDbBatch` readers; `IsSubQuery` at every `new BuildInfo(` site; `GetResultFromReader` / `HasKeyedQueryHarvesters` / `HasCteUnionQuery` assignments; `ImplicitCollectionLoading`; `StartLoadTransaction`; `TranslationModifier` push/pop). It found D-1, D-2 and D-6 sound.

Round 2 (same critic, re-attacking the revision): **weak.** It confirmed the revised D-3 by enumerating every `PushTranslationModifier` site (none on the root path, so the stack is empty when the root `ScalarSelectBuilder` runs and the `isTemporary: false` push becomes `_globalModifier`), and noted TO-39's 3-vs-1 arm independently guards that assumption. Objections and what changed — applied after the round, not re-attacked (the skill caps revision at one round):
- D-3's failure mode and the `WithLoadStrategyBuilder` P7 row said an explicit `With*LoadStrategy()` inside a body wins locally; the code does the opposite (`WithLoadStrategyBuilder.cs:27-30`, outermost marker wins). Verified by reading the file. Now stated as the intended behaviour (D-3), added as SC-15 / TO-43, and to E-1's XML remarks.
- TO-38 had no shape both mutations could change: now an enclosing query with its own eager-loaded collection and a scalar nested body.
- The `ExpressionBuilder.cs:254-275` P7 row was stale against E-4: now names `Build<T>` and the root `_query`.

Carried verdict: **weak**, with every objection answered in the text above; the remaining unprobed items are the reasoned ones each `TO-n` measures (TO-39, TO-40).
