# Work plan: issue-5865-validate-limited-derived-join — route the element form to the keyed strategy, and reject the shape nothing can express

**Tier:** L  ·  **Status:** implementing  ·  **Approved-at:** —  ·  **Branch:** issue/5865-validate-limited-derived-join
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

Closes [#5865](https://github.com/linq2db/linq2db/issues/5865). Tier **L**: one edit is in
`Source/LinqToDB/Internal/SqlQuery/Visitors/` — a `paths:` match for `.claude/rules/cross-cutting-core.md`.

## P1 Problem

Sybase ASE applies a derived table's `TOP` to the **whole joined result** rather than to the derived
table. linq2db models this as `SqlProviderFlags.IsJoinDerivedTableWithTakeInvalid`
(`Internal/SqlProvider/SqlProviderFlags.cs:87`, set only by `SybaseDataProvider.cs:56`), and
`SqlQueryValidatorVisitor.VisitSqlJoinedTable` (`:355`) rejects it — but the condition reads
`element.Table.Source`, i.e. only the **joined** side. A limited derived table in the `FROM` clause
was examined by nothing.

Measured at the database level, raw SQL through `AdoNetCore.AseClient` against the `sybase`
container (`.build/.agents/issue5865-raw.txt`; two parents, three children, parent 2 has two):

| # | shape | rows | correct |
|---|---|---|---|
| A | `FROM (SELECT TOP 1 …) m INNER JOIN CH c ON m.Id = c.ParentId` | **1** | 2 |
| B | control — same shape, `TOP` removed | 2 | 2 |
| C | `FROM PR p INNER JOIN (SELECT TOP 1 …) m ON …` (the shape already rejected) | 1 | 1 |
| D | `FROM (SELECT TOP 1 …) m` — no join | 1 | 1 |
| E | `FROM (SELECT TOP 1 …) m, CH c WHERE m.Id = c.ParentId` (comma join) | **1** | 2 |
| F | `WHERE c.ParentId IN (SELECT TOP 1 …)` | — | `AseException: Incorrect syntax near the keyword 'TOP'` |
| G | A, with the derived table wrapped in one more plain `SELECT` | **1** | 2 |

B fixes the expected value empirically. D shows the defect needs a second source; E shows a comma
join triggers it too; F and G show ASE offers no rewrite that both limits the parent and joins to
details — **except** the one measured below.

The user-visible consequence is the element form of eager loading.
`db.Parent.Where(p => p.ParentID == id).LoadWith(p => p.Children).First()` builds its detail preamble
in `ProcessEagerLoadingExpression` (`Internal/Linq/Builder/ExpressionBuilder.EagerLoadDefault.cs:98-133`)
as `parent.SelectDistinct().SelectMany(p => p.Children, (m, d) => new KeyDetailEnvelope(key, d))`,
and the cloned parent still carries `First()`'s `TOP 1` — exactly shape **A**. Reproduced locally on
`Sybase.Managed` (`.build/.agents/issue5865-plain.txt`): `Children = 1` where SQLite returns 2. The
**non-compiled** form reproduces too, which #5865 lists as *not verified*.

Two corrections to #5865's own account, both traced in source:

1. *"the preamble is not run through the validator"* is **wrong**. `BuildPreambleQueryAttached`
   (`ExpressionBuilder.EagerLoad.cs:369`) → `BuildQuery` → `SqlProviderHelper.IsValidQuery`
   (`ExpressionBuilder.cs:297`). The preamble is validated; the *rule* did not describe the shape.
2. The exception a user actually sees comes from earlier still. `Query{T}.cs:222` sets
   `validateSubqueries = IsApplyJoinSupported`, false on Sybase, so pass 1 replaces every eager load
   with an error and pass 2 re-runs with validation on; there `SelectManyBuilder.cs:146` →
   `IsSupportedSubquery` → the build-time simulation at `ExpressionBuilder.SqlBuilder.cs:207-225`
   refuses, and `BuildSequence` throws from inside `ProcessEagerLoadingExpression`.

### Why the queryable form survives, and what that measurement bought

`LoadWith(…).Take(1).ToList()` returns the correct rows on Sybase. Traced SQL
(`.build/.agents/issue5865-sql.txt`) shows why: it emits
`FROM (SELECT DISTINCT [t1].[ParentID] FROM (SELECT TOP 1 …) [t1]) [m_1] INNER JOIN [Child]` — two
levels, the join source unlimited. `First()` collapses to one level because `QueryHelper.IsLimitedToOneRecord`
recurses through a single derived source (`QueryHelper.cs:2284`) and matches `TakeValue: SqlValue { Value: 1 }`,
so `OptimizeDistinct` (`SelectQueryOptimizerVisitor.cs:1422`) drops the DISTINCT as redundant and
`MoveSubQueryUp` merges what is left. This is what makes `D-2`'s depth-1 predicate a decision rather
than an accident, and it is pinned by `TO-5`.

## P2 Success criteria

- **SC-1** The element form of eager loading returns the **full** detail collection on a provider with
  `IsJoinDerivedTableWithTakeInvalid` — compiled, non-compiled, sync, async, direct and remote. → TO-1, TO-2
- **SC-2** The queryable form (`Take(1).ToList()`), which is correct today, stays correct. → TO-3
- **SC-3** A query whose `FROM` clause holds a limited derived table **and** a second source (a join on
  that table source, or a sibling table) is rejected with
  `ErrorHelper.Sybase.Error_JoinToDerivedTableWithTakeInvalid` instead of returning short results. → TO-4
- **SC-4** No behaviour change on any provider that leaves the flag `false`. → TO-6
- **SC-5** The Sybase suite shows no failure that is not either pre-existing at the branch point or a
  test converted to `[ThrowsForProvider]` here. → TO-7

### Reconciliation against #5865's stated scope

#5865 asked for two things: the shape **rejected**, and *"a different strategy is selected"*. Both are
delivered — the second by `D-1`, which is what the first draft of this plan wrongly recorded as
impossible. No narrowing to disclose.

## P3 Constraints & anti-goals (M/L)

1. Public API outside `LinqToDB.Internal.*` unchanged; no signature changes, so no
   `PublicAPI.Unshipped.txt` entry and no `CompatibilitySuppressions.xml` refresh.
2. Generated SQL for providers that leave the flag `false` must not change — every edit is inside that
   flag's own `if`.
3. Anti-goal: **do not special-case general optimizer simplifications for one provider.** See `D-3`.
4. Do not weaken or delete the existing `VisitSqlJoinedTable` rule; 17 `[ThrowsForProvider]` sites rest on it.
5. No `[ActiveIssue]` gates and no provider exclusions as a remedy — a declared refusal is the house pattern.

## P4 Unknowns (M/L)

- **U-1** Does Sybase mis-handle a **FROM**-side limited derived table? — resolved-by probe: **yes**, arm A vs control B.
- **U-2** Does it need a `JOIN`, or any second source? — resolved-by probe: **any**; arm E (comma FROM) is equally wrong, arm D is correct.
- **U-3** Is a multi-table `FROM` reachable from real LINQ? — resolved-by **instrumentation**, not reasoning: a logging build over the whole Sybase suite recorded the rule firing 127× with one table and one join, 4× with one table and two joins, and **8× with `Tables.Count == 2` and no joins**. The comma-FROM arm is live, not defensive code.
- **U-4** Is the preamble validated today? — resolved-by source trace: **yes**; see `P1`. Refutes #5865's stated cause.
- **U-5** Does `KeyedQuery` work on Sybase? — resolved-by probe (`.build/.agents/issue5865-keyed.txt`): **yes**. `WithKeyedLoadStrategy()` *and* `WithUnionLoadStrategy()` both return the correct `Children = 2` for the element form. The 37 blanket `TestProvName.AllSybase` exclusions in `EagerLoadingStrategyKeyedQueryTests` sit next to `AllAccess` with no comment and had never been measured. This is the finding the whole design turns on, and it came from a critic objection (`P12` O-3).
- **U-6** Is `ResolveStrategy`'s condition too narrow — does some element-form shape miss the remap? — resolved-by probe: **no**. `IsLimited` logs identically (`True, False, True, False`) for a shape that is fixed and one that still fails, so it is not what separates them.
- **U-7** Then why does `Issue4596Test` still fail? — resolved-by probe on the fallback chain: `declined KeyedQuery reason=ComplexParentReference`, exactly twice (its two contexts). The remap fires, `KeyedQuery` declines at its documented limit, the chain falls back to `Default`, and the validator refuses. Designed behaviour, not a gap.
- **U-8** Cover `SkipValue` too? — resolved-by review: **yes, via `IsLimited`**. `SelectQueryExtensions.IsLimited` (`:56`) is `TakeValue is not null or SkipValue is not null`, it is the codebase's own name for this concept, it is already used in this very file (`SqlQueryValidatorVisitor.cs:206`), and it matches the error message's own wording — *"JOIN to limited recordset"*. (Raised by the user; the first draft hand-rolled `Select.TakeValue != null` at both sites.)
- **U-9** Does the new `FROM`-side check pre-empt another rule's message? — resolved-by measurement: **it did**. `DoubleOrderBy` reported the Sybase TOP message instead of `Error_OrderBy_in_Derived`. Fixed by `D-4`.

## P5 Decisions (M/L)

### D-1 — Remap `Default → KeyedQuery` in `ResolveStrategy` when the query is limited

- **chosen:** three lines in `ExpressionBuilder.ResolveStrategy`, beside the existing
  `CteUnion → KeyedQuery` remap: if the strategy is `Default`, the provider sets the flag, and
  `buildContext.SelectQuery.IsLimited`, use `KeyedQuery`. It carries parent keys instead of joining, so
  the offending shape is never built.
- **rejected: set `SelectQuery.DoNotRemove` on the cloned parent from the eager-load builder.** Implemented
  and then withdrawn on the user's steer — *"просто не давай схлопувати підзапити в потрібному місці"*. It
  pokes one AST node from the builder to steer an optimizer decision made elsewhere.
- **rejected: guard the merge in `SelectQueryOptimizerVisitor.IsMovingUpValid`.** Implemented and
  **measured insufficient**: instrumentation showed the guard firing (twice) and the shape reappearing
  anyway, because `OptimizeDistinct` then strips the DISTINCT off the surviving wrapper — `IsLimitedToOneRecord`
  recurses into the limited inner query — after which the wrapper is trivial and is inlined on a later pass.
  Holding the shape would take a second guard inside `OptimizeDistinct`, i.e. two general simplifications
  specialised for one provider (`P3` anti-goal 3).
- **rejected: emit a different SQL shape for Sybase.** Probes F and G refute both rewrites.
- **why this:** it is what #5865 asked for, it lives where strategy remapping already lives, it needs no
  optimizer surgery, and `KeyedQuery` is measured working on Sybase (`U-5`).
- **failure mode of the choice:** when `KeyedQuery` itself declines (`ComplexParentReference`), the chain
  falls back to `Default` and the query is refused rather than silently wrong. Observed once in the suite
  (`Issue4596Test`, `U-7`). Also: every Sybase `LoadWith` + `Take`/`First` now takes `KeyedQuery`, whose
  Sybase coverage is currently zero — see `P10`.

### D-2 — Extend the validator rule to the `FROM` side, at depth 1 only

- **chosen:** in `VisitSqlFromClause`, fire when the flag is set and some `SqlTableSource` in
  `element.Tables` is a limited `SelectQuery` while the `FROM` clause has a second source (that table
  source carries joins, or `Tables.Count > 1`). Leave `VisitSqlJoinedTable` untouched.
- **rejected: `VisitSqlTableSource`.** More local, but a table source cannot see its siblings, so it
  cannot express `U-2`'s comma-join arm — which `U-3` measured firing 8 times.
- **rejected: walking through wrappers to find a limited query at any depth.** It would reject the
  queryable form, which is correct today (`P1`, *Why the queryable form survives*). Depth 1 is the point.
- **why this:** the flag's own doc says *"any JOIN to subquery which has TOP"* — "any" already claims
  both sides; the rule under-implemented its own contract.
- **failure mode of the choice:** a query correct by accident — outer cardinality already ≤ the limit —
  now throws. Measured: two tests, both `EXISTS`-shaped, where the row count cannot matter. See `P10`.

### D-3 — Keep the optimizer untouched

- **chosen:** revert both optimizer experiments; `SelectQueryOptimizerVisitor.cs` is unchanged against HEAD.
- **why this:** the two simplifications involved (`OptimizeDistinct`'s redundant-DISTINCT drop and
  `MoveSubQueryUp`'s merge) are correct everywhere; the shape they jointly produce is only wrong on one
  provider, and the strategy choice is a cheaper and more honest place to express that.
- **failure mode of the choice:** a hand-written `FROM (limited) JOIN` query still reaches the provider
  and is refused rather than rewritten. That is `D-2`'s job and is the correct outcome per probes F/G.

### D-4 — Run the new check after the descent, guarded on `IsValid`

- **chosen:** place it after `base.VisitSqlFromClause`, under `if (IsValid && …)`.
- **rejected:** an early return at the top of the method, which is where it was first written.
- **why this:** a source already refused for its own reason keeps reporting that reason. It fixes the
  `DoubleOrderBy` message flip (`U-9`) and subsumes the critic's `_fakeJoin` objection (`P12` O-4): the
  APPLY check runs during the descent and short-circuits, so a synthesised join never reaches this rule.
- **failure mode of the choice:** rule precedence is now positional. A future reordering of the descent
  would silently change which message a doubly-invalid query reports.

## P6 Edit-points

- **E-1** `Internal/Linq/Builder/ExpressionBuilder.EagerLoad.cs:ResolveStrategy` — `Default → KeyedQuery`
  remap + XML doc restating it. → TO-1, TO-2, TO-3
- **E-2** `Internal/SqlQuery/Visitors/SqlQueryValidatorVisitor.cs` — `HasJoinedLimitedDerivedTable` helper
  + the guarded call at the end of `VisitSqlFromClause`. → TO-4, TO-5, TO-6
- **E-3** `Internal/SqlProvider/SqlProviderFlags.cs:IsJoinDerivedTableWithTakeInvalid` — XML doc restates
  SC-3: either side of the join, and a multi-table `FROM`. → TO-4
- **E-4** `Tests/Linq/Linq/CompileTests.cs`, `CompileTestsAsync.cs` — drop the Sybase exclusions from
  `ElementFormLoadWithTest`, `ElementFormLoadWithThenLoadTest`, `ElementFormLoadWithAsyncTest`. → TO-1
- **E-5** `Tests/Linq/Linq/EagerLoadingTests.cs` — `ElementFormLoadWithReturnsAllDetails` and
  `LimitedFormLoadWithReturnsAllDetails`. → TO-2, TO-3
- **E-6** `Tests/Linq/Linq/WhereTests.cs:Issue_SubQueryFilter1/2`,
  `Tests/Linq/Linq/QueryableAssociationTests.cs:Issue4596Test` — `[ThrowsForProvider]`. → TO-7
- **E-7** `Tests/Linq/Linq/JoinToLimitedTests.cs` — `JoinFromLimited`, `CrossJoinFromLimited`: the
  fixtures that make the rule's two arms sensitive to the defect rather than merely to its refusal. → TO-5
- **E-8** `Tests/Linq/Linq/EagerLoadingStrategyKeyedQueryTests.cs` — remove the 37 Sybase
  exclusions. → TO-8

## P7 Impact map (M/L)

| Row | Verdict |
|---|---|
| **Writers of `IsJoinDerivedTableWithTakeInvalid`** — `Grep` over `Source/`: declaration + `GetHashCode`/`Equals`, `SybaseDataProvider.cs:56` (only `= true`), `SqlQueryValidatorVisitor.cs:355` (only reader before this branch). | covered by E-1/E-2/E-3 — blast radius is Sybase only |
| **Callers of `SqlProviderHelper.IsValidQuery`** — `ExpressionBuilder.cs:297`, `ExpressionBuilder.SqlBuilder.cs:217`, `BasicSqlOptimizer.cs:1196`, `SelectQueryOptimizerVisitor.cs:3747/3760/3773/3802`. Every one already branches on `false`; a stricter rule makes them decline more often, never mis-handle a new value. | covered by E-2. Note the critic's correction (`P12` O-5): declining there **keeps** the join, which is then refused at `:297` — a stricter validator cannot turn a wrong query into a correct one, only into a refusal |
| **Callers of `ResolveStrategy`** — `CompleteEagerLoadingExpressions` only, once per expression set. Its result feeds the `CteUnion → KeyedQuery → Default` chain, which already handles a declining strategy. | covered by E-1; the decline path is exercised by `Issue4596Test` (`U-7`) |
| **`ThrowsForProvider` sites bound to `Error_JoinToDerivedTableWithTakeInvalid`** — 17 before this branch across `Issue461Tests` (×4), `JoinToLimitedTests` (×2), `DefaultIfEmptyTests` (×2), `AssociationTests`, `ConvertExpressionTests`, `ElementOperationTests`, `SelectTests`, `SelectScalarTests`, `SelectQueryTests`, `InsertTests` (×2), `UpdateFromTests`. A **wider** rule cannot stop them throwing. | out-of-scope; re-verified by TO-7 |
| **Sites bound to `Error_OUTER_Joins`** — the negative subjects at risk from a message flip, ~25 across `ElementOperationTests`, `ConvertExpressionTests`, `EagerLoadingTests`, `ConditionalTests`, `ConcatUnionTests`, `GroupByTests`, `JoinTests`, `StringJoinTests`, … | covered by D-4 and by TO-7's diff, which shows none of them moved |
| **Serialized / wire shapes** — `SqlProviderFlags` is `[DataMember]`-annotated and crosses `LinqService`; no member added, removed or reordered, only an existing flag's interpretation widens, and both ends run the same build. `.LinqService` contexts are in every run below. | out-of-scope |
| **Baselines** — `BaselinesPath` is CI-only. Sybase SQL changes for every element-form eager load (now keyed) and for shapes the optimizer no longer builds. | covered by G-02 — the PR's baselines branch is the artifact |

## P8 Test obligations (M/L)

- **TO-1** *(SC-1, red→green)* `CompileTests.ElementFormLoadWithTest`, `…ThenLoadTest`,
  `CompileTestsAsync.ElementFormLoadWithAsyncTest` with the Sybase exclusion removed. Red arm observed
  **for the right reason** before the fix: `Has.Count.EqualTo(2)` → got 1, not an exception.
- **TO-2** *(SC-1, red→green)* `EagerLoadingTests.ElementFormLoadWithReturnsAllDetails` — the plain,
  non-compiled shape #5865 lists as not verified. Same red arm.
- **TO-3** *(SC-2, control)* `EagerLoadingTests.LimitedFormLoadWithReturnsAllDetails` — the queryable
  form on **Sybase**. Discriminating input: it is the shape whose two-level SQL is correct today, so a
  predicate that walked through wrappers (`D-2` rejected alternative) reddens it while TO-1/TO-2 stay green.
- **TO-4** *(SC-3, red→green)* the `FROM`-side rejection itself, via `Issue_SubQueryFilter1/2` and
  `Issue4596Test` under `[ThrowsForProvider]`. Red arm = the queries succeed silently before the change.
- **TO-5** *(SC-3, red→green)* `JoinToLimitedTests.JoinFromLimited` and `CrossJoinFromLimited` — the
  join arm and the comma-`FROM` arm (`Tables.Count > 1`, no joins), each reading **two** rows out of a
  source limited to one, so a TOP escalated to the joined result returns one. Both carry
  `Assert.That(exp.Count(), Is.EqualTo(2))` on the expected side so the fixture fails loudly if the
  seed data ever stops discriminating. **Mutation recorded:** with the rule commented out, both fail on
  `Expected and result lists are different. Length` — a data mismatch, not a missing exception.
- **TO-6** *(SC-4, control)* the same fixtures plus `ElementFormLoadWithReturnsAllDetails` on
  `SQLite.MS` / `SQLite.MS.LinqService` return full data. **Mutation recorded:** deleting the
  `_providerFlags.IsJoinDerivedTableWithTakeInvalid` conjunct reddens all six SQLite cases with the
  rule's own exception; restoring it returns 8/8 green. The guard is therefore load-bearing and
  confined to the flag.
- **TO-7** *(SC-5, characterization)* full `Sybase.Managed` suite before and after, diffed by test id.
- **TO-8** *(new, characterization)* `EagerLoadingStrategyKeyedQueryTests` on Sybase, whose 37 blanket
  exclusions this branch removes because `D-1` makes Sybase depend on that strategy: **76/76 pass**.

## P9 Verification gates

Recorded against the working tree as of the final Sybase run; re-derive before the PR.

- `G-01`: **pass, with one gap named below** — TO-1/TO-2/TO-3: 25/25 on `Sybase.Managed` + `SQLite.MS`,
  both direct and `.LinqService`. TO-4: green via `[ThrowsForProvider]`. TO-5 and TO-6: green with
  their mutations recorded. TO-7: below. TO-8: 76/76.
  **Gap:** no single full-suite run contains *both* the fix and the un-gating — the two attempts were
  eaten by a Sybase stall (see `P10`). The strongest evidence is the clean 8785/12 full run plus the
  76/76 and 1007/1007 focused runs on top of it. CI is the first place all of it runs together.
- `G-02`: **blocked** — baselines are CI-only; the PR's baselines branch is the artifact.
- `G-03`: n/a — no new public surface.
- `G-04`: n/a — no API surface change.
- `G-05`: **pass** — `dotnet build Source/LinqToDB/LinqToDB.csproj -c Release -f net10.0` and
  `-f netstandard2.0` both succeed (needs `-p:NuGetAudit=false`; `Microsoft.Build.Tasks.Git` 10.0.301
  carries an advisory that fails restore under warnings-as-errors, unrelated to this branch).
- `G-06`: **pass** — `SelectQueryOptimizerVisitor.cs` reverted to HEAD; no unrelated reformatting.
- `G-07`: **pass** — `Tests/Tests.Playground/TestTemplate.cs` must be reverted before staging (currently dirty).
- `G-08`: **pass** — cross-cutting core change resting on red→green plus two full-suite diffs.
- `G-09`: — not yet run.

**TO-7 result.** Baseline (branch point): 8775 total, 12 failed — all `ContainsTests`, the recorded
pre-existing Sybase set. Final: 8785 total, 18 failed. Diff by test id: **6 new, 0 gone**, being
`Issue_SubQueryFilter1`, `Issue_SubQueryFilter2` and `Issue4596Test`, each on `Sybase.Managed` and
`Sybase.Managed.LinqService` — all three converted to `[ThrowsForProvider]` by `E-6`. Intermediate
measurements on the way: validator alone 49 failed (37 new); after `D-4` 47; after `D-1` 18.

## P10 Adjudicated (M/L)

- **Two `EXISTS`-shaped queries now refuse where they returned correct data — but they never covered the
  defect.** `Issue_SubQueryFilter1/2` put a `First()` subquery beside another `FROM` source; under
  `EXISTS` only emptiness matters, and ASE's defect cannot empty a non-empty set. Measured rather than
  reasoned, because `AssertQuery` skips the comparison entirely when both sides are empty
  (`TestBase.AssertQuery.cs:465`) and a constant-`false` predicate would have made both tests vacuous:
  `Patient` has **1** row (`PersonID = 2`), `Any(John)` is false, `Any(Tester)` is true, and both
  queries return **1** row. So the comparison does run — the tests are not vacuous — but with a single
  `Patient` row and an emptiness-only predicate, a correct and a TOP-mangled plan give the same answer.
  Gating them therefore costs a real but narrow data check and **no** coverage of the shape, which
  nothing covered. Accepted; narrowing the rule on an `EXISTS` context would add cross-cutting state and
  diverge from the joined-side rule, which has been equally conservative since 2022.
- **The 37 `EagerLoadingStrategyKeyedQueryTests` Sybase exclusions are removed in this branch.** They
  sat beside `AllAccess` with no comment and had never been measured; with `D-1` making Sybase depend
  on the keyed strategy, zero coverage was not tenable. Measured 76/76 green (TO-8). Removed with one
  `replace_all`, not by hand; `IsCteSupported` at `:1740` names Sybase for a real reason (no CTE) and
  is untouched.
- **`Issue4596Test` is refused, not fixed.** `KeyedQuery` declines it (`ComplexParentReference`) and no
  strategy can express it on Sybase. Fixing `KeyedQuery`'s parent-reference limit is out of scope.
- **Sybase stalls, and it is not this branch.** Two full-suite runs froze at ~93 % (8288/8863) with the
  heartbeat stuck and one DML test marked `[slow] still running after 8m` — `UpdateTestWhere`, then
  `Enumerable_Upsert` — the second on a **freshly created** container, so leftover locks from killed
  runs are ruled out. The maintainer confirms it is a known condition of this container. Attribution
  was settled by isolation rather than a control run: `Tests.xUpdate` alone is 1007/1007 in 72 s and
  the newly enabled fixture alone is 76/76. Likewise `Issue4596Test`, which hung twice when run alone
  earlier, completes 2/2 in 2m06s on the clean container — nothing reproducible to compare against
  `master`, so no such comparison was made.

## P11 Amendments (M/L)

- **A-1** `E-1` replaced the plan's original single-edit design after `U-5` measured `KeyedQuery` working
  on Sybase. The first design refused the element form outright and converted 18 test methods to
  `[ThrowsForProvider]`; the user chose the strategy-remap direction when offered the two. `P2`'s
  criteria were rewritten from "is rejected" to "returns the full collection", and the disclosure that
  #5865's second clause was unimplementable was withdrawn.
- **A-2** `D-3` — both optimizer approaches (`DoNotRemove` from the builder; the `IsMovingUpValid` guard)
  were implemented, measured, and **abandoned**, not deferred. The `IsMovingUpValid` guard is refuted by
  measurement, not by preference: it fires and the shape reappears.
- **A-3** `U-8` — both new sites moved from `Select.TakeValue != null` to `SelectQueryExtensions.IsLimited`
  on the user's prompt. The pre-existing `VisitSqlJoinedTable:355` check still uses the hand-rolled form;
  left alone deliberately (an unmodified line, and the divergent input — `Skip` in a Sybase derived
  table — is unreachable), but the asymmetry is now in one rule and should be raised in review.

- **A-4** `E-7` added after the user pushed back on `P10`'s claim that the two `EXISTS` tests were
  adequate coverage — *"тоді треба зробити тест чутливим"*. Those two cannot be made sensitive (the
  defect is provably invariant under `EXISTS`), so the sensitivity was moved to two new fixtures over
  the shape itself, each with a guard against the seed data drifting into an insensitive state.
- **A-5** `E-8` added on the user's decision — *"якщо вони почали працювати, то так"* — after `U-5`
  measured the keyed strategy working on Sybase. `TO-8` is its verification.

## P12 Critic verdict (M/L)

**weak** (`plan-critic`, run on a different model). Objections and dispositions:

- **O-1 — the exception's path was described wrongly.** Accepted; `P1` now carries the two-pass build and
  the `SelectManyBuilder` simulation. `SC` outcomes were unaffected.
- **O-2 — `P1` row G over-generalised, and no `P8` row guarded the Sybase-side symmetry.** Accepted;
  `TO-3` now requires the queryable-form control, which had been added ad hoc.
- **O-3 — the `KeyedQuery` rejection rested on a false premise.** Accepted, and it turned out to be the
  most valuable objection in the review: probe F says nothing about `KeyedQuery`, which never emits `TOP`
  in a subquery. Measuring it (`U-5`) changed the whole design.
- **O-4 — the predicate counted `_fakeJoin`.** Accepted; resolved structurally by `D-4` rather than by a
  special case.
- **O-5 — `U-5`'s "bonus" was inverted.** Accepted; `P7` row 2 now states that a stricter validator can
  only produce a refusal.
- **O-6 — counts and paths wrong** (3 Sybase-excluded methods not 4; 17 sites not 15; the `.trx` path).
  Accepted and corrected throughout.
- **O-7 — `TO-1`/`TO-2` conflated engine-level and provider-level.** Accepted; obligations rewritten.
- **O-8 — the dispatch premise was stale and a `ProbeLog` debug hook was in the tree.** Accepted; all
  instrumentation is removed and `git diff Source/` shows three files.
