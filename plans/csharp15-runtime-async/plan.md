# Work plan: csharp15-runtime-async — C# 15 and runtime async on net11.0

**Tier:** L  ·  **Status:** approved  ·  **Approved-at:** 2026-09-19  ·  **Branch:** feature/csharp15-runtime-async
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

Branch 2 of the .NET 11 track. Cut off `feature/net11-support` (PR #5942) at `5ece0ee9e`; worktree
`C:\Worktrees\linq2db\csharp15-runtime-async`.

## P1 Problem

.NET 11 replaces compiler-generated async state machines with runtime async, and linq2db has no
evidence about how its async surface behaves under it. Two concrete, checkable facts today:

- `Directory.Build.props:25` pins `<LangVersion>14</LangVersion>`, so no C# 15 construct compiles
  anywhere in the repo.
- Every net11.0 assembly still lowers `async` classically. Measured on a net11.0 probe built with the
  pinned SDK `11.0.100-rc.1.26425.128`: an `async Task<int>` method carries `AsyncStateMachineAttribute`,
  emits a `<Work>d__0` nested type, and reports `MethodImplAttributes = 0 (IL)`. With
  `<Features>runtime-async=on</Features>` the same method has no attribute, no nested type, and
  `MethodImplAttributes = 8192 (Async)`.

The absent capability is the evidence itself: linq2db's async surface is broad (ADO async through
`AsyncDbConnection`/`AsyncDbTransaction`, hand-written `IAsyncEnumerator` implementations, the
`SafeAwaiter` sync-over-async bridges, four `AsyncLocal` ambient scopes, three remote clients), and
nothing yet says whether it works when the runtime drives suspension instead of the compiler. Without
that, the ship/don't-ship call at .NET 11 RTM has nothing to rest on.

## P2 Success criteria

- SC-1 Every net11.0 target compiles under `LangVersion 15` + `runtime-async=on` in Release, with `TreatWarningsAsErrors` and the Release-only analyzer set active. → TO-1
- SC-2 The opt-in is proven to have taken effect in the emitted assemblies, not merely passed to csc. → TO-2
- SC-3 The full provider matrix runs on net11.0 with runtime async on, and every failure is either absent or attributed to a named cause with a recorded decision. → TO-3
- SC-4 The three stack-budget canaries either pass at their current budgets, or their new budgets and hop counts are measured and recorded. → TO-4
- SC-5 The feature can be turned off by one command-line property, with no project file edited. → TO-5
- SC-6 No other TFM is affected: net462 / netstandard2.0 / net10.0 assemblies keep classic lowering. → TO-6

## P3 Constraints & anti-goals (M/L)

- **Public API unchanged.** No `PublicAPI.*.txt` entry, no `CompatibilitySuppressions.xml` change. The
  change is a compiler switch, not a surface change.
- **No product source edits as part of the enablement.** If a runtime-async defect needs a code
  workaround, that is a `P11` amendment with its own evidence, not silent scope.
- **Performance is explicitly not a success criterion.** The user's call, with the reason: linq2db is
  an ORM whose work is dominated by database I/O, so async-machinery overhead is too small to matter.
  The earlier plan-mode draft carried a query-build + execution benchmark obligation; it is dropped.
  Any number produced is informational and gates nothing. See `P10`.
- **F# and VB `LangVersion` are not touched.** They use a different numbering scheme
  (`LinqToDB.FSharp.fsproj:4` = 9, `Tests.VisualBasic.vbproj:4` = 16.9); a "C# 15" change means
  nothing there.
- **No TFM list changes.** `Build/TargetFrameworks.props` is branch 1's contract and stays as-is.
- **Unmergeable before .NET 11 RTM**, inherited from branch 1: `global.json` pins an exact prerelease
  SDK.
- **Out of scope:** per-project or per-method opt-outs, and an F#-side equivalent (`OtherFlags`).
  Using C# 15 language features was also an anti-goal — *raise the ceiling, don't spend it* — until
  A-1 narrowed it: a feature is adopted only where an analyzer the bump enables demands it, never
  opportunistically.

## P4 Unknowns (M/L)

- U-1 What is the exact opt-in spelling, and does a wrong one fail loudly? Only `runtime-async=on` works; bare `runtime-async` and `runtime-async=true` are accepted by csc and silently ignored (no error, no warning, classic lowering), and `/features:runtime-async` was confirmed to reach csc via `-p:ProvideCommandLineArgs=true -t:Rebuild -getItem:CscCommandLineArgs`, so the flag transports and Roslyn declines to act on it — this is what makes SC-2/TO-2 necessary — resolved-by probe.
- U-2 Does a TFM-conditioned append compose with the existing `<Features>strict</Features>`? Yes: `<Features>strict</Features>` followed by `<Features Condition="'$(TargetFramework)'=='net11.0'">$(Features);runtime-async=on</Features>` produced `MethodImplAttributes = 8192` while keeping `strict`; the same self-referencing append is already proven at `Directory.Build.props:50` (`$(NoWarn);MA0001`), which evaluation shows firing on net11.0 only — resolved-by probe.
- U-3 Do `async` iterators (`async IAsyncEnumerable<T>` with `yield`) convert too? No — `Stream()` kept `AsyncIteratorStateMachineAttribute` and its `<Stream>d__2` nested type at `MethodImplAttributes = 0` in the same assembly where a plain `async Task` method became `Async`, so every compiler-generated async iterator in `Source/**` (`EnumerableHelper.SyncToAsyncEnumerable`/`BatchSingle`/`GetNewEnumerable`, `AsyncExtensions.AsyncEnumerableAdapter`, `LinqToDBForEFQueryProvider.GetAsyncEnumerator`) keeps its current lowering — resolved-by probe.
- U-4 Does `ExecutionContext` still flow across an await under runtime async? Yes — an `AsyncLocal<int>` set before two awaits read back correctly, covering the four ambient-state sites (`ActivityHierarchy:67`, `RetryPolicyBase:77`, `NoLinqCache:15`, `CacheEntryHelper:12`) — resolved-by probe.
- U-5 Does the pinned SDK accept `LangVersion 15`, and does runtime async depend on it? Accepted, and independent — the feature behaves identically on 14, 15 and `latest`, with no `preview` needed — resolved-by probe.
- U-6 Which projects actually produce a net11.0 output? 13 in `Source/`, 12 in `Tests/`, 10 in `Examples/`; everything else is structurally excluded, enumerated in P7 — resolved-by scout.
- U-7 Do the two props files that opt out of the root props need the feature? No — `Source/CodeGenerators/Directory.Build.props` is netstandard2.0-only and `Tests/Tests.T4.Nugets/Directory.Build.props` is net10.0-only, so the net11.0 condition can never fire there; they need the `LangVersion` half only, for parity — resolved-by scout.
- U-12 Does the repo's "netX or newer" idiom survive a future .NET without an edit? Yes — `$([MSBuild]::IsTargetFrameworkCompatible('$(TargetFramework)', 'net11.0'))` evaluates `True` for net11.0, net12.0 and net13.0 and `False` for net10.0, net462 and netstandard2.0, with `Features` coming out as `strict;runtime-async=on` and `strict` respectively — resolved-by probe.
- U-9 Does a TFM-conditioned property in `Directory.Build.props` reach a project that declares a singular `<TargetFramework>` in its body? No — props are evaluated before the body, so the condition never fires there; the same condition moved verbatim into `Directory.Build.targets` does fire (probed both ways on the same project: `implFlags=0` vs `implFlags=8192`), and the critic measured the live consequence on `Tests/Tests.SingleFile/Tests.SingleFile.csproj:6-7`, which evaluates `NoWarn` without the `MA0001` the `:50` precedent is supposed to add — resolved-by probe, and it moved D-1.
- U-10 Does flipping `EnableRuntimeAsync` actually recompile? No, not on its own: `Microsoft.Common.CurrentVersion.targets:3883-3889` hashes `@(Compile)`, `@(ReferencePath)`, `$(DefineConstants)`, `$(LangVersion)`, `$(Deterministic)`, `$(PathMap)` and resources into `CoreCompileCache` and **omits `$(Features)`**, so a switch flip alone skips `CoreCompile` and re-tests the previous binaries — every A/B in P8 must force the rebuild — resolved-by probe.
- U-11 Does the feature reach the F# and VB test projects? F# no (`Fsc` never consumes `$(Features)`), VB yes (`Microsoft.VisualBasic.Core.targets:79` passes `Features="$(Features)"` to `Vbc`), and VB's response to `runtime-async=on` is unprobed — inert today because `Tests/VisualBasic` contains no `Async Function`/`Await` — resolved-by scout, recorded as a P10 residual rather than a blocker.
- U-8 Do the stack-budget canaries shift? The recursion `StackGuard` protects is synchronous (`QueryElementVisitor.Visit`, `ExpressionVisitorBase.Visit`) and `Enter`/`Exit`/`RunOnEmptyStack` are plain sync methods, so those frames are not re-lowered; what can still move is the async frames around a query build and the cost of a `RunOnEmptyStack` hop, and that residual is measured by TO-4 rather than assumed — resolved-by scout.

## P5 Decisions (M/L; rejected alternatives mandatory at L)

### D-1 — Opt-in lives in a new root `Directory.Build.targets`, TFM-conditioned, with no switch property

- **chosen:** `<Features Condition=" $([MSBuild]::IsTargetFrameworkCompatible('$(TargetFramework)', 'net11.0')) ">$(Features);runtime-async=on</Features>`
  in a **new root `Directory.Build.targets`** (the repo has none today), not beside the existing
  `Features`/`NoWarn` block in `Directory.Build.props`.
- **rejected:** an exact `'$(TargetFramework)'=='net11.0'` match, which the first draft used — it has
  to be edited at every .NET release, and the repo already answers that with the compatibility
  function: `Directory.Build.props:81` gates `ADO_ASYNC` and the other feature constants that way, and
  `Directory.Packages.props:146-168` picks package bands that way. Measured across TFMs: `net11.0`,
  `net12.0` and `net13.0` evaluate `True` (`Features` = `strict;runtime-async=on`), `net10.0`,
  `net462` and `netstandard2.0` evaluate `False` (`Features` = `strict`).
- **rejected:** an `EnableRuntimeAsync` switch property, which the first draft carried so the controls
  in `P8` would have an off state — unnecessary, measured: `Features` is an ordinary MSBuild property,
  so passing `-p:Features=strict` as a **global** property overrides the conditioned assignment
  outright (evaluation returns `strict` instead of `strict;runtime-async=on`, and the resulting
  net11.0 build has `stateMachine=True`, `implFlags=0`). A second property to express what a global
  property already expresses is a concept with its own failure mode — most obviously someone pinning
  it in a CI job and no longer testing what ships.
- **rejected:** the root `Directory.Build.props`, which was the first choice — measured wrong. A
  `.props` file is evaluated *before* the project body, so `$(TargetFramework)` is empty there for any
  project that declares a **singular** `<TargetFramework>` in its own body; the condition silently
  never fires. Probed both ways: same probe project, same condition, `Directory.Build.props` →
  `stateMachine=True`, `implFlags=0`; moved verbatim to `Directory.Build.targets` → `implFlags=8192`.
  The `:50` `NoWarn` precedent works only because cross-targeting inner builds receive
  `TargetFramework` as a *global* property, which is visible during props evaluation.
- **rejected:** per-project `<Features>` on each of the 35 net11.0-producing projects — drifts the
  moment a project is added, and the census in `P7` shows four projects already hardcode their TFM.
- **rejected:** an unconditional `<Features>` — emits `MethodImplAttributes.Async` IL into
  netstandard2.0 / net462 / net10.0 assemblies whose runtimes cannot execute it.
- **why this:** `.targets` is imported after the project body, so it sees `$(TargetFramework)` under
  both project shapes — cross-targeting and single-TFM-in-body — and `Features` is not read until
  `CoreCompile`, so setting it that late is still in time. One edit-point, one mechanism, one line,
  and the A/B the ship decision needs costs `-p:Features=strict` rather than a second concept.
- **failure mode of the choice:** the "net11.0 or newer" form means the next .NET version inherits
  runtime async on the day its TFM is added, with nobody having verified it there — accepted, because
  the alternative is a condition that silently *stops* applying and has to be remembered instead.
  Separately, a directory that stops the *targets* walk-up silently misses the feature and nothing
  says so. There are none today — measured: MSBuild discovers
  `Directory.Build.props` and `Directory.Build.targets` independently, so the two isolating props
  files (`Source/CodeGenerators/Directory.Build.props`, `Tests/Tests.T4.Nugets/Directory.Build.props`)
  do **not** block a root `.targets`; a probe reproducing that exact shape evaluated
  `Features=strict;runtime-async=on`. The two are net-standard2.0/net10.0 anyway (U-7), so nothing
  fires there. The first `Directory.Build.targets` added under a subdirectory would reintroduce the
  hole invisibly, and TO-2 is what turns that from silent into red.

### D-2 — `LangVersion 15` repo-wide, not conditioned on TFM

- **chosen:** raise `Directory.Build.props:25` from 14 to 15, and the two opt-out copies with it.
- **rejected:** conditioning `LangVersion` on net11.0 — the same source files compile for every TFM,
  so any C# 15 construct used under the condition would be a compile error on net462 /
  netstandard2.0 / net10.0. A split language version buys nothing and breaks the build the first time
  it is used.
- **why this:** matches how the repo already treats `LangVersion` (one unconditioned value), and
  runtime async does not need it (U-5) — so the two halves of this branch are independent and can be
  reverted independently.
- **failure mode of the choice:** a C# 15 feature that lowers to a BCL type only present on net11.0
  would compile on one TFM and fail on the others, with the error appearing far from this change. The
  anti-goal in `P3` (use no C# 15 feature on this branch) is what bounds it.

### D-3 — Test projects get the feature too

- **chosen:** the net11.0 condition is not scoped to `Source/**`, so all 12 net11.0 test projects
  compile with runtime async. This is the user's stated intent: the suite is the stress test.
- **rejected:** product-only enablement, with tests left classic — halves the exercised surface, and
  the interesting interactions (NUnit's sync-over-async adapter, the custom per-lane thread dispatcher,
  the `IWrapSetUpTearDown` command chain) are exactly in the test host.
- **why this:** ~26 000 tests per provider leg is the largest async workload available, and it is free.
- **failure mode of the choice:** a runtime-async defect inside the test host presents as "test
  infrastructure is broken", which is the hardest failure to attribute. The control is the net10.0 leg
  of the same run, which is classic by construction, plus `-p:EnableRuntimeAsync=false` (D-1).

### D-4 — No performance gate

- **chosen:** measure nothing as a gate; perf regressions do not block this branch.
- **rejected:** the query-build + execution benchmark the plan-mode draft carried — the user's
  judgement is that DB I/O dominates an ORM's async cost, so the number cannot change the decision.
- **why this:** an obligation whose result changes nothing is ceremony, and `measuring-query-build.md`
  work here is expensive (BenchmarkDotNet's child-process toolchain does not work in this repo).
- **failure mode of the choice:** a pathological regression — a hop or an allocation storm in a hot
  path — ships unnoticed. Partially covered anyway: CI leg wall-clock is recorded per run, so an
  order-of-magnitude change would show up as a timing outlier without anyone benchmarking.

### D-5 — Prove the flag took effect once, at implementation time, with no committed test

- **chosen:** inspect the built net11.0 assemblies once — a named linq2db `async` method must report
  `MethodImplAttributes.Async` with no `AsyncStateMachineAttribute`, and the net10.0/net462 builds of
  the same method must still carry the attribute. Recorded in `P9`, not shipped.
- **rejected:** trusting the build alone — U-1 measured that two of three plausible spellings compile
  silently and do nothing, so a green build is not evidence that anything changed.
- **rejected:** a committed regression test asserting the lowering — the user's call: that is testing
  the SDK's behaviour rather than linq2db's, and the suite should not carry it. Noted at the time that
  such a test would also keep re-checking the property after the branch merges; the answer is that the
  branch's own purpose is to decide whether the property stays at all, so there is nothing yet to
  protect.
- **why this:** it produces the same evidence at the moment it is actually needed — before the stress
  run is believed — without adding a permanent test whose subject is the compiler.
- **failure mode of the choice:** a later edit to `Directory.Build.targets` can silently switch the
  feature off and nothing notices, because the verification is a one-off. Partially covered: with the
  feature off the branch is a no-op, so the next `[all]` run would agree suspiciously exactly with
  branch 1's.

## P6 Edit-points

- E-1 `Directory.Build.props:25` — `<LangVersion>14</LangVersion>` → `15`.
- E-2 `Directory.Build.targets` (new file at the repo root) — one `<Features>` append gated on
  `IsTargetFrameworkCompatible(..., 'net11.0')`, per D-1. One property, no switch, no per-release edit.
- E-3 `Source/CodeGenerators/Directory.Build.props:5` — `LangVersion` 14 → 15, parity only (this file
  imports nothing; netstandard2.0, so no `Features` change).
- E-4 `Tests/Tests.T4.Nugets/Directory.Build.props:5` — `LangVersion` 14 → 15, parity only (net10.0,
  isolated build).
- E-5 `Source/LinqToDB/Internal/SqlQuery/SqlTable.cs:80-97` — the `nextSiblingColumn` labeled loop replaces a bool flag plus an inner `break` (A-1).
- E-6 `Source/LinqToDB/Internal/SqlProvider/JoinsOptimizer.cs:67,113-125` — the `nextChildJoin` labeled loop, same shape (A-1).
- E-7 `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuilder.EagerLoadUnion.cs:604,618-629` — the `nextSlot` labeled loop, same shape (A-1).

No test file is added: per D-5 the effectiveness check is a one-off inspection recorded in `P9`.

## P7 Impact map (M/L)

- `Directory.Build.props:25` — the only unconditioned C# `LangVersion`; searched `LangVersion` over the whole worktree, 8 hits: this one, two hand-duplicated copies in props files that import nothing (`Source/CodeGenerators/Directory.Build.props:5`, `Tests/Tests.T4.Nugets/Directory.Build.props:5`), three F# at `9` (`LinqToDB.FSharp.fsproj:4`, `Tests.FSharp.fsproj:7`, `Tests.EntityFrameworkCore.FSharp.props:10`), one VB at `16.9` (`Tests.VisualBasic.vbproj:4`), and zero `.csproj` overrides — covered by E-1 (F#/VB excluded per P3, and E-3/E-4 take the two copies).
- `Directory.Build.props:51` — `<Features>strict</Features>`, unconditioned; searched `<Features>|Features=|WarningsNotAsErrors|CompilerVisibleProperty|OtherFlags`, finding exactly three `Features` sites all holding the bare string `strict` (the other two being the same opt-out files), and no `WarningsNotAsErrors`, `CompilerVisibleProperty` or F# `OtherFlags` anywhere — covered by E-2.
- `Source/CodeGenerators/Directory.Build.props:9` and `Tests/Tests.T4.Nugets/Directory.Build.props:9` — the two duplicated `<Features>strict</Features>` copies, in files whose TFMs are netstandard2.0 and net10.0 respectively, so the net11.0 condition can never fire in either — out-of-scope.
- `Directory.Build.props:50` — the precedent E-2 copies, verified by evaluation rather than reading: `dotnet msbuild Source/LinqToDB/LinqToDB.csproj -p:TargetFramework=<tfm> -getProperty:Features -getProperty:LangVersion -getProperty:NoWarn` returns `Features=strict` and `LangVersion=14` on net11.0, net10.0 and netstandard2.0 alike, and appends `MA0001` on net11.0 only — covered by E-2.
- net11.0 output census — searched every `*.csproj`/`*.fsproj`/`*.vbproj` (83 files) plus the props inheritance chain: 13 `Source/`, 12 `Tests/` and 10 `Examples/` projects produce net11.0, and the four that hardcode the literal moniker (`LinqToDB.EntityFrameworkCore.EF11.csproj:6`, `Tests.EntityFrameworkCore.EF11.csproj:6`, and the two EF10 counterparts) still import the root props — covered by E-2.
- Projects structurally excluded from net11.0 — analyzers and `CodeGenerators` (`netstandard2.0`, Roslyn-component requirement), LINQPad (`net472;net8.0-windows7.0`, plus a `net8.0` pack project), 14 NuGet meta-packages and WCF (`net462`), EF3 (`netstandard2.0;net462`), EF10 (`net10.0`), `Tests.Analyzers`/`Tests.Analyzers.Internal` (`net10.0`), `Tests/Tests.T4.Nugets/**` (`net10.0`, isolated), `.github/.github.csproj` (`net10.0`) — out-of-scope, and collectively the reason D-1 conditions on the TFM.
- `Directory.Build.props:225-228` and `Tests/Directory.Build.props:5-6` — the `Testing` configuration collapses every inheriting project to net11.0 only (repeated in the three projects that override their own TFM list), so after E-2 the documented fast-iteration loop silently becomes a runtime-async build — covered by E-2.
- `Source/LinqToDB/Internal/Common/StackGuard.cs` — probes every 8 recursion levels (`StackProbeInterval = 8`, tuned down from 64 against a documented ~220 bytes/level x64 budget) and hops via `Task.Factory.StartNew` + `AsyncWaitHandle.WaitOne()` + `GetAwaiter().GetResult()`, with both consumers (`QueryElementVisitor:29,41,80,82`, `ExpressionVisitorBase:12,22,24,31`) synchronous — covered by E-2, measured by TO-4.
- Reflection over async internals in `Source/**` — searched `AsyncStateMachine|IAsyncStateMachine|GetStateMachineAttribute|AsyncMethodBuilder|d__\d+` and separately `INotifyCompletion|ICriticalNotifyCompletion|IValueTaskSource|ExecutionContext|SynchronizationContext`: zero hits for all of them — out-of-scope.
- Sync-over-async bridges — `Internal/Async/SafeAwaiter.cs` (7 call sites), `StackGuard.cs:91`, `SignalRDataContext.cs:59`, `YdbProvider.cs:26`, `YdbProviderAdapter.cs:145`, all blocking on a `Task` from a sync frame, and the path with a recorded prior incident (`ParameterTests.cs:1496-1504`, an 11-minute CI hang from pool starvation) — covered by E-2, exercised by TO-3.
- Hand-written `IAsyncEnumerator` implementations — 10 sites (`AsyncEnumeratorAsyncWrapper`, `CommandInfo.ReaderAsyncEnumerator`, `LimitAsyncEnumerator`, `AsyncBatchEnumerator`, `GroupingAsyncEnumerator`, two `ExpressionBuilder` wrappers, `ExpressionQuery`, `LoadWithQueryable`, `BulkCopyReader`), ordinary classes whose `async` members are re-lowered, alongside 5 compiler-generated async iterators that U-3 measured as unaffected — covered by E-2, exercised by TO-3.
- `ADO_ASYNC` — defined at `Directory.Build.props:81` for anything net8.0-compatible, so net11.0 takes the same branch as net10.0 today across all 7 `#if` sites, none of them net11.0-specific — out-of-scope.
- Stack-budget tests — `StackUseTests.cs:121` (200 KiB thread), `:149` (150 KiB) and `Issue3674Tests.cs:34` (80 KiB, +10 KiB for ClickHouse Octonica) assert nothing, passing when `Thread.Join()` returns and failing as an uncatchable `StackOverflowException` that kills the test process, while `TestExpressionVisitorHops`/`TestSqlVisitorHops` assert the exact nesting depth (0/1/2) of `InsufficientExecutionStackException` — covered by E-2, measured by TO-4.
- Test infrastructure around async — searched `SynchronizationContext` and `Task\.Run\(` under `Tests/Base`, zero hits; what exists is the `IWrapSetUpTearDown` chain (`ActiveIssueAttribute`, `ThrowsWhenAttribute`) driving `innerCommand.Execute` synchronously and `ResourceLaneDispatcher:322` running each leaf work item on a dedicated background thread, where an interaction would present as a hung lane rather than an assertion failure — covered by E-2, exercised by TO-3.
- Test categories — `Tests/Base/TestCategory.cs` defines only `SkipCI`, `Create` and `FTS`, so no async subset can be selected by an existing filter and a targeted pass needs an explicit test-name filter — deferred: TO-4 names the tests directly instead.
- `Tests/Tests.SingleFile/Tests.SingleFile.csproj:6-7` — the one net11.0 project that sets a singular `<TargetFramework>` in its body and clears `<TargetFrameworks>`, so props-level TFM conditions never fire for it (measured: its `NoWarn` lacks `MA0001`); `Tests/Tests.Analyzers/Tests.Analyzers.csproj:7` has the same shape and becomes net11.0 the day net10.0 is dropped — covered by E-2, which is why D-1 moved to `Directory.Build.targets`.
- `Examples/**` — 10 net11.0 projects that are **not** in `linq2db.slnx` (searched it: only `Tests.SingleFile` at `:337`); they build from `Examples/Examples.slnx`, Debug-only in CI (`build-job.yml:49-50`, `.github/workflows/build.yml:176`) — covered by E-2, with TO-1 extended to build that solution rather than leaving SC-1 unproven for them.
- F# and VB test projects — `Fsc` never consumes `$(Features)` (searched the SDK's F# targets, zero hits), so `Tests.FSharp`, `Tests.EntityFrameworkCore.FSharp.EF11` and `LinqToDB.FSharp` are unaffected; `Microsoft.VisualBasic.Core.targets:79` does pass `Features` to `Vbc`, so `Tests/VisualBasic` receives the flag, and it contains no `Async Function`/`Await` — out-of-scope for F#, deferred: VB carries no async code to exercise.
- `Tests/BannedSymbols.txt:25-26,74,80-87` — bans `GetCustomAttribute<T>()`, `GetCustomAttributes(bool)` and `Attribute.IsDefined`, and `MethodImplAttributes.Async` exists only in the net11.0 BCL; both constrained the committed effectiveness test the first draft carried — out-of-scope now that D-5 makes the check a one-off inspection rather than a shipped test.
- `CONTRIBUTING.md:87` — documents `SupportedNetVersions`/`LatestNetVersion`, names that `Build/TargetFrameworks.props` replaced with `ModernTargetFrameworks`/`LatestTargetFramework` — out-of-scope: the drift belongs to branch 1 (#5942), which introduced the rename, and it was fixed there as `328e00a4a`.

## P8 Test obligations (M/L)

- TO-1 (SC-1) Release build of `linq2db.slnx` on the branch with analyzers and `TreatWarningsAsErrors` active (which covers all four TFMs, so the portable-TFM gate comes with it), plus a **Debug** build of `Examples/Examples.slnx` — Debug, not Release, per A-2: that solution's Release build is red on the base too, so the Release form of this obligation cannot distinguish this branch from any other — proof: characterization, asserting no new behaviour, only that the switch compiles everywhere.
- TO-2 (SC-2) The D-5 effectiveness check, run once at implementation time and recorded in P9 rather than committed — on the built net11.0 `linq2db.dll` a named `async` method reports `MethodImplAttributes.Async` and carries no `AsyncStateMachineAttribute`, with the member chosen by first confirming on net10.0 that it is a real `async` method rather than merely `Task`-returning, and the mutation that must actually be run is the same inspection after `-t:Rebuild -p:Features=strict` — proof: control.
- TO-3 (SC-3) Full `tests [all]` matrix on the branch head, discriminated against branch 1 at `5ece0ee9e`, whose own `[all]` run is the control over an identical test corpus so any delta is attributable to this branch's two properties; sub-surfaces that must be exercised rather than assumed are the `SafeAwaiter` sync-over-async paths (remote/LinqService legs), the 10 hand-written `IAsyncEnumerator` implementations, and `BulkCopyReader` — proof: control.
- TO-4 (SC-4) Stack budgets run as an explicit pair rather than inside the sweep — `StackUseTests.EagerLoadProjection`, `StackUseTests.TestStackHopOption`, `StackUseTests.TestExpressionVisitorHops`, `StackUseTests.TestSqlVisitorHops`, `Issue3674Tests.InThread` on net11.0, first with the feature on and then rebuilt with `-t:Rebuild -p:Features=strict`, recording per test the asserted hop depth or thread survival; a budget change is a result to record, a process crash is a blocker — proof: control.
- TO-5 (SC-5) `-t:Rebuild -p:Features=strict` on a net11.0 build produces classic lowering, i.e. TO-2's inspection inverted and therefore not an independent obligation, kept because it is what proves the off-switch the ship decision relies on is real rather than assumed — proof: control.
- TO-6 (SC-6) The unchanged path — the net10.0 and net462 builds of the same assembly still carry `AsyncStateMachineAttribute` on the method TO-2 inspects, catching the feature leaking to a TFM whose runtime cannot execute it — proof: control.
- TO-7 (SC-2, SC-4, SC-5, SC-6) Every arm of TO-2/TO-4/TO-5/TO-6 is built with `-t:Rebuild` (or `--no-incremental`) and each records that `CoreCompile` actually ran, because `Microsoft.Common.CurrentVersion.targets:3883-3889` omits `$(Features)` from `CoreCompileCache` and a `-p:Features=` override touches no file in `$(MSBuildAllProjects)` — without this both arms re-test the same binaries and every control reads as a silent clean — proof: control.

## P9 Verification gates

- G-01: — (pending) — TO-3's full matrix plus TO-4's explicit control pair.
- G-02: — (pending) — a compiler switch is not expected to move emitted SQL, so a non-empty baselines diff is itself a finding rather than a formality.
- G-05: pass — subsumed by the whole-solution Release build, which compiles all four TFMs: `dotnet build linq2db.slnx -c Release -m:2` → 0 errors, 6 warnings (pre-existing `MSB3277` reference-unification noise in `Tests.Benchmarks`), 18m04s. A separate `-f netstandard2.0` pass would re-test what this already covered.
- **Examples (TO-1, second half): pass** — `dotnet build Examples/Examples.slnx -c Debug -m:2` → 0 errors, 0 warnings, 3m15s, all 10 net11.0 projects compiled with `LangVersion 15` and runtime async on. Release is red on the base too, hence A-2.
- **Off-switch control (TO-5, TO-7): pass.** `dotnet build Source/LinqToDB/LinqToDB.csproj -c Release -f net11.0 -t:Rebuild -p:Features=strict` → net11.0 inverts to **0 `MethodImpl.Async` / 254 `AsyncStateMachineAttribute`**, i.e. the net10.0 shape; rebuilding without the override returns it to **254 / 0**. Both arms forced `CoreCompile`, so the negative is a real negative rather than a stale binary. Trap worth knowing for any repeat: the inspection script memory-maps the assembly via `PEReader`, and leaving it undisposed makes the *next* build fail with `MSB3027`/`MSB3021` ("user-mapped section open") — it reads as a file-permission problem several steps from its cause.
- **D-5 effectiveness check (TO-2, TO-6): pass.** Metadata-only inspection of `.build/bin/LinqToDB/Release/<tfm>/linq2db.dll` via `PEReader` (`.build/.agents/inspect-lowering.ps1`), counting methods whose `ImplAttributes` carry `0x2000` against methods carrying `AsyncStateMachineAttribute`: **net11.0 → 254 / 0** (first hit `LinqToDB.DataContext.ReleaseQueryAsync`), **net10.0 → 0 / 254**, **net462 → 0 / 255**, **netstandard2.0 → 0 / 255**. Every async method converted on net11.0, none anywhere else — the feature is on, and it did not leak to a TFM whose runtime cannot execute it.
- G-06: — (pending)
- G-07: — (pending)
- G-09: — (pending) — Tier L, per `work-plan.ps1 -Action gates` (G-03/G-04 n/a: no public surface; G-08 n/a: no engine-code edit).

## P10 Adjudicated (M/L)

- **No performance measurement.** Dropped on the user's explicit judgement that DB I/O dominates an
  ORM's async cost, so the number cannot change the ship decision (D-4). A review finding that this
  branch ships without benchmarks is answered by this entry.
- **The `Testing` configuration silently becomes a runtime-async build.** Accepted rather than
  special-cased: it collapses to net11.0 by design, and making the fast loop classic would mean local
  iteration no longer matches what CI compiles.
- **`Tests.Analyzers`, `Tests.Analyzers.Internal`, LINQPad, CLI-adjacent net462 and netstandard2.0
  projects are untouched by the feature.** Structural, not an oversight — their TFMs cannot satisfy
  the condition (P7).
- **No committed test asserts that runtime async is on.** The user's call: the lowering is the SDK's
  behaviour, not linq2db's, and the suite should not carry a test for it (D-5). The evidence is
  produced once, at implementation time, and recorded in `P9`.
- **No `EnableRuntimeAsync` switch property.** The off-switch is `-p:Features=strict`, which is a
  global MSBuild property and therefore already overrides the conditioned assignment — measured
  (D-1). A review finding that the feature "cannot be turned off without editing a file" is answered
  by this entry.
- **`Vbc` receives `runtime-async=on` and its handling of it is unprobed.** `Tests/VisualBasic`
  contains no `Async Function` or `Await`, so there is nothing for it to lower either way; if VB ever
  gains async code here, the flag's VB behaviour becomes a real unknown rather than an inert one
  (U-11).
- **F# projects never see the feature.** `Fsc` does not consume `$(Features)`, so `LinqToDB.FSharp`,
  `Tests.FSharp` and `Tests.EntityFrameworkCore.FSharp.EF11` stay classic on net11.0 while the C#
  assemblies around them do not. Accepted: there is no F# opt-in short of `OtherFlags`, which the repo
  does not use anywhere.

## P11 Amendments (M/L)

- A-1 (2026-09-19, after the first Release build) — **`LangVersion 15` turns on IDE0410 and the repo
  builds it as an error.** The first Release build of `linq2db.slnx` failed with 12 `IDE0410` errors —
  3 unique sites × 4 TFMs, all in `Source/LinqToDB`, all the same shape: a bool flag set inside an
  inner loop, an inner `break`, then `if (flag) continue;` in the outer one. That is the pattern C# 15
  labeled jumps replace, and the repo's global `dotnet_analyzer_diagnostic.severity = error` plus
  `TreatWarningsAsErrors` makes it a build stopper rather than a suggestion. Options put to the user:
  `NoWarn` the rule, adopt labeled jumps, or downgrade to suggestion. **User chose to adopt**, so E-5,
  E-6 and E-7 are added and `P3`'s "use no C# 15 feature" anti-goal narrows to "adopt one only where
  an analyzer the bump enables demands it". The syntax was probed before touching product code — a
  net11.0 `LangVersion 15` program with `outer:` on a loop and `continue outer;` from a nested loop
  compiles and behaves correctly. Approval of the E-5…E-7 surface is the user's answer to that
  question; the rest of the plan's approval is unaffected. **The count may grow:** the failing build
  stopped at `Source/LinqToDB`, so no project downstream of it has compiled yet and further IDE0410
  sites may surface — each one is covered by this amendment's disposition, not a new decision.
- A-2 (2026-09-19, after the Examples build) — **TO-1's Release build of `Examples/Examples.slnx` is scoped down to Debug.** The critic's O-3 was right that SC-1 counted 10 `Examples` projects no obligation compiled, and the fix as written said "Release". Building it produced 60 errors, all ordinary analyzer findings (`MA0047`, `MA0048`, `CA1050`, `MA0076`) in `Examples/Compat/ConfigurationManager/Program.cs` and its siblings — nothing to do with C# 15 or runtime async. **Verified pre-existing** rather than assumed: the same project built `-c Release` in the branch-1 worktree (`LangVersion 14`, no runtime async) fails on the same rules, 16 errors on net462. The cause is structural — analyzers are Release-only in this repo and CI builds `Examples` **Debug-only** (`build-job.yml:49-50`, `.github/workflows/build.yml:176`), so that solution's Release configuration has never been green and gates nothing. Demanding it here would import 60 unrelated fixes into a compiler-switch branch. Debug still compiles those projects with `LangVersion 15` and `runtime-async=on`, which is the coverage SC-1 actually wants. The Examples-in-Release gap is a real finding and belongs to its own issue, not this branch.

## P12 Critic verdict (M/L)

**weak** — `plan-critic` on a different model, run against the branch worktree. Five objections, all
accepted; four of them re-verified here rather than taken on the critic's word, and two changed the
design. What it searched: `AsyncStateMachine|IAsyncStateMachine|AsyncMethodBuilder|MethodImplAttributes`
over every `.cs/.vb/.fs` (0 hits), the `LangVersion`/`Features` inventory (matched P7), every
`<TargetFramework(s)>` declaration (found the one singular-TFM net11.0 project), an MSBuild evaluation
of `Tests.SingleFile`, `RuntimeAsync|runtime-async` over the SDK targets (no property-name collision
with `EnableRuntimeAsync`), the ApiCompat configuration (no `AttributesMustMatch`, so P3's
no-baseline-change claim stands), and the three stack canaries plus `StackGuard` (U-8 stands).

- **O-1 — the A/B controls could not see a negative.** `CoreCompileCache` omits `$(Features)`, so a
  switch flip alone skips `CoreCompile`. Verified directly in
  `Microsoft.Common.CurrentVersion.targets:3883-3889`. → new U-10 and TO-7; TO-2/4/5/6 now carry
  `-t:Rebuild`.
- **O-2 — the props-level condition cannot reach a project whose body sets a singular
  `<TargetFramework>`, and one exists.** Re-probed both placements on the same project:
  `Directory.Build.props` → `implFlags=0`, `Directory.Build.targets` → `implFlags=8192`. → D-1's
  placement changed to a new root `Directory.Build.targets`, its failure-mode line corrected, new U-9,
  new P7 rows for `Tests.SingleFile` and `Tests.Analyzers`.
- **O-3 — TO-1 did not compile the 10 `Examples` projects SC-1 counts.** Verified: `linq2db.slnx`
  contains no `Examples` entry. → TO-1 extended to `Examples/Examples.slnx`.
- **O-4 — the "12 test projects" census was overstated**: two F# (Fsc ignores `Features`), one VB
  (Vbc receives it, unprobed), one single-TFM-in-body. → U-11, two P7 rows, two P10 entries.
- **O-5 — E-5 as written would trip `Tests/BannedSymbols.txt`** (`GetCustomAttribute`/`IsDefined`
  banned) and cannot name `MethodImplAttributes.Async` on a pre-net11 BCL; it also never named the
  method under test. → TO-2 and TO-6 rewritten; new P7 row.

**Post-critique revision (user review, not the critic).** Three changes, all narrowing or hardening,
none widening: the `EnableRuntimeAsync` switch was cut (D-1), the committed effectiveness test was cut
(D-5, and with it E-5), and the exact-TFM match became the repo's `IsTargetFrameworkCompatible`
idiom (D-1). `P6` went from five edit-points to four with no new test file; no area was added and no
surface widened, so the critic was not re-dispatched. Each cut rests on a measurement taken after the
verdict: `-p:Features=strict` as a global property overrides the conditioned assignment, and the
compatibility function evaluates `True` from net11.0 forward. O-5's `BannedSymbols`/`0x2000` objection
is moot now that no test is committed.

Carried forward, not closed: the critic could not check VB's actual response to `runtime-async=on`
(P10 records it as inert-today), and did not confirm branch 1 has an `[all]` run at `5ece0ee9e` —
which it does: the matrix went 19/20 at `894491b41` with the one red leg re-run green at `5ece0ee9e`.
