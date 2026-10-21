# Work plan: issue-5964-filtered-progress-total — Heartbeat total under --filter: count the tests NUnit will run

**Tier:** M  ·  **Status:** approved  ·  **Approved-at:** 2026-10-21 (user)  ·  **Branch:** issue/5964-filtered-progress-total
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

## P1 Problem

[#5964](https://github.com/linq2db/linq2db/issues/5964). Under `--filter`, the `--test-progress` heartbeat's `total` is the discovered (pre-filter) test-case count. `TestProgressTracker.OnBefore` calls `_state.SetTotal(test.TestCaseCount)` for every suite (`Tests/Base/TestProgressReporter.cs:70-75`), and `SetTotal` keeps the largest value (`Tests/Base/TestProgressState.cs:98-105`). `etaSec` is derived from that total (`TestProgressReporter.cs:254`). The issue's observed run: 14 methods × 7 providers reported `"total": 70328, "etaSec": 515501` after 20 tests. Falsifiable shape: on master, a filtered run's final heartbeat has `done: true` with `completed` ≪ `total`.

## P2 Success criteria

- SC-1 For a filtered run, the heartbeat's `total` equals the number of tests that fire the reporter's `ITestAction` (= final `completed`), and `totalIsUpperBound` is `false`. → TO-1
- SC-2 The counter excludes what NUnit runs without the action: leaves that are not `Runnable` (Ignored / Skipped / NotRunnable), `Explicit` leaves the filter does not explicitly match, and every leaf under a suite NUnit skips (non-runnable suite, or `Explicit` not explicitly matched). It includes an `Explicit` leaf that the filter explicitly matches. → TO-2
- SC-3 When the root work item cannot be resolved, `total` falls back to the root `TestCaseCount`, `totalIsUpperBound` is `true`, and `etaSec` is `null`. → TO-3
- SC-4 The reflection hop the resolver depends on (an instance field of type `WorkItem` on `SimpleWorkItemDispatcher` and `ParallelWorkItemDispatcher`) is guarded by a test, so a future NUnit bump that removes it fails loudly instead of degrading silently to the upper bound. → TO-4

## P3 Constraints & anti-goals

- The heartbeat stays a no-op without `--test-progress` (`TestProgressReporter.cs:147-149`): the new counting call sits after `EnsureInit()`'s early return, checked in the diff review (G-09), not by a test.
- Progress reporting must never fail or hang a test run: resolution/counting is wrapped and falls back (existing rule, `TestProgressReporter.cs:174-178`, `:305-310`).
- Existing JSON fields keep their names and types; `totalIsUpperBound` is additive (the only parser, `.claude/scripts/test-status.ps1:74-82`, ignores unknown fields). `total`'s meaning does change for unfiltered runs too — it drops Ignored / Explicit / NotRunnable leaves that `TestCaseCount` includes (intended, SC-2); the D-4 follow-up rewrites `testing.md:284`/`:910` accordingly rather than only deleting the caveat.
- No change to `ResourceLaneDispatcher` / parallelization, to NUnit filtering, or to the deferred-commit protocol in `TestProgressState`.
- No product code (`Source/`) changes.
- No VSTest-filter parser — rejected by the user in favour of NUnit's own resolved tree (D-1).

## P4 Unknowns

- U-1 Is the root work item's child tree already built, from the run's real filter, when the root suite's `BeforeTest` fires? — resolved-by probe (decompiled NUnit 4.6.1 `NUnitTestAssemblyRunner.RunAsync`: `TopLevelWorkItem = WorkItemBuilder.CreateWorkItem(LoadedTest, filter, …, recursive: true)` at decompiled line 210, then `Dispatcher.Start` at :381; `WorkItemBuilder.CreateWorkItem` adds a child only when `filter.Pass(child)` or a descendant passes, decompiled `WorkItemBuilder.cs:64-108`). measured (decompile); runtime confirmation is TO-1.
- U-2 Which leaves fire `ITestAction.BeforeTest/AfterTest`? — resolved-by probe (decompiled `SimpleWorkItem.MakeTestCommand`, `SimpleWorkItem.cs:62`: actions wrap the command only when `RunState == Runnable || (RunState == Explicit && Filter.IsExplicitMatch(Test))`; otherwise `SkipCommand`). measured (decompile).
- U-3 Which suites skip their whole subtree without running child actions? — resolved-by probe (decompiled `CompositeWorkItem.PerformWork`, `CompositeWorkItem.cs:150-197`: `Explicit && !Filter.IsExplicitMatch` → `SkipFixture`; `RunState` `Skipped` / `Ignored` / `NotRunnable` → `SkipFixture`; a failed OneTimeSetUp → `SkipChildren` at run time). measured (decompile). The OneTimeSetUp-failure case is unpredictable up front — see P10.
- U-4 How does the tracker reach the root work item? — resolved-by probe. `TestExecutionContext.CurrentContext.Dispatcher` is public; `SimpleWorkItemDispatcher` and `ParallelWorkItemDispatcher` each hold a private `WorkItem? _topLevelWorkItem` (decompiled, net8.0 and net462 builds of NUnit 4.6.1 both); `MainThreadWorkItemDispatcher` holds none. `WorkItem.Test`, `WorkItem.Filter`, `CompositeWorkItem.Children` and `ITestFilter.IsExplicitMatch` are public (reflected). `ParallelWorkItemDispatcher` swaps `_topLevelWorkItem` for isolated work (decompiled `:265`, `:288`), so the resolver accepts a field value only when `ReferenceEquals(item.Test, rootTest)`. measured (reflection + decompile).
- U-5 At the root suite's `BeforeTest`, is `Context.Dispatcher` NUnit's dispatcher or the repo's `ResourceLaneDispatcher` (which holds no `WorkItem` field)? — resolved-by scout. `ResourceLaneDispatcherInstaller.TryInstall` (`Tests/Base/Parallelization/ResourceLaneDispatcherInstaller.cs:26-35`) is called from `[OneTimeSetUp] TestAssemblySetup` of the global-namespace `[SetUpFixture]` (`Tests/Linq/TestsInitialization.cs:32`, `:226`), a child suite of the assembly suite; the assembly-level action's suite `BeforeTest` runs in the assembly suite's own one-time setup, before that. measured (critic decompile): `NamespaceTreeBuilder.AddSetUpFixture` adds a global-namespace `[SetUpFixture]` as a child of the `TestAssembly` root, and `CompositeWorkItem.MakeOneTimeSetUpCommand` (decompiled `:236-261`) fires the root's actions before any child is dispatched. TO-1 on Tests/Linq is the runtime confirmation; a `totalIsUpperBound: true` there amends the plan.
- U-6 Does the MTP NUnit adapter (6.3.0) pass `--filter` into NUnit's filter, or post-filter results? — resolved-by probe. measured (critic decompile of adapter 6.3.0): `NUnit3TestExecutor.RunTests` → `ConvertVsTestFilterToNUnitFilter` → `Execution.CheckFilter` → `FilterByList` → `NUnitEngineAdapter.Run(listener, filter)`; the framework receives an `<or><test>…</test></or>` list (or a category filter). Exception: `CheckFilter` returns `TestFilter.Empty` when the discovered count exceeds `AssemblySelectLimit` (default 2000) and the filter is not category-only — see P10. Red side measured on master (this worktree, net10.0, `--provider SQLite.MS,SQLite.Classic`, filter `CreateData.CreateDatabase|CountTests.Count1|CountTests.Count2`, `--settings .runsettings`): 18 passed; heartbeat `done: true, total: 22301, completed: 18, etaSec: 56555.333`.
- U-7 Can TO-2 build a work-item tree without NUnit discovering the sample tests as real tests? — resolved-by probe: build the tree by hand over plain methods with no `[Test]`/`[TestCase]` attribute, then `WorkItemBuilder.CreateWorkItem(root, filter, recursive: true)`. measured (critic decompile): `TestMethod` ctors (`:78`, `:88`), `MethodWrapper(Type, string)` (`:75`) and that overload are public; `Test.Actions` is `internal` — not used.
- U-8 `[Repeat]` / `[Retry]` re-enter the action for one case. — resolved-by scout: `TestProgressState.Book` books one unit per full name (`TestProgressState.cs:210-220`), so one leaf = one unit; the counter counts leaves. No change.

## P5 Decisions

### D-1 — Source of the filtered count

- **chosen:** read NUnit's resolved root `WorkItem` (via the dispatcher's `WorkItem` field, verified by `ReferenceEquals(item.Test, root)`) and count the leaves whose action will fire, mirroring U-2/U-3.
- **rejected:** a VSTest-filter evaluator over the test tree (the issue's proposal) — has to reproduce the adapter's FQN mapping and NUnit's parent/explicit match rules, covers `FullyQualifiedName` only; user chose this option out in the session.
- **rejected:** `NUnitTestAssemblyRunner.CountTestCases(filter)` — needs the runner instance, unreachable from an action, and counts non-runnable leaves too.
- **why this:** exact by construction for any filter form the adapter emits (NUnit `where`, id list, `TestCategory != SkipCI` on CI).
- **failure mode of the choice:** depends on a private NUnit field name. Mitigated by the fallback (SC-3) and the guard test (SC-4).

### D-2 — Where the total is set

- **chosen:** only for the root suite (`test.Parent == null`), once; other suites no longer call `SetTotal`. `SetTotal` becomes an assignment carrying an `isUpperBound` flag.
- **rejected:** keep max-wins per suite — a later suite's raw `TestCaseCount` would overwrite the exact root count whenever it is larger.
- **why this:** the root is the only node whose work item covers the whole run.
- **failure mode of the choice:** if the root `BeforeTest` never fires (a run with no runnable tests), `total` stays 0, the same as master's behaviour for that case.

### D-3 — Placement of the counter

- **chosen:** a new public static helper `Tests/Base/TestRunCounter.cs` (`TryResolveRootWorkItem(dispatcher, root)`, `CountActionTests(WorkItem)`, `FindWorkItemFields(Type)`), public like `TestProgressState` so `Tests/Linq/Infrastructure` can test it.
- **rejected:** private methods inside `TestProgressTracker` — untestable without a live run.
- **why this:** keeps the tracker the IO/publishing side, as `TestProgressState`'s summary already describes.
- **failure mode of the choice:** one more public type in the test-infra assembly; no consumer outside Tests.

### D-4 — Corpus follow-ups

- **chosen:** `test-status.ps1` (`completed/?` and no ETA on `totalIsUpperBound`), the `testing.md:284` caveat, `testing.md:910`, and the `test-runner.md:86` staleness tell are parked as a PR comment and applied after merge.
- **rejected:** landing them now — standing user rule to defer corpus docs until the source PR merges.
- **why this:** the old script reads the new JSON correctly in the exact case; only the rare fallback shows a misleading `total`, as master does today.
- **failure mode of the choice:** until the follow-up lands, a fallback run still prints `completed/total` without `?`.

## P6 Edit-points

- E-1 `Tests/Base/TestRunCounter.cs:TestRunCounter` — new: resolve the root `WorkItem` from a dispatcher by reflection over instance fields assignable to `WorkItem`, accepting only `ReferenceEquals(item.Test, root)`; count leaves per U-2/U-3; never throws (returns `null` on any failure).
- E-2 `Tests/Base/TestProgressReporter.cs:TestProgressTracker.OnBefore` — root suite only: `TestRunCounter` count, else fallback `TestCaseCount` with `isUpperBound: true`; non-root suites no longer set the total; replace the "over-counts" comment.
- E-3 `Tests/Base/TestProgressReporter.cs:TestProgressTracker.Write` — emit `"totalIsUpperBound"`; `etaSec` is `null` when the total is an upper bound.
- E-4 `Tests/Base/TestProgressState.cs:SetTotal/Total/TotalIsUpperBound` — `SetTotal(long, bool isUpperBound = false)` assigns; new `TotalIsUpperBound`; `Total` summary updated; the Book() comment about "unfiltered runs" updated.
- E-5 `Tests/Linq/Infrastructure/TestRunCounterTests.cs` — new fixture for TO-2, TO-3, TO-4.
- E-6 `Tests/Linq/Infrastructure/TestProgressStateTests.cs` — TO-3's state half (`SetTotal` assignment + flag); existing `DoneLatchesWhenCompletedReachesTotal` stays.

## P7 Impact map

- `Tests/Base/TestProgressReporter.cs:74` — sole production `SetTotal` caller (scout: `SetTotal\b` over `Tests\`) — covered by E-2
- `Tests/Linq/Infrastructure/TestProgressStateTests.cs:186` — sole test `SetTotal` caller, `DoneLatchesWhenCompletedReachesTotal` (`:182-194`) — covered by E-6 (signature stays source-compatible via default parameter)
- `Tests/Base/TestProgressReporter.cs:248-254` — sole `Total` reader, ETA computation — covered by E-3
- `Tests/Base/TestProgressState.cs:246` — done latch `_completed >= _total` — covered by E-4 (comment only; an exact total makes the latch correct for filtered runs too)
- `Tests/Linq/AssemblyInfo.TestProgress.cs:5`, `Tests/Tests.Playground/AssemblyInfo.TestProgress.cs:5`, `Tests/EntityFrameworkCore/AssemblyInfo.TestProgress.cs:6` — the three projects applying the reporter (scout: `AssemblyInfo\.TestProgress|TestProgressReporter`) — covered by E-2 (shared code); only Tests/Linq is run end-to-end (TO-1), Playground/EF are unexercised, see P8
- `Tests/Base/Parallelization/ResourceLaneDispatcherInstaller.cs:28-33` — replaces `Context.Dispatcher` with `ResourceLaneDispatcher` (no `WorkItem` field) from SetUpFixture OneTimeSetUp — out-of-scope (installed after the root `BeforeTest`, U-5; TO-1 measures)
- `Tests/Base/Attributes/ActiveIssueAttribute.cs:342,353`, `Tests/Base/Attributes/ThrowsWhenAttribute.cs:173,184` — deferred-commit callers of the tracker (scout: `TestProgressTracker`) — out-of-scope (protocol unchanged)
- `.claude/scripts/test-status.ps1:74-82` — sole JSON parser (scout: `\$p\.` / `etaSec` over `*.{ps1,csx,js,…}`) — deferred: D-4, corpus after merge
- `.claude/docs/testing.md:284`, `.claude/docs/testing.md:910`, `.claude/agents/test-runner.md:86`, `.claude/skills/test-progress/SKILL.md:25-28`, `.claude/knowledge-base/areas/TESTS-INFRA/INDEX.md:129` — docs that describe `total` (scout: `test-progress\.|test-status|heartbeat`) — deferred: D-4, corpus after merge
- CI `--filter "TestCategory != SkipCI"` (`Build/Azure/pipelines/templates/test-workflow-windows.yml:246`, `.github/workflows/build.yml:270`) — a non-FQN filter; with D-1 it is counted exactly — covered by E-1 (no CI edit)

## P8 Test obligations

- TO-1 Filtered end-to-end run on Tests/Linq, net10.0, `--provider SQLite.MS,SQLite.Classic`, `--filter` of two test methods plus `CreateData.CreateDatabase`, `--test-progress`: final heartbeat has `done: true`, `totalIsUpperBound: false`, `total == completed`. Red on master: same command shows `total` ≫ `completed` (discriminating input: a filter selecting a small subset of a ~70k-case assembly). — proof: red→green
- TO-2 `TestRunCounterTests.CountsOnlyTestsThatRunTheAction`: hand-built tree (root suite → fixture suite with Runnable ×2, Ignored ×1, Explicit ×1 leaves; an Ignored suite with a Runnable child; an Explicit suite with one Runnable and one Explicit child); per filter case, `CountActionTests(WorkItemBuilder.CreateWorkItem(root, filter, recursive: true))` equals the hand-derived count: (a) empty filter → 2; (b) a FullName filter naming one Runnable leaf → 1; (c) a FullName filter naming the Explicit leaf → 1 (explicit match); (d) a FullName filter naming the Explicit suite → 1 (its Explicit child is not explicitly matched — `SimpleWorkItem.cs:62` re-tests per leaf); (e) a FullName filter naming the fixture suite → 2. Each expected value comes from U-2/U-3, not from a first run; discriminating input: the Ignored/Explicit nodes, which a `TestCaseCount`-based count includes. — proof: red→green (the counter does not exist on master; mutations: dropping the leaf `RunState` test turns (a) red at 4; dropping the suite skip clause turns (a) red at 4; dropping both gives 7, the `TestCaseCount`; inheriting explicit match from the suite turns (d) red at 2)
- TO-3 `TestRunCounterTests.UnresolvableDispatcherYieldsNull` (`TryResolveRootWorkItem(new MainThreadWorkItemDispatcher(), root)` and `(null, root)` → `null`) plus `TestProgressStateTests.SetTotalAssignsAndCarriesUpperBound` (`SetTotal(10, isUpperBound: true)` then `SetTotal(3)` → `Total == 3`, `TotalIsUpperBound == false`). — proof: red→green
- TO-3b `TestRunCounterTests.ResolvesRootWorkItemOnlyForItsOwnTest`: a `new SimpleWorkItemDispatcher()` whose field found by `FindWorkItemFields` is set to `WorkItemBuilder.CreateWorkItem(root, TestFilter.Empty, recursive: true)`; `TryResolveRootWorkItem(dispatcher, root)` returns that item, `TryResolveRootWorkItem(dispatcher, otherSuite)` returns `null`. Discriminating input: the second suite, which a resolver without the `ReferenceEquals` clause accepts. — proof: red→green
- TO-4 `TestRunCounterTests.NUnitDispatchersExposeTopLevelWorkItem`: `FindWorkItemFields(typeof(SimpleWorkItemDispatcher))` and `(typeof(ParallelWorkItemDispatcher))` are each non-empty. Guard: fails on an NUnit bump that drops the field. — proof: characterization
- Unexercised: Tests.Playground and the EF Core projects share E-1/E-2 but are not run end-to-end; they use NUnit's default dispatcher, whose field is guarded by TO-4.

## P9 Verification gates

- G-01: pass — `worktree-test.ps1` (Tests/Linq, net10.0). TO-2/3/3b/4 + `TestProgressStateTests`: 18 passed, all 5 expected tests present. TO-1 red (master): `total 22301, completed 18, done true, etaSec 56555.333`; green (branch, same command, lane dispatcher installed): `total 18, totalIsUpperBound false, completed 18, done true`. Mutation: suite-skip clause dropped → `CountsOnlyTestsThatRunTheAction` red `Count(root, TestFilter.Empty)` 4L vs 2L (and `ResolvesRootWorkItemOnlyForItsOwnTest` 4L vs 2L); reverted, re-run green. `test-diff-sweep.ps1 -IncludeWorkingTree`: 0 narrowed sets, 1 chain at `TestProgressReporter.cs:276` — matches the surrounding column-aligned `sb.Append` block, kept.
- G-02: n/a — Tests/Base infra only, no SQL emitted; the runs wrote no baseline changes.
- G-06: pass — diff touches only E-1..E-6 lines.
- G-07: pass — nothing under `Tests/Tests.Playground/` changed.
- G-09: — (pending) adversarial diff read before the PR opens.
- Extra: pass — `dotnet build Tests/Linq/Tests.csproj -c Release -f net10.0` succeeded, 0 warnings; `dotnet build Tests/Base/Tests.Base.csproj -c Release -f net462` succeeded.

## P10 Adjudicated

- A suite whose OneTimeSetUp fails, or ends `Skipped` (`Assert.Ignore` / `Assume` inside `[OneTimeSetUp]`), skips its children at run time (decompiled `CompositeWorkItem.PerformWork:165-171`), so `completed` ends below `total` for that run; the run still finishes via `MarkDone` at root teardown (`TestProgressReporter.cs:92-93`). Not predictable before execution; accepted.
- Adapter `AssemblySelectLimit` (default 2000; `.runsettings` lifts it to 1 000 000): above the limit a non-category filter is widened to `TestFilter.Empty`, NUnit runs everything, and `total` correctly counts everything. A hand run without `--settings .runsettings` therefore shows a full-assembly `total` for a "filtered" run — that is the run being widened, not this issue regressing. Goes into the D-4 doc follow-up.
- The fallback path keeps master's over-count (marked `totalIsUpperBound: true`) — accepted, D-1 failure mode.

## P11 Amendments

_None._

## P12 Critic verdict

**weak** (plan-critic, model `fable`, 2026-10-21). Searched: decompiled NUnit 4.6.1 (`NamespaceTreeBuilder.AddSetUpFixture`, `CompositeWorkItem`, `SimpleWorkItem`, `WorkItemBuilder`, both dispatchers, `TestFilter`, `TestExecutionContext`, `TestMethod`, `MethodWrapper`) and adapter 6.3.0 (`NUnit3TestExecutor` → `Execution.CheckFilter` → `NUnitEngineAdapter.Run`); `SetTotal|TestCaseCount|\.Total\b` and `RunState` over `Tests\`; heartbeat-field readers over `.claude`; runsettings/props for dispatcher settings; `Source/BannedSymbols.txt`. Strongest point: the counter reuses NUnit's own pre-built filtered tree and predicates. Objections and what changed:
- SC-4 had no committed test of the resolver's positive arm or its `ReferenceEquals` clause → added TO-3b.
- TO-2 could not separate per-leaf from suite-inherited explicit matching → added an Explicit child to the Explicit suite, cell (e), and named the suite-skip and explicit-inheritance mutations.
- P10 covered a failing OneTimeSetUp only → widened to a `Skipped` one-time setup.
- Adapter `AssemblySelectLimit` widening unstated → P10 line + D-4 follow-up.
- P3 "keep meaning" overstated → narrowed to names and types; `total` drops non-runnable leaves on unfiltered runs too.
- U-5 / U-6 / U-7 relabelled measured from the critic's decompile citations; U-6 also carries the measured master red side.
