# Work plan: issue-6000-fix-nested-fromsql-cache — Nested FromSql/FromSqlScalar reuses stale SQL from query cache

**Tier:** M  ·  **Status:** amended — approval void (A-3, A-4), re-earn  ·  **Approved-at:** 2026-10-08 (user; round-2 fixes un-re-critiqued, P10 baseline move accepted) — superseded by A-3  ·  **Branch:** issue/6000-fix-nested-fromsql-cache
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

## P1 Problem

[#6000](https://github.com/linq2db/linq2db/issues/6000): with `sql` a captured local that changes per loop iteration (`1, 2, 1`),

```cs
var query = table.Where(i => i.Id.In(db.FromSqlScalar<int>(FormattableStringFactory.Create(sql))));
query.ToSqlQuery().Sql; // iteration 2 still contains "SELECT 1 AS value"
```

the second execution emits and runs the first iteration's SQL. Calling `FromSqlScalar` outside the lambda works.

Mechanism (scout-traced, reading only):
- The nested call survives expose intact — `ExposeExpressionVisitor.cs:495-512` only swaps the captured `db` for a `SqlQueryRootExpression`; the `Create(closure.sql, …)` argument stays a closure member read and reaches `TableBuilder.BuildRawSqlTable` (`TableBuilder.cs:293-294`).
- `TableBuilder.PrepareRawSqlArguments` (`TableBuilder.RawSqlContext.cs:72`) evaluates the format at build time — `mc.Arguments[0].EvaluateExpression<string>()` (`:81`, `:91`), `formatArg.EvaluateExpression()` (`:97`) — and nothing registers that value with the query cache. `FromSql`/`FromSqlScalar`'s `sql` parameter has no `[SqlQueryDependent]` (`DataExtensions.cs:1483-1485, 1533-1535, 1582-1585`), unlike every sibling API that turns a client value into SQL text.
- Failure mode 2: a *captured* `FormattableString` (`var fs = $"…{v}"; … db.FromSql<T>(fs)` inside a lambda) bakes the format **and** wraps each argument as a fresh `Expression.Constant` (`RawSqlContext.cs:~105`). Those become `SqlValue`s whose cache check compares the build-time value against the same unmapped constant (`ExpressionCacheManager.cs:643-645`) — always equal, so changed arguments are stale too.
- Failure mode 3: a captured `RawSqlString` bakes its format the same way (`RawSqlContext.cs:~126`).
- Top level is safe because `ExpressionQueryImpl` puts the format into the tree as a constant (`DataExtensions.cs:1496, 1546, 1596`), which stays in the cache key.

## P2 Success criteria

- SC-1 Nested `FromSqlScalar(FormattableStringFactory.Create(capturedSql))` over iterations `1,2,1` returns rows for the current SQL each time, and iteration 3 is a cache hit.  → TO-1
- SC-2 Nested `FromSql` with a captured `FormattableString` whose format and interpolated argument change returns the current rows each time.  → TO-2
- SC-6 Nested `FromSql` with a captured `FormattableString` whose format is fixed and only the interpolated argument changes returns the current rows and reuses the cached query.  → TO-6
- SC-7 Same as SC-6 with the argument switching between a value and `null` returns the current rows (no replayed `NULL` or replayed value).  → TO-7a, TO-7b
- SC-3 Nested `FromSql` with a captured `RawSqlString` whose format changes returns the current rows each time.  → TO-3
- SC-4 Nested `FromSql` with an inline interpolated string (constant format, captured argument) still reuses the cached query when only the argument changes.  → TO-4
- SC-5 Existing `FromSqlTests`, `SqlExtensionsTests` and query-cache tests stay green; the only existing baselines that move are the `Issue3782Test2`/`Issue3782Test4` `inline=False` sets, literal → parameter.  → TO-5

## P3 Constraints & anti-goals

- No public API change; no `[SqlQueryDependent]` on public `FromSql` parameters (see D-1).
- Top-level `FromSql`/`FromSqlScalar` path (format is a `ConstantExpression`) unchanged — same SQL, same caching.
- Inline interpolated nested form keeps parameterizing its arguments and keeps cache hits.
- `Sql.Expr` behaviour unchanged: D-2's argument rewrite is scoped to the `BuildRawSqlTable` caller (D-3), and `Sql.Expr`'s captured-`FormattableString` path is already correct-but-uncached (`RegisterExtensionAccessors` marks the `FormattableString` object, compared by reference).
- No AST / `IDataProvider` / translator interface change.
- Deliberate SQL change (P10): nested captured-`FormattableString` arguments emit a parameter instead of a literal — matching the top-level path (`DataExtensions.cs:1452` `WrapAsParameter`). Moves 24 `inline=False` baselines of `Issue3782Test2` (PostgreSQL) / `Issue3782Test4` (SqlServer); `inline=True` sets unchanged.

## P4 Unknowns

- U-1 Is the nested call evaluated/spliced before `TableBuilder` sees it (which would move the bug elsewhere)? No — `ExposeExpressionVisitor.cs:495-512` keeps the call, only replaces `Arguments[0]` — resolved-by scout
- U-2 Does `MarkAsValue` compare strings by content? Yes — `ExpressionEqualityComparer.CompareValues` (`ExpressionEqualityComparer.cs:40-58`), `string` → `Equals`; `FormattableString` would compare by reference, so mark `.Format`, never the object — resolved-by scout
- U-3 Does a wrapper expression absent from the main tree (`Property(Convert(formatArg), "Format")`) resolve through `ApplyAccessors`? Yes, if the inner closure `ConstantExpression` is the MainExpression instance — `AccessorsMapping` is reference-keyed (`InternalExtensions.cs:188-225`), `ApplyAccessors` recurses (`ExpressionCacheManager.cs:99-125`); same assumption existing `MarkAsValue` callers make — resolved-by scout; confirmed at runtime by TO-1..TO-3
- U-4 Do `Convert(ArrayIndex(Call(formatArg, GetArguments), i), T)` args parameterize per execution? Yes — `HandleValue` builds a constant only when `IsImmutable`; `GetArguments` is not read-only (`ExpressionTreeOptimizationContext.cs:428-436`) and a closure field is mutable (`:454-466`) → `BuildParameter`; the `Convert` is required or `HasDbMapping(object)` rejects it (`ParametersContext.cs:324-328`) — resolved-by scout; confirmed by TO-2
- U-5 Does the compiler emit `NewArrayInit` for `Create(sql)`'s params inside an expression lambda? Irrelevant to the fix — both Call branches evaluate `Arguments[0]` identically and both get the registration — resolved-by scout
- U-6 First execution = 2 misses (memory)? Refuted by reading (`IncrementMissCount` single call site, `Query{T}.cs:194`); tests assert miss-count deltas between iterations, never an absolute first-iteration count — resolved-by scout

## P5 Decisions

### D-1 — Register the evaluated format via `MarkAsValue`, not `[SqlQueryDependent]`

- **chosen:** in `BuildRawSqlTable`, `builder.ParametersContext.MarkAsValue(formatExpression, format)` where `formatExpression` yields the format string; skipped when the source, after unwrapping `Convert` (the compiler's `op_Implicit` for `string` → `RawSqlString`, `RawSqlString.cs:16`), is a `ConstantExpression` — already in the structural key.
- **rejected:** `[SqlQueryDependent]` on `FromSql`'s `sql` parameter — `PrepareForCache` would fold the whole `FormattableStringFactory.Create(...)` call into a constant `FormattableString`, which compares by reference → every nested inline-interpolated query becomes a permanent cache miss, and its arguments turn into baked values instead of parameters. Also a public-API attribute change.
- **why this:** same mechanism `RegisterExtensionAccessors` uses for extension arguments (`ExpressionBuilder.QueryBuilder.cs:406-424`); compares only the format text, keeps argument parameterization.
- **failure mode of the choice:** if a future rewrite replaces the closure constant before `BuildRawSqlTable`, the accessor compares the build-time value with itself and the bug silently returns — TO-1..TO-3 are the guard.

### D-2 — Captured-FormattableString arguments become accessor-backed expressions

- **chosen:** when `formatArg` is not a `ConstantExpression`, build each argument as `Convert(ArrayIndex(Call(formatArg, GetArguments), i), T)` where `T` is the runtime type, lifted to `Nullable<T>` for value types — a cached accessor must survive a later `null` (the `CorrectAccessorExpression` null guard only covers `Nullable<>` operands, `NullableTypeExtensions.cs:47-49`, so an `object`→`int` unbox of `null` would throw) — mirroring the existing RawSqlString-array branch (`RawSqlContext.cs:~138-140`); keep `Expression.Constant` when `formatArg` is constant (top-level path).
- **rejected:** `MarkAsValue` on `GetArguments()` (element-wise compare), keeping literals — preserves the `Issue3782` baselines, but bakes values into SQL, recompiles per distinct argument, and leaves nested and top-level forms emitting different SQL for the same `FormattableString`.
- **why this:** arguments then parameterize like every other closure value and like the top-level path; the existing RawSqlString branch proves the shape.
- **failure mode of the choice:** (a) `ISqlExpression` values — keep `Expression.Constant`, as the RawSqlString branch does (same pre-existing staleness, deferred in P7); (b) a `null` argument has no runtime type, so no `Convert` and `HasDbMapping(object)` rejects it (`ParametersContext.cs:466-467`) — keep `Expression.Constant(null)` and additionally `MarkAsValue(<ArrayIndex expr>, null)` so a later non-null value forces a rebuild instead of replaying `NULL`.

### D-3 — Format-source returned from `PrepareRawSqlArguments`; argument rewrite opt-in

- **chosen:** add `out Expression? formatExpression` and a `bool parameterizeCapturedArguments` input to `PrepareRawSqlArguments`; `BuildRawSqlTable` passes `true`, `Sql.Expr`'s `ExprBuilder` passes `false` and discards the out.
- **rejected:** recomputing the source in `BuildRawSqlTable` — duplicates the branch logic, drifts. Applying D-2 to `Sql.Expr` too — changes `Sql.Expr` SQL with no test and no reported bug, in a patch release.
- **why this:** the branch that evaluates the format is the only place that knows where it came from; the flag keeps `Sql.Expr` byte-identical. `TableBuilder` is internal.
- **failure mode of the choice:** the two callers diverge on captured-`FormattableString` argument handling; recorded in P10 so a later unification is a decision, not a surprise.

## P6 Edit-points

- E-1 `Source/LinqToDB/Internal/Linq/Builder/TableBuilder.RawSqlContext.cs:PrepareRawSqlArguments` — new `out Expression? formatExpression`, `bool parameterizeCapturedArguments`, and an out list of `ArrayIndex` expressions whose build-time value was `null`; when set and `formatArg` is non-constant, captured-FormattableString args built as `Convert(ArrayIndex(Call(formatArg, GetArguments), i), T or T?)`, with the `ISqlExpression` / `null` cases of D-2 (D-2, D-3).
- E-2 `Source/LinqToDB/Internal/Linq/Builder/TableBuilder.RawSqlContext.cs:BuildRawSqlTable` — `MarkAsValue(formatExpression, format)` when non-null; `MarkAsValue` for null captured args (D-1, D-2).
- E-3 `Source/LinqToDB/Sql/Sql.Expressions.cs:ExprBuilder.Build` — pass `false`, discard the out-param.
- E-4 `Tests/Linq/Linq/FromSqlTests.cs` — new `Issue6000_*` tests (P8).
- E-5 `linq2db.baselines` — regenerated by CI: `Issue3782Test2`/`Issue3782Test4` `inline=False` sets (literal → parameter) and new `Issue6000_*` files; no hand edits.
- E-1, E-2, E-3 — **superseded by A-3**: `TableBuilder.RawSqlContext.cs` and `ExprBuilder.Build` are no longer edited.
- E-6 `Source/LinqToDB/Internal/Linq/Builder/Visitors/ExposeExpressionVisitor.cs:VisitMethodCall` / `HandleSqlDependentParameters` — new `ConvertRawSqlString` (rewrite `FromSql(RawSqlString, params)` / `Sql.Expr(RawSqlString, params)` into the `FormattableString` overload over `FormattableStringFactory.Create(sql.Format, parameters)`) and `PrepareFormattableString` (evaluate only the format; expand an evaluable captured `FormattableString` into `Create(format, GenerateArray(args))`; resolve only the format from compiled-query arguments) (A-3, A-4).
- E-7 `Source/LinqToDB/Mapping/SqlQueryDependentAttribute.cs` — `ExpressionsEqual` splits `FormattableStringFactory.Create(format, NewArrayInit)` into format-by-value + arguments-structural; `ObjectsEqual` compares two `FormattableString`s by format and arguments (A-3).
- E-8 `Source/LinqToDB/DataExtensions.cs` — `[SqlQueryDependent]` on the `FormattableString` parameter of `FromSql` / `FromSqlScalar`; internal `GenerateFormattableString` helpers replace the two inline `Create` builders (A-3).
- E-9 `Source/LinqToDB/Sql/Sql.Expressions.cs` — `[SqlQueryDependent]` on `Sql.Expr<T>(FormattableString)` (A-3).
- E-10 `Source/LinqToDB/Internal/Reflection/Methods.cs` — internal `FormattableStringFactory_Create`, `FromSqlFormattable`, `FromSqlRaw`, `SqlExt.ExprFormattable`, `SqlExt.ExprRaw` (A-3).
- E-11 `Source/LinqToDB/Internal/Linq/DependentArgumentValues.cs` — compiled-table cache key compares / hashes a `FormattableString` by format and arguments (A-4).
- E-12 `Tests/Linq/Linq/SqlExtensionsTests.cs` — `Expr_*` tests (A-3).

## P7 Impact map

- `Source/LinqToDB/Internal/Linq/Builder/TableBuilder.cs:293-294` — sole callers of `BuildRawSqlTable` (searched `BuildRawSqlTable` across `Source/`) — covered by E-2
- `Source/LinqToDB/Sql/Sql.Expressions.cs:537` — second caller of `PrepareRawSqlArguments` (searched `PrepareRawSqlArguments` across `Source/`) — covered by E-3
- `Source/LinqToDB/Sql/Sql.Expressions.cs:563` `Sql.Expr<T>(FormattableString)` with column-referencing interpolation args — `RegisterExtensionAccessors` skips non-client-evaluable `Create(...)` (`ExpressionBuilder.QueryBuilder.cs:413`), so a captured format may be stale; same bug class, different builder, unprobed — deferred: separate extension-builder path; probe and file a follow-up issue rather than widen this PR
- `TableBuilder.RawSqlContext.cs:~131-135` captured `object[]` holding `ISqlExpression` items for RawSqlString — baked as `Expression.Constant`, compared against itself — deferred: needs ISqlExpression comparison semantics; follow-up issue alongside the Sql.Expr one
- `Tests/Linq/Linq/FromSqlTests.cs:1100-1121` `Issue3782Test2`, `:1137-1149` `Issue3782Test4` — nested captured `FormattableString` with one argument; baselines show literal `'Person'` / `N'Person'` in all 48 files (critic, `git grep` on `linq2db.baselines` HEAD); under D-2 the 24 `inline=False` files move to a parameter (searched `(FromSql|FromSqlScalar|Sql\.Expr)<…>\(\s*ident` across `Tests/`) — covered by E-5
- `Tests/Linq/Linq/FromSqlTests.cs:1036, 1067` `TestBasicScalarQuery*` — nested captured zero-arg `FormattableString`; gains only the format `MarkAsValue`, SQL unchanged — covered by E-2
- `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuildVisitor.cs:2655` `HandleStringFormat` — `string.Format(closureFormat, col)` evaluates the format at build time without registration; same stale-cache class (searched `EvaluateExpression<string>()` in `Internal/Linq/Builder`) — deferred: different API, file follow-up issue with the `Sql.Expr` row
- `Source/LinqToDB/Internal/Linq/Builder/TableBuilder.CteTableContext.cs:39` `AsCte(closureName)` — name evaluated, `LinqExtensions.cs:1151-1153` has no `[SqlQueryDependent]`; same class — deferred: same follow-up issue
- `TableBuilder.RawSqlContext.cs:79-87` non-`NewArrayInit` Call branch — written for removed `string.Format` caller (commit 140dedacf); misreads a captured `object[]` passed to `Create` — out-of-scope: pre-existing, unrelated to caching
- Sibling text-producing APIs (`TableName`/`SchemaName`/`With`/`TagQuery`/`QueryHint`/`Sql.TableName`/table functions/`MethodChainBuilder`; the two exceptions are the `HandleStringFormat` and `AsCte` rows above) — registered via `[SqlQueryDependent]`, `RegisterExtensionAccessors` or `RegisterDynamicExpressionAccessor` (searched `EvaluateExpression|MarkAsValue|SqlQueryDependent|RegisterExtensionAccessors` in builders) — out-of-scope
- `ExpressionCacheManager.MarkAsValue` (`:680`) — append-only list, no dedupe; subquery-validation retry (`Query{T}.cs:223-230`) re-registers identical checks — out-of-scope: correct, negligible cost, shared with existing callers
- LinqService/remote — `MarkAsValue` state is client-side cache metadata, not serialized (searched `_byValueCompare` across `Source/`) — out-of-scope

## P8 Test obligations

All in `FromSqlTests`, `[Test, QueryCacheTest]`. SQL shape follows `TestBasicScalarQuery` (`FromSqlTests.cs:1020-1042`): `FROM {QuoteTableName("Person", context)}`, provider-quoted `value` alias (backticks on YDB), `[DataSources(TestProvName.AllAccess)]`; the varying part is a `WHERE` on `PersonID` against the `Person` test data (ids 1..4), so no FROM-less select. Each loops `{1, 2, 1}` and **declares the captured local inside the loop body** — a fresh closure per iteration, so an accessor that failed to re-root (U-3) reads the old closure object and shows up red rather than passing by reading a mutated shared closure. Miss counts are asserted as deltas between iterations (U-6), never absolute.

- TO-1 nested `FromSqlScalar<int>(FormattableStringFactory.Create(sql))` inside `Where(p => p.ID.In(...))`, `sql` text differs per iteration (`… WHERE PersonID = 1` / `= 2`); discriminating input: iteration-2 text; asserts result ids == `[v]` each iteration, miss count grows 1→2 and is unchanged 2→3 — proof: red→green
- TO-2 nested `FromSql`/`FromSqlScalar` with captured `FormattableString fs` whose format **and** interpolated argument change per iteration; asserts current rows each iteration — proof: red→green (D-1 alone suffices; does not isolate D-2 — TO-6 does)
- TO-6 nested `FromSqlScalar` with captured `FormattableString fs = $"… WHERE PersonID = {v}"` — format fixed, argument `{1,2,1}`; discriminating input: iteration-2 argument, which unfixed and D-1-only code answer with iteration-1 rows; asserts current rows each iteration and miss count unchanged after iteration 1 — proof: red→green (isolates D-2)
- TO-7a TO-6 with `int? v` over `{1, null, 1}`; asserts iteration 2 returns empty rows **without throwing** and iteration 3 returns `[1]` — proof: red→green (isolates the `Nullable<T>` lift; without it the cached accessor unboxes `null` → NRE)
- TO-7b TO-6 with `int? v` over `{null, 1, null}`; asserts iteration 2 returns `[1]` and iterations 1/3 empty — proof: red→green (isolates D-2(b): only a build-time `null` reaches it; a `Constant(null)` without `MarkAsValue` replays `NULL`)
- TO-3 nested `FromSql<Person>(rs, args)` with captured `RawSqlString rs` whose format changes, args via `params` (`FromSqlScalar` has no `RawSqlString` overload, `DataExtensions.cs:1533-1535`); asserts current rows each iteration — proof: red→green
- TO-4 nested inline `FromSqlScalar($"… WHERE PersonID = {v}")` (constant format, captured arg) over `{1,2,1}`; asserts current rows and miss count unchanged after iteration 1 — proof: characterization (guards against over-invalidation; already green before the fix)
- TO-5 `FromSqlTests` (incl. `Issue3782Test2/4` where providers are local), `SqlExtensionsTests`, `QueryCacheTests` on SQLite; CI baselines diff shows only the `Issue3782Test2/4` `inline=False` move plus new `Issue6000_*` files — proof: characterization

## P9 Verification gates

- G-01: pass — built `Tests/Linq` net10.0 in the worktree, ran `linq2db.Tests.exe --provider SQLite.MS --provider SQLite.Classic` (+ LinqService lanes): pre-fix `FromSqlTests.Issue6000` 24/24 red-row cases failed with the iteration-1 result replayed on iteration 2, TO-4 green; post-fix 30/30 green. TO-5: `FromSqlTests`, `SqlExtensionsTests`, `SqlExtensionTests`, `CachingTests`, `SqlRawSqlTableTests`, `Issue5125Tests`, `DynamicColumnsTests`, `QueryCacheEvictionTests` 368/368 green. `Issue3782Test2/4` not run locally (PostgreSQL / SqlServer) — CI
  - TO-1 `Issue6000_NestedScalar_FormatChanges` · TO-2 `Issue6000_NestedScalar_CapturedFormattable_FormatAndArgumentChange` · TO-6 `Issue6000_NestedScalar_CapturedFormattable_ArgumentChanges` · TO-7a `Issue6000_NestedScalar_CapturedFormattable_ValueThenNull` · TO-7b `Issue6000_NestedScalar_CapturedFormattable_NullThenValue` · TO-3 `Issue6000_Nested_CapturedRawSqlString_FormatChanges` · TO-4 `Issue6000_NestedScalar_InlineInterpolation_Cached` · TO-8 `Issue6000_NestedScalar_CapturedFormattable_ArgumentShapeChanges` · TO-9 `Issue6000_NestedScalar_CapturedFormattable_SqlExpressionArgumentChanges` · TO-10 `Issue6000_Nested_CapturedRawSqlString_ArgumentArrayChanges` — final state: unfixed 36/36 red cases fail, fixed 380/380 green
- G-02: — (pending CI) expect only `Issue3782Test2`/`Issue3782Test4` `inline=False` (literal → parameter) to move, plus new `Issue6000_*` files; `inline=True` sets expected unchanged (reasoned, unmeasured: inlined parameter renders through the same `ValueToSqlConverter` as a `SqlValue`) — inspect if they move, don't auto-fail; any other moved baseline is a regression
- G-03: n/a — `Sql.Expressions.cs` edit is a call-site change inside private nested `ExprBuilder`; `PrepareRawSqlArguments` is on internal `TableBuilder`
- G-04: n/a — no public surface changed
- G-05: pass — `dotnet build Source/LinqToDB/LinqToDB.csproj -c Release -f netstandard2.0` and `-f net10.0`: 0 warnings, 0 errors
- G-06: pass — diff limited to E-1..E-4; new signature column-aligned to file style
- G-07: pass — nothing under `Tests/Tests.Playground/` touched
- G-09: pass — `/code-review` on the worktree diff: 9 findings; 4 fixed via A-1 (types, count, `ISqlExpression`, `RawSqlString` array) with tests, 1 test-coverage finding addressed by TO-8..TO-10, 4 declined/deferred in P10

## P10 Adjudicated

- Nested captured-`FormattableString` arguments now emit parameters instead of literals (24 `Issue3782Test2/4` `inline=False` baselines). Reason: matches the top-level path (`DataExtensions.cs:1452` `WrapAsParameter`) and is the only way to fix argument staleness without a recompile per value; #3782 was about arguments not being applied at all, not about literal-vs-parameter form.
- `Sql.Expr` keeps literal arguments for a captured `FormattableString` (D-3 flag). Reason: already correct (uncached), no reported bug, patch release.
- `Sql.Expr` column-arg format staleness, `HandleStringFormat`, `AsCte(name)` — same bug class, deferred to [#6002](https://github.com/linq2db/linq2db/issues/6002) (6.x), widened to a builder-wide evaluate-and-register helper plus enforcement. Captured `ISqlExpression` array items are now covered by A-1.
- Review findings declined (A-1 round): literal → parameter for captured-`FormattableString` arguments where a provider rejects a parameter (`TOP {0}`) — accepted above, matches the top-level path; non-`NewArrayInit` `Create(fmt, arr)` Call branch — pre-existing (P7 out-of-scope); reuse `WrapAsParameter` — the top-level path relies on a reference-compared `FormattableString` constant (always a cache miss), so it has no cache-comparison logic to reuse.

## P11 Amendments

- A-1 (2026-10-08, after `/code-review`) — the review found that argument runtime types were not part of cache comparison: the same format arriving with `1L` / `"1"` / a `DataParameter` instead of `1` hit the cache and the typed accessor threw `InvalidCastException`; the same gap covered argument count (index past a shorter array), changing `ISqlExpression` arguments (inlined, compared against itself), and the captured `RawSqlString` `object[]` branch (P7 deferred row). Replaced D-2's `Nullable<T>` lift and D-2(b)'s null `MarkAsValue` with one mechanism: `PrepareRawSqlArguments` returns `cacheDependencies` — format, then `GetArguments().Length` / `array.Length`, then each element's runtime type (`null` → `null` type), plus the value of each `ISqlExpression` element — registered in order so the count check exits before any index read (`Query.cs:96-106` stops at the first mismatch). Exact type matching makes every accessor's `Convert(item, T)` safe and removes the `T` → `T?` parameter typing; a `null` argument stays an inlined constant and forces a rebuild through its type check. Applied to the captured `RawSqlString` array too (flag-gated, so `Sql.Expr` unchanged). Same E-1/E-2/E-3 files; E-1/E-2 descriptions superseded by this entry. New obligations TO-8 `ArgumentShapeChanges` (FormattableString `{[1], [2L, 99], [1]}`), TO-9 `SqlExpressionArgumentChanges` (`new SqlValue(v)` over `{1,2,1}`), TO-10 `CapturedRawSqlString_ArgumentArrayChanges` (`object[]` `{[1], [2L, 99], [1]}`) — all red→green, measured: on unfixed source 36/36 red cases fail (TO-10 with `InvalidCastException`), post-fix 380/380 green across the TO-5 set. Approval for the superseded E-1/E-2 detail re-earned by presenting this amendment.
- A-2 (2026-10-08, Copilot review on #6003) — TO-8/TO-10 changed count and type together and only grew the array, so the count check masked the type check and the count-first ordering was never exercised. Split each into `…ArgumentTypeChanges` (same length, `int` → `long`) and `…ArgumentCountShrinks` (`[1, 99]` → `[2]`). Controls, measured on SQLite.MS: mutation "type dependency removed" → only the two `TypeChanges` tests (InvalidCastException) and the two null tests fail, `CountShrinks` green; mutation "count dependency registered last" → only the two `CountShrinks` tests fail (IndexOutOfRangeException). Restored code: 388/388 green across the TO-5 set. Tests-only change, E-4.
- A-3 (2026-10-09, sdanyliv `a7d69548a`, `d737b6d5f`; recorded 2026-10-10 for the #6003 review) — **design replaced.** The `RawSqlContext` mechanism (D-1 `MarkAsValue`, D-2 accessor-backed arguments, D-3 flag, A-1 `cacheDependencies`) is reverted. The fix now happens at expose time:
  - the `FormattableString` parameter of `FromSql`, `FromSqlScalar` and `Sql.Expr` is `[SqlQueryDependent]` (E-8, E-9). This reverses D-1's rejection. D-1's failure mode (the whole `Create(...)` folds into a reference-compared constant) is avoided because `HandleSqlDependentParameters` routes `FormattableString` arguments to `PrepareFormattableString` instead of `PrepareForCache` (E-6).
  - `PrepareFormattableString` turns the format of `Create(format, new object[] {…})` into a constant and keeps the argument array as an expression. An evaluable captured `FormattableString` is expanded into the top-level shape, `Create(Constant(format), GenerateArray(args))`, with arguments wrapped as parameters (E-6).
  - `ConvertRawSqlString` rewrites both `RawSqlString` overloads into their `FormattableString` overloads, top-level calls included (E-6).
  - `SqlQueryDependentAttribute.ExpressionsEqual` compares the format by value and the argument array through the supplied comparer (E-7).
  - P3 revisions: `[SqlQueryDependent]` now sits on public parameters. This is an attribute on existing members; the signatures are unchanged and there is no new public API. `Sql.Expr` behaviour changes: the "byte-identical" anti-goal and the D-3 P10 entry are retired, and `Sql.Expr` takes the same path as `FromSql`.
  - New P10 baseline move, from the PR body: a `FromSql(RawSqlString, params object[])` argument array is now named by position, so `TestParametersInExpr2` renders `@p` instead of `@parameters`.
  - Tests are renamed without the `Issue6000_` prefix. SC→test map: SC-1 `FromSqlScalar_Nested_FormatChanges`; SC-2 `FromSqlScalar_Nested_Captured_FormatChanges`, `FromSql_Nested_FormatChanges`; SC-6 `FromSqlScalar_Nested_Captured_ArgumentChanges`; SC-3 `FromSql_Nested_RawSqlString_FormatChanges`; SC-4 `FromSqlScalar_Nested_Interpolated_ArgumentChanges`. The A-1/A-2 cases now map to `FromSqlScalar_Nested_Captured_ArgumentTypeChanges`, `FromSqlScalar_Nested_Captured_SqlExpressionArgumentChanges` (restored in `b16aed7dc`), `FromSql_Nested_RawSqlString_ArgumentsChange` (captured `object[]`: `[1]`, `[2L]`, `[3, 4]`), plus `Expr_FormatChanges` and `Expr_RawSqlString_ArgumentsChange` (E-12).
  - **Not re-pinned under the new mechanism** (reasoned, unprobed): SC-7 / TO-7a / TO-7b (a `null` argument) and the `…ArgumentCountShrinks` cases from A-2. No current test shrinks an argument array or passes `null`.
  - All tests are SQLite-only.
  - Critic: not re-dispatched. The design was replaced, not widened, at Tier M. The #6003 review is the first independent read of it.
- A-4 (2026-10-09, `b16aed7dc`) — compiled queries. With `[SqlQueryDependent]` on the parameter, a compiled query materialised the whole `FormattableString` from its argument array. Its arguments were inlined as literals, and each distinct value built and cached a separate query. Now only the format is resolved through `ResolveCompiledQueryArguments` and recorded via `RecordMaterializedArgumentSlots`; the interpolation arguments stay reads of the argument array and render as parameters (E-6). A `FormattableString` passed as a compiled-query argument threw on master; it is now expanded with parameters, and `DependentArgumentValues` compares and hashes it by format and arguments (E-11). Tests: `FromSql_Compiled_Interpolated_ArgumentIsParameter`, `FromSqlScalar_Nested_Compiled_ArgumentIsParameter`, `FromSql_Compiled_FormattableStringArgument`. Per the PR body, all three fail without the fix (not re-measured here). `649d46ba2` drops the no-op `unchecked` in `DependentArgumentValues.GetHashCode`; the repo sets no `CheckForOverflowUnderflow`.
- Approval for A-3 / A-4 is **void until re-earned**: the approved design (D-1..D-3, E-1..E-3) no longer describes the branch.

## P12 Critic verdict

Critic model: `fable` (config `criticModel: opus` is the author's own family, so overridden for independence).

**Round 1 — refuted.** Searched: both callers; `MarkAsValue` and the accessor map; `FormattableString|RawSqlString` across `Source/`; `EvaluateExpression<string>()` in builders; nested captured-`FormattableString` tests; `linq2db.baselines` HEAD for `Issue3782Test2/4` (measured: literal in all 48 files); `HandleValue`/`CanBeConstant`/`IsImmutable` whitelists; `ExposeExpressionVisitor.cs:481-519`; `QueryCache.TryFind`. Upheld D-1 and its rejection of `[SqlQueryDependent]`. Objections and responses:
1. D-2 moves `Issue3782Test2/4` baselines, contradicting P3/G-02 → owned: P3, SC-5, E-5, G-02, P7, P10 updated.
2. D-2 silently changes `Sql.Expr` → D-3 flag scopes the rewrite to `BuildRawSqlTable`.
3. TO-2 cannot isolate D-2 → TO-6 (argument-only) added.
4. Fresh closure needed for TO-1..TO-3 to guard U-3 → P8 preamble requires loop-body locals.
5. TO-1 SQL not provider-neutral → `TestBasicScalarQuery` shape adopted.
6. P7 sibling row not backed → `HandleStringFormat` and `AsCte` rows added, deferred.
7. D-1 constant skip must unwrap `Convert` → D-1 updated.
Also from "not checked": null-argument path → D-2 (b) and TO-7.

**Round 2 — refuted (narrowly).** Searched: `IsNullableType`, `ClientValueGetter`/`ParameterCacheEntry`, `CompareValues(`, `FromSqlScalar` overloads, `RegisterExtensionAccessors(`, `HandleValue`/`IsImmutable` re-trace for TO-6, `BuildParameter` null short-circuit. Upheld: D-1, D-3 flag (Sql.Expr byte-identical), owned `Issue3782` move, TO-6 discriminates three outcomes. Objections and responses:
1. `{1, null, 1}` → cached accessor unboxes `null` to `int` → NRE → D-2 lifts value types to `Nullable<T>`.
2. TO-7 never reached D-2(b) → split into TO-7a `{1,null,1}` (Nullable lift) and TO-7b `{null,1,null}` (D-2(b)).
3. TO-3 used a non-existent `FromSqlScalar(RawSqlString, …)` overload → `FromSql<Person>`.
4. No E-1→E-2 plumbing for null args → E-1 returns the null `ArrayIndex` list.
5. G-02 over-asserted `inline=True` unchanged → inspect-if-moved.
Revision cap (one round) reached; round-2 fixes are **not re-critiqued** — presented to the user with that status.
