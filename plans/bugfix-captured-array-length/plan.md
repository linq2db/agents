# Work plan: bugfix-captured-array-length — Bind client-only array Length as a parameter

**Tier:** M  ·  **Status:** approved  ·  **Approved-at:** 2026-10-22 (user, ArrayLength-only revision)  ·  **Branch:** bugfix/captured-array-length
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

## P1 Problem

A client-only `arr.Length` of a captured array used where SQL is required fails translation:

```csharp
var arr = new[] { 1 };
db.Person.Where(p => p.ID == arr.Length).ToList();
// LinqToDBException: The LINQ expression could not be converted to SQL.
// ArrayLength(value(<closure>).arr)
```

Same in an insert/update setter (`ItemsCount = arr.Length`). Measured with a NuGet probe (SQLite execution): 5.4.1 binds it as a parameter (`[r].[ItemsCount] = @ItemsCount`); 6.0.0, 6.3.0, 6.4.0, 6.5.0 and current master all throw. Regression from the 6.0 builder rewrite: 5.4.1's `ConvertToSql` had a node-agnostic `if (CanBeCompiled(expression)) return ParametersContext.BuildParameter(...)` (`Source/LinqToDB/Linq/Builder/ExpressionBuilder.SqlBuilder.cs:851` at `v5.4.1`); in 6.x that decision lives in per-node visitors, and `ExpressionBuildVisitor.VisitUnary` (`Source/LinqToDB/Internal/Linq/Builder/ExpressionBuildVisitor.cs:2662-2863`) has no case for `ExpressionType.ArrayLength`, so the node never reaches `HandleValue` (`:3057`) and falls through to `base.VisitUnary` (`:2863`) untranslated.

`ExpressionType.TypeAs` of a closure value fails the same way (measured on master: `(o as int?)` with `object o = 1`), but that is a deliberate maintainer decision, not this defect — see D-2 and P10.

## P2 Success criteria

- SC-1 `Where(p => p.ID == arr.Length)` with a captured `int[]` returns the matching rows on every provider, the length bound as a parameter. → TO-1
- SC-2 An insert setter `Value = arr.Length` stores the array length. → TO-2
- SC-3 The cached query re-evaluates the length per execution (array of length 1, then 2, returns different rows) without a second cache miss. → TO-3
- SC-4 A set-operation projection carrying `arr.Length` (`Select(... L = arr.Length).Concat(...)`) executes and returns the length. → TO-4
- SC-5 A plain final projection `select new { p.ID, L = arr.Length }` stays client-evaluated (no SQL column for `L`). → TO-5

## P3 Constraints & anti-goals (M/L)

- No public API change; the edit is inside `LinqToDB.Internal.*`.
- No change to row-dependent `ArrayLength` (array columns): not client-evaluable, so `HandleValue` declines and it keeps today's path.
- No change to `TypeAs`: `Sql.AsSql(1 as int?)` stays non-convertible, pinned by `ConstantTests.NullableTypeConstantDefininitionAsSqlThrows` (`Tests/Linq/Linq/ConstantTests.cs:293-303`, #5144).
- No change to `byte[].Length` / `Binary.Length`: already mapped to `Sql.Length` by `Linq/Expressions.cs:556,562` and rewritten in `ExposeExpressionVisitor.VisitUnary` (`Internal/Linq/Builder/Visitors/ExposeExpressionVisitor.cs:978-989`) before the build visitor runs.
- No change to final-projection client evaluation (`CanTryHandleValue` returns false for plain `BuildPurpose.Expression`, `ExpressionBuildVisitor.cs:3054`).
- No baselines change other than the new tests' own files.

## P4 Unknowns (M/L)

- U-1 Can `TranslateMember` / a member translator claim an `ArrayLength` node first, so ordering matters? — resolved-by scout: no. `MemberTranslatorBase.Translate` only looks up the registry for `MethodCallExpression or MemberExpression or NewExpression` (`Internal/DataProvider/Translation/MemberTranslatorBase.cs:52`) and its unary arm requires `Method != null` (`:74`); no registration of `Array.Length` exists under `Internal/DataProvider/**/Translation` (only string `"".Length`, `StringMemberTranslatorBase.cs:33`). `VisitUnary` itself calls `TranslateMember` only when `node.Method != null` (`ExpressionBuildVisitor.cs:2677,2700`).
- U-2 Which unary node kinds producible by the C# compiler in a lambda are unhandled by `VisitUnary`? — resolved-by probe (master, SQLite.MS): `~x` works (`(~@x)`), `-x - 1` works (`@p`), `o as int?` fails, `arr.Length` fails. `Increment`/`Decrement`/`IsTrue`/`IsFalse`/`Unbox`/`Throw` are not emitted by the C# lambda compiler; `Quote` is a lambda argument, not a value. So `ArrayLength` and `TypeAs` are the complete C#-producible set; `TypeAs` is excluded by D-2.
- U-3 Is `byte[].Length` affected? — resolved-by probe + scout: no. Probe on master: `Where(r => r.ItemsCount == bytes.Length)` → `[r].[ItemsCount] = Length(@bytes)`, produced by the `Linq/Expressions.cs:562` mapping that `ExposeExpressionVisitor` applies before `ExpressionBuildVisitor` runs (scout: `ExposeExpressionVisitor.cs:978-989`).
- U-4 Final projections today? — resolved-by probe: `Select(r => r.Id + arr.Length)` and `Select(r => new { r.Id, L = arr.Length })` work on master, SQL selects only `[r].[Id]` (client evaluation). `CanTryHandleValue` is false there (`ExpressionBuildVisitor.cs:3045-3054`), and `PreferClientCalculation` (`:2345-2355`) can short-circuit `VisitUnary` only under the same plain-`Expression` purpose — no conflict.
- U-5 Set-operation projection (`BuildFlags.ForSetProjection`) today? — resolved-by probe: `Select(r => new { r.Id, L = arr.Length }).Concat(Select(r => new { r.Id, L = 0 }))` throws `InvalidOperationException: No coercion operator is defined between types 'System.Int32[]' and 'System.Int32'` on master. `CanTryHandleValue` is true under `Expression + ForSetProjection` (`:3054`), so the new case reaches `HandleValue` there; reasoned, unprobed that this resolves the coercion error — TO-4 is the measurement, and an amendment follows if it does not.
- U-6 Query-cache correctness: does the parameter re-read the array per execution? — resolved-by scout + critic read: `IsImmutableVisitor.VisitMember` (`ExpressionTreeOptimizationContext.cs:454-466`) marks a closure field non-immutable, so `CanBeConstant` is false and `HandleValue` takes `ParametersContext.BuildParameter` (`ExpressionBuildVisitor.cs:3083`), an accessor over the closure expression. TO-3 measures both the value and the cache-miss count.
- U-7 `OrderBy(r => r.Id + arr.Length)` — resolved-by probe: works on master today (not routed through the gap); out of scope.
- U-8 Does an existing test pin the behaviour of a client-only unary the case would change? — resolved-by critic search: for `TypeAs` yes (`ConstantTests.cs:293-303`, #5144); for `ArrayLength` no (`.Length` census in P7).

## P5 Decisions (M/L; rejected alternatives mandatory at L)

### D-1 — A dedicated `ArrayLength` case in `ExpressionBuildVisitor.VisitUnary` calling `HandleValue`

- **chosen:** in the `switch (node.NodeType)` (`ExpressionBuildVisitor.cs:2706`) add `case ExpressionType.ArrayLength:` → `if (HandleValue(node, out var translatedValue)) return Visit(translatedValue); break;`. `HandleValue` already gates on `Sql`/`Expression+ForSetProjection` purpose, `CanBeEvaluatedOnClient` and `PreferServerSide` (`:3043-3055`), so a row-dependent node declines and keeps today's `base.VisitUnary` path. Mirrors `VisitMember` → `HandleMember`, which tries `HandleValue` right after `TranslateMember` (`:1712-1724`); `TranslateMember` cannot claim a method-less unary (U-1).
- **rejected:** a generic `HandleValue` fallback before the final `return base.VisitUnary(node)` — it would also fire for `Convert`/`ConvertChecked` that `break` out of their case (e.g. conversion to `object`, which the `Convert` case deliberately excludes at `:2854`), for `Not`/`Negate` whose own cases did not return, and for `TypeAs` (D-2); wider blast radius than the defect.
- **rejected:** register `T[].Length` in `Linq/Expressions.cs` — the member map is keyed by concrete array type (`MemberInfoWithType`, `MemberHelper.cs:23-26`), so it cannot cover `T[]` generically, and a mapping would also rewrite row-dependent array columns.
- **rejected:** rewrite `ArrayLength` into a `MemberExpression` on `Array.Length` in `ExposeExpressionVisitor` — changes the tree shape for every consumer (row-dependent array columns, cache keys, test generator) to fix one visitor's missing case.
- **why this:** smallest change at the exact site of the gap; reuses the shared parameterization path unchanged. The `Convert` twin's `node.Type != typeof(object)` clause is not carried: an `ArrayLength` node is always `int`.
- **failure mode of the choice:** another unhandled unary kind still falls through; accepted — none besides `TypeAs` is producible from C# lambdas (U-2).

### D-2 — Leave `TypeAs` out

- **chosen:** `ArrayLength` only.
- **rejected:** add `TypeAs` to the same case — would turn `Sql.AsSql(1 as int?)` into `SELECT 1` (critic trace: `HandleValue` → `CanBeConstant` → `BuildConstant`), reversing the #5144 decision that `as` stays non-convertible (sdanyliv: "We do not support `try_convert` out of the box and never have"), and flipping `ConstantTests.NullableTypeConstantDefininitionAsSqlThrows` red on every non-SQLite provider.
- **why this:** the task is the `Length` fix; reversing a maintainer decision needs its own discussion.
- **failure mode of the choice:** a client-only `o as T` keeps failing translation; recorded in P10.

## P6 Edit-points

- E-1 `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuildVisitor.cs:VisitUnary` — add `case ExpressionType.ArrayLength:` calling `HandleValue`, else `break`.
- E-2 `Tests/Linq/Linq/ParameterTests.cs` — new tests TO-1..TO-6.

## P7 Impact map (M/L)

- `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuildVisitor.cs:2706` `VisitUnary` switch — the only `ExpressionBuildVisitor` site for this node kind (scout searched `ArrayLength` across `Source/LinqToDB`; `VisitUnary` handles only Not/UnaryPlus/Negate/NegateChecked/Convert/ConvertChecked) — covered by E-1
- `Source/LinqToDB/Internal/Linq/Builder/Visitors/ExposeExpressionVisitor.cs:978-989` `ArrayLength` via `Linq.Expressions.ConvertMember` — runs earlier; mapped `byte[]` never reaches E-1 (searched `ArrayLength` in `Source/LinqToDB`) — out-of-scope
- `Source/LinqToDB/Linq/Expressions.cs:556,562` `Binary.Length` / `byte[].Length` → `Sql.Length` — unchanged (searched `\.Length\b` mappings in `Linq/Expressions.cs`) — out-of-scope
- `Source/LinqToDB/Internal/DataProvider/Translation/MemberTranslatorBase.cs:52,74`, `TranslationRegistration.cs:254` — cannot dispatch a method-less unary (searched `Register(Member|Method)…Length|\[\]` under `Internal/DataProvider`) — out-of-scope
- `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuildVisitor.cs:3043-3097` `CanTryHandleValue`/`HandleValue` — reused unchanged; callers of the visitor with `BuildPurpose.Sql`: Where (`ExpressionBuilder.SqlBuilder.cs:75` → `:4000`), setters (`UpdateBuilder.cs:490,514,527`, reached from `InsertBuilder.cs:108,139,189,358,514`), OrderBy/GroupBy/Join/DistinctBy keys (`OrderByBuilder.cs:109,114`, `GroupByBuilder.cs:170,231,391`, `JoinBuilder.cs:132-133`, `DistinctByBuilder.cs:127`); `Expression+ForSetProjection`: `MergeProjectionHelper.cs:48-49`, `ExpressionBuilder.EagerLoadUnion.cs:203,313,471,904` (searched `UsingBuildPurpose\(|BuildPurpose\.(Sql|Expression)\b|ForSetProjection` in `Internal/Linq/Builder`) — covered by E-1 (all gain parameterization of client-only ArrayLength; TO-1, TO-2, TO-4 exercise Where, setter, set projection)
- `TypeAs` consumers `ExpressionBuilder.SqlBuilder.cs:1801`, `SelectContext.cs:114,147`, `ExpressionBuildVisitor.cs:1769,3867`, and the #5144 pin `ConstantTests.cs:293-303` (searched `ExpressionType\.TypeAs` in `Internal/Linq/Builder`; critic searched `\bas (int|long|…|object|char)\??\)` in `Tests/Linq`) — untouched, E-1 does not handle `TypeAs` — out-of-scope
- `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuildVisitor.cs:2345-2355` `PreferClientCalculation` — returns before the switch only under plain `Expression` purpose where `HandleValue` is false anyway — out-of-scope
- Tests: no existing test uses a captured array's `.Length` inside a query (searched `=>.*[^.\w]\w+\.Length\b`, `\.(Where|Select|Set|Value|Update|Insert|OrderBy|GroupBy|Any|Count)\(.*\b\w+\.Length\b`, `ArrayLength` across `Tests/**/*.cs`; only string `.Length` hits) — covered by E-2
- Remote (`LinqService`) — no contract change; a parameter is serialized like any closure value (nothing added under `Internal/Remote`) — out-of-scope

## P8 Test obligations (M/L)

Fixture `Tests/Linq/Linq/ParameterTests.cs` (owns closure→parameter behaviour). `[DataSources]` with no exclusions; layout per `testing.md` → *Test layout* (one call per line, `AssertQuery` where the result is a sequence).

- TO-1 `ArrayLengthInWhere`: `db.Person.Where(p => p.ID == arr.Length)` with `var arr = new[] { 0 }` via `AssertQuery`; discriminating input: length 1 matches exactly Person ID 1, master throws `LinqToDBException` — providers: `[DataSources]` (all, incl. `.LinqService`) — proof: red→green
- TO-2 `ArrayLengthInInsertSetter`: local table, `table.Insert(() => new T { Id = 1, Value = arr.Length })` with a 3-element array, read back `Value == 3`; master throws — providers: `[DataSources]` (all, incl. `.LinqService`) — proof: red→green
- TO-3 `ArrayLengthIsReadPerExecution`: same query run with `arr = new[] { 0 }` then `arr = new[] { 0, 0 }`; asserts single row ID 1 then ID 2, and `GetCacheMissCount()` unchanged across the second run (fixture idiom `ConstantTests.cs:266-270`); master throws on the first run — providers: `[DataSources]` (all, incl. `.LinqService`) — proof: red→green
- TO-4 `ArrayLengthInSetProjection`: `Select(p => new { p.ID, L = arr.Length }).Concat(Select(p => new { p.ID, L = 0 }))` over Person filtered to ID 1, via `AssertQuery`; discriminating: `L` is 2 for the first branch; master throws the coercion error (U-5) — providers: `[DataSources]` (all, incl. `.LinqService`) — proof: red→green
- TO-5 `ArrayLengthInProjection`: `select new { p.ID, L = arr.Length }` via `AssertQuery` plus `query.GetSelectQuery().Select.Columns.Count.ShouldBe(1)` (idiom `ComplexTests.cs:734`) — discriminating: a bound `L` would add a second column; passes on master too — providers: `[DataSources]` (all, incl. `.LinqService`) — proof: characterization (proves the plain-projection path is unchanged, nothing new)
- TO-6 `ArrayLengthInCompiledQuery`: `CompiledQuery.Compile((ITestDataContext db, int[] arr) => db.Person.Where(p => p.ID == arr.Length).Select(p => p.ID))` invoked with lengths 1 then 2, returns ID 1 then 2 — the array arrives through `ParametersParam`, not a closure; master throws `could not be converted to SQL` — providers: `[DataSources]` (all, incl. `.LinqService`) — proof: red→green

## P9 Verification gates

- G-01: pass — `worktree-test.ps1` on SQLite.MS, SQLite.Classic, SqlServer.2022 (+ `.LinqService`): unfixed E-1 → 24 failed / 9 passed (18× `LinqToDBException: could not be converted to SQL` = TO-1/2/3, 6× `No coercion operator … Int32[] … Int32` = TO-4; TO-5 green ×6); fixed → 33/33 green. Collateral `ParameterTests`+`ConstantTests`+`InheritanceTests` on SQLite.MS, SqlServer.2022 (+ `.LinqService`): 545 total, 0 failed, 26 skipped (after adding `[QueryCacheTest]` to TO-3 — without it the shared per-type cache-miss counter raced under parallel execution, 1 failure on SqlServer.2022). `test-diff-sweep.ps1 -IncludeWorkingTree`: 0 chains, 0 narrowed sets. After A-1: E-1 removed locally → TO-6 red ×4 (SQLite.MS, SqlServer.2022 + `.LinqService`, `could not be converted to SQL`), restored → all six tests 39/39 green on SQLite.MS, SQLite.Classic, SqlServer.2022 (+ `.LinqService`); `Tests/Linq` Release net10.0 0 errors. Tests: TO-1 `ArrayLengthInWhere`, TO-2 `ArrayLengthInInsertSetter`, TO-3 `ArrayLengthIsReadPerExecution`, TO-4 `ArrayLengthInSetProjection`, TO-5 `ArrayLengthInProjection`, TO-6 `ArrayLengthInCompiledQuery`.
- G-02: pass — `BaselinesPath` `c:\GitHub\linq2db.bls` (not a git repo; only new files): 15 new `ParameterTests.ArrayLength*` files; read SqlServer.2022 Where/Insert/SetProjection — length bound as `@arr` (`= 1`, `= 3`, `CAST(@arr AS Int)` in the UNION ALL leg). No pre-existing baseline touched by the change (collateral run produced no new-SQL diffs to review; dir untracked, so verified by test outcome only).
- G-05: pass — `dotnet build Source/LinqToDB/LinqToDB.csproj -c Release -f netstandard2.0` and `-f net10.0`: 0 warnings, 0 errors (fresh DLLs, 33 s); `Tests/Linq` Release net10.0: 0 warnings, 0 errors.
- G-06: pass — `git diff` touches only E-1 (one added `case`, 10 lines) and E-2 (new tests at end of fixture).
- G-07: pass — `git status`: only `ExpressionBuildVisitor.cs` and `ParameterTests.cs` modified; nothing under `Tests/Tests.Playground/`.
- G-09: pass — independent read on `fable` (general-purpose agent, read-only) of the full diff: no correctness findings; walked `CanTryHandleValue`, row-dependent decline, `PreferClientCalculation`, `ForKeys`, `ForceParameter`, `ParametersParam`, cache-key equality. Nit (TO-3 name) and an untested compiled-query path → A-1.

## P10 Adjudicated (M/L)

- A client-only `o as T` keeps failing translation. #5144 (`ae50f7cc8`) kept `as` non-convertible on purpose (`try_convert` semantics are unsupported) and pins it in `ConstantTests.cs:293-303`; reopening that is a maintainer call, not part of this fix.
- `VisitTypeBinary` (`ExpressionBuildVisitor.cs:3935-3948`) has the same no-`HandleValue` shape for `o is T` on a captured object (critic, by reading). Contrived in a predicate; not in scope.

## P11 Amendments (M/L)

- A-1 (2026-10-22, independent review) — rename TO-3 to `ArrayLengthIsReadPerExecution` (the query is cached; the value is re-read); add TO-6 for the compiled-query path, which reaches E-1 through `ExpressionBuilder.ParametersParam` and had no test.
  re-derives: P6 (E-2), P8 (TO-3, TO-6), P9 (G-01, G-09)
  conventions: `testing.md` → *Test layout* embedded; swept with `test-diff-sweep.ps1 -IncludeWorkingTree` — 0 chains, 0 narrowed sets.

## P12 Critic verdict (M/L)

**weak** — plan-critic on `fable`, 2026-10-22. It searched `ArrayLength` and `ExpressionType\.TypeAs` across `Source/LinqToDB`, every `HandleValue\(` call site, the client-evaluability / `IsImmutableVisitor` / `PreferServerSide` code, `\bas …\??\)` and `.Length` patterns across `Tests`, `git log -S` for the #5144 test, and v5.4.1 `ConvertToSql`.

Objections and response:

- Including `TypeAs` reverses #5144 and flips `ConstantTests.NullableTypeConstantDefininitionAsSqlThrows` red (verified: test at `ConstantTests.cs:293-303`; PR #5144 thread records the decision). → `TypeAs` dropped (D-2), its obligations removed, P10 entry added, `ConstantTests` added to G-01.
- TO-6 (now TO-5) could not fail for its criterion's reason. → now asserts the select-column count.
- TO-3 did not pin the cached half of its criterion. → now asserts `GetCacheMissCount()` equality.
- TO-7's premise was unmeasured. → removed with `TypeAs`.
- `VisitTypeBinary` has the same shape (minor). → P10.
- Clause parity with the `Convert` twin (minor). → D-1: `ArrayLength` is always `int`.

Not re-dispatched: the revision narrows scope and tightens assertions; it adds no edit-point.
