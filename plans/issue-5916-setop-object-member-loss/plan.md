# Work plan: issue-5916-setop-object-member-loss — Keep projection members when a set-operation branch is cast to object

**Tier:** M  ·  **Status:** approved  ·  **Approved-at:** 2026-09-12  ·  **Branch:** issue/5916-setop-object-member-loss
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

Worktree: `C:\Worktrees\linq2db\5916-setop-object-member-loss`, base `origin/master` @ `dfd2f4415`. Issue [#5916](https://github.com/linq2db/linq2db/issues/5916), milestone 6.5.1.

## P1 Problem

A set operation whose operands are cast to `object` silently drops every projected member that would be
evaluated client-side. Measured on 6.5.0 / SQL Server 2016 (issue #5916); the two queries below differ only
by the cast.

```csharp
// A - correct
t.Select(p => new { id = "p_" + p.Id.ToString("N"), name = p.Name })
 .Concat(t.Select(p => new { id = "q_" + p.Id.ToString("N"), name = p.Name }))

// B - silently wrong
t.Select(p => (object)new { id = "p_" + p.Id.ToString("N"), name = p.Name })
 .Concat(t.Select(p => (object)new { id = "q_" + p.Id.ToString("N"), name = p.Name }))
```

A emits the four columns the projection reads and materializes the anonymous type:

```sql
SELECT CAST(N'p_' AS NVarChar(4000)), [p].[Id], CAST(N'N' AS NVarChar(4000)), [p].[Name] FROM [L2dbRepro] [p]
UNION ALL
SELECT CAST(N'q_' AS NVarChar(4000)), [p_1].[Id], CAST(N'N' AS NVarChar(4000)), [p_1].[Name] FROM [L2dbRepro] [p_1]
```

B emits one column and materializes each row as a bare `string`:

```sql
SELECT [p].[Name] FROM [L2dbRepro] [p] UNION ALL SELECT [p_1].[Name] FROM [L2dbRepro] [p_1]
```

No exception and no diagnostic. The row count is right, so nothing downstream notices.

Cause, read on this base: `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuildVisitor.cs:2426-2438`
replaces a `Convert(<constructor>, object)` with the constructor's single "straight" placeholder.
`CollectPlaceholdersStraight` (`:4455`) recurses only into `SqlGenericConstructorExpression` assignments and
parameters, `MemberInitExpression` bindings and `NewExpression` arguments, so a member holding a client-side
expression tree contributes zero placeholders even though it reads real columns — leaving exactly one, which
the collapse then treats as the whole object.

## P2 Success criteria

- SC-1 The `(object)`-cast form of the repro returns rows of the projected anonymous type with the same member values as the uncast form, on the same provider. → TO-1
- SC-2 The `(object)`-cast form emits the same column set as the uncast form (four columns, not one). → TO-2
- SC-3 The shapes that are correct on 6.5.0 stay correct — a translatable member, a three-member branch, and a terminal `Select` of the same projection. → TO-3
- SC-4 Full `Tests/Linq` shows no behaviour change outside the new tests, and every baseline that moves is explained. → TO-4

## P3 Constraints & anti-goals (M/L)

- No public API change. Nothing outside `LinqToDB.Internal.*` moves, so no `PublicAPI.Unshipped.txt` and no `CompatibilitySuppressions.xml` work is expected.
- No change to the set-operation merge machinery — `SetOperationBuilder.cs`, `MergeProjectionHelper.cs`. The defect is upstream of both; touching them needs a `P11` amendment.
- No new throw. The issue asks for the members to be kept; a refusal was the reporter's fallback preference, not their first.
- The other "one column stands in for the object" reductions stay untouched: `ContainsBuilder.cs:179`, `GroupByBuilder.cs:266-282`, `TableLikeQueryContext.cs:414-423`. They are deliberate and reach their conclusion by a different route (see `P7`).
- Target is the 6.5.1 patch milestone, so the change has to stay narrow enough that any baseline movement is explainable line by line.
- No unrelated reformatting; the file's column alignment is intentional.

## P4 Unknowns (M/L)

- U-1 The issue's case 6 (operand order swapped) is recorded as *correct* on 6.5.0, but the collapse is order-independent, so the mechanism predicts it fails in either order. — **resolved-by probe: the issue's matrix is wrong.** `ConcatObjectCastClientSideMemberOnSecondOperand` is **red** against the unfixed base on SQLite.MS and SQLite.MS.LinqService (run 2026-09-12). The failure output shows the three-member branch keeping all its columns while the two-member branch collapses to a bare string in the *same* query — which also confirms the straight-placeholder-count mechanism directly rather than by inference. Reported back on #5916 as a comment; no change to the fix.
- U-2 Does anything legitimately depend on the collapse outside a set projection? — resolved-by scout: `CollectPlaceholdersStraight` has exactly one call site in the repo (`ExpressionBuildVisitor.cs:2424`; verified independently by `Grep` over the worktree), and every other one-column-object reduction uses the deep `CollectPlaceholders` or reads the constructor directly, so none of them is reachable through this edit. Residual exposure is bounded by G-01.
- U-3 Does the pipeline downstream of the branch projection tolerate a `Convert(<SqlGenericConstructorExpression>, object)` where it currently receives a bare placeholder? — resolved-by scout: yes, and deliberately. `MergeProjectionHelper.cs:388` and `BuildProxyBase{TOwner}.cs:237` both reach through a conversion via `SequenceHelper.IsConstructorBranch`, the latter with a comment naming exactly this case; `BuildExtractExpression` runs under `BuildPurpose.Extract`, which `:2324` sends straight to `base.VisitUnary`; and materialization dispatches on the inner `SqlGenericConstructorExpression`, so the wrapper is re-applied by the default `Update`. One corner the scout could not settle by reading — whether the duplicate/variable hoisting at `ExpressionBuilder.QueryBuilder.cs:75-102` behaves identically for a wrapped node — is covered by TO-1's green run, which exercises the whole path.
- U-5 Is the collapse load-bearing for any test that wraps a *constructor* in a conversion today? — resolved-by scout: no test casts a constructed object to `object` at all, but several cast one to a base type, and three of them assert a column count. They are named as canaries in `P7`; G-01 is what decides.
- U-4 Does the edit reach purposes other than `Expression`? — resolved-by scout: yes. `:2324` admits `Traverse`, `Sql` and `Expression`, and `:2406` diverts only `Expression` without `ForSetProjection`, so the guarded code is reached by every `Convert` under `BuildPurpose.Sql` and `BuildPurpose.Traverse` as well. This widens the edit's reach beyond the reported defect and is the reason SC-4 exists.

## P5 Decisions (M/L; rejected alternatives mandatory at L)

### D-1 — Where to stop the collapse

- **chosen:** hoist the existing bail-out `node.Method == null && operandExpr is not SqlPlaceholderExpression` from `:2444` to the top of the `placeholders.Count == 1` block, so a constructed operand is never replaced by one of its member columns — in any purpose.
- **rejected:** add `&& !_buildFlags.HasFlag(BuildFlags.ForSetProjection)` to the collapse condition — smaller blast radius and near-zero baseline churn, but it leaves the identical silent member loss reachable under `BuildPurpose.Sql` and `BuildPurpose.Traverse`, which `P7` shows are the larger surface.
- **rejected:** keep the collapse and raise a `SqlErrorExpression` when it would discard members — restores the 6.4.0-style throw, which is safe but leaves the shape unsupported and gives the heterogeneous-`Concat` use case no server-side answer. The reporter ranked this second explicitly.
- **why this:** the condition is a proxy that leaks. `placeholders.Count == 1` was meant to identify "the operand *is* a single column"; a constructor holding one column satisfies it without being one. `:2444` already encodes the correct test and is only consulted on the other arm of the same `if`, so the fix restores an intent the file already carries rather than inventing a new rule.
- **failure mode of the choice:** a caller that today receives a collapsed placeholder will now receive `Convert(<constructor>, T)`, which is not SQL — so a silently-wrong value becomes a translation error. Better failure, still a behaviour change. Two things bound it, both established after the critic pass: the delta lives only inside the type-matching arm at `:2430-2434`, so a conversion to a base type that is neither `object` nor the operand's own type already exits at `:2444` and cannot move; and no test in the corpus enters the branch at all, so **G-01 cannot prove this safe** — it can only show nothing unrelated broke. If a caller does surface later, fall back to D-1's first rejected option and record the residual rather than weakening a test.

### D-2 — Leave the `node.Method != null` path alone

- **chosen:** the hoisted guard keeps its `node.Method == null` condition, so a conversion carrying a user-defined operator still collapses as today.
- **rejected:** dropping the condition to cover every conversion — wider than the defect and unmotivated: a user-defined conversion operator from an anonymous type is not a shape the issue exercises or that the codebase produces.
- **why this:** the guard is being *moved*, not rewritten. Changing its condition in the same edit would make the diff impossible to attribute if the suite reddens.
- **failure mode of the choice:** if a user-defined conversion over a constructed operand exists in the wild it stays broken. No such shape appears in `Tests/`; it would surface as a separate report.

## P6 Edit-points

- E-1 `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuildVisitor.cs:VisitUnary` — move the `node.Method == null && operandExpr is not SqlPlaceholderExpression` bail-out from below the type-matching `if` to above it, inside the `placeholders.Count == 1` block; add a two-to-three-line comment stating why the operand has to be the placeholder itself.
- E-2 `Tests/Linq/UserTests/Issue5916Tests.cs` — new file; the regression and control tests in `P8`.

## P7 Impact map (M/L)

- `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuildVisitor.cs:2424` — the only caller of `CollectPlaceholdersStraight` anywhere in the repo. Searched `CollectPlaceholdersStraight` across the worktree (scout, re-verified by `Grep`): two hits, the definition at `:4455` and this call. — covered by E-1
- `Source/LinqToDB/Internal/Linq/Builder/ContainsBuilder.cs:179` — `testPlaceholders.Count != 1` decides `InSubQuery` vs `EXISTS`, i.e. the same "object with one column is that column" assumption. Reached through `ExpressionBuilder.CollectPlaceholders` (the deep collector, `ExpressionBuilder.SqlBuilder.cs:541`), not the straight one. Searched `placeholders?.Count`, `CollectPlaceholders|CollectDistinctPlaceholders` across `Source/`. — out-of-scope
- `Source/LinqToDB/Internal/Linq/Builder/GroupByBuilder.cs:266-282` — same assumption for a single-member grouping key, also via the deep collector (`ExpressionBuildVisitor.cs:4440`). — out-of-scope
- `Source/LinqToDB/Internal/Linq/Builder/TableLikeQueryContext.cs:414-423` — reduces a merge-source projection to a scalar by requiring `generic.Assignments.Count == 1` and taking `Assignments[0]`; inspects the constructor directly, never collects placeholders. — out-of-scope
- `Source/LinqToDB/Internal/Linq/Builder/MergeProjectionHelper.cs:48-49` — the only shared site that sets `BuildFlags.ForSetProjection`, with three callers: `SetOperationBuilder.cs:615` and `:620` (the two set-operation branch projections) and `EnumerableContextDynamic.cs:200` (in-memory / `VALUES` sequence rows). Searched `ForSetProjection` and `BuildProjectionExpression` across `Source/`. All three reach E-1. — covered by E-1
- `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuilder.EagerLoadUnion.cs:203`, `:313`, `:471`, `:904` — the four other sites that set the flag, building eager-load CTE-union anchor and branch rows. They build a `ContextRefExpression` or a member access over one rather than a user projection, so a `Convert` over a constructor is not the shape they produce — but they are on the same code path and inherit the change. — covered by E-1
- `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuildVisitor.cs:2324` + `:2406` + `:2430-2434` — the purpose gate and the type-matching condition together bound the real delta, which is **narrower than the first draft claimed**. `Traverse`, `Sql` and `Expression` all pass `:2324`, and only `Expression` without the flag is diverted at `:2406` — but the behaviour E-1 changes lies inside the type-matching arm, which requires `node.Type == typeof(object)`, an identity conversion, a match against the single column's `SystemType`, or an enum pair. A conversion to any other base type already exits at `:2444` today and is untouched. Under `Traverse` the critic reads `:1502` as returning member nodes untranslated, so `IsSqlReady` (`SequenceHelper.cs:980`, rejects any `ContextRefExpression`) fails and the block is unreachable for a user operand — read-derived on both sides, not measured. Searched `_buildPurpose is` within `VisitUnary`. — covered by E-1
- Test corpus coverage of the changed branch — **nil**. Searched `\(object\??\)\s*new\b`, `\(object\??\)\s*\(\s*new\b` and `\bas object\b` across `Tests/**/*.cs` (scout and critic independently): no matches; all 38 `(object)` occurrences in `Tests/Linq` are member casts, constants or harness code. Consequence for `P9`: a green G-01 establishes that nothing unrelated broke, **not** that the `Sql`/`Traverse` reach is safe, because nothing in the corpus enters the branch under those purposes. — deferred: unexercised by corpus; the residual is carried in `P10` and bounded by `D-1`'s fallback
- `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuildVisitor.cs:249-254` (`CombineFlags`) — combining is an OR unless `ResetPrevious` is passed, so `ForSetProjection` survives into nested builds (`TranslationContext.Translate` at `:5423`, `LambdaResolveVisitor.cs:43`/`:67`). Independently corroborated by the measurement recorded for #5818. Consequence: the guarded block is reached from deeper frames than the set sites themselves. — covered by E-1
- `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuildVisitor.cs:910`, `:958` — under `Sql` or `ForSetProjection`, `New` / `MemberInit` are parsed into `SqlGenericConstructorExpression`. This is what makes the operand at `:2411` a constructor node rather than a raw `NewExpression`, i.e. why `CollectPlaceholdersStraight` sees assignments at all. Searched `ParseGenericConstructor` across `Source/`. No edit needed — it is the precondition E-1 relies on, not a site that moves. — out-of-scope
- `Tests/Linq/UserTests/Issue5683Tests.cs:110`, `:148`, `:169` — **canaries.** The closest existing shape: a set-operation branch projecting `(Projection)new DerivedProjection { … }`. `Projection` carries two columns, so `placeholders.Count == 2` and the collapse never fires — these should not move. All three hard-assert `Select.Columns.Count == 3`, which makes them the cheapest detector if E-1 changes branch keying after all. Searched `\(object\??\)\s*new` and `(select|=>)\s*\(\s*[A-Z]\w*\??\s*\)\s*new\s` across `Tests/`. No E-n touches them; G-01 is what reports movement. — out-of-scope
- `Tests/Linq/UserTests/Issue1225Tests.cs:58`, `:72` and `Tests/Linq/Microsoft/MicrosoftODataTests.cs:192`, `:234` — proposed as canaries in the first draft and **refuted by the critic**, which is why the row survives rather than being deleted. `Issue1225Tests.cs:48` types `GroupByContainer` as `LastInChain` and `:84` constructs `LastInChain`, so no conversion over a constructor exists there at all — the only `Convert` boxes the `Value = it.Id` *member*. Verified directly by reading `:42-59`. `MicrosoftODataTests` is a base-class upcast, and a `Convert(ctor, Base)` where `Base` is neither `object` nor the operand's own type cannot satisfy the type-matching condition at `ExpressionBuildVisitor.cs:2430-2434`, so it already exits at `:2444` and E-1 cannot change it. Neither is a detector. — out-of-scope
- `Tests/Linq/Linq/SetOperatorComplexTests.cs:205`, `:228`, `:251`, `:275` and `Tests/Linq/Linq/ConcatUnionTests.cs:2154`, `:2179` — inheritance set operations over real entities (`Book`/`Roman`/`Novel`, `SetEntityBase`/`A`/`B`/`C`), with per-row `ShouldBeOfType` assertions. Multi-column entities, so no collapse expected; listed because they are the nearest behavioural neighbours of the pairing the fix restores. Searched `(Concat|Union|UnionAll|Except|Intersect)` against inheritance hierarchies across `Tests/Linq`. No E-n touches them. — out-of-scope
- `Tests/Linq/Linq/CteTests.cs:1052` (`Issue5457`) and `Tests/Linq/DataProvider/Types/TypeTestsBase.cs:292-296` — the `typeof(object)` arm's *current* population: a `Convert` to `object` over a **member**, not a constructor. `operandExpr` there is the placeholder itself, so E-1's guard passes them through unchanged. This is the set the fix must not disturb, and TO-5 pins it. — covered by E-1
- Provider SQL builders / optimizers — Localized — searched `CollectPlaceholdersStraight` and `ForSetProjection` across `Source/`, no hit outside `Internal/Linq/Builder`; the edit is in expression-tree building, runs before any `ISqlBuilder`, and emits no new AST node kind, so no sibling `*SqlBuilder` / `*SqlOptimizer` / `*MemberTranslator` mirrors it and no emitted-SQL change originates provider-side.
- `LinqService` / serialized contracts — Localized — searched `CollectPlaceholdersStraight` and `ForSetProjection` across `Source/`, neither appears in a remote contract, a `[DataMember]` shape or a serialized enum, so no wire shape changes.

## P8 Test obligations (M/L)

All in `Tests/Linq/UserTests/Issue5916Tests.cs`, `[DataSources]`, modelled on
`Tests/Linq/UserTests/Issue5683Tests.cs` and the set-operation region of `Tests/Linq/Linq/StringConcatTests.cs:860-930`.

**Instrumentation, and why it is not the obvious one.** A bare `AssertQuery(query)` on an `IQueryable<object>`
**cannot go red for this defect.** `TestBase.AssertQuery.cs:467` defaults the comparer to
`ComparerBuilder.GetEqualityComparer<T>()`, which for `T = object` walks
`TypeAccessor.GetAccessor<object>().Members` — empty (`ComparerBuilder.cs:34`) — and
`CreateEqualsFunc` folds the empty set with `.DefaultIfEmpty(ExpressionInstances.True)`
(`ComparerBuilder.cs:201-203`), yielding an always-true equality; only the row **count** is then compared, and
`P1` says the count is already right on the unfixed base. Verified by reading all three sites. So every
`red→green` obligation below passes an explicit comparer — `AssertQuery(query, EqualityComparer<object>.Default)`
— which for anonymous types is structural equality, unequal against a `string` pre-fix and equal post-fix. Each
also carries a direct runtime-type assertion, so the test states the defect rather than inferring it.

- TO-1 The minimal repro — same anonymous shape both operands, one client-side member, both cast to `object`. Asserts, with the explicit comparer, that every row is the projected anonymous type and that both members carry the expected values. — proof: red→green
- TO-2 The same query's column count, asserted as `query.GetSelectQuery()!.Select.Columns.Count.ShouldBe(n)` — the repo's idiom for this, used at `Issue5683Tests.cs:130`. `n` is to be **measured on the green run and then written into the test**, not predicted here: whether the differing `"p_"`/`"q_"` constants serve as the branch discriminator or an extra `__projection__set_id__` anchor column is added is exactly what the run answers. The pre-fix value is expected to be 1 and must be recorded from the red run. — proof: red→green
- TO-3 Controls that must be green **both** before and after. (a) a fully translatable projection — two plain columns, no client-side member. Deliberately **not** `Guid.ToString()`: `GuidMemberTranslatorBase.cs:35-38` returns `null` in the base, so on a provider with no override the member is client-side, the straight count is 1, and the shape is *not* correct on 6.5.0 there — a red would be the defect, not a control failure. (b) a three-member branch with one client-side member (straight count 2). (c) a terminal `Select` of the repro's projection, no set operation. — proof: control
- TO-4 Variants pinning that the defect is not specific to `Concat`, to `Guid`, or to matching shapes: `UnionAll` in place of `Concat`; `p.Name.Length.ToString("X")` as the client-side member; two operands of two members with different names; and the `new { … } as object` spelling, which `ExpressionBuilder.SqlBuilder.cs:1801-1818` rewrites through `EnsureType` into the same `Convert` and therefore reaches the same site. Same instrumentation as TO-1. — proof: red→green
- TO-5 Symmetry guard on the unchanged path: a `(object)` cast over a bare column — `Select(p => (object)p.Name)` — inside the same set operation. Here `operandExpr` **is** the placeholder, so E-1's guard passes it through and it must still collapse to that column. This is the shape the surviving collapse exists for, and the only in-corpus population of the `typeof(object)` arm (`CteTests.cs:1052`, `TypeTestsBase.cs:292-296`) has it. — proof: control
- TO-6 The issue's case 6 — operand order swapped — run against the unfixed base to settle `U-1`. Whichever way it falls, it is green after the fix; the result is reported back on #5916 rather than changing the fix. — proof: characterization

## P9 Verification gates

- G-01 Tests pass via `/test`, declared proof mode observed: **pass (locally partial)** — the fixture's red→green was observed, not assumed: 14 failed / 9 passed against the unfixed base, 23/23 passed with `E-1`, on SQLite.MS + SQLite.MS.LinqService. Every control was green in **both** arms, so the reds are attributable. Neighbours from `P7`: 917/917. The `Tests.Linq.` namespace reached 6982 completed / 0 failed before the host killed it for memory. **The full suite did not complete locally** — three runs were killed with 2.8-5.7 GB free on a shared box; `Tests.UserTests` and the tail namespaces are covered only by the 917-test neighbour run. Completion belongs to CI (`/azp run test-all`), and this gate is not a clean local full-suite pass
- G-02 Baselines reviewed, not just regenerated: **pass** — of 3881 pre-existing SQLite.MS baselines, 3877 unchanged and 4 moved (`AggregationTests.MinMaxOverBooleanExpression`, `…Grouped`, `GroupByTests.Max11`, `Max12`). Causation probed rather than argued: the fix was stashed, rebuilt, and those four re-run — all four produced the **post** hashes with the fix absent, so the movement is pre-existing drift between the local tree and master (consistent with tip commit `dfd2f4415` / #5909, which folds single-predicate search conditions and is exactly what `MAX(CASE WHEN … THEN 1 ELSE 0 END)` is). **Zero baselines move because of this change.** The 3145 additions are first-time captures, not movement
- G-05 Builds on the portable TFMs: **pass** — `dotnet build Source/LinqToDB/LinqToDB.csproj -c Release -f netstandard2.0 -m:1` → `Build succeeded`, zero warnings. Release config, so the Release-only analyzers ran clean too. No BCL API was added, so this was expected; run because the edit is in core rather than skipped on that expectation
- G-06 No unrelated reformatting / renames: **pass** — `git diff --stat` is one file, 8 insertions / 5 deletions: the guard moved verbatim plus a three-line comment. No alignment or whitespace touched
- G-07 No playground scratch staged: **pass** — nothing under `Tests/Tests.Playground/` was touched; the only untracked file is the new fixture. The worktree-local `UserDataProviders.json` seeded so `BaselinesPath` would resolve is gitignored (`.gitignore:17`) and cannot be staged
- G-08 Cross-cutting core change surfaced, proven by test: **pass** — added by hand; `-Action gates` marks it inapplicable because `ExpressionBuildVisitor.cs` is not under `SqlQuery/**` or `Translation/**`, but it is shared engine code every query passes through and `P7`'s widest row is exactly a cross-cutting reach. Surfaced to the user before implementation — the widened `Sql`/`Traverse` reach was put in front of them as the deciding trade-off of `D-1`, and they chose it over the narrower option. Rests on TO-1's observed red→green and the measured baseline-neutrality probe, not on reading. Cross-model: the design was attacked by `plan-critic` on `fable` and the diff by `code-reviewer` on `fable`, neither of which authored the change
- G-09 Diff got an adversarial read before the PR opened: **pass** — `code-reviewer` on `fable` over the working-tree diff. **No correctness findings.** Both primary leads returned `checked-clean` with evidence: the `node.Method != null` path is provably indistinguishable before and after (the old guard was `Method == null`-gated too, so the two orderings agree on it), and the new fixture's instrumentation does detect the negative (`TestBase.Asserts.cs:83-118` runs a two-way `Except` with the supplied comparer, so a `string` row is unequal to every expected anonymous instance). Flake sweep clean: `ConvertMemberTranslatorDefault.ProcessToString:432-435` refuses a formatted `ToString` before any provider override, so the client-side member is client-side on every provider; `AreEqual` is unordered, so `Concat` row order cannot flake. Two NITs, both taken — see `P11`

## P10 Adjudicated (M/L)

- The `node.Method != null` conversion over a constructed operand keeps collapsing — see `D-2`. Not a finding on this branch.
- `ContainsBuilder`, `GroupByBuilder` and `TableLikeQueryContext` carry the same one-column-object assumption and are deliberately left alone — see `P3` and `P7`. Whether any of them is also wrong is a separate question, not this branch's.
- The issue's case 6 may turn out to be mis-recorded (`U-1`). Correcting the issue's matrix is a comment on #5916, not a change to the fix.
- **G-01 cannot establish that the `BuildPurpose.Sql` / `Traverse` reach is safe**, because no test in the corpus enters the changed branch under any purpose (measured: no `(object)new`, `(object)(new`, or `as object` anywhere in `Tests/`). Accepted rather than closed: the delta is confined to the type-matching arm, `Traverse` looks unreachable for a user operand as read, and `D-1` carries an explicit fallback. A reviewer noting "the suite does not cover this" is correct and is not a new finding.
  - **Narrowed after the G-09 pass** (read-derived, not run): the `Sql`-purpose consumers largely cannot reach the arm either. `JoinBuilder.cs:126-127` and `OrderByBuilder.cs:102` call `.Unwrap()` on the key body first, and `InternalExtensions.Unwrap()` (`:41-46`) strips every `Convert`/`ConvertChecked` — so `o => (object)new { o.ID }` as a key never arrives. `GroupByBuilder:266`, `DistinctByBuilder:131`, `DistinctBuilder:70`, `ContainsBuilder:146`/`:172`, `HasUniqueKey:28`, `DefaultIfEmptyBuilder:22` and the four eager-load union sites all consume through the deep `CollectPlaceholders` / `CollectDistinctPlaceholders`, which see through a kept `Convert`. The residual is `ConvertCompareExpression` (`:4173-4231`), where a two-member `Convert(ctor, object)` on both sides already fails on master — so the one-member case working was an artifact of the collapse, not a contract. State the reach this way in the PR body rather than as "unverified".
- TO-2's expected column count is measured on the green run, not predicted in advance. A reviewer asking why the plan does not state the number should read this entry: predicting it would have made the assertion agree with whatever the run produced.

## P11 Amendments (M/L)

- A-1 (2026-09-12, post-G-09) — two `[Test(Description=…)]` strings in `Tests/Linq/UserTests/Issue5916Tests.cs` corrected. Both were written from the issue's matrix before the red run measured otherwise, so both contradicted this branch's own evidence: `ConcatObjectCastClientSideMemberOnSecondOperand` was labelled a *control* when it is one of the seven red→green regressions (`U-1`), and `ConcatObjectCastStringLengthClientSideMember` was labelled "not specific to a formatted **Guid**" when no test in the fixture uses a `Guid` at all — `Person` has no `Guid` column, so the repro stands in `p.ID.ToString("X")`. Wording only, inside an `E-2` file; no `P6` row changes and no approval is voided.

## P12 Critic verdict (M/L)

**weak** — `plan-critic` on `fable` (different family from the author, per `.claude/plans/config.json`;
`criticTiming: before`). It did not challenge `E-1` or the mechanism; it attacked the *evidence apparatus*,
and three of its five objections were correct and load-bearing. Objections, kept visible:

1. **`AssertQuery` on an `IQueryable<object>` cannot go red.** The default comparer degenerates to
   always-true for `object`, leaving only the row count — which is already correct pre-fix. **Accepted.**
   Independently verified by reading `TestBase.AssertQuery.cs:467`, `ComparerBuilder.cs:34` and `:201-203`.
   `P8` rewritten: every `red→green` obligation now passes `EqualityComparer<object>.Default` and carries a
   runtime-type assertion. This is the objection that justified the pass — as written, TO-1 and all of TO-4
   would have been green against the unfixed base.
2. **`Guid.ToString()` is not a provider-independent control.** `GuidMemberTranslatorBase.cs:35-38` returns
   `null` in the base, so on a provider without an override the member is client-side and the shape is *not*
   correct on 6.5.0 there — a red would have been misread as the `U-1` answer. **Accepted**; TO-3(a) now uses
   two plain columns.
3. **Two of the `P7` canaries cannot enter the changed branch.** `Issue1225Tests` types the member as the
   same type it constructs (verified by reading `:42-59`), and `MicrosoftODataTests`' base-class upcast fails
   the type-matching condition at `:2430-2434`. **Accepted**; the row now records the refutation instead of
   claiming detectors that do not exist.
4. **`verified by G-01` on the widest `P7` row was inferred from something that will not happen** — nothing
   in `Tests/` enters the branch, so a green suite proves absence of collateral damage, not safety of the
   reach; and `Traverse` looks unreachable for a user operand (`:1502` + `IsSqlReady`). **Accepted**; the row
   is relabelled and the residual is adjudicated in `P10`.
5. **TO-2 had no failable form** ("read off the run … recorded in the PR body"). **Accepted**; it is now a
   `Select.Columns.Count` assertion in the repo's own idiom.

Also taken, unprompted: `new { … } as object` reaches the same site via the `EnsureType` rewrite at
`ExpressionBuilder.SqlBuilder.cs:1801-1818`, added as a TO-4 variant.

Nothing was rejected. The critic's own summary of what survives — `SelectContext.cs:156` hands the `Convert`
body to `VisitUnary` intact, `IsSqlReady` accepts the constructor, `CollectPlaceholdersStraight` does not
recurse into the client-side member, and `:2430-2438` then produces exactly the reporter's one-column SQL —
is the mechanism `P1` states, re-derived independently.

Not re-dispatched: `weak` is carried forward with objections visible, and the revisions are confined to the
test apparatus and the impact map, not to `E-1`.
