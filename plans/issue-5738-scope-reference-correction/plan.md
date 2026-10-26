# Work plan: issue-5738-scope-reference-correction — scope EnsureReferencesCorrected walks to exclude pulled-up parts

**Tier:** L  ·  **Status:** approved  ·  **Approved-at:** 2026-10-26 (user, critic verdict weak, objections in P12)  ·  **Branch:** issue/5738-scope-reference-correction
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

SQO below = `Source/LinqToDB/Internal/SqlQuery/Visitors/SelectQueryOptimizerVisitor.cs`; line numbers are master `4e6f16bb3`. Probe evidence lives under the gitignored `.build/.agents/` of the primary clone; the probe tree is `C:\Worktrees\linq2db\5738-probe` (throwaway, never committed).

## P1 Problem

Building the `JoinTests.StackOverflow` shape (`Tests/Tests.Benchmarks/Benchmarks/QueryGeneration/DeepJoinChainBenchmark.cs`, SQL Server 2017 mock, query cache off, Release net10.0) does quadratic work in `SelectQueryOptimizerVisitor` (#5738). Measured with an uncommitted counter patch (`.build/.agents/5738-probe-counters.patch` lineage; outputs `5738-probe-time13/14/15.txt`, `5738-ab2.txt`):

- `SelectQueryOptimizerVisitor` visits 23,038 at depth 40 and 79,498 at depth 80 (×3.45 per doubling); all query-element visits 38,910 → 110,410.
- 95% of those visits (75,496 at d=80) come from `EnsureReferencesCorrected` (SQO:1139) re-walks: 405 walks at d=80, growing linearly, each visiting the current level's whole join list. Post-order processing merges every child into its parent first (`MoveSubQueryUp` SQO:1847, joins inserted at SQO:1971), so level L's loop re-walks the ~d−L joins pulled up from below. Visits by element at d=80: `JoinedTable` 9,963, `TableSource` 10,449, `SqlTable` 10,368, `SqlField` 20,253, `SearchCondition` 10,935, `ExprExprPredicate` 9,963; `SqlQuery` only 486.
- The 405 walks apply 488 replacement swaps in total. Per site: after `MoveSubQueryUp` (SQO:2757) 162 walks with swaps; after `OptimizeJoinSubQueries` (SQO:264) 81 walks with swaps; after a version change (SQO:296) 162 walks with zero swaps.
- Self time at d=120 (Stopwatch, fastest of 30, timers-on ≈ timers-off): `SelectQueryOptimizerVisitor` visits 41–63 ms of a 157–270 ms build — the largest single region.

## P2 Success criteria

- SC-1 On `DeepJoinChainBenchmark`, all query-element visits at d=80 are ≤ 60,000 (master 110,410) and grow ≤ ×1.75 from d=80 to d=120 (master ×1.95), measured with the counter patch applied to the branch.  → TO-1
- SC-2 Generated SQL is byte-identical to master: benchmark SQL at d=40/80/120, and CI test-all produces no changed file in its baselines PR.  → TO-2
- SC-3 The BUGCHECK guard (D-4) never fires in CI test-all, and fires under a deliberately widened scope.  → TO-3
- SC-4 The refusal path of D-3 (a pending replacement whose owner is not in the level's loop-start set forces a full walk) is reached by named existing tests, whose SQL and results match master.  → TO-4
- SC-5 The local coverage set (the 307-test SQLite.MS filter of U-1, plus `JoinOptimizeTests` on Northwind.SQLite.MS) stays green.  → TO-5

## P3 Constraints & anti-goals (M/L)

- No public API change: every new member of `SelectQueryOptimizerVisitor` is private; `SqlQueryVisitor`, `QueryElementVisitor` and `QueryHelper` are untouched.
- The set and order of optimization steps does not change; only how much of the tree a correction walk visits.
- Generated SQL unchanged for every provider and both direct and remote contexts.
- The full-tree `Replacer` at the end of `ProcessElement` (`Source/LinqToDB/Internal/SqlQuery/Visitors/SqlQueryVisitor.cs:88-105`) stays as is; it remains the backstop for every replacement.
- Not a goal: the nullability source walk, the builder `ExpandToRoot` re-walk, or timing targets (P10).

## P4 Unknowns (M/L)

- U-1 Do parts pulled up by `MoveSubQueryUp` ever hold a reference a later correction walk at that level must swap? — resolved-by probe: detect mode (master behaviour, would-be misses logged) on 307 filtered tests, SQLite.MS + LinqService: 0 B′ swap misses (`.build/.agents/5738-detect/`); positive control excluding the level's own joins too: 1,278 swap misses (`5738-control/`), so the detector can disagree. Filter: JoinTests StackOverflow/ApplyJoin/SubQueryJoin, SubQueryTests.SubSub*, AllAnyTests.Any*, ConditionalTests.CrossToOuterApply, Issue3432Tests, ElementOperationTests.Nested*, OptimizerTests, SelectQueryOptimizationTests, SelectManyTests, JoinToLimitedTests, LoadWithTests.LoadWith*.
- U-2 Do the mutating overrides that run during a walk — `VisitExistsPredicate` (SQO:3930-3966), `VisitSqlOrderByClause` (SQO:387-400), `VisitSqlNullabilityExpression` (SQO:435-444) — change a part the scoped walk skips? — resolved-by probe: `ToDebugString` before/after on every in-scope part in the U-1 census: 0 mutation misses; 639 under the positive control.
- U-3 Is it safe to skip a walk when nothing was registered since the previous walk of the same query (`_version` unchanged)? — resolved-by probe: 3 misses in the U-1 census (two correlated `TAKE 1` subqueries in `AllAnyTests`/`ElementOperationTests`, one `UNION` query) and 31 on the wider U-8 census, i.e. some steps move elements without `NotifyReplaced`. Rejected in D-2.
- U-4 Does the cost come from walks descending into nested derived tables? — resolved-by probe: only 81 derived-table bodies reached by correction walks at d=80 (41 at d=40) against 75k correction visits on join parts (`5738-probe-time14.txt`). Rejected in D-1.
- U-5 Can a BUGCHECK `throw` inside the optimizer be swallowed? — resolved-by probe: in an earlier census the builder's speculative builds caught optimizer exceptions and fell back ("Provider does not support CROSS/OUTER/LATERAL joins", "could not be converted to SQL"; `5738-census-local3.json`). The guard therefore proves the non-speculative path only; the logged census of U-1 is the evidence for the rest (P10).
- U-6 Does pooled visitor reuse leak state? — resolved-by scout: `Cleanup` (SQO:139-165) resets `_version` and friends; the new fields must be reset there too (E-1).
- U-7 Can a pulled-up APPLY body reference the merged child's output columns? — resolved-by probe: the U-1 census includes APPLY/LATERAL and correlated shapes (ApplyJoin, CrossToOuterApply, OuterApplyOptimization, Any*, Nested*) with 0 misses; a pulled-up part belongs to the child, so it references the child's sources, never the child's output columns.
- U-8 Is the D-3 refusal path reachable from the test corpus? — resolved-by probe: refusal-logging census (U-1 filter plus `JoinOptimizeTests` on Northwind.SQLite.MS, 342 tests, `.build/.agents/5738-refusal/`) logged 6 refusals, all on `LoadWithTests` shapes with a pulled-up `WEAK LEFT JOIN [MainItem] (a_Parent)` under `SubItem1`; the same run had 0 B′ misses and 31 A-rule misses. Its 3 test failures were `IndexOutOfRangeException` in the probe's own non-thread-safe region-timer arrays, not in the change.
- U-9 Is the critic's case reachable — a source merged at level q after the loop started (the re-pointed first source), or a pulled-up join flattened by `JoinMoveSubQueryUp`? — resolved-by probe: under the round-1 rule with `LATE-MERGE` / `LATE-JOINMERGE` logging, 346 tests (U-8 filter plus the critic's computed-key chain as scratch tests `Probe5738Tests.ComputedKeyChain3/4`) logged 0 late merges, 0 late join-merges and 0 B′ misses (`.build/.agents/5738-reach/`). Round 2 pointed out that those tests projected the key at the top, which blocks the late merge; the key-less variant `ComputedKeyChain3NoKey` under the round-1 rule also logged 0 late merges and 0 misses (`5738-round2/old-probe/`, 7 tests, positive scoped-walk counter present). The case remains unreached; no test reddens the old rule.
- U-10 Do the D-3 refusal clauses have a red arm in the corpus? — resolved-by probe: with the owner test removed (always scope when there are pulled-up parts), the U-1 filter plus `Probe5738Tests` — 313 tests on SQLite.MS + LinqService, all green — logged 0 B′ misses and the positive counter (about 2,500+ scoped walks; `5738-round2/noowner-u1/`); the earlier 86-test run (`5738-rules/detect-noowner/`, `LoadWith*` plus scratch) agreed. The 6 `LoadWithTests` refusals are conservative, not necessary.
- U-12 Is the wrap → unwrap route reached on a provider that takes it (`!IsSubQueryOrderBySupported`: Access, DB2, Informix, SAP HANA)? — resolved-by probe: U-1 filter on Access.Ace.OleDb, 245 tests green under both the round-1 and the final rule, 0 late merges, 0 misses, positive counter present (`5738-round2/new-u1-access/`, `old-u1-access/`). DB2, Informix and SAP HANA were not run locally; D-4 covers them on CI.
- U-11 Does the change save time, not only visits? — resolved-by probe: `time-deepjoin` (Stopwatch, fastest of 30), two runs each on a quieter box: build total d=80 master 48.7 / 59.0 ms → B′ 40.1 / 40.3 ms; d=120 97.1 / 90.9 → 81.0 / 80.1; `SelectQueryOptimizerVisitor` visit self time d=120 23.4 / 19.0 → 5.3 / 10.6 (`.build/.agents/5738-rules/time-*.txt`).

## P5 Decisions (M/L; rejected alternatives mandatory at L)

### D-1 — Scope correction walks to exclude parts pulled up into the level

- **chosen:** while a level's fixpoint loop runs, remember the joins and extra FROM tables `MoveSubQueryUp` moved into it (SQO:1971, 1992). A correction walk of that level skips them when D-3 allows. Measured (B′ in `5738-ab2.txt`): visits at d=80 110,410 → 52,090, d=120 215,510 → 84,830 (×1.63 per 1.5× depth), SQL identical, 0 detect misses.
- **rejected:** skip nested derived-table bodies in the walk — the walks barely reach any (U-4), so no gain.
- **rejected:** a reverse-reference index (who references X) — no such structure exists (scout: every `QueryHelper` dependency helper is a full walk), and building one touches `SqlQueryVisitor`, against P3.
- **rejected:** drop the in-loop walks and rely on the final `Replacer` — later steps in the same loop read the tree by reference and need corrected references: `ResolveWeakJoins` `IsDependsOnSources` (SQO:1205-1206), `CountUsage` (SQO:3569), `IsAllowedToMove` (SQO:1836), `IsDependsOn` (SQO:2673), `CollectDependencies(_rootElement)` (SQO:3180, 2935), `CorrectColumnNesting` (SQO:3348).
- **why this:** a pulled-up part was a child's internals; it can only reference that child's sources, so the child's output columns and `All` (the elements `MoveSubQueryUp` replaces, SQO:1952/1968) cannot occur in it.
- **failure mode of the choice:** a future step that moves an element referencing a current-level replaced element into a pulled-up part, without `NotifyReplaced`, would leave a stale reference until the final `Replacer`. D-4 makes that loud on CI.

### D-2 — Do not skip walks on an unchanged version

- **chosen:** every scheduled correction walk still runs (scoped or full).
- **rejected:** skip a walk when the same query's `_version` is unchanged since its last walk — saves 162 walks at d=80 (52,090 → 46,175 visits combined with D-1) but missed 3 real changes in the U-1 census (U-3).
- **why this:** D-1 alone is near linear; the extra 11% is not worth an unsound rule.
- **failure mode of the choice:** the 162 no-swap walks stay, at scoped (cheap) size.

### D-3 — When a walk may be scoped

- **chosen:** when a level's loop starts, record its direct sources — the `Source` of every FROM table and of every (nested) join table, not their bodies. `NotifyReplaced` records, per registration, the owner of the replaced element (`SqlColumn.Parent` or `SqlField.Table`) and the level it was registered under (the looping query, or the parent for the pre-loop `OptimizeColumns`, SQO:234). Each merge also removes from that loop-start set every source a pulled-up part can reference: the sources of the pulled-up joins and FROM tables, and the child's first source re-pointed into q's table source when it brings joins with it (SQO:1973). That covers a wrap → unwrap (`MoveTablesToSubQuery` / `MoveDuplicateUsageToSubQuery` then `MoveSubQueryUp`), which returns q's own original joins as pulled-up parts. A walk of level q is scoped only if every registration still pending is owned by q itself (its references live above q), or was registered during q's loop and is owned by a source still in q's loop-start set. Anything else forces a full walk: an unknown owner, a registration made outside any loop (`directOf` null), a registration from a deeper level, and any owner that arrived during the loop — the merged child's first source re-pointed into q (SQO:1973) and merged again by the `--i` retry (SQO:2759), a pulled-up join flattened by `JoinMoveSubQueryUp` (SQO:2722-2723), a pulled-up weak join removed by `ResolveWeakJoins` (SQO:1260), a source wrapped by `MoveDuplicateUsageToSubQuery`/`MoveTablesToSubQuery`. After a scoped walk, the registrations made under q are dropped from the pending list; after a full walk, all except those owned by q.
- **rejected:** owner is any direct source of q that was not pulled up (round-1 rule) — the critic showed it accepts the merged child's first source X, which every pulled-up ON condition references (refuted, P12). Measured: no late merge occurred anywhere in the censuses (U-9, U-12), so no test reddens the old rule; the loop-start rule closes the case by construction at zero measured cost (identical benchmark visits, 0 refusals).
- **rejected:** loop-start set without removal on merge (round-2 rule) — the critic showed a wrap → unwrap returns q's original joins as pulled-up parts while their sources stay in the set (weak, P12). Not reached in the censuses either (U-12); the removal costs nothing measurable (`5738-round2/ab-deepjoin.txt`: B′ visits unchanged, 0 refusals).
- **rejected:** scope unconditionally after `MoveSubQueryUp` only — misses the 81 swapping walks after `OptimizeJoinSubQueries`, leaving the visits quadratic (`5738-ab1.txt`: B at the post-merge site only, 90,970 at d=80).
- **why this:** every in-loop `NotifyReplaced` site replaces a column or the `All` field of a direct source of the looping query (all nine sites: SQO:1260, 1755, 1952, 1968, 2713, 2790, 2852, 3241, 3884; re-read by the critic), and a loop-start direct source of q is either the child being merged — whose output columns pulled-up parts cannot reference — or a sibling that a non-lateral FROM child cannot reference.
- **failure mode of the choice:** refusing too often makes the change a no-op for a shape — measured 0 refusals on the benchmark and 6 on the census (U-8). The refusal clauses are safety nets, not proven necessary: dropping the owner test entirely produced no miss on 313 SQLite tests (U-10), no deeper-level registration survives a level's last walk (critic's reading of the pruning rule), and the late-merge and wrap → unwrap cases they close were not reached (U-9, U-12). No test can therefore turn red on them; D-4 is what would catch a violation on CI.

### D-4 — A BUGCHECK guard instead of a BUGCHECK full walk

- **chosen:** under `#if BUGCHECK` (Debug, Testing and Azure — `Source/LinqToDB/LinqToDB.csproj:17-20`, i.e. every CI test leg), a scoped walk checks each skipped part with `Find` for an element that has a pending replacement and throws `InvalidOperationException` if one exists. It follows the precedent at `Source/LinqToDB/Internal/SqlProvider/OptimizationContext.cs:132-154`.
- **rejected:** under BUGCHECK, walk the skipped parts anyway and compare `ToDebugString` — that turns CI back into master behaviour, so the shipped skip path would go untested.
- **why this:** CI keeps exercising the skip path while the premise of D-1 is checked across every provider.
- **failure mode of the choice:** it cannot see a mutation-type divergence (U-2, measured locally only), and a throw in a speculative build can be swallowed (U-5).

## P6 Edit-points

- E-1 `Source/LinqToDB/Internal/SqlQuery/Visitors/SelectQueryOptimizerVisitor.cs:fields+Cleanup` — level state (looping query, loop-start source set, pulled-up parts and their sources, pending registrations), reset in `Cleanup` (SQO:139).
- E-2 `Source/LinqToDB/Internal/SqlQuery/Visitors/SelectQueryOptimizerVisitor.cs:NotifyReplaced` — record owner and registering level before `++_version` (SQO:168).
- E-3 `Source/LinqToDB/Internal/SqlQuery/Visitors/SelectQueryOptimizerVisitor.cs:VisitSqlQuery` — set and restore the level state around the fixpoint loop (SQO:237-304), including the loop-start direct-source set of D-3, and the registering level around `OptimizeColumns` (SQO:234).
- E-4 `Source/LinqToDB/Internal/SqlQuery/Visitors/SelectQueryOptimizerVisitor.cs:MoveSubQueryUp` — record the joins and FROM tables moved into the parent (SQO:1971, 1992) and the re-pointed first source (SQO:1973), and remove their sources from the loop-start set.
- E-5 `Source/LinqToDB/Internal/SqlQuery/Visitors/SelectQueryOptimizerVisitor.cs:EnsureReferencesCorrected` — D-3 decision, scope for the walk, pending-list pruning (SQO:1139).
- E-6 `Source/LinqToDB/Internal/SqlQuery/Visitors/SelectQueryOptimizerVisitor.cs:VisitSqlJoinedTable+VisitSqlTableSource` — return a skipped part unvisited during a scoped walk; D-4 guard (SQO:174, 355).

## P7 Impact map (M/L)

- `SQO:252, 258, 264, 270, 296, 2757, 3347` — every `EnsureReferencesCorrected` caller; each passes the looping query — covered by E-5
- `SQO:1260, 1755, 1952, 1968, 2713, 2790, 2852, 3241, 3884` — every `NotifyReplaced` site reaching SQO's map; old element is a column or `All` of a direct source, or (3241) of the current query — covered by E-2
- `SQO:2921 QueryHelper.WrapQuery`, `SQO:2943, 3188 _rootElement.Replace` — replacements outside SQO's map; they never enter the pending list or `_version` — out-of-scope
- `SQO:387-400, 435-444, 3930-3966` — mutating overrides no longer run on skipped parts in a scoped walk — covered by E-6 (U-2 measured)
- `SQO:1205-1206, 1836, 2673, 3180, 2935, 3348, 3569` — readers after a correction that search by reference; they see a stale reference only if a skipped part held a pending replacement — covered by E-6 (D-4 guard)
- `Source/LinqToDB/Internal/SqlQuery/Visitors/SqlQueryVisitor.cs:88-105` — final `Replacer` over the whole tree, unchanged — out-of-scope
- `SQO:215, 333` — `_parentSelect` left pointing at the last nested query after a walk (scout); a scoped walk visits fewer queries, readers SQO:213/3218/3221 do not run inside a walk — out-of-scope
- `SQO:139-165 Cleanup` — pooled-visitor reset — covered by E-1
- `SQO:1973 tableSource.Source = subQueryTableSource.Source`, `SQO:2759 --i` retry, `SQO:2722-2723 JoinMoveSubQueryUp` re-point — sources that become direct sources of q during its loop; pulled-up parts reference them — covered by E-3 (loop-start set) and E-5 (refusal)
- `MoveDuplicateUsageToSubQuery` / `MoveTablesToSubQuery` (SQO:3608-3621, 3628-3675) — wrap sources into a new subquery during the loop; the new subquery is not a loop-start source, so its registrations refuse scoping — covered by E-5
- wrap → unwrap (`MoveToSubQuery` SQO:3818 on `!IsSubQueryOrderBySupported` providers, `MoveDuplicateUsageToSubQuery` SQO:3763/3804) — the unwrap's `MoveSubQueryUp` returns q's original joins and first source as pulled-up parts; their sources leave the loop-start set — covered by E-4
- `EnsureReferencesCorrected` callers outside SQO — Localized — searched `EnsureReferencesCorrected` across `Source/`, only SQO (private method); no other `SqlQueryVisitor` subclass affected.
- Public surface — Localized — searched new member names against `Source/LinqToDB/PublicAPI.*.txt`; all new members private, no `PublicAPI.Unshipped.txt` entry.
- `Tests/Linq/Linq/JoinTests.cs:1073 StackOverflow` — writes the 101-level SQL to baselines (`BaselinesManager.LogQuery`, `JoinTests.cs:1092`) — covered by E-5 (TO-2 baselines)

## P8 Test obligations (M/L)

- TO-1 With the counter patch applied to the branch (uncommitted), `DeepJoinChainBenchmark` `ab-deepjoin`/count mode reports all query-element visits at d=80 ≤ 60,000 and d=120/d=80 ≤ ×1.75; master reports 110,410 and ×1.95. Discriminating input: depth 80 vs 120 of the same chain — providers: SQL Server 2017 mock (benchmark) — proof: red→green
- TO-2 Benchmark SQL at d=40/80/120 byte-identical to master; CI test-all baselines PR for the branch contains no changed file (`JoinTests.StackOverflow` included) — providers: all CI test-all providers, direct and remote — proof: characterization (proves no SQL change, no new behaviour)
- TO-3 D-4 guard: CI test-all (Azure config, BUGCHECK on) green; locally, widening the scope to the level's own joins (mutation: the `PROBE5738_CONTROL_B` scope in the probe tree) makes the guard throw on the U-1 filter — providers: all CI providers; SQLite.MS for the control — proof: control
- TO-4 The `LoadWithTests` cases that reach the D-3 refusal (U-8: pulled-up weak `a_Parent` join under `SubItem1`) pass on the branch with SQL equal to master; before implementation a probe run with the test name in each refusal log line pins the exact methods, and they are listed here by amendment. This is reachability only: U-10 measured that these refusals are not necessary, so no mutant of the owner test can turn red on them — providers: SQLite.MS — proof: characterization (+ reachability probe)
- TO-5 The U-1 filter (307 tests, SQLite.MS + LinqService) plus `JoinOptimizeTests` (Northwind.SQLite.MS) green on the branch — providers: SQLite.MS, Northwind.SQLite.MS — proof: characterization

## P9 Verification gates

- G-01: — (pending)
- G-02: — (pending)
- G-05: — (pending)
- G-06: — (pending)
- G-07: — (pending)
- G-08: — (pending)
- G-09: — (pending)

## P10 Adjudicated (M/L)

- Timing is not a success criterion: the box often runs at ~100% CPU (vmmem), wall-clock medians scattered 2–4× across runs and a cycle-counter clock cost ~48k cycles per call; deterministic visit counts are the criterion (SC-1). Timings are reported for information only (U-11).
- SC-1 holds for Release builds only. Under BUGCHECK (Debug, Testing, Azure) the D-4 guard runs `Find` over every skipped part on every scoped walk, so those builds keep master's quadratic visit profile on the benchmark; TO-1 is measured in Release.
- The D-4 guard does not cover a throw swallowed by a speculative build (U-5) or a mutation-type divergence (U-2); both are covered by the logged local census only.
- The 162 zero-swap walks after a version change are kept (D-2).

## P11 Amendments (M/L)

_None._

## P12 Critic verdict (M/L)

- Round 1 (plan-critic, fable, 2026-10-26): **refuted**. Objections: (1) the D-3 owner set accepted the merged child's first source X (re-pointed at SQO:1973, referenced by every pulled-up ON condition) and pulled-up joins re-pointed by `JoinMoveSubQueryUp` (SQO:2722-2723), so a later merge of X at the same level would leave stale references in skipped parts; (2) U-1/U-7 were closed by a corpus sweep without a computed key carried across three levels; (3) no obligation per D-3 clause — the owner-test mutant was unwritten and the deeper-level clause cannot be reddened; (4) SC-1 holds in Release only. Searched: all nine `NotifyReplaced` sites (claim holds), `IsMovingUpValid` SQO:2091-2571 and `JoinMoveSubQueryUp` SQO:2573-2732 for parent-scoped predicates, `SelectQueryExtensions.IsSimple`, `QueryElementVisitor` select-clause visits and `SqlQueryFindVisitor` (the 3884 shape does not false-positive the guard), BUGCHECK in csproj and both CI configs (now verified), the probe diff and the misses files. Strongest point it named: the detect/control pair and the BUGCHECK guard can say no. What changed: objection 1 probed before accepting — the critic's shape and every late merge are unreachable in the 346-test census (U-9), and D-3 now admits only loop-start direct sources, closing the case by construction at zero measured cost; objection 3 probed — the owner-test mutant produced no miss (U-10), so the clauses are recorded as safety nets and TO-4 says it proves reachability only; objection 4 recorded in P10; U-11 added the time measurement.
- Round 2 (same critic, 2026-10-26): **weak**. Objections: (1) U-9's scratch tests projected the key at the top, which blocks the late merge, so "unreachable" was unsupported — a key-less variant should redden the round-1 rule; (2) a same-level wrap → unwrap (`MoveTablesToSubQuery` / `MoveDuplicateUsageToSubQuery`, then `MoveSubQueryUp`) returns q's original joins as pulled-up parts while their sources stay in the loop-start set — fix: remove pulled-up and re-pointed sources from the set; reachable on Access/DB2/Informix/HANA and via the SQLite OUTER APPLY dedupe route; (3) U-10's census was 86 tests, not the U-1 filter, the no-owner run had no positive counter, and two LinqService `LoadWith` cases had failed on gRPC in that run; nits on E-1, SC-4 and the `directOf` null case. Searched: the revised prototype against all nine registration sites (round-1 class closed by construction), the three wrap sites and their callers, `IsMovingUpValid` for a clause blocking a clause-only unwrap (none), the provider flags gating the routes, `QueryElementVisitor`/`SqlQueryFindVisitor` (no guard false positive). Strongest point it named: the loop-start rule keys safety on the level before any merge. What changed: (2) adopted in D-3/E-4 plus a P7 row; (1) probed — the key-less variant reaches no late merge under the round-1 rule either (U-9), so the case stays unreached and untestable; (3) re-run on 313 SQLite tests with a positive counter, all green including the LinqService `LoadWith` cases (U-10), plus an Access.Ace.OleDb leg (U-12); nits applied. Cap reached: no round 3, the `weak` verdict stands with these objections visible.
