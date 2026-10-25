# Work plan: issue-6148-fix-ydb-left-join-outer-predicate — YDB: LEFT JOIN outer-only ON predicate moved to WHERE drops outer rows

**Tier:** L  ·  **Status:** approved  ·  **Approved-at:** 2026-10-25 (user, knowing round-2 narrowing un-re-attacked)  ·  **Branch:** issue/6148-fix-ydb-left-join-outer-predicate
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

## P1 Problem

[#6148](https://github.com/linq2db/linq2db/issues/6148). With `SqlProviderFlags.IsComplexJoinConditionSupported = false` (only YDB, `YdbDataProvider.cs:56`), `SelectQueryOptimizerVisitor.MoveJoinConditionsToWhere` (`SelectQueryOptimizerVisitor.cs:2903-2910`, `:2972-2977`) moves a LEFT JOIN ON predicate that does not depend on the joined subtree into the outer WHERE, filtering outer rows the LEFT JOIN must preserve. Other providers keep `LEFT JOIN t ON (x.Id = t.ParentID AND x.Kind = 'C1')`; YDB emits `LEFT JOIN t ON x.Id = t.ParentID WHERE x.Kind = 'C1'u`. The flag's XML doc (`SqlProviderFlags.cs:567-572`) describes the outer-only → WHERE move as intended.

Measured on master (worktree at `72d9e049c`, local `ydb` container): `JoinTests.LeftJoinOuterOnlyPredicate` returns 16 rows vs 17 expected; `LeftJoinOuterOnlyPredicateOnPrecedingJoin` 27 vs 29; both `YDB` and `YDB.LinqService`. SQLite.MS green on both.

## P2 Success criteria

- SC-1 A LEFT JOIN with an outer-only ON predicate on the outer main table returns every outer row on YDB, matching the in-memory result → TO-1
- SC-2 Same when the outer-only predicate sits beside a key on a preceding joined table → TO-2
- SC-3 The issue's TPH repro (derived-type association whose discriminator lands in ON) returns `[1, null]` on YDB → TO-3
- SC-4 A LEFT JOIN ON predicate that depends on neither join input (parameter only) no longer filters outer rows when false → TO-4
- SC-5 The rewritten key equality does not match NULL inner keys for outer rows that fail the folded predicate (nullable inner key, default `CompareNulls.LikeClr`) → TO-5
- SC-6 An outer-only conjunct whose value can be decided from parameters alone at execution (parameter inside AND/OR/CASE/function) is never folded, so it can never collapse the key into `inner IS NULL`; on YDB it stays in ON and the query is rejected instead of returning wrong rows → TO-6
- SC-6c An outer-only comparison against a nullable-typed parameter is not folded (a null value would make render-time `Reduce` decide it) → TO-6c
- SC-6b An outer-only comparison against a bare non-nullable parameter (`c.ChildID != id`) is folded and returns the in-memory result on both `YDB` and `YDB.LinqService` → TO-6b
- SC-7 Providers with the flag `true` emit unchanged SQL; INNER JOIN and mixed (both-input) predicate handling on YDB unchanged → TO-7
- SC-8 YDB-excluded LEFT JOIN tests that now pass are un-gated; the rest stay as they are → TO-8
- SC-9 A null-aware key (both sides nullable, `UnknownAsValue != null`) is never picked as the fold key; the query keeps its master outcome (YDB rejection), never silently dropping NULL/NULL matches → TO-9
- SC-10 A LEFT JOIN ON equality between the joined side and a parameter (`a1.Id = ids[0]`, `FSharpTests.Issue1813Test8`) is pushed into the joined derived table and runs on YDB → TO-10

## P3 Constraints & anti-goals (M/L)

- No public API change; `SqlProviderFlags` members and serialization (`DataMember Order = 63`) unchanged — doc text only.
- No SQL change for any provider with `IsComplexJoinConditionSupported = true` (`SelectQueryOptimizerVisitor.cs:283` is the sole reader).
- INNER JOIN relocation to WHERE stays as is (sound for INNER).
- Mixed predicates (both inputs) stay in ON, as today.
- No change to `SqlExpressionOptimizerVisitor` / `SqlPredicate.Reduce` (cross-cutting); the fix stays inside `MoveJoinConditionsToWhere`.
- User-visible delta (YDB only): LEFT JOIN queries with outer-only ON predicates return the outer rows they previously dropped; ON predicates with no outer dependency (parameter/constant only, or joined-side = parameter) move into a joined derived table instead of WHERE / instead of being rejected; an outer-only predicate with no usable plain equality key (incl. a null-aware both-nullable key, TO-9), or one that is not fold-safe (TO-6), stays in ON — YDB rejects the query instead of silently returning fewer rows.

## P4 Unknowns (M/L)

- U-1 Does YDB accept a `CASE` as an ON equality argument? — resolved-by probe: `CASE WHEN p.ParentID <> 2 THEN p.ParentID END = c.ParentID` fails `Error: ELSE is required` (measured); `SELECT COUNT(*) FROM Parent p LEFT JOIN Child c ON CASE WHEN p.ParentID <> 2 THEN p.ParentID ELSE NULL END = c.ParentID` runs and returns 17 = the TO-1 expected row count (measured, `JoinTests.YdbProbeCaseKeyInOn`, YDB direct).
- U-2 Will the builder emit `ELSE NULL` for a single-WHEN `SqlCaseExpression`? — resolved-by scout: `SqlExpressionOptimizerVisitor.VisitSqlCaseExpression` (`SqlExpressionOptimizerVisitor.cs:318-323`) rewrites a single-WHEN CASE to `SqlConditionExpression(cond, result, Else ?? SqlValue(null))`; `BasicSqlBuilder.BuildSqlConditionExpression` (`BasicSqlBuilder.cs:4040-4070`) always emits `ELSE <FalseValue>`. E-1 sets an explicit `SqlValue(type, null)` else regardless.
- U-3 Does `SelectQueryOptimizerVisitor` run before the YDB convert visitor? — resolved-by scout: `BasicSqlOptimizer.Finalize:64` → `SelectQueryOptimizerVisitor` (no convert in Finalize); convert runs at execution (`DataConnection.QueryRunner.cs:241-272`, `OptimizationContext.cs:130/140`).
- U-4 Null-aware expansion of the rewritten key — resolved-by scout: `SqlPredicate.ExprExpr.Reduce` (`SqlPredicate.cs:441-496`) expands Equal to `a = b OR a IS NULL AND b IS NULL` when `UnknownAsValue != null`, LikeClr and both sides nullable; the CASE side is always nullable (`SqlCaseExpression.CanBeNullable`); WHERE-originated predicates pulled into LEFT ON keep `UnknownAsValue = true` (`ExpressionBuildVisitor.cs:4913-4920`) while Join() keys are reset (`QueryHelper.CorrectComparisonForJoin`, `QueryHelper.cs:2004-2016`). Correction (critic round 1): a key whose `Reduce` at `SelectQueryOptimizerVisitor.cs:2903-2905` yields a `SqlSearchCondition` (null-aware, both sides nullable) is *not* moved — `:2910` sees it depends on the joined side, `:2915` rejects the push, so it stays in ON unreduced with `UnknownAsValue: true` and expands to OR at build (YDB rejects: `FSharpTests.cs:453-457`). So "stays in ON" ≠ "plain key"; the fold key must pass the `:2903-2905` test itself (D-1 picker), and only then is `UnknownAsValue: null` semantics-preserving (D-3).
- U-5 CASE collapse — resolved-by critic (reasoned, cited): `VisitSqlConditionExpression` (`SqlExpressionOptimizerVisitor.cs:164-167`) returns `FalseValue` when the condition evaluates false; `VisitExprExprPredicate` (`:1754-1762`) rewrites `NULL = x` to `x IS NULL` regardless of `UnknownAsValue`. Parameter values reach evaluation on the remote path (`RemoteDataContextBase.QueryRunner.cs:46,71-72`) and on the direct path once the statement is parameter-dependent (`DataConnection.QueryRunner.cs:233,245`; `BasicSqlOptimizer.cs:2215-2230` marks a statement parameter-dependent when a `SqlCase`/`SqlCondition` condition `CanBeEvaluated(true)`; `QueryHelper.Evaluate.cs:10-18,65-67,458-533` short-circuits search conditions). So any folded condition decidable from parameters alone can collapse → D-5 (fold-safe guard).
- U-8 Which outer-only shapes are decidable from parameters alone? — resolved-by critic rounds 1–2 (reasoned, cited; probed by TO-6/TO-6b/TO-6c): a predicate with no `SqlParameter` cannot change value per run; an `ExprExpr` with one bare **non-nullable** `SqlParameter`/`SqlValue` operand and a parameter-free outer-column operand cannot be decided, because `QueryHelper.Evaluate.cs:137-148` needs both sides and `SqlPredicate.ExprExpr.Reduce` short-cuts only on a null-valued operand (`SqlPredicate.cs:387,396-414,430-437`, run at render time via `BasicSqlBuilder.cs:3197-3203`; parameter values present once any nullable-typed parameter makes the statement parameter-dependent, `BasicSqlOptimizer.cs:2136`, and always on the remote runner). A nullable-typed parameter can be null → `col = @null` becomes `IsNull(col)` (folded to `False` for a non-nullable column, `SqlExpressionOptimizerVisitor.cs:1613-1618`) or `Expr(SqlValue(UnknownAsValue))` → collapse. Anything else carrying a parameter (search condition, CASE/condition expression, function such as `COALESCE(@p, x.A)`, `InList` over an empty parameter list) may evaluate → not fold-safe.
- U-6 Does the fold need to set `moved`? — resolved-by scout: the WHERE move at `:2972-2977` never sets `moved`; the loop at `SelectQueryOptimizerVisitor.cs:239-304` re-runs on `isModified`. The fold sets `moved = true` like the wrap paths; a CASE key reduces to a plain `ExprExpr` so a re-run keeps it.
- U-7 Which tests exclude/gate YDB on this shape? — resolved-by scout (`git grep` `AllYdb` inside `ActiveIssue|Throws*|DataSources` under `Tests/`, 176 hits triaged): strong `FSharpTests.Issue1813Test8` (`FSharpTests.cs:438`; joined-side = parameter — reasoned from source, measured by TO-10 pre-fix, `Tests/FSharp/Issue1813.fs:296` — never enters the LEFT branch on master because a `SqlParameter` is not a `SqlValue` at `:2905`, hence D-2's widening and TO-10); `DefaultIfEmptyTests.WithoutDefault`/`WithDefault` relabelled unrelated (critic: `Take(0).DefaultIfEmpty()` has no ON predicates, `:2882` skips it); medium `FSharpTests.Issue1813Test10` (`:457`), `AssociationTests.NullAssociation` (`AssociationTests.cs:500`), `Issue2832Tests.TestIssue2832` (`Issue2832Tests.cs:108`); low-medium `SelectTests.Coalesce4/5` (`SelectTests.cs:412/423`), `SubQueryTests.Test3` (`SubQueryTests.cs:49`).

## P5 Decisions (M/L; rejected alternatives mandatory at L)

### D-1 — outer-dependent, joined-independent LEFT ON predicate: fold into the outer key

- **chosen:** collect such predicates (D-5 fold-safe only); pick the first remaining ON predicate that passes the same key test as `:2903-2905` (`ExprExpr { Operator: Equal }`, `Reduce(nullability.WithJoinSource(...))` is still an `ExprExpr`, neither side a `SqlValue`) and whose one side has no joined-subtree dependency while the other has no outer dependency; replace its outer side with `CASE WHEN <AND of collected> THEN outerKey ELSE NULL END`. A failing outer row gets a NULL key and matches nothing, which is the LEFT JOIN meaning of a false ON conjunct.
- **rejected:** keep in ON unchanged — YDB rejects non-equality ON conjuncts (`JOIN ON expression must be a conjunction of equality predicates`), so the issue's association shape would throw instead of working.
- **rejected:** wrap the outer side into a derived table with a computed key column — the outer side may span the main table plus preceding joins (SC-2); wrapping it reshapes the FROM and every later join's column references.
- **rejected:** throw `LinqToDBException` — refuses a query YDB can run correctly.
- **why this:** local to the join, semantics-preserving, keeps ON a conjunction of equalities each side depending on one input.
- **failure mode of the choice:** the CASE side collapses to `NULL` when its condition evaluates false (U-5) → `inner IS NULL` match; a null-aware key expands to OR (U-4). D-5 keeps parameter-decidable conjuncts out of the CASE; the strict picker plus D-3 keep the key plain (TO-9 guards the null-aware key).

### D-2 — the LEFT branch classifies every conjunct by dependency, keys included

- **chosen:** for a LEFT join, every ON conjunct — plain equality keys included — is classified by `QueryHelper.IsDependsOnOuterSources(predicate, currentSources: sources)` and `QueryHelper.IsDependsOnSources(predicate, sources)`: no outer dependency → the existing push-into-wrapped-derived-table branch (`:2915-2968`), whether or not it touches the joined subtree (covers `c.Kind = 'X'` as today, `@p` / constants instead of WHERE, and `joined.Id = @p` instead of the YDB rejection); outer-only → D-1 / D-5; both → stays in ON. INNER keeps the current `move` gate. `LEFT JOIN t ON k AND P` with `P` independent of the outer row equals `LEFT JOIN (SELECT … FROM t WHERE P) ON k`.
- **rejected:** keep the `move` gate in front of the LEFT logic — leaves `joined.Id = @p` (Test8 shape) rejected by YDB.
- **rejected:** fold no-outer predicates into the CASE — evaluable from parameters alone, so a false value collapses the CASE (U-5).
- **rejected:** keep moving to WHERE — the bug (SC-4).
- **why this:** reuses shipped code; semantics-exact; never reaches the key.
- **failure mode of the choice:** an extra derived table in YDB SQL for parameter-only and joined-side-parameter predicates (baseline change); when every conjunct is pushed the ON is empty and `SqlQueryValidatorVisitor.cs:342-348` raises `Error_Join_Without_Condition` (`IsSupportsJoinWithoutCondition = false`) — same outcome as master, where the WHERE move empties it too; a joined source that is neither `SelectQuery` nor `SqlTable` cannot be wrapped (`:2919-2948`) and the predicate stays in ON.

### D-5 — fold only conjuncts that cannot be decided from parameters

- **chosen:** an outer-only conjunct is folded iff it has no `SqlParameter` (`QueryHelper.HasParameter`), or it is an `ExprExpr` whose one operand is a bare `SqlParameter` with a non-nullable CLR type (or a `SqlValue`) and whose other operand has no parameter (U-8). Any other outer-only conjunct stays in ON (D-4). The non-nullable clause is the critic round-2 narrowing: a null-valued parameter lets render-time `Reduce` turn the comparison into a constant.
- **rejected:** fold everything and rely on the CASE never being evaluated — refuted by U-5.
- **rejected:** a fold-proof ELSE (`CAST(NULL AS …)` / raw `NULL` SQL) — after a collapse YDB still rejects `NULL = col` (an equality argument must depend on exactly one input, `YdbDataProvider.cs:59-60`), and a cast of NULL is plausibly folded back to `SqlValue(null)`; unprobed, and buys only a different error.
- **rejected:** exclude every parameter-bearing conjunct — loses the common `x.Kind == @p` / `c.ChildID != id` shape, which is provably non-evaluable.
- **why this:** the admitted set is exactly the set whose value needs an outer column, so the CASE condition (an AND of them) can never evaluate to false.
- **failure mode of the choice:** a correct-but-rejected YDB query for outer-only predicates with nested parameter logic (TO-6) — loud, not wrong.

### D-3 — rewritten key uses `UnknownAsValue: null`

- **chosen:** build `new SqlPredicate.ExprExpr(caseExpr, Equal, innerKey, unknownAsValue: null)`, as `QueryHelper.CorrectComparisonForJoin` does for Join() keys.
- **rejected:** keep the original key's `UnknownAsValue` — expands to `… OR CASE … IS NULL AND inner IS NULL` (U-4), matching NULL inner keys for every failing outer row.
- **why this:** the D-1 picker admits only keys that `Reduce` to a plain equality under the join's nullability, i.e. NULL never matched them before the rewrite either (one side non-nullable, or `UnknownAsValue` already `null`).
- **failure mode of the choice:** none known; TO-5 is the control — on YDB the mutation reddens by rejection of the expanded OR, not by wrong rows (the fold runs only where the flag is false, so the semantic separation is not observable on any provider).

### D-4 — no usable key, or not fold-safe: keep the predicates in ON

- **chosen:** when no key passes the D-1 picker (incl. a null-aware both-nullable key), or a conjunct fails D-5, leave it in ON.
- **rejected:** WHERE (the bug); throw (YDB reports its own error).
- **why this:** a silent wrong result becomes a loud provider error.
- **failure mode of the choice:** a query that today returns (wrong) rows starts throwing on YDB — P3 user-visible delta.

## P6 Edit-points

- E-1 `Source/LinqToDB/Internal/SqlQuery/Visitors/SelectQueryOptimizerVisitor.cs:OptimizeJoinConditions.MoveJoinConditionsToWhere` — LEFT branch: D-2 classification of every conjunct, D-5 fold-safe test, D-1 strict picker + fold with D-3 key, D-4 fallback; INNER branch untouched.
- E-2 `Source/LinqToDB/Internal/SqlProvider/SqlProviderFlags.cs:IsComplexJoinConditionSupported` — XML doc describes the new LEFT JOIN handling.
- E-3 `Tests/Linq/Linq/JoinTests.cs` — TO-1, TO-2, TO-4, TO-5, TO-6, TO-6b, TO-9; the temporary `YdbProbeCaseKeyInOn` is removed before commit.
- E-4 `Tests/Linq/Linq/InheritanceTests.cs` — TO-3 (issue's TPH repro). A local TPH model is needed: the shared `Tests/Model/InheritanceParentChild.cs:56` association sits on the base type, not a derived one; `InheritanceTests.cs:678-836` already hosts local `CreateLocalTable` models.
- E-5 `Tests/Linq/Linq/FSharpTests.cs` (TO-10: drop `Issue1813Test8`'s YDB `ThrowsForProvider`), and conditionally `Tests/Linq/Linq/AssociationTests.cs`, `Tests/Linq/Linq/SelectTests.cs`, `Tests/Linq/Linq/SubQueryTests.cs` — drop a YDB exclusion / gate only where TO-8 shows it green.

## P7 Impact map (M/L)

- `SelectQueryOptimizerVisitor.cs:283` — sole reader of `IsComplexJoinConditionSupported` (search `IsComplexJoinConditionSupported` over `Source/`) — covered by E-1
- `YdbDataProvider.cs:56` — sole setter (same search) — out-of-scope
- `SqlProviderFlags.cs:582/838/922` — declaration, hash, equals (same search) — covered by E-2
- `SelectQueryOptimizerVisitor.cs:2611, 2691-2700` OptimizeJoinSubQueries — moves a flattened subquery WHERE into LEFT ON (search `Condition\.Predicates\.(Remove|Clear|Add)` over `Source/LinqToDB/Internal`) — out-of-scope: producer of the predicates E-1 consumes, LEFT-safe
- `JoinsOptimizer.RemoveDuplicates.cs:231-239` — leftover predicates on duplicate-join merge, LEFT guarded at 125-138/160-168/194-201 (same search) — out-of-scope: runs after (`BasicSqlOptimizer.cs:68`), only same-field equality pairs on LEFT
- `JoinsOptimizer.cs:135-142` — parent→child condition moves while un-nesting, never to WHERE (same search) — out-of-scope
- `Source/LinqToDB/Internal/DataProvider/Ydb/*` — no join-predicate moves (search `JoinType\.Left` in the Ydb folder: no hits) — out-of-scope
- `YdbSqlExpressionConvertVisitor.cs:448-455` ConvertSqlCaseExpression adds `ELSE NULL` (search `SqlCase|ELSE` in the Ydb folder) — out-of-scope: E-1 sets the else explicitly
- `SqlExpressionOptimizerVisitor.cs:164-167, 318-323, 1754-1762` — CASE collapse and `NULL = x` → `IS NULL` (scout search `OptimizeExpExprPredicate|SqlCaseExpression|SqlConditionExpression`) — deferred: unchanged per P3; bounded by D-2, probed by TO-6
- `SqlPredicate.cs:441-496` Reduce null-aware expansion (scout search `class ExprExpr|UnknownAsValue|ISqlPredicate Reduce\(`) — covered by E-1 (D-3)
- `YdbSqlBuilder.cs` — no CASE/condition/join rendering override (search `BuildSqlConditionExpression|BuildSqlCaseExpression|BuildPredicate|BuildJoinType|WrapJoinCondition`) — out-of-scope
- YDB-excluded LEFT JOIN tests (U-7 search) — covered by E-5 / TO-8 / TO-10; `Issue2832Tests.cs:108` (in-body subquery-count gate) — deferred: re-run in TO-7 sweep only
- `BasicSqlOptimizer.cs:2215-2230` IsParameterDependedElement — a `SqlCase`/`SqlCondition` whose condition `CanBeEvaluated(true)` flips the statement to parameter-dependent (critic search `IsParameterDependent =|IsParameterDependedElement(`) — covered by E-1 (post-fix guarantee: a folded CASE condition contains no parameter of nullable type and no parameter outside a bare comparison operand, so `CanBeEvaluated(true)` on it is false and the `:2215-2230` arm does not flip; `:2136` can still flip the statement for any nullable-typed parameter elsewhere, unrelated to the fold)
- `SqlQueryValidatorVisitor.cs:342-348` — `Error_Join_Without_Condition` for an emptied ON under `IsSupportsJoinWithoutCondition = false` (critic search `IsSupportsJoinWithoutCondition` across `Source/`) — out-of-scope: same outcome as master (D-2 failure mode)
- `UseMappingSchemaTests.DerivedAssociationFollowsHandleSchema` on open PR [#6145](https://github.com/linq2db/linq2db/pull/6145) — the issue's origin test, absent from this tree (critic: `gh pr view 6145` OPEN) — deferred: if #6145 lands with a YDB gate on it, un-gate it after this merges; TO-3 is the in-tree repro

## P8 Test obligations (M/L)

- TO-1 `JoinTests.LeftJoinOuterOnlyPredicate`: `Parent` LEFT `Child` ON `p.ParentID == c.ParentID && p.ParentID != 2`, `AssertQuery` — providers: all `[DataSources]` (red measured on YDB/YDB.LinqService, 16 vs 17) — proof: red→green
- TO-2 `JoinTests.LeftJoinOuterOnlyPredicateOnPrecedingJoin`: INNER `Child`, LEFT `GrandChild` ON `ch.ChildID == g.ChildID && p.ParentID != 2` — providers: all `[DataSources]` (red measured, 27 vs 29) — proof: red→green
- TO-3 `InheritanceTests` issue repro: TPH `Shape`/`Circle`/`Square`, `Circle.Parent` association, `CreateLocalTable` rows `(1,"C1"),(2,"S2")`, expected `[1, null]` from P1 — providers: all `[DataSources]` — proof: red→green
- TO-4 `JoinTests` LEFT `Child` ON `p.ParentID == c.ParentID && flag`, `[Values] bool flag`, `AssertQuery`; discriminating input `flag = false` (master moves `false` to WHERE → 0 rows) — providers: all `[DataSources]` — proof: red→green
- TO-5 `JoinTests.LeftJoinOuterOnlyPredicateNullableKey`: `Child` LEFT `Parent` via `Where(p => p.Value1 == c.ParentID && c.ChildID != 11).DefaultIfEmpty()` (WHERE-originated key, `UnknownAsValue = true`, outer side non-nullable) — providers: all `[DataSources]` — proof: control (mutation: keep the original `UnknownAsValue` in D-3 → red on YDB by rejection of the expanded OR; wrong-row separation unobservable, see D-3)
- TO-6 `JoinTests.LeftJoinOuterOnlyPredicateWithParameter`: TO-5 shape with ON `p.Value1 == c.ParentID && ((c.ChildID != 11 && flag) || (c.ChildID == 21 && flag))`, `[Values] bool flag` — providers: all `[DataSources]`, YDB family expected to throw `Ydb.Sdk.Ado.YdbException` — type-only assertion, since `flag = true` leaves a non-equality conjunct in ON while `flag = false` folds it to a constant ON, two different YQL messages (critic round 2) — proof: red→green (master measured pre-fix: 16/17 rows for `true`, 0/17 for `false` on both legs; after: loud rejection per D-5)
- TO-6c `JoinTests` nullable-parameter cells: TO-5 shape with ON `p.Value1 == c.ParentID && c.ChildID > minId` and, separately, `&& c.ChildID == id`, `[Values(null, 11)] int?` — providers: all `[DataSources]`, both `YDB` and `YDB.LinqService`; YDB expected to throw `Ydb.Sdk.Ado.YdbException` for every cell (nullable-typed parameter → not fold-safe → stays in ON), never wrong rows — proof: red→green (master moves it to WHERE)
- TO-6b `JoinTests` outer-only comparison against a captured int: TO-5 shape with ON `p.Value1 == c.ParentID && c.ChildID != id`, `[Values(11, 21)] int id` — providers: all `[DataSources]` incl. both `YDB` and `YDB.LinqService` — proof: red→green (master moves it to WHERE)
- TO-9 `JoinTests` null-aware key: `Parent` LEFT `GrandChild` via `Where(g => p.Value1 == g.ParentID && p.ParentID != 2).DefaultIfEmpty()` (both `int?`, `Tests/Model/ParentChild.cs:25,168`) — providers: all `[DataSources]`, YDB family `[ThrowsForProvider("Ydb.Sdk.Ado.YdbException", TestProvName.AllYdb)]` with the measured message — proof: characterization (master already rejects; guards the picker against silently dropping NULL/NULL matches)
- TO-10 `FSharpTests.Issue1813Test8` with its YDB `ThrowsForProvider` removed (`FSharpTests.cs:437-440`) — providers: its `[DataSources]` — proof: red→green (master: the declared `YdbException`; after: passes)
- TO-7 `JoinTests`, `AssociationTests`, `InheritanceTests` full fixtures plus `Issue2832Tests` before/after, with a baselines diff showing SQL changes for YDB only — providers: YDB, YDB.LinqService, SQLite.MS — proof: characterization (no new behaviour proven; CI full run covers the remaining providers)
- TO-8 each remaining U-7 candidate re-run on YDB with its YDB exclusion removed locally: `FSharpTests.Issue1813Test10`, `AssociationTests.NullAssociation`, `SelectTests.Coalesce4`, `SelectTests.Coalesce5`, `SubQueryTests.Test3` — providers: YDB, YDB.LinqService — proof: characterization; un-gate only the green ones (E-5)

## P9 Verification gates

- G-01: — (pending)
- G-02: — (pending)
- G-05: — (pending)
- G-06: — (pending)
- G-07: — (pending)
- G-08: — (pending)
- G-09: — (pending)

## P10 Adjudicated (M/L)

_None yet._

## P11 Amendments (M/L)

_None._

## P12 Critic verdict (M/L)

- Round 1 (plan-critic, fable): **refuted**. Objections: (1) D-3's premise false — a null-aware key stays in ON unreduced (`:2903-2915`), so the syntactic picker would silently drop NULL/NULL matches → strict picker in D-1, U-4 corrected, TO-9 added; (2) U-5 mis-cited `DataConnection.QueryRunner.cs:245`, and the CASE collapse fires via the remote runner and `IsParameterDependedElement` → D-5 fold-safe guard, TO-6 re-specified as a YDB rejection, TO-6b added on both legs; (3) D-2 did not reach the `move` gate, so `joined.Id = @p` (Test8) stayed rejected → D-2 classifies every LEFT conjunct, TO-10 added; (4) TO-5 reddens by rejection, not wrong rows → relabelled; (5) emptied ON → `Error_Join_Without_Condition`, `DefaultIfEmptyTests` unrelated → D-2 failure mode, U-7 relabelled; (6) P7 missed `BasicSqlOptimizer.cs:2215-2230`, `SqlQueryValidatorVisitor.cs:342-348`, #6145's origin test → added; (7) TO-3 local model justification → E-4. Critic searched: flag readers/setters, Ydb builder/optimizer, `IsSupportsJoinWithoutCondition`, `IsNestedJoinsSupported`, `new EvaluationContext(`, `IsParameterDependedElement(`, `CorrectComparisonForJoin`, `AllYdb` in `Tests/Linq` (8 candidates read, not all 176), `Tests/FSharp/Issue1813.fs:284-359`, `Tests/Model/ParentChild.cs`.
- Round 2 (same critic, on the revision): **refuted**, on one cell. (1) D-5 admitted nullable-typed bare parameters, which render-time `Reduce` can decide when the value is null (`SqlPredicate.cs:407-414,430-437`, `BasicSqlBuilder.cs:3197-3203`) → collapse → wrong rows with a nullable inner key → D-5 narrowed to non-nullable parameters, U-8 rewritten, TO-6c added. (2) TO-6 cannot pin one message across `flag` values → type-only assertion. (3) TO-10's parameter shape is reasoned → U-7 relabelled; TO-10 measures it. (4) P7 `:2215-2230` row overstated → rephrased to the post-fix guarantee. Critic's own summary: round-1 refutations closed; D-5 "correct in kind", the narrowing is "a one-clause narrowing". Critic searched: `reducePredicates: true` callers, `BuildJoinTable`/`BuildSearchCondition`, `VisitIsNullPredicate`, `OptimizeExpExprPredicate`, `HasParameter`/`HasQueryParameter`, validator call sites, `QueryHelper.Evaluate.cs` predicate arms, baselines clone for `Issue1813Test8` (none).
- Round-2 narrowing applied by the author and **not re-attacked** (skill cap: one revision round). Presented to the user with that status.
