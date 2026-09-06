# Work plan: feature-activeissue-verify-attribute — Run-and-verify replacement for [ActiveIssue] (EF Core pilot)

**Tier:** L  ·  **Status:** approved  ·  **Approved-at:** 2026-09-05 (user, after critic verdict `weak` folded in)  ·  **Branch:** feature/activeissue-verify-attribute
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

Scope of *this branch*: the new attribute + the EF Core pilot. The 315 `Tests/Linq` sites are a
separate branch (see `P10`).

## P1 Problem

`Tests/Base/Attributes/ActiveIssueAttribute.cs:134` sets `RunState.Explicit`, so a gated test is
**excluded from discovery, not skipped** — it appears in neither the run count nor the skip count
(`.claude/docs/testing.md:60`). 340 application sites across 105 files, of which 315 are
`Tests/Linq` and 25 are `Tests/EntityFrameworkCore`. Three falsifiable defects follow:

1. **Two issues on one test cannot be expressed.** `[AttributeUsage(…, AllowMultiple = false)]`
   (`ActiveIssueAttribute.cs:17`). A test broken on Oracle for issue A and ClickHouse for issue B
   must merge both into one `Configurations` list under one issue reference, losing the attribution.
2. **A fixed issue is never detected.** The gate's only output is the category written at
   `ActiveIssueAttribute.cs:135`; searched across `.github/`, `Build/`, `*.props`, `*.targets`,
   `*.ps1`, `*.sh`, `*.runsettings` and `Tests/` — **written and never read**. The only CI category
   expression is `TestCategory != SkipCI` (`Build/CI/run-provider-tests.sh:130`). A gate therefore
   survives its own fix indefinitely and nothing reports it.
3. **The resulting rot is already present and invisible.** `Tests/EntityFrameworkCore/Tests/IssueTests.cs:232`
   (`Issue4333Test`) and `:1110` (`TempTableSurvivesAcrossCommands`) are written
   `[ActiveIssue(TestProvName.AllPostgreSQL)]`, which binds `ActiveIssueAttribute(string issue)`
   (`:38`) — `TestProvName.AllPostgreSQL` is a `const string` (`TestProvName.cs:101`), **not** the
   `Configuration` property. `Configurations` stays null, `runTest` stays false for every provider
   (`:116-121`), and the test is gated on SQLite, SQL Server and MySQL too — while the comment at
   `IssueTests.cs:1109` says the limitation is PostgreSQL-only.

## P2 Success criteria

- SC-1 A test carrying the new attribute that **passes** is decided `Failure` naming the issue → TO-1
- SC-2 A test that fails with the **declared** error is decided `Inconclusive` → TO-2
- SC-3 A test that fails with a **different** error is decided `Failure` naming expected and actual → TO-3
- SC-3b An inner `Skipped` / `Ignored` / `Inconclusive` / `Warning` result is **passed through unchanged** → TO-3
- SC-4 Two instances on **one method** with disjoint provider targeting each govern their own provider — the capability `AllowMultiple=false` denies today → TO-4
- SC-5 The `--test-progress` heartbeat exposes an `inconclusive` bucket surviving a repeat/retry re-book, and `test-status.ps1` prints it → TO-5
- SC-6 All 24 live EF gates are triaged: `git grep -c "\[ActiveIssue[(\]]" -- Tests/EntityFrameworkCore` returns **0** (the pattern must exclude `[ActiveIssueNew(`, which a bare `\[ActiveIssue` prefix match would count; assumes E-12 removes the dead `FSharpTests.cs:55` gate rather than leaving it), and all four EF suites report zero `Failure` → TO-6
- SC-7 The sentinel formatter emits one parsable ASCII line for a message containing `|`, `%`, a newline and a non-ASCII char → TO-7

## P3 Constraints & anti-goals (M/L)

- **No behaviour change for the 315 `Tests/Linq` gates on this branch.** They keep `RunState.Explicit`;
  this branch must be green and mergeable on its own.
- **No `Source/` change of any kind.** No public API, no `PublicAPI.*`, no `CompatibilitySuppressions.xml`.
- **No CI yml change on this branch** (`.github/workflows/**`, `Build/Azure/**`, `Build/CI/**`).
- **No edit to the primary clone's `UserDataProviders.json`.** The pilot's provider set is seeded in
  the worktree's own copy (U-8), leaving the user's main-test environment untouched.
- **`ThrowsWhen` family semantics unchanged** — `ThrowsForProvider` (509 uses) and subclasses.
  `MessageMatches` is *read*, never modified.
- No reformatting / renaming of lines the change does not already touch.
- The force-fail edit (E-2) is **never committed** on this branch.

## P4 Unknowns (M/L)

- U-1 Does anything still hold the tests back once `RunState.Explicit` is removed? — resolved-by scout: no. Zero `ActiveIssue` hits across `.github/`, `Build/`, `*.ps1`, `*.sh`, `*.runsettings`, `*.props`.
- U-2 Do two `IWrapSetUpTearDown` wrappers on one method nest correctly under the deferral protocol? — resolved-by scout: yes, depth-counted (`TestProgressState.cs:120-129`, `:164`), pinned by `TestProgressStateTests.NestedWrappersBookOnceWithTheOutermostVerdict:121`.
- U-3 Is `Inconclusive` treated as a failure by any script or workflow? — resolved-by scout + probe: `grep -rni "inconclusive"` over `.github/`, `Build/`, `.claude/` → zero hits; and `Build/CI/report-trx.ps1:122` fails the step only on `Failed > 0`, reading the trx `passed`/`failed` counters only (`:56-57`), where `inconclusive` is a separate counter.
- U-4 Can the EF corpus exercise the LinqService branch of the match rule? — resolved-by scout: **no**. Both EF data-source attributes pass `includeLinqService: false`. Covered by unit tests instead (TO-4).
- U-5 Can a newly-enabled EF test hang the pilot? — resolved-by scout: yes. `IssueTests.cs:96` `Issue4603Test` and `:179` `Issue4012Test` are recursive `GetCte<Parent>` queries; `.runsettings` sets no `DefaultTimeout`, none of the 24 carries `[Timeout]`, Npgsql's `CommandTimeout` is infinite when unset and SQLite has none. Mitigated by D-5.
- U-6 Is `FSharpTests.cs:55` a live gate? — resolved-by probe: **no**. `FSharpTests.cs:1` is `#if EF8`; `EF8` is defined only at `Source/LinqToDB.EntityFrameworkCore/LinqToDB.EntityFrameworkCore.EF8.csproj:10`, and `DefineConstants` do not cross a `ProjectReference` — only `Tests.EntityFrameworkCore.EF10.csproj:7` defines anything (`EF10`). **24 live gates, not 25.**
- U-7 What happens when the test is not provider-parameterized (`provider == null`)? — resolved-by reading `ActiveIssueAttribute.cs:114-121`: the gate applies unconditionally even when `Configurations` is set. The new attribute preserves this (D-1's failure mode).
- U-8 Which config file does a worktree run read? — resolved-by probe: **none today**. `C:\Worktrees\linq2db\activeissue-triage\UserDataProviders.json` does not exist, the worktree is **not nested** under the primary clone, and `TestConfiguration.GetFilePath` walks ancestors only — so it climbs from `.build/bin` to `C:\` and finds nothing. The pilot must seed a worktree-local copy (`.claude/docs/worktree.md` → *`UserDataProviders.json` in a worktree*). Sibling worktrees carry one for exactly this reason.
- U-9 Do the six MySQL-scoped gates get local evidence? — resolved-by critic: **partially, and the gap is accepted**. CI runs the EF suite on `MySqlConnector.5.7`, `MySqlConnector.8.0` **and** `MariaDB.11` (`Build/Azure/net80/mysql.json:3-9`, `test-matrix.yml:378-388`), three servers with different error wording. The pilot enables all three locally (containers `mysql`, `mysql57`, `mariadb` all exist and are stopped) so an `ErrorMessage` harvested on one is not silently generalised to the others. Affected sites: `ToolsTests.cs:271,305,320,337,352,702` and `IssueTests.cs:792`.
- U-10 How do MTP + NUnit3TestAdapter 6.2.0 map `Inconclusive` to a run exit code and to the console summary? — **resolved-by probe** (2026-09-05, standalone NUnit 4.6.1 / NUnit3TestAdapter 6.2.0 / MTP 2.3.3 project, one passing + one `Assert.Inconclusive` test): the runner prints `skipped Inconclusive (77ms)`, summarises `total: 2 / failed: 0 / succeeded: 1 / skipped: 1`, reports `Test run summary: Passed!` and **exits 0**. So an inconclusive result does not fail a run (D-3 is sound), and it is folded into the **skipped** bucket — the critic's expectation, confirmed. Consequence: on CI, where no `--test-progress` is passed, the `ActiveIssueNew` population is indistinguishable from genuinely skipped tests, so D-4's heartbeat bucket is the only local counter and Phase 3 needs its own.
- U-11 What does the wrapper do with an inner `Ignored` / `Warning` result? — resolved-by critic: the copied pattern gets it wrong. `ThrowsWhenAttribute.cs:165-176` reports an inner `Ignored` result as `Failure` quoting the ignore reason. Not reachable in the pilot (no gated EF test calls `Assert.Ignore`/`Inconclusive`; `IdTests.cs:44,75,…` do but are ungated), live at Phase 3 — so E-1 defines pass-through explicitly (SC-3b) rather than inheriting the bug.

## P5 Decisions (M/L; rejected alternatives mandatory at L)

### D-1 — Targeting is decided at runtime inside the command, not at build time

- **chosen:** the wrapper calls `NUnitUtils.GetContext(context.CurrentTest)` (`Tests/Base/NUnitUtils.cs:50`) for `(provider, isLinqService)` and decides applicability per test case.
- **rejected:** mirror the old attribute's `CombiningStrategyAttribute` + `ITestBuilder` shape (`ActiveIssueAttribute.cs:18,97`) — two `ITestBuilder`s on one method build the case list **twice**, which is exactly why the old attribute is `AllowMultiple = false`. Keeping it forfeits the headline requirement.
- **why this:** `ThrowsWhenAttribute` proves the pattern at scale — `AllowMultiple = true`, reads `context.CurrentTest.Arguments` at execution time, 864 combined uses across its subclasses. The critic's consumer sweep confirmed `GetContext` resolves a provider for **every** EF case.
- **failure mode of the choice:** a test with no `DataSourcesBaseAttribute`-carrying parameter yields `provider == null` and the instance applies unconditionally, silently ignoring a `Configuration =` the author wrote. Detected by TO-4's null-provider case.

### D-2 — `ErrorMessage` is matched with `ThrowsWhenAttribute.MessageMatches`

- **chosen:** reuse the existing `internal static bool MessageMatches(string actual, string expected)`, which treats `{0}`-style placeholders as patterns and otherwise does `actual.Contains(expected)`.
- **rejected:** a private `Contains` — loses placeholder handling the repo added deliberately so a test can name an `ErrorHelper` format-string constant instead of copying its wording with arguments substituted (the copy is what rots).
- **why this:** the repo's own idiom for this exact question, already handling multi-line messages via `RegexOptions.Singleline`.
- **failure mode of the choice:** an expected message legitimately containing a literal `{0}` is silently treated as a pattern. Inherited, not introduced.

### D-3 — "Still broken" reports `Inconclusive`

- **chosen:** matched failure → `ResultState.Inconclusive`.
- **rejected:** `Success`, which is what `ThrowsWhenCommand` does for an expected throw (`ThrowsWhenAttribute.cs:186`) — it would put a known-broken test in the pass count, reintroducing `P1` defect 2.
- **rejected:** `Skipped` — the test really ran and its outcome is meaningful.
- **why this:** the only NUnit state that is neither pass nor fail, so CI stays green while the population stays countable.
- **failure mode of the choice:** **CI passes no `--test-progress`** (`test-workflow-linux.yml:157`, `run-provider-tests.sh:128-135`), so "the population stays countable" holds for *local* sweeps only; on CI the population is folded into whatever the platform maps Inconclusive to (U-10). Phase 3 must add its own count.

### D-4 — Add a real `inconclusive` bucket to the heartbeat, in `Book` **and** `Unbook`, and surface it

- **chosen:** `_inconclusive` field + `Inconclusive` property + a `case` in both `TestProgressState.Book` (`:222-234`) and `Unbook` (`:251-266`), the JSON line in `TestProgressReporter.Write` (`:269`), **and** the `test-status.ps1` output line (E-14).
- **rejected:** leaving it in the existing `default:` arm — counted in `_completed` but no bucket.
- **rejected:** editing `Book` only — `Unbook` exists so a `[Repeat]`/`[Retry]` re-book does not double-count; an asymmetric pair leaks a count on every re-booked inconclusive case.
- **why this:** it is the local sweep's primary metric. E-14 is what makes the motivation true: without it the JSON carries the bucket and the tool the plan names still prints only pass/fail/skip.
- **failure mode of the choice:** `TestProgressStateTests.cs:226` asserts `Passed + Failed + Skipped == units`; a fourth partition member changes that invariant and the `Recorder` write-tuple (`:277`,`:284`) needs a seventh field. Both in E-5.

### D-5 — The pilot is bounded by two filtered runs per provider, not by test ordering

- **chosen:** per provider, run the 22 safe gates first, then a second filtered run containing only `Issue4603Test` and `Issue4012Test` (U-5), with `--hangdump --hangdump-timeout 5m` on both.
- **rejected:** `[Order]` on the two CTE tests — a change to tests under triage, which is the contamination argument used to reject `[Timeout]` below; and NUnit's default alphabetical order puts `Issue4012Test`/`Issue4603Test` *before* the rest, so a hangdump kill would lose every later case in that run.
- **rejected:** `[Timeout]` / `CancelAfter` — NUnit 4's `CancelAfter` requires the test to take a `CancellationToken`, i.e. changing the signature of a test we are trying to observe.
- **rejected:** provider `CommandTimeout` — infinite for Npgsql when unset, absent for SQLite, so exactly the two providers that can hang are the two that are unbounded.
- **why this:** isolates the only two known-unbounded tests into a run whose loss costs nothing else, using the same `--hangdump` convention as CI.
- **failure mode of the choice:** `--hangdump-timeout` is a **per-test inactivity** guard, not a run budget, so a query making slow steady progress is not caught — visible as a run exceeding its expected wall-clock, not automatically.

### D-6 — The force-fail edit is applied locally and never committed on this branch

- **chosen:** E-2 is applied to the working tree for each sweep and reverted before commit.
- **rejected:** committing it now — it turns all 315 `Tests/Linq` gates red, so the branch could not be merged and every concurrent PR would have to distinguish its own failures from the noise.
- **why this:** the EF triage completes in-session, so the force-fail state only has to exist while sweeping.
- **failure mode of the choice:** an uncommitted edit is lost to a `git stash`/`reset`, and `git apply` **stages**, so `git checkout -- <path>` silently does not revert it. Revert with `git checkout HEAD -- <path>` and prove it with `git diff HEAD`. The 12 untouched self-test fixtures (D-8) are the tripwire if a revert is missed.

### D-7 — The sentinel formatter is committed `Tests/Base` code; only its caller is temporary

- **chosen:** a committed `ActiveIssueSentinel` static in `Tests/Base` owning `Format(...)` and `TryParse(...)`; E-2 (uncommitted) only calls `Format`. Line shape:
  `##L2DB-AI|1|<FullName>|<provider|->|<0|1>|<PASSED|FAILED>|<errorType|->|<message>`, `|`/`%`/newlines escaped, message capped ~500 chars, no stack trace.
- **rejected:** putting the formatter inside E-2 — it would be uncommitted, so nothing could test it and TO-7 could not exist as an obligation at all.
- **rejected:** a side-channel file per case — provider lanes run in parallel since #5614, so an unlocked `File.AppendAllText` throws `IOException` *inside the code under test* and fails the test it is instrumenting.
- **rejected:** relying on the trx `testName` alone — it carries no class name (that lives on `TestMethod/@className`, joinable only by `testId`), and cannot express "this test actually passed" once force-fail has rewritten every outcome to `Failure`.
- **why this:** makes the format testable and gives the `.ps1` parser (E-9) a C# `TryParse` to mirror.
- **failure mode of the choice:** the message is also what a human reads; capping it at one line discards the assertion diff, so a wrong-results case must be re-run locally to see what differed.

### D-8 — The 12 existing self-test fixtures are left untouched

- **chosen:** `ActiveIssueConfigurationTests.cs` (7) and `ActiveIssueGenericTests.cs` (5) keep their current bodies and their `[ActiveIssue]` attributes. New-attribute tests go in E-8 instead.
- **rejected:** rewriting them into unit tests of the new `AppliesTo` (the original plan) — their bodies `Assert.Fail("This test should be available only for explicit run")`, so they fail loudly the moment the **old** gate stops applying. That is precisely the guard `P3`'s first constraint needs while E-2 is hand-applied and hand-reverted on every sweep, and D-6 names a botched revert as its own failure mode.
- **why this:** deleting a tripwire at the moment it is most load-bearing is a bad trade for a tidier diff; it also shrinks `P6`.
- **failure mode of the choice:** the new attribute's targeting logic gets no *migrated* coverage, so E-8 must re-derive the 7 permutations from scratch rather than porting them.

## P6 Edit-points

- E-1 `Tests/Base/Attributes/ActiveIssueNewAttribute.cs` (new) — `NUnitAttribute, IApplyToTest, IWrapSetUpTearDown`, `AllowMultiple = true`; ctors `()`/`(int)`/`(string)`; `Details`/`Configuration`/`Configurations`/`SkipForLinqService`/`SkipForNonLinqService`; `ErrorType`/`ErrorTypeName`/`ErrorMessage`; pure statics `AppliesTo`, `Matches` and **`Decide(innerState, innerMessage, winner, isRemote) → (state, message)?`**; nested `DelegatingTestCommand` reduced to a thin shell over `Decide` under `BeginDeferred`/`CommitDeferred`
- E-2 `Tests/Base/Attributes/ActiveIssueAttribute.cs:106-137` — force-fail mode: drop the `RunState.Explicit` write, add `IWrapSetUpTearDown` calling `ActiveIssueSentinel.Format`. **Applied locally, never committed** (D-6)
- E-3 `Tests/Base/TestProgressState.cs:46-82,203-267` — `_inconclusive` field, `Inconclusive` property, `case` in `Book` and `Unbook`
- E-4 `Tests/Base/TestProgressReporter.cs:258-285` — emit `inconclusive` in the heartbeat JSON
- E-5 `Tests/Linq/Infrastructure/TestProgressStateTests.cs:226,273-288` — inconclusive booking + re-book cases; partition invariant and `Recorder` tuple updated
- E-8 `Tests/Linq/Infrastructure/ActiveIssueNewTests.cs` (new) — `Decide` matrix (SC-1/2/3/3b), `AppliesTo` matrix incl. LinqService and null-provider, precedence/overlap, `ActiveIssueSentinel` round-trip
- E-9 `.claude/scripts/active-issue-triage.ps1` (new, corpus) — sentinel parser mirroring `TryParse`, per-site grouping, suggested annotation
- E-10 `Tests/EntityFrameworkCore/Tests/IssueTests.cs` — 18 gates triaged
- E-11 `Tests/EntityFrameworkCore/Tests/ToolsTests.cs` — 6 gates triaged; the `TestGlobalQueryFilters` gate at `:270-272` sits inside `#if NET8_0_OR_GREATER` and the condition must be preserved
- E-12 `Tests/EntityFrameworkCore/Tests/FSharpTests.cs:55` — dead gate (U-6); removed so SC-6 can reach 0
- E-13 `.claude/docs/testing.md:60,62,64,148` (corpus) — gate semantics and the heartbeat field list, falsified by E-1/E-4
- E-14 `.claude/scripts/test-status.ps1:83` (corpus) — print the `inconclusive` bucket in the one-line summary
- E-15 `Tests/Base/ActiveIssueSentinel.cs` (new) — committed `Format`/`TryParse` (D-7)
- E-16 (procedure, no file) — solo re-run plus bisect corroboration before any removal verdict (A-1, A-2)
- E-17 `Tests/EntityFrameworkCore/Models/Northwind/NorthwindContext.cs:ConfigureEntityFilter` — predicate reads the context property directly instead of a null local (A-4)
- E-18 `Tests/EntityFrameworkCore/Tests/CustomContextIssueTests.cs` — `Issue4669QueryFilterTest` + `Issue4669Context`, a deterministic #4669 repro on an isolated model (A-5)

## P7 Impact map (M/L)

- `Build/CI/run-provider-tests.sh:130`, `.github/workflows/build.yml:233`, `Build/Azure/pipelines/templates/test-workflow-{linux,windows}.yml`, `.runsettings` — searched `TestCategory` and `ActiveIssue` repo-wide: the only category expression is `!= SkipCI`; `"ActiveIssue"` is written (`ActiveIssueAttribute.cs:135`) and read nowhere — out-of-scope on this branch because E-2 is never committed (D-6).
- `Tests/Base/Attributes/SkipCategoryAttribute.cs:28,33` — searched `RunState` across `Tests/` (5 sites; critic's independent sweep agrees). The only other writer of `RunState.Explicit`; its guard short-circuits when `ActiveIssue` already set it. Zero `[SkipCategory(` usage sites exist — deferred: the guard's meaning changes only once E-2 is committed, i.e. on the `Tests/Linq` branch.
- NUnit `[Explicit]` — searched `\bExplicit\b` across `Tests/`: 6 sites, **none** overlapping an `[ActiveIssue]`. `ActiveIssueAttribute.cs:108`'s `RunState != Runnable` early-out is a read and stays — out-of-scope.
- `Tests/Base/TestProgressState.cs:226` `Book` / `:251` `Unbook` — mirrored pair; searched `TestStatus.` across `Tests/Base`. `Unbook` exists solely to reverse `Book`. Covered by E-3 (both arms).
- `TestStatus.|ResultState.|.Outcome|Result.Status` across `Tests/**/*.cs` (critic's sweep) — consumers are `ThrowsWhenAttribute`, `TestProgressState.Book/Unbook`, `TestProgressReporter:100,133`, `TestProgressStateTests`, `ExpectedExceptionAttribute` (0 usages). **No type-keyed helper or lookup keyed on status outside E-3's pair.** Covered by E-3.
- `BaselinesManager.cs:31` / `TestBase.cs:236` `FailCount` readers — searched `FailCount`. Both run in `[TearDown]`, i.e. *inside* the wrapper, so they observe the pre-rewrite result and a rewritten-to-Inconclusive test still skips its baseline dump — out-of-scope: existing behaviour, and the one we want.
- `.claude/scripts/test-status.ps1:83`, `.claude/skills/test-progress/SKILL.md:28`, `.claude/docs/testing.md:148`, `.claude/agents/test-runner.md:102,111` — searched `test-progress|passed|failed|skipped|completed` across `.claude/`. All parse JSON into a `PSCustomObject` or are prose, so an added field breaks nothing; `testing.md:148` enumerates the schema and becomes wrong — covered by E-13; `test-status.ps1` prints only three buckets — covered by E-14.
- `Tests/EntityFrameworkCore/Tests/CustomContextIssueTests.cs:26-32` — searched `EnsureDeleted|LastContexts` across the EF subtree. It **overrides `GetConnectionString` and calls `TestContextTracker.LastContexts.Remove(connectionString)`** with the comment *"as test corrupts database, we should mark it non-created for other fixtures"*, so the next fixture re-inits correctly. Out-of-scope — the earlier claim that it desynchronises the tracker was **false** and the sharding rule it justified has been withdrawn.
- `Parallelizable|LevelOfParallelism|NonParallelizable` across `Tests/EntityFrameworkCore` — none; `ResourceLaneDispatcherInstaller.TryInstall` is called only from `Tests/Linq/TestsInitialization.cs:225`. Localized — searched the EF subtree and `Tests/Base`: **the EF assembly runs sequentially**, so no interleaving hazard between EF fixtures.
- `Tests/EntityFrameworkCore/ContextTestBase.cs:53-66,102-103` + `TestBase.cs:168-238` — searched `EnsureDeleted|EnsureCreated|DB_SUFFIX`. One database per (provider, EF TFM) shared by all 14 fixtures, re-inited on fixture switch. Six of the 24 gated tests insert into shared pre-seeded tables with no cleanup then assert `.Single()`, so a *second* sweep of the same fixture without an intervening fixture switch is untrustworthy — deferred: a sweep-procedure constraint with no code change; enforced by TO-6's re-init rule.
- `ThrowsForProvider|ThrowsWhen|ThrowsFor` across `Tests/EntityFrameworkCore` — Localized — searched the whole EF subtree: **zero matches**, so the new attribute cannot collide with the throws-family in the pilot.
- Reflection consumers of the attribute type — Localized — searched `typeof(ActiveIssue|nameof(ActiveIssue|GetCustomAttributes<ActiveIssue` across the worktree (critic's independent sweep agrees): none anywhere in `Tests/`; hits only in KB prose.

## P8 Test obligations (M/L)

- TO-1 (SC-1) `ActiveIssueNewTests.Decide_PassingTest_IsFailure` — calls the pure `Decide` with an inner `ResultState.Success`; asserts `Failure` and that the message names the issue reference. Proof: **red→green against a named mutant** — `Decide` returning `null` for a Success input (equivalently `Wrap` returning `command` unchanged) must make it fail. A compile-red on a not-yet-existing file is *not* the red.
- TO-2 (SC-2) `…Decide_DeclaredError_IsInconclusive` — inner `Failure`/`Error` whose message matches `ErrorType` + `ErrorMessage`; asserts `Inconclusive`. Proof: **red→green** against the same named mutant.
- TO-3 (SC-3, SC-3b) `…Decide_DifferentError_IsFailure` plus `…Decide_InnerSkippedIgnoredWarning_PassesThrough` — the second asserts `Decide` returns `null` for each of `Skipped`, `Ignored`, `Inconclusive`, `Warning`. Proof: **control** — the same inner result is rewritten under TO-2's declaration and passed through here, so a `Decide` that rewrites unconditionally fails one of the two.
- TO-4 (SC-4) `…AppliesTo` matrix — the 7 targeting permutations re-derived (D-8 keeps the originals in place, so these are new), **plus** `SkipForLinqService`/`SkipForNonLinqService` (unreachable from EF, U-4) **plus** `provider == null` (D-1's failure mode) **plus** two-instance precedence and the equally-specific overlap case. Proof: **red→green** for the two-instance case; **characterization** for the 7 permutations, which must reproduce the old attribute's answers exactly.
- TO-5 (SC-5) `TestProgressStateTests.InconclusiveIsBookedInItsOwnBucket` **and** `…IsUnbookedOnRepeat` — the second is the symmetry guard on the unchanged `Unbook` path and must fail against a `Book`-only implementation, which is how D-4's rejected variant is shown wrong rather than argued wrong. Proof: **red→green**.
- TO-6 (SC-6) The EF sweep. **Inventory first** (U-8/U-9): seed the worktree's `UserDataProviders.json`; enable `SQLite.MS`, `PostgreSQL.16`, `SqlServer.2022.MS`, `MySqlConnector.8.0`, `MySqlConnector.5.7`, `MariaDB.11` in `NETFX`/`NET80`/`NET90`/`NET100`; start `pgsql16`, `sql2022`, `mysql`, `mysql57`, `mariadb`. Cells = provider × {EF3, EF8, EF9, EF10}, minus MySQL on EF10 (`#if !NET10_0`). Each run **asserts a non-zero discovered case count** — a bucket with no enabled provider yields zero EF cases and reports as a pass, which is the vacuous green this obligation exists to exclude. Then per site: run, harvest, annotate, re-run after an intervening fixture switch. Proof: **red→green** per site.
- TO-7 (SC-7) `…SentinelRoundTrip` — `ActiveIssueSentinel.Format` fed a message containing `|`, `%`, CRLF and a non-ASCII char, asserting a single line out and `TryParse` recovering every field. Proof: **control** — the same assertion must fail against an unescaped formatter. This is testable only because D-7 moved the formatter into committed code (E-15).

## P9 Verification gates

- G-01: **pass** — per obligation:
  - TO-1 `Decide_PassingTest_IsFailure` — proof observed: with MUTANT-A (`Decide` returns `null` for `TestStatus.Passed`) built in, this test and only this test went red; reverted, green again.
  - TO-2 `Decide_DeclaredError_IsInconclusive`, `…WithMessageFragment…` — green; same mutant build discriminates.
  - TO-3 `Decide_DifferentErrorType_IsFailure`, `…DifferentErrorMessage…`, `Decide_InnerNonVerdictOutcome_PassesThrough` (4 cases) — control satisfied: the same inner result is rewritten under TO-2's declaration and passed through here.
  - TO-4 `AppliesTo_*` (7) + `SelectGoverning_*` (3), incl. LinqService both directions and the null-provider case.
  - TO-5 `InconclusiveIsBookedInItsOwnBucket` + `InconclusiveIsUnbookedOnRepeat` — proof observed: MUTANT-B (Inconclusive case removed from `Unbook`) reddened the second and only the second, which is what shows D-4's rejected Book-only variant wrong by measurement rather than by argument.
  - TO-6 **pass** — 24/24 live EF gates triaged; `git grep -c "\[ActiveIssue[(\]]" -- Tests/EntityFrameworkCore` returns 0. Post-annotation run: EF10 62 cases 0 failed / 51 inconclusive, EF8 102/0/82, EF9 102/0/82, EF3 95/13/67 where all 13 failures are `SQLite.MS`, the documented net462 `e_sqlite3` gap (memory `reference_ef3_net462_sqlite_native`), not a mismatch. Non-zero case counts observed per leg, so no leg reported a vacuous green.
  - TO-7 `Sentinel_RoundTripsAwkwardCharacters`, `…AbsentProviderAndTypeRoundTripAsNull`, `…LongMessageIsCapped`, `…RejectsForeignLines`, `…ExtractsExceptionTypeButNotAssertionProse`.
- G-02: **n/a for this branch** — EF tests do not write `linq2db.baselines` SQL files (`BaselinesManager` is driven from `Tests/Base` for the main suite; the EF projects produced no baseline output during any sweep). Re-assess on the `Tests/Linq` branch, where newly-passing gates will write baselines they never wrote before.
- G-03: n/a — no new public surface; `Tests/**` ships in no package
- G-04: n/a — no `Source/` change, so no ApiCompat baseline movement
- G-05: **pass** — `Tests.Base` built clean on `net462` and `net10.0` explicitly, and via the EF projects on `net8.0` (EF8) and `net9.0` (EF9) — all four TFMs it targets.
- G-06: **pass** — `git diff HEAD --stat` covers 6 files, all in `P6`; no reformatting of untouched lines. `ActiveIssueAttribute.cs` is absent from the diff, which is the proof that the force-fail edit (E-2, D-6) was reverted against HEAD rather than against the index.
- G-07: n/a — no playground involvement

## P10 Adjudicated (M/L)

- **The 315 `Tests/Linq` gates are out of scope for this branch.** Committing E-2 turns them all red, making the branch unmergeable and poisoning every concurrent PR's signal. Do not flag their continued use of `[ActiveIssue]` in review of this PR.
- **Both `ActiveIssueAttribute` and `ActiveIssueNewAttribute` exist simultaneously after this branch,** with duplicated targeting logic. The rename/delete is the final cutover and needs all 340 sites migrated first.
- **`ActiveIssueNew` is a deliberately ugly name** — the user specified it, to be renamed at cutover.
- **The 12 self-test fixtures keep their `[ActiveIssue]`** (D-8) — they are the tripwire for a missed force-fail revert, not oversight.
- **The MySQL gates' CI-vs-local wording gap is accepted** (U-9): the pilot enables all three MySQL servers locally so an `ErrorMessage` is not generalised across them from a single observation.
- **Over-baselining is not a problem** — the release flow resets `linq2db.baselines` to the anchor commit.
- **#4643 and #4662 are closed, milestoned 6.2.0, citing #5393.** Bisected to `aae685c02` ("Added TypeMapping
  conversion usage", 2026-03-04) against its parent `4c1f1988a` (#5392) — adjacent commits, so the transition
  is pinned. Both failed at introduction (`b7de32bf4`) with issue-specific errors, so the gates were justified
  when written and the removals are correct.
- **Two #4669 tests are deliberately left ungated: `ToolsTests.TestGlobalQueryFilters` and
  `IssueTests.Issue4669Test`.** Both fail only in isolation and pass in any full run, so an `ActiveIssueNew`
  would report "test passed but is marked" and turn CI red. `CustomContextIssueTests.Issue4669QueryFilterTest`
  (E-18) carries the regression coverage instead, and is gated. Do not flag the two ungated ones as missing
  gates.
- **#4669 is not fixed and is not a bisect candidate.** Root cause measured: EF Core's own
  `RelationalSqlTranslatingExpressionVisitor.VisitUnary` on a query filter reading a shadow property via
  `EF.Property`; no linq2db frame in the stack. Scope measured across six providers: MySqlConnector 5.7/8.0
  and MariaDB.11 fail, SQLite / PostgreSQL 13,14,16 / SqlServer 2022 pass — so the original `AllMySql` scope
  was correct.
- **Phase-3 CI facts are stale and must be re-derived.** `.github/workflows/{build,tests,tests-comment}.yml`
  exist on this base; the Azure-only picture recorded above predates them.
- **Phase-3 CI facts, recorded now because they were measured now:** both CIs run tests on this base and a `/azp run` comment starts both, duplicating the 15 Linux legs; Azure is authoritative for Windows/netfx/x86. No per-test artifact is published for the provider suites — the only `.trx` artifact is `cli-test-results-*` (`build.yml:237-242`) and `Tests/LinqToDB.CLI` has zero gates. `Build/CI/report-trx.ps1:86-96` writes one markdown line per failed test into `$GITHUB_STEP_SUMMARY` **uncapped** (only the `::error::` annotations are capped, at 10), so ~1200 failures will approach GitHub's 1 MiB limit. `retryCountOnTaskFailure: 2` plus `run-provider-tests.sh:140`'s `attempts=3` are uncapped by failure count and will re-run guaranteed-red Oracle/Access legs three times against a 180-minute timeout. **CI passes no `--test-progress`**, so the heartbeat bucket is a local-sweep instrument only.

## P11 Amendments (M/L)

- A-1 **A `PASSED` cell is not evidence until the test has also been run in isolation.** The sweep ran a
  filtered subset (`TestCategory=ActiveIssue`), and in-process state left by earlier tests can hide a
  failure: `ToolsTests.TestGlobalQueryFilters` passes in a 64-test fixture run and fails solo with
  `System.Diagnostics.UnreachableException`, masked by `NavigationProperties` alone (bisected from 46
  candidates; `TestToList`, `TestAssociations`, `TestInclude` do not mask it). Every `remove` verdict and
  every provider listed under `passesOn` therefore needs a solo re-run before it is acted on. Applied
  retroactively: `Issue4643Test` and `Issue4662Test` were re-checked solo and hold.
- A-2 **A `remove` verdict must be corroborated by a bisect that finds a fail→pass commit.** If no such
  commit exists, the gate never demonstrated the issue and the test is the defect, not the product. Adds
  `E-16` (no code change; a procedure step recorded in `P8`/`TO-6`).
- A-3 **A gate that is inert today is migrated, not deleted.** The four `#if EF10` filter gates in
  `ToolsTests` were removed as "structurally dead" because EF10 excludes MySQL, then restored as
  `ActiveIssueNew`: the exclusion is `#if !NET10_0` with the comment *"provider need update for v10"*, so it
  is temporary, and deleting the gate would leave the tests unguarded the moment MySQL returns to net10.0.
- A-4 **`Tests/EntityFrameworkCore/Models/Northwind/NorthwindContext.cs:ConfigureEntityFilter` added to
  `P6` as E-17.** Its predicate read `IsSoftDeleteFilterEnabled` through a local initialised to `null` and
  never assigned, so the `enableFilter` parameter every `NorthwindContextTestBase` test passes was inert.
  Fixed to reference the context property directly, matching the `IsFilterProducts` filters in the same
  file. Approved by the user; `ToolsTests` is 64/0 green with it. Independent of #4669, which reproduces
  with or without it.
- A-5 **`Tests/EntityFrameworkCore/Tests/CustomContextIssueTests.cs` added to `P6` as E-18** — a
  deterministic #4669 regression test on its own `DbContext`. The shared-model test cannot serve as one
  (see A-1). Minimal trigger, established empirically: a **shadow** property (`e.Property<bool>("IsDeleted")`)
  reached through `EF.Property` in a `HasQueryFilter`. An earlier attempt using `EF.Property` against a real
  CLR property did **not** reproduce. No joins, no soft-delete machinery and no Northwind model needed.

## P12 Critic verdict (M/L)

**weak** — `plan-critic` on Fable, one pass. Nine objections; the design survived, the test plan did not.

**Accepted and fixed:**

1. *SC-6's metric matches the migrated sites* — `\[ActiveIssue` is a prefix match that counts `[ActiveIssueNew(`, so the criterion could never reach 0. Now `\[ActiveIssue[(\]]`, with E-12's outcome stated. (This error was mine and was also in the census command.)
2. *The `CustomContextIssueTests` `P7` row was false* — verified against `CustomContextIssueTests.cs:26-32`: it **does** clear `TestContextTracker.LastContexts`. Row corrected, TO-6's sharding rule withdrawn.
3. *TO-1..3 had no mechanism* — a gated test that passes is `Failure` by construction so it cannot sit green in the suite, and a nested `NUnitTestAssemblyRunner` shares the static tracker and would fire `MarkDone` on the outer run. Resolved by extracting a pure `Decide` (E-1) and testing at that level, with the `Wrap`-pass-through mutant named as the red.
4. *TO-7 could not exist* — its subject lived in never-committed code with no Pester harness. Resolved by D-7/E-15 moving the formatter into committed `Tests/Base`.
5. *The pilot's runnable cells were not inventoried* — TO-6 now carries the full setup list plus a non-zero-case-count assertion. The critic also surfaced that CI runs EF MySQL on **three** servers (5.7, 8.0, MariaDB 11), so U-9 enables all three locally.
6. *D-5's mitigation named no mechanism* and the natural one (`[Order]`) violates D-5's own contamination argument — now two filtered runs per provider.
7. *E-6/E-7 removed the only guard on `P3`'s first constraint* — the 12 fixtures fail loudly when the old gate stops applying, which is exactly what a botched E-2 revert looks like. Now D-8: leave them untouched; `P6` lost two edit-points.
8. *No arm for an inner Skipped/Ignored/Warning result* — the copied pattern reports Ignored as Failure. Now SC-3b + U-11 + TO-3's second case.
9. *D-4's motivation was not delivered by `P6`* — `test-status.ps1` still printed only pass/fail/skip. Now E-14. The critic also established that **CI passes no `--test-progress`**, which narrows D-3's claim to local runs.

**Carried forward unresolved:** U-10 — the MTP/NUnit3TestAdapter mapping of `Inconclusive` to exit code and summary bucket is still `reasoned, unprobed`; the critic could not check it either (no adapter source on disk). It is now a probe scheduled **before** E-1 is written, and the branch's mergeability depends on it.

**Critic's own strongest finding in favour:** D-1's runtime targeting survived every consumer sweep — no type-keyed helper, no second wrapper, no reflection reader — and `P1` defect 3 is real and cited.
