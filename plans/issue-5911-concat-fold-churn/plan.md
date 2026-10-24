# Work plan: issue-5911-concat-fold-churn — Concat fold rebuilds unchanged literals on every optimizer pass

**Tier:** M  ·  **Status:** approved  ·  **Approved-at:** 2026-10-24 (E-1, E-2; TO-1…TO-10)  ·  **Branch:** issue/5911-concat-fold-churn
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

## P1 Problem

`SqlExpressionOptimizerVisitor.VisitSqlConcatExpression` (`Source/LinqToDB/Internal/SqlProvider/SqlExpressionOptimizerVisitor.cs:1267-1348`) calls `EnsureFolded(i)` on the first evaluable non-empty string operand (`:1320`) whether or not anything will merge, then `FlushPending` emits `new SqlValue(pending)` (`:1290`) and the method returns `new SqlConcatExpression(...)` (`:1347`). So a concat whose literals are all lone and already in folded form — e.g. `$CONCAT$(t.A, '-', t.B)` — is rebuilt with a fresh `SqlValue` per literal and a fresh concat node on **every** optimizer pass. The fold has no identity fixpoint.

measured (#5911 probe, `C:\Worktrees\linq2db\5911-optimizer-passes`, SQLite.MS, 628 tests across CteTests / ConcatUnionTests / SetOperator* / JoinTests / JoinOptimizeTests / LeftJoinTests): every `SelectQueryOptimizerVisitor.cs:223` whole-tree pass in fixpoint iteration ≥2 that changed the tree's debug string (19 of 3,472) changed only `[UID:n]` values, and the diffs inspected (`AggressiveCteOptimizationTwoColumns`, `Issue3945`) are exactly the `'-'` / `' 00:00:00.000'` literals inside `$CONCAT$` getting new UIDs. Before: `$CONCAT$(..., [UID:947]'-', ...)`; after the next pass on an unchanged tree: `$CONCAT$(..., [UID:951]'-', ...)`.

Consequence: per-pass allocation churn in the query-build path (#5911 suspects allocation pressure for its super-linear component), and node identity that changes with no semantic change, which makes "did this pass change anything" unanswerable by reference comparison — the premise #5911's pass-skipping work needs.

## P2 Success criteria

- SC-1 Optimizing a concat whose string literals are lone (no adjacent literal), non-empty and already `SqlValue` with `ValueType == new DbDataType(typeof(string))` returns the **same** `SqlConcatExpression` instance and leaves its operand array untouched. → TO-1
- SC-2 Every shape that folds today still folds to the same output: adjacent literals merge, empty / evaluated-NULL literals drop (`PreserveNull=false`), evaluated NULL returns a NULL value (`PreserveNull=true`), a single-literal concat collapses to the literal, a non-canonically typed literal is rebuilt with the default `string` type, a non-`SqlValue` evaluable string operand is replaced by its value; a non-string evaluable operand between literals keeps them unmerged and unchanged. → TO-1b, TO-2…TO-7, TO-9
- SC-4 With the fix applied, no whole-tree expression pass in fixpoint iteration ≥2 changes the tree's debug string on the #5911 probe corpus (measured on master: 19 of 3,472 changed, all UID-only). → TO-10
- SC-3 Generated SQL is unchanged across providers (no baselines diff on the PR's baselines branch). → TO-8

## P3 Constraints & anti-goals (M/L)

- No change to generated SQL on any provider; no baselines delta.
- Keep the first-pass type normalisation of a string literal to plain `DbDataType(typeof(string))` (`new SqlValue(object)`, `SqlValue.cs:25-29`). Whether that normalisation is itself right is out of scope.
- No public API change (`SqlExpressionOptimizerVisitor` members are `Internal.*`; the override signature is untouched).
- No change to `SelectQueryOptimizerVisitor`'s pass structure — that is the separate #5911 plan.

## P4 Unknowns (M/L)

- U-1 Does any caller rely on the concat fold returning a *new* node (e.g. a `!ReferenceEquals` loop that expects progress, or a shared-node un-sharing)? — resolved-by scout: every override/caller of `VisitSqlConcatExpression` (S-1) treats `ReferenceEquals(result, element)` as "nothing changed"; the fold already returns `element` for a concat with no evaluable operand (`:1336-1337`), so the unchanged-identity outcome is an existing, exercised path.
- U-2 Is a rebuilt literal byte-identical to a kept canonical one? — resolved-by scout: `new SqlValue(object)` sets only `Value` and `ValueType = new DbDataType(value.GetType())` (`SqlValue.cs:25-29`); `SqlValue` carries no other state (`SqlValue.cs:30-45`). A kept operand passing the canonical test (same string, `ValueType == DbDataType(typeof(string))`) is indistinguishable apart from identity. `DbDataType` equality is value equality over all six facets (`DbDataType.cs:109-117`, `operator ==` at `:150`). Keeping instances can leave a literal shared where master un-shared it (`SqlExpressionConvertVisitor.cs:846` puts one `anyCharacterExpr` twice in a concat; `:762` shares `character` with a REPLACE argument); critic searched `\.ValueType\s*=[^=]` across `Source/` — 7 setters, all build-time — and found no post-optimization mutator, and `LinqServiceSerializer.cs:72` dedupes by reference, so sharing is harmless.
- U-3 `SqlValue.ValueType` has a public setter (`SqlValue.cs:36-45`); a pass between optimizer runs could retype a literal. — resolved-by design: the canonical test requires the default `string` type, so a retyped literal is still rebuilt (and re-normalised) exactly as today.
- U-4 Does `TryEvaluateNoParameters` on a `SqlValue` return its `Value` unchanged? — resolved-by probe at TO-1/TO-6 (the canonical case must evaluate to the same string; a non-`SqlValue` evaluable operand must still be replaced).

## P5 Decisions (M/L; rejected alternatives mandatory at L)

### D-1 — Decide "needs folding" in a read-only pre-scan, keep the fold loop as is

- **chosen:** before the existing loop, a pre-scan over `operands` returns `element` unless some operand needs work. A "string literal" here is defined exactly as the loop defines it — `TryEvaluateNoParameters(operand, out v) && v is string` (`:1298`, `:1312`) — so it includes any evaluable non-`SqlValue` operand, e.g. an inlined `SqlParameter` (`IsQueryParameter = false`) at execution time. Needs work: an evaluated NULL; an empty string; a string literal adjacent (no non-literal between) to another string literal; a string literal whose operand is not a canonical `SqlValue` (`operand is SqlValue { Value: string } sv && sv.ValueType == StringType`); or `operands.Length == 1` with that operand a string literal (the loop collapses it to the literal, `:1344-1345`). A non-string evaluable operand resets adjacency, as it flushes `pending` in the loop (`:1329-1333`). If any holds, the unchanged loop runs.
- **rejected:** keep the original typed operand when it is lone (skip normalisation) — changes literal typing, and so possibly the rendered literal (e.g. a `DataType.NVarChar` literal), on the first pass; violates P3.
- **rejected:** lazily materialise `folded` inside the loop (defer `EnsureFolded` until a second literal or a drop is seen) — one pass, no double evaluation, but restructures the fold's control flow; a larger diff in a method whose behaviour must be preserved exactly.
- **rejected:** run the loop, then compare `folded` element-wise with `operands` and return `element` when equal — still allocates the list and the `SqlValue`s every pass, which is half the problem.
- **why this:** the loop is untouched, so SC-2 holds by construction; the pre-scan only adds an early return whose condition is "the loop would emit the same operands", argued per branch in U-2.
- **failure mode of the choice:** operands that fold are evaluated twice (pre-scan, then loop). Cost lands only on the pass that actually folds — typically the first; a pre-scan condition that disagrees with the loop silently drops a fold (guarded by TO-2…TO-7).

## P6 Edit-points

- E-1 `Source/LinqToDB/Internal/SqlProvider/SqlExpressionOptimizerVisitor.cs:VisitSqlConcatExpression` — add the D-1 pre-scan (early `return element`) ahead of the fold loop; a static `DbDataType` for the canonical string type.
- E-2 `Tests/Linq/Linq/StringConcatTests.cs` — AST-level tests TO-1…TO-7 driving `SqlExpressionOptimizerVisitor.Optimize` directly on hand-built concats over `Person` fields.

## P7 Impact map (M/L)

- S-1 overrides/callers: searched `VisitSqlConcatExpression` across `Source/` (worktree at `origin/master` 57b910ede). `QueryElementVisitor.cs:3644` (base), `SqlExpressionConvertVisitor.cs:1765` (`!ReferenceEquals(converted, element)` → re-visit; termination needs identity, unaffected or helped), `SelectQueryOptimizerVisitor.cs:4111` (nested visitor, returns `element`), `ReduceIsNullExpressionVisitor.cs:192`, `WrapParametersVisitor.cs:234` — none depends on the optimizer producing a new node — out-of-scope
- S-2 producers: searched `new SqlConcatExpression(` across `Source/` — 17 sites (`ExtensionBuilderExtensions.cs:48,61,76`, `SqlExpressionFactoryExtensions.cs:212,221,236`, `SqlExpressionConvertVisitor.cs:762,844-846,1964,1991`, `QueryHelper.cs:1687`, `YdbSqlExpressionConvertVisitor.cs:325`, `SqlServerSqlExpressionConvertVisitor.cs:238`, `LinqServiceSerializer.cs:3235`, `QueryElementVisitor.cs:3667`, the fold itself `:1347`). Any of them can feed literals in any type; the canonical test decides per operand, so producers need no change — covered by E-1
- S-5 `SelectQueryOptimizerVisitor.cs:3890-3907` `OptimizeInnerQueries` — consumes the optimizer's result by reference identity and clears `doNotRemoveQueries` on change; found by G-09, not by the original sweep (searched callers of `VisitSqlConcatExpression`, not consumers of `Optimize`'s identity) — deferred: reach unprobed off SQLite, gated by G-02 (A-1)
- S-3 `Source/LinqToDB/Internal/Remote/LinqServiceSerializer.cs:3235` remote deserialisation builds concats from the wire; shape unchanged — out-of-scope
- S-4 literal rendering: a kept canonical literal has the same `ValueType` as the rebuilt one (U-2), so `BasicSqlBuilder` literal rendering sees identical input — Localized — searched `new SqlValue(` construction in the fold (`:1290,1303,1342`) and `SqlValue` state (`SqlValue.cs:13-45`); no emitted-SQL change — covered by E-1

## P8 Test obligations (M/L)

- TO-1 `$CONCAT$(Person.FirstName, '-', Person.LastName)` with `'-'` as `new SqlValue("-")`, `PreserveNull=false`: `Optimize` returns the same instance (`ShouldBeSameAs`) and `Expressions[1]` is the same `SqlValue`. Discriminating input: a lone canonical literal — master rebuilds it. — providers: none (AST-level, no data source) — proof: red→green
- TO-1b `(FirstName, 'a', new SqlValue(5), 'b')` returns the same instance — pins D-1's adjacency reset by a non-string evaluable operand; an implementation treating `5` as adjacency-neutral re-folds every pass. — providers: none — proof: red→green
- TO-2 adjacent literals `(FirstName, 'a', 'b', LastName)` fold to `(FirstName, 'ab', LastName)`. — providers: none — proof: characterization
- TO-3 empty literal `(FirstName, '', LastName)` with `PreserveNull=false` drops to `(FirstName, LastName)`. — providers: none — proof: characterization
- TO-4 evaluated NULL `new SqlValue(typeof(string), null)` with `PreserveNull=true` returns a NULL `SqlValue`; with `PreserveNull=false` it drops. — providers: none — proof: characterization
- TO-5 single-literal concat `('x')` returns the `SqlValue` `'x'`, not a concat. — providers: none — proof: characterization
- TO-6 non-canonical literal `new SqlValue(new DbDataType(typeof(string), DataType.NVarChar), "-")` between two fields is rebuilt: result is a new concat whose literal has `ValueType == new DbDataType(typeof(string))`. Discriminating input for the pre-scan's type test: dropping that test keeps the NVarChar literal. — providers: none — proof: characterization
- TO-7 a second `Optimize` over the result of TO-2 / TO-6 returns that result unchanged (`ShouldBeSameAs`) — the fixpoint after a real fold. — providers: none — proof: red→green
- TO-9 inlined parameter `(FirstName, p, LastName)` with `p = new SqlParameter(new DbDataType(typeof(string)), "p", "-") { IsQueryParameter = false }` and an `EvaluationContext` carrying `p`'s value (`SqlParameterValues.SetValue`, `SqlParameterValues.cs:35`): result is a new concat whose `Expressions[1]` is `SqlValue { Value: "-" }` with `ValueType == new DbDataType(typeof(string))`. Discriminating input for D-1's literal predicate: a pre-scan keyed on `operand is SqlValue` instead of evaluation leaves `p` in place, and SQL Server then renders `'-'` (VarChar) where master renders `N'-'` (critic: `SqlServerMappingSchema.cs:308-312`). — providers: none — proof: characterization
- TO-8 SQL unchanged: `StringConcatTests` and `CteTests` green on SQLite.MS locally, and the PR's baselines branch shows no diff on CI. — providers: SQLite.MS (local), CI matrix (baselines) — proof: characterization
- TO-10 port E-1 onto the probe worktree (`C:\Worktrees\linq2db\5911-optimizer-passes`, uncommitted instrumentation) and re-run its corpus (CteTests, ConcatUnionTests, SetOperator*, JoinTests, JoinOptimizeTests, LeftJoinTests on SQLite.MS): expected `changed=False` on every `iterN-*` row (master: 19 changed of 3,472). A non-zero count names a second churn source. — providers: SQLite.MS — proof: red→green

## P9 Verification gates

- G-01: pass (local half) — red run on unfixed E-1 (`worktree-test.ps1 -Filter …StringConcatTests.Optimizer_ -NoBuild`): 11 run, 4 failed exactly TO-1, TO-1b, TO-7(True/False) with "should be same as … but was", 7 characterization green. Green run with E-1 (`-Filter CreateData.CreateDatabase|StringConcatTests.|CteTests.` on SQLite.MS): 233/233 passed, `missingTests: []`. TO-10 pass: E-1 applied via `git apply` onto the probe worktree, corpus widened to 979 tests (adds SelectQueryOptimizationTests, xUpdate.UpdateTests, xUpdate.InsertTests; 976 passed, 3 skipped, 0 failed): 0 `changed` rows among 4,439 iteration-≥2 root passes and 166 iteration-≥2 CTE-body passes (master, 628-test corpus: 19 changed, all UID-only), so the concat fold was the only churn source on this corpus. TO-8's CI half still pending.
  - TO-1 → `StringConcatTests.Optimizer_LoneLiteral_KeepsConcat` (red → green)
  - TO-1b → `StringConcatTests.Optimizer_LiteralsSeparatedByNonStringConstant_KeepsConcat` (red → green)
  - TO-2 → `StringConcatTests.Optimizer_AdjacentLiterals_Merge` (green before and after)
  - TO-3 → `StringConcatTests.Optimizer_EmptyLiteral_Drops` (green before and after)
  - TO-4 → `StringConcatTests.Optimizer_NullLiteral_PreserveNull_ReturnsNull`, `StringConcatTests.Optimizer_NullLiteral_NoPreserveNull_Drops` (green before and after)
  - TO-5 → `StringConcatTests.Optimizer_SingleLiteral_CollapsesToLiteral` (green before and after)
  - TO-6 → `StringConcatTests.Optimizer_TypedLiteral_RebuiltWithStringType` (green before and after)
  - TO-7 → `StringConcatTests.Optimizer_FoldedConcat_IsFixpoint(True/False)` (red → green)
  - TO-8 → `StringConcatTests` + `CteTests` on SQLite.MS, 233/233 (local half)
  - TO-9 → `StringConcatTests.Optimizer_InlinedParameter_ReplacedByValue` (green before and after)
  - TO-10 → probe re-run, 0 changed iteration-≥2 rows
- G-02: blocked — CI baselines on the PR (TO-8's CI half); needs the push and an Azure `test-all` run.
- G-05: pass — `dotnet build Source/LinqToDB/LinqToDB.csproj -c Release -f netstandard2.0` and `-f net10.0` both "Build succeeded", 0 warnings.
- G-06: pass — `git diff --stat`: 2 files, 221 insertions, 0 deletions; no unrelated lines touched.
- G-07: n/a — no `Tests/Tests.Playground/` changes.
- G-09: pass — `code-reviewer` over `git diff 57b910ede` (unpushed): 1 finding, MIN001 (`OptimizeInnerQueries` identity consumer) → A-1; pre-scan ≡ loop confirmed clause by clause, each clause pinned by a test; no public API change. Out-of-scope note: rebase onto current `origin/master` before the PR.

## P10 Adjudicated (M/L)

_None yet._

## P11 Amendments (M/L)

- A-1 (2026-10-24, G-09 `code-reviewer` MIN001) — P7 missed a reference-identity consumer of the optimizer's result: `SelectQueryOptimizerVisitor.OptimizeInnerQueries` (`SelectQueryOptimizerVisitor.cs:3890-3907`) sets `column.Expression = optimized` and calls `doNotRemoveQueries?.Clear()` whenever `Optimize` returns a new instance (`:3900-3904`). `MoveDuplicateUsageToSubQuery` adds its wrapper to that list (`:3613`, reached from `:3763` / `:3804` for an `OuterApply` on a provider without APPLY, or a conditionless join where `IsSupportsJoinWithoutCondition` is false), and `OptimizeSubQueries` honours it (`:2748`). On master a top-level `$CONCAT$` with a string literal in an accessible subquery column came back as a new node every pass and cleared the list; with E-1 it does not, so the wrapper can now survive where master merged it back. Possible SQL change on those providers, against P3. measured: on master's fold with probes on `doNotRemoveQueries.Add` and on every clear of a non-empty list, 1,760 SQLite.MS tests (781: SubQueryTests, StringConcatTests, EagerLoadingTests, SelectTests, AssociationTests; 979: the TO-10 corpus) recorded **0** adds and **0** non-empty clears — the path is not reached on SQLite. Reach on Access / SQLite-less-APPLY shapes / MySQL 5.7 / Firebird <4 / Informix / ClickHouse is unprobed locally; G-02 (CI baselines across the matrix) is the gate, and a baselines diff in an OUTER APPLY / conditionless-join shape is to be read as this mechanism first. If it fires, the branch's output (protection kept) is the one the list was written for; that would be recorded as a P10 entry and P3 narrowed. No E-n change.
  re-derives: P7 (new row), P3 (conditional on G-02)

## P12 Critic verdict (M/L)

**weak** (plan-critic, model `fable`, 2026-10-24, round 1).

Objections, all answered by additions; E-1 and D-1's mechanism unchanged:

1. SC-2's "non-`SqlValue` evaluable operand" clause had no obligation, and it is reachable: an inlined `SqlParameter` (`IsQueryParameter=false`, `ParametersContext.cs:179`) passes `HasQueryParameter()` and evaluates at execution (`BasicSqlOptimizer.cs:2130-2134` → `OptimizationContext.cs:130/170/183`); a pre-scan keyed on `operand is SqlValue` would leave it in place and change SQL Server literal rendering (`'x'` vs `N'x'`, `SqlServerMappingSchema.cs:308-312`) silently. → D-1 now pins the literal predicate to the loop's `TryEvaluateNoParameters(...) && v is string`; TO-9 added.
2. D-1's adjacency-reset clause mapped to no obligation. → TO-1b added.
3. `lead:` "the concat fold is the only churn source" was unproven for 17 of 19 UID-only diffs; the probe can settle it. → SC-4 / TO-10 added (port E-1 onto the probe worktree, expect 0 changed `iterN` rows).

What the critic searched (and confirmed): `VisitSqlConcatExpression` overrides (U-1 holds; no caller needs a new node); `\.ValueType\s*=[^=]` setters across `Source/` (7, all build-time; sharing harmless, now in U-2); `SqlValue.cs` whole (`sealed`, state = `Value` + `ValueType`); `DbDataType.Equals` (`:109-117`, six facets); `QueryHelper.Evaluate.cs:75-91` (evaluation cached per `EvaluationContext`, so D-1's double evaluation is a dictionary hit); Transform/Modify return-same-instance path (`QueryElementVisitor.cs:3644-3674`); `git log -S EnsureFolded` (original to #5504 `de4d00002`); KB `SQL-PROVIDER`/`SQL-AST` issues and `dead-ends.md` (no prior concat-fold dead end). It verified the probe's `probe5911c/events.tsv` counts independently. It ran no build or test; TO-1 / TO-7 being red on master is by code reading until run.

Not re-dispatched: verdict was `weak`, not `refuted`, and the revisions add obligations without changing E-1 or D-1's mechanism.
