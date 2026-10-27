# Work plan: issue-5843-compare-cache-constants-by-content — Keep the cache compare for build-time values folded out of the SQL

**Tier:** M  ·  **Status:** approved  ·  **Approved-at:** 2026-10-27 (user, after critic round 2)  ·  **Branch:** issue/5843-compare-cache-constants-by-content
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

Issue: [#5843](https://github.com/linq2db/linq2db/issues/5843) · milestone 6.6.0 · base `origin/master` 12bc7fe14. Direction chosen by the user after critic round 1 (option A: root cause in `ExpressionCacheManager`, no `EqualsToVisitor` change).

## P1 Problem

`ExpressionBuilder.BuildConstant` (`ExpressionBuilder.SqlBuilder.cs:418-477`, sole caller `ExpressionBuildVisitor.cs:3096` `HandleValue`) evaluates a client-immutable expression at build time and registers `(SqlValue, accessor)` via `RegisterSqlValue` (`:473` → `ExpressionCacheManager.cs:683-687`). `BuildQueryCacheCompareInfo` turns each registration into a build-time-vs-run-time compare, **but only if the `SqlValue` survives into the finalized statement** (`ExpressionCacheManager.cs:636-641`, `if (!sqlValues.Contains(value)) continue;`, from #4676 with no stated reason; `sqlValues` collected after `Finalize`, `ExpressionBuilder.cs:312,355-379`). A value the optimizer folded away (`true AND p.ID = 2` → `p.ID = 2`) still shaped the SQL, yet gets no compare. Its inputs then stay in the key as they are: a kept array constant compared by reference (`EqualsToVisitor.cs:304-312`), a non-scalar object constant turned into a type-only placeholder (`ExpressionCacheHelpers.cs:17-21`, `EqualsToVisitor.cs:19`), or a static member compared by member identity.

Measured on master 12bc7fe14, SQLite.MS, over `Model.Person` (probe log `.build/.agents/probe5843.txt`; each row re-run with the filter removed, all correct):

- **Wrong results, compiler-built:** `static readonly int[] _ids = {2}`; `Where(p => _ids[0] > 0 && p.ID == 2)` → `[2]`; `_ids[0] = 0` → still `[2]` (correct: empty). `static readonly Cfg _cfg` with a mutable field; `Where(p => _cfg.MutableFlag && p.ID == 2)` → `[2]`; flag set false → still `[2]`.
- **Wrong results, hand-built:** `Constant(holder).InitOnlyId > 0 && p.ID == 2` with `new Holder { InitOnlyId = 1 }` → `[2]`; a **fresh** `new Holder { InitOnlyId = 0 }` → `[2]` (correct: empty). `Constant(ids)[0] > 0 && p.ID == 2`, `ids = {2}` then `ids[0] = 0` on the same instance → `[2]`, miss delta 0.
- **#5843's rebuild:** `Constant(ids)[0] > 0 && p.ID == 2` with an equal fresh array → miss; `Constant(ids) != null && p.ID == 2` equal fresh `{1, 2}` → miss (delta 1).
- Already correct on master: values that survive into the SQL (`ArrayIndex`/`ArrayLength` compared with a column, `Contains(Constant(int[]), p.ID)`, `Select(p => Constant(int[]))`, scalar-`List<int>` `MakeIndex`/`Contains`/projection, scalar-`List<int>` `MakeIndex(...) > 0` fold) and `static readonly List<int> _list; _list.Count > 0 && …` after `Clear()` (empty).

## P2 Success criteria

- SC-1 A folded predicate over an element of a `static readonly int[]` reflects mutation of that element. → TO-1
- SC-2 A folded predicate over a mutable field of a `static readonly` object reflects mutation of that field. → TO-2
- SC-3 A folded predicate over a member of a non-scalar object constant reflects a fresh object with a different value. → TO-3
- SC-4 A folded predicate over an element of a constant array reflects same-instance mutation (empty, miss) and hits on an equal fresh array. → TO-4, TO-5
- SC-5 `Constant(ids) != null && p.ID == 2` hits on an equal fresh array; `Constant(ids).Length > 0 && p.ID == 2` hits on an equal fresh array and returns empty for an empty array. → TO-6, TO-7
- SC-6 Folds the key already covers by construction (bare kept non-collection constant, `Default`, an accessor equal to a surviving one) add no compare; restored compares in the census fixtures stay a small fraction of dropped registrations (number recorded in G-01). → TO-8, G-01
- SC-7 Shapes already correct on master stay correct and keep hitting; existing #5879 tests and the census fixtures stay green; no SQL baseline moves. → TO-9, TO-10

## P3 Constraints & anti-goals (M/L)

- No public API change; no SQL change — baselines must not move.
- `EqualsToVisitor`, `ExpressionCacheHelpers.ShouldRemoveConstantFromCache`, `IsImmutableVisitor` and `ExpressionEqualityComparer.CompareValues` unchanged.
- Do not restore compares the key covers by construction (D-2): dropped values are ~64% of registrations in the census, and 2,412 of 2,426 are bare constants, `Default` or duplicates of a surviving accessor.
- No `Issue5843` type or test names; tests in `Tests/Linq/Linq/ExpressionTests.cs` beside the #5879 constant-collection tests, `Description` links the issue.

## P4 Unknowns (M/L)

- U-1 Which shapes misbehave — resolved-by probe: P1 (15 measured shapes on master and with the filter removed).
- U-2 How many registered values are dropped today, and of what kind — resolved-by probe (census instrumentation in `BuildQueryCacheCompareInfo`, SQLite.MS over `CachingTests`, `ConstantTests`, `ParameterTests`, `ExpressionTests`, `WhereTests`, `TestQueryCache`, 509 tests): 984 builds, 3,774 registrations, 2,426 dropped (924 builds with ≥1, max 21). Dropped by kind (classified in this order): 1,078 accessor equal (`ExpressionEqualityComparer`) to a surviving one, 1,266 bare scalar constant, 68 `Default(Nullable<>)`, 8 `MemberAccess` static chain `ConstantsContainer.InnerClassReadonly.InitOnlyId`, 6 containing a collection constant. Measured with E-2 in place (G-01): 36 of 2,478 dropped registrations restored, in 32 of 1,002 builds (the inverted rule also restores static member chains and other non-constant folds).
- U-3 Does restoring compares break existing behaviour — resolved-by probe: with the filter removed entirely, the 509 census tests pass (508 + 1 skipped) and every P1 shape is correct.
- U-4 Which builder inputs are "immutable" and so reach `BuildConstant` — resolved-by critic round 2 + probe: `IsImmutableVisitor` (`ExpressionTreeOptimizationContext.cs:438-469`) admits a `static readonly` holder and does not check the leaf; `ArrayIndex`/`ArrayLength` have no override; init-only members of a constant are immutable (`:353-354,459-462`). The immutable set is not changed here (P3); D-2 makes the compare independent of it.
- U-5 Can a restored compare make every lookup miss — resolved-by reading: the compared value is the evaluated accessor (the `SqlValue`'s CLR value, a scalar for every registration in the census); `CompareValues` is opaque only for `IQueryable` (`ExpressionEqualityComparer.cs:48-49`), which `BuildConstant` cannot produce from an immutable expression (method calls are not immutable). No `IQueryable` value appeared in the census.
- U-6 Is the restored compare's build-time value safe to evaluate after `Finalize` — resolved-by probe: the filter-removed run evaluated all 2,426 dropped accessors through `evaluator.Evaluate` (`ExpressionCacheManager.cs:643`) without a failure.
- U-7 Which `MappingSchema` the D-2 predicate must use — resolved-by reading: `dc.MappingSchema`, the one `ReplaceParameterizedAndClosures` uses for the key (`ExpressionCacheManager.cs:660`), so the predicate and the key agree.

## P5 Decisions (M/L; rejected alternatives mandatory at L)

### D-1 — Restore the compare at its drop site, not at the key comparison

- **chosen:** in `BuildQueryCacheCompareInfo`, keep a `_bySqlValueCompare` entry whose `SqlValue` is absent from the final statement unless D-2 says the key covers it.
- **rejected:** content compare in `EqualsToVisitor.EqualsToX(ConstantExpression)` (plan round 1) — fixes the rebuild only; same-instance mutation, static holders and placeholder constants stay stale; bypasses `NpgsqlPath.Equals` / user collection `Equals`.
- **rejected:** remove the filter entirely — correct (U-3) but adds a compiled delegate and a per-lookup evaluation for 2,426 of 3,774 registrations (U-2), 2,412 of them already covered by the key.
- **rejected:** tighten `IsImmutableVisitor` so static-readonly leaves and array elements become parameters — changes SQL (literal → parameter) for every such query, moves baselines, and leaves the placeholder-constant shape (SC-3).
- **why this:** the folded value is what determined the SQL; comparing it also makes `PrepareExpressionAccessors` put the accessor's constants into `nonComparable`, so a kept array becomes a placeholder and stops being reference-compared.
- **failure mode of the choice:** a fold the key covers only loosely (a scalar whose `Equals` is looser than its rendering, `1.0m == 1.00m`) stays compared by the key's `Equals`, as on master.

### D-2 — Which dropped folds the key already covers

- **chosen:** skip a dropped entry iff its accessor is (a) `ExpressionEqualityComparer`-equal to the accessor of an entry that survives (that compare already exists), or (b) after `Unwrap()`, a `DefaultExpression`, or a `ConstantExpression` that `ShouldRemoveConstantFromCache(c, dc.MappingSchema)` keeps and whose value is not a non-`string` `IEnumerable` (the key compares it with `Equals`). Restore every other dropped entry. One private static predicate in `ExpressionCacheManager`.
- **rejected:** restore only accessors containing a placeholder or collection constant (plan round 2) — leaves constant-free static-holder folds stale (`_ids[0] > 0`, `_cfg.MutableFlag`; U-4, measured).
- **why this:** (a) and (b) are the only kinds whose value the key provably compares by value; everything else (member chains, array elements, binary folds over any input) is restored, so the decision no longer depends on what `IsImmutableVisitor` admits.
- **failure mode of the choice:** a restored compare over a value that cannot change (`InitOnlyId` on a static chain, 8 in the census) costs one delegate per cached query that never misses.

## P6 Edit-points

- E-1 `Source/LinqToDB/Internal/Linq/ExpressionCacheManager.cs:BuildQueryCacheCompareInfo` — the `_bySqlValueCompare` loop: drop the `sqlValues is { Count: > 0 }` guard; build the compare when the value is in `sqlValues` or `IsCoveredByCacheKey` is false; skip otherwise.
- E-2 `Source/LinqToDB/Internal/Linq/ExpressionCacheManager.cs:IsCoveredByCacheKey` — new private static D-2 predicate (`accessor`, surviving accessors, `MappingSchema`).
- E-3 `Tests/Linq/Linq/ExpressionTests.cs` — TO-1…TO-10 tests beside `HandBuiltIndexOverConstantCollection`; remove the `Probe5843_*` scratch region and its helper types.

## P7 Impact map (M/L)

- `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuildVisitor.cs:3096` `HandleValue` → `BuildConstant` — sole producer of `_bySqlValueCompare` entries (searched `\bBuildConstant\(` and `RegisterSqlValue` across `Source/`) — covered by E-1
- `Source/LinqToDB/Internal/Linq/Builder/ExpressionTreeOptimizationContext.cs:267-494` `IsImmutableVisitor` — decides which expressions reach `BuildConstant` (static-readonly holders, array elements, init-only members); unchanged, D-2 is independent of it — out-of-scope
- `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuilder.cs:352-379` `FinalizeQueryCacheInformation` — supplies `sqlValues` (post-`Finalize`, plus preambles `:367-373`); `HasConstants` gate `:357` unchanged; `sqlValues` may be null or empty while a compare is still built — covered by E-1
- `Source/LinqToDB/Internal/Linq/ExpressionCacheManager.cs:458,465-477` `ReplaceParameterizedAndClosures` — a restored compare's `PrepareExpressionAccessors` adds the accessor's constants to `nonComparable`, turning a kept array into a placeholder — covered by E-1
- `Source/LinqToDB/Internal/Linq/Query.cs:96-106` `ComparisionFunctions` → `ExpressionEqualityComparer.CompareValues` — compares the restored scalar value; unchanged — out-of-scope
- `Source/LinqToDB/Internal/Expressions/ExpressionVisitors/EqualsToVisitor.cs:19,304-312` — placeholder type-only match and reference compare of kept collections stay; with a restored compare they no longer decide a folded value — out-of-scope
- `Source/LinqToDB/Internal/Expressions/ExpressionEqualityComparer.cs:34-39` `CompareValues` summary ("a constant left in the query cache key … reference equality for a collection") — still true — out-of-scope
- `Source/LinqToDB/Internal/Linq/ExpressionCacheManager.cs:509-511` parameter entries filtered by surviving `AccessorId` — parameters are read at run time; one absent from the SQL did not shape it at build time — out-of-scope
- `Source/LinqToDB/Internal/Linq/ExpressionCacheManager.cs:616-634` `_byValueCompare` (`MarkAsValue`) — unfiltered already — out-of-scope
- `Source/LinqToDB/Internal/Linq/CompiledTable{T}.cs` / `DependentArgumentValues.cs` — compiled queries share `ExpressionBuilder`, so they get the same restored compares — covered by E-1
- `Tests/Linq/Linq/ConstantTests.cs:140-270` — static/instance member constants, readonly and init-only leaves; must stay green (U-3) — covered by E-3
- `Tests/Linq/Linq/ExpressionTests.cs:657-718` #5879 `HandBuiltIndexOverConstantCollection` / `ShouldRebuildOnMutation` — must stay green — covered by E-3
- `Tests/**` `GetCacheMissCount` assertions (296 across 33 files) — over-invalidation would show here; census fixtures run in U-3, the rest in G-01's wider run and CI — covered by E-3

Searches: scouts over the worktree (`ShouldRemoveConstantFromCache|MarkAsValue|RegisterSqlValue|NonComparableExpressions`, `GetExpressionAccessors`, `\.EqualsTo\(`, `IExpressionCacheKey`, `(Add|Set)ScalarType`, `Expression\.Constant\(`, `TryFind\(`, `ComputeChainHash`); `\bBuildConstant\(`, `_bySqlValueCompare|RegisterSqlValue|builtValues|sqlValues`, `HasConstants`, `git log -S "sqlValues.Contains(value)"` (→ b7de32bf4, #4676); critic round 2: `bool CanBeImmutable\(`, `HandleValue\(`, `static readonly (int|…)\[\] |static readonly List<` in `Tests/Linq`.

## P8 Test obligations (M/L)

Conventions embedded: `testing.md` → *Test layout* (one call per line, no `Issue<N>` names, `Tests/Model`), *Testing query cache HIT / MISS behaviour* (`[QueryCacheTest]`, miss delta from a captured baseline), *A narrowed provider set is a claim* (AllSQLite matches the provider-independent #5879 cache tests, `ExpressionTests.cs:600-602`). Static fields mutated by a test are restored in `finally`.

- TO-1 `static readonly int[]` field `{2}`; `Where(p => field[0] > 0 && p.ID == 2)` → `[2]`; `field[0] = 0` → empty (master `[2]`, measured) — providers: AllSQLite — proof: red→green
- TO-2 `static readonly` object with a mutable `bool` field `true`; `Where(p => obj.Flag && p.ID == 2)` → `[2]`; flag false → empty (master `[2]`, measured) — providers: AllSQLite — proof: red→green
- TO-3 `Where(Constant(holder).InitOnlyId > 0 && p.ID == 2)`, holder `InitOnlyId = 1` → `[2]`; fresh holder `InitOnlyId = 0` → empty (master `[2]`, measured); separates D-2's restore of placeholder-constant folds — providers: AllSQLite — proof: red→green
- TO-4 `Where(Constant(ids)[0] > 0 && p.ID == 2)`, `ids = {2}` → `[2]`; `ids[0] = 0` same instance → empty and miss delta +1 (master `[2]`, delta 0, measured) — providers: AllSQLite — proof: red→green
- TO-5 same shape, equal fresh `{2}` → `[2]`, miss delta 0 (master: miss, measured) — providers: AllSQLite — proof: red→green
- TO-6 `Where(Constant(ids) != null && p.ID == 2)`: equal fresh `{1, 2}` → miss delta 0 (master delta 1, measured) — providers: AllSQLite — proof: red→green; its `null` arm → empty is a characterization (correct on master by reference miss)
- TO-7 `Where(Constant(ids).Length > 0 && p.ID == 2)`: equal fresh → delta 0 (master value recorded in the red run); `new int[0]` → empty (separates: a compare-less mutant returns `[2]`) — providers: AllSQLite — proof: red→green
- TO-8 `Where(Constant(5) > 0 && p.ID == 2)` vs `Constant(-1)`: `[2]` then empty with a miss (the key compares the scalar); same on master; the compare-count half of SC-6 is verified by the G-01 census, not a test, since `CompareInfo` is internal with no `InternalsVisibleTo` — providers: AllSQLite — proof: characterization
- TO-9 scalar `List<int>` (`SetScalarType`) `MakeIndex(Constant(list), 0) > 0 && p.ID == 2` mutation → empty, equal fresh → hit; `static readonly List<int>` `Count > 0` after `Clear()` → empty (both measured correct on master) — providers: AllSQLite — proof: characterization
- TO-10 existing #5879 tests (`HandBuiltIndexOverConstantCollection`, `HandBuiltArrayAccess_RebuiltTreeHitsCache`, `HandBuiltIndexerProperty`, `HandBuiltArrayAccessInProjection`), `ConstantTests`, and the six census fixtures stay green — providers: AllSQLite — proof: characterization

## P9 Verification gates

- G-01: pass — `worktree-test.ps1` `ExpressionTests.Folded*|HandBuilt*` on SQLite.Classic + SQLite.MS: 52/52 green on the branch; with `ExpressionCacheManager.cs` stashed (master) on SQLite.MS: 7 failed = TO-1…TO-7 exactly (4 stale `[2]`, 3 equal-array misses; TO-7 master value = miss), TO-8/TO-9/TO-10 green. Census fixtures (6 fixtures, SQLite.MS) with E-2 + census hook: 511/512 green (1 skipped); 1,002 builds, 3,832 registrations, 2,478 dropped, **36 restored** (32 builds, max 2 per build). Hook deleted afterwards; `Source/LinqToDB` Debug net10.0 builds clean.
- G-02: — (pending) — CI baselines diff must be empty (P3)
- G-05: — (pending) — `dotnet build Source/LinqToDB/LinqToDB.csproj -c Release -f netstandard2.0` and `-f net462`
- G-06: — (pending) — diff review: only E-1…E-3 lines
- G-07: — (pending) — no `Tests/Tests.Playground` files staged; probe region and census instrumentation removed
- G-09: — (pending) — `/code-review` on the branch diff before the PR
- Release analyzers: — (pending) — `dotnet build Source/LinqToDB/LinqToDB.csproj -c Release -f net10.0` and `Tests/Linq/Tests.csproj -c Release -f net10.0`

## P10 Adjudicated (M/L)

- A kept collection constant that no accessor reaches stays reference-compared in the key (`EqualsToVisitor.cs:304-312`): its value did not shape the SQL, so an equal fresh instance only causes a rebuild, never a wrong result.
- Element-level `Equals` looseness in `CompareValues` (`decimal` scale, `DateTime.Kind`) applies to restored compares as it already does to surviving ones.
- No timing benchmark: the cost argument is the restored-compare count (U-2, re-measured in G-01), not a measured time.
- `IsImmutableVisitor` treating `static readonly` leaves and array elements as immutable (U-4) is kept: the fold is now compared, so it is correct; whether those should be parameters instead is a SQL-shape question outside this fix.

## P11 Amendments (M/L)

_None._

## P12 Critic verdict (M/L)

- Round 1 (fable, on the `EqualsToVisitor` content-compare design): **refuted**. Objections: accessor-less folds read content (`ArrayIndex > 0`, `ArrayLength > 0` optimized out at `ExpressionCacheManager.cs:640`), so the mutation hazard was live; TO-7 could not see it; D-1 omitted the root-cause option at `:640`; the probe log lacked the cited measurements; D-2's "overrides `Equals`" was underspecified. Response: probed — master returns stale `[2]` after same-instance mutation (confirmed); log re-run; user chose the root-cause option; design replaced; census added (U-2).
- Round 2 (fable, on the root-cause design with the collection/placeholder-only narrowing): **weak**. Objections: (1) constant-free `static readonly` holder folds (`_ids[0] > 0`, `_cfg.MutableFlag`, `_list.Count > 0`) would stay uncompared, and "static readonly chains cannot change" was false; (2) no obligation for the placeholder-constant clause, which on master is stale for a *fresh* object; (3) TO-4's longer-array cell could not separate, and TO-3 `null` / TO-6 were characterizations; (4) the restore count was unmeasured for the narrowed predicate; (5) the predicate must use `dc.MappingSchema`. Response: probed on master — `_ids[0]` and `_cfg.MutableFlag` stale `[2]`, `_list.Count` correct, fresh init-only holder stale `[2]`; all correct with every compare restored. D-2 inverted to "skip only what the key covers by construction" (objection 1); TO-1/TO-2/TO-3 added (1, 2); TO-7 uses an empty array, `null` arm and TO-9 labelled characterization (3); restore count re-measured in G-01 before the hook is deleted (4); U-7 pins `dc.MappingSchema` (5). Not re-dispatched: the skill caps refuted-revision at one round, and this revision answers each objection with a measurement or a rule change rather than an argument.
