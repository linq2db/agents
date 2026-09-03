# Work plan: issue-5842-fix-compiled-query-loadwith — canonicalize the compiled-query root so a composed query can resolve its data context

**Tier:** M  ·  **Status:** draft  ·  **Approved-at:** —  ·  **Branch:** issue/5842-fix-compiled-query-loadwith
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

Scope note: PR #5844's original subject (#5842) is already fixed and pushed. This plan covers only the follow-on defect [#5854](https://github.com/linq2db/linq2db/issues/5854), which the maintainer asked to fix on this branch.

## P1 Problem

`CompiledQuery.CompileQuery`'s first `Transform` rewrites every lambda parameter to `Convert(ArrayIndex(ps, idx), type)` — index 0 included, which is always the `IDataContext`. So the expression stored on `CompiledTable<T>` carries `Convert(ps[0], TContext)` as its root, and every consumer that needs the context from that expression must resolve `ps[0]`, which requires `parameterValues`.

That holds while the expression stays inside `CompiledTable` (`GetInfo` threads `parameterValues` into `ExposeExpression` and the builder). It breaks the moment the expression is composed further at run time, because `IQueryProvider.CreateQuery` produces a fresh `ExpressionQuery` with `Parameters == null`.

Reproduced on `876c9c0f5b` with a user-defined pass-through over `LoadWith` (`Tests/Linq/Linq/CompileTests.cs:852`, currently red and uncommitted):

```
System.InvalidOperationException : variable 'ps' of type 'System.Object[]' referenced from scope '', but it is not defined
  at System.Linq.Expressions.Compiler.VariableBinder.VisitParameter
  at LinqToDB.Common.Compilation.CompileExpression            (Common/Compilation.cs:43)
  at ExpressionEvaluator.EvaluateExpression                   (Internal/Expressions/ExpressionEvaluator.cs:122)
  at EvaluationHelper.EvaluateExpression                      (Internal/Linq/Builder/EvaluationHelper.cs:54)
  at TableBuilder.GetRootMappingSchema                        (Internal/Linq/Builder/TableBuilder.cs:235)
  at TableBuilder.BuildSequence                               (Internal/Linq/Builder/TableBuilder.cs:269)
  … WhereBuilder → LoadWithBuilder → ExpressionBuilder.Build
  at Query`1.CreateQuery                                      (Internal/Linq/Query{T}.cs:223)
  at ExpressionQuery`1.GetQuery                               (Internal/Linq/ExpressionQuery.cs:91)
  at LoadWithQueryable`2.GetEnumerator                        (LinqExtensions/LinqExtensions.LoadWith.cs:116)
```

The root never becomes a `SqlQueryRootExpression` because the canonicalization in `ExposeExpressionVisitor.cs:402` gates on `mc.Arguments[0] is MemberExpression or ConstantExpression` — a `Convert(ArrayIndex(...))` is a `UnaryExpression`, so the branch is skipped regardless of `parameterValues`.

## P2 Success criteria

- SC-1 A compiled query whose outermost operator is a user-defined pass-through over a linq2db operator executes and returns correct rows, on two invocations with different argument values. → TO-1
- SC-2 No regression in the existing compiled-query and eager-loading corpus. → TO-2
- SC-3 The change alters no generated SQL for shapes that work today. → TO-3

## P3 Constraints & anti-goals (M/L)

- Public API outside `LinqToDB.Internal.*` must not change. `CompiledQuery`'s `Compile` / `Invoke` overloads and the `Func<...>` shapes they return are shipped surface.
- `parameterValues` indexing must not shift. Every `ArrayIndex(ps, i)` for i ≥ 1 keeps its index, and `CompiledTable`'s `(IDataContext)parameters[0]` keeps working.
- Not restructuring the compiled delegate to `Func<IDataContext, object?[], object?>` — it renumbers every argument index and drags in the public `Invoke<…>` surface for no correctness gain.
- Anti-goal: do not introduce `ExpressionConstants.DataContextParam` into the query tree. See D-1 — it is measurably the wrong node.
- The already-shipped parts of this branch are out of scope: the `StartLoadTransaction` fix, the `CancellationToken` threading, `Method.DeclaringType`, and the `table: this` cache key are committed and not to be revisited.

## P4 Unknowns (M/L)

- U-1 Does fixing only the **root** complete #5854, or do the *argument* references (`Convert(ArrayIndex(ps, i), T)` for i ≥ 1) also fail on the composed path? — resolved-by critic (source trace, round 1): **insufficient**. The build survives because the node becomes a SQL parameter rather than being evaluated, but execution NREs on `ps[1]` since `IQueryProvider.CreateQuery` (`ExpressionQuery.cs:233-251`) does not copy `Parameters` and `CompiledTable{T}.cs:80` is its only writer. See `P12` O-1. I had asserted this was probe-only; it was not.
- U-5 Does the composed path reach `Query.Compare`, whose compare functions bind `ParametersParam` but are invoked with `null`? — resolved-by critic (source trace, round 1): **yes**, on the second invocation via `QueryCache.Default.TryFind`, and only when a compiled query uses one argument more than once. See `P12` O-2.
- U-2 Can a user's compiled lambda declare a *second* `IDataContext`-typed parameter? — resolved-by scout: **yes**. `Compile`'s `TArg1…TArg5` are unconstrained (`CompiledQuery.cs:405-511`), so `Compile<ITestDataContext, IDataContext, IQueryable<Person>>((db, db2) => db2.GetTable<Person>())` compiles today. No such test exists in the corpus. Consequence: any context rewrite must key on **index 0**, never on the parameter's type.
- U-3 Does any test leave a data-context reference outside every folded node? — resolved-by scout: **no**, across all 115 `CompiledQuery.Compile` sites in `Tests/`. Four shapes are rescued only by an outer fold, closest being `TableFunctionTests.cs:52` (`new Model.Functions(db)`, held inside the fold solely by a degenerate `select p`).
- U-6 Does removing `ps` from the escaping expression entirely — index 0 to `SqlQueryRootExpression`, arguments to a per-invocation closure holder — close #5854 without the rest of the plan? — resolved-by probe: **partly, and it breaks something worse**. The wrapper repro went green 4/4 (including `.LinqService`, two invocations with different arguments), but the wider gate went **8 red**: `LoadWithThenLoadTest` and `MultipleLoadWithTest` on all four SQLite contexts, failing *silently* with `Mapper has switched to slow mode` and `Rows Count: 0`. Cause: accessor paths are recorded **positionally** (`PathVisitor`, backing `GetExpressionAccessors`), and an eager-loading preamble rebuilds its detail query during mapping by applying a path recorded against the `ArrayIndex` shape; wrapping the holder in `Convert` only moved the cast from `UnaryExpression` to `BinaryExpression`. Caveat worth carrying forward: this was a **retro-fit** onto a tree whose accessors had already been recorded by `GetInfo` against `ps` — a design producing an ordinary tree from the start would not hit that specific conflict.
- U-7 What is the compiled-query shortcut actually worth? — resolved-by measurement (`CacheActivityBenchmark`, manual runner, mock connection, 500 iterations each): compiled **0.76 µs / 1.35 KB** per execution against a derived-by-subtraction regular **≈4.1 µs / ≈2.95 KB**. Time noise on this harness is ~8%, so the allocation column is the trustworthy one, and against a real round trip 3.3 µs is invisible. Reading: the shortcut earns its keep in hot loops on a fast local database, and does not earn an ever-growing set of `ps` special cases across six visitors.
- U-8 Constraints any future fix must respect, surfaced by the maintainer: a compiled lambda can contain **several** queries (proved by instrumentation — two `CompiledTable<Parent>` from one lambda), so a cache must be keyed per fold site, not per `CompiledQuery`; and **DML folds too** (14 `*WithOutput` overloads plus plain `Update`/`Delete`/`Insert`), so a compiled lambda is not necessarily a query and can mix DML with queries in one body. Also `ConcurrentTest1/2/3` invoke one compiled query from 100 threads, so argument storage must stay per-invocation.
- U-4 Is the compiled query's expression ever serialized over the `LinqService` remote contract? — resolved-by scout: **no**. `Internal/Remote/` contains no expression-tree serializer; `LinqServiceSerializer` handles `SqlStatement`, `LinqServiceResult` and `string[]` only.

## P5 Decisions (M/L)

### D-1 — Canonicalize to `SqlQueryRootExpression`, not `ExpressionConstants.DataContextParam`

- **chosen:** replace `Convert(ArrayIndex(ps, 0), TContext)` with `SqlQueryRootExpression.Create(dataContext, TContext)`.
- **rejected:** `ExpressionConstants.DataContextParam`, which was this plan's first draft and the shape the maintainer's steer suggested. Refuted by scouts on three independent counts, all measured against source:
  - **Evaluability flips.** `ExpressionTreeOptimizationContext.cs:157-171` gives three different answers for the three root shapes — `ps` leaves `CanBeEvaluated` true; `dctx` sets false only under `InMethod`; `SqlQueryRootExpression` is evaluable only under `InMethod` **and** matching `ConfigurationID`. That answer fans out through `ExpressionBuilder.SqlBuilder.cs:369` to ~40 call sites.
  - **Immutability silently flips.** `IsImmutableVisitor` (`ExpressionTreeOptimizationContext.cs:483-492`) sets `IsImmutable = false` for `ps` and `container` and lets **any other parameter fall through leaving it true**, so a `dctx`-rooted subtree could be folded to a constant where a `ps`-rooted one was not. `ExpressionBuildVisitor.cs:2649`'s explicit `ParametersParam` check — which forces a parameter over a constant — also would not fire.
  - **Two compile paths hard-fail.** `ExpressionBuilder.EagerLoadKeyedQuery.cs:1089` and `ExpressionBuilder.EagerLoadUnion.cs:1386` build lambdas binding `ParametersParam` but not `DataContextParam`; a surviving `dctx` throws `variable 'dctx' … is not defined`. `BufferReconstructionVisitor` neutralizes `SqlQueryRootExpression` (`:1357`) but passes any other `ParameterExpression` through unchanged.
- **why this:** `SqlQueryRootExpression` is the established query-tree root — `Table<T>`'s own constructor builds one (`Internal/Linq/Table{T}.cs:21`), and every site above already handles it. `DataContextParam` is by contrast the *accessor-side* root: `CorrectAccessorExpression` (`ExpressionCacheManager.cs:334`, duplicated at `ParametersContext.cs:587`) converts `SqlQueryRootExpression` → `DataContextParam` when lifting a fragment out for separate compilation, i.e. the first draft was pushing against the codebase's own direction of travel.
- **failure mode of the choice:** `SqlQueryRootExpression` carries a `MappingSchema` and a `ContextType` and compares by `ConfigurationID` + `ContextType` (`SqlQueryRootExpression.cs:44-59`). Building one therefore requires a live context, so this cannot happen in the static `CompileQuery`; it must happen per invocation, which costs a tree rewrite on each `Create` call. If a compiled query is invoked against two contexts with different `ConfigurationID`s, each gets its own rewritten tree — correct, but not shared.

### D-2 — Rewrite in `CompiledTable<T>.Create`, not in `CompileQuery`

- **chosen:** rewrite the stored `_expression` inside `Create`, which already receives `parameters` and extracts `db`.
- **rejected:** rewriting in `CompileQuery`'s first `Transform`. It has no data context (it is `static` and runs once, before any invocation), so it cannot build a `SqlQueryRootExpression` at all — which is what forced the first draft toward `DataContextParam`.
- **rejected:** rewriting inside `GetInfo`'s cache factory. That would fix the expression the *builder* sees but not the one handed to the user: `Create` returns `new Table<T>(db, _expression)`, and it is `Table<T>.Expression` that a runtime composition (`LoadWithWrapper`, a trailing `.Where`) builds on. Fixing only `GetInfo` leaves #5854 exactly as it is.
- **why this:** `Create` is the only site that has both the context and the expression that escapes into user hands. `Execute` / `ExecuteAsync` need no rewrite — they return `T`, not a composable queryable.
- **failure mode of the choice:** the rewrite runs per invocation rather than once. If measurable, it can be memoized per `ConfigurationID` on the `CompiledTable` instance — deferred until it shows up, since `Create` already does a cache lookup and a `Table<T>` allocation.

### D-3 — Match by index 0, not by parameter type

- **chosen:** rewrite only the node produced for `query.Parameters[0]`.
- **rejected:** rewriting every parameter whose type is an `IDataContext`. This was the first draft's stated position ("type-based test, not positional — надійніше") and it is wrong: U-2 shows a second `IDataContext`-typed argument is legal, and a type-based rewrite would silently redirect it to the context from `ps[0]`.
- **why this:** `Invoke<…>` hard-wires the context to `args[0]` (`CompiledQuery.cs:297-390`) and `CompiledTable` reads `(IDataContext)parameters[0]`, so index 0 *is* the contract.
- **failure mode of the choice:** a subclass of `CompiledQuery` (the ctor is public shipped API) could hand in a `LambdaExpression` whose first parameter is not the context. `Invoke` would already be broken for such a type today; this change does not make it worse.

### D-4 — Answer the argument half at execution time, not at build time

- **chosen:** `ExpressionQuery`'s two `IQueryProvider.CreateQuery` overloads copy `Parameters` onto the query they construct, so a composed query keeps the compiled-argument array for `SetParameters` / `InitPreambles`.
- **rejected:** threading `parameterValues` through `Query<T>.GetQuery` into `ExpressionBuilder`, which is what `ac0a256482` did and what was reverted. The maintainer's objection was specifically that it puts `parameterValues` on the path **every** query takes, and routes compiled queries through the global query cache.
- **why this:** the two halves of the defect have different lifetimes and only one of them is a build-time need. The **root** must resolve while the query is being built — E-1/E-2 remove that need entirely by emitting a node `EvaluationHelper` resolves from `dataContext` alone. The **arguments** are never evaluated at build time: `IsImmutableVisitor` marks a `ps`-rooted subtree mutable, so it becomes a SQL parameter (`ExpressionBuilder.SqlBuilder.cs:352-360`) and its value is read at execution through `ExpressionQuery.Parameters` → `QueryRunnerBase.Parameters` → `SetParameters`. So the build path stays untouched and only the execution path gains the array it already expects.
- **failure mode of the choice:** `CreateQuery` is on the composition path of *every* query, not only compiled ones. For a non-compiled source `Parameters` is already `null`, so the copy is a no-op — but it is a hot path, and the edit must be a field copy, not a call.

### D-5 — Answer O-2 structurally, not by threading

- **chosen:** skip duplicate-check registration for getters rooted at `ParametersParam`.
- **rejected:** threading `Parameters` through `Query<T>.GetQuery → QueryCache.TryFind → Compare`. Both are public in `LinqToDB.Internal.Linq` and tracked in `PublicAPI.Shipped.txt`, so a signature change costs an API-baseline regeneration and widens the surface this branch touches.
- **why this:** two `ArrayIndex(ps, i)` nodes for the same `i` read the same array slot by construction, so they are duplicates without anything being evaluated. Deciding that structurally is strictly more determined than evaluating both against a runtime array — the evaluation could only ever confirm what the shape already guarantees.
- **failure mode of the choice:** it assumes no two distinct indices can alias. They cannot — `CompileQuery` assigns each index from `query.Parameters.IndexOf`, which is injective — but if a future change ever made two lambda parameters share an index, the skip would silently merge them where evaluation would have caught it.

## P6 Edit-points

- E-1 `Source/LinqToDB/CompiledQuery.cs:CompileQuery` — memoize the single `Expression` instance produced for `query.Parameters[0]` and hand it to `TableHelper.CallTable` alongside the folded expression, so `CompiledTable` can find it by **reference** rather than by re-deriving a shape. `_expression` itself keeps `Convert(ArrayIndex(ps, 0), TContext)` unchanged — per O-3, the folded path must not see the new node.
- E-2 `Source/LinqToDB/Internal/Linq/CompiledTable{T}.cs:Create` — build a per-invocation copy of `_expression` in which **every** occurrence of the E-1 node is replaced by `SqlQueryRootExpression.Create(db, <declared context type>)`, and hand that copy to `Table<T>`. `GetInfo`, `Execute` and `ExecuteAsync` continue to read the raw field.
- E-3 `Source/LinqToDB/Internal/Linq/ExpressionQuery.cs:IQueryProvider.CreateQuery` — both overloads copy `Parameters` onto the constructed query. Answers O-1.
- E-4 `Source/LinqToDB/Internal/Linq/ExpressionCacheManager.cs:RegisterParameterEntry` — do not register a duplicate check when both getters are rooted at `ParametersParam`. Answers O-2.
- E-5 `Tests/Linq/Linq/CompileTests.cs` — `WrappedLoadWithTest` + the namespace-level `CompiledQueryWrapperExtensions.LoadWithWrapper` (already written, uncommitted, currently red), plus the repeated-argument case from TO-4.

## P7 Impact map (M/L)

- `Source/LinqToDB/Internal/Linq/Builder/Visitors/ExposeExpressionVisitor.cs:520-546` — `VisitMember`'s explicit if/else over the root: `UnwrapConvert()` is `ArrayIndex` on `ps` → evaluate; else `is SqlQueryRootExpression` → evaluate. The comment at `:524` names the compiled-query case outright. After E-2 the second branch is taken instead of the first; both are supported. Searched: `Grep "ParametersParam"` over `Source/` (20 hits / 11 files). — covered by E-2
- `Source/LinqToDB/Internal/Linq/Builder/TableBuilder.cs:227-241` — `GetRootMappingSchema` short-circuits on `SqlQueryRootExpression` before reaching `EvaluateExpression`, which is where P1's stack throws. This is the site the fix targets. — covered by E-2
- `Source/LinqToDB/Internal/Linq/Builder/ExpressionTreeOptimizationContext.cs:157,227,471,483` — evaluability and immutability decisions differ per root shape. `SqlQueryRootExpression` has explicit arms at `:227` and `:471`; a bare `ParameterExpression` does not. Searched: `Grep "ParametersParam"`, `Grep "SqlQueryRootExpression"` over `Source/`. These sites are why D-1 picks the node it does. — covered by E-2
- `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuilder.EagerLoadKeyedQuery.cs:1089` and `.EagerLoadUnion.cs:1386` — lambdas binding `ParametersParam` but not `DataContextParam`; `BufferReconstructionVisitor:1357` neutralizes `SqlQueryRootExpression` to `Expression.Default`. Safe under E-2, unsafe under D-1's rejected alternative. — covered by E-2
- `Source/LinqToDB/Internal/Linq/QueryCache.cs:525-553` — `ComputeChainHash`'s `default:` arm hashes `NodeType` + `Type`, so all root shapes are handled and only the hash value moves. Not on the compiled-query path anyway: `CompiledTable{T}.cs:27-35` keys on the table instance. Searched: `Grep "CompareInfo"`, `grep -n "ComputeChainHash"`. — out-of-scope
- `Source/LinqToDB/Internal/Remote/**` — no expression-tree serializer exists; `LinqServiceSerializer` covers `SqlStatement` / `LinqServiceResult` / `string[]` only. Searched: `Grep "ExpressionType\.Parameter|ParameterExpression|SqlQueryRootExpression"` over `Source/LinqToDB/Internal/Remote` — no matches. — out-of-scope
- `Source/LinqToDB/Internal/Linq/ExpressionCacheManager.cs:334` and `Source/LinqToDB/Internal/Linq/Builder/ParametersContext.cs:587` — two byte-identical copies of `CorrectAccessorExpression`, both converting `SqlQueryRootExpression` → `DataContextParam` for accessor fragments. After E-2 the compiled-query tree finally carries the node they expect, so accessor lifting behaves as it does for every other query. Pre-existing duplication, not touched. — out-of-scope
- `Tests/Linq/Linq/TableFunctionTests.cs:52`, `TableFunctionOldTests.cs:52`, `EnumerableSourceTests.AsQueryable.cs:399`, `CompileTests.cs:326,335` — the four shapes where the context is not a chain root and survives only because an outer node folds. Unaffected by E-1/E-2 (which change the node's *form*, not whether it is folded), but they are the corpus's only near-miss cases and TO-2 must cover them. Searched: `Grep "CompiledQuery\.Compile"` over `Tests/` (115 hits / 19 files, all reviewed). No edit touches them; they are regression surface, run by TO-2. — out-of-scope
- `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuildVisitor.cs:2649,2995` — the `ParametersParam` presence check that forces a SQL parameter, and the `ArrayIndex(ps, …)` `VisitBinary` early-out. Both continue to fire for arguments i ≥ 1, which E-1/E-2 deliberately do not touch: that is what keeps the argument half an execution-time problem rather than a build-time one, answered at execution by D-4. — covered by E-3
- `Source/LinqToDB/Internal/Linq/ExpressionQuery.cs:233-251` — `IQueryProvider.CreateQuery`'s two overloads construct an `ExpressionQueryImpl` without copying `Parameters`. `CompiledTable{T}.cs:80` is the field's only writer in `Source/`, so every runtime composition of a compiled result loses the argument array. Searched: `Grep "Parameters =" / "new ExpressionQueryImpl" / "new Table<"` over `Source/` (critic, round 1). — covered by E-3
- `Source/LinqToDB/Internal/Linq/Query.cs:100-101` — `Query.Compare` invokes each compare function with `compiledParameters: null` while the lambdas bind `ParametersParam` (`ExpressionCacheManager.cs:524-529`). Reached only on the composed path's second invocation via `QueryCache.Default.TryFind`, and only when one compiled argument is used more than once. — covered by E-4, asserted by TO-4
- `Source/LinqToDB/Internal/Linq/Table{T}.cs:26-33` (`Table<T>(IDataContext, Table<T> basedOn)`, behind every `Change*` at `:238-299`), `Source/LinqToDB/LinqExtensions/LinqExtensions.LoadWith.cs:55-60` (`LoadWithAsTable`), and ~50 hint / `*SpecificExtensions` sites of the form `new Table<TSource>(table.DataContext, Expression.Call(…, table.Expression, …))` — all rebuild a query from an expression without carrying `Parameters`, the same defect shape as `CreateQuery`. Reachable only from a compiled query whose declared result is `ITable<T>`. — deferred: see P10; `ITable<T>`-typed compiled results are a narrower shape than `IQueryable<T>` / `IEnumerable<T>` and no test in the corpus exercises one through a hint or `Change*`

## P8 Test obligations (M/L)

- TO-1 `CompileTests.WrappedLoadWithTest` — a compiled query whose outermost operator is `CompiledQueryWrapperExtensions.LoadWithWrapper`, invoked twice with `id` 1 and 2, asserting the fixture's differing children counts (1 and 2). The second invocation is what proves argument variation survives the composed path, which is exactly U-1's question. — proof: **red→green**, already confirmed red on `876c9c0f5b` with the P1 stack.
- TO-2 `CompileTests` + `CompileTestsAsync` + `LoadWith*` + `EagerLoading*` on `SQLite.Classic` + `SQLite.MS` — 1265 today, 1267 with TO-1's two cases. Covers the four near-miss shapes named in P7. — proof: **characterization**; it proves no new behaviour, and its value is that E-2 changes a node every compiled query carries.
- TO-3 Baselines diff over the run in TO-2 — zero modified `.sql` files. E-2 changes an expression node, not a translation, so any moved SQL is a defect. — proof: **control**; `BaselinesPath` must be set or this obligation is unmet, not skipped.
- TO-4 A compiled query that uses **one argument more than once** (`p.ParentID == id || p.Value1 == id`), composed through the wrapper and invoked **twice** with different ids, asserting different results per invocation. The second invocation is what reaches `QueryCache.Default.TryFind` → `Query.Compare`, which is the only path to O-2. The two ids must be chosen so the expected results differ — assert `Is.Not.EqualTo` between the two expected values inside the test, so a fixture that cannot discriminate fails loudly instead of passing. — proof: **red→green** against E-4 specifically; must be shown red with E-1/E-2/E-3 applied and E-4 absent, or it is not testing what it claims.

## P9 Verification gates

- G-01: — (pending) tests green via the worktree runner
- G-02: — (pending) baselines reviewed (TO-3)
- G-03: n/a — D-5 was chosen partly to keep it so. No public signature changes: E-3 edits a method body, E-4 edits registration logic, E-1/E-2 are `internal` / private. Had the rejected threading in D-5 been taken, `Query.Compare` and `QueryCache.TryFind` are in `PublicAPI.Shipped.txt` and this would have become `/api-baselines` work.
- G-05: — (pending) Release build on `netstandard2.0` / `net462` / `net10.0`
- G-07: — (pending) no playground scratch staged

## P10 Adjudicated (M/L)

- The two `CorrectAccessorExpression` copies (`ExpressionCacheManager.cs:334`, `ParametersContext.cs:587`) are byte-identical duplicates. Pre-existing, unrelated to this change, deliberately not deduplicated here — a shared helper would be a cross-cutting edit for a local fix.
- `ExpressionCacheManager.cs:105`'s comment refers to a `ReplaceParameter` method that no longer exists. Stale comment, found by a scout, out of scope for this branch.
- Per-invocation cost of the E-2 rewrite is accepted un-memoized until measured. Reason: `Create` already performs a dictionary lookup and allocates a `Table<T>`, so the rewrite is unlikely to dominate; no measurement was taken.
- The `Table<T>(IDataContext, Table<T> basedOn)` / `LoadWithAsTable` / hint-site family (critic O-4) is **deferred, not fixed**. Reason: reachable only from a compiled query whose declared result type is `ITable<T>`, then further composed through a `Change*` or a provider hint. `IQueryable<T>` / `IEnumerable<T>` are the shapes users actually declare — every one of the 115 `CompiledQuery.Compile` sites in `Tests/` uses one of those or an element type, and none composes an `ITable<T>` result through a hint. Fixing it means auditing ~50 construction sites, which is a separable change with its own blast radius. Record on #5854 rather than widening this branch.
- SC-1 is scoped to the composed-**queryable** path. `query(db, id).Where(...)` — composition applied *outside* the compiled lambda, which the PR body's "Not fixed here" section documents — is the same mechanism and should also become green under E-3; if it does, the PR body needs correcting, and if it does not, that is a finding rather than a silent gap. TO-2 does not currently assert it.

## P11 Amendments (M/L)

_None._

## P12 Critic verdict (M/L)

**Round 1 — `refuted`** (Fable 5.1, read-only; no build or test run).

What it searched: `ParametersParam` / `ArrayIndex` / `DataContextParam` / `SqlQueryRootExpression.Create` / `VisitSqlQueryRootExpression` across `Source/`; `Parameters =` / `new ExpressionQueryImpl` / `new Table<` for writers of `ExpressionQuery.Parameters`; the `ClientValueAccessor → SetParameters → GetQueryRunner` flow; `Compile<…, IQueryable<…>>` composition shapes across `Tests/`.

Objections carried forward:

- **O-1 (fatal to `P6` as written).** `U-1` is settleable from source and the answer is *insufficient*. After E-1/E-2 the composed tree still carries `Convert(ArrayIndex(ps,1), int)`. The build succeeds — `IsImmutableVisitor` sets `IsImmutable = false` on `ps`, so `CanBeConstant` is false (`ExpressionBuilder.SqlBuilder.cs:352-360`) and the node becomes a SQL parameter rather than being evaluated. But at execution `ExpressionQuery.Parameters` is `null`, because `IQueryProvider.CreateQuery` (`ExpressionQuery.cs:233-251`) does not copy it and `CompiledTable{T}.cs:80` is its only writer in `Source/`. TO-1 therefore moves from `GetRootMappingSchema` to an NRE on `ps[1]` in `SetParameters` / `InitPreambles`. E-1/E-2 remain **necessary but not sufficient**.
- **O-2 (missing from `P7` entirely).** `Query.Compare` invokes every compare function with `compiledParameters: null` (`Query.cs:100-101`) while those lambdas bind `ParametersParam` (`ExpressionCacheManager.cs:524-529`). A compiled query using one argument twice registers a duplicate check (`ExpressionCacheManager.cs:184-204`) and NREs on the **second** invocation of the composed path via `QueryCache.Default.TryFind`. Dormant on the folded path, which is keyed on `table: this`. TO-1 uses its argument once and cannot detect it.
- **O-3.** E-1/E-2 are underdetermined in a way that moves blast radius: if the distinguishable shape is written into the stored `_expression`, the *folded* path carries it and D-1's hazards return through `Execute`. `_expression` must stay raw; `Create` builds a per-invocation copy. E-2 must also replace **every** index-0 occurrence, not just the outermost (`db.Parent.Where(p => db.Child.Any(…))`).
- **O-4.** `Table<T>(IDataContext, Table<T> basedOn)` (`Table{T}.cs:26-33`, behind every `Change*`), `LoadWithAsTable`, and ~50 hint / `*SpecificExtensions` sites rebuild a query from an expression without `Parameters`, exactly like `CreateQuery`. Reachable only from an `ITable<T>`-typed compiled result, so secondary — but a fix that patches `CreateQuery` alone leaves them.
- **O-5.** `Query.Compare` and `QueryCache.TryFind` are public in `LinqToDB.Internal.Linq` and tracked in `PublicAPI.Shipped.txt`; threading `Parameters` through them by signature change needs `/api-baselines`, so `G-03` would not stay `n/a`.

Objections it explicitly declined to raise, having checked them: `D-1` survives independent reading (count (b) slightly overstated — a `dctx` under a member is already non-evaluable at `:162-168` — but (a) and (c) carry it); `D-2` holds, since `LoadWith` composes from `currentSource.Expression` (`LinqExtensions.LoadWith.cs:194-203`); `P3`'s indexing invariant holds under either reading of E-1; `ExposeExpressionVisitor.cs:527-535` stays live for `GetInfo` / `Execute` / `ExecuteAsync`.

Named as the plan's strongest element: `D-1` — 17 sites in `Source/` already emit `SqlQueryRootExpression`, so the composed tree becomes the shape the corpus already exercises.

**Round 2 — `refuted`** (Fable 5.1, read-only). It attacked the revision, not the original, and broke `D-4`:

- **O-A.** `D-4`'s load-bearing claim — "arguments are never evaluated at build time" — is false. About ten builders evaluate argument subtrees during build (`TableAttributeBuilder`, `TakeSkipBuilder` hints, `QueryNameBuilder`, `AsSubQueryBuilder`, `AllJoinsBuilder`, `OrderByBuilder`, `CountByBuilder`, `ExpressionBuilder.Aggregation`, `RegisterExtensionAccessors`), and `[SqlQueryDependent]` arguments reach the builder as `ps[i]` because `IsCompilableVisitor` returns false for `ps`. Constructible today: `Compile<…>((db, tbl, id) => db.Parent.TableName(tbl).Where(p => p.ParentID == id).LoadWithWrapper(…))` fails from `TableAttributeBuilder` after E-1…E-4 — a third frame, same exception. The right partition is **by consumer** (SQL value vs builder-evaluated query-shape input), not by lifetime.
- **O-B.** `TO-4` as written cannot be red: `Parent.Value1` is `int?`, so the two parameter expressions differ structurally, never merge, and `ComparisionFunctions` stays null — green without E-4. Needs a merging pair on one non-nullable column.
- **O-C.** `E-4`'s predicate is under-specified; a bare `Find(ps) != null` would also skip mixed `ps[i] + closure` pairs.
- **O-D.** `P7` misses the mapper's `ParametersParam` binder and the cross-provider inlining shapes (`db.Parent.Concat(query(db,1))`), which E-3 does not reach.

**Outcome: the branch ships without this fix.** The critic's suggested lever — make the escaping expression carry no `ps` at all — was probed and the result is recorded in `P4` U-6. `WrappedLoadWithTest` is committed under `[ActiveIssue(5854)]` (`4a8addd03f`) and the write-up posted on #5854. No round 3: further critique **waived-by-user** ("без критика на fable").

**Revision direction chosen at the time (author, superseded by round 2): the narrow split.** O-1 and O-2 are accepted in full. The response is *not* the rejected `ac0a256482` threading, because the two halves live at different lifetimes: the **root** is a build-time need, answered by E-1/E-2 with no `parameterValues` at all; the **arguments** are an execution-time need, answered by copying `Parameters` in `CreateQuery`; and O-2 is answered structurally — two `ArrayIndex(ps, i)` reads of the same slot are duplicates by construction, so the duplicate check can skip evaluation instead of gaining a threaded parameter. That leaves `Query<T>.GetQuery` / `ExpressionBuilder` untouched, which was the maintainer's actual objection to `ac0a256482`. This reasoning is the author's, built on the critic's source trace and **not itself probed** — it goes back to the critic in round 2 before any code.
