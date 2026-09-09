# Work plan: issue-5787-fix-aggregate-execute-fallback — Aggregate with an untranslatable selector inside a projection must refuse, not client-evaluate

**Tier:** M  ·  **Status:** implemented, awaiting acceptance  ·  **Approved-at:** —  ·  **Branch:** issue/5787-fix-aggregate-execute-fallback
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

Issue: [#5787](https://github.com/linq2db/linq2db/issues/5787)

## P1 Problem

An aggregate whose selector cannot be translated refuses honestly when asked on its own, and fails with an
internal `InvalidOperationException` when the same aggregate sits inside a projection. Measured on SQLite
(`SQLite.Classic`, net10.0, playground probe, 2026-09-09):

```csharp
t.Min(r => r.StartedOn.ToBinary());
// LinqToDB.LinqToDBException: The LINQ expression 'x.StartedOn.ToBinary()' could not be converted to SQL.

t.Select(_ => new { M = t.Min(r => r.StartedOn.ToBinary()) }).First();
// System.InvalidOperationException: There is no method 'AggregateExecute' on type 'LinqToDB.LinqExtensions'
//   that matches the specified arguments
//   at System.Linq.EnumerableRewriter.FindMethod(...)
//   at LinqToDB.LinqExtensions.AggregateExecute[TSource,TResult](...)  LinqExtensions.cs:1806
//   at lambda_method19(Closure, IQueryRunner, DbDataReader)
```

Worse than the message: the second form **runs a query first** (`SELECT 1 FROM [Row] LIMIT 1`, with the
table separately eager-loaded as a preamble) and only fails during materialization.

Mechanism, traced with `Console.Error` instrumentation in `HandleSubquery` / `AggregateExecuteBuilder`
(probe output kept in this plan's `P4` rows, instrumentation reverted):

1. `t.Min(selector)` inside a projection fails to build as a sequence (`AggregationBuilder` declines when
   `buildInfo.IsSubQuery`), so `HandleSubquery` returns `false`.
2. The aggregation translation path then rewrites it to the marker call
   `LinqExtensions.AggregateExecute(t, source => source.AsQueryable().Min(selector))`
   (`ExpressionBuilder.Aggregation.BuildAggregateExecuteExpression`).
3. `AggregateExecuteBuilder` cannot translate the body and returns
   `BuildSequenceResult.Error(<SqlErrorExpression over the untranslatable selector>)`.
4. `GetSubQuery` **discards** `BuildSequenceResult.ErrorExpression` — it only forwards `AdditionalDetails`
   (`null` here) — so `HandleSubquery` sees `ctx == null`, `errorMessage == null`, `isSequence == true`
   and, having no context to ask `IsSingleElement` of, returns `false`.
5. The visitor then treats the marker call as ordinary client-side code: its source `t` becomes a
   `SqlEagerLoadExpression`, and `AggregateExecute` is left in the materialization lambda.
6. At runtime `AggregateExecute`'s source is an `EnumerableQuery`, whose `EnumerableRewriter` looks for
   `Enumerable.AggregateExecute` and throws.

Step 5 contradicts an invariant the codebase already asserts in two places:
`ExpressionTreeOptimizationContext` declares `AggregateExecute` **server-side-only**
(`IsServerSideOnlyCheckVisitor.VisitMethodCall`) and **not client-evaluable**
(`CanBeEvaluatedOnClientCheckVisitor.VisitMethodCall`).

## P2 Success criteria

- SC-1 `t.Select(_ => new { M = t.Min(r => <untranslatable>) }).First()` throws `LinqToDBException` naming
  the untranslatable selector — the same message the bare `t.Min(r => <untranslatable>)` produces — and
  throws while building the query, so no command reaches the server. → TO-1
- SC-2 The same holds for the other aggregate entry points that route through the marker: `Max`, `Sum`,
  `Average`, and the public `IQueryable.AggregateExecute` extension used directly in a projection. → TO-2
- SC-3 Aggregates in a projection whose selector *is* translatable keep working unchanged — same result,
  same SQL. → TO-3
- SC-4 `IntervalTranslationTests.AggregatesOverADifference` reports a `LinqToDBException` naming the
  expression on the providers currently gated by `[ActiveIssue(5787)]`, rather than the
  `AggregateExecute` `InvalidOperationException`. → TO-4

## P3 Constraints & anti-goals (M/L)

- No public API change. `GetSubQuery` and `HandleSubquery` are `LinqToDB.Internal.Linq.Builder` members;
  the new helper is `private static`. No `PublicAPI.Unshipped.txt` entry, no `CompatibilitySuppressions.xml`
  regeneration.
- **No generated-SQL change for any provider.** The fix only fires on a path that currently ends in a
  runtime `InvalidOperationException`, so no query that succeeds today may change shape. Baselines must be
  unchanged.
- **Anti-goal: do not make the failing form succeed.** Option (2) in the issue — teaching
  `AggregateExecute` to evaluate the aggregate client-side when the source is not a linq2db query — would
  silently fetch whole tables and would diverge from the bare form. The issue's stated expectation is the
  refusal; this branch implements the refusal only.
- **Anti-goal: do not generalise the client-evaluation fallback.** Making *every* failed sequence build in
  a projection surface its error would turn many currently-client-evaluated projections into errors. The
  change is scoped to the one marker method that provably cannot be client-evaluated.
- Query-cache behaviour untouched: the change is inside query building, before any cache write.

## P4 Unknowns (M/L)

- U-1 Which code path actually produces the surviving `AggregateExecute` call — `AggregationBuilder`
  (non-subquery) or `ExpressionBuilder.Aggregation` (subquery)? — resolved-by probe: `Console.Error`
  instrumentation in `HandleSubquery` and `AggregateExecuteBuilder` on the SQLite repro showed the
  subquery path (`ExpressionBuilder.Aggregation.BuildAggregateExecuteExpression`), with `HandleSubquery`
  failing at `purpose=Expression, isSequence=True, ctx=null, errorMessage=null` on
  `<table>.AggregateExecute(source => source.AsQueryable().Min(r => r.StartedOn.ToBinary()))`.
- U-2 Is the error expression `AggregateExecuteBuilder` produces good enough to reuse verbatim, or does it
  name the internal marker? — resolved-by probe: it is `SqlErrorExpression` over
  `Ref(AggregateRootContext::SampleClass).StartedOn.ToBinary()`; `SqlErrorExpression.PrepareExpression`
  renders the context ref as `x`, giving `'x.StartedOn.ToBinary()'` — byte-identical to the bare form's
  message.
- U-3 Can an `AggregateExecute` call legitimately be client-evaluated, i.e. is the current fallback ever
  correct? — resolved-by scout: no. `LinqExtensions.AggregateExecute` is
  `currentSource.Provider.Execute<TResult>(expr)`; on any non-linq2db provider that is
  `EnumerableQuery` → `EnumerableRewriter` → `InvalidOperationException`. The codebase already encodes
  this in `ExpressionTreeOptimizationContext`'s two `Methods.LinqToDB.AggregateExecute` special cases.
- U-4 Does the same defect reach `BuildPurpose.Sql` / `BuildPurpose.Root`, not only
  `BuildPurpose.Expression`? — resolved-by probe (**mutation control**, 2026-09-09, SQLite.Classic
  net10.0): with the guard removed from the `Sql or Root` leg only, `AggregateInOrderByRefuses` goes red
  (1 failed of 7) while the other six stay green — so the `Sql` half is load-bearing and covered.
  `BuildPurpose.Root` is **not** separately exercised: no query shape was found that reaches it with an
  `AggregateExecute` node. It is included because it shares the branch condition with the
  `ctx?.IsSingleElement` check directly above it — recorded in `P10`.
- U-5 Does `GroupBy`-scoped aggregation (`g.Min(r => <untranslatable>)`) route through the same marker? —
  resolved-by probe: **no**. `GroupedAggregateRefuses` is green both before and after the fix, so a
  grouped aggregate already refuses through `GroupByContext`. Kept as a characterization test, labelled
  as such in `P8`.
- U-6 Do the `StringConcat` / `StringJoin` / window-function fixtures that call `AggregateExecute`
  *directly* still pass? Those exercise the marker's successful path. — resolved-by the `P9` runs;
  **unresolved until G-04 reports**.
- U-7 Which errors can actually flow into the guard? — resolved-by critic + probe: **not only
  `AggregateExecuteBuilder`'s own two error returns**. `AggregateExecuteBuilder.cs:51-52` returns the
  *source sequence's* build result verbatim, and `ExpressionBuilder.cs:494-495` rewrites any
  non-sequence result into `Error(originalExpression)` — so ~18 builders that carry an
  `additionalDetails` string reach the guard. Measured: `t.Select(_ => new { M = t.DistinctBy(…).Min(…) })`
  loses `Additional details: 'DistinctBy requires at least one ordering key.'` under the first draft of
  E-3. Fixed and pinned by TO-6.
- U-8 Is `AggregateExecuteBuilder`'s `MarkerType.AggregationFallback` branch a live fallback the guard
  could pre-empt? — resolved-by scout: **no**. `grep MarkerExpression(` across `Source/` finds two
  construction sites (`MarkerExpression.cs:28` `PreferClientSide`, `EntityConstructorBase.cs:262`
  `ExplicitEagerLoad`); nothing constructs an `AggregationFallback` marker, so that branch is dead.
- U-9 Do `WindowFunctionHelpers.BuildAggregateExecuteExpression` / `LegacyMemberConverterBase` emit
  markers whose build failure is *meant* to fall back? — resolved-by scout: **no** for both. Both
  `WindowFunctionHelpers` overloads have zero in-tree callers. `LegacyMemberConverterBase` runs inside
  `ExposeExpressionVisitor`, i.e. before `ExpressionBuildVisitor`, so its output is indistinguishable
  from a user-written marker and carries no fallback contract.
- U-10 Can `GetAggregationContext` (`ExpressionBuildVisitor.cs:5497-5525`), which deliberately tolerates
  an `AggregateExecute` build failure, be broken by the guard? — resolved-by scout: **no**. It calls
  `TryBuildSequence` directly and returns `null`; it never goes through `HandleSubquery`.

## P5 Decisions (M/L; rejected alternatives mandatory at L)

### D-1 — Surface the translation error rather than teach the marker to run on the client

- **chosen:** When a sequence build for an `AggregateExecute` marker call fails, return the builder's
  `SqlErrorExpression` from `HandleSubquery` so the standard error path throws `LinqToDBException` at
  build time.
- **rejected:** Make `LinqExtensions.AggregateExecute` detect a non-linq2db source and evaluate the
  aggregate with `Enumerable.*` — it would make the query *succeed*, but only by eager-loading the whole
  table, and the bare form of the identical aggregate would still throw. Two forms of one query
  disagreeing about whether an expression is translatable is worse than both refusing.
- **rejected:** Change `AggregationBuilder` / `ExpressionBuilder.Aggregation` not to emit the marker when
  the body is untranslatable — the untranslatability is only discovered *by* `AggregateExecuteBuilder`,
  after the marker exists; deciding earlier means duplicating the translation attempt.
- **why this:** It restores the property the issue asks for (projection form == bare form), it costs one
  guard on an already-existing failure branch, and the error text is the one the aggregate builder
  already produced.
- **failure mode of the choice:** If some other builder legitimately relies on an `AggregateExecute`
  build failure falling back — e.g. a shape where the marker is emitted speculatively and a later
  fallback rewrites it — that query now throws instead of taking the fallback. The guard fires on
  `ctx is null || errorMessage is not null`, so it does **not** distinguish which `return` produced that
  state: `AggregateExecuteBuilder`'s `FallbackExpression` exit (`:73-74`) returns the chained build's
  result verbatim and therefore *does* reach the guard. What makes that safe is that it reaches it only
  once the chained `TryBuildSequence` has itself produced no context — a fully-failed chain, which should
  error. The `MarkerType.AggregationFallback` exit (`:77-83`) is dead code (U-8) and mitigates nothing.
  The one path that genuinely tolerates an `AggregateExecute` build failure is `GetAggregationContext`,
  which bypasses `HandleSubquery` entirely (U-10). Residual risk covered by the full-suite runs in `P9`.

### D-2 — Key the guard on the marker method, not on "server-side-only"

- **chosen:** `node is MethodCallExpression mc && mc.IsSameGenericMethod(Methods.LinqToDB.AggregateExecute)`.
- **rejected:** `Builder.IsServerSideOnly(node)` — reads as the more principled rule ("a server-side-only
  node cannot take the client fallback"), but `IsServerSideOnly` walks the whole subtree, so any failed
  subquery containing a `[ServerSideOnly]` member anywhere would start throwing at build time. That is a
  much larger behaviour change than this issue justifies, with no measured beneficiary.
- **why this:** The marker is the one construct whose client-side execution is impossible *by
  construction*, and `ExpressionTreeOptimizationContext` already names it explicitly twice for the same
  reason — so naming it a third time follows an established local precedent rather than inventing one.
- **failure mode of the choice:** Another marker method with the same "only our provider can execute it"
  property would need its own entry; the guard does not generalise. Accepted — the alternative
  generalisation is unbounded.

### D-3 — Thread `BuildSequenceResult.ErrorExpression` out of `GetSubQuery`, and rebuild the message the way the bare form does

- **chosen:** Add `out Expression? errorExpression` to `GetSubQuery` and assign
  `buildResult.ErrorExpression` on the normal exit. The guard then mirrors
  `ExpressionBuilder.BuildSequence:505-510` **exactly** — reuse an existing `SqlErrorExpression`
  verbatim (`WithType`), otherwise wrap `errorExpression ?? node` *together with* `errorMessage`, so a
  builder's `additionalDetails` reaches the user.
- **rejected:** `SqlErrorExpression.EnsureError(errorExpression, node.Type)` — reads as the idiomatic
  helper, but its non-error branch passes `null` for the message, which **silently drops**
  `additionalDetails`. Measured: the `DistinctBy`-without-`OrderBy` projection lost
  `Additional details: 'DistinctBy requires at least one ordering key.'` while the bare form kept it.
- **rejected:** Build a fresh `SqlErrorExpression` over the marker call itself — the message would then
  be `The LINQ expression '<table>.AggregateExecute(source => source.AsQueryable().Min(…))' could not be
  converted to SQL.`, which leaks an internal marker into a user-facing message and does not match the
  bare form.
- **why this:** `GetSubQuery` has exactly one caller, so widening its signature is contained, and
  copying the bare form's construction is what makes SC-1's message-equality contract hold by
  construction rather than by coincidence.
- **failure mode of the choice:** the `errorExpression ?? node` fallback is defensive only —
  `IsSequence` requires a non-null `ErrorExpression` or `AdditionalDetails`
  (`BuildSequenceResult.cs:39`) and the guard sits inside `if (isSequence)`, so in practice
  `errorExpression` is always non-null. If `ExpressionBuilder.BuildSequence`'s message construction ever
  changes, this copy drifts from it and SC-1 silently weakens; TO-1 and TO-6 both compare the two
  messages, so the drift fails a test rather than shipping.

## P6 Edit-points

- E-1 `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuildVisitor.cs:GetSubQuery` — add
  `out Expression? errorExpression`, initialise it to `null`, assign `buildResult.ErrorExpression` on the
  normal exit.
- E-2 `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuildVisitor.cs:HandleSubquery` — capture the new
  out-parameter; in the failed-sequence branch call the new guard on both the `BuildPurpose.Expression`
  and the `BuildPurpose.Sql or BuildPurpose.Root` legs, before each falls through to `return false`.
- E-3 `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuildVisitor.cs:IsUnbuildableAggregateExecute` —
  new `private static` helper: returns the aggregate builder's error (or a node-based one) when the failed
  node is an `AggregateExecute` marker call.
- E-4 `Tests/Linq/Linq/AggregationTests.cs` — five new tests covering SC-1..SC-3, appended before
  `ValueBesideASumKeepsItsOwnPrecision`. They reuse the fixture's existing `db.Types` /
  `Item.Data` models — **no new model type, no issue-numbered fixture**. (An earlier draft put them in
  `Tests/Linq/UserTests/Issue5787Tests.cs`; the maintainer asked for them in their proper home instead,
  so that file does not exist. See `P11 A-1`.)
- E-5 `Tests/Linq/Linq/IntervalTranslationTests.Queries.cs:AggregatesOverADifference` — replace
  `[ActiveIssue(5787, Configurations = [NoTickTotalProviders, UnsupportedDifferenceProviders])]` with
  `[ThrowsCannotBeConverted(NoTickTotalProviders + "," + UnsupportedDifferenceProviders)]`, matching the
  fixture's own idiom at `:329` / `:795` (restates SC-4: the gated providers now *assert* the refusal
  instead of being excluded).

## P7 Impact map (M/L)

- `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuildVisitor.cs:2780` — the **only** caller of
  `GetSubQuery` (searched `GetSubQuery(` across `Source/`: 2 hits — the declaration and this call) —
  covered by E-2.
- `BuildSequenceResult.ErrorExpression` producers — searched `BuildSequenceResult.Error(` across
  `Source/`: 49 sites, 18 of them carrying an `additionalDetails` string. **Any of them can reach the
  guard**, not only `AggregateExecuteBuilder`'s own error returns: `AggregateExecuteBuilder.cs:51-52`
  returns the *source sequence's* build result verbatim, and `ExpressionBuilder.cs:494-495` rewrites a
  non-sequence result into `Error(originalExpression)`. This is what forced E-3 to carry `errorMessage`
  — covered by E-3 and TO-6.
- `Methods.LinqToDB.AggregateExecute` consumers — searched `AggregateExecute` across `Source/`: in-tree
  marker producers are `AggregationBuilder.cs:38`, `ExpressionBuilder.Aggregation.cs:470`,
  `LegacyMemberConverterBase.cs:169` and `ExpressionBuildVisitor.cs:5518`
  (`WindowFunctionHelpers`' two overloads have zero in-tree callers). None emits a marker whose build
  failure is meant to fall back (U-9). The two guards in `ExpressionTreeOptimizationContext`
  (server-side-only / not-client-evaluable) are the invariant this change enforces — covered by E-3.
- `HandleSubquery` callers — `ExpressionBuildVisitor.cs:861` (`VisitMethodCall`), `:1684`
  (`HandleMember`), `:2932` (`VisitContextRefExpression`). All three reach the same failure branch, so
  the guard is installed once for all of them — covered by E-2.
- `GetAggregationContext` (`ExpressionBuildVisitor.cs:5497-5525`) — the one site that deliberately
  tolerates an `AggregateExecute` build failure; it calls `TryBuildSequence` directly and returns
  `null`, bypassing `HandleSubquery` — out-of-scope.
- Public `LinqExtensions.AggregateExecute` / `AggregateExecuteAsync` — unchanged; the async overload uses
  `GetLinqToDBSource()` and never reaches the client path — out-of-scope.
- Test fixtures calling `AggregateExecute` directly — searched `AggregateExecute` across `Tests/`:
  `StringConcatTests` (4), `StringJoinTests` (6+), `WindowFunctionsTests.PercentileCont` and siblings.
  These exercise the *successful* build, which the guard never sees — verified by the runs in `P9`.
- Lockstep mirrors: none. The guard is a single site in one visitor; there is no provider-specific,
  `Insert`/`Update`, or read/write-converter counterpart. Searched `Source/LinqToDB/Internal/Linq/Builder/`
  for a second `IsSingleElement == true` fallback-to-error shape: the two legs inside `HandleSubquery`
  are the only ones, and both are covered by E-2.
- Serialized/wire shapes: none — no enum, no `LinqService` contract, no SQL AST node touched.

## P8 Test obligations (M/L)

All in `AggregationTests`, measured on `SQLite.Classic`, net10.0, `linq2db.Tests.exe`; red arms produced
by `git apply -R` of the E-1..E-3 patch, never by a checkout. Final arm: `AggregationTests` +
`IntervalTranslationTests` = **178 / 0 failed**; red arm = **27 total, 4 failed**.

- TO-1 `UntranslatableAggregateInProjectionRefusesLikeTheBareForm` — the issue's shape asserts the
  projection message **equals** the bare aggregate's, and that `DataConnection.LastQuery` is still
  `null` (nothing ever reached the server). — proof: **red→green, measured**. Red arm:
  `InvalidOperationException: There is no method 'AggregateExecute' …` — the defect itself.
- TO-2 `UntranslatableAggregateInProjectionRefusesForEveryAggregate` — `Max`, `Sum`, `Average` and a
  direct `IQueryable.AggregateExecute` call in a projection all produce `LinqToDBException`. — proof:
  **red→green, measured**, same `AggregateExecute` `InvalidOperationException`.
- TO-3 `TranslatableAggregateInProjectionStillRuns` — symmetry guard on the **unchanged** path: a
  translatable aggregate in the same projection shape returns the right values. — proof: **control,
  measured green in both arms**.
- TO-4 `UntranslatableAggregateRefusesInPredicateOrderByAndGrouping` — covers E-2's `BuildPurpose.Sql`
  leg. — proof: **red→green, measured**. Red arm: *no exception at all* (`But was: null`) — the
  untranslatable aggregate is silently dropped from the `ORDER BY` and the query runs. Also the
  mutation control for U-4: removing the guard from that leg alone turns exactly this test red while
  the other six stay green.
- TO-5 folded into TO-4 — the predicate and grouping shapes already refused before the fix
  (characterization); they share the test method with the `OrderBy` shape, which does not. The
  characterization value is that the guard leaves them unchanged.
- TO-6 `UnbuildableAggregateSourceKeepsItsDetailMessage` — the aggregate's *source* refuses with an
  `additionalDetails` string (`DistinctBy` with no ordering key); asserts the projection message equals
  the bare one, details included. — proof: **red→green, measured twice**. Against the *first draft of
  E-3* (`EnsureError`, guard present) it failed on exactly the dropped
  `Additional details: 'DistinctBy requires at least one ordering key.'` — that is the arm that proves
  the message-carrying half. Against the *unfixed* code it fails with the `AggregateExecute`
  `InvalidOperationException` like the others. `#if NET8_0_OR_GREATER` — `Queryable.DistinctBy` is net8+
  in this repo (`Methods.cs:152-160`), so net462 has no coverage for this obligation.
- TO-7 `IntervalTranslationTests.AggregatesOverADifference` un-gated and re-declared with
  `ThrowsForProvider` for the providers that genuinely cannot translate the aggregate. — proof:
  red→green on Access (`NoTickTotalProviders`) and Informix (`UnsupportedDifferenceProviders`) locally;
  SQL Server 2014-minus has no local container and is covered by CI.
- TO-8 Regression sweep: full `Tests/Linq` on SQLite — proof: characterization (no new failures against
  the same run on `master`).

## P9 Verification gates

- G-01: **pass** — `dotnet build Source/LinqToDB/LinqToDB.csproj -c Release -f net10.0` → 0 warnings,
  0 errors. Covers the analyzers and CS1574 on E-3's `<see cref="LinqExtensions.AggregateExecute{…}"/>`
  / `<see cref="IQueryProvider.Execute{TResult}"/>`.
- G-02: **pass** — `dotnet build Source/LinqToDB/LinqToDB.csproj -c Release -f netstandard2.0` → 0/0.
- G-03: **pass, two parts.**
  (a) TFM coverage — `dotnet build Tests/Linq/Tests.csproj -c Debug` with **no `-f`** → all four TFMs
  (net462/net8.0/net9.0/net10.0), 0 warnings, 0 errors.
  (b) Analyzers — a plain `-c Release -f net10.0` dies on `Tests/Base/Attributes/UsesRemoteContextAttribute.cs`
  MA0206 (introduced by [#5614](https://github.com/linq2db/linq2db/pull/5614), untouched here) **before
  `Tests` compiles at all**, so that log would prove nothing. Ran the documented probe: patch that one
  attribute to `: Attribute;`, build `-c Release -f net10.0 -p:TreatWarningsAsErrors=false`, confirm the
  log actually contains `server processed compilation - Tests (net10.0)` and per-file diagnostics, then
  revert the patch (`git status` re-checked clean). Result: **14 errors, 3 warnings, none in a file this
  branch touches** — `ValueConversionTests` MA0154 ×2, `IntervalTranslationTests.**Arithmetic**.cs`
  MA0140 ×2, `OrmBattleTests` + `DataOptionsTests` MA0158/IDE0330, `Issue5683Tests` MA0206 ×2,
  `Issue5719Tests` MA0206 ×4, plus IDE2000/CA2025 warnings. `AggregationTests.cs` and
  `IntervalTranslationTests.Queries.cs` are clean.
- G-04: **pass** — `linq2db.Tests.exe --provider SQLite.Classic --test-progress` (whole suite, no
  filter): `total: 11295, failed: 0, succeeded: 10957, skipped: 338`, 12 m 35 s. Cross-checked against
  the skip list per `testing.md`: all 7 `Issue5787Tests` cases and `AggregatesOverADifference` are in
  the **passed** set, not the 338 skips. No `master` A/B run was needed — zero failures.
- G-05: **pass** — `AggregatesOverADifference` with the new `ThrowsCannotBeConverted` declaration:
  `Access.Ace.Odbc` 1/1, `Informix.DB2` 1/1. Pre-fix both reported
  `InvalidOperationException: There is no method 'AggregateExecute'`; post-fix both report
  `LinqToDBException … could not be converted to SQL.` **`TestProvName.AllSqlServer2014Minus` is not
  covered locally** — no such container exists on this machine (`sql2019`/`sql2022` only); CI covers it.
- G-06: **n/a** — the configured `BaselinesPath` (`c:\GitHub\linq2db.bls`) is not a git clone, so there
  is no local baseline diff to review. The change cannot alter SQL for a query that builds — it converts
  a runtime failure into a build-time one — and G-04 regenerated baselines with zero failures. CI's
  baselines PR is the real gate.
- G-07: **pass** — playground scratch (`TestTemplate.cs`, the `Tests.Playground.csproj` `<Compile
  Include>` link) reverted via `git checkout --`; the G-03(b) MA0206 probe reverted by `Edit`;
  `git status` shows exactly E-1/E-4/E-5's three paths (`ExpressionBuildVisitor.cs`,
  `AggregationTests.cs`, `IntervalTranslationTests.Queries.cs`, `+161/−4`), no untracked files;
  `git -C .claude status` shows only this plan. No new `.cs` file ships, so the BOM/CRLF question does
  not arise — both edited test files keep their existing encoding.

## P10 Adjudicated (M/L)

- The guard does not generalise to other "only linq2db can execute this" markers (D-2). Deliberate: the
  general form (`IsServerSideOnly`) changes behaviour for shapes with no measured beneficiary.
- The failing query is made to *fail earlier and better*, not to succeed (P3 anti-goal, D-1). A reviewer
  proposing client-side evaluation of the aggregate is re-raising a rejected alternative.
- **`BuildPurpose.Root` in E-2 is unexercised.** No query shape was found that reaches `Root` with an
  `AggregateExecute` node, so the guard's `Root` half has no test. It is kept because it shares the
  branch condition with the `ctx?.IsSingleElement` error return immediately above it — splitting the
  condition to `Sql` only would make the new guard inconsistent with the check it sits beside. The
  `Sql` half *is* exercised and load-bearing (TO-4's mutation control).
- **TO-6 has no net462 coverage.** `Queryable.DistinctBy` is `#if NET8_0_OR_GREATER` in this repo, so the
  detail-message obligation is only proven on net8.0+. The code path is TFM-independent.
- **The `[ActiveIssue(5787)]` gate on `AggregatesOverADifference` becomes
  `[ThrowsCannotBeConverted]`, not a removal.** Access and Informix still cannot translate the aggregate
  — they now say so honestly, which is the whole fix. Measured: both give
  `LinqToDBException : The LINQ expression 'x.FinishedOn - … x.StartedOn' could not be converted to
  SQL.` SQL Server 2014-minus (the third gated family) has no local container; its sibling sites in the
  same fixture already carry `ThrowsCannotBeConverted(TestProvName.AllSqlServer2014Minus)`, and CI
  settles it.

## P11 Amendments (M/L)

- **A-1 (2026-09-09, user instruction).** The tests were first written as
  `Tests/Linq/UserTests/Issue5787Tests.cs` with its own `BudgetedTask` model, on the strength of the
  standing rule *"no `Issue<NNNN>` prefixes in common fixtures — move the whole test to
  `UserTests/Issue<NNNN>Tests.cs`"*. The maintainer asked for the opposite here: the tests belong in
  their proper home. Moved into `Tests/Linq/Linq/AggregationTests.cs`, reusing that fixture's existing
  `db.Types` and `Item.Data` models so no new type and no issue-numbered name is introduced; the
  `UserTests` file is deleted. `E-4` rewritten; every `TO-n` re-measured against the new shapes
  (`db.Types.DateTimeValue.ToBinary()` instead of a local `DateTime` column), red arm re-run: 4 of 27
  fail without the fix, 0 of 178 with it. Reading of the rule going forward: `UserTests/Issue<N>Tests.cs`
  is the fallback when a test has no natural home, not the default.
- **A-2 (2026-09-09, user instruction).** Branch renamed `claude/ticket-5787-2bf59a` →
  `issue/5787-fix-aggregate-execute-fallback` (the harness-generated worktree name was not the repo
  convention). The plan directory was renamed to match, since `<key>` is derived from the branch.

## P12 Critic verdict (M/L)

**weak** — `plan-critic`, 2026-09-09. Run on **Opus 5 at the user's explicit instruction**, so the
corpus's different-model rule (`agent-rules.md` → *Non-trivial work starts with `/work-plan`*) is
waived-by-user for this branch.

Objections and what changed:

| # | Objection | Response |
|---|---|---|
| 1 | D-1's failure-mode mitigation misdescribes the mechanism — the guard fires on `ctx is null`, not on a specific `return`, so `AggregateExecuteBuilder`'s `FallbackExpression` exit *does* reach it | Accepted. D-1 rewritten against the real mechanism |
| 2 | Half that mitigation cites `MarkerType.AggregationFallback`, which has no producer anywhere in `Source/` | Accepted, verified independently (`grep MarkerExpression(` → 2 sites, neither). Recorded as U-8 |
| 3 | P7's "only `AggregateExecuteBuilder`'s two error returns reach the guard" is false — `AggregateExecuteBuilder.cs:51-52` and `ExpressionBuilder.cs:494-495` pass other builders' errors through | Accepted. P7 row rewritten; recorded as U-7 |
| 4 | **Code defect:** the guard used `EnsureError`, which drops `additionalDetails`, so SC-1's message-equality breaks for any failure carrying one | Accepted and **fixed**. Reproduced first (`DistinctBy` projection lost `Additional details: 'DistinctBy requires at least one ordering key.'`), then E-3 rewritten to mirror `ExpressionBuilder.BuildSequence`. Pinned by TO-6 |
| 5 | D-3's failure mode is wrong and its `errorExpression == null` branch is dead | Accepted. D-3 rewritten; the branch is kept as documented defensive code |
| 6 | The `BuildPurpose.Root` leg has no criterion, no obligation, and P3's justification is not the Root baseline | Partly accepted. Measured that the **`Sql`** half is load-bearing (mutation control → TO-4); `Root` is unexercised and now recorded in `P10` rather than silently claimed |
| 7 | U-4/U-5/U-6 "resolved-by probe" against circular or not-yet-existing evidence | Accepted. U-4 and U-5 re-resolved by actual measurement; U-6 explicitly marked unresolved until G-04 |
| 8 | Worktree state note — the prototype appeared reverted mid-review | Artifact of the critic reading during the red-arm `git apply -R`; the fix is applied |

Not contested: the critic independently confirmed the async overload is out of scope, that
`WindowFunctionHelpers`' two overloads have no in-tree callers, that `LegacyMemberConverterBase` runs at
expose time and carries no fallback contract, and that `GetAggregationContext` bypasses `HandleSubquery`.
