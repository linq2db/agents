# Work plan: issue-6489-fix-cross-column-cte-walk — Recursive CTE cross-referencing columns make the nullability walk N^M

**Tier:** L  ·  **Status:** parked  ·  **Approved-at:** —  ·  **Branch:** issue/6489-fix-cross-column-cte-walk (stacked on issue/6466-fix-recursive-cte-nullability-walk, PR #6490; never pushed)
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

> **Parked (2026-11-27, user decision).** Answer reuse that stays exact against the cut-based walk kept turning up unchecked walk inputs: cuts (designed in), walked-off-path columns (critic round 1), the context's queries (critic round 2, measured red). Checking the last one at reuse costs about a re-walk, or forbids the cross-branch reuse #6489 needs. The viable redesign is an order-independent fixed-point evaluation per cycle, which changes some answers and needs its own plan. The implementation and its tests are kept in `implementation.patch` beside this plan (`git apply` on b519aecab); nothing was committed to a linq2db branch.

## P1 Problem

[#6489](https://github.com/linq2db/linq2db/issues/6489): after #6466 (PR #6490), `NullabilityContext.CanBeNull` still re-walks a column once per path that reaches it, because the cycle guard is on-path only. In a recursive CTE whose columns read each other through the CTE (`ParentID = ct.ParentID + ct.Level`), a head column reached from each of N recursive branches is walked again from each, so one outermost call costs ~N^M for M chained columns. Measured on #6490's code (SQLite.MS, max column walks per outermost call during one `ToSqlQuery()`): flat 104 / 286 / 916 for N = 5 / 10 / 20; 2-column cross-reference 391 / 2,347 / 16,292; 3-column 2,018 / 23,672 / 326,592 (N=20 unfinished in 2 min). The flat shape is also super-linear per call (~N²): the slowest call reaches ~6N distinct columns and enters each 4–7 times (diamond-shaped column graph), the CTE head 4N times.

## P2 Success criteria

- SC-1 On the translated statement, one outermost `CanBeNull` call on a recursive CTE column walks at most 3N columns for N recursive branches, for self-reading and 2-/3-column cross-referencing shapes (#6490's walk: (N+1)² for a column reading another).  → TO-1
- SC-2 Every answer equals the answer of the same walk without reuse (#6490's walk), over the measured corpus and the hand-built counterexample.  → TO-2, TO-3, TO-4
- SC-3 No answer outlives the outermost call that computed it.  → TO-5

## P3 Constraints & anti-goals (M/L)

- No `CanBeNull` answer changes versus #6490's walk (which itself equals master's on the #6466 census) — generated SQL and baselines must not move.
- No memo that outlives one outermost walk: contexts are held across a rewrite pass (`SqlExpressionOptimizerVisitor.cs:1152`, `BasicSqlBuilder.cs:268`).
- Public API: no change outside `#if BUGCHECK` test hooks (the `SelectQueryOptimizerVisitor` precedent, `SelectQueryOptimizerVisitor.cs:51`); `NullabilityContext` is in `LinqToDB.Internal.SqlQuery`.
- PR scope: #6489, partial (P10), stacked on #6490.

## P4 Unknowns (M/L)

- U-1 Where does the flat shape's ~N² per call come from? — resolved-by probe: per-column entry histogram of the slowest outermost call (flat, N=10): 64 distinct columns over 62 parents, each entered 4–7 times, the CTE head ParentID 40 times; `parentIndexSharedByDistinctColumns = 0` (no stale duplicate columns). A diamond-shaped column graph re-walked per path. measured.
- U-2 Cost of reuse guarded by cuts only — resolved-by probe, superseded: linear for every shape (3-column 145 / 280 / 550 / 1,090 for N = 5 / 10 / 20 / 40), but the rule is unsound (P12 round 1, U-8).
- U-3 Does reuse change answers? — resolved-by probe: differential census, each outermost `CanBeNull(SqlColumn)` answered with reuse and by a twin context with reuse disabled, over `CteTests` + `ConcatUnionTests` + `NullabilityContextTests` + scratch fixtures (COALESCE over two CTE columns with mixed-type branches, branches of different types, nested `Union` + `Concat`, recursive-part-first, 3-column cross-reference, an `int`/`int?` cross-cut fixture) × 1–3 branches, SQLite.MS: 0 mismatches / ~199,000 compared, 500 tests passed — under the final rule (U-8). measured.
- U-4 Can the census see the cut check? — resolved-by probe: with the cut check disabled, 0 mismatches over the same run while 2,538 reuses happened whose recorded cuts did not hold. Every column in those fixtures is typed `int` in SQL, so cut answers coincide whatever the mapping. measured.
- U-5 Do the per-frame cut lists stay small? — resolved-by probe: without de-duplication, two cases did not finish in 2 min (cut lists grow multiplicatively through reuse); with one entry per column per frame every case finishes. measured.
- U-6 Is keying the reuse by column alone sound when the walk's context differs (WithQuery appends each branch query)? — resolved-by reading + U-3: within one outermost call all contexts share the caller's Queries prefix, JoinSource and transformation info; branch contexts only append branch queries (`WithQuery`, called only from the branch loop; no other context is created mid-walk except the DEBUG `SqlColumn.ToString` — #6466 and #6489 round-1 critic searches). `CanBeNullSource` answers from the last query in which a source is reachable; an appended branch query changes an answer only for sources inside that branch, and a column inside branch b is reached only through the head's loop, which appends b. reasoned; the census found no mismatch (U-3).
- U-7 How much of translation time is the nullability walk? — resolved-by probe, noisy: wall-clock on a loaded machine varied 10× between identical runs. Wall-clock is not used as evidence; counted work is.
- U-8 Is the cut check enough? — resolved-by probe: no (critic round 1). Hand-built AST Len ← Name (int cast of a string), Name ← Len (string cast of an int), Total ← Len + Name, outermost `CanBeNull(Total)`: reuse with cuts checked only → `false`; reuse disabled (#6490) → `true`; reuse refused also when a column the answer walked is on the path → `true` (`NullabilityContextTests.RecursiveCteColumnsReadingEachOther`). measured.
- U-9 Cost under the final rule, during one `ToSqlQuery()`? — resolved-by probe (max walks per outermost call): flat 75 / 145 / 285 for N = 5 / 10 / 20 (linear); 3-column 371 / 991 / ≥ 2,906 with one answer per column, 247 / 647 / 1,897 with several (D-6) — ~N^1.5; 3-column N=20 does not finish in 3 min, nearly all of it in the walk (~5,000 outermost calls). measured.
- U-10 Why do answers stop holding in the 3-column shape? — resolved-by probe: invalidation log, 3-column N=5: 41,456 new answers, each forced by a real path-state change — mostly a pass-through wrapper column (`Level` idx2 → idx1 → idx0 → CTE field) the answer walked now being on the path, or a cut at a column no longer on the path. A column gathers up to N answers (5 / 10 / 20). measured.
- U-11 Cost on the translated statement (direct call per CTE field column, as TO-1 asserts)? — resolved-by probe: with reuse ≤ 2N + 2 (self 11 / 21; 2-column ParentID 22 / 42; 3-column ParentID 22 / 42, ChildID 2 — `int?`, answers `true` at once) for N = 10 / 20; reuse disabled: self 11 / 21, 2- and 3-column ParentID 121 / 441 = (N+1)². measured.

## P5 Decisions (M/L; rejected alternatives mandatory at L)

### D-1 — Reuse answers within one outermost walk when the walk would take the same steps

- **chosen:** a private `ColumnWalk` shared by the contexts one outermost call creates (it replaces `_visitedColumns`): `Path` (column → branch being walked, as in #6490), per-column answers each with (a) the cuts at columns above it that its walk made and (b) the set of columns its walk entered, including the sets of answers it reused. An answer is reused when every recorded cut's column is on the path with the same cut answer and no column of its set is on the path. Its cuts and set are then merged into the caller's frame.
- **rejected:** cuts checked only — unsound (U-8).
- **rejected:** reuse only answers whose walk met no cut — a recursive CTE head's answer always depends on a cut, so the heads, which carry the cost, would never be reused. reasoned.
- **rejected:** a fixed-point evaluation (answers independent of walk order) — linear for every shape but changes answers where the cut answer by type differs from the fixed point (the #6466 census control answering `false` at set-operator re-entries produced 52 mismatches); user chose the exact rule (2026-11-27).
- **rejected:** answers stored on the context across calls — P3.
- **why this:** the walk below a column, given the shared context prefix (U-6), is determined by which columns it meets on the path and their cut answers. Recorded cuts cover the columns it met on the path; the walked set covers the columns it met off the path. Both equal → same steps → same answer.
- **failure mode of the choice:** a walk input outside the path state and the shared prefix: `CanBeNullSource` answers that differ between branch contexts (U-6), `_nullabilityOverrides` (consulted only before delegation on the context the call is made on — unchanged), `IsNeverNullAggregate` (reads the column's own parent; unchanged within a call). And the rule is not linear on cross-referencing columns during translation (U-9) — P10.

### D-2 — Key reuse by column, not by context

- **chosen:** answers are keyed by the `SqlColumn` reference.
- **rejected:** key by (column, Queries, JoinSource, transformation info) — each branch context appends its branch query, so a head reached from N branches would get N keys. reasoned.
- **failure mode of the choice:** U-6's argument is reasoned; the census is its only measurement.

### D-3 — One cut entry per column per frame

- **chosen:** `AddCut` skips a column already in the frame.
- **why this:** a column on the path keeps one mapping for the lifetime of every frame below it (its mapping changes only when its loop advances, after those frames popped), so a second entry carries the same answer. Without it lists grow multiplicatively (U-5).

### D-4 — Answers are dropped when the path empties

- **chosen:** when the outermost column's frame pops (`Path.Count == 0`), answers, ids and frames are cleared.
- **why this:** P3; the next call on the same context may see a rewritten statement.
- **failure mode of the choice:** an outermost call that is not a column (`SqlBinaryExpression.CanBeNullable(ctx)` reaching two columns) runs two separate walks; reuse does not span them.

### D-5 — `#if BUGCHECK` hooks for counted tests

- **chosen:** `NullabilityContext.ColumnsWalked` and `DisableAnswerReuse`, under `#if BUGCHECK` only, following `SelectQueryOptimizerVisitor`'s BUGCHECK counters (`SelectQueryOptimizerVisitor.cs:51-60`, read by `SelectQueryOptimizationTests.cs:699-735`). Debug, Testing and Azure (CI) builds define BUGCHECK for the library and the tests (`LinqToDB.csproj:23-26`, `Tests/Directory.Build.props:11-15`).
- **rejected:** wall-clock bounds — U-7.
- **failure mode of the choice:** TO-1 and TO-2 do not run in Release test configurations.

### D-6 — Several answers per column

- **chosen:** a column keeps every answer it computed in the walk; reuse takes the latest that holds.
- **why this:** with one slot a column alternately reached in two path states is re-walked on every switch; measured 991 → 647 (N=10) and 2,906 → 1,897 (N=20) max walks per call, 3-column (U-9).
- **failure mode of the choice:** memory per walk grows with answers × walked-set size; answers per column measured ≤ N (U-10).

## P6 Edit-points

- E-1 `Source/LinqToDB/Internal/SqlQuery/NullabilityContext.cs:CanBeNull` — `_visitedColumns` → `ColumnWalk _walk` with `TryCut` / `TryReuse` / `Enter` / `Leave`, `ColumnSet` bit set, column walk body moved to `CanBeNullWalked` (D-1–D-4, D-6).
- E-2 `Source/LinqToDB/Internal/SqlQuery/NullabilityContext.cs` (BUGCHECK block) — `ColumnsWalked`, `DisableAnswerReuse` (D-5).
- E-3 `Tests/Linq/Linq/CteTests.cs` — `RecursiveColumnsNullabilityWalkIsBounded` (TO-1), `RecursiveColumnsNullabilityReuseKeepsAnswers` (TO-2), helper `RecursiveColumnsCte`, all under `#if BUGCHECK`.
- E-4 `Tests/Linq/Infrastructure/NullabilityContextTests.cs` — `RecursiveCteColumnsReadingEachOther` (TO-3), `RecursiveCteColumnsAnswerAgainAfterChange` (TO-5), helper `ColumnsReadingEachOtherCte`.

## P7 Impact map (M/L)

- `_visitedColumns` readers/writers — searched `_visitedColumns` across `Source/`: `NullabilityContext.cs` only — covered by E-1.
- Contexts created during a walk — searched `new NullabilityContext(` and `.WithQuery(` / `WithJoinSource` / `WithTransformationInfo` across `Source/` (#6466 P7 list: `MySqlSqlBuilder.cs:362`, `ExpressionBuildVisitor.cs:2615`, `ExpressionBuilder.QueryBuilder.cs:759`, `BasicSqlBuilder.Merge.cs:56`, `BasicSqlBuilder.cs:268,2356`, `JoinsOptimizer.RemoveDuplicates.cs:24`, `SqlExpressionConvertVisitor.cs:254`, `SqlExpressionOptimizerVisitor.cs:765,1152`, `SqlSearchCondition.cs:184`) — all outside a walk; each starts its own `ColumnWalk` — out-of-scope.
- Re-entry routes into `CanBeNull(SqlColumn)` — `SqlColumn.CanBeNullable` (`SqlColumn.cs:151`), `SqlCteField.CanBeNullable` (`SqlCteField.cs:45`), `SqlCteTableField.CanBeNullable` (`SqlCteTableField.cs:56`) — every route reaches the column arm, so every entered column is in the walked set and every cut is recorded — covered by E-1.
- Path membership of walked columns as a reuse input — the walk's steps depend on it (U-8) — covered by E-1 (walked set).
- Override contexts — `new NullabilityContext(parent, overrides)` delegates every call to the parent; the walk runs on the parent's `ColumnWalk` — covered by E-1 (unchanged delegation).
- BUGCHECK hook precedent — `SelectQueryOptimizerVisitor.cs:51` / `SelectQueryOptimizationTests.cs:699` — covered by E-2 (follows it).
- Public API — no shipped member changes; BUGCHECK members are absent from Release builds — out-of-scope.
- `ActiveIssue(6489` gates — `git grep -n "ActiveIssue(6489" -- Tests`: no hits — out-of-scope.

## P8 Test obligations (M/L)

- TO-1 `CteTests.RecursiveColumnsNullabilityWalkIsBounded`: per CTE field column of the translated statement, one `CanBeNull` walks ≤ 3N columns; self / two / three × N = 10, 20; discriminating input is a column reading another (`ParentID = ct.ParentID + ct.Level`) — providers: SQLite.MS (walks the translated AST, executes nothing) — proof: red→green (reuse disabled, i.e. #6490's walk: 121 / 441 > 30 / 60, U-11; the self shape is linear either way and characterizes).
- TO-2 `CteTests.RecursiveColumnsNullabilityReuseKeepsAnswers`: every column of the CTE body and its branches answers the same with reuse on and off; self / two / three × N = 1, 2, 4 — providers: SQLite.MS — proof: characterization (all-`int` columns; reuse without the walked-set check stays green here, as U-4 predicts).
- TO-3 `NullabilityContextTests.RecursiveCteColumnsReadingEachOther`: the hand-built counterexample answers `true` (#6490's answer) — providers: none (AST only) — proof: red→green (scratch mutation removing the walked-set check: `false`).
- TO-4 Existing `CteTests` + `ConcatUnionTests` + `NullabilityContextTests` green — providers: SQLite.MS locally, all via CI — proof: characterization.
- TO-5 `NullabilityContextTests.RecursiveCteColumnsAnswerAgainAfterChange`: a second `CanBeNull` on the same context after the anchor's Name becomes `NULL` answers `true` — providers: none — proof: control (scratch mutation keeping answers across calls turns it red — `Stack empty` on reusing at depth 0).

## P9 Verification gates

- G-01: pass — `worktree-test.ps1` SQLite.MS net10.0, `CteTests` + `ConcatUnionTests` + `NullabilityContextTests` + `CreateDatabase`: 495 passed / 0 failed / 2 skipped (pre-existing), all five new tests present. TO-1 bound vs reuse-off counts U-11; TO-3 red under scratch walked-check removal (`should be True but was False`); TO-5 red under scratch clear removal (`InvalidOperationException: Stack empty`). `test-diff-sweep.ps1 -IncludeWorkingTree`: narrowedSets 4 (each reasoned on the line above), every other category 0.
- G-02: blocked — CI baselines PR; expected no SQL change (P3).
- G-03: pass — `dotnet build Tests/Linq/Tests.csproj -c Release -f net10.0` succeeded (BUGCHECK off, analyzers on); no new shipped member.
- G-04: n/a — no shipped surface change.
- G-05: pass — `dotnet build Source/LinqToDB/LinqToDB.csproj -c Release -f netstandard2.0` succeeded.
- G-06: pass — diff reviewed: `NullabilityContext.cs` column arm, walk state and BUGCHECK block; two test files.
- G-07: n/a — nothing under `Tests/Tests.Playground/`.
- G-08: blocked — CI after push.
- G-09: blocked — adversarial diff read before the PR opens (critic round 2).

## P10 Adjudicated (M/L)

- Partial fix, by user decision (2026-11-27): during translation, cross-referencing recursive columns stay ~N^1.5 per outermost call (U-9) — 3-column N=20 does not translate in 3 min — because answers truly depend on the path states the optimizer's pass-through wrapper columns create (U-10). Exactness against #6490's walk rules out the order-independent fixed point that would be linear. #6489 stays open for that redesign.
- The cut check (D-1 (a)) is not shown load-bearing by any reachable query (U-4); it is part of what makes reuse exact by construction.
- TO-1 asserts on the translated statement, where reuse is ≤ 2N + 2; the mid-translation shapes (U-9) are not asserted, because the residue above would fail any linear bound there.

## P11 Amendments (M/L)

_None._

## P12 Critic verdict (M/L)

- Round 1 (fable, plan-critic) — **refuted**. D-1's "the walk below a column is determined by the column, the shared prefix and the cut answers it consults" was false: it also depends on which columns were not on the path and so were walked in full. Counterexample: Len ← Name, Name ← Len (string), Total ← Len + Name. Also weak: U-2 measured on the unsound rule; D-3's invariant only commented; P7 had no row for path membership of walked columns.
  - Response: walked-set check added (D-1 (b)); counterexample built as TO-3 and measured red without the check (U-8); U-2 superseded by U-9; P7 row added; D-6 added; costs re-measured (U-9 – U-11). The LINQ spelling of the counterexample did not reproduce (linq2db hoists `ct.Name.Length` into its own CTE column; every outer answer was `true`).
  - User decision after the re-measure: ship the exact rule as a partial fix; #6489 stays open.
- Round 2 (fable, plan-critic) — **refuted**. U-6 / D-2 ("a column inside branch b is reached only through the head's loop, which appends b") is false when the outermost call is on a branch column under a context that lacks its branch — TO-2's own calling convention. A column below it that reads an outer-joined table only the branch reaches is answered with the table unresolved (`false`), then reused under the head's loop where the branch is in the context and a fresh walk answers `true`. Measured: `NullabilityContextTests.RecursiveCteBranchColumnFromContextWithoutBranch` — reuse `false`, reuse disabled `true`. Production reachability not established (the critic found no caller that provably builds the shape). Weak: no obligation reddens on removing the cut check alone; no P7 row for contexts created on an inner query; allocations per column walk on plain queries unmeasured. Held: empty frame stack, ids after clear, exception paths, D-3 under merges, override delegation, DEBUG `ToString`, `DisableAnswerReuse` before a walk.
  - User decision: park #6489 (see the header). The round-2 test is in `implementation.patch` (`NullabilityContextTests.RecursiveCteBranchColumnFromContextWithoutBranch`) and fails on that implementation.
