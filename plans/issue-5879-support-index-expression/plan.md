# Work plan: issue-5879-support-index-expression — IndexExpression in a query tree

**Tier:** M  ·  **Status:** approved  ·  **Approved-at:** 2026-10-24 (user; E-1…E-4, U-1…U-15; U-15 limit gets its own issue if the probe reproduces)  ·  **Branch:** issue/5879-support-index-expression
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

## P1 Problem

[#5879](https://github.com/linq2db/linq2db/issues/5879): a query tree carrying an `IndexExpression` (`ExpressionType.Index`, produced only by hand-built trees: `Expression.ArrayAccess`, `Expression.MakeIndex`, `Expression.Property(obj, indexer, args)`) fails with `NotSupportedException: Unhandled expression type: Index` from `PathVisitor.Path` (`Source/LinqToDB/Internal/Expressions/ExpressionVisitors/PathVisitor.cs:265`), reached from `ExpressionCacheManager..ctor` (`Internal/Linq/ExpressionCacheManager.cs:51`) on every query build. Repro (issue body, SQLite.Classic/net10.0): `db.GetTable<ParameterDeduplication>().Where(t => t.String2 == ArrayAccess(() => values, 0)).ToSqlQuery()` throws. The compiler's shapes for the same source (`BinaryExpression{ArrayIndex}`, `Array.Get` call, indexer `get_Item` call) translate. Downstream of that throw, more consumers lack an `Index` arm: `EqualsToVisitor` throws on a cache compare (`EqualsToVisitor.cs:101`), `ExpressionBuildVisitor` has no `VisitIndex`, `LoadWithBuilder` rejects it (`LoadWithBuilder.cs:305`), and `IsImmutableVisitor` skips the read-only-method gate its `get_Item` twin takes. All of this is reasoned, unprobed: the build visitor may still parameterize the raw node through its generic `CanTryHandleValue`/`HandleValue` path (`ExpressionBuildVisitor.cs:3074-3104`). Beyond the first throw, none of it has been run.

## P2 Success criteria

- SC-1 A `Where` predicate comparing a column to `Expression.ArrayAccess(<closure array>, Constant(0))` executes and returns the rows its compiler twin `ids[0]` returns → TO-1
- SC-2 The same shape rebuilt from a fresh closure with different array contents is a query-cache hit (miss count unchanged) and returns the new contents' rows → TO-2
- SC-3 `Expression.MakeIndex(<closure List<int>>, List<int>.Item, [Constant(0)])` behaves as `list[0]`: correct rows, and a rebuilt tree is a cache hit returning the new contents → TO-3
- SC-4 An index over a collection held directly in a `ConstantExpression` (`MakeIndex(Constant(list), Item, …)` and `ArrayAccess(Constant(arr), …)`), rebuilt with different contents, returns the new contents' rows (no stale literal reused from the cache) → TO-4
- SC-5 An `ArrayAccess` over a closure array in a `Select` projection returns the current element on each execution of a rebuilt tree → TO-5
- SC-6 The parameter built from a hand-built `ArrayAccess` is named after its source array (`["values"]`), as #5740 intended → TO-6
- SC-7 A multi-dimensional `Expression.ArrayAccess(<closure int[,]>, i, j)` returns the rows its compiler twin `grid[i, j]` returns → TO-7
- SC-8 `LoadWith` with a hand-built `MakeIndex(p.Children, List<Child>.Item, [Constant(0)])` path loads the same graph as `LoadWith(p => p.Children[0].Parent!.Children)` → TO-8
- SC-9 A `CompiledQuery` whose lambda carries a hand-built `ArrayAccess` over a closure array returns the current element on each call → TO-9
- SC-10 Compiler-built trees are untouched: existing `ParameterTests`, `ExpressionTests` and `LoadWithTests` stay green with no SQL-baseline change for them → TO-10

## P3 Constraints & anti-goals (M/L)

- No public API change (the edit is a private override in an internal visitor); no `PublicAPI.*.txt` edit.
- A tree with no `IndexExpression` must be processed exactly as today. `VisitIndex` fires only on an `Index` node, so compiler-built queries see no SQL, caching or performance change.
- No change to `PathVisitor`, `EqualsToVisitor`, `ExpressionBuildVisitor`, `LoadWithBuilder` or `IsImmutableVisitor` (D-3).
- The `EvaluationHelper` `ArrayIndex` slot-substitution suspicion (U-10) is not fixed on this branch.

## P4 Unknowns (M/L)

- U-1 Does every build entry pass the tree through `ExposeExpressionVisitor` before `ParametersContext` / `ExpressionBuilder` see it? — resolved-by scout + read: main query `Query{T}.cs:164` (`ExposeAndPrepareExpression`) → `expressions = currentQueries` `:171` → `new ParametersContext(expressions, …)` `:202`; compiled `CompiledTable{T}.cs:110-116`; associations `AssociationHelper.cs:68,237`; table filters `TableBuilder.cs:141,192`; single-convert `ExpressionBuilder.SqlBuilder.cs:239`.
- U-2 Can a cached key contain an `Index` node after E-1? — resolved-by read: only the exposed tree is cached (`Query{T}.cs:171,210`). E-1 removes every `Index` with a getter; the residue (getter-less indexer, D-2) still throws in `PathVisitor` at build time, before `TryAdd`, so it is never cached.
- U-3 Does the first cache lookup (`Query{T}.cs:151`, raw tree still holding `Index`) throw in `EqualsTo` against a cached normalized key? — resolved-by read: `EqualsToVisitor.cs:18-22` returns `false` on a `NodeType` mismatch before the throwing switch, and the cached key holds `ArrayIndex`/`Call` at that position. Run-proof: TO-2 second execution.
- U-4 Is a rebuilt normalized tree a cache hit? — resolved-by probe (TO-2/TO-3): the raw lookup misses (U-3); `isExposed` is true, so the second lookup `Query{T}.cs:182` compares normalized trees. `IncrementMissCount` (`:194`) runs only if both miss. Expected value from D-1 (parity): hit, the same as the compiler twin, which TO-2 measures as its control.
- U-5 Is `MakeIndex(Constant(list))` inlined as a literal, unlike its `get_Item` twin? Scout claim: `IsImmutableVisitor` has no `VisitIndex`, so the `IsReadOnlyMethod` gate (`ExpressionTreeOptimizationContext.cs:428-436`) is skipped. — resolved-by D-1: after E-1 the node is a `get_Item` call and takes that gate. TO-4 asserts the outcome; the probe stage in P8 measures whether the divergence was real.
- U-6 What does E-1 do to an `Index` used as a write target (`Assign`, compound assigns, `Pre/PostIncrementAssign`/`DecrementAssign`)? — resolved-by read + D-2: the base visitor rebuilds the parent with a non-writable `Call`/`ArrayIndex` and throws `ArgumentException` instead of today's `NotSupportedException`. Both are fail-loud and neither is translatable. P10. As a `ref` argument to a call, the rewrite drops the writeback, which no query can observe.
- U-12 Rank-1 non-zero-based array (`T[*]`) via `ArrayAccess` — resolved-by D-2 (no guard). Critic: BCL `Expression.ArrayIndex(Expression, Expression)` checks only `GetArrayRank() != 1`, so the node may become an ordinary `ArrayIndex` read. Reasoned, unprobed. It has no compiler twin and no provider can translate it; whatever the outcome, it is not a parity regression.
- U-13 Static indexed property (VB `Shared`, `Object == null`) — resolved-by D-2: `Expression.Call(null, getter, args)` is valid. No test, because C# cannot declare one.
- U-15 Subtrees expose returns unvisited — resolved-by read (`ExposeExpressionVisitor.cs:732-735`), effect reasoned, unprobed. Under `_optimizeConditions`, a conditional that is compilable as a whole but whose *visited* test is not (e.g. the test is a closure linq2db `IQueryable` the visit turns into `SqlQueryRootExpression`) is returned with `IfTrue`/`IfFalse` unvisited. An `Index` in those branches survives E-1 and reaches `PathVisitor.cs:265`; the compiler twin does not throw there. Also: the `ExposedQuery` interceptor loop `Query{T}.cs:81-98` stops after 10 rounds with the last result unexposed (interceptor-produced, same class as U-14). P10 + red-stage probe.
- U-14 Producers of an `Index` that bypass E-1 — resolved-by critic search + read: `TableBuilder.cs:141-144` exposes the lambda-only filter and **then** runs the `QueryFilter` interceptor without re-exposing (the dynamic path `:188-192` intercepts first). An interceptor introducing an `Index` there reaches `PathVisitor.cs:265`. The three `RegisterDynamicExpressionAccessor` funcs (`TableBuilder.cs:156`, `AssociationHelper.cs:57,234`) expose before returning, so `Query.cs:79` never sees one. P10.
- U-7 Indexer property with no getter — resolved-by D-2: left unchanged; it still throws in `PathVisitor`, as today.
- U-8 Does `Expression.ArrayIndex(array, IEnumerable<Expression>)` produce the compiler's multi-dim shape? — resolved-by D-2: the rank-1 / one-index case uses the `(array, index)` overload (Binary). Multi-index uses the overload that returns a `MethodCallExpression` to `Get`, which the issue says is the compiler's shape. TO-7 measures this against the compiler twin.
- U-9 Is every API E-1 uses available on `net462` / `netstandard2.0`? — resolved-by read: `PropertyInfo.GetGetMethod(bool)` and `Expression.ArrayIndex` / `Expression.Call` overloads exist in ns2.0. G-05 portable build proves it.
- U-10 `EvaluationHelper.cs:30` swaps **any** `ArrayIndex` for `Constant(parameterValues[i])` when `parameterValues != null`, without checking `Left == ParametersParam`. That is scout-reasoned and unconfirmed. After E-1, normalized nodes reach it exactly as compiler-built `arr[i]` does. — resolved-by user answer (2026-10-24): probe it with a throwaway test. If it reproduces, draft a separate issue for user confirmation; it is not fixed here. Parity with the compiler shape is preserved either way.
- U-11 Harness: hit/miss instrument — resolved-by read: `QueryUtils.GetCacheMissCount<T>` (`Tests/Base/QueryUtils.cs:127`, reads `Query<T>.CacheMissCount`), plus `[QueryCacheTest]` (`Tests/Base/Attributes/QueryCacheTestAttribute.cs:40`) for isolation. These are `IQueryable` builds. The compiled path (TO-9) asserts values only, because `GetCacheMissCount()` cannot see a `CompiledQuery` build (testing.md → *Testing query cache HIT / MISS*).

## P5 Decisions (M/L)

### D-1 — Normalize `IndexExpression` into the compiler's shapes in `ExposeExpressionVisitor.VisitIndex`

- **chosen:** one override in `Internal/Linq/Builder/Visitors/ExposeExpressionVisitor.cs` rewrites each `Index` into what the compiler emits for the same source, then re-dispatches with `Visit(normalized)`. Every downstream consumer (cache manager, cache compare, build visitor, immutability / client-evaluation checks, member converters, `[ExpressionMethod]`, `LoadWithBuilder`) then sees only shapes it already supports. User decision, 2026-10-24.
- **rejected:** per-consumer `Index` arms (`PathVisitor`, `EqualsToVisitor`, `ExpressionBuildVisitor.VisitIndex`, an `IsImmutableVisitor` twin). That is four or more sites, and parity gaps would remain in `LoadWithBuilder.cs:305` and the server-side-only checks (`ExpressionTreeOptimizationContext.cs:77-99`). Every future `ArrayIndex` / `get_Item` special case would also have to remember `Index`. Not counted as a gap: member converters / `[ExpressionMethod]` on an indexer getter (`ExposeExpressionVisitor.cs:99-114`). Searching `get_Item|get_Chars|IndexerName` across `Source/LinqToDB` finds no in-box converter targeting one, so there is no reachable red.
- **rejected:** normalizing in `BinaryExpressionAggregatorVisitor` at `Query{T}.cs:126`. It runs before `IExpressionPreprocessor` / `IQueryExpressionInterceptor` (`:130-137`), so nodes those introduce would survive. It does not see `[ExpressionMethod]` bodies expanded during expose (`ExposeExpressionVisitor.cs:107-113`). The compiled path `CompiledTable{T}.cs:110` does not call it.
- **why this:** expose is the single funnel every build entry passes through before `ParametersContext` (U-1), and its output is what gets cached (U-2).
- **failure mode of the choice:** a consumer that reads the **raw** tree before expose still sees `Index`. Known pre-expose readers are the first `TryFind` (safe, U-3), `QueryCache.ComputeChainHash` (hash only, default arm), `CompiledQuery.CollectDependentArgumentIndexes` (`ps`-only, `CompiledQuery.cs:122`) and user preprocessors/interceptors (their own code). Cost: every execution of such a query is exposed before its cache hit, the existing path for any tree expose changes (`Query{T}.cs:164-187`).

### D-2 — Rewrite rules

- **chosen:** `Indexer == null` with one argument → `Expression.ArrayIndex(obj, arg)` (Binary). `Indexer == null` with several → `Expression.ArrayIndex(obj, args)` (the `Get` call). `Indexer` with a getter → `Expression.Call(obj, getter, args)` (`GetGetMethod(true)`, `obj` null for a static indexed property). Getter-less indexer → node returned unchanged (`base.VisitIndex`).
- **rejected:** guarding `Assign` targets and non-zero-based rank-1 arrays (`int[*]`). Neither is translatable; both fail loudly either way (P10); a guard would be support for a shape no query can use.
- **why this:** the target shapes are exactly the compiler's, so parity is by construction, not by mirroring.
- **failure mode of the choice:** an `Index` used as an assignment target now fails in expose with `ArgumentException` instead of a later `NotSupportedException` (U-6).

### D-3 — No `Index` arms in `PathVisitor` / `EqualsToVisitor`

- **chosen:** leave both visitors unchanged.
- **rejected:** adding the arms the issue proposes, as a safety net. After E-1 neither is reachable with an `Index` node (U-2, U-3), so they would ship with no reachable red. The user's rule for this change is a red per gap.
- **why this:** the throws stay as loud guards for any future build path that skips expose.
- **failure mode of the choice:** such a path fails with `NotSupportedException`, loudly, not silently.

## P6 Edit-points

- E-1 `Source/LinqToDB/Internal/Linq/Builder/Visitors/ExposeExpressionVisitor.cs:VisitIndex` — new override implementing D-2, placed beside `VisitBinary`.
- E-2 `Tests/Linq/Linq/ExpressionTests.cs` — new `HandBuiltIndex*` tests for TO-1…TO-5, TO-7, TO-9 on the shared `Person` model, with a local helper that builds each tree from fresh values.
- E-3 `Tests/Linq/Linq/ParameterTests.Naming.cs:ParameterName_FromHandBuiltIndexExpression` — remove the `[ActiveIssue(5879, …)]` gate (TO-6).
- E-4 `Tests/Linq/Linq/LoadWithTests.cs` — new hand-built `MakeIndex` `LoadWith` test beside `LoadWith12` (TO-8).

## P7 Impact map (M/L)

- `Internal/Expressions/ExpressionVisitors/PathVisitor.cs:265` — throws on `Index`; after E-1 it is reached only by exposed trees (U-1), which hold no `Index` with a getter — covered by E-1
- `Internal/Expressions/ExpressionVisitors/EqualsToVisitor.cs:101` — throws on `Index`; callers `Query.cs:64,79` only (searched `\.EqualsTo\(` across Source: the remaining hits are `MemberInfo.EqualsTo`); unreachable per U-2/U-3 — covered by E-1
- `Internal/Linq/Builder/ExpressionBuildVisitor.cs:3529` `HandleBinary` ArrayIndex arm, and `VisitMethodCall` `HandleValue :950` for `get_Item` — receive the normalized node — covered by E-1
- `Internal/Linq/Builder/LoadWithBuilder.cs:271` (ArrayIndex) / `:203-240` (Call) vs default throw `:305` — receive the normalized node — covered by E-1 (TO-8)
- `Internal/Linq/Builder/ExpressionTreeOptimizationContext.cs:428-436` `IsImmutableVisitor` read-only-method gate; `:77-99` server-side-only check on `get_Item` — reached for a normalized getter call — covered by E-1 (TO-4)
- `Internal/Linq/Builder/Visitors/ExposeExpressionVisitor.cs:99-114` member converter + `[ExpressionMethod]` on the indexer getter — run when the rewritten call is re-dispatched — covered by E-1
- `Internal/Linq/Builder/EvaluationHelper.cs:30` — normalized `ArrayIndex` reaches the unguarded slot substitution, the same as a compiler-built one — deferred: separate suspicion, probe + issue per U-10
- `Internal/Linq/ExpressionCacheManager.cs:311,318` `SuggestParameterDisplayName` — after E-1 the `ArrayIndex` arm names the parameter, and the `IndexExpression` arm becomes unreachable from queries — out-of-scope (left in place: dead, harmless, and #5740's own code)
- `Internal/Linq/QueryCache.cs:525-553` `ComputeChainHash` — raw-tree hash, default arm for `Index`, hash only — out-of-scope
- `Internal/Linq/Builder/ExpressionTestGenerator.cs:196` — diagnostics only (`GenerateExpressionTest`); prints `Index` without brackets — out-of-scope
- Pre-expose readers: `CompiledQuery.cs:122` (`ps`-only), `ExpressionCacheManager.cs:106` (`ParametersParam`-only), `ExposeExpressionVisitor.cs:448,483,774` (`ps`-only) — out-of-scope (cannot match a user `Index`)
- Construction-only `Expression.ArrayIndex(` sites (`ExpressionBuilder.EagerLoad.cs:389,419`, `EagerLoadUnion.cs`, `EagerLoadKeyedQuery.cs:894`, `CompiledQuery.cs:247`, `FormattableStringHelper.cs:232,238`) — build internal trees; none construct `Index` — out-of-scope
- `ExpressionBuilder.EagerLoadKeyedQuery.cs:1156` — a *read* keyed on `ArrayIndex{Right: Constant int}` with no `ps` guard. A user node cannot match it: the read requires `Convert(…)` as the `Object` of a `PreambleResult.GetList` call, which only `:894` builds — out-of-scope
Searches (two scouts over the worktree at fd999f689): `ArrayIndex`, `ExpressionType\.Index\b|IndexExpression|VisitIndex`, `NodeType\s*\)|NodeType\s+switch` (~60 hits read), `throw new \w+Exception\(.*(NodeType|expression type)`, `override Expression\?? Visit\(`, `:\s*ExpressionVisitor\b`, `HandleValue\(`, `CanBeConstant|CanBeEvaluatedOnClient|IsServerSideOnly`, `\.Path\(|GetExpressionAccessors\(`, `ExposeExpression\(` (build entries for U-1). Result: no other `Index` throw on the query path; the only class deriving from BCL `ExpressionVisitor` is `ExpressionVisitorBase.cs:10`; `VisitIndex` is overridden only in `ExpressionPrinter.cs:1019`.

## P8 Test obligations (M/L)

Every hand-built tree is built inside a local helper from **fresh** values, which is the rules-engine pattern. Cache tests use the helper-with-parameter idiom (one closure display class across calls) plus `[QueryCacheTest]`. The provider narrowing for those tests is stated at the attribute: they are query-cache tests, and the key is provider-independent. Assertions go one call per line (testing.md → *Test layout*). Expected values come from the fixed `Person` / `Parent` data and D-1 (parity with the compiler twin), never from a first run.

- TO-1 `HandBuiltArrayAccess`: `Person.Where(p => p.ID == ArrayAccess(closure {2,3}, Constant(0)))` returns IDs `[2]`, the same as the compiler twin `ids[0]` — providers: [DataSources] — proof: red→green (master: `NotSupportedException: Unhandled expression type: Index`, `PathVisitor.cs:265`)
- TO-2 `HandBuiltArrayAccess_RebuiltTreeHitsCache`: helper(ids) called with `{2,3}` then `{3,4}` → `[2]` then `[3]`; miss count unchanged on the 2nd call; the compiler twin run the same way is the measured control — providers: [IncludeDataSources(TestProvName.AllSQLite)] — proof: red→green (master: same throw)
- TO-3 `HandBuiltIndexerProperty`: `MakeIndex(closure List<int>, Item, [Constant(0)])` with `{2}` then `{3}` → `[2]` then `[3]`; 2nd call is a hit — providers: [IncludeDataSources(TestProvName.AllSQLite)] — proof: red→green (master: same throw)
- TO-4 `HandBuiltIndexOverConstantCollection`: `MakeIndex(Constant(new List<int>{2}), Item, [Constant(0)])` then `{3}`; the same for `ArrayAccess(Constant(new[]{2}), Constant(0))` then `{3}` → `[2]` then `[3]` each; no hit/miss assertion (the key treatment of a constant collection is not what is under test) — providers: [IncludeDataSources(TestProvName.AllSQLite)] — proof: red→green (master: same throw)
- TO-5 `HandBuiltArrayAccessInProjection`: `Person.Where(p => p.ID == 1).Select(p => ArrayAccess(closure, Constant(0)))` built by the helper with `{"a"}` then `{"b"}` → `["a"]` then `["b"]`; the compiler twin `values[0]` run the same way is the measured control, so a red on call 2 can be told apart from pre-existing projection behaviour — providers: [DataSources] — proof: red→green (master: same throw)
- TO-6 `ParameterName_FromHandBuiltIndexExpression` (un-gated) → parameter names `["values"]` — providers: [IncludeDataSources(TestProvName.AllSQLite, TestProvName.AllSqlServer)] (existing) — proof: red→green (master: the gate's own expected throw)
- TO-7 `HandBuiltMultiDimArrayAccess`: `ArrayAccess(closure int[,] {{1,2},{3,4}}, Constant(1), Constant(0))` → IDs `[3]`, the same as the compiler twin `grid[1, 0]` — providers: [DataSources] — proof: red→green (master: same throw)
- TO-8 `LoadWithHandBuiltIndexer`: `Parent.LoadWith(<p => MakeIndex(p.Children, List<Child>.Item, [Constant(0)]).Parent!.Children>)`, `ParentID < 2` → `LoadWith12`'s check written in Shouldly (`Should.NotThrow(() => result.p.Children.Single().Parent!.Children.Single())`, one call per line) — providers: [DataSources(TestProvName.AllAccess)] (copied from `LoadWith12`'s measured exclusion, `LoadWithTests.cs:308`) — proof: red→green (master: same throw)
- TO-9 `HandBuiltArrayAccessCompiledQuery`: `CompiledQuery.Compile` over a hand-built lambda `(db) => db.Person.Where(p => p.ID == ArrayAccess(closure, 0))`; mutate the captured array between calls → `[2]` then `[3]`, the same as the compiler twin compiled the same way (measured control) — providers: [DataSources] — proof: red→green (master: same throw or its compiled-path equivalent, recorded when run)
- TO-10 existing `ParameterTests` + `ExpressionTests` + `LoadWithTests` green after E-1; no SQL-baseline diff for pre-existing tests — providers: SQLite.Classic, SQLite.MS locally; CI full — proof: characterization (proves no regression only, no new behaviour)
- Per-consumer red stage (probe, not committed; answers the "red per gap" requirement and U-5). Run with E-1 disabled, in this order, recording every test's outcome at each step. (1) Master state: all of TO-1…TO-9 throw in `PathVisitor`. (2) Add a temporary `PathVisitor` `Index` arm only, then run. Expected, not measured: TO-2/TO-3 throw `InvalidOperationException` from `EqualsTo` on call 2. (3) Add a temporary `EqualsToVisitor` arm too, then run. Record what each test now does. TO-1/TO-5/TO-7/TO-9 may fail in the build visitor, or may go green because the generic `HandleValue` path parameterizes the raw node. TO-4 may reuse a stale literal (U-5) or go green. TO-8 is expected to fail with `LoadWithBuilder` "is not an association". A test that is green at step 3 has no consumer gap behind it: it is relabelled `characterization` for that consumer, P1's corresponding claim is corrected, and the reason is recorded. Then revert both arms and re-enable E-1; `git diff --stat` must show only E-1…E-4.
- U-15 probe (throwaway `[Test]`, run after E-1): `Person.Where(p => p.ID == (closureQuery.Any() ? ArrayAccess(arr, 0) : 0))` with `closureQuery = db.Person`, run beside its compiler twin. If the hand-built form throws and the twin doesn't, the limit is real: P10 keeps it, and an issue is drafted for user confirmation.
- Side probe (U-10, throwaway `[Test]`, not committed): `CompiledQuery` with a captured `string[]` read at index 1 where `Builder.EvaluateExpression` runs (e.g. a `Sql.Alias` argument, `ExpressionBuildVisitor.cs:816`), compiler-built. Reproduces iff the evaluated value is the compiled-query argument rather than the array element.

## P9 Verification gates

- G-01: — (pending) `/test` worktree run of `ExpressionTests.HandBuilt` + `ParameterTests.ParameterName_` + `LoadWithTests.LoadWith` (SQLite.Classic, SQLite.MS; SqlServer if up), each red stage recorded per P8
- G-02: — (pending) baselines diff: only the new tests' SQL, none for pre-existing tests
- G-05: — (pending) `dotnet build Source/LinqToDB/LinqToDB.csproj -c Release -f netstandard2.0` and `-f net462`
- G-06: — (pending) `git diff` shows only E-1…E-4 lines
- G-07: — (pending) no `Tests/Tests.Playground/` change staged
- G-09: — (pending) adversarial read of the diff before the PR opens

## P10 Adjudicated (M/L)

- An `IndexExpression` used as an `Assign` target now fails in expose with `ArgumentException` instead of `NotSupportedException` (U-6, D-2). Neither is translatable, and no query API produces an assignment over an index.
- A non-zero-based rank-1 array (`T[*]`) indexed via `ArrayAccess` is rewritten like any rank-1 access (U-12). What happens after that is reasoned, unprobed. It has no compiler twin and no provider can translate it.
- A `QueryFilter` interceptor that introduces an `IndexExpression` on the lambda-only filter path (`TableBuilder.cs:141-144`: expose runs before the interceptor) still hits `PathVisitor`'s `NotSupportedException` (U-14). That requires user interceptor code to build the node itself. Changing the expose/interceptor order there is a separate concern with its own behavioural surface.
- An `IndexExpression` in a branch of a client-compilable conditional whose visited test stops being compilable (U-15, `ExposeExpressionVisitor.cs:732-735`) is not normalized and still throws in `PathVisitor`. That is reasoned, unprobed, and measured in the red-stage probe. Changing which branches expose visits there is out of scope: those lines preserve `?:` short-circuit semantics.
- `ExpressionCacheManager.SuggestParameterDisplayName`'s `IndexExpression` arm (`:318`) becomes unreachable from queries but is kept: removing #5740's arm is out of this change's scope, and it is harmless.
- `EvaluationHelper.cs:30` (U-10) is handled as a separate probe → issue, not on this branch. E-1 gives hand-built trees the same exposure compiler-built ones already have.

## P11 Amendments (M/L)

_None._

## P12 Critic verdict (M/L)

**weak** (plan-critic on `fable`, 2026-10-24). No objection kills E-1. Its strongest finding is in the plan's favour: D-1's funnel claim survived an independent search. Every raw-tree walker before expose is BCL-visitor based; the only throwing `NodeType` switches are `PathVisitor.cs:265`, `EqualsToVisitor.cs:101` and `LoadWithBuilder.cs:305`; all three dynamic-accessor registrations expose before comparing; and D-2's overload split is exactly the compiler's shapes.

Searched: `VisitIndex|ExpressionType\.Index\b|IndexExpression`, throwing defaults under `Internal/Expressions/ExpressionVisitors`, the visitor hierarchy, all 9 `ExposeExpression(` call sites, the `RegisterDynamicExpressionAccessor` registrations, `EqualsToVisitor.cs:15-22`, `GetExpressionAccessors(`, all 18 `ExpressionType.ArrayIndex` hits, `ArrayAccess|MakeIndex` in Tests, the KB, the BCL `ArrayIndex` overloads, and the `EvaluateExpression` fallback. Not checked: nothing was run; U-10 is left to the side probe; TO-5's and TO-9's re-read mechanisms are reasoned from `ApplyAccessors` only.

Objections and responses:
- TO-5 had no compiler-twin control → added.
- P10's `int[*]` line stated a false mechanism (BCL checks rank only) → replaced by U-12 (reasoned, unprobed) and a corrected P10 line.
- Red-stage order unspecified, and a possible green at the build visitor through generic `HandleValue` → the stage is now ordered (1)/(2)/(3), with the green outcome and its relabel rule. P1's build-visitor claim is relabelled reasoned.
- `TableBuilder.cs:141-144` post-expose `QueryFilter` interceptor bypasses E-1 → verified by read; U-14 + P10.
- P7 `EagerLoadKeyedQuery.cs:1156` was mis-filed as construction → own row (a read, unreachable shape).
- D-1 listed member converters on the indexer getter as a gap with no instance → the search is recorded, and it is marked "no reachable gap".
- Nit: TO-8 used `Assert.DoesNotThrow` → Shouldly `Should.NotThrow`.

Rows added in the same revision from the user's coverage question (not critic objections): U-6 widened to compound/increment assigns and `ref` arguments; U-13 static indexed property. The revision has not been re-critiqued: the critic is advisory at Tier M and the verdict is `weak`, not `refuted`.
