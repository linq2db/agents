# Work plan: issue-5911-skip-redundant-optimizer-passes — Skip the root whole-tree expression pass after the first fixpoint iteration

**Tier:** L  ·  **Status:** approved  ·  **Approved-at:** 2026-10-24 (E-1, E-2, E-3; TO-1…TO-6; critic round 2 weak, folded in)  ·  **Branch:** issue/5911-skip-redundant-optimizer-passes
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

## P1 Problem

#5911: a query build runs the whole-tree expression optimizer five times. `SelectQueryOptimizerVisitor.Optimize` (`Source/LinqToDB/Internal/SqlQuery/Visitors/SelectQueryOptimizerVisitor.cs:51-130`) runs a fixpoint loop that always takes at least two iterations (`:100-104` forces the second), and every iteration's `ProcessElement` → `VisitSqlQuery` runs a root-level `_expressionOptimizerVisitor.Optimize(..., visitQueries: true)` at the top (`:223`) and again at the bottom (`:314`). In iteration ≥2, the `:223` pass re-optimizes a tree the previous iteration's `:314` already optimized, separated only by `OptimizeColumns` / `UnnestJoins` / `OptimizeOrderBy` (`:98-117`).

measured (#5911 probe, this worktree, uncommitted instrumentation; SQLite.MS; 628 tests — CteTests, ConcatUnionTests, SetOperator*Tests, JoinTests, JoinOptimizeTests, LeftJoinTests — 625 passed, 3 skipped; two identical runs, zero `ToDebugString` render failures): of 3,472 root-level, non-CTE `:223` passes in iteration ≥2, **0** changed the tree's `ToDebugString()` once `[UID:n]` is stripped; 19 changed UIDs only (the concat fold's literal churn, fixed separately on `issue/5911-concat-fold-churn`). This includes 1,088 passes where the previous iteration reported a change (1,073 with the tree changed since `:314`) and 238 after a `:326` set-operator re-entry. Control: iteration-1 `:223` changed semantics in 3,129 of 3,468 passes, CTE-body passes in 100 of 326 — the comparison detects real change. Posted: https://github.com/linq2db/linq2db/issues/5911#issuecomment-6388836289.

Falsifiable statement: on master the iteration-≥2 root `:223` pass runs (3,472 times on the corpus) and does no semantic work there.

## P2 Success criteria

- SC-1 No `:223` pass (root-level or CTE body) runs in fixpoint iteration ≥2: probe count 0 on the corpus (master: 4,273 root + 166 CTE, U-6), and a committed BUGCHECK-counter test pins it. → TO-1, TO-6
- SC-2 Generated SQL is byte-identical to master on the probe corpus, SQLite.MS, captured locally A/B. → TO-2
- SC-3 CI `test-all` on the PR has no test failing that passes on master **and** the PR's `linq2db.baselines` branch has no diff against baselines master. Both halves are needed: `BaselinesManager.Dump` writes nothing for a failed test (`Tests/Base/BaselinesManager.cs:37-41`), so a newly throwing test is invisible to the baselines diff alone. → TO-3
- SC-4 Every iteration-1 `:223` still runs, root and CTE body: probe counts of `iter1` and `cte-iter1` equal master's on the widened corpus (4,269 and 166, U-6). → TO-4
- SC-5 Query translation of `DeepJoinChainBenchmark` at depth 100 (cache disabled) is not slower than master; expected faster. → TO-5

## P3 Constraints & anti-goals (M/L)

- No change to generated SQL on any provider; no baselines delta.
- `_isColumnsOptimized` keeps its meaning and its readers (`:3293` `OptimizeApplyJoin` gate, `:3304` `processMultiColumn:`) see the same value at the same time as on master — the forced second iteration stays (#5911: it is load-bearing).
- `:314` passes are unchanged — not measured, not in scope.
- `OptimizationContext.cs:130` (`OptimizeAndConvertAll`) pass is unchanged — out of scope.
- No public API change (`SelectQueryOptimizerVisitor` is `Internal.*`; no signature changes). The E-2 counters exist only under `#if BUGCHECK`, which Release does not define, so they ship nowhere and need no `PublicAPI.*.txt` entry — the same arrangement as `QueryCache.cs:1074-1099`.
- The probe instrumentation is not part of the change: it is saved as a patch under `.build/.agents/` and reverted before implementation.

## P4 Unknowns (M/L)

- U-1 Is the probe corpus representative beyond SQLite? — resolved-by design: not claimed. SC-3 / TO-3 (CI matrix baselines) is the gate; the probe is the reason to try, not the proof.
- U-2 `ToDebugString` does not render a `SqlValue`'s `ValueType` (`SqlValue.cs:51-69`), so a pass that only retypes nodes reads as "no change". — resolved-by design: SC-2 / SC-3 compare emitted SQL, where a retyped literal or cast is visible; the probe count is not used as proof of equivalence.
- U-3 Is `_isColumnsOptimized` exactly "fixpoint iteration ≥2" at every `VisitSqlQuery`? — resolved-by scout: searched `_isColumnsOptimized` in the file — 8 hits. Assigned only at `:82` (reset at entry), `:90` (reset before the loop), `:103` (set `true` after iteration 1's `ProcessElement` and `OptimizeColumns`), `:158` (`Cleanup`); the other hits are the declaration `:38` and the readers `:3293`, `:3304`. It is `false` throughout iteration 1's `ProcessElement` and `true` for every later one.
- U-4 Which callers run `SelectQueryOptimizerVisitor.Optimize`, and does each reach the loop? — resolved-by scout: searched `SelectQueryOptimizerVisitor|OptimizeQueries\(` across `Source/LinqToDB`: `BasicSqlOptimizer.OptimizeQueries` (`BasicSqlOptimizer.cs:2473-2487`) called from `Finalize` (`:64`) and the update/delete rewrites (`:1210,1425,1482,1507,1607,2008,2051`, `SqlServerSqlOptimizer.cs:133`), and `ExpressionBuilder.SqlBuilder.cs:207` (validity check on a cloned subquery). All use the pooled visitor (`QueryHelper.cs:44-45`) and the same loop; the probe instrumented the visitor, so every caller was in the measured population.
- U-6 Are CTE-body passes in iteration ≥2 also no-ops, and does the result hold with DML and the AST-shape fixture? — resolved-by probe (2026-10-24, critic round-1 lead): CTE category split by iteration, corpus widened to 979 tests (adds `SelectQueryOptimizationTests`, `xUpdate.UpdateTests`, `xUpdate.InsertTests`; 976 passed, 3 skipped), concat fix applied. `cte-iter1` 166 passes / 102 semantic; **`cte-iterN` 166 / 0 changed**; `iter1` 4,269 / 3,551 semantic; `iterN-signalled` 1,106 / 0 (1,091 tree changed since `:314`); `iterN-afterReentry` 243 / 0; `iterN-unsignalled` 2,924 / 0 (154 tree changed since `:314`). Every CTE semantic change is in iteration 1; executed iteration-≥2 `:223` passes on master's loop: 4,273 root + 166 CTE.
- U-5 Is "root, non-CTE" exactly `saveParent == null && _currentCteClause == null`? — resolved-by scout: `VisitCteClause` (`:3909-3928`) sets `_parentSelect = null` and `_currentCteClause = element` for the CTE body and restores both; the `:326` re-entry runs with `_parentSelect == selectQuery` (`:230`), so it never reaches `:223`. The probe's categories used exactly this predicate.

## P5 Decisions (M/L; rejected alternatives mandatory at L)

### D-1 — Skip the `:223` pass in iteration ≥2 unconditionally, root and CTE body alike (user-chosen form "a", widened to CTE bodies by the user after U-6, 2026-10-24)

- **chosen:** guard the `:223` call with `!_isColumnsOptimized`, so every query that reaches it — statement-level roots and CTE bodies — skips it once iteration 1 is done.
- **rejected:** skip only when the previous iteration reported no change (#5911's proposed form) — needs two missing change signals added (`SqlQueryOrderByOptimizer.cs:103-109`, `SqlQueryColumnOptimizerVisitor.cs:308-323`) plus the `:326` re-entry treated as a change; the probe found the pass a semantic no-op *with* signals as well (1,088 passes), so the extra state buys nothing measured.
- **rejected:** skip `:314` instead — it runs right after the iteration's structural rewrites; never measured as a no-op.
- **rejected:** keep CTE bodies unconditional (the form first approved) — U-6 measured `cte-iterN` 166 / 0 changed; every CTE semantic change is in iteration 1.
- **rejected:** a `BUGCHECK` verification that still runs the skipped pass and throws on change — CI's `Azure` configuration defines `BUGCHECK` (`Tests/Directory.Build.props:13-14`), so CI would then exercise the non-skipping path and its baselines would no longer measure the change; running it on a clone instead costs a whole-tree clone per iteration in every CI test.
- **why this:** smallest change the measurement supports; no new state; the gate is a phase the visitor already tracks.
- **failure mode of the choice:** a query shape outside the corpus needs expression optimization of a node that `OptimizeColumns` / `UnnestJoins` / `OptimizeOrderBy` produced, before iteration ≥2's structural rewrites read it (`OptimizeSubQueries`, `OptimizeJoins`, … `:244-291`). Iteration ≥2's own `:314` still optimizes it before the loop ends, so the exposure is a structural rewrite that would have fired on an optimized predicate and does not, or that trips on an unfolded predicate. Three visible forms: a SQL diff; an exception during the build; and a flipped `IsValidQuery` verdict from the build-time caller (`ExpressionBuilder.SqlBuilder.cs:199-225`, consumed at `:217`), which changes the build strategy or throws `LinqToDBException`. TO-3 covers all three (failures and baselines). Structural backing, from the critic's read: between `:314`(k) and `:223`(k+1) the only new nodes are `SqlValue(1)` dummy columns (`SqlQueryColumnOptimizerVisitor.cs:543-552`), ORDER BY items re-using already-optimized expressions (`SqlQueryOrderByOptimizer.cs:159-168`), CTE field sync, and `UnnestJoins` INNER→LEFT / CrossApply→OuterApply flips under a LEFT parent (`JoinsOptimizer.cs:127-133`), which the nullability calculator already treated as nullable (`NullabilityContext.cs:335-338`). No fold becomes newly available.

### D-2 — Gate on `_isColumnsOptimized`, not a new iteration counter

- **chosen:** reuse `_isColumnsOptimized` (U-3: it is exactly "iteration ≥2").
- **rejected:** a dedicated `_iteration` field — a second piece of loop state that must be kept in step with the first in `Optimize` and `Cleanup`.
- **why this:** the existing flag already names the phase, and its readers are unchanged.
- **failure mode of the choice:** a later change to when `_isColumnsOptimized` flips also moves the skip. One comment line at the guard says the skip is keyed on that phase.

### D-3 — Pin the skip with a BUGCHECK pass counter and a committed test (user decision, 2026-10-24, after critic round-1 objection 5)

- **chosen:** three `#if BUGCHECK` instance counters on `SelectQueryOptimizerVisitor`, reset in `Optimize` beside `_isColumnsOptimized` (`:82`): `FirstIterationPassesReached` and `LaterIterationPassesReached`, incremented at the `saveParent == null` block **before** the guard, split by `_isColumnsOptimized`; and `ExpressionPassesExecuted`, incremented inside the guard immediately before the call. (Round 2: a phase counter placed inside the guard is unreachable for iteration ≥2 by construction.) A test runs a fresh `SelectQueryOptimizerVisitor` over a clone (`QueryVisitorExtensions.Clone`, `QueryVisitorExtensions.cs:183-192`) of a built CTE statement and reads the counters.
- **rejected:** probe-only evidence (the plan's first P10) — leaves the skip unguarded against a later edit that removes the guard; `QueryCache.cs:1074-1099` shows BUGCHECK test diagnostics are an accepted pattern, consumed by `QueryCacheEvictionTests.cs:1`.
- **rejected:** static or `[ThreadStatic]` counters — the visitor is pooled (`QueryHelper.cs:44-45`) and tests run in parallel; an instance the test constructs itself is isolated by construction.
- **rejected:** counting inside `SqlExpressionOptimizerVisitor.Optimize` — it is shared by every call site (`:314`, `:3898`, `OptimizationContext`), so the count would not isolate `:223`.
- **why this:** the counter is where the decision is, it costs nothing in Release, and the test needs no database.
- **failure mode of the choice:** a regression that runs the pass from a second, uncounted call site is invisible to the counters. Every other regression of the guard moves `ExpressionPassesExecuted` away from `FirstIterationPassesReached`: removing it makes executed = first + later, and over-skipping makes executed < first.

## P6 Edit-points

- E-1 `Source/LinqToDB/Internal/SqlQuery/Visitors/SelectQueryOptimizerVisitor.cs:VisitSqlQuery` — guard the `:223` `_expressionOptimizerVisitor.Optimize` call with `!_isColumnsOptimized` per D-1 (the `saveParent == null` block keeps its DEBUG `before` capture).
- E-2 `Source/LinqToDB/Internal/SqlQuery/Visitors/SelectQueryOptimizerVisitor.cs:Optimize,VisitSqlQuery` — `#if BUGCHECK` counters per D-3: three `public int` properties, reset in `Optimize`, the two phase counters before the guard and the executed counter inside it.
- E-3 `Tests/Linq/Linq/SelectQueryOptimizationTests.cs` — TO-6, with only the new test method inside `#if BUGCHECK`; the file's three existing ungated tests (`:17`, `:36`, `:60`) stay ungated.

## P7 Impact map (M/L)

- `SelectQueryOptimizerVisitor.cs:3293,3304` readers of `_isColumnsOptimized` — searched `_isColumnsOptimized` in the file (8 hits); no assignment added or moved — out-of-scope
- `BasicSqlOptimizer.cs:64,1210,1425,1482,1507,1607,2008,2051`, `SqlServerSqlOptimizer.cs:133`, `ExpressionBuilder.SqlBuilder.cs:207` — every caller of the visitor's `Optimize` (searched `SelectQueryOptimizerVisitor|OptimizeQueries\(` across `Source/LinqToDB`); all reach the loop and get the skip — covered by E-1
- `SelectQueryOptimizerVisitor.cs:3909-3928` `VisitCteClause` — CTE bodies enter with `_parentSelect == null` and get the same guard as roots; `_isColumnsOptimized` is visitor-wide, so a CTE body visited in iteration ≥2 is skipped too — covered by E-1
- `Tests/Linq/Linq/QueryCacheEvictionTests.cs:1`, `Source/LinqToDB/Internal/Linq/QueryCache.cs:1074-1099` — precedent for `#if BUGCHECK` test diagnostics on a public `Internal.*` type (searched `#if BUGCHECK` in `Source/LinqToDB` and `Tests/Linq`: `QueryCache.cs`, `OptimizationContext.cs:132,142`, `SqlSelectClause.cs`, `SqlPlaceholderExpression.cs`, `Linq/Expressions.cs`) — covered by E-2, E-3
- `SelectQueryOptimizerVisitor.cs:326-331` set-operator re-entry — never reaches `:223` (U-5) — out-of-scope
- `SelectQueryOptimizerVisitor.cs:3898` column-expression optimize (`visitQueries: false`) — a different call site, not touched — out-of-scope
- `OptimizationContext.cs:130` `OptimizeAndConvertAll` whole-tree pass — not touched — out-of-scope

## P8 Test obligations (M/L)

- TO-1 Re-apply the saved probe patch (`.build/.agents/probe5911-visitor.patch`, `Probe5911.cs.saved`) on top of E-1, with `Record` moved **inside** E-1's guard so it counts *executed* passes (placed after the guarded call it would log every skipped pass as `changed=False`), and run the corpus (CteTests, ConcatUnionTests, SetOperator*Tests, JoinTests, JoinOptimizeTests, LeftJoinTests, SelectQueryOptimizationTests, xUpdate.UpdateTests, xUpdate.InsertTests): executed `iterN-*` and `cte-iterN` counts 0 (master: 4,273 and 166, U-6). — providers: SQLite.MS — proof: red→green
- TO-2 Local A/B SQL capture on the same corpus, into two **fresh, empty** `BaselinesPath` directories (worktree-local `UserDataProviders.json` via `/test-providers`; `TestConfiguration.cs:167-176` honours the path only if it exists, and a reused directory makes both sides equal by construction): one with E-1 reverted, one with E-1 applied. Compare the file-name sets, the counts and the bytes of every common file. A test that newly fails shows as a missing file, so the name sets must match too. Build-only tests (`GetSelectQuery`, `ToSqlQuery`) write nothing (`TestBase.cs:69-74`); `SelectQueryOptimizationTests` covers that gap by asserting AST shape directly. — providers: SQLite.MS — proof: characterization
- TO-3 CI `test-all` on the PR: no test failing that passes on master, and the PR's `linq2db.baselines` branch has no diff against baselines master (no baselines PR, or an empty one). — providers: full CI matrix — proof: characterization
- TO-4 Same probe run as TO-1: executed `iter1` = 4,269 and `cte-iter1` = 166, as on master; asserts the guard does not over-skip. — providers: SQLite.MS — proof: control (mutation: guard on `_isColumnsOptimized` inverted → `iter1` / `cte-iter1` fall to 0)
- TO-6 `SelectQueryOptimizationTests` (BUGCHECK-gated method): build a **parameterless** query with one CTE (`.AsCte()`, no captured locals — `Clone()` shares `SqlParameter` instances with the cached query, `SqlQueryCloneVisitorBase.cs:21-22`) over a shared `Tests/Model` table via `GetDataConnection()` / `GetStatement()`, clone the statement, run `new SelectQueryOptimizerVisitor().Optimize(clone, clone, …)`, and assert `FirstIterationPassesReached >= 2` and `LaterIterationPassesReached >= 2` (root and CTE body both reached in each phase — pins that the CTE body is in scope; lower bounds, because how often a body is visited per iteration is not pinned by this change) and `ExpressionPassesExecuted == FirstIterationPassesReached`. Pre-step (critic round-2 lead): run the red arm once — E-2 kept, E-1 reverted — confirm `Optimize` over a finalized CTE clone does not throw, and record the observed counters here; expected red: executed = first + later. — providers: none (build only, no data source) — proof: red→green
- TO-5 `dotnet run -c Release --project Tests/Tests.Benchmarks/linq2db.Benchmarks.csproj -f net10.0 -- manual-deepjoin` at depth 100, master vs branch, ≥10 iterations and 3 warm-ups each (the defaults, 1 warm-up / 3 iterations at `DeepJoinChainBenchmark.cs:76`, are too few to compare): branch median and min both ≤ master's, and the median difference reported with both runs' spread. Run only on the user's go-ahead. — providers: none (no connection) — proof: characterization

## P9 Verification gates

- G-01: pass (local obligations) — TO-1, TO-2, TO-4, TO-6 observed as declared below; TO-3 is G-02 (blocked on CI); TO-5 skipped until the user's go-ahead, so no speed claim is verified.
  - TO-6 red arm (E-2 + E-3, E-1 not applied; `worktree-test.ps1 -Filter …WholeTreeExpressionPassRunsOnlyInFirstIteration`, SQLite.MS): `Optimize` over the finalized CTE clone did not throw; first and later phase assertions held (first = 2); failed on `ExpressionPassesExecuted should be 2 but was 4` (= first + later) — red for the stated reason.
  - TO-6 green (E-1 applied), with the 979-test corpus on SQLite.MS: 980 run, 977 passed, 3 skipped, 0 failed; `missingTests: []`.
  - TO-2 pass: worktree-local `UserDataProviders.json` seeded from the template (`/test-providers`, user-approved), `BaselinesPath` → fresh empty `.build/.agents/baselines-A` (run A: E-1 guard made unconditional, E-2/E-3 kept; 980 run, only `WholeTreeExpressionPassRunsOnlyInFirstIteration` failed, as expected) then fresh empty `baselines-B` (run B: E-1 applied; 980 run, 0 failed). `compare-baselines-ab.ps1`: 487 files each side, 487 common, 0 only-A, 0 only-B, 0 differing bytes.
  - TO-1 pass: throwaway `Probe5911.Executed` inside E-1's guard, same corpus, E-1 applied (980 run, 0 failed): 0 `iterN`, 0 `cte-iterN` executed (master 4,273 / 166).
  - TO-4 pass: same run, `iter1` 4,271 and `cte-iter1` 168 executed, against master 4,269 / 166; the +2 / +2 is TO-6's own test (its build's `Finalize` plus its explicit `Optimize`, one root + one CTE body each).
  - Final tree (probe removed): `SelectQueryOptimizationTests` 39/39, `missingTests: []`.
  - TO-3 → G-02 (blocked: CI). TO-5 → skipped: benchmark not run (user go-ahead pending); unverified: any wall-clock gain.
- G-02: blocked — CI `test-all` on the PR (no new failures + empty baselines diff); needs push.
- G-05: pass — `dotnet build Source/LinqToDB/LinqToDB.csproj -c Release -f netstandard2.0` and `-f net10.0`: "Build succeeded", 0 warnings (after fixing a CS1025 introduced when removing the probe line).
- G-06: pass — `git diff --stat`: `SelectQueryOptimizerVisitor.cs` +33/−2, `SelectQueryOptimizationTests.cs` +36; only E-1/E-2/E-3 lines.
- G-07: n/a — no `Tests/Tests.Playground/` changes.
- G-08: pass — TO-6 is the core-layer test (AST-level, no data source), red → green observed.
- G-09: pass — `code-reviewer` over `git diff 57b910ede` (unpushed): MIN001 (TO-6 blind to an inverted guard) and MIN002 (guard comment overstated a structural invariant) → both fixed, A-1. Out-of-scope observations carried to the PR body: the iteration-≥2-only rewrites (`OptimizeApplyJoin` `:3325`, `processMultiColumn:` `:3336`) on APPLY-capable providers and MERGE roots are covered only by G-02; no speedup claimed until TO-5 runs.

## P10 Adjudicated (M/L)

_None yet._ (The first draft's "no committed test" entry was withdrawn by D-3.)

## P11 Amendments (M/L)

- A-1 (2026-10-24, G-09 `code-reviewer` MIN001 + MIN002) — (1) TO-6 stayed green with the guard **inverted** (measured: mutation `if (_isColumnsOptimized)` → 2/2 passed), because `ExpressionPassesExecuted == FirstIterationPassesReached` also holds when later = first = 2; D-3's "every other regression … moves executed away from first" was false. E-2's executed counter is split into `FirstIterationPassesExecuted` / `LaterIterationPassesExecuted` (incremented inside the guard by phase) and TO-6 now asserts first-executed = first-reached and later-executed = 0. measured: inverted guard → red (`FirstIterationPassesExecuted should be 2 but was 0`); guard removed → red (`LaterIterationPassesExecuted should be 0 but was 2`); real guard → `SelectQueryOptimizationTests` 39/39. (2) The guard comment claimed a structural invariant the set-operator re-entry (`:358-363`, after the closing pass) does not respect; reworded as a measured claim naming the re-entry. D-1's structural-backing list omits the re-entry; it is covered by measurement (U-6 `iterN-afterReentry` 243 / 0), not structure. Same E-n set; approval of E-2's shape re-earned by the mutation runs above.
  re-derives: P5 (D-3 chosen + failure mode), P6 (E-2 counter set), P8 (TO-6 assertions)

## P12 Critic verdict (M/L)

**weak** (plan-critic, model `fable`, 2026-10-24, round 1). Objections and dispositions:

1. TO-3 blind to newly throwing tests (`BaselinesManager.cs:37-41` skips `Dump` on failure); D-1's failure mode named only the SQL half; the `IsValidQuery` consumer (`ExpressionBuilder.SqlBuilder.cs:217`) was missing. → SC-3 / TO-3 now require "no new failures **and** empty baselines diff"; D-1 failure mode lists all three forms.
2. TO-2 could go green vacuously (existing / shared `BaselinesPath`, missing-file blindness, build-only tests write nothing). → TO-2 rewritten: two fresh directories, name sets + counts + bytes.
3. Corpus lacked `SelectQueryOptimizationTests` and multi-root statements. → added with `xUpdate.UpdateTests` / `xUpdate.InsertTests` (U-6); `MergeTests` not added (no MERGE on SQLite).
4. `lead:` CTE semantic changes not split by iteration. → measured (U-6): `cte-iterN` 166 / 0. Open: whether D-1 widens to CTE bodies (user decision pending).
5. P10's "test-only surface" reason contradicted by `QueryCache.cs:1074-1099` (`#if BUGCHECK` test diagnostics). → open: committed BUGCHECK counter test vs probe-only (user decision pending).
6. TO-1's `Record` placement would log skipped passes. → TO-1 now moves `Record` inside the guard.
7. TO-5 3-sample median has no tolerance. → ≥10 iterations, 3 warm-ups, median and min.

Critic searched: `_isColumnsOptimized` (8 hits; U-3 exact), `_parentSelect\s*=|_currentCteClause\s*=` (U-5 exact), nested `new SelectQuery` / `VisitSqlQuery(` / `ProcessElement(` sites (`:2927,3167,3610,3630`, all nested), all `SelectQueryOptimizerVisitor` references (P7 caller list complete), `IsParameterDependent\s*=\s*true` (no optimizer-side state), whole reads of `SqlQueryColumnOptimizerVisitor.cs`, `SqlQueryOrderByOptimizer.cs`, `JoinsOptimizer.UnnestJoins`, `NullabilityContext.IsNullableSourceCalculator` (structural backing now in D-1), the probe's raw `events.tsv` (numbers reproduce), nondeterministic data in corpus fixtures (none), `BaselinesPath`/`Dump`/`LogQuery` in `Tests/Base`, `#if BUGCHECK` sites, KB SQL-AST and `dead-ends.md`, `git log -S "do expression optimization again"` → `7ec71d530` (#3401, no rationale). Not checked: whether the LinqService server re-runs this visitor; `MergeTests` on SQLite.MS.

Items 4 and 5 decided by the user 2026-10-24: D-1 widened to CTE bodies; D-3 / E-2 / E-3 / TO-6 added. Delta sent back to the critic (round 2).

**Round 2: weak** (plan-critic, `fable`, 2026-10-24). All seven round-1 dispositions checked as answering their objections. New objections:

1. The iteration-≥2 counter inside the guard is unreachable by construction; TO-6's `== 0` was a tautology, and `Iter1 > 0` did not pin that the CTE body is reached. → D-3 now counts *reached* passes per phase before the guard, plus one *executed* counter inside it; TO-6 asserts both phases `>= 2` and executed = first.
2. A whole-file `#if BUGCHECK` would hide the fixture's three ungated tests. → E-3 gates only the new method.
3. `lead:` `Optimize` over a finalized CTE clone has no production precedent; `Clone()` shares parameters with the cache. → TO-6 pre-step runs the red arm first and records the counters; the query is parameterless.

Critic searched in round 2: `events.tsv` row counts (U-6 reproduces exactly); `new SelectQuery\b` sites (all nested); `VisitCteClauseReference` (never descends into `Body`; a CTE body is visited once per iteration via `With`, `QueryElementVisitor.cs:1354-1355`); `new CteClause\(` (no optimizer-side creation); `\.Finalize\(` and `LinqService.cs:124,156,219,259` (the remote server does not re-run the visitor — closes round-1 "not checked"); PublicAPI files for the `QueryCache` BUGCHECK members (0 hits; analyzers and doc generation Release-only, `Directory.Build.props:120-122,132`; `BUGCHECK` in `LinqToDB.csproj:17-19`); `GetDataConnection()` defaults to SQLite.MS (`DataProviders.json`); clone visitor Transform arms keep `With`. Not checked: that the U-6 counts are identical without the concat fix (no A/B; TO-1 / TO-4 will run on a tree that has the concat fix only if it has merged).

Not re-dispatched: verdict `weak`, revisions confined to D-3 / E-2 / E-3 / TO-6 wording and placement, E-1 unchanged.
