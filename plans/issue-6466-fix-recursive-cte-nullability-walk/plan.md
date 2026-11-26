# Work plan: issue-6466-fix-recursive-cte-nullability-walk — Recursive CTE nullability walk grows factorially

**Tier:** L  ·  **Status:** draft  ·  **Approved-at:** —  ·  **Branch:** issue/6466-fix-recursive-cte-nullability-walk
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

> Authoring order: this plan was written after a measurement-driven implementation (probe → red test → fix), not before the first source edit. The probes behind every `P4` row ran on the branch with temporary instrumentation that is not in the diff.

## P1 Problem

Translating a recursive CTE whose body is an anchor plus N recursive `Concat` branches takes time that grows roughly factorially with N ([#6466](https://github.com/linq2db/linq2db/issues/6466)). `NullabilityContext.CanBeNull` (`Source/LinqToDB/Internal/SqlQuery/NullabilityContext.cs:152-207` on master) walks every UNION / UNION ALL branch column of a set-operator column (`:162-190`) before adding the column to the cycle guard `_visitedColumns` (`:193`). In a recursive CTE each recursive branch reaches the head column again through `SqlCteTableField` → `SqlCteField.Column`; the head is not yet guarded, so every re-entry walks all branches again and only the branch columns cut the walk — every ordering of the branches is visited. Measured on master: `CteTests.RecursiveWithManyRecursiveBranches` (10 branches, SQLite.MS) does not finish translating within its 1-minute bound.

## P2 Success criteria

- SC-1 A recursive CTE with 10 recursive branches translates within the test's 1-minute bound (it hangs on master).  → TO-1
- SC-2 Every nullability answer `CanBeNull` gives for a column is unchanged versus master over the measured corpus (U-2, U-4, U-9), including a recursive CTE whose anchor column is non-nullable while the recursive branch column is nullable, and a body whose recursive part comes first.  → TO-2, TO-3, TO-4

## P3 Constraints & anti-goals (M/L)

- No change to a `CanBeNull` answer versus master on the measured corpus — generated SQL and baselines must not move (SC-2). Beyond it, D-2's failure mode is the unmeasured residue.
- No public API change: `NullabilityContext`'s public surface is untouched; `_visitedColumns` is private.
- No memo that outlives one walk: contexts are held for a whole optimizer / builder pass while the statement is rewritten (`SqlExpressionOptimizerVisitor.cs:1152`, `BasicSqlBuilder.cs:268`), so no cached answer may be stored on the context across top-level calls.
- PR scope is #6466 alone — a local translation-performance bug.

## P4 Unknowns (M/L)

- U-1 Does registering the head column before the branch loop make the #6466 shape polynomial? — resolved-by probe: branch-walk counter over one `ToSqlQuery()` translation, SQLite.MS, branches 1/2/3/4/5/6/8/10/20 → 205 / 830 / 1,927 / 3,556 / 5,777 / 8,650 / 16,592 / 27,862 / 150,932 branch walks per translation, ~N³ (critic fit `9.87·N³ + 180·N²`). Rows returned stayed 28 for every N (results correct). measured.
- U-8 What does one outermost call cost? — resolved-by probe: max column walks per outermost `CanBeNull(SqlColumn)` call during one translation (outer `where h.ChildID != 3 && h.ParentID != 4`), N = 5/10/20: flat (`ParentID = ct.ParentID`, `Level = ct.Level + 1`) 104 / 286 / 916, translation 2.0 s at N=10, 10.1 s at N=20; two cross-referencing columns (`ParentID = ct.ParentID + ct.Level`) 391 / 2,347 / 16,292, 9.0 s / 58.5 s; three (`ChildID = ct.ChildID + ct.ParentID` added) 2,018 / 23,672 / 326,592, 28.0 s at N=10, unfinished at 2 min for N=20. Per call ~N² flat and ~N^M with M chained cross-referencing columns (the guard is on-path only, so a column reached from each of N branches is re-walked from each). Calls per translation ~320·N. measured. The flat ~N² per call is not explained by reading (a flat head walk should be N+1); reasoned, unprobed.
- U-9 Do COALESCE over two CTE columns, branches of different types, a nested `Union` + `Concat` body, and a recursive-part-first body change answers? — resolved-by probe: differential census with those four fixtures × 1/2/3 branches added: 0 mismatches / ~189,000 compared; all 12 translate. measured.
- U-10 Is the branch-mapping reset after the loop load-bearing? — resolved-by probe: census with the reset removed: 51 mismatches (`new=False legacy=True`), all from the recursive-part-first fixture. measured.
- U-2 If the re-entered head answers by its own type (candidate A), do answers change? — resolved-by probe: differential census (each outermost `CanBeNull(SqlColumn)` computed by the candidate and by a verbatim copy of the master walk, answers compared) over `CteTests` + `ConcatUnionTests` on SQLite.MS: 0 mismatches / ~177,000 compared. measured.
- U-3 Can the census disagree at all? — resolved-by probe: control mode answering `false` at every set-operator re-entry produced 52 mismatches over the same run (after fixing a logging recursion, see U-6). measured.
- U-4 Does a head-vs-branch nullability-kind mismatch flip candidate A's answer? — resolved-by probe: added fixture (anchor `GrandChildID = p.ParentID` typed `int`, recursive branch `ct.GrandChildID + 1` typed `int?`): candidate A 118 mismatches, all `new=False legacy=True`; candidate B (own type OR any union branch type) 0; candidate E (the branch column currently being walked) 0, ~182,000 compared each. measured. Master answers `true` here because its walk cuts the cycle at the branch column, whose type is `int?`.
- U-5 Is candidate E's re-entry answer bounded? — resolved-by reasoning over the edit: a dictionary lookup, O(1); B loops over all branches per re-entry, O(N) per re-entry. reasoned, unprobed beyond U-1's counts (U-1 measured A; E walks the same edges, only the cut answer differs).
- U-6 Does anything else in a re-entered path call back into `CanBeNull`? — resolved-by probe: the first control run overflowed the stack because the probe's log line called `SqlColumn.ToString()`, which itself calls `CanBeNullable` (`SqlColumn.ToString` → `CanBeNullable`). Only probe code was affected; the edit adds no such call. measured.
- U-7 Does a column shared by two parents (DAG-shaped, not cyclic) re-walk? — resolved-by reading: yes, on master and after the change (the guard is on-path only). Not the #6466 shape; see P10.

## P5 Decisions (M/L; rejected alternatives mandatory at L)

### D-1 — Register the column in the cycle guard before its set-operator branches are walked

- **chosen:** `_visitedColumns` is entered on arrival (after the nullable-source early return) and removed in a `finally`; the set-operator branch loop and the expression walk both run inside it.
- **rejected:** a per-outermost-call memo of answers computed without a cycle cut — every answer in a recursive CTE is computed under a cut, so the memo alone does not help the #6466 shape; it would only address the DAG case (U-7), which is out of scope.
- **rejected:** a memo stored on the context — contexts live for a whole rewrite pass (P3); a cached answer goes stale as the statement changes.
- **why this:** removes the factorial re-walk at its source: a head is never re-walked while it is on the path. It does not stop a column reached from several branches being walked once per branch — that is the N^M cross-referencing residue (U-8, P10).
- **failure mode of the choice:** the re-entered head now answers by a cut instead of a re-walk, so the cut's answer must equal what the master walk computed (D-2).

### D-2 — A set-operator column re-entered from one of its branches answers by that branch column's type

- **chosen:** `_visitedColumns` becomes `Dictionary<SqlColumn, SqlColumn?>`; while a set-operator column walks a branch it maps to that branch column, otherwise to `null`. A re-entry answers by the mapped branch column's `SystemType`, else by the column's own (unchanged for every non-set-operator column and for re-entry during the expression walk).
- **rejected:** candidate A — re-entered head answers by its own type: flips `true → false` when the anchor is `int` and the branch `int?` (U-4, 118 mismatches).
- **rejected:** candidate B — own type OR any union branch's type: 0 mismatches but O(N) per re-entry, and it reads branches the master walk never cut at, so it can answer `true` where master answered `false` (a non-recursive UNION branch typed nullable but walking non-null) — reasoned, unprobed. Not constructible from LINQ as far as found: a recursive branch reading a nullable member is typed nullable itself, so E and B agree whenever the member type governs the branch types.
- **why this:** it is exactly the first cut the master walk makes: on master the re-entered head walks its branches, and the branch currently on the path is the one that cuts, by its own type. Measured identical (U-4).
- **failure mode of the choice:** master's re-walk also OR-ed in the other branches' nested walks; E answers only the current branch's cut. They agree when nullability propagates as OR-of-inputs or a constant (binary operators, `CalcCanBeNull`'s `IfAnyParameterNullable` / `NotNullable` / `Defined`). An `IfAllParametersNullable` function (COALESCE-like) over two different cyclic paths could differ — reasoned, unprobed; no census case hit it.

## P6 Edit-points

- E-1 `Source/LinqToDB/Internal/SqlQuery/NullabilityContext.cs:CanBeNull` — `_visitedColumns` becomes `Dictionary<SqlColumn, SqlColumn?>`; the column is registered before the set-operator loop and removed in `finally`; a re-entry answers by the walked branch column's type (D-1, D-2).
- E-2 `Tests/Linq/Linq/CteTests.cs:RecursiveWithManyRecursiveBranches` — new: 10 recursive branches, translation bounded at 1 minute.
- E-3 `Tests/Linq/Linq/CteTests.cs:RecursiveColumnNullabilityFollowsRecursiveBranchType` — new: pins the master answer for an `int` anchor / `int?` branch column (`true`) and a matching `int` column (`false`), 1 and 3 branches.
- E-4 `Tests/Linq/Linq/CteTests.cs:RecursivePartFirstColumnNullabilityFollowsOwnType` — new: a body whose recursive part comes first; the head re-enters itself through its own expression after the branch loop, and answers by its own `int?` type (`true`).

## P7 Impact map (M/L)

- `NullabilityContext._visitedColumns` readers/writers — searched `_visitedColumns` across `Source/`: `NullabilityContext.cs` only (declaration, `??=` allocation, `WithQuery` carry-over at the branch loop, add/remove) — covered by E-1.
- Contexts created with a fresh guard — searched `new NullabilityContext(` and `.WithQuery(` / `WithJoinSource` / `WithTransformationInfo` across `Source/`: `MySqlSqlBuilder.cs:362`, `ExpressionBuildVisitor.cs:2615`, `ExpressionBuilder.QueryBuilder.cs:759`, `BasicSqlBuilder.Merge.cs:56`, `BasicSqlBuilder.cs:268,2356`, `JoinsOptimizer.RemoveDuplicates.cs:24`, `SqlExpressionConvertVisitor.cs:254`, `SqlExpressionOptimizerVisitor.cs:765,1152`, `SqlSearchCondition.cs:184` — all create contexts outside a walk; none reads the guard — out-of-scope (unchanged behaviour: each starts empty, as on master).
- Re-entry routes into `CanBeNull(SqlColumn)` — searched `CanBeNullable(NullabilityContext` overrides that forward to a column: `SqlColumn.CanBeNullable` (`SqlColumn.cs:151`), `SqlCteField.CanBeNullable` (`SqlCteField.cs:45`), `SqlCteTableField.CanBeNullable` (`SqlCteTableField.cs:56`), `NullabilityContext.CanBeNull` `SqlCteTableField` arm — all reach the column through `CanBeNull`, so the guard sees every re-entry — covered by E-1.
- Composite overrides that call `operand.CanBeNullable(...)` directly (`SqlBinaryExpression.cs:69` and kin) — they bottom out in `SqlColumn.CanBeNullable` → `CanBeNull`, which holds the guard — covered by E-1; their propagation shape is D-2's failure-mode assumption.
- Public surface — `NullabilityContext` public members unchanged (`PublicAPI.Shipped.txt:5291` lists `WithQuery`; no signature edited) — out-of-scope.
- `ActiveIssue(6466` gates — `git grep -n "ActiveIssue(6466" -- Tests` at the branch base: no hits — out-of-scope; re-run at every master merge.

## P8 Test obligations (M/L)

- TO-1 `CteTests.RecursiveWithManyRecursiveBranches`: 10-branch recursive CTE translates within 1 minute — providers: RecursiveCteContextSource(false) (direct contexts; the remote leg adds nothing to a translation bound) — proof: red→green (measured red on master SQLite.MS: `Wait(1 min)` returned false; green after E-1 in 1.45 s).
- TO-2 `CteTests.RecursiveColumnNullabilityFollowsRecursiveBranchType`: `int` anchor / `int?` branch column answers `true`, matching `int` column answers `false`, for 1 and 3 branches; discriminating input is the type mismatch (candidate A answers `false`) — providers: SQLite.MS (asserts the AST nullability directly; translation is provider-agnostic) — proof: characterization (passes on master and on the fix; mutation to candidate A turns it red, recorded in G-01).
- TO-3 Existing recursive-CTE and set-operator tests stay green: `CteTests` + `ConcatUnionTests` — providers: SQLite.MS locally, all providers via CI — proof: characterization.
- TO-4 `CteTests.RecursivePartFirstColumnNullabilityFollowsOwnType`: recursive-part-first body, head `GrandChildID` answers `true`; discriminating input is the expression-phase re-entry after the loop (U-10) — providers: SQLite.MS (asserts the AST nullability directly) — proof: characterization (census U-9 shows master's answer equals the fix's on this fixture; scratch mutation removing the reset turns the 1-branch case red, recorded in G-01; the 3-branch case does not discriminate).

## P9 Verification gates

- G-01: pass — `worktree-test.ps1` SQLite.MS net10.0: TO-1 red on master (`Wait` false at 1 min), green on fix (1.45 s); TO-2 green on master 2/2 and on fix 2/2, red 2/2 under scratch mutation `var cut = column` (`CanBeNull(grandChildId)` false); TO-3 `CteTests` + `ConcatUnionTests` + `CreateDatabase` 473 passed / 0 failed / 2 skipped (pre-existing), incl. TO-1, TO-2, TO-4; TO-4 red 1/2 under scratch mutation removing `_visitedColumns[column] = null` (`CanBeNull(grandChildId)` false for 1 branch). Note: one intermediate run read a stale master DLL (restored file older than the build) and showed TO-1 red; re-run after touching the file is the recorded one. `test-diff-sweep.ps1 -IncludeWorkingTree`: chains 0, nestedChains 0, narrowedSets 2 (reasoned, line above), narrowedWithoutReason 0, shouldlySubjectGates 0, typeOnlyShouldlyGates 0, continuationIndents 0, unanchoredAssertionGates 0, narrowedContinuations 0, cacheMissOutsideQueryCacheTest 0, handDuplicatedAreEqual 0, invisibleChars 0, issueNamedMembers 0, localModels 0, attributePadding 0, issueFixtureFiles 0. Release: `dotnet build Tests/Linq/Tests.csproj -c Release -f net10.0` succeeded.
- G-02: blocked — CI baselines PR; expected to show no SQL change (P3).
- G-03: n/a — no new public surface.
- G-04: n/a — no public surface change.
- G-05: n/a — no new BCL API used.
- G-06: pass — `git diff` reviewed: `NullabilityContext.cs` changes only the `SqlColumn` arm and the guard's declaration; `CteTests.cs` adds two usings and two tests.
- G-07: n/a — nothing under `Tests/Tests.Playground/`.
- G-08: blocked — red→green TO-1 local; CI run after push pending.
- G-09: blocked — adversarial diff read before the PR opens.

## P10 Adjudicated (M/L)

- The guard stays on-path only, so a column shared by two parents (DAG-shaped, e.g. `c_k = c_(k-1) + c_(k-1)`) is still walked once per parent — pre-existing on master and not the #6466 shape (recursive CTE branches). A per-outermost-call memo for it is a separate change with its own answer-equality proof.
- TO-1 is a wall-clock bound, not a counted-work assertion: counting needs a product hook or a test-side `ISqlExpression`; the 1-minute bound sits ~40× above the fixed time (1.45 s including first-query overhead) and ~∞ below master's, so it cannot flake in either direction on a healthy agent. On a regression its `Task.Run` translation is not cancelled and keeps one thread busy until the test process exits — accepted, since the run is already red.
- Cross-referencing recursive columns stay polynomial-but-steep: max walks per call ~N^M for M chained columns that read each other through the CTE (U-8: N=10 M=3 28 s; N=20 M=3 > 2 min). Master is factorial on the same shapes. Not the #6466 repro (`V = r.V + 1`, `Id = r.Id`: no cross-reference); closing it needs answers reused within one outermost call, which are cut-dependent (P3, D-1 rejected memo) — a separate design.
- The flat shape's ~N² per call (U-8) is unexplained by reading; it is polynomial and fixes the reported hang, and is not investigated here.

## P11 Amendments (M/L)

_None._

## P12 Critic verdict (M/L)

- Round 1 (fable, plan-critic) — **weak**. No changed answer versus master on a reachable input, no super-linear per-call cost on the flat #6466 shape by reading. Searched: `_visitedColumns|new NullabilityContext\(` and `.WithQuery(` / `GetContext` across `Source/`; every `CanBeNullable(NullabilityContext` override in `Internal/SqlQuery`; `IfAllParametersNullable|All\(.*CanBeNullable` (AND-shaped composers `SqlCoalesceExpression.cs:70`, `SqlRowExpression.cs:22`, `QueryHelper.cs:2088`); `\?\? |Sql\.Row|\.Union\(` over `CteTests.cs`; an arm-by-arm diff of master vs the change. Objections and responses:
  - U-1's "~N² per translation, each call linear" contradicted its numbers → re-measured per call (U-8); U-1 corrected to ~N³ per translation.
  - D-1's "each edge once" fails for cross-referencing columns (N^M) → measured (U-8), D-1 reworded, P10 line added. Pre-existing (master factorial); not the issue repro.
  - SC-2/P3 stated absolutely while D-2 admits an unprobed AND-shaped class → census extended with COALESCE / mixed-type / nested / recursive-first fixtures, 0 mismatches (U-9); SC-2/P3 narrowed to the measured corpus.
  - Expression-phase re-entry unwalked → recursive-first fixture reaches it; reset proven load-bearing (U-10); TO-4 added.
  - TO-2 pins one clause; E vs B / first-branch mapping undiscriminated → TO-4 covers the reset; an E-vs-B discriminator was not constructible from LINQ (D-2 note).
  - TO-1 leaves a runaway task on red → P10 line.
- Not re-critiqued after the response; the responses are measurements and wording narrowing, no new edit-point beyond E-4 (a test).
