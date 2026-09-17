# issue/5936-fix-keyed-detail-limit — KeyedQuery: scope a detail-side Take/Skip per parent

Tier: **M** — one area, three files, but a defect fix with a real choice of fix location (local path vs whole-strategy fallback), which is the shape `work-plan.md` says must not take S.

Issue: [#5936](https://github.com/linq2db/linq2db/issues/5936) · milestone 6.5.1 · status: implementing

## P1 Problem

Under `EagerLoadingStrategy.KeyedQuery`, a `Take` / `Skip` on an eager-loaded child collection is applied
once to the whole child batch instead of once per parent key. Reported on `SQLite.Classic` and
`PostgreSQL.18`, direct and remote: two parents with three children each and a child `Take(2)` return
`[2, 0]` where `[2, 2]` is correct, with no error. `Default` returns `[2, 2]`.

Reproduced on this branch (SQLite.Classic, 3 companies × 3/4/5 departments, association child with
`OrderBy(d => d.Id).Take(2)`); the child preamble is:

```sql
SELECT [d].[CompanyId], [d].[Id], [d].[Name] FROM [Department] [d]
WHERE [d].[CompanyId] IN (1, 2, 3) ORDER BY [d].[Id] LIMIT @take   -- 2   → Rows Count: 2
```

Cause: `ProcessEagerLoadingKeyedQuery` has two child-query shapes and only one is flat.
`ExpressionBuilder.EagerLoadKeyedQuery.cs:203-246` rewrites `childFK == parentKey` into
`keys.Contains(childFK)`, which collapses every parent's children into one un-correlated result set; the
rest of the chain — including the limit — is carried over verbatim and now spans the batch. The sibling
path at `:248-287` emits `keys.SelectMany(k => child.Where(fk == k) …)`, one correlated sub-query per key,
where the limit stays per parent (CROSS APPLY where supported; otherwise
`SelectQueryOptimizerVisitor.OptimizeApplyJoin` `:1486` emulates it via the `ROW_NUMBER` built at `:1602`,
which is why `Default` is correct on SQLite, a provider with `IsApplyJoinSupported = false`).

## P2 Success criteria

- **SC-1** — a child `OrderBy(…).Take(n)` over an **association** under `KeyedQuery` returns
  `min(n, childCount)` rows for **every** parent, matching in-memory LINQ. → `TO-1`
- **SC-2** — the same holds for `Skip(m).Take(n)` over an association: the *offset* is per parent too. → `TO-2`
- **SC-3** — a limited child that already builds the correlated shape (an explicitly filtered child table)
  keeps returning per-parent results, identically under `Default`, `KeyedQuery` and `CteUnion`. → `TO-3`
- **SC-4** — no eager-load query *without* a chain limit changes its emitted SQL: no existing baseline moves
  and every `KeyedQuery`-consuming fixture stays green. → `TO-4`

## P3 Constraints & anti-goals

- **Do not touch `ResolveStrategy` or `EagerLoadFallbackReason`.** The issue's own remedy wants both; declined
  in `D-1`, disclosed in the PR body. Open PR [#5900](https://github.com/linq2db/linq2db/pull/5900) is
  rewriting `ResolveStrategy`.
- No public API surface; no `PublicAPI.Unshipped.txt` entry; no baseline regeneration (a release task).
- No behaviour change for a child sequence with no chain `Take`/`Skip` — the Contains rewrite stays the
  default shape.
- No reformatting of neighbouring lines.
- **#5935 is not fixed here.** Its repro (an eager-loaded `OrderBy` whose key is absent from the projection)
  overlaps the reported shape; the fixtures keep the ordering key in the projection to stay clear of it.
  Fix lives on PR [#5938](https://github.com/linq2db/linq2db/pull/5938).

## P4 Unknowns

- **U-1** — does the `SelectMany` + VALUES path actually scope the limit per key on a provider with **no**
  APPLY support? The VALUES-source-plus-correlated-limit combination is exercised by no existing test.
  **resolved-by probe (measured, SQLite.Classic, 2026-09-17):** yes. `TO-3`'s `KeyedQuery` arm emits
  `FROM (VALUES (1),(2),(3)) [k_1] INNER JOIN (… ROW_NUMBER() OVER (PARTITION BY [d].[CompanyId] ORDER BY
  [d].[Id]) as [rn] …) [d_1] ON [d_1].[CompanyId] = [k_1].[item] AND [d_1].[rn] <= 2` — the emulation branch,
  per key.
- **U-2** — does `CteUnion` share the defect? **resolved-by probe (measured, same run):** no. Its branch CTE
  carries the same `PARTITION BY [d].[CompanyId] … rn <= 2`. Had it been red it would have taken its own
  issue/branch, not this PR.
- **U-3** — does any existing test put a `Take`/`Skip` on an eager-loaded child under `KeyedQuery` (i.e. would
  the guard move an existing baseline)? **resolved-by scout:**
  `git grep -l "WithKeyedLoadStrategy\|EagerLoadingStrategy.KeyedQuery" -- "Tests/*.cs"` returns five files —
  `Tests/Linq/Infrastructure/DataOptionsTests.cs`, `Tests/Linq/Linq/EagerLoadingStrategyKeyedQueryTests.cs`,
  `EagerLoadingStrategyUnionTests.cs`, `EagerLoadingWideKeyTests.cs`, `ImplicitCollectionLoadingTests.cs`.
  Grepped `\.Take\(|\.Skip\(` across them: no hit sits on an eager-loaded child chain
  (`EagerLoadingWideKeyTests.cs` has none at all; the union fixture's are parent-side at `:557`, `:565`, and
  an uncorrelated `Take(100)` inside a parent `Any` at `:3688`). Expect zero existing-baseline churn; any
  movement falsifies the scope.
- **U-4** — a provider with neither APPLY nor window functions cannot express a per-key limit under *any*
  strategy. The new fixtures carry the file's existing `TestProvName.AllAccess, TestProvName.AllSybase`
  exclusions, so they do not assert on those. #5900 removes those blanket exclusions repo-wide; flag the
  interaction on that PR rather than pre-empting it here. *resolved-by user disclosure* (recorded in `P10`).
- **U-5** — why does an explicitly filtered child table (`tDep.Where(d => d.CompanyId == c.Id)`) already take
  the correlated path while the equivalent association takes the Contains rewrite? Measured, not explained:
  `TO-3` is green against the unfixed tree on all three strategies while `TO-1`/`TO-2` are red.
  `FindChildFkExpression` requires the FK side to be a `MemberExpression`, so the table form presumably
  arrives as something else after `ExpandContexts`. *resolved-by measurement; the mechanism is not
  load-bearing for this fix* — the guard is upstream of that distinction and the fixtures pin both shapes.

## P5 Decisions

**D-1 — where the fix goes.**
- **chosen:** refuse the Contains shortcut when the child's method chain carries a `Take`/`Skip`, so those
  queries take KeyedQuery's existing correlated `SelectMany` + VALUES JOIN path.
- **rejected:** the issue's own remedy — `ProcessEagerLoadingKeyedQuery` returns `null` with a new
  `EagerLoadFallbackReason`, stepping the whole query down to `Default`. It downgrades eager loading for
  every *other* collection in the same query, silently disables a strategy asked for by name (the
  [#5904](https://github.com/linq2db/linq2db/issues/5904) shape), and lands on the same correlated
  `SelectMany` shape KeyedQuery already has locally — so it buys no correctness the local path lacks.
- **why this:** the defect is a property of one of two shapes, not of the strategy. `U-1` measured the
  surviving shape producing the correct per-key SQL on the reporting provider.
- **failure mode of the choice:** on a provider that supports neither APPLY nor window functions, the
  correlated shape is inexpressible where the flat one merely returned wrong rows — a wrong answer becomes a
  loud failure. That is the intended direction, and `Default` fails identically there (`U-4`).

**D-2 — detect on the outer chain, not the whole tree.**
- **chosen:** walk `MethodCallExpression.Arguments[0]` while `IsQueryable`, stepping through
  `SqlAdjustTypeExpression` and converts — the same walk `HasOnlySimpleFilterDependencies:394-420` uses.
- **rejected:** an `Expression.Visit` over the whole sequence. It fires on limits that are already correctly
  scoped — `children.SelectMany(c => c.Sub.Take(2))`, `children.Where(c => db.Other.Take(1).Any(…))` — and
  would disable the Contains shortcut for queries that are not affected.
- **why this:** only a limit on the child's own chain is the one the Contains rewrite re-scopes.
- **failure mode of the choice:** a limit reachable only through a node shape the walk does not step through
  is missed and stays wrong. The walk covers what this file's own sibling walks cover; a new wrapper node
  type would need the same row added to all of them.
- **separating input:** `Logs.SelectMany(l => l.Sub.Take(2))` — chain-walk `false`, whole-tree `true`.

**D-3 — `Take` / `Skip` only.**
- **chosen:** match `mce.Method.Name is nameof(Enumerable.Take) or nameof(Enumerable.Skip)`.
- **rejected:** adding `TakeLast` / `SkipLast` / `ElementAt`. `TakeSkipBuilder` dispatches on exactly
  `[BuildsMethodCall("Skip", "Take")]` — no other name reaches a `SelectQuery` limit, and `ElementAt*`
  yields a scalar, so it cannot be an eager-loaded collection's outer node.
- **why this:** the guard's set is the set the SQL limit is built from.
- **failure mode of the choice:** if a future builder starts lowering another name to `TakeValue`/`SkipValue`,
  this guard silently stops covering it. `TakeSkipBuilder`'s attribute is the single site to re-check.

## P6 Edit-points

- **E-1** `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuilder.EagerLoadKeyedQuery.cs:ProcessEagerLoadingKeyedQuery`
  — the `canUseContains` gate at `:190-201` also requires `!HasChainLimit(correctedSequence)`. → `TO-1` `TO-2`
- **E-2** same file — new `static bool HasChainLimit(Expression)` beside `HasOnlyEqualityKeyReferences`. → `TO-1` `TO-3` `TO-4`
- **E-3** `Tests/Linq/Linq/EagerLoadingStrategyKeyedQueryTests.cs` — new region *Detail-side Take/Skip —
  scoped per parent (#5936)* with `Select_KeyedQuery_AssociationDetailTakeIsPerParent`,
  `Select_KeyedQuery_AssociationDetailSkipTakeIsPerParent`, `Select_KeyedQuery_DetailTakeIsPerParent`.
  → `TO-1` `TO-2` `TO-3`

## P7 Impact map

- **callers of `canUseContains`** — searched `ExpressionBuilder.EagerLoadKeyedQuery.cs`: the flag is a local,
  read at `:203` and `:248` inside `ProcessEagerLoadingKeyedQuery` only. `covered by E-1`.
- **callers of `ProcessEagerLoadingKeyedQuery`** — searched: one call site,
  `ExpressionBuilder.EagerLoad.cs:628`, so there is no second entry point the guard must also cover.
  `covered by E-1`.
- **callers of `HasChainLimit`** — new symbol, single call site. `covered by E-1`.
- **mirrored strategy entry points** — `ProcessEagerLoadingExpression` (`ExpressionBuilder.EagerLoadDefault.cs:18`)
  and `ProcessCteUnionBatch` (`ExpressionBuilder.EagerLoadUnion.cs`). Searched both for a Contains/`IN`
  rewrite: neither has one; both build a `SelectMany` over the parent query / branch CTE, so the per-key
  scoping the guard restores already holds there. `out-of-scope`, and measured by `TO-3`'s `Default` /
  `CteUnion` arms (`U-2`).
- **emitted SQL for untouched queries** — the guard fires only on a chain `Take`/`Skip`. The consumer set is
  `git grep -l "WithKeyedLoadStrategy\|EagerLoadingStrategy.KeyedQuery" -- "Tests/*.cs"` →
  `Tests/Linq/Infrastructure/DataOptionsTests.cs`, `Tests/Linq/Linq/EagerLoadingStrategyKeyedQueryTests.cs`,
  `Tests/Linq/Linq/EagerLoadingStrategyUnionTests.cs`, `Tests/Linq/Linq/EagerLoadingWideKeyTests.cs`,
  `Tests/Linq/Linq/ImplicitCollectionLoadingTests.cs`; none carries a `Take`/`Skip` on an eager-loaded child
  chain (`U-3`). `covered by E-2` + `TO-4`.
- **serialized / wire shapes** — none: no AST node, no enum, no `LinqService` contract, no public API changed.
  Remote execution is covered by the fixtures' `[DataSources(true, …)]` and measured red+green on
  `SQLite.Classic.LinqService`. `out-of-scope`.
- **provider capability flags** — `IsApplyJoinSupported` / `IsWindowFunctionsSupported` are *read* by the
  existing optimizer path the guard routes into; nothing is added or defaulted. `out-of-scope`.

## P8 Test obligations

- **TO-1** `Select_KeyedQuery_AssociationDetailTakeIsPerParent` — `red→green`. The reported shape: an
  association, `OrderBy(d => d.Id).Take(2)`, projected to a type that drops the FK (`CompanyId`), so it also
  exercises `WrapTerminalSelectWithEnvelope`. Red observation recorded in `G-01`: the child preamble is the
  flat `WHERE CompanyId IN (1,2,3) … LIMIT @take` returning 2 rows for the whole batch, and the failure is a
  Shouldly data assertion — **not** #5935's `InvalidOperationException`, which is why the ordering key stays
  in the projection.
- **TO-2** `Select_KeyedQuery_AssociationDetailSkipTakeIsPerParent` — `red→green`, `Skip(1).Take(2)`. The
  separating observation is the per-parent *offset*: a global `Skip` drops rows from the first parent only,
  so a fixture asserting only counts would pass on a wrong-offset implementation.
- **TO-3** `Select_KeyedQuery_DetailTakeIsPerParent` (`[Values] EagerLoadingStrategy`) — `characterization`
  **and** the symmetry guard on the unchanged path. An explicitly filtered child table already builds the
  correlated shape (`U-5`), so this is green before and after the fix on all three strategies; it proves
  `E-2` adds no behaviour there, and it is what measured `U-1` and `U-2`.
- **TO-4** symmetry guard across the whole consumer set — the five files `U-3` enumerates, run on the same
  provider set as `G-01`, plus a baselines diff. `characterization`. The negative subjects are those files'
  existing fixtures, named rather than described; a moved existing baseline falsifies `U-3`.

## P9 Verification gates

All rows measured 2026-09-17 against the tree committed as this branch's first commit.

- `G-01`: **pass**, one row per obligation. Runs via the built MTP exe from the worktree
  (`linq2db.Tests.exe --provider <p> --test-progress --filter "…CreateData.CreateDatabase|…IsPerParent"`),
  `/test`'s documented exception for a worktree whose fixtures do not exist in the primary clone.
  - `TO-1` `Select_KeyedQuery_AssociationDetailTakeIsPerParent` — **red→green observed.** Red on
    `SQLite.Classic` + `.LinqService`: `Shouldly.ShouldAssertException`, child preamble
    `WHERE [d].[CompanyId] IN (1, 2, 3) ORDER BY [d].[Id] LIMIT @take` → `Rows Count: 2` for the whole
    batch. Green after `E-1`: `FROM (VALUES (1),(2),(3)) [k_1] INNER JOIN (… ROW_NUMBER() OVER (PARTITION
    BY [d].[CompanyId] ORDER BY [d].[Id]) as [rn] …) ON … AND [d_1].[rn] <= 2` → `Rows Count: 6`. The row
    count *is* the observation that the branch fired: 2 = batch-wide, 6 = 2 per parent.
  - `TO-2` `Select_KeyedQuery_AssociationDetailSkipTakeIsPerParent` — **red→green observed**, same two
    contexts, same failure class.
  - `TO-3` `Select_KeyedQuery_DetailTakeIsPerParent` ×3 strategies — green before and after, as specified.
    Its pre-fix `KeyedQuery` SQL is what measured `U-1`, its `CteUnion` SQL what measured `U-2`.
  - `TO-4` — 395/395 on `SQLite.Classic` across `EagerLoadingStrategyKeyedQueryTests`,
    `EagerLoadingStrategyUnionTests`, `EagerLoadingWideKeyTests`, `ImplicitCollectionLoadingTests`,
    `EagerLoadingTests`. `DataOptionsTests` is option-plumbing only and was not run.
  - Provider breadth: `SQLite.Classic` 12/12, `SQLite.MS` + `DuckDB` 22/22, `SqlServer.2017` 12/12 — each
    direct and remote. SQL Server covers the other emulation route:
    `FROM (VALUES …) [k_1]([item]) CROSS APPLY (SELECT TOP (2) … WHERE [k_1].[item] = [d].[CompanyId]
    ORDER BY [d].[Id]) [d_1]` → 6 rows. Both `OptimizeApplyJoin` outcomes are therefore measured.
- `G-02`: **skipped** — the worktree carries a seeded (gitignored, unstaged) `UserDataProviders.json`, so
  baselines were written to the shared `linq2db.bls` path but not diffed here. What is therefore unverified:
  whether any *existing* baseline moved. `U-3`'s search says none can (no existing fixture puts a
  `Take`/`Skip` on an eager-loaded child under `KeyedQuery`); the CI baselines PR is the authority.
- `G-03`: n/a — no new public surface (both edits are `private`/`static` inside an internal partial class).
- `G-04`: n/a — no public API change, so no `CompatibilitySuppressions.xml` refresh.
- `G-05`: **pass** — `dotnet build Source/LinqToDB/LinqToDB.csproj -c Release -f net10.0` (analyzers on) and
  `-f netstandard2.0` (portable TFM) both exit 0.
- `G-06`: **pass** — `git diff --stat` is 2 files, +158/−1; the source hunk is the gate line plus the new
  helper, no reformatting of neighbouring lines.
- `G-07`: **pass** — nothing under `Tests/Tests.Playground/` is touched; the only untracked-but-present file
  is the gitignored `UserDataProviders.json`, which `git status` does not see.
- `G-08`: n/a — `Internal/Linq/Builder` is not on `cross-cutting-core.md`'s `paths:` list, and the change adds
  no AST node, provider seam or translator signature. Resting on red→green, not reasoning (`TO-1`, `TO-2`).
- `G-09`: **pass** — `plan-critic` on a different model attacked the design and the shipped diff; verdict and
  objections in `P12`, both folded in as `A-2`.

## P10 Adjudicated

- **The issue's stated remedy is not implemented.** #5936's *Expected behavior* asks the strategy resolver to
  fall back and notes `EagerLoadFallbackReason` has no member for this case. Declined per `D-1`, whose
  failure-mode line qualifies the loss: on a provider supporting neither APPLY nor window functions the
  correlated shape is inexpressible and now fails loudly instead of returning wrong rows — `Default` fails
  identically there, so no strategy regresses. To be disclosed in the PR body; not a review finding.
- **Access / Sybase are not asserted on**, matching every other fixture in this file. Named in `U-4`;
  re-opens when #5900 removes the blanket exclusions.
- **`U-5` is left unexplained.** The table-vs-association path divergence is measured and fixtured on both
  sides, but no mechanism is recorded. Not a gap in the fix — the guard sits upstream of the divergence.

## P11 Amendments

- **A-1 (2026-09-17) — the red→green obligations moved from the table form to the association form.** As
  authored, `TO-1`/`TO-2` used `tDep.Where(d => d.CompanyId == c.Id)…Take(2)`. Measured against the unfixed
  tree, that shape **passes** on all three strategies: it already builds the correlated VALUES-join, so it
  could never have gone red and would have shipped as a fixture whose name claims the defect and whose input
  does not reach it. The association form — the one the issue reports — is red. `P2`, `P6`/`E-3` and `P8` are
  rewritten accordingly; the table form is retained as `TO-3`, relabelled `characterization`. This does not
  change `E-1`/`E-2`, so the approved source surface is unchanged. New unknown `U-5` records the divergence.
- **A-2 (2026-09-17) — sweep and citation corrections from the critic.** `P7`'s emitted-SQL row, `U-3` and
  `TO-4` named a fixture set that included `EagerLoadingTests.cs` (which never uses `KeyedQuery`) and omitted
  `EagerLoadingWideKeyTests.cs` (five `WithKeyedLoadStrategy()` call sites). Re-derived from
  `git grep -l`, verified independently. `P1`'s `OptimizeApplyJoin` citation was taken from a checkout 93
  commits behind and is corrected to this branch's `:1486` / `:1602`. No conclusion changed:
  `EagerLoadingWideKeyTests.cs` carries no `Take`/`Skip`, so "no existing baseline moves" still holds — but it
  now rests on a search rather than on luck.

## P12 Critic verdict

**weak** — `plan-critic` on a different model (Sonnet), 2026-09-17.

Objections, both accepted and folded in as `A-2`:

1. *"TO-4's negative-subject fixture list is not derived from an actual search for `KeyedQuery`-strategy
   consumers, and it names the wrong set of files"* — correct, and it also invalidated `U-3`'s scout. The
   critic verified independently that no baseline actually moves; its point was that the plan's evidence
   chain did not establish that. Re-derived and re-verified.
2. Stale `OptimizeApplyJoin` line citation — correct, fixed.

It attacked `E-1`/`E-2` and could not fault them. Specifically, `D-2`'s outer-chain walk survived every
construction it built from real code paths: the association-predicate `Where`-wrapping order (the new outer
`Where`'s `Arguments[0]` is the entire prior chain, `Take` included), `LoadWith`'s filter function in both its
expression-tree and compiled-delegate forms, and the `ApplyModifierInternal` / `LoadWithInternal` /
`AssociationRecord` wrapper nodes a real `LoadWith(…).Take(…)` chain interposes — all of which are on the
`IsBuiltInQueryable` list the walk already steps through. It also refuted its own suspicion that `TO-3`'s
`CteUnion` arm silently degrades to `KeyedQuery` for a single-association query: `ProcessCteUnionBatch` has no
association-count gate, so the arm genuinely exercises the union machinery.
