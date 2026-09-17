# Work plan: 5935 — Fix eager-load OrderBy crash when the ordering key is absent from the projection

**Tier:** M  ·  **Status:** draft  ·  **Approved-at:** —  ·  **Branch:** issue/5935-fix-eager-load-ordering
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

## P1 Problem

[#5935](https://github.com/linq2db/linq2db/issues/5935). An eager-loaded collection that is ordered and then
projected throws at query-build time when the ordering key is not a member of the projection:

```cs
db.GetTable<Item>().Select(item => new
{
    item.Value,
    Logs = item.Logs.OrderBy(log => log.Id)          // key: log.Id
                    .Select(log => new { log.Log })  // projection omits it
                    .ToArray(),
});
// System.InvalidOperationException: No generic method 'OrderBy' on type 'System.Linq.Enumerable'
// is compatible with the supplied type arguments and arguments.
```

Adding `log.Id` to the projection, or using `FirstOrDefault()` instead of `ToArray()`/`ToList()` (no eager
load), avoids it. `OrderByDescending` / `ThenBy` / `ThenByDescending` behave identically. Worked in 6.3.0,
broken in 6.4.0 and 6.5.0.

Mechanism: `CollectOrderBy` (`ExpressionBuilder.EagerLoad.cs:149`) walks the detail sequence and hands the
ordering lambdas to `ApplyEnumerableOrderBy` (`:323`), which re-sorts the materialized per-key list
client-side. Until #5450 the walk stopped at any operator that changed the sequence type
(`if (!mc.Type.IsSameOrParentOf(current.Type)) break;`). Commit `6357afa67` removed that guard so the walk
could cross a `Select` and remap the lambdas onto the projected type (`RemapOrderByThroughSelect`, `:215`).
When a key is not in the projection, `:284` keeps the **original, entity-typed** lambda, and
`ApplyEnumerableOrderBy` then asks `Expression.Call(typeof(Enumerable), "OrderBy", [ItemLog, int], …)` to bind
against a `List<anon>` — no such overload, hence the throw.

## P2 Success criteria

- SC-1 The #5935 shape (`OrderBy` + a projection omitting the key, materialized with `ToArray`/`ToList`) builds and executes without throwing, on both the `Default` and `KeyedQuery` strategies. → TO-1
- SC-2 For an **unlimited** detail the eager-loaded rows come back in the order the user asked for, ascending **and** descending — dropping the client-side re-sort is not a silent loss of ordering there. Scoped to unlimited on purpose: U-1 measured that a limited detail keeps its `ORDER BY` inside the APPLY subquery. → TO-2
- SC-3 `ThenBy` / `ThenByDescending` under the same shape behave as SC-1 + SC-2. → TO-3
- SC-4 The shape that works today — the ordering key *present* in the projection — keeps working and keeps its order. → TO-4
- SC-5 The other element-type-changing operators the walk crosses unremapped below an `OrderBy` — `SelectMany` and `Cast<>` — do not throw. `OfType<>` is deliberately excluded: its element type is a *subclass*, so `IsSameOrParentOf` is true and E-2 does not skip it, meaning it behaves exactly as today and needs an inheritance-mapped fixture to say anything new. → TO-5
- SC-6 The same shape with a **limited** detail (`Take`/`Skip`) stops throwing; its ordering is explicitly not claimed, because the `ORDER BY` never leaves the APPLY subquery there (U-1). → TO-6

## P3 Constraints & anti-goals

- **No emitted-SQL change.** Neither edited function touches `SelectQuery`; both only shape a client-side
  expression. Existing baselines must not move — only new files for the new tests.
- **No public API.** Both symbols are private/`static` members of the `internal partial class
  ExpressionBuilder`, under `LinqToDB.Internal.*`.
- **Client-side re-ordering stays as a mechanism** — and U-1 shows why it must: for a limited (`Take`/`Skip`)
  detail the `ORDER BY` never leaves the APPLY/LATERAL subquery, so the re-sort is the only thing ordering
  `EagerLoadingTests.TestGroupJoin` / `TestSkipTake` today.
- **Do not restore the 6.3.0 sequence-type break in `CollectOrderBy`** — it would also stop at the `Select` the
  remap now handles, undoing #5450's fix (see D-3).
- Patch release: ships on milestone **6.5.1**, branched off `origin/master` like the other nine 6.5.1 PRs.

## P4 Unknowns

- U-1 Does the detail query keep its `ORDER BY` when the ordering column is not in the SELECT list? **Only for an *unlimited* detail.** `SqlQueryOrderByOptimizer.CanRemoveOrderBy` returns `false` on `selectQuery.IsLimited` (`Source/LinqToDB/Internal/SqlQuery/Visitors/SqlQueryOrderByOptimizer.cs:244`), so for a `Take`/`Skip` detail the push-up never runs and the `ORDER BY` stays **inside** the APPLY/LATERAL subquery with none on the outer preamble query — measured on two baselines: `EagerLoadingTests.TestGroupJoin(SqlServer.2019)` (`CROSS APPLY (SELECT TOP (10) … ORDER BY [d].[SubDetailValue])`, no outer `ORDER BY`) and `EagerLoadingTests.TestSkipTake(PostgreSQL.15)` (`INNER JOIN LATERAL (… ORDER BY d."DetailId" LIMIT 2 OFFSET 1) ON 1=1`) — resolved-by probe (critic-supplied, re-verified by reading `CanRemoveOrderBy` and both blobs)
- U-2 Is dropping the client re-sort a *regression* for any shape that works today? No. `!found` splits two ways: where the `Select` changed the element type the call at `:337` cannot bind, so the shape throws today (matrix rows 2 and 4) and E-1 reproduces 6.3.0 — whose guard `if (!mc.Type.IsSameOrParentOf(current.Type)) break;` also collected nothing there; where the `Select` kept the element type (a `MemberInit` to the same entity with the key member **redefined**, row 5) it binds and re-sorts by the redefined value, disagreeing with the SQL, and E-1 removes that — an improvement, not a regression — resolved-by probe (critic re-derived all five rows against the shipped `v6.3.0` body of `CollectOrderBy` and `IsSameOrParentOf`, `ReflectionExtensions.cs:420`; row 5 re-verified here by reading `RemapOrderByThroughSelect:255-286`)
- U-3 Do `OrderBy(...).SelectMany(...)` / `.Cast<>()` / `.OfType<>()` reach `ApplyEnumerableOrderBy` with a mismatched lambda? E-2 is **unconditional** either way — the guard is the precondition of the `Expression.Call` it protects and costs one loop — so this decides only whether TO-5 is `red→green` or `characterization` — resolved-by probe TO-5
- U-5 Does the `KeyedQuery` strategy scope a detail-side `Take`/`Skip` per parent key? **No** — `Take|Skip|Limited|RowNumber` in `ExpressionBuilder.EagerLoadKeyedQuery.cs` returns 0 hits, `ResolveStrategy` (`EagerLoad.cs:536-549`) routes only on CTE/window support, `EagerLoadFallbackReason` has no limited-child member, and the `Contains` rewrite (`EagerLoadKeyedQuery.cs:203-223`, read here) swaps only the `childFK == parentKey` equality for `keys.Contains(childFK)`, leaving the `Take` applied to the whole filtered set. That makes a KeyedQuery arm of TO-6 unprovable, hence TO-6 is `Default`-only. The global-`Take` behaviour **was** then probed and **is** a defect — `[2, 0]` instead of `[2, 2]` on SQLite.Classic and PostgreSQL.18, direct and remote, from a child query carrying one global `LIMIT` — now filed as [#5936](https://github.com/linq2db/linq2db/issues/5936) (6.5.1, wrong rows) and out of scope here — resolved-by probe (scratch test, run and removed)
- U-4 Does any existing test depend on the client re-sort correcting an order the SQL did not produce? **Yes, and they are known**: `EagerLoadingTests.TestGroupJoin` and `TestSkipTake` (the two U-1 baselines) — both key-*present* entity projections, so neither enters E-1's branch, and E-2 leaves them alone because their lambda parameter type equals the element type. G-01 running the full `EagerLoading` filter is the check that this reasoning holds — resolved-by probe G-01

## P5 Decisions

### D-1 — When a key cannot be remapped, drop the whole client-side ordering

The shape matrix this decision is actually made against — `l` is the detail entity, "re-sort" = the client-side
`ApplyEnumerableOrderBy` pass:

| detail sequence | 6.3.0 | 6.5.0 | after E-1/E-2 |
|---|---|---|---|
| `OrderBy(l => l.Id).Select(l => new { l.Id, l.Log })` (key present) | no re-sort | re-sort | re-sort — unchanged |
| `OrderBy(l => l.Id).Select(l => new { l.Log })` (key absent) | no re-sort | **throws** | no re-sort — as 6.3.0 |
| `OrderBy(l => l.Id).Take(n)`, entity projection | re-sort | re-sort | re-sort — unchanged |
| `OrderBy(l => l.Id).Take(n).Select(l => new { l.Log })` | no re-sort | **throws** | no re-sort — as 6.3.0 |
| `OrderBy(l => l.Id).Select(l => new ItemLog { Id = l.ItemId, … })` (same type, key redefined) | re-sort by the **redefined** `Id` | same — no throw | no re-sort, SQL order by the real `Id` — **better** |

- **chosen:** `RemapOrderByThroughSelect` returns `null` — the value the method already uses at `:249` to mean
  "drop the client-side ordering" — instead of keeping the source-typed lambda.
- **rejected:** detect `Take`/`Skip` in the walk and throw a `LinqToDBException` naming the fix ("put the
  ordering key in the projection") rather than silently dropping (the critic's option 1a). It answers the real
  gap U-1 exposes, but by replacing a shape that *worked in 6.3.0* with a hard error — a second regression
  layered on the one this issue reports. A patch release for a regression must not introduce another.
- **rejected:** carry the ordering key into the detail projection so the client can still sort by it — the real
  root-cause fix and the only one that closes the limited-detail gap, but it changes emitted SQL and
  materialization for every ordered eager load. Not a patch-release change; filed as a follow-up instead.
- **rejected:** retire `CollectOrderBy`/`ApplyEnumerableOrderBy` entirely — U-1 refutes it outright: the re-sort
  is load-bearing for limited details, where the `ORDER BY` never leaves the APPLY subquery.
- **why this:** row by row in the matrix, every shape E-1 touches either **throws today** (rows 2 and 4, where
  E-1 reproduces 6.3.0 exactly) or **re-sorts by a key the projection redefined** (row 5, where E-1 is strictly
  better: the client sort silently disagreed with the SQL's). It is not "loss-free" in the absolute sense — it
  is *no worse than the last release in which the query ran at all*, which is the correct bar for a regression
  fix, and on row 5 it is better than either release.
- **failure mode of the choice:** for a **limited** detail with an unmappable key (matrix row 4) the resulting
  order rests on the APPLY/LATERAL nested-loop emitting inner order — true in practice, not a SQL guarantee.
  That gap is pre-existing (6.3.0 had it) and is not closed here; TO-6 pins the no-throw half of it and says
  plainly that order is unasserted. Matrix row 5 is the only shape where E-1 removes a re-sort that actually
  ran: a `MemberInit` to the same entity type whose key member is **redefined** (`Id = l.ItemId`) sorted the
  projected objects by the redefined value, disagreeing with the SQL. Dropping it is a fix, not a loss — but it
  is a visible behaviour change and belongs in the PR description.

### D-2 — All-or-nothing, not the remappable prefix

- **chosen:** one unmappable key drops the entire ordering list.
- **rejected:** keep the prefix up to the first failure — LINQ's `OrderBy` is stable, so re-sorting by a
  partial key would in principle preserve the SQL's ordering within ties.
- **why this:** it relies on stability of an ordering the SQL already produced in full; dropping is the same
  outcome with no reasoning step, and the prefix form has no shape that needs it.
- **failure mode of the choice:** none distinguishable from D-1's — both end at "the SQL order stands".

### D-3 — The sibling guard goes in `ApplyEnumerableOrderBy`, not back in `CollectOrderBy`

- **chosen:** `ApplyEnumerableOrderBy` skips the re-sort when a collected lambda's parameter type is not
  same-or-base of the sequence's element type.
- **rejected:** restore 6.3.0's `if (!mc.Type.IsSameOrParentOf(current.Type)) break;` in the walk, exempting
  `Select` — it re-opens per-operator "is this safe to cross?" reasoning, which is exactly what #5450 removed,
  and undoes that fix's intent. (A second objection considered and dropped as **unreachable**: it would also
  fire on a `ToList()`/`ToArray()`-terminated chain. No builder registers those — `EnumerableBuilder.CanBuild`
  needs `CanBeEvaluatedOnClient` — so `HandleSubquery` fails on the materializing call and the visitor descends
  to its argument (`ExpressionBuildVisitor.cs:2867` → `:2873`); `SequenceExpression` never contains it.)
- **why this:** the check belongs where the call is actually built — it is exactly the precondition
  `Expression.Call(typeof(Enumerable), …)` will otherwise throw on, expressed once for every operator rather
  than per-operator.
- **failure mode of the choice:** it makes a future genuine remapping bug fail silently (no ordering) instead
  of loudly (exception). Accepted: the fallback is the SQL's own ordering, which is correct.

## P6 Edit-points

- E-1 `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuilder.EagerLoad.cs:RemapOrderByThroughSelect` — the
  `if (!found)` arm at `:284` returns `null` instead of appending the un-remapped lambda.
- E-2 `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuilder.EagerLoad.cs:ApplyEnumerableOrderBy` — return
  `queryExpr` unchanged when any lambda's parameter type is not `IsSameOrParentOf` the sequence element type
  (`TypeHelper.GetEnumerableElementType`); adds `using LinqToDB.Internal.Extensions;`. Unconditional: the walk
  crosses **every** unhandled `IsQueryable` operator (`SelectMany`, `Cast`, `OfType`, `GroupBy`, `Join`,
  `GroupJoin`, `Zip`, …), so gating the guard on one probed operator would leave `:337` reachable through the
  others.
- E-3 `Tests/Linq/UserTests/Issue5935Tests.cs` — new file: the regression fixture (TO-1…TO-6).

## P7 Impact map

- `ExpressionBuilder.EagerLoad.cs:200` — the only caller of `RemapOrderByThroughSelect`; its composition loop already breaks on a `null` return, so E-1 needs no caller change (searched `RemapOrderByThroughSelect` across `Source/`: 2 hits, declaration + this call) — covered by E-1
- `ExpressionBuilder.EagerLoad.cs:385` + `ExpressionBuilder.EagerLoadKeyedQuery.cs:863` — the only two callers of `ApplyEnumerableOrderBy`; both pass the `List<T>` from `PreambleResult<TKey,T>.GetList`, so the element type E-2 compares against is well-defined at both (searched `ApplyEnumerableOrderBy` across `Source/`: 3 hits, declaration + these two) — covered by E-2
- `ExpressionBuilder.EagerLoadDefault.cs:85` + `ExpressionBuilder.EagerLoadKeyedQuery.cs:156` — the only two callers of the eager-load `CollectOrderBy`, i.e. the `Default` and `KeyedQuery` strategies; both reach E-1 and E-2, which is why every obligation runs against both (searched `CollectOrderBy` across `Source/`) — covered by E-1, E-2
- `ExpressionBuilder.EagerLoadUnion.cs` — the `CteUnion` strategy does **not** call `CollectOrderBy`; it orders via `CurrentOrderBy` + `WindowFunctionHelpers.BuildRowNumber` (`:173-187`, `:333`, `:486`) (searched `CollectOrderBy|ApplyEnumerableOrderBy` in that file: 0 hits) — out-of-scope
- `Internal/DataProvider/Translation/LegacyMemberConverterBase.cs:175` — a same-named `CollectOrderBy`, unrelated symbol (window-function chain parsing), different signature; name collision only (same search) — out-of-scope
- Emitted SQL — neither edited method touches `SelectQuery`, `SqlOrderByItem` or any AST node; both build a client-side `Expression` only, so no existing baseline should move (searched both method bodies for `SelectQuery` / `OrderBy.Items`: 0 hits) — out-of-scope
- Public API — both symbols are private/`static` inside `internal partial class ExpressionBuilder`; no `PublicAPI.*.txt` or `CompatibilitySuppressions.xml` entry exists or is needed (searched both names across `Source/**/PublicAPI.*.txt`: 0 hits) — out-of-scope
- Serialized / remote shapes — no enum, no `LinqService` contract and no query-cache key participates; the change is inside preamble expression construction (searched both names across `Source/LinqToDB.Remote*`: 0 hits) — out-of-scope

## P8 Test obligations

All obligations live in the new `Tests/Linq/UserTests/Issue5935Tests.cs` (E-3), `[DataSources]` (remote
included), and each is parameterized `[Values(EagerLoadingStrategy.Default, EagerLoadingStrategy.KeyedQuery)]`
via `GetDataContext(context, o => o.UseDefaultEagerLoadingStrategy(strategy))`, because P7 shows both
strategies reach the edited code — **except TO-6, which is `Default` only** for the reason U-5 records. Fixture: `Item` / `ItemLog` local tables mirroring the issue, `Log` encoding
the `Id` order (`"line1".."lineN"`) with rows **inserted scrambled**, so natural-order retrieval is not the
expected answer.

- TO-1 `OrderByKeyNotProjected` — `Logs.OrderBy(l => l.Id).Select(l => new { l.Log }).ToArray()` inside an outer projection does not throw; discriminating input is the projection omitting `l.Id`, with TO-4's key-present sibling as the control; the red must be `InvalidOperationException: No generic method 'OrderBy' …`, not an assertion failure — proof: red→green
- TO-2 `OrderByKeyNotProjected` + `OrderByDescendingKeyNotProjected` — the returned `Log` values equal `line1..lineN` ascending and `lineN..line1` descending; the **descending** arm is the discriminating input, since a provider returning insertion or PK order answers it differently from a correct one, so "ordering silently lost" cannot pass; expected values come from P1's fixture definition, never from the first run — proof: red→green
- TO-3 `ThenByKeyNotProjected` — `.OrderBy(l => l.ItemId).ThenBy(l => l.Id).Select(l => new { l.Log })` with both keys absent, pinning that the `ThenBy` entry point into the defect is fixed too (the issue reports all four names); note it does **not** exercise the switch's `ThenBy` arm post-fix, because E-1 returns `null` before the switch runs — TO-4 is what covers that arm — proof: red→green
- TO-4 `OrderByKeyProjected` + `ThenByKeyProjected` — symmetry guard on the **unchanged** path: `.OrderBy(l => l.Id).Select(l => new { l.Id, l.Log })` and `.OrderBy(l => l.ItemId).ThenBy(l => l.Id).Select(l => new { l.ItemId, l.Id, l.Log })` still remap and still return ordered rows, green before *and* after; the `ThenBy` arm is the only obligation that reaches `ApplyEnumerableOrderBy`'s `ThenBy`/`ThenByDescending` switch arms once E-1 lands — proof: characterization
- TO-5 `OrderByThenSelectMany` plus a `Cast<object>()` variant — U-3's probe over the operators the walk crosses unremapped, both of which change the element type to something E-2's guard will reject; E-2 ships either way, so this is `red→green` for whichever operator currently reaches `:337` and `characterization` for the rest. `OfType<>` is out per SC-5 — E-2 does not skip it, so it would only re-assert today's behaviour — proof: red→green
- TO-6 `OrderByTakeKeyNotProjected` — `.OrderBy(l => l.Id).Take(2).Select(l => new { l.Log })`, the limited-detail instance of the defect, asserted for **no throw and the per-parent row count only**; ordering is deliberately *not* asserted, because U-1 shows the `ORDER BY` stays inside the APPLY/LATERAL subquery and D-1's failure mode records that gap as pre-existing and out of scope. **The one obligation NOT parameterized over both strategies — `Default` only** (see U-5): KeyedQuery has no per-key limit handling, so its row count is not the property under test here and a KeyedQuery arm would stay red after the fix for an unrelated reason — proof: red→green (it throws today, exactly as TO-1 does)

## P9 Verification gates

- G-01: pass — `worktree-test.ps1`, `Testing`/net10.0, all obligations in `Tests/Linq/UserTests/Issue5935Tests.cs`.
  **Red:** 22 failed / 10 passed on SQLite before any source edit, every failure carrying the issue's
  `InvalidOperationException: No generic method 'OrderBy(Descending)' on type 'System.Linq.Enumerable' …`
  (grepped from `red-sqlite.log`); the 10 green were exactly the key-present arms plus `CreateDatabase`, so the
  fixture discriminates. **Green:** 32/32 on SQLite and 32/32 on PostgreSQL.18 after E-1+E-2, order assertions
  included. Per obligation:
  - TO-1 `Issue5935Tests.OrderByKeyNotProjected` — red→green, red was the `InvalidOperationException`
  - TO-2 `Issue5935Tests.OrderByKeyNotProjected` + `Issue5935Tests.OrderByDescendingKeyNotProjected` — red→green, both directions asserted
  - TO-3 `Issue5935Tests.ThenByKeyNotProjected` — red→green
  - TO-4 `Issue5935Tests.OrderByKeyProjected` + `Issue5935Tests.ThenByKeyProjected` — characterization, green before *and* after
  - TO-5 `Issue5935Tests.OrderByThenSelectMany` + `Issue5935Tests.OrderByThenCast` — red→green; both were red with the same exception, which resolves U-3 by measurement and retires E-2's conditionality
  - TO-6 `Issue5935Tests.OrderByTakeKeyNotProjected` — red→green, `Default` strategy only, order deliberately unasserted
  **Regression:** 722/722 on the full `EagerLoading` filter across both providers, plus a targeted 5/5 on
  `EagerLoadingTests.TestGroupJoin` + `TestSkipTake` — the two U-4 named as depending on the client re-sort —
  confirming they still run and still pass.
- G-02: skipped — no baselines were written, so no diff exists to review. The worktree is not nested under the
  primary clone, so `TestConfiguration`'s walk-up never resolves `UserDataProviders.json` and `BaselinesPath`
  is unset for these runs (verified: nothing under `C:\GitHub\linq2db.bls` modified during the session).
  **Therefore unverified locally:** that no *existing* baseline moved. P7's emitted-SQL row is the standing
  argument that none can — `ExpressionBuilder.EagerLoad.cs` contains no reference to `SelectQuery`,
  `OrderBy.Items` or `SqlOrderByItem` anywhere in the file — and CI's baselines PR is the actual check.
- G-03: n/a — P6 touches `LinqToDB.Internal.*` only; no public surface.
- G-04: n/a — same; and API baselines are a release task, never regenerated on a feature PR.
- G-05: pass — `Source/LinqToDB/LinqToDB.csproj -c Release -f net10.0` (analyzers, 0 warnings, 43 s),
  `-f netstandard2.0` (portable TFM, 0 warnings, 38 s), and `Tests/Linq/Tests.csproj -c Release -f net10.0`
  (0 warnings, 2 m 20 s) so the new fixture meets CI's Release leg for analyzers too.
- G-06: pass — `git diff` is 1 `using`, 2 changed arms and 2 comments in one file, plus one new test file;
  no reformatting, no rename, no untouched line modified.
- G-07: pass — `git status` shows only `ExpressionBuilder.EagerLoad.cs` (M) and `Issue5935Tests.cs` (??);
  nothing under `Tests/Tests.Playground/`.
- G-09: pass — adversarial read of the diff done before proposing the PR. It caught one defect in my own
  work: the guard's comment asserted "the detail query already carries it as ORDER BY", which is the very
  claim U-1 disproved for limited details. Reworded to state the decision without the false premise.

## P10 Adjudicated

- For an **unlimited** detail, dropping the client-side re-sort leaves the ordering to the SQL `ORDER BY`
  (D-1, U-1). "The ordering is no longer applied client-side" is the fix, not a defect, and TO-2's descending
  arm pins it.
- For a **limited** detail (`Take`/`Skip`) with an unmappable key, the resulting order rests on APPLY/LATERAL
  nested-loop behaviour rather than a SQL guarantee — measured in U-1, reasoned in D-1's failure mode. This is
  **not** adjudicated as fine: it is a pre-existing gap (6.3.0 behaved the same), out of scope for a patch
  release, and is now tracked as [#5937](https://github.com/linq2db/linq2db/issues/5937) (6.6.0) with the
  root-cause fix named there. A review raising it is right; the disposition is "tracked separately".
- The `ThenBy`-prefix case is deliberately all-or-nothing (D-2); "you could have kept the first key" is
  adjudicated, not an oversight.
- Over-baselining from the new tests needs no cleanup — the release flow resets `linq2db.baselines`.

## P11 Amendments

_None._

## P12 Critic verdict

**Round 1 — `refuted`** (plan-critic on Fable). Searched: the three symbol censuses across `Source/` (matched
P7 exactly, independently re-derived), `EagerLoadUnion.cs` ordering path, `git show 6357afa67`,
`git log -S ApplyEnumerableOrderBy` (introduced in #3401 `7ec71d530`, so the re-sort predates the strategies),
`OrderBy.Items.Clear|RemoveOrderBy|MoveOrderBy|IsOrderByRequired` across `Internal/` → `SqlQueryOrderByOptimizer`,
and three `linq2db.baselines` blobs. Nothing executed.

Objections and what changed:

1. **"The detail query carries the `ORDER BY`" is false for a limited detail** — `CanRemoveOrderBy` bails on
   `IsLimited`, so `Take`/`Skip` keeps the `ORDER BY` inside the APPLY/LATERAL subquery, and the two baselines
   prove it. **Upheld** — I re-read `SqlQueryOrderByOptimizer.cs:244` and both blobs rather than take the
   claim. Consequences: U-1 re-scoped to unlimited details with the measured negative recorded; SC-2 narrowed;
   D-1 rebuilt around a 4-row shape matrix and now justified as *"no worse than 6.3.0 for exactly the shapes
   that throw today"* instead of *"loss-free"*; P10's first entry split, with the limited-detail gap recorded
   as pre-existing and **tracked**, not adjudicated away; new TO-6 pinning the limited shape's no-throw half on
   an APPLY provider. The critic's suggested remedy — throw a `LinqToDBException` for limited+unmappable — is
   **rejected** in D-1: it converts a shape that worked in 6.3.0 into a hard error, i.e. a second regression
   inside a regression fix. E-1 and E-2 stand, which the critic also concluded.
2. **E-2 gated on a single-operator probe while its rationale is per-operator** — the walk crosses `GroupBy`,
   `Join`, `GroupJoin`, `Zip`, `OfType` too. **Accepted**: E-2 is now unconditional and U-2/U-3 were rewritten
   so no edit-point depends on a probe's outcome.
3. **TO-3 cannot cover the switch's `ThenBy` arms post-fix**, because E-1 returns `null` before the switch
   runs. **Accepted**: TO-4 gains a key-present `ThenBy` arm, and TO-3's claim is corrected in place.

Not accepted from the critic's report: nothing else — its P7 re-derivation matched, and its one
**could-not-determine** (how KeyedQuery handles a per-key limited detail) is out of this plan's scope and is
noted here so a later Take-shaped obligation under `[Values(KeyedQuery)]` does not assume it.

**Round 2 — `weak`** (same critic, same model, on the revision). It re-derived all five matrix rows against the
**shipped `v6.3.0`** body of `CollectOrderBy` (`git grep … v6.3.0 --`) rather than against my reasoning, and
confirmed row 4's 6.3.0 cell — the fact the throw-rejection rests on. Four objections, all carried into the
plan, none a design change:

1. **TO-6's `KeyedQuery` arm is unprovable** — KeyedQuery has no per-key limit handling, and its `Contains`
   rewrite leaves `Take` applied to the whole filtered set, so the arm would stay red post-fix for an unrelated
   reason. **Accepted** after reading `EagerLoadKeyedQuery.cs:203-223` myself: TO-6 is `Default`-only, and the
   underlying question is recorded as U-5 (out of scope; worth a separate issue if G-01 confirms it).
2. **The matrix was missing row 5** — a `MemberInit` to the *same* entity type with the key member redefined
   binds today and re-sorts by the redefined value. **Accepted**, verified here against
   `RemapOrderByThroughSelect:255-286`: U-2's "every shape E-1 changes throws today" was too strong, and the
   correction runs in the favourable direction — E-1 *fixes* a silent mis-sort there.
3. **SC-5 claimed `OfType<>` with nothing behind it** — and `OfType` is the one operator E-2 does *not* skip
   (subclass ⇒ `IsSameOrParentOf` true). **Accepted**: dropped from SC-5/TO-5 with the reason stated, rather
   than asserting an unprobed no-throw.
4. **Nits** — E-3's obligation range, G-01's PostgreSQL rationale misattributed to TO-6, and D-3's
   `ToList`/`ToArray` argument being unreachable (`SequenceExpression` never contains the materializing call —
   verified at `ExpressionBuildVisitor.cs:2867-2873`). All four applied; D-3's rejection now stands on its
   sound reason only.

Carried forward as `weak` with the objections visible: every one was a correction to the plan's *claims*, and
the edit surface (E-1, E-2, E-3) is unchanged from round 1.
