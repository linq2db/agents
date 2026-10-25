# Running Tests

Tests use **NUnit3** with **Shouldly** assertions (not NUnit Assert), running on **Microsoft.Testing.Platform** (MTP) — selected via `global.json` — not VSTest. Test targets: `net462`, `net8.0`, `net9.0`, `net10.0`. **Always use Debug configuration and prefer `net10.0`** — Release enables Roslyn analyzers and is much slower to build. The full test suite takes ~1 hour or more; avoid running it unless necessary.

**"Not NUnit Assert" covers *value* assertions only.** Use Shouldly (`.ShouldBe`, `.ShouldBeGreaterThan`, …) for value checks, but **exception assertions use NUnit `Assert.Throws<T>` / `Assert.ThrowsAsync<T>`** — Shouldly's `Should.Throw` / `Should.NotThrow` do **not** compile in this repo (`CS0117: 'Should' does not contain a definition for 'Throw'`). For a "does not throw" case, just run the call directly (an unexpected throw fails the test). Also: `Tests/Linq` has **no `InternalsVisibleTo`** for LinqToDB internals — public types under `LinqToDB.Internal.*` (e.g. `QueryCache`, `AttributeReader`) are testable directly, but a genuinely `internal` type (e.g. the `BoundedCache` storage primitive) is inaccessible from tests (`CS0122`); test it through a public API rather than widening its surface or adding IVT.

**Don't prepend a `dotnet build`.** `dotnet test` builds the project automatically if binaries are stale; a standalone `dotnet build` right before `dotnet test` only adds waiting time. If a test run fails with compile errors, fix them and re-run `dotnet test` directly.

Under MTP, `dotnet test` takes the project via `--project` (a solution/filter via `--solution`) — the bare `dotnet test <project>` form is rejected. Always pass `--settings .runsettings` so NUnit honors `AssemblySelectLimit`; otherwise a broad `--filter` can fall back to running the whole assembly.

**Don't pass MSBuild switches to `dotnet test` — they are forwarded to the test platform and silently void the filter.** MTP's `dotnet test` hands arguments it doesn't recognise to the test application rather than rejecting them, so an MSBuild switch like `-m:1` is consumed as a test-platform argument: the run ends in **`Zero tests ran` (exit 5)** with no diagnostic naming the switch. The failure mimics a filter that matched nothing, which is the expensive part — the natural next move is to re-check the filter and the assembly, not the flag you added for an unrelated reason. Keep such switches on the `dotnet build` step and run `dotnet test --no-build` afterwards. (Surfaced on #5737: a filter returning `total: 2` returned `total: 0` after `-m:1` was added to reduce build parallelism.)

```bash
# Run a single test class or method
dotnet test --project Tests/Linq/Tests.csproj --filter "FullyQualifiedName~ClassName.MethodName" -f net10.0 --settings .runsettings --test-progress

# Run tests with the lightweight playground solution (faster load)
dotnet test --solution linq2db.playground.slnf --settings .runsettings --test-progress
```

**`--filter` takes `FullyQualifiedName~<substring>` — the MTP *graph-query* form silently matches nothing.** A pattern like `/*/*/RemoteContextTests/*` (asm/namespace/class/method, valid in some MTP surfaces) returns **`Zero tests ran` (exit 5)** through `dotnet test` rather than being rejected as a bad pattern, so it is indistinguishable from a filter that legitimately matched nothing — and from the unbuilt-binary case above, which reports identically. Substring matching against the fully-qualified name is what works, and it matches a whole fixture (`FullyQualifiedName~RemoteContextTests`) as readily as one method. **A sibling *option* name fails the same way:** `--filter-method '*Foo*'` is accepted by `dotnet test` and returns `Zero tests ran` (exit 5) rather than an unknown-option error, so a plausible-looking flag you half-remember costs a full run to disprove. On a small DB-free project, running the whole suite unfiltered is cheaper than one wrong guess. Note the multi-filter `|` form under *Targeted repro in a worktree* below is documented for the **test executable**; it is untested through `dotnet test`.

**A `(` in a `--filter` value is filter syntax, not part of the name.** Parentheses group filter expressions, so a term written to anchor on the end of a method name — `FullyQualifiedName~.MyTest(` — crashes the test application before any test runs with *`Incorrect format for TestCaseFilter Error: Empty parenthesis ( )`* (exit 82 from the test exe). A filter cannot anchor on where a method name ends, so write `FullyQualifiedName~.MyTest` and keep method names unique enough to make the substring unambiguous. (Surfaced on #5959, joining fourteen method names into one `|` filter.)

**`Zero tests ran` is a filter miss, not a red — and the sibling async fixture is a *different class*.** The dangerous case is a `Fixture.Method` filter, because `FullyQualifiedName~` is a plain substring match and the `.` makes the fixture name load-bearing: `~CompileTests.Foo` matches nothing in `CompileTestsAsync`, while the bare `~CompileTests` matches both fixtures. The failure is silent and the exit code is non-zero, so during a mutation experiment — where you *predicted* a red — it reads as your own model being refuted. Check `total:` before reading the verdict: `total: 0` means nothing executed and the run says nothing either way. The mirror is worth knowing too: a `total:` higher than expected means the filter caught a sibling fixture you didn't intend, which quietly widens what a "green" covers. (Surfaced on #5844: `~CompileTests.ElementFormLoadWithHonorsCancellation` returned `Zero tests ran` because that test lives in `CompileTestsAsync`; it was nearly recorded as arm 1 refuting its own prediction.)

**A green summary from a chained build-then-run proves nothing until you read the *build's* exit code.** When one command builds and then runs — `dotnet build … ; <exe> --filter …`, the shape a background task naturally takes — a **failed build leaves the previous binary in place** and the run proceeds against it. It then reports a full, plausible `total:` with `failed: 0`, for code the binary does not contain. Neither tell above fires: `total:` is not 0, and the duration heuristic does not catch it because the tests genuinely executed. So check the build's exit code, or grep its log for `Build FAILED` / `Build succeeded`, before quoting any number from the run. On this machine the cause is usually resource exhaustion rather than a code error — `CSC : error CS8104 … There is not enough space on the disk` and host OOM kills both land here, and both are transient, so the same command succeeds on retry and the stale result is never revisited. (Surfaced on #5740: `126 total, 0 failed` was reported to the user as confirmation of a change the binary did not contain — the build had died on CS8104 three minutes in. The honest re-run of the same fixture found two failures, one of them a real stale test expectation.)

**Default to `Tests.Playground` for any iterative test run** — fresh tests, fix-verification on existing tests, ad-hoc repro. The full `Tests/Linq/Tests.csproj` build is ~3+ minutes; the playground project is ~30s. Two distinct shapes:

1. **Scratch verification** — one-off tests that won't be committed. Edit `Tests/Tests.Playground/TestTemplate.cs` directly with a self-contained fixture (define converters / tables / data inline). No `<Compile Include>` needed; the SDK-style csproj implicitly compiles the project's own `*.cs` files. Revert when done — the template-edit is scratch (per `agent-rules.md` → *Never commit playground scratch*).
2. **Iterating on a real test in `Tests/Linq/`** — add `<Compile Include="..\Linq\<sub>\<File>.cs" Link="<File>.cs" />` to `Tests/Tests.Playground/Tests.Playground.csproj`. The link is local scratch and must **not** be committed (same rule). Use this shape when iterating on a test that already lives in `Tests/Linq/` (e.g. a regression test you just wrote alongside a fix) without paying the cost of the full `Tests/Linq/Tests.csproj` multi-TFM build.

```bash
dotnet test --project Tests/Tests.Playground/Tests.Playground.csproj --filter "FullyQualifiedName~ClassName.MethodName" -f net10.0 --settings .runsettings --test-progress
```

Reach for the full `Tests/Linq/Tests.csproj` only when the test target spans many files that would require a wide playground link, or when running a broad filter (e.g. an entire test class).

**To capture a probe's output, write it to a file and `Read` it.** The MTP runner buffers `TestContext.Out` and console output, so stdout capture from a playground probe comes back **empty** — `File.WriteAllText` the result to `.build/.agents/<name>.txt` instead. This is what makes raw-SQL probing practical (`db.Query` / `db.Execute` straight into a file).

**A playground probe can bypass linq2db entirely and hit a provider's driver.** Every provider's ADO package is available there via `linq2db.TestProjects.props` → `linq2db.Providers.props` (net8+: `DuckDB.NET.Data.Full`, Oracle, `Octonica.ClickHouse`, `Ydb.Sdk`, …), so a scratch repro can construct the driver connection directly — `new DuckDB.NET.Data.DuckDBConnection(...)` — with no `TestBase` and no `DataProviders.json`. Use it to pin a pure SQL/driver-level bug apart from the ORM (#5710's DuckDB sequence collision was confirmed this way).

**Match the provider to the issue's stated domain, not to whatever is already enabled.** Verifying a PostgreSQL JSONB concern against DuckDB because DuckDB happened to be enabled is a category error — the verification only carries weight on the provider the bug lives on, and enabling the right one via `/test-providers` is faster than running an irrelevant test and then defending it. Provider-*agnostic* concerns (a translator heuristic affecting everything) can still take the simplest provider, normally SQLite.

**Benchmarks go in `Tests/Tests.Benchmarks/`, never a hand-rolled `Stopwatch` loop.** The repo has a BenchmarkDotNet harness (`Benchmarks/Queries/CacheActivityBenchmark.cs` is the shape) that gives warmup, statistics and multi-TFM runs; an ad-hoc `[Test]` with a `Stopwatch` in `Tests/Linq` or the playground is noisy and pollutes the test project. Add a `[MemoryDiagnoser]` / `[Benchmark]` class instead — and still gate the timing run on user confirmation.

```bash
dotnet run -c Release --project Tests/Tests.Benchmarks/linq2db.Benchmarks.csproj -f net10.0 -- --filter '*Name*'
```

Force `InProcessEmit` in the benchmark's `[Config]` (`Job.Default.WithToolchain(InProcessEmitToolchain.Instance)`) — the child-process multi-runtime jobs (net462/8/9) fail in the AV-restricted local environment and report `NA`; they run on CI. Don't re-add `MarkdownExporter.GitHub`, which the global `Config.Instance` already registers (BDN warns on the duplicate).

**YDB keyless-table failures take a plain `[PrimaryKey]`, applied to every provider.** When a fixture's local table fails on YDB with *"Primary key is required for ydb tables"*, add `[PrimaryKey]` to a suitable unique column — do **not** scope it as `[PrimaryKey(Configuration = ProviderName.Ydb)]`. A PK on a unique column doesn't change query results anywhere, so the provider-scoped attribute is unnecessary complexity. Pick a genuinely unique column: `Id` often carries intentional duplicates in `DistinctBy` / `CountBy`-style tests, so reach for `Date` or a composite. Write `[PrimaryKey]` alone, never `[Column, PrimaryKey]` (it already implies the column mapping), and add no comment when the key lands on an obvious `Id` — only when the choice is non-obvious.

**Targeted repro in a worktree — run the MTP exe directly.** `dotnet test --project <path>` can fall back to the legacy VSTest MSBuild target (error: `MSB1001: Unknown switch … --project … --target:VSTest`) when the new-`dotnet test` opt-in isn't resolved for that invocation — e.g. a relative `--project` pointing into a `git worktree` from another checkout's cwd. For a focused run, skip `dotnet test` and invoke the built test executable directly with MTP options:

```bash
.build/bin/Tests/Testing/net10.0/linq2db.Tests.exe --provider Firebird.5 --test-progress --filter "FullyQualifiedName~CreateData.CreateDatabase|FullyQualifiedName~UpdateFromSubqueryRowFlattened"
```

For a broad run, add `--report-trx --report-trx-filename <f>.trx --results-directory .build/.agents/<dir>` and read the result through [`../scripts/trx-failures.ps1`](../scripts/trx-failures.ps1) (`-GroupBy message|reason`, `-Like`, `-DirectOnly`): it turns hundreds of failures into a ranked list of causes, which is what triaging a newly enabled provider needs.

The `--provider <Name>` flag (repeatable, comma- or space-separated) **replaces** the providers configured in `UserDataProviders.json` for that run — no file edit needed, as long as the provider's connection string is defined in the file. The harness locates `UserDataProviders.json` by walking up the directory tree from the assembly path, stopping at the nearest ancestor that has it — so a copy at the worktree root is picked up, and a worktree nested inside the primary clone resolves the clone's file with no copy at all. Build the project first (`dotnet build <proj> -c Testing -f net10.0`) since you're bypassing `dotnet test`'s implicit build.

**`--provider` does not exist on an older checkout — there, editing the file *is* the mechanism.** It arrived with `3c345be327` (PR #5621, 2026-06-17), and the only release tag carrying it is **v6.4.0**; `v6.3.0` and earlier have neither `--provider` nor `--test-progress`. So a bug repro or bisect on an old tag reverts to the pre-#5621 method: select providers by trimming the `Providers` array in `UserDataProviders.json`, and in a worktree drop a **trimmed copy at the worktree root** to override whatever the walk-up would otherwise resolve. Delete that copy when done — being the nearest ancestor, it silently restricts every later run from that tree. Passing `--provider` on such a checkout is not a no-op: it's an unrecognised argument. Those tags also predate MTP, so the runner invocation differs too: classic VSTest takes the project as a **positional** arg (`--project` dies with `MSB1001: Unknown switch`), and `-p:NuGetAudit=false` is needed because old package pins now trip advisories that fail *restore* under warnings-as-errors.

**Verifying an `[ActiveIssue]` gate — read the skip *reason*, not the pass count.** Since [#5882](https://github.com/linq2db/linq2db/pull/5882) (merged 2026-09-17) `ActiveIssueAttribute` no longer writes `RunState.Explicit`: a gated test **runs**, and the attribute adjudicates its outcome (`Tests/Base/Attributes/ActiveIssueAttribute.cs:244,248`).

- **Still failing** → `ResultState.Inconclusive`, which MTP prints under `skipped` and the `--test-progress` heartbeat counts as `inconclusive`, with the reason `[ActiveIssue] Known issue (<reference>), still failing as expected:` followed by **the observed failure**.
- **Passing** → a red: `Test passed but is marked with [ActiveIssue] (<reference>). If the issue is fixed, remove the attribute; if it only passes for some providers, narrow Configuration.`

Two consequences. **`failed: 0` on its own proves nothing about a gate** — a test that never ran reports identically — so `Grep` the log for `^skipped <Test>` and read the reason; for a *non*-gated change, confirm execution from the baseline file's mtime instead. And a gate is a **two-sided** assertion: an over-broad `Configuration` goes red the moment a provider starts passing, which is how three `AllAccess`-keyed gates were caught on #5956 once LibRed did what Microsoft's Access drivers cannot.

**Don't read a big red run's log by hand — `.claude/scripts/parse-test-failures.ps1 -LogPath <log>` groups it by cause.** A full-suite log runs to hundreds of thousands of lines, and the summary gives counts and a flat list of names but never a *why*; the script collapses identical first-lines, so a hundred-plus failures become a few dozen causes with a representative message each. Pass **`-IncludeSkipped`** to audit a batch of `[ActiveIssue]` gates in the same pass — that is where their verdicts land, per the paragraph above.

**Harvesting what a gate hides is now just a run.** Because gated tests execute, the `still failing as expected:` reason *contains* the observed failure — so triaging whether a gate is still needed costs one ordinary filtered run plus a `Grep` of the log, with no `--report-trx`, no by-name filter trick, and no temporary edit to `ActiveIssueAttribute`. The elaborate by-name / `Explicit`-editing recipes this section used to carry (measured 2026-09-08/09 against the pre-#5882 attribute, including the `SkipForLinqService` half-run trap) describe a mechanism that no longer exists; they are gone rather than corrected.

## Gating an assertion failure

**A gate proven only by CI is unproven for its message form.** CI has no test sources, so it only ever produces Shouldly's no-source message; confirm the pattern with one local run, or write it so it matches both forms (the rules below). (#5959: three `ErrorMessage` misses on one branch, the last one written during a CI triage and verified by CI alone.)

Derive any `ErrorMessage` you write from the trx's — or the log's — raw message text, never from a whitespace-normalised view of it: Shouldly wraps `should be` / `0` / `but was` / `1` across four lines, so a fragment copied from a collapsed rendering matches nothing (use the `{0}`-placeholder form, which `ThrowsWhenAttribute.MessageMatches` expands to `.*?` under `RegexOptions.Singleline`). When the assertion text is awkward to quote — embedded quotes, parentheses — prefer a declaration-free gate whose `Details` opens with `no-declaration:`, which is the idiom for a gate on an assertion failure rather than a throw. **Never use the Shouldly source expression as the fragment.** Shouldly puts the asserted expression (`t.Single().Value`, `Sql.DateAdd(…, r.Day)`) into its message only when it can read the test's source file: on a dev box it can, on CI it can't, and the message is then just `<actual> should be <expected> but was not`. A gate keyed on the expression holds locally and fails every CI leg with `[ActiveIssue] Expected … but found`. Match the expected value instead, anchored on the next clause: `ErrorTypeName = "Shouldly.ShouldAssertException", ErrorMessage = "should be{0}<expected>{1}but was"`. Without the anchor the unanchored `.*?` also matches the *opposite* failure of a sibling assertion — `should be{0}1` matches `should be 0 but was 1` — so a regression of the fix the test pins passes as Inconclusive. (#5959) **The closing clause depends on the assertion and on whether Shouldly found the source:** `ShouldBe` closes with `but was` on both, but `ShouldContain` closes with `but did not` on CI and `but was actually` locally — so `should contain{0}<expected>{1}but did not` holds on CI and fails locally, and a single-line `should contain <expected> but did not` (no placeholders) matches neither. Anchor on `{1}but` unless the clause is known to be the same on both, and check it against CI's raw text, not a local run. (#5959, `CoarseAggregateSetOperationKeepsLiteralTime`: three CI legs red on the single-line form.)

**Never read a test's gate state off a windowed `Read` — `Grep` the file for `ActiveIssue`.** Attributes sit *above* the method signature, so a `Read` with an `offset` chosen to land on `public void <Test>(` silently excludes the `[ActiveIssue]` / `[Test]` lines that determine whether the test runs at all. The window looks complete — signature, body, closing brace — which is what makes the omission invisible, and any conclusion drawn from it ("this test was ungated and passing") is then wrong in a way nothing downstream contradicts. `git grep -n "ActiveIssue" -- <file>` costs one call and lists every gate with its line number. (Surfaced on #5804: `CompileTests.cs` was read from line 580, putting `IDataContext_CompiledQueryTest_AsList`'s gate at 578 out of frame; it had in fact been `[ActiveIssue]` since #4540, and the mistaken reading produced a false "this regressed on current master" inference that a `git log -L` had to undo.)

**`[ActiveIssue]` is `AllowMultiple=true`.** To add a provider to a test that already carries a gate, add a **second attribute** with its own `Configuration`, issue reference and expected failure — don't fold two providers' reasons into one `Details`. Single provider → `Configuration = TestProvName.AllX`; multiple that share one reason → `Configurations = new[] { ProviderName.Sybase, TestProvName.AllYdb }`. (The `Configuration`/`Configurations` setters split on commas, so either form accepts grouped names.)

**`[ActiveIssue]` runs the test and rewrites its outcome — it no longer hides it from discovery.** [#5882](https://github.com/linq2db/linq2db/pull/5882) has landed and `[ActiveIssueNew]` took the old attribute's name, so there is one attribute again and it is the run-and-verify one: **Inconclusive** when the test fails as the attribute declares, **Failure** when it passes (the issue is fixed, the gate must go) or fails some other way (a regression, or a moved error message). Five consequences:

- **Declare `ErrorType` / `ErrorTypeName` / `ErrorMessage`.** A gate with none matches *any* failure and will mask an unrelated regression. It is also self-verifying in the other direction: a wrong `ErrorTypeName` turns the gate into a failure, so a green run after adding one is evidence the type is right. **An `AssertQuery` wrong-results failure carries no type name** — leave `ErrorType` / `ErrorTypeName` unset and pin `ErrorMessage` on a diff row (`Truncated = 1 } <> { Id = 1, Truncated = 1.25 }`); declaring `NUnit.Framework.AssertionException` makes the gate fail as `Expected <…> but found` (`ActiveIssueAttribute.cs:128-129`; #5943 round 7). **Never match `ErrorMessage` on the subject of a Shouldly assertion:** Shouldly builds the subject from the test's source file, which CI's test binaries don't have, so the same failure reads `present should be True` locally and `False` on CI and the gate breaks only there. Gate it with `ErrorTypeName = "Shouldly.ShouldAssertException"` (or give the assertion a `customMessage`). (#5969, `ContainsOverADifference`.) The verb phrase that follows the subject is the same on both, so when the type alone is too broad, pin that with a `{0}` placeholder for the line break — `ErrorMessage = "should be greater than{0}0"` matches CI's `0 / should be greater than / 0 / but was not` and the local form alike. (#5640, the ClickHouse identity-key gates.)
- **A fixed issue announces itself** as `"test passed but is marked with [ActiveIssue]"`. That is the point of the attribute; `/enable-disabled-test` exists for the *old* one's inability to do it.
- **Gate per engine and per case.** `Configuration` scopes the gate to providers, but a `[ValueSource]` argument cannot be targeted — so when a fixture's cases divide differently across engines, **split the `ValueSource`** and give each group its own gate, rather than scoping one gate and accepting that it is wrong for some arguments. `AccessTests.cs`'s Issue 3893 identifiers are the worked example: four lists, one per rejection pattern. (Added on #5956 after scoping a single gate to the Microsoft drivers turned 5 wrongly-gated passes into 5 real failures.)
- **Exclude, don't gate, a test whose failure kills the database session.** The gate only rewrites the test's own outcome; the dead connection still goes back to the provider's pool and fails whichever test draws it next, on a different test each time. Its own failure is unstable too: the `Dispose` of a temp table or context runs on the dead socket and its exception replaces the original. Exclude the provider from the data source and record the server version last checked (#6029, ASE 16.1 `UnusedSource_Query`).
- **A gate on the baselines check needs `RequiresBaselines = true`.** `Baselines for remote context doesn't match direct access baselines` is thrown by `BaselinesWriter`, which runs only when `BaselinesPath` is set. A run that writes no baselines — a `tests` workflow_dispatch with an empty `baselines_branch`, a local run without a baselines clone — passes the test, and the gate turns that pass red. `RequiresBaselines` (added by #6048) limits the gate to runs that write baselines. (#6048, `Issue5972_UInt64`.)

**A SQLite.MS `Mapping of column … value failed` that appears only after a sibling case is #6028 reached by test order — clear the caches, don't gate.** Two cases (two `[Values]` arms, two tests) whose queries expand to the same tree share one cached query, and on SQLite.MS #6028 can leave that query's materializer faulted after its first execution, so the second case fails on a correct cache hit. Confirm by running the case alone (`Name~<argument>`, above): it passes. Call `Query.ClearCaches()` (`LinqToDB.Internal.Linq`) at the start of the test. `[ActiveIssue(6028)]` is the wrong tool here — it turns red whenever the case runs alone or first. (#5708, 2026-10-22: `AnEmptyCellOverANonNullableColumnReadsNull(SQLite.MS, Templates)` after its `Cell` arm; the shared tree was also evidence that both arms lower identically.)

**An assertion on a `[DataSources]` test must hold for every provider's ordering defaults.** Two cost a full CI round on #5969:

- **NULL sort position is the provider's default** when no `NullsPosition` is requested — last in ascending order on PostgreSQL, Oracle, DB2, DuckDB and ClickHouse, first on SQLite, Access and SQL Server. Assert only the relative order of the non-NULL keys, or request the position explicitly. (`RowNumberWithNullableBooleanOrderBy`: 42 failures across six legs.)
- **Row order without `ORDER BY` is unspecified** — give the query an `OrderBy` whenever its result has more than one row and anything order-sensitive reads it. `AssertQuery` itself does **not** compare in sequence: `AreEqual` (`Tests/Base/TestBase.Asserts.cs`) checks the count and then `Except`s both ways, so a reordering alone cannot fail it — only its diagnostic printout is row-by-row. (`Issue5970Test` was recorded as "correct rows, wrong order, Oracle 11 only"; given the set comparison, the real cause is unverified.)

**Instrumenting engine code to trace a divergence.** To find where the SQL build diverges (e.g. a node dropped only on the remote path), add temporary `System.Console.Error.WriteLine("YDBINST:…")` traces at suspect visitor / builder methods, run the targeted test, `grep` the captured output for the marker, then `git restore <source-files>` to revert (confirm `git status -- Source/ Tests/` is clean before committing). **Do not filter SQL-AST nodes by `ToString()` content** (`expr.ToString()?.Contains("GetLength")`) — it does not reliably contain the function/identifier name and silently matches nothing; filter on **structural properties** instead (node type, `IsMandatory`, `ToType`, `cast.Expression is SqlFunction { Name: … }`).

**Capture caveat — `Console`/`TestContext.Progress` output is only captured from a test's *body*.** Traces emitted from `[OneTimeSetUp]`/`[OneTimeTearDown]`, a custom `IWorkItemDispatcher`, the LinqService server, or any other non-test thread are **not** reliably surfaced by the console logger — they can come back empty and mislead you into a wrong "this code never ran" conclusion. For those, write the diagnostic to a **file** (e.g. under `AppContext.BaseDirectory`) and `Read` it back. (For live *run progress* — current test, completed/total, pass/fail — rather than engine tracing, use the `LINQ2DB_TEST_PROGRESS` heartbeat instead; see *Monitoring a long run* below.)

## Report a test verdict only from an observed artifact

A test verdict must come from something you actually observed — parsed pass/fail counts, the real exception, a captured log line — never from inference that the code "should" pass. "Everything works" is the cheapest continuation when nothing visibly contradicts it, so an unverified success verdict is the default failure mode; guard against it by pinning every verdict to evidence. Use an honest four-way vocabulary and never collapse the last two into an implied pass:

- **Pass** — a run reported non-zero matching tests and all passed (cite the counts). An `Assert.Throws<T>` / `[ThrowsForProvider]` test whose expected exception fired is a **pass**, not a failure.
- **Fail** — at least one test failed; quote the verbatim NUnit message + top stack frame, attributed to the correct fully-qualified test.
- **Not tested** — you did not run it (or the filter matched zero tests). Say so plainly; don't imply it passed.
- **Blocked** — a precondition prevented the run (provider not configured, container down, build error). Report the blocker and what would unblock it.

This is the reporting counterpart to `agent-guardrails.md` → *A subagent's reported result is a claim, not evidence* and `acting-on-findings.md` → *Red test first for a review-finding fix* (a red→green demonstration is the bar); `test-runner`'s structured `status` enum (`passed` / `failed` / `none_matched` / `error` / `blocked`) is exactly this vocabulary — relay it verbatim, don't upgrade a `none_matched`/`blocked` into a green claim.

**A *skipped* test is "not tested" — and it hides inside a green summary.** `none_matched` covers a filter that resolved nothing, which is visible. The commoner miss is a filter that resolved plenty while the one test you actually changed was excluded at runtime by a provider gate — `Assert.Ignore`, a capability check, `[ActiveIssue]`, a `SkipIf…` helper. The run then reports `0 failed` with a healthy pass count and nothing names the omission, so a change verified this way was never exercised at all. After any run you are citing as verification, cross-check the `skipped` list against the tests you touched: MTP prints skipped tests per-test with their reason (`Grep` the log for `^skipped `), and `worktree-test.ps1` returns the count in `summary.skipped`. When your test is in there, pick a provider on the branch it exercises and re-run. (Surfaced on #5643: a rewritten assertion in `UpdateThroughUnsupportedSourceShapeThrows` was "verified" by a SQLite.MS run reporting 44 total / 0 failed / 28 passed — the test is gated to the `SELECT`-fallback read-back path and SQLite takes the `RETURNING` branch, so it sat in the 16 skips. MySQL ran it.)

**A pass in a suite run is not evidence until the test is run alone.** The section above covers a test that
never ran; this is the harder case — it ran, it passed, and the pass was manufactured by whatever ran
*before* it. Tests share process state (linq2db and EF caches keyed on a model, static mapping schemas,
provider-level singletons), so an earlier test can leave the pipeline in a shape that hides a later test's
failure entirely. Nothing in the output distinguishes that from a real pass, and it survives every
reporting discipline above: the counts are honest, the test genuinely executed, and it genuinely passed.

So before treating a pass as evidence *about that test* — enabling a gate, closing an issue, calling a
regression fixed — re-run it **in isolation** (`--filter` naming just that test) and confirm it still
passes. When solo and suite disagree, that difference is the finding: the test is order-dependent and
cannot serve as a regression test until it is made deterministic, usually by giving it its own context or
model so it shares no cached state.

To find *what* masks it, bisect the fixture rather than guessing: run the target alongside halves of the
sibling set until a minimal masking set remains. (Measured on #4669: `ToolsTests.TestGlobalQueryFilters`
passes in its 64-test fixture and fails alone with `System.Diagnostics.UnreachableException`.
`NavigationProperties` is the **only** one of 46 siblings that masks it — `TestToList`,
`TestAssociations` and `TestInclude` do not — and it sorts earlier alphabetically, so a full run always
masks it. A 12/12 pass across three MySQL servers was consequently read as "the issue is fixed"; it was
not. The replacement lives on a dedicated `DbContext` and fails identically alone and after the masker.)

The same caution applies to a **filtered sweep**: a subset run has its own ordering, so a `PASSED` cell
harvested from one is not interchangeable with either a solo run or a full-suite run.

## Running the analyzer tests (`Tests/Tests.Analyzers`)

The `linq2db.Analyzers` package tests are a **standalone** project — DB-free, provider-independent, single-TFM `net8.0` (to match the Roslyn testing SDK's Net80 reference pack; a higher pack trips CS1705), MTP host with the NUnit runner. They are **not** covered by the `/test` skill, which selects the Playground / `Tests/Linq` provider projects and injects the `CreateData.CreateDatabase` filter. Run them directly:

```bash
dotnet test Tests/Tests.Analyzers/Tests.Analyzers.csproj -c Release
```

Use **Release** — the Meziantou / Roslyn analyzer rules that gate the code-fix project (e.g. MA0154 "use `<see langword>`") run Release-only, so a Debug/Testing run compiles green while CI's Release leg fails. The `net8.0` runtime must be installed locally (the SDK 10 still *builds* the net8.0 target; it's the test *host* that needs the runtime); CI provisions it via the `with_analyzer_tests`-gated `UseDotNet` step in `Build/Azure/pipelines/templates/build-job.yml`.

**This project is the one exception to "always pass `--test-progress`"** (`agent-rules.md` → *Running tests*). Its host does not register that extension, so the option is forwarded to the test application, which prints its help and exits **5 — reported as `Zero tests ran`**. That is the same symptom as a bad filter and as the MSBuild-switch trap below, so it gets misdiagnosed twice before anyone reads the help output. Omit the flag here; the suite is ~100 s and needs no heartbeat. The same holds for `Tests/Tests.Analyzers.Internal`: read this as covering the class — a DB-free analyzer-fixture project is added roughly once per analyzer family and each inherits the trap. Generalised: **`Zero tests ran` after a flag change means the flag, not the filter** — run the built test executable with the same arguments and read what it prints, since `dotnet test` swallows the help output that names the culprit.

**Inside a fix loop, run the built executable directly rather than `dotnet test`** — it skips the build entirely and takes ~1 s for a filtered run against ~100 s for the whole project:

```bash
.build/bin/Tests.Analyzers/Release/linq2db.Tests.Analyzers.exe --filter "FullyQualifiedName~ReportsMicrosecondFactoryConstant"
```

`--filter` is an extension option this host *does* accept (the same `FullyQualifiedName~` syntax). Run the whole project — no filter — for the final confirmation, since a filtered green says nothing about what the change broke elsewhere. (A red→green→mutation cycle on one rule ran this ~15 times in a single session; the difference is minutes per iteration.)

## Running the CLI tests

`Tests/LinqToDB.CLI` (assembly `linq2db.CLI.Tests`) covers `Source/LinqToDB.CLI` — the `dotnet linq2db` tool, its `query` / `execute` / `schema` / `credentials` commands, and the MCP server. **`/test` does not cover this project**: it selects between Playground and `Tests/Linq`, so a CLI change has to be run by hand.

It is a **third member of the bare-NUnit-MTP class** described for `Tests.Analyzers` above, and inherits the same trap: the host does not register the test-progress extension, so **`--test-progress` exits 5 as `Zero tests ran`**. Omit it. `--filter` *is* accepted, with the usual VSTest `FullyQualifiedName~` syntax — NUnit where-syntax (`method == X`, `test =~ X`) is **not**, and fails with exit 82 and a `VSTestBridgedTestFrameworkBase` stack rather than anything naming the filter. The CI template's `--filter "TestCategory != SkipCI"` looks like where-syntax but is the VSTest spelling of a category filter.

Build then run the executable, the way `Build/Azure/pipelines/templates/test-cli.yml` does — CI builds once and runs the exe for `net8.0`, `net9.0` and `net10.0` in turn:

```bash
dotnet build Tests/LinqToDB.CLI/Tests.LinqToDB.CLI.csproj -c Testing
.build/bin/Tests.LinqToDB.CLI/Testing/net10.0/linq2db.CLI.Tests.exe --settings .runsettings
```

```bash
.build/bin/Tests.LinqToDB.CLI/Testing/net10.0/linq2db.CLI.Tests.exe --settings .runsettings --filter "FullyQualifiedName~SecretConsoleReader"
```

The suite is ~250 tests and needs no database — it creates its own SQLite files under the NUnit work directory. Budget **~2 minutes** on an idle machine, but the MCP fixtures spawn the built `dotnet-linq2db` exe over STDIO and read its responses with a timeout, so they are **load-sensitive**: the same suite took 6m40s next to a concurrent Release build and `McpInfoMarksDefaultProfileUnusableWhenDefaultHasNoProvider` failed with a bare `TimeoutException`. A lone MCP timeout is the tell — re-run that one test on its own (it takes ~3 s) before treating it as a regression.

Because the CLI multi-targets `net8.0;net9.0;net10.0` and `Testing` collapses to `net10.0`, a pre-push Release check should cover a lower TFM too: `dotnet build Tests/LinqToDB.CLI/Tests.LinqToDB.CLI.csproj -c Release -f net8.0`.

**A DB2 `--provider-location` folder for local CLI runs.** DB2 is not bundled with the CLI. Assemble a provider folder from the `Net.IBM.Data.Db2` package in the NuGet cache: copy `lib/net10.0/IBM.Data.Db2.dll` and the `buildTransitive/clidriver/` directory (~81 MB) into one folder, then pass that folder's `IBM.Data.Db2.dll` path to `--provider-location`. The package's own targets lay a consuming app's output out the same way. The IBM client mangles its messages unless `DB2CODEPAGE=1208` is set.

## The x86 FPU JIT sweep (`Tests/Tests.FpuJit`)

`Tests/Tests.FpuJit` is a net462 x86 console exe, not an NUnit project, run by the `x86 FPU-unmasked JIT sweep` job in `.github/workflows/build.yml` on every PR. With FP exceptions unmasked (as C++Builder / Delphi hosts leave them) it `PrepareMethod`s every method of every shipped assembly with a .NET Framework target, and fails on any method the x86 .NET Framework JIT cannot compile — in practice a `NaN` / `±Infinity` constant or a `double.IsPositiveInfinity` / `IsNegativeInfinity` compare. Build the special values with `Internal/Common/FloatingPointHelper` instead (#6051). `/test` does not run it; locally, on Windows:

```bash
dotnet build Tests/Tests.FpuJit/Tests.FpuJit.csproj -c Release -p:RunApiAnalyzersDuringBuild=false
.build/bin/Tests.FpuJit/Release/net462/linq2db.Tests.FpuJit.exe
```

Exit 0 = clean, 1 = JIT faults (`FAIL` lines name the methods), 2 = an environment or coverage error (`ERROR` lines), 3 = harness failure.

**A shipped Source project gaining or losing a .NET Framework target changes the sweep's input list, and nothing fails when it is missed.** That covers a new project on the default TFMs (`Directory.Build.props` includes `net462`), an explicit `net4x` added to an existing one, or one dropped. Update both lists in the same PR: the `ProjectReference` in `Tests/Tests.FpuJit/Tests.FpuJit.csproj` and the assembly name in `ExpectedAssemblies` in `Tests/Tests.FpuJit/Program.cs`. The harness fails when an assembly it expects is missing. It cannot know about an assembly nobody listed: an unlisted project is simply not swept, and the gate stays green (#6051, plan P10). The LINQPad driver (net472) is the one deliberate exclusion.

## BUGCHECK-gated tests

Test fixtures wrapped in `#if BUGCHECK` (internal-invariant unit tests that drive `#if BUGCHECK`-gated test hooks on the core library — e.g. `QueryCacheEvictionTests` driving `QueryCache.RunSweepNow` / `BucketCount`) only compile in **Debug / Testing / Azure** configurations. `BUGCHECK` is defined in `Source/LinqToDB/LinqToDB.csproj` and mirrored into `Tests/Directory.Build.props` so the test project sees the same symbol. Consequences:

- Run them with `-c Testing` (net10.0-only, fast) or `-c Debug`. A **Release** run compiles the fixture to nothing — `--filter` matches zero tests, not a pass.
- The core library must also be built in a BUGCHECK config for the gated test hooks to exist; `-c Testing` covers both.

## Repro blocked by a separate, known engine bug — gate on the blocker, defer the fix

A third case beyond *reproducible* and *can't-reproduce*: the finding's mechanism is verified against core code, but you can't drive an end-to-end red repro because an *unrelated, independently-tracked* engine bug blocks the only path to it. Then commit the regression test `[ActiveIssue]`-gated on the **blocker's** issue and defer the actual fix until the blocker merges — so the fix is verified over the real path once un-gated (per [`evidence-discipline.md`](evidence-discipline.md) → *Verify a fix by the same path that surfaced the bug*), rather than applying a speculative fix that can't yet be exercised. (#5704, #1813, #5701)

**An `[ActiveIssue]` must reference an issue that outlives the PR, never the PR itself.** A gate on the PR's own number loses its tracker the moment the PR merges. File the issue and gate on it.

**A gate that holds for only one `[Values]` arm needs an ungated sibling for the other.** `ActiveIssue` gates a whole test (or a configuration via `Configurations`), never one parameter value, so a test hard-coded to the failing arm leaves the passing arm unwatched. Move the body into a helper that takes the parameter, and declare two `[Test]` methods: the gated one passing the failing value, an ungated `…With<Value>` one passing the other. (#5983: two gates referenced the PR and ran only the option-off arm; both were moved to #6046, each with an option-on sibling.)

## Native `TimeSpan` columns can't be stored on every provider

A `TimeSpan` property mapped with no `[Duration]` fails on three providers before any query runs, inside `CreateLocalTable`:
- **SQLite Classic** — the driver binds it through `Convert.ToDateTime`: `Unable to cast object of type 'System.TimeSpan' to type 'System.IConvertible'`.
- **SQL CE** — `No mapping exists from DbType Time to a known SqlDbType`.
- **Oracle** — `ORA-00902: invalid datatype` on `CREATE TABLE`.

Exclude them in `[DataSources(...)]`, or map the member with `[Duration]` when the test is not about a native time type. SQLite MS, DuckDB, Access, SQL Server 2008+, PostgreSQL, YDB, Firebird, Sybase, DB2, Informix and MySQL 8 store it. (#5983, `SpanOverMissedLeftJoinReadsDefault`)

## The runner's arch tag is the PE machine type — read the CLR header to know the process arch

Microsoft.Testing.Platform tags tests and run summaries as `(<exe>|<tfm>|<arch>)`, for example
`(linq2db.Tests.exe|net462|x86)`. That `arch` is the exe's PE machine type. `I386` alone is ambiguous: it is the
machine type of both an AnyCPU build and an x86 one. What decides the process is the CLR header's `Requires32Bit`
flag. Read it with `System.Reflection.PortableExecutable.PEReader` (`PEHeaders.CoffHeader.Machine` and
`PEHeaders.CorHeader.Flags`). The `x64` / `x86` segment in a CI path (`net462\main\x64\…`)
is only the name of the artifact half, and it says nothing about the process.

The SDK gives a .NET Framework **exe** published with no RID the default win-x86. Our MTP test projects are exes,
so `Tests/Linq` net462 published without `-a` is `I386, ILOnly, Requires32Bit`: a 32-bit process. Until #6128
(`bd7455b77`) both CIs published the main netfx suite that way. Every non-Access netfx leg therefore ran 32-bit,
and on full runs NUnit's result string ran out of address space (`OutOfMemoryException` in
`TestEventDispatcher` / `XmlNode.OuterXml`). Published with `-a x64`, the exe is `Amd64` with no
`Requires32Bit`. #5614 read the label the other way round and retracted a correct analysis.

## `ToListAsync` needs `using LinqToDB.Async`

Without it the call binds to .NET 10's `System.Linq.AsyncEnumerable.ToListAsync<TSource>(IAsyncEnumerable<TSource>, …)`,
which does not accept an `IQueryable`, and the build fails with a misleading
`CS0411: The type arguments for method … cannot be inferred from the usage`. The error points at the query
rather than at the missing using, so it reads as a problem with the expression. `LinqToDB` alone is not
enough — the queryable overloads live in `LinqToDB.Async`.

**Raw SQL — `db.Execute("…")` needs `using LinqToDB.Data`.** Same shape, different namespace: the
`Execute` / `ExecuteAsync` / `Execute<T>` extensions on `IDataContext` live in
`LinqToDB.Data.DataContextExtensions`, so a fixture holding only `using LinqToDB;` fails with
`CS1061: 'ITestDataContext' does not contain a definition for 'Execute'`. That names the *receiver* type,
which reads as "the test context can't do this" rather than "a using is missing" — and `ITestDataContext`
being a test-harness interface makes the wrong reading plausible. Reach for this when a test needs DDL the
mapping layer can't express (`CREATE TRIGGER`, `CREATE SEQUENCE`); existing users are
`PostgreSQLSchemaProviderTests` and `CreateData`.

## Converting a multi-threaded test to async

Tests that fan out synchronous queries over remote (`.LinqService`) contexts starve the thread pool: every
sync call on a remote context goes through `SafeAwaiter.Run` — `Task.Run(...).GetAwaiter().GetResult()` — so
each worker holds **two** pool threads while the in-process Kestrel/gRPC host serving those calls needs pool
threads of its own, and nothing raises the pool floor. Prefer removing the blocking (`await …ToListAsync()`,
`Task.WhenAll`, workers started as tasks rather than via `Task.Run`) over raising `ThreadPool.SetMinThreads`,
which only makes the starvation survivable. `ConcurrentRunner`-based tests are unaffected — they use
dedicated `Thread` objects and cast to `DataConnection`, so they never run remote.

## Monitoring a long run

A full suite run takes 1–2 hours. To watch progress without scraping console output, the test assembly writes a small JSON heartbeat (updated ~once/sec, immediately on each failure) that you can `Read` at any time. It's **opt-in** via the `--test-progress` command-line option; the reporter is a no-op when the option is absent, so default runs are unaffected.

**Always pass `--test-progress` when launching a run** — via `test-runner`, `/test`, or ad-hoc — so progress is observable. It's a normal CLI option (no env var, no session-wide toggle):

```bash
dotnet test --project Tests/Linq/Tests.csproj -f net10.0 --settings .runsettings --filter "..." --provider SQLite.MS --test-progress
```

**The rule is enforced, not just stated.** [`../hooks/require-test-progress.js`](../hooks/require-test-progress.js) is a `PreToolUse` hook (matcher `Bash|PowerShell`) exiting 2 on a flagless `linq2db.Tests*.exe` / `dotnet test` invocation; the bare-NUnit hosts (`Tests.Analyzers`, `Tests.Analyzers.Internal`, the CLI tests) and `--list-tests` are exempt. Wire it per [`claude-setup.md`](claude-setup.md). It matches on command *text*, so a command that merely quotes a flagless invocation is blocked too — an accepted cost. That includes a command that only *names* the exe, such as `Get-ChildItem -Filter linq2db.Tests.exe` or a header read. Put the name inside a scratch script under `.build/.agents/` and run the script, since the hook sees only the script path (#6128). Added 2026-09-09 after the rule was broken in a session that had it loaded, which is the evidence that prose had reached its limit here.

A bare `--test-progress` writes to `.build/.agents/test-progress.<tfm>.<pid>.json` (one per TFM/process); pass `--test-progress <dir|*.json>` to redirect it. Fields: `done`, `total`, `totalIsUpperBound`, `completed`, `passed`, `failed`, `skipped`, `inconclusive`, `currentTest`, `elapsedSec`, `testsPerSec`, `etaSec`, and `recentFailures[]`; `sessionId` is the launching session's `CLAUDE_CODE_SESSION_ID` (`null` outside Claude Code), so a per-session observer shows only its own runs. `inconclusive` counts the cases an `[ActiveIssueNew]` gate rewrote — a known issue still failing as declared. It is the only local count of that population: the platform summary folds Inconclusive into *skipped*, and CI passes no `--test-progress` at all.

Read the heartbeat directly, or with the summary helper (the `/test-progress` skill reports the latest run):

```bash
pwsh -NoProfile -File .claude/scripts/test-status.ps1          # newest run, one-line summary
pwsh -NoProfile -File .claude/scripts/test-status.ps1 -Raw     # dump the raw JSON
```

**An optional cap stops a run whose filter selects too much.** [`../hooks/arm-test-cap.js`](../hooks/arm-test-cap.js) (a `PreToolUse` hook, matcher `Bash|PowerShell`, wired personally per [`claude-setup.md`](claude-setup.md)) arms [`../scripts/test-cap.ps1`](../scripts/test-cap.ps1) for each test command; once the heartbeat's filtered `total` is known, a run over the cap (default 1000) is stopped and `test-status.ps1` prints `test-cap: stopped (total N, cap M)`. Only runs descending from the same `claude.exe` whose command line carries the same `--filter` are touched; an upper-bound or pre-#6098 total is recorded as unverifiable and left running. Override per command with a trailing `# test-cap:off` or `# test-cap:<n>`.

Use the script rather than `ls -t` on the directory: it accumulates heartbeats from prior sessions and concurrent runs, so "newest by mtime" is a guess about whose run you are looking at.

**Caveat:** `total` is the number of tests the run executes under the given `--filter` (Ignored / Explicit / NotRunnable leaves excluded, filtered or not). `totalIsUpperBound: true` marks the discovered-count fallback, which has no ETA. A run without `--settings .runsettings` can be widened by the adapter's `AssemblySelectLimit` (default 2000) to the whole assembly, and `total` then counts all of it. A suite whose OneTimeSetUp fails or is skipped leaves `completed < total`. `done` comes only from the root suite's teardown.

## Test Database Configuration

Tests run against multiple database providers. Configuration comes from `UserDataProviders.json` (gitignored, user-specific). To get started:
1. Copy `UserDataProviders.json.template` to `UserDataProviders.json` (or run `/test-providers reset`, which does the same thing under explicit confirmation and writes a backup of any existing file).
2. This gives you SQLite-based testing out of the box.
3. Add connection strings for other databases as needed.

After the file exists, `/test-providers` is the supported way to enable / disable providers per TFM bucket and to start the docker containers behind them. `/test` reads the resulting state but never edits it — see [`.claude/skills/test-providers/SKILL.md`](../skills/test-providers/SKILL.md).

**For a single run, prefer `--provider` over editing the `Providers` array** — it runs exactly the named providers (any with a connection string defined) without touching the file; see *Scoping a run to specific providers* below. Editing `UserDataProviders.json` is for changing the **default** set (used when no `--provider` is passed), connection strings, and `BaselinesPath`.

**Ask before editing `UserDataProviders.json`.** Before the **first** edit in a session, ask the user whether to stash/back up the current file. The file is gitignored and holds the user's connection strings + enabled-provider flags — an incorrect edit has no git history to recover from. Subsequent edits in the same session don't need to re-prompt.

### `Providers` is keyed by TFM

`UserDataProviders.json` has a top-level section per target framework (`NETFX`, `NET80`, `NET90`, `NET100`), each with its own `Providers` array and each `BasedOn` the shared `MyConnectionStrings` section.

**Don't comment/uncomment entries to run a provider — pass `--provider`.** It replaces the active set for that run, so any provider with a connection string runs without the file being touched. The exception is a checkout that predates the flag (pre-#5621, i.e. `v6.3.0` and earlier) — there, trimming these arrays is the only way to scope a run; see *Scoping a run to specific providers* above. The `Providers` arrays define only the **default** set, used when a run passes no `--provider`. When you do change a default, edit the section matching the `-f` flag — `NETFX` only affects `net462` runs, `NET100` only affects `net10.0` runs, etc.; editing the wrong section silently does nothing.

### How CI resolves test config (`Build/Azure/*.json`) vs local

Local runs read `UserDataProviders.json`. **CI does not** — each Azure job copies `Build/Azure/net{80,90,100}/<config>.json` (e.g. `sqlite.json`, `duckdb.json`) into `UserDataProviders.json` (see `Build/Azure/pipelines/templates/test-workflow-*.yml`), while the tracked root `DataProviders.json` is the base. `SettingsReader.Deserialize` (`Tests/Base/Tools/SettingsReader.cs`) merges the two **first-writer-wins** — the copied CI config's `Connections` keys win, the base only fills in what's missing — and resolves `BasedOn` chains: `NET*.Azure` → `AzureConnectionStrings` → `CommonConnectionStrings`.

Consequences:

- A `CommonConnectionStrings` edit in `DataProviders.json` flows to **both** local dev *and* CI (both inherit it). To change a provider **only** in CI, add a `Connections` override to the Build/Azure job file — don't rely on editing `DataProviders.json` alone (and don't duplicate a string into both when the base already supplies it).
- `BaselinesPath` is set only in `AzureConnectionStrings`, so baseline capture/compare is **CI-only**; local runs don't diff baselines unless you set it yourself.
- **The section is selected by TFM *and* configuration, so reproducing CI locally means seeding `NET<n>.Azure`, not `NET<n>`.** CI builds and runs tests under the repo's custom `Azure` configuration (`test_configuration: 'Azure'` in `Build/Azure/pipelines/templates/build-vars.yml`; `<Configurations>Testing;Debug;Release;Azure</Configurations>`), and the reader resolves `NET100.Azure` for a `-c Azure` run. A local `dotnet test … -c Azure` against a file that only defines `NET100` therefore reads **neither** its `Providers` nor its `BaselinesPath` — the run goes green and writes **zero** baselines, with nothing saying why. Define both sections when switching a local run to `Azure` to match CI. (Cost a full run on #5737 before the empty output directory was traced to this.)
- **A test-config mode that breaks filtered/local runs (`dotnet test --filter …`, which skips the `a_CreateData` seed) must not become the tracked default.** Scope the risky mode to a CI-only Build/Azure override and keep the dev default safe — or fix the underlying limitation. (#5698: DuckDB shared in-memory can't be preloaded from its committed file — `COPY FROM DATABASE` fails on FK ordering — so it's CI-only, full-suite-seeded; SQLite preloads via the backup API, so its in-memory default is filtered-run-safe.)

### Container-backed providers

Most non-file providers (SAP HANA, most Oracle versions, PostgreSQL, MySQL, DB2, Informix, ClickHouse, SQL Server 2017+) connect to local docker containers. Start the needed container(s) before running tests — e.g. `docker start hana2 oracle11`. SAP HANA in particular takes several minutes after container start before its internal HDB database finishes warm-up; tests that run immediately after `docker start hana2` may hit "connection refused".

File-based providers (SQLite, SqlCe, Access) don't need a container.

**A wave of failures confined to container-backed providers is a dead container, not a regression.** Before diagnosing code, run `docker ps -a` and compare each failing provider against its container's status. Two shapes recur:

- **The container exited mid-session.** A filter that passed an hour earlier can come back with dozens of failures because the container died in between. The tell is that *every* failing provider is container-backed while the file-based ones (SQLite, DuckDB, SqlCe, Access) all pass, and the failures share a near-identical short duration.
- **The container reports `Up (healthy)` but refuses connections.** Docker's health state is not a readiness guarantee for the DB's listener — `firebird30` / `firebird40` have shown `Up 22 hours (healthy)` while their mapped ports returned `SocketException: ConnectionRefused`. A restart clears it.

The exception text settles it either way: `ConnectionRefused` / `Unable to complete network request to host` is environment, not code. (Surfaced on #5643: a 40-failure run was `clickhouse` + `mysql` having exited ~1h earlier, and two Firebird reproduction attempts failed against healthy-but-unreachable containers — the local repro had to be abandoned and the diagnosis grounded in CI plus the provider's documented limitation instead.)

**Not netfx-only.** SqlCe and Access — despite being "legacy" providers — run on *every* test TFM (`net462` + `net8.0`/`net9.0`/`net10.0`), enabled in the matching `Providers` bucket. Run their suites on `net10.0` (fast single-TFM), not `net462`. (A bare `pwsh 7` host can't load SqlCe's native engine for ad-hoc probes — see [`windows-gotchas.md`](windows-gotchas.md) — but the test process loads it fine on any TFM.)

### Provider variant defaults

When the user asks to run tests against a provider family without naming the exact variant:

- **Oracle** → `Oracle.<ver>.Managed`. Run `Oracle.*.Native` only on explicit request — Native pulls in bitness-specific drivers the user prefers to avoid by default.
- **Access** → `Access.*.Ace.OleDb` + `Access.*.Ace.Odbc`. Never enable `Access.*.Jet.*` without an explicit request.
- **SAP HANA** → both `SapHana.Native` and `SapHana.Odbc`.

**Access Jet requires x86.** If the user does request `Access.*.Jet.*`, the test process must run under x86 (32-bit). When running x86, **do not** enable any other provider alongside Jet — other providers may be x64-only (native drivers) or architecture-agnostic but untested on x86, so a mixed x86 run risks failures unrelated to the Jet work.

## Scoping a run to specific providers (`--provider`)

The test executables accept a `--provider` command-line option that runs exactly the named provider(s), **replacing** the providers configured in `UserDataProviders.json`. It is repeatable and accepts comma- or space-separated values:

```bash
dotnet test --project Tests/Linq/Tests.csproj -f net10.0 --settings .runsettings --filter "FullyQualifiedName~CreateData.CreateDatabase|FullyQualifiedName~MyTest" --provider PostgreSQL.18 --test-progress
```

`--provider` replaces the active main-test provider set (`TestConfiguration.UserProviders`) with exactly the names given, so **any provider with a connection string defined in `DataProviders.json` / `UserDataProviders.json` runs without editing the enabled-providers list** — it need not be enabled. (EF Core test runs instead intersect their curated `EFProviders` list, so `--provider` can only narrow EF runs to supported providers, never add an unsupported one.) Connection strings still come from those files; a `--provider` name with no connection logs a warning and fails to connect. An absent option leaves behavior unchanged (the providers enabled in `UserDataProviders.json` run).

**Multiple providers: comma- (or space-) separate them** — `--provider Firebird.5,PostgreSQL.18` (or `--provider Firebird.5 PostgreSQL.18`) runs both.

**So don't report the enabled list as the coverage bound.** The rule above is well documented, and it is still easy to *use* `--provider` correctly and then *describe* the run wrongly — "I covered every provider enabled in `NET100`" reads as a coverage claim while actually naming a file's contents. The real bound on a local run is **connection strings that resolve plus containers that are up**, which is both wider (a provider not in the `Providers` array runs fine) and narrower (an enabled provider whose container is down fails, or is simply absent from what you ran). State which providers actually executed and which ones CI will be the first to exercise, rather than quoting the file — and note that CI's matrix comes from `Build/Azure/net100/*.json`, not from `UserDataProviders.json` at all, so "enabled locally" says nothing about what CI will run. (Surfaced on #5844: nine providers were run via `--provider` — including Sybase, which is *not* in `NET100` — and the coverage was then summarised as "all providers enabled in NET100", which was simultaneously an overclaim about CI and an underclaim about what had been tested. The user's question was *"звідки ти взяв що заенейблено"*.)

**`--provider` takes a *provider* name, and the connection-string files list names that are not provider names.** `UserDataProviders.json` carries `Access` and `Access.Odbc` among its connections, but `TestProvName.AllAccess` expands to `Access.Ace.OleDb`, `Access.Ace.Odbc`, `Access.Jet.OleDb`, `Access.Jet.Odbc` — so `--provider Access` resolves nothing and the run reports **zero cases**, which is indistinguishable from "this provider is unavailable on this machine". Read the `TestProvName.All<X>` constant before concluding a provider can't run here; a zero-case result is a naming hypothesis, not a capability finding. (Surfaced on #5882: Access was recorded as unreachable across four gates and the ledger, and corrected only when the user said *"wrong, ace driver exists here"*. ACE works; only the 32-bit Jet pair genuinely does not.)

**`[IncludeDataSources]` silently excludes the remote path; `[DataSources]` includes it.** `IncludeDataSourcesAttribute`'s `params string[]` constructor passes `includeLinqService: false` to its base, so a fixture written entirely with `[IncludeDataSources(TestProvName.AllSQLite)]` never runs through a `LinqService` context — on **any** CI leg, not just locally. `[DataSources]` appends `TestBase.LinqServiceSuffix` to each enabled provider instead, so one `[DataSources]` test covers both the direct and the remote context. There is also an `IncludeDataSourcesAttribute(bool includeLinqService, params string[])` overload when a test needs a narrow provider set *and* the remote path. The failure mode is invisible: the fixture is green, the provider list looks deliberate, and nothing reports that a whole context never ran. Confirm which it is with `--list-tests --provider <name>` and look for `<provider>.LinqService` rows — a count alone does not distinguish "two providers" from "two `[Values]` arms". (Surfaced on #5926, where every test of a new option's fixture was `[IncludeDataSources]`, so no leg exercised the option remotely.)

**A narrowed `--provider` set does not narrow the *expectation* side — `TestBase.Types` reads the default configuration.** `Types` and `Types2` open a bare `new TestDataConnection()` (`Tests/Base/TestBase.Tables.cs:23-50`), which resolves `DefaultConfiguration` from `UserDataProviders.json` — normally `SQLite.MS` — not the context under test. A run scoped to a single non-default provider therefore never initialises that database, and every `AreEqual(from t in Types …, from t in db.Types …)` comparison fails with **`Expected list cannot be empty`**. The symptom looks nothing like its cause: mass failure across a provider-specific fixture, with the *server* side plainly working — the log shows the generated SQL and `Rows Count: 12` right beside the empty expectation. Include the default configuration in `--provider` whenever the filter reaches a comparison fixture, and read an "expected empty" failure as a harness gap, never as a regression in the code under test. (Surfaced 2026-09-22 on #5959: `--provider ClickHouse.Octonica` alone produced **199 failures of 298**, which read as a mass regression from a cross-cutting typing change; the same filter with `SQLite.MS` and `DuckDB` added was 841 / 0.)

**`--list-tests` discovers nothing without `--provider`.** Every `[DataSources]` / `[IncludeDataSources]` method resolves zero providers and so contributes zero cases, leaving a listing that looks like the fixture does not exist. Always pass `--provider <name>` when using the listing to check whether a method is covered — which is the check the zero-cases rule under *Tests that pass but catch nothing* depends on.

**Size a regression sweep with `--list-tests` before launching it.** Run the same `--provider` / `--filter` with `--list-tests` (about 7 s) and read the `found N test(s)` line. Filter by fixture (`FullyQualifiedName~.WhereTests.`), not by a bare substring: `~Where` / `~Join` / `~SubQuery` match method names across the whole suite. (#5983 round 6: such a filter matched 5,044 methods, about 47 k cells over five providers, and was killed after 2 h a third done.)

**To run one case of a parameterized test, AND the method filter with `Name~<argument value>`.** `--filter "FullyQualifiedName~Fixture.Method&Name~Templates"` selects the `[Values]` / `[TestCase]` case whose name carries that argument. `DisplayName~` is not a filter property under MTP: it resolves **zero** tests (exit 8), which reads like a wrong method name. (#5708, 2026-10-22: isolating `AnEmptyCellOverANonNullableColumnReadsNull(…, Templates)`.)

**To exercise the remote (LinqService) path, pass the BASE provider name, not the `.LinqService` suffix.** `DataSourcesBaseAttribute` auto-appends a `<provider>.LinqService` case for every base provider (unless `.runsettings` sets `DisableRemoteContext` / `NoLinqService`), so `--provider Firebird.5` runs **both** the direct `Firebird.5` and the remote `Firebird.5.LinqService` cases. Passing `--provider Firebird.5.LinqService` double-suffixes it to `Firebird.5.LinqService.LinqService`, which has no connection string → those cases silently don't run (you'll see only `CreateDatabase` execute). This is also why `test-runner`, given a `.LinqService` provider name, comes back green-but-empty.

### Running EF Core tests locally

The `/test` skill targets the Playground / Linq projects only — the EF Core integration tests are separate and run by hand.

- **Per-EF-version projects.** `Tests/EntityFrameworkCore/Tests.EntityFrameworkCore.EF10.csproj` (plus `EF9` / `EF8` for EF Core 9 / 8, and `EF3` for EF Core 3.1 — netfx-only). Build the one you need: `dotnet build Tests/EntityFrameworkCore/Tests.EntityFrameworkCore.EF10.csproj -c Debug`.
- **MTP exe, run directly.** These are `OutputType Exe` (Microsoft.Testing.Platform + NUnit runner), so run the built executable, not `dotnet test`: `.build/bin/Tests.EntityFrameworkCore.EF10/Debug/net10.0/linq2db.EntityFrameworkCore.Tests.exe --filter "FullyQualifiedName~MyTest"`. Filter with `--filter` (VSTest-style `FullyQualifiedName~` / `Name~`); the NUnit MTP runner rejects `--treenode-filter`.
- **SQLite needs no container.** `--provider SQLite.MS` runs the SQLite-capable EF tests against a file / `:memory:` DB created via EF `EnsureCreated` — no docker. Other EF providers need their DBs like the main suite. (EF projects intersect their curated `EFProviders` set, so `--provider` only narrows.)
- **EF SQL Server needs the `.MS` variant.** `EFProviders` (`TestConfiguration.cs`) is a curated set — `SQLiteMS`, `AllSqlServer2016PlusMS` (Microsoft.Data.SqlClient only), `AllPostgreSQL13Plus`, `AllMySqlConnector`. `[EFDataSources]` **intersects** `--provider` with it, so a non-`.MS` SQL Server id (`SqlServer.2022`, System.Data.SqlClient) is dropped and the run reports **0 cases as a pass** — a false green, not an error. Use `SqlServer.2022.MS`. A pool-leak repro especially needs a *pooled server* provider (SQLite has no hard pool cap), so this trap can hide the very bug under test.
- **Model / mapping-schema assertions need no database at all.** `ctx.Model` builds the EF model and `LinqToDBForEFTools.GetMappingSchema(ctx.Model, ctx, null)` builds the linq2db schema without opening a connection or resolving a data provider — so one test can construct contexts on *two* providers (e.g. SQLite plus SQL Server via a throwaway connection string) and compare their schemas with no container, and it passes under any `--provider`. `ctx.CreateLinqToDBContext()` / `CreateLinqToDBConnection()` do **not** qualify: they go through `GetEFProviderInfo` → `Database.GetDbConnection()`, which constructs the ADO connection (and on EF3/net462 that alone can fail locally: the test exe's output may lack an x64 `runtimes/win-x64/native/e_sqlite3.dll`, so SQLite connections throw `TypeInitializationException` on `SqliteConnection` — an environment fault, not a code one). Used by `MappingSchemaCacheTests`.
- **Suppress baseline capture for loop / stress tests.** `using var _ = new DisableBaseline("reason");` (`Tests/Base/ScopedSettings.cs`) turns off SQL-baseline recording for its scope. Use it for a test that runs the same statement many times (e.g. a 300× connection-leak loop) — otherwise every iteration is captured, bloating the baseline by thousands of identical lines per provider/EF combo.
- **The EF test database is shared across tests, not recreated per test.** `ContextTestBase.CreateContext` runs `EnsureDeleted` / `EnsureCreated` only when the connection string's last context type differs (`TestContextTracker.LastContexts`, `Tests/EntityFrameworkCore/ContextTestBase.cs`), so every test on the same context sees the rows earlier tests left. A test that inserts must clear its own tables first (e.g. `ctx.X.ToLinqToDBTable().Delete()`) or use keys nothing else writes. `HasData` seed rows are the only data guaranteed at start.
- **In a worktree, use absolute paths.** The Bash tool's cwd is always the *primary* clone, and `cd <worktree> && dotnet …` is hook-rejected (no `&&`). Pass the absolute worktree csproj / exe path to `dotnet build` / the test exe instead.

### Running providers in parallel

Each provider config maps to a distinct database, so runs scoped to **distinct** providers don't collide and can run concurrently. Three cautions, the first two from the standing single-session rule:

- **One distinct provider (= one database) per parallel run.** The same provider on two concurrent runs — including the *same* provider across two TFMs — hits the same database and corrupts state. The parallel unit is the database, not the process.
- **A connection override that points two configs at one database breaks that inside a single run.** Pointing `SqlServer.2005` and `SqlServer.2005.MS` both at `tempdb` fails one config only, with a schema error (`Cannot drop the table … does not exist`) — a false red beside the real result. Give each config its own database, or run them one at a time.
- **Build once, and don't let the runs build concurrently.** Two `dotnet test` invocations on the same project race to write and lock the shared `linq2db.Tests.dll` (fails with `MSB3027`). Build once, then launch each run as the **test executable directly** — it never builds, and each process writes its own per-PID heartbeat:

```bash
dotnet build Tests/Linq/Tests.csproj -c Debug -f net10.0
```
```bash
.build/bin/Tests/Debug/net10.0/linq2db.Tests.exe --provider PostgreSQL.18 --test-progress --filter "FullyQualifiedName~CreateData.CreateDatabase|FullyQualifiedName~MyTest"
```
```bash
.build/bin/Tests/Debug/net10.0/linq2db.Tests.exe --provider MySql.8.0 --test-progress --filter "FullyQualifiedName~CreateData.CreateDatabase|FullyQualifiedName~MyTest"
```

- **Don't start a run while another is still opening file databases.** Every run's startup (`TestBase`'s static constructor → `DatabaseUtils.CopyDatabases()`) deletes and re-copies the output's `Database` folder, so a second exe launched from the same output while the first holds SQLite / Access / SQL CE files open dies with `IOException: The process cannot access the file 'TestData.MS.sqlite'` — every test failed within a second, providers notwithstanding. Put the file-database providers in one process, or launch the next run only once the first is past initialization. (#5640: a ClickHouse run started alongside a YDB + SQLite.MS run.)

Each process writes its own `.build/.agents/test-progress.<tfm>.<pid>.json`; poll them with `/test-progress` or `test-status.ps1`. The runner's native filter flag is `--filter` (the same `FullyQualifiedName~` syntax), confirmed via `--help`.

**Firebird temp-table teardown must scope its pool clear — never `FirebirdTools.ClearAllPools()`.** Firebird needs the pooled connection evicted after a temp-table drop (its lingering metadata reference otherwise fails the next DDL with `object TABLE … is in use` / `lock conflict on no wait transaction`). But `ClearAllPools()` is **process-wide** across every connection string, so under parallel execution it tears down the connections other concurrently-running Firebird versions (2.5/3/4/5, each a distinct connection string) are actively using. Use the scoped `FirebirdTools.ClearPool(connection)` (direct path) or `ClearPool(connectionString)` (remote/LinqService path, where the context isn't a `DataConnection` — resolve via `GetConnectionString(config.StripRemote())`); `TestUtils.ClearFirebirdPool` is the shared helper. (PR #5689.)

## Database initialization

`Tests.Linq.Create.CreateData.CreateDatabase` is attributed `[Test, Order(0)]` — NUnit runs it first in the session, and every downstream test that calls `GetDataContext(context)` relies on it having created + populated the provider's schema. After a container restart, a fresh clone, or an aborted previous run, the schema may not be current.

**Always include `CreateDatabase` in your `--filter`.** Prepend `FullyQualifiedName~CreateData.CreateDatabase|` to any filter you construct — the test is idempotent, re-running it is cheap, and it removes the "empty database" failure mode entirely.

**Derive the `FullyQualifiedName~` filter from the test's `namespace`, not its folder path — and sanity-check the run's test count.** linq2db test namespaces don't mirror the directory tree: `Tests/Linq/Linq/QueryGenerationTests.cs` is `namespace Tests.Linq` (not `Tests.Linq.Linq`), `Tests/Linq/Update/MergeTests.*.cs` is `Tests.xUpdate`. A filter built from the folder (`FullyQualifiedName~Tests.Linq.Linq.QueryGenerationTests`) matches **zero** real tests, so the run is **vacuously green** — only the prepended `CreateDatabase` cases execute (e.g. `total: 3`, "Passed!"). Always `Grep` the file's `^namespace` line to build the filter, and after the run confirm `total` is in the expected ballpark — a suspiciously small `total` on a "passed" run is the tell. (Surfaced verifying #5599/#5169 ungatings: a `Tests.Linq.Linq.*` filter ran 3 tests and reported green before the count exposed it.)

```bash
dotnet test --project Tests/Linq/Tests.csproj -f net10.0 --filter "FullyQualifiedName~CreateData.CreateDatabase|FullyQualifiedName~FirebirdTests.DropTableTest" --settings .runsettings --test-progress
```

If your test modifies data, revert changes to avoid side effects in downstream tests.

**`CreateDatabase` runs on an *ungated* lane keyed by provider context, so two configs sharing one server run their create scripts at the same time.** `DatabaseLaneStrategy.Classify` returns `LaneAssignment.Ungated(context)` for it — deliberately off the provider's serial lane, so a provider's other tests can wait on its readiness latch without queueing behind it. The key is the **context string** (`NUnitUtils.GetContext` folds in only the `.LinqService` suffix), not the physical server, and several CI configs share one container: `MySql.8.0` + `MySqlConnector.8.0` on port 3306, `MySql.5.7` + `MySqlConnector.5.7` on 3307 ([`Build/Azure/scripts/mysql.sh`](../../Build/Azure/scripts/mysql.sh)). Each config has its own database (`testdata` / `testdataconnector` in `DataProviders.json`), so per-database DDL is safe — but anything **server-global** in a create script is not, and the two lanes will interleave on it. Namespace such an object per config with the script's `{DBNAME}` macro: `CreateData.RunScript` does a plain `text.Replace("{DBNAME}", db.OpenDbConnection().Database)` over the whole file before splitting it into batches. (Surfaced on [#5882](https://github.com/linq2db/linq2db/pull/5882): `MySql.sql` created a hardcoded `test_schema` — in MySQL a *schema* is a **database**, so it is server-global, unlike the per-database `test_schema` in `PostgreSQL.sql` / `SqlServer.sql`. One lane's `DROP SCHEMA IF EXISTS` landed inside the other's `CREATE SCHEMA` → `CREATE TABLE test_schema.TestSameName` window and the leg failed with MySQL 1049 `Unknown database 'test_schema'`. Fixed by `test_schema_{DBNAME}`.)

**Resolving a config's provider before its database exists can cache the wrong provider for the whole process.** A config whose `Provider` is a bare driver name with no version in the config name is resolved by server-version detection, which connects with the configured string. `MariaDB.11` is the local case: it is registered as plain `MySqlConnector`. When that database is missing the open fails with 1049, `MySqlProviderDetector` swallows the error and returns the MySQL 5.7 fallback, and `ConfigurationInfo.DataProvider` caches it (`MySqlProviderDetector.cs:72-86`, `DataConnection.Configuration.cs:127`). Every later `MariaDB.11` test in the run then sees MySQL 5.7, and CTE tests fail with *"DataProvider do not supports Common Table Expressions"*. Code that runs before the database exists must not call `GetDataProvider(<config>)` or open a `DataConnection` on the config: use an explicit provider over raw ADO, as `a_CreateData.EnsureMySqlDatabase` does ([#6054](https://github.com/linq2db/linq2db/pull/6054)). The same applies to a test that needs no database at all, such as one checking a provider's `MappingSchema` or literals. The unversioned `DataConnection.GetDataProvider(name, cs)`, and a `<Tools>.GetDataProvider()` left on its `AutoDetect` version default (Oracle, Firebird, SQL Server, …), auto-detect the server version by opening a connection, which then fails quietly. Use the version-pinned factory instead (`OracleTools.GetDataProvider(OracleVersion.v12, OracleProvider.Managed)`, `FirebirdTools.GetDataProvider(FirebirdVersion.v5)`). ([#6058](https://github.com/linq2db/linq2db/pull/6058))

**A filtered run that skips `CreateDatabase` can show failures that masquerade as pre-existing / unrelated.** A prior data-mutating test can leave `TestData*.sqlite` with corrupted rows; a later filtered run then reads bad data and fails on tests that have nothing to do with your change. **Stash-and-rerun does not disprove this** — both runs share the same corrupted file, so they fail identically and the comparison looks like "pre-existing". Before concluding "these failures pre-date my change / are unrelated", re-run with `FullyQualifiedName~CreateData.CreateDatabase|` prepended to rebuild the schema.

**A filtered run that skips `CreateDatabase` on a provider can also look like a hang.** Each provider test waits in `TestBase.OnBeforeTest` → `CustomTestContext.AwaitDatabaseReady` for that provider's `CreateDatabase` to signal readiness, bounded at **2 minutes**. Skip it, and every test stalls for 2 minutes before it proceeds. A `--hangdump-timeout` shorter than that dumps a fake hang with `ResourceReadinessLatch.WaitReady` at the top of the test thread's stack. When a hand-run "hang" shows that frame, fix the filter before analysing the dump. (#5978 Firebird repro loop.) This applies especially when working in a `git worktree` — where each worktree has its own `TestData*.sqlite`. `/test` runs against a worktree when you pass `run <filter> worktree <abs-worktree-path>` (it forwards `repoRoot` to `test-runner`), and it injects the `CreateDatabase` prefix for you; don't hand-run `dotnet test` there (see [`worktree.md`](worktree.md) → *Running tests from a worktree*).

## A test that fails only on NETFX (net462) jobs

When CI shows a test failing on the `Tests (NETFX x64)` jobs while the same test passes on the .NET 8/9/10 tasks of the same provider, suspect a **runtime driver divergence**, not a TFM-agnostic code bug. ADO.NET providers can behave differently across runtimes — e.g. `SqlDataReader.GetName` returns duplicate empty names for unnamed result columns (`select 1, 1`) on .NET Framework but distinct names on modern .NET (#5659).

The `Testing` config is net10.0-only and a net10.0 run **won't reproduce** such a failure. Reproduce on net462 directly:

```bash
dotnet build Tests/Linq/Tests.csproj -c Debug -f net462
```
```bash
.build/bin/Tests/Debug/net462/linq2db.Tests.exe --provider SqlServer.2022 --test-progress --filter "FullyQualifiedName~CreateData.CreateDatabase|FullyQualifiedName~<Fixture>.<Test>" --settings .runsettings
```

`--provider` supplies the connection string from `DataProviders.json` without editing the enabled-providers list; the net462 exe runs x86. This is the runtime sibling of the compile-time `agent-rules.md` → *TFM API availability* rule.

**Second cause: the expression tree itself differs.** C# 14 binds `array.Contains(x)` to `MemoryExtensions.Contains(ReadOnlySpan<T>, T)` on net8+ but to `Enumerable.Contains` on net462, and linq2db translates the two differently: `MemoryExtensions` is never queryable, so it goes to the IN-list predicate or the client, while `Enumerable.Contains` over a non-constant array can reach `ContainsBuilder` and become a `VALUES` subquery. A query over `new[] { col, … }.Contains(…)` can therefore build different SQL per TFM, and a local net10 green says nothing about the net462 legs — reproduce on net462 as above. (#5983: green locally on net10, red on every net462 leg.)

## Running against the netstandard2.0 asset

The divergence above is between two *user* TFMs. There is a third combination that no CI leg runs: a **modern runtime loading linq2db's netstandard2.0 asset**. That is what an app gets when it consumes linq2db through a netstandard2.0 library, or when its runtime's TFM has been dropped. Here the user's code is compiled for net8+ (so `array.Contains` *is* the `MemoryExtensions` shape), but every `#if NET8_0_OR_GREATER` branch in linq2db is missing (#6067). Which gates must still work there is policy: [`code-design.md`](code-design.md) → *A TFM gate may withhold a feature, never recognition of unchanged source*.

Run it locally. The script builds `Source/LinqToDB` at the test TFM with the netstandard2.0 define set, so every TFM gate takes its ns2.0 branch, and overlays that `linq2db.dll` onto the net10.0 test output:

```powershell
& .claude/scripts/worktree-test.ps1 -RepoRoot <checkout> -Project Tests/Linq/Tests.csproj -Tfm net10.0 -LinqToDBAsset netstandard2.0 -Filter "FullyQualifiedName~CreateData.CreateDatabase|FullyQualifiedName~<Fixture>.<Test>" -Provider SQLite.MS
```

It runs with `--no-build`, then restores the test output and rebuilds `Source/LinqToDB` normally. The JSON reports `linqToDBAsset`, so a result can't be mistaken for a normal run.

**Why a simulation, not the real ns2.0 binary.** Overlaying the actual netstandard2.0 `linq2db.dll` fails every test in setup with `MissingMethodException: …ClickHouseOptions.<Clone>$()`. Tests compiled against net8+ call a record's covariant `<Clone>$` for every `with`, and the ns2.0 build doesn't have it. The simulation reproduces every `#if` gate. It does not reproduce the ns2.0 polyfills' type identities (`Index`, `Range`, `IsExternalInit` bind to the BCL types here). (#6067.)

Two reading rules:
- **`MissingMethodException` / `TypeLoadException` is a feature-parity gap, not a break.** The tests call API that the ns2.0 code paths don't have.
- **A regression test for an ns2.0 break is green on every CI leg before the fix as well.** Its red→green proof exists only under this simulation, so record both runs in the PR.

## A narrowed provider set is a claim — re-derive it when the feature stops being provider-conditional

`[DataSources]` is the default for a reason: it runs everything configured, so a provider that cannot do the thing
says so. Every narrowing away from it — `[IncludeDataSources(a, b, c)]`, or an exclusion list — encodes a *reason*,
and that reason has a lifetime. The common one is a feature with two code paths, where the tests were pinned to the
providers exercising the interesting path so an SQL-text assertion meant something. When the branch later collapses
those paths into one, the pin stops being a statement about the feature and becomes an inherited artifact: the tests
still pass, the list still looks deliberate, and the coverage is quietly narrower than the code's reach.

So when a change **removes** a provider-conditional path, revisit the provider sets of every test that touched it
rather than carrying them forward. Widen to bare `[DataSources]` with **no** exclusions first, and let a real failure
justify each exclusion you then add — a pre-emptive gate on a provider you never ran is a guess that outlives the
person who made it (`AGENTS.md` → *Keep digging to the root*). Tests that legitimately stay narrow are the ones
narrow for a non-provider reason: SQL-text assertions, call-site guards that throw before any SQL is built,
query-cache tests, and anything embedding literal `FromSql` text.

(2026-09-21, #5708: the pivot/unpivot tests were pinned to SQLite + DuckDB + SQL Server + Oracle because those were
the providers with a native `PIVOT`/`UNPIVOT` keyword and the tests asserted native-vs-lowered SQL. When native
emission was deleted and everything became translated SQL, the pins had no remaining justification — and PostgreSQL,
the one provider whose emitted SQL the change actually altered and the only one gaining a version gate, was not in
any of them. *"as we moved from native to translated sql - those should execute all providers as [DataSources]"*.)

**A new `[DataSources]` test inherits its siblings' measured gates.** When a sibling test of the same mechanism already gates or excludes a provider for a measured failure (`#5998` Access ODBC sub-seconds, `#6062` SqlCe decimal scale), that failure is known, so the new test carries it from the start — or runs the provider and shows it does not apply. And a query moved or widened off one provider is checked against master's tests for **each capability-gated clause it contains** — a window frame, a `LAG` default, a `Decimal` width — not only for the function it is named after. (#5959 round 7: three round-6 tests widened to `[DataSources]` failed on Access ODBC, Firebird 3 — a `ROWS` frame master already pins in `WindowFunctionsTests.LastValue` — and SqlCe, each gated on a sibling.)

**State the reason at the attribute.** A narrowed set — an exclusion in `[DataSources(...)]`, or an `[IncludeDataSources(...)]` that is not a single-provider translator test — carries a `//` line directly above the test (or in its leading comment) naming why each provider is in or out: the measured failure, or the provider-conditional mechanism the test exists for. A test comment that implies a wider set than the attribute runs is the same defect in reverse — a reader widens it and gets a red leg.

```csharp
// Sybase: https://stackoverflow.com/questions/25281843
[Test]
public void PowDecimalBaseScale([DataSources(TestProvName.AllSybase)] string context)

// Only YDB and ClickHouse render a decimal literal's scale, so only they can cut the value.
[Test]
public void RoundDecimalValueScale([IncludeDataSources(true, TestProvName.AllYdb, TestProvName.AllClickHouse)] string context)
```

Not this: a two-provider `[IncludeDataSources]` whose comment explains only how the query is shaped, or a YDB-only test commented "on the providers that render a literal's scale". `.claude/scripts/test-diff-sweep.ps1` lists every narrowed attribute a branch adds, with the line above it. (#5943: asked for in review rounds 2 and 5, missed again in round 6 — NIT019, NIT020.)

## Test Patterns

```csharp
[TestFixture]
public class MyTest : TestBase
{
    [Test]
    public void TestSomething([DataSources] string context)
    {
        using var db = GetDataContext(context);
        // AssertQuery runs query against both DB and in-memory collections
        // and verifies matching results
        AssertQuery(db.Person.Where(_ => _.Name == "John"));
    }
}
```

- `[DataSources]` — runs test for each enabled database provider
- **Reading a test's provider scope — `[DataSources]` arguments are an *exclude* list, and the remote path is on by default.** `[DataSources(A, B)]` runs the test on every enabled provider *except* A and B, **and** includes each provider's `.LinqService` remote case (the bare `DataSourcesAttribute(params string[])` constructor passes `includeLinqService: true`). `[DataSources(false, A, B)]` is the same exclude set with the remote case suppressed. `[IncludeDataSources(includeLinqService, A, B)]` is the opposite shape — an include *whitelist* (only A, B), with the leading bool controlling the remote case. **The bare `[IncludeDataSources(A, B)]` overload passes `includeLinqService: false`** (`Tests/Base/Attributes/IncludeDataSourcesAttribute.cs:10-13`) — the *opposite* default from bare `[DataSources]`, so an include-scoped test is direct-only unless you spell out `[IncludeDataSources(true, …)]`. (A #5701 probe temporarily rewrote two tests to `[IncludeDataSources(TestProvName.AllYdb)]` to capture the exception each leg throws, got `total: 2` instead of 4, and nearly concluded the remote context was unavailable for YDB.) When judging whether a test covers a provider (e.g. in review), do **not** read the argument list as an include set: `[DataSources(TestProvName.AllMariaDB, TestProvName.AllMySql57)]` *does* run on Oracle, SQL Server, etc., including their `.LinqService` variants. (A #5723 review pass misread this as MySQL/MariaDB-only with no remote path and raised two spurious coverage findings.)
- `TestBase` — base class providing `GetDataContext()`, `AssertQuery()`, etc.
- **In a `TestBase` fixture, `Person`, `Parent`, `Child` … name the in-memory collection properties, not the model types.** `nameof(Person.FirstName)` binds to the `IEnumerable<Person>` property and fails `CS1061`; write `nameof(Tests.Model.Person.FirstName)` or the string literal. (#5708, 2026-10-22.)
- **`AssertQuery` is blind for an `IQueryable<object>` — pass an explicit comparer.** It defaults to `ComparerBuilder.GetEqualityComparer<T>()` (`Tests/Base/TestBase.AssertQuery.cs:467`), which compares `T`'s *members*. For `T = object` there are none: `GetEqualsFunc<object>()` walks an empty `TypeAccessor.GetAccessor<object>().Members` (`ComparerBuilder.cs:34`) and `CreateEqualsFunc` folds the empty set with `.DefaultIfEmpty(ExpressionInstances.True)` (`:201-203`), yielding an always-true equality. Only the **row count** is then checked, so a test over an `object`-typed projection passes while every row holds the wrong value — or the wrong *type*. Pass `AssertQuery(query, EqualityComparer<object>.Default)`, which for anonymous types dispatches to their compiler-generated structural equality, and add a direct type assertion (`result.ShouldAllBe(x => x.GetType() != typeof(string))`) so the test states the defect rather than inferring it. The trap is silent in the direction that matters: a red→green obligation written with the bare call is **green in both arms**. (#5916: caught by the plan critic reading the comparer's source; the fixture's six regressions would otherwise have proven nothing.)
  - `ShouldAllBe` takes an `Expression<Func<T,bool>>`, so `x is not string` is `CS8122` — use `x.GetType() != typeof(string)`.
- Tests live in `Tests/Linq/` (main tests), `Tests/Base/` (test framework), `Tests/Model/` (model classes)
- **Provider-specific tests go in that provider's own fixture.** A test exercising one provider's behavior (a YDB CTE-naming quirk, an Oracle row-predicate case) belongs in the provider fixture (`Tests/Linq/DataProvider/YdbTests.cs`) — not prepended to a shared cross-provider fixture (`CteTests`, `WhereTests`). Shared fixtures are for behavior asserted across many providers.
- **No new per-issue `Issue<N>Tests.cs` fixture (`Tests/Linq/UserTests/`, `Tests/EntityFrameworkCore/Tests/`), and no new tests in an existing one.** An issue regression goes into the fixture that owns the behaviour, or into a new fixture named for it (`Tests/Linq/<Area>/<Behaviour>Tests.cs`); the issue goes in `[Test(Description = "<url>")]`. The catch-all `IssueTests.cs` stays allowed. The existing per-issue fixtures are legacy, and review flags new or extended ones ([`test-review-checklist.md`](test-review-checklist.md)). (#6058)
- **No `#region` blocks or banner comments in test methods.** Don't wrap added tests in a new `#region`, and don't introduce `//----` banner comment blocks. Keep explanatory comments as plain `//` lines **inside** the method body next to the code they describe — and don't relocate existing in-body comments out to the method/attribute level when making an unrelated edit.
- **Mapping attributes live in the `LinqToDB` root namespace.** `ExpressionMethodAttribute` (and peers) are `LinqToDB.*`, not `LinqToDB.Mapping.*` — a test/playground file needs `using LinqToDB;` in addition to `using LinqToDB.Mapping;`, otherwise `[ExpressionMethod(...)]` fails with `CS0246`. (`ColumnAttribute`, `TableAttribute`, `InheritanceMappingAttribute` are in `LinqToDB.Mapping`.)
- **Feature-gated test attributes use *exclude* filters, not include whitelists.** An attribute that scopes a run to providers supporting some feature (the `FeatureSources/` attributes, e.g. `SupportsAnalyticFunctionsContext`) should subclass `DataSourcesAttribute` with an `Unsupported` exclude list — like `InsertOrUpdateDataSourcesAttribute` — **not** an `IncludeDataSourcesAttribute` whitelist. Exclude-based means a newly-added provider context is covered automatically (only the genuinely-unsupported providers are listed); a whitelist silently omits every new context until someone remembers to add it. Reuse / convert an existing feature attribute rather than adding a parallel one, and keep per-feature gaps (a provider that supports the feature family but not one function) as `[ThrowsForProvider]` on the individual test, not in the attribute.
  - **The same provider set is also pasted as a literal in `[ThrowsCannotBeConverted(...)]`, and that is not an oversight to "fix".** `SupportsAnalyticFunctionsContextAttribute.Unsupported` is the canonical `IsWindowFunctionsSupported == false` set — Access, SqlCe, Sybase, MySQL < 8.0, Firebird < v3 — but it is a `List<string>`, so it **cannot** be an attribute argument. Tests that assert the *throw* on those providers therefore spell the list out: `[ThrowsCannotBeConverted([TestProvName.AllAccess, ProviderName.SqlCe, TestProvName.AllSybase, TestProvName.AllMySql57, TestProvName.AllFirebirdLess3])]`, currently 22+ occurrences across `UnionByMethodTests`, `ExceptByMethodTests`, `IntersectByMethodTests`, `IndexMethodTests` and `DistinctByMethodTests`. Copy the literal verbatim when adding such a test (`ThrowsForProviderAttribute` splits each argument on `','`, so the `TestProvName.*` multi-name constants work as-is). Hoisting it would need a `const string` on `TestProvName` referenced from both sides — a repo-wide test-infra change, not something to do in passing while adding a test, and not a review finding on a PR that merely adds more copies.
- **A fixture named `Issue<N>Tests` names what the fixture tests, not why a gate inside it exists.** When attributing an `[ActiveIssue]` (or any per-test waiver) that carries no number of its own, the fixture's number is the obvious guess and it is right about half the time — so check the issue's actual title against the gate's stated reason, in both directions. It rejects as often as it confirms, and a wrong number is worse than none: it asserts a tracked defect that does not exist and sends the next reader to an unrelated report. Where no issue covers the gate's reason, a `no-issue:` marker with a one-line note is the honest answer — **for a refusal or a probed server limit only.** A gate whose observed failure is a silent wrong value (a truncated time, a lost row) gets a filed issue instead: `no-issue:` there files a fixable defect as a fact of life. (#5959: a Sybase `date UNION datetime` truncation gated `no-issue:` became #6050: the same branch already cast around that Sybase mismatch in comparisons.) (Both outcomes on #5882, one after the other: `Issue1363Tests.TestInsert` is gated for "Unsupported INSERT syntax" while #1363 is about null subquery parameters — unrelated, so it takes `no-issue:`; `Issue133Tests.PositiveWindowFunctionsWhereTest` is gated for "Wrong Having detection" and #133 is "Generation of subquery instead of HAVING returns wrong results" — an exact match, so 133 is correct.)
- **A test's full name must be unique — it is an identity key, not a label.** `linq2db.baselines` files are keyed by the fully-qualified test name, so two cases resolving to the same full name (e.g. a `TestCaseSource` / `ValueSource` yielding duplicate argument tuples) is a **test-authoring bug to fix by renaming**, not a condition harness code has to defend against. Harness code keyed on `ITest.FullName` may therefore assume uniqueness — don't add collision handling for it, and don't raise review findings speculating about name collisions. (Established while reviewing #5726, where the heartbeat's deferral map keys on `ITest.FullName`.)
- **Shared-fixture leftovers are a test bug — never design around them.** `AllTypes` and `Person` are pre-filled fixtures many tests insert into. A row left behind after a test is **not** a tolerated steady state: it means that test forgot to clean up, and the harness is built to expose it. `TestBase.Identity.cs`'s header says so outright — *"We intentionally don't remove extra records and allow it to fail in that cases to allow us detect tests that forget to cleanup and leave junk records in those tables"* — so `ResetAllTypesIdentity` reseeds the identity (`lastValue = 2` → next id 3) without deleting anything. Consequences when a fixture-dependent test goes red: **(a)** the correct fix is to find the test that leaked the row, not to make the failing query tolerate it; **(b)** do not read "leftovers exist by design" out of that comment — the design is the *detection*, not the leftovers; **(c)** a lookup rewritten to dodge a stray row (adding `ORDER BY ID` to a by-value lookup, `TOP 1`, a tighter predicate) converts a test that was correctly reporting a bug into one that passes while the bug remains. **(d)** The identity-collision detector only catches junk at ids adjacent to the reseed point — rows further up (a run that inserted tens of thousands of times) collide with nothing and are invisible to it. (Surfaced post-merge on #5754: disabling DB2's `AUTO_STMT_STATS` changed a query plan, which surfaced surviving `AllTypes` rows at ids 50773–216310; the PR added `ORDER BY ID` to `DataProviderTestBase.PassNullSql`/`PassValueSql` — citing that same comment as license — rather than finding the leak.)
- **Test layout — house rules for new test code:** see [*Test layout*](#test-layout) below.
- **EF Core tests only run the `.MS` (Microsoft.Data.SqlClient) SQL Server variants.** `EFIncludeDataSources` / `EFDataSources` intersect the requested providers with `TestConfiguration.EFProviders`, whose SQL Server entry is `AllSqlServer2016PlusMS` — Microsoft.Data.SqlClient only. Passing a `System.Data.SqlClient` name (`SqlServer.2022`) to an EF test — including `test-runner`'s `--provider` — resolves to **zero** variants and reports `none_matched` (not an error), so it silently looks like the test "passed" nothing. Use the `.MS` name (`SqlServer.2022.MS`). The full EF provider scope is `SQLiteMS` + `AllPostgreSQL13Plus` + `AllSqlServer2016PlusMS` (+ `AllMySqlConnector` off net10) — narrower than the plain-linq2db set. (`TestConfiguration.cs` → `EFProviders`.)

## Test layout

These are the maintainer's house rules for **new** test code, and they win over the enclosing fixture's idiom. Many older fixtures (`AllAnyTests.cs` uses `AreEqual` throughout) predate them, so "match the surrounding file" is not a reason to write a one-liner. Leave existing, untouched tests as they are; reformat a master test only when the PR already rewrites most of it.

1. **One call per line in a method chain.** That covers both LINQ queries and assertion chains. Prefer putting the query in a variable and asserting it separately over a long chain that ends in `.ShouldBe(...)`.

   ```csharp
   // not this
   db.Parent.Where(p => p.Value1 != null).Any(p => p.Value1 > 1)
       .ShouldBe(Parent.Where(p => p.Value1 != null).Any(p => p.Value1 > 1));

   // this
   var expected = Parent
       .Where(p => p.Value1 != null)
       .Any(p => p.Value1 > 1);

   db.Parent
       .Where(p => p.Value1 != null)
       .Any(p => p.Value1 > 1)
       .ShouldBe(expected);
   ```

   A single call followed by an assertion is a chain too — the shape an eyeball sweep misses (#6008 round 3):

   ```csharp
   // not this
   FormattableStringHelper.TrySplit(create, out var format, out var split).ShouldBeTrue();

   // this
   FormattableStringHelper
       .TrySplit(create, out var format, out var split)
       .ShouldBeTrue();
   ```

2. **Query syntax, multi-line, one clause per line.** Use query syntax whenever the query has a `join` or `SelectMany`. A plain `Where`/`Select` chain can stay method syntax, laid out per rule 1.
   - Put `var query =` on its own line, then `from`, `where`, `orderby`, `group … into` and `select` each on their own line.
   - Break a non-trivial `select new` into `{ … }` lines.
   - A chain inside the projection follows rule 1.
   - A query passed straight to `AssertQuery(` gets the same layout.
   - Set operations have no query-syntax form, so they stay `.Concat(...)` etc.
   - When a join sits on top of a set operation, wrap it: `from x in a.Concat(b) join …`.

3. **`AssertQuery` instead of a hand-duplicated `AreEqual` expected.** `AreEqual(<LINQ-to-objects copy>, <db query>)` keeps two copies of the query that can drift apart. `AssertQuery(query)` derives the expected result from the same query, against the in-memory collections. Four cases where the rule does not apply:
   - **Scalar results.** A root `Any` / `All` / `Count` cannot go through `AssertQuery`. Use rule 1's form with an in-memory `expected` and `ShouldBe`.
   - **`object`-typed projections.** These need the explicit-comparer caveat in *Test Patterns* above.
   - **Scalar element types.** Still `AssertQuery`, but pass `EqualityComparer<T>.Default` (`<T?>` for a nullable result). The default comparer compares `T`'s public instance members: an `int`, `double`, `string` or `DateTime` has none, so every pair compares equal and the assertion checks only the row count ([#6099](https://github.com/linq2db/linq2db/issues/6099); #5943 MIN022: `DegreesOfIntTruncates` over `int`). A `decimal` has members, `Scale` included, so a provider returning `2.50` for an expected `2.5` fails instead (#5943: `Round16` on YDB). An anonymous-type projection is unaffected.
   - **Aggregates over a navigation.** `AssertQuery` evaluates the expected side over tables it reads back from the database, and on that side `p.Children.Max(c => (int?)c.ChildID) == 11` came out false for every parent. It expected 7 rows where 6 were correct (#6121, `NegatedNullableAggregateComparisonFromSubquery`). Keep `AreEqual` with an explicit LINQ-to-Objects expected over the model collections, and say why in a one-line comment so a reviewer can tell it from a layout slip.

   What a conversion trades away: `AssertQuery` re-reads every table the query names (`TableName(…)` included) and runs the expected side over that read-back data, then compares count plus a two-way `Except` — order is not checked, and a value the database stored wrongly is wrong on both sides. So changing the test's data cannot prove a converted test can fail; prove it with a product mutation that forces a wrong value (#5943 round 5: away-from-zero answered to-even turned each converted `Round32`–`Round35` red). The actual query runs first, so a red and an `[ActiveIssue]` gate's exception are unchanged.

   **The expected side runs the provider's `Expressions` map expansions too.** On a provider with a `MapMember` entry for the member under test, the expected value is the map's C# expansion, not the member's own body. A red or green there partly measures the map — e.g. Oracle's `Sql.Right` map made the expected value of `Right("John", 5)` NULL, not `"John"`. Judge a mapped provider's result again once the map entry is gone (#5922).

   **A test of a translation must make the call reach SQL — wrap it in `Sql.AsSql(...)`.** In a projection, a call over columns is often left to the client: most translator handlers decline when `TranslationFlags.Expression` is set and `CanBeEvaluatedOnClient` holds, and the value is then computed in C# from the fetched columns. The test passes on every provider while testing nothing — check that the function appears in the baseline SQL. (#5922: `MathRoundNegativeMidpoints` was green on 16 providers with SQL `SELECT Id, D, F`; with `Sql.AsSql` it went red on 14.) Keep a separate un-wrapped cell when the client fallback is itself under test.

   ```csharp
   // not this
   AreEqual(
       from p in    Parent orderby p.ParentID select new { p.ParentID, Has =    GrandChild.Where(g => g.ChildID != null).Any(g => g.ParentID == p.ParentID) },
       from p in db.Parent orderby p.ParentID select new { p.ParentID, Has = db.GrandChild.Where(g => g.ChildID != null).Any(g => g.ParentID == p.ParentID) });

   // this
   var query =
       from p in db.Parent
       orderby p.ParentID
       select new
       {
           p.ParentID,
           Has = db.GrandChild
               .Where(g => g.ChildID != null)
               .Any(g => g.ParentID == p.ParentID),
       };

   AssertQuery(query);
   ```

Review severity for a violation in added test code is `NIT`, with a `suggestion` block (the [`code-reviewer`](../agents/code-reviewer.md) rule 7). (Codified after #6027: all five new `AllAnyTests.Issue6024_*` tests broke these rules. Two review rounds missed them because the rules lived only in personal auto-memory.)

**Naming in a feature fixture** binds hand-written tests too, not only `test-writer`'s: no `Issue<N>`-prefixed types or test names in a shared `<Feature>Tests.cs` — the issue goes in `[Test(Description = "<url>")]` only. Rule and severity: [`test-writer.md`](../agents/test-writer.md) → *Fixture lookup*, [`test-review-checklist.md`](test-review-checklist.md) → *`Issue<N>` names in a shared feature fixture*. (#6060)

**Core behaviour is tested on the common models, not on a copy of the issue's.** Build the repro on `Tests/Model` (`Parent` / `Child` / `Person` …) and its pre-populated tables, and add a fixture-local type only for the shape the shared models lack — e.g. a base class and interface mapped onto the existing `Child` table, not new `Client` / `Contract` tables via `CreateLocalTable`. The shared data also gives an in-memory `expected` and a `[DataSources]` matrix for free. (#6109)

**Asserting that a test helper's assertion fails needs NUnit's `Assert.Throws`, not `Should.Throw`.** NUnit records a failed `Assert.That` on the current test result before it throws `AssertionException`, so catching the exception does not un-fail the test. `Assert.Throws<AssertionException>(() => AssertQuery(…))` runs the delegate in `TestExecutionContext.IsolatedContext`, which uses a fresh result and discards the recorded failure; Shouldly's `Should.Throw` has no such isolation. This is the one deliberate exception to "Shouldly over `Assert`". (#6131, measured by decompiling NUnit 4.6.1 `Assert.Throws` / `CreateIsolatedContext`.)

## Constant vs parameter arguments in test queries

A captured variable passed as a method argument inside a query is a query parameter, not a constant: in `foreach (var p in …) t.Select(r => Math.Round(r.D, p))` the translator sees a `SqlParameter` and takes its runtime branch. A test meant to pin a translator's *constant* branch must put the literal in the lambda (`Math.Round(r.D, 4)`), and its SQL must show no `DECLARE` for that argument. (#5943: `Round24`'s "constant precision" section looped over `p` and exercised only the runtime path until the logged SQL showed `DECLARE $p Int32`.)

## F# tests

F# regression tests live in `Tests/FSharp/*.fs` (compiled into `Tests.FSharp.fsproj`) and are driven from C# fixtures in `Tests/Linq/Linq/FSharpTests.cs`.

- **Call `nonNull` on nullable-returning members before instance methods.** The F# project has nullness enabled, so a member typed `string | null` (e.g. `DataConnection.LastQuery`) trips `FS3261` ("nullness warning … do not have compatible nullability") — a **warning-as-error** — the moment you call an instance method on it (`.Substring`, `.IndexOf`, …). Bind through the F# 9 `nonNull` helper first: `let sql = nonNull db.LastQuery`. Passing the raw value to an API that accepts `obj`/`object` (e.g. an NUnit `Assert.That(x, constraint)`) does **not** trip it — only instance-member access does. (`nonNull` is the established idiom — `FSharpQueryExpressionInterceptor.fs` uses it.) This is F#-compiler-specific, so the fast `Testing` (net10.0) build **does** catch it — unlike the `net462`/`netstandard2.0` BCL-availability traps.
- **`task { … }` returns `Task<unit>`; upcast to `Task`** with `:> System.Threading.Tasks.Task` when a C# fixture awaits a non-generic `Task`.
- **Three F#-specific compile traps when writing a discriminated-union or `Sql.AsSql` test.** Each is a warning-as-error or an overload surprise, each costs a build cycle, and none is obvious from the surrounding code (all three hit on #5704):
  - **A single-case union's field property is not reachable from F# source.** `type UserId = UserId of int` compiles a property (`Item`) that reflection sees, but `u.Item` is `FS0039: The type 'UserId' does not define a field, constructor, or member named 'Item'`. Destructure (`let (UserId v) = u`) in F# code, or go through `FSharpType.GetUnionCases(t, true).[0].GetFields().[0]` when you need the `PropertyInfo` — which is what `FSharpSingleCaseUnionSupport` does.
  - **`FSharpType.GetUnionCases(t, true)` needs the namespace opened, or `true` binds the wrong overload.** The `bool` (`allowAccessToPrivateRepresentation`) form is an extension in `FSharpReflectionExtensions`, so a *fully-qualified* `Microsoft.FSharp.Reflection.FSharpType.GetUnionCases(t, true)` resolves against the static class instead and fails with `FS0001: expected 'BindingFlags' but here has type 'bool'`. `open Microsoft.FSharp.Reflection` and call it unqualified. Same for `FSharpValue.PreComputeUnionConstructorInfo(case, true)`.
  - **Member access on a struct a function returns is `FS0052`.** `(Sql.AsSql vopt).IsValueNone` on a `voption` trips *"The value has been copied to ensure the original is not mutated…"*, which is an error under `TreatWarningsAsErrors`. Prefer the module-function spelling — `ValueOption.isNone (Sql.AsSql vopt)` — which reaches the same translator arm without a struct temporary, rather than reaching for `#nowarn "52"`.
- **`UseFSharp()` is applied to *every* test context, not just F# tests.** The context builders in `Tests/Base/TestBase.Context.cs` call `.UseFSharp()` on every context they create (direct and LinqService), deliberately — so the whole non-F# suite exercises the F# option/union/translator registration and proves it's harmless for non-F# code. Consequence: **any change to `UseFSharp` (or the mapping schema, interceptors, or member translators it registers) has all-provider blast radius** across the entire matrix, not just `FSharpTests`. In particular it must keep the context's `ConfigurationID` stable across calls — a per-call `new` registration (e.g. `UseMemberTranslator(new …())`) gives every context a distinct id and defeats the query cache, reddening the `Query<T>.CacheMissCount` tests on every provider (#5704). See [`agents/code-reviewer.md`](../agents/code-reviewer.md) rule 1 → *ConfigurationID stability*.

## Tests that pass but catch nothing

A test that compiles and goes green is not yet a regression guard — it has to be able to go **red** on the bug it targets. The recurring ways an AI-drafted test silently guards nothing:

- **Happy-path only.** Asserts the success case and nothing else; the edge that actually broke (null, empty, overflow, negative, boundary, provider-specific fold) goes untested. A regression test must exercise the *failing* input, not a neighbouring working one.
- **Brittle string assertions.** `ShouldBe("…literal SQL…")` / `ShouldContain("…text…")` locked onto incidental wording — churn mass-fails them while the real logic regresses undetected. Assert behavior (row content, shape, count), not a string. The SQL-shape variant is covered in detail under *When a substring assertion is vacuous* below.
- **Mocking the logic away.** Stubbing the component under test so the assertion verifies the mock, not linq2db. Here that shows up as asserting against a hand-built expected object instead of round-tripping through `AssertQuery` / a real `CreateLocalTable<T>`.
- **Mirroring the implementation.** Deriving the expected value by re-running the same code path under test — or reading the current emitted SQL and pasting it back as the baseline — bakes the current behavior, bugs included, in as "correct".
- **Trivially-true assertions.** `result.ShouldNotBeNull()`, `count.ShouldBeGreaterThanOrEqualTo(0)`, asserting only that the query *ran* — green regardless of whether the targeted logic is correct. Line coverage built from assertions that can't fail is no coverage at all. Assert the specific value / shape / count the fix changes, not that *something* came back.
- **Generation-only, never executed.** A test that only asserts on `query.ToSqlQuery().Sql` (or `GetSelectQuery()`) and never calls `.ToList()` / `AssertQuery` never runs the SQL against the DB — it verifies the builder emitted a string, not that the string is valid or returns the right rows. A test must **execute against the database**; generation-only assertion is an *exception* reserved for two cases: (a) the SQL-generation API itself is the subject under test (e.g. `ToSqlQuery` behavior), or (b) the configured provider cannot execute the generated SQL (bespoke tables absent from the test schema, a dialect construct the test DB can't run) — and case (b) is acceptable **only with explicit user acceptance**, noted at the test. Never reach for generation-only assertion just to skip DB/table setup. (When the tables are only test-local, `CreateLocalTable<T>` makes execution self-contained — see the ClickHouse note under *Cross-provider gotchas*.)

- **A tie-break key that agrees with the key under test.** Specific to ordering-sensitive folds (`OVER (ORDER BY <predicate>)`, `PARTITION BY <predicate>`, `WITHIN GROUP`): a value assertion only discriminates if the *secondary* sort key **disagrees** with the folded one. Seed the data so the row the predicate singles out is the one the tie-break would have ordered differently — otherwise a fold that is dropped entirely, or collapsed to a constant, produces the same numbers as a correct fold and the test passes against the bug. Enumerate the failure modes explicitly (correct / inverted / constant / one-branch `CASE WHEN p THEN 1 END` yielding NULL) and check the expected values differ under each. (Surfaced on #5725: the first `Issue5123Test` draft matched the join on the *highest* `Id`, so correct folding and a dropped key both gave `1/2/3`; reseeding the match onto the lowest `Id` made correct `3/1/2` while both failure modes stayed `1/2/3`. A `COUNT` assertion is the mirror case — `COUNT` is value-blind by construction, so it can only ever pin nullness-invariance, never a value error.)

- **A parameter NUnit cannot supply values for, which produces no test cases at all.** The worst version of "catches nothing": the method never runs anywhere, on any provider, and is absent from discovery entirely rather than showing up skipped. A `[Test]` whose parameters include a plain `bool` (or an enum) with no `[Values]` / `[ValueSource]` alongside a data-source parameter is the shape — NUnit does **not** auto-fill it here, and nothing reports the method as unrunnable. Any `[ActiveIssue]` gate on such a method is dead with it, so the gate also never reports. The cheap check is `--list-tests --provider <name>`: a method absent from that listing while its siblings in the same fixture appear is not covered, whatever the suite's pass count says. (Surfaced on #5882: `CteTests.SelectQueryTest` had `bool inlineParams` with no source and had never run; adding `[Values]` cost nothing — 24 of 28 cases passed — and exposed a real Oracle 11 failure the dead gate had been "covering". Verified by probe *after* the attribute cutover, so it is NUnit's behaviour and not an artefact of the old attribute acting as the `ITestBuilder`.)

- **A scope invariant tested on a hand-picked subset.** "Nothing X happens while Y" (nothing loads while impersonating, nothing allocates inside the lock, no query runs before validation) is a claim over a *set*, and a test matrix built from the cases the author was thinking about passes while the claim fails on the rest. Expand the set into its axes and give each element a case: for a provider-facing invariant, that is every bundled client × each phase (connect fails, connect succeeds, a typed-value read, which needs a reachable server) × each provider origin (bundled, `--provider-location`). Beside each control, record the mutation that reddens it (remove the mechanism, move the work inside the scope) and run that mutation in the fixture's real order. (#5995: the CLI's `NothingIsLoadedWhileImpersonating` covered 3 of 15 bundled clients, all against refused TCP connections. Oracle's failure path, a `geography` read and a DB2 `--provider-location` client each loaded a native library inside the session, and three in-process controls stayed green under the mutation that should have reddened them.)

- **Shared fixture data that never reaches the path.** The shared tables (`Types` / `LinqDataTypes`, `Person`, `Parent`/`Child`) have fixed column types and fixed values — `MoneyValue` is two-decimal on every row. A test whose path depends on how an argument relates to the *data* (rounding precision vs scale, a length vs the stored string, a range boundary) must state which rows reach the path, or seed its own rows with `CreateLocalTable` and declared `Precision`/`Scale`. (#5943: `Round16` rounded `MoneyValue` to `p.ID % 2 + 2` digits — always ≥ the scale of 2 — so every row was a no-op and the runtime scaling path never ran; `Round17`/`Round18` on the same PR seed their own `Decimal(p,s)` tables and do reach theirs.)

- **A format of exactly `"{0}"` skips the format machinery.** `BasicSqlBuilder` renders a `SqlExpression` / `SqlFragment` whose `Expr` is literally `"{0}"` as `Parameters[0]` and never calls `BuildFormatValues`, so the other arguments are never built. A test about argument rendering — which arguments become parameters, how they are formatted — must use a non-trivial format such as `"({0})"`. (#6008: `Sql.Expr<int>(Create("{0}", 1, 99))` passed with and without the fix; `"({0})"` went red under the mutation.)

Before reporting a test written, state in one line **which input makes it go red** and confirm it would have failed against the pre-fix code. If you can't name that input, it isn't a guard yet. Mutation-score tooling is out of scope; the red→green demonstration required by `acting-on-findings.md` → *Red test first for a review-finding fix* is the bar.

**For a fix that changes a *shared* template / code path serving many providers, run the pre-fix RED on *each* targeted provider — don't extrapolate red→green from a sibling that shares the path.** A regression test enabled for N providers only guards them if each one actually *routes through* the changed code; a provider may hit a different `Configuration`-specific override (or a default with no builder) so the same source change lands as different — or no — SQL. Reasoning "Oracle shares DuckDB's default template, so DuckDB-green implies Oracle-green" skips exactly the question the RED run answers: does this provider emit the broken form pre-fix? Demonstrate it. (Surfaced on #5644: the `Lead(expr, nulls)` IGNORE-NULLS fix touched the shared default template + added a PG19 variant; RED was confirmed independently on DuckDB, PostgreSQL 19, *and* Oracle before trusting the fix, rather than inferring Oracle from DuckDB's shared path.)

## Proposed: property-based / invariant testing for the SQL pipeline (not yet wired in)

The current suite is example-based: a human (or AI) names specific inputs and asserts specific outputs. **Property-based testing** inverts that — you state an *invariant* that must hold for *all* inputs, and a generator throws hundreds of randomized cases at it to find the one that breaks it. It's the automated form of "name the input that makes it go red" above: instead of guessing the edge case, you let the generator find it. This is **a proposal, not built** — recorded here so the idea isn't lost and so a future effort starts from a candidate list rather than a blank page. linq2db's SQL-generating core is unusually well-suited to it because several pipeline invariants are exact, deterministic, and provider-independent:

- **AST clone round-trip** — for any SQL AST node, `clone(node)` must be `Equals` to `node` *and* hash equal. Directly exercises the equality/hash/clone fan-out `code-reviewer` rule 1 polices by hand; a generator over node shapes would surface a dropped field automatically.
- **Visitor identity** — running an identity `QueryElementVisitor` over a tree returns a structurally-equal tree (no field silently neutralized to `None` / `null` / `0` — the same drop class rule 1's "new field propagation" sub-bullet watches for).
- **LinqService serialization round-trip** — `deserialize(serialize(tree))` must equal `tree` for any tree. The remote path's correctness is exactly this property; today it's only spot-checked per construct.
- **Optimizer idempotence** — optimizing an already-optimized tree is a fixed point (`optimize(optimize(x)) == optimize(x)`). This is the very invariant whose violation produces the infinite-recursion hangs in *Diagnosing hung test runs* below — a property test would catch a non-idempotent rewrite before it ships.
- **Type-mapping symmetry** — `DataType` ↔ provider `DbType` / CLR-type mapping conversions round-trip where the mapping is defined as bijective.

Framework note: there is **no property-testing dependency in the repo today**. Options if pursued: a generator library (CsCheck — minimal-dependency, .NET-native shrinking; or FsCheck), or hand-rolled randomized generators feeding ordinary NUnit `[Test]` methods with a logged seed for reproduction. Start with **one** invariant (AST clone round-trip is the highest-leverage and needs no DB) as a proof-of-concept before committing to a framework — the package choice and the shrinking/seed-reproduction story are the real decisions, and they belong to whoever scopes the effort, not to a doc.

## Cross-provider gotchas for new tests

### YDB requires a primary key on every table

YDB rejects `CREATE TABLE` without a primary key, so `db.CreateLocalTable<T>()` of a keyless type fails at setup with `Primary key is required for ydb tables` (wrapped in a `Pre type annotation` error). It's a test-data fix, not a provider change.

**It is on CI** — the GitHub Actions `Lin u_YdbSybase` leg runs it, so a keyless fixture in a `[DataSources]` test fails there and not only locally. The error arrives as a `YdbException`/`GenericError` naming neither the table nor the column, and over `LinqService` it is wrapped in a `Grpc.Core.RpcException`, so a fixture problem presents as the *feature* not working on YDB. Read the message before assuming the query is at fault. (#5708: 24 pivot/unpivot tests × direct and `LinqService` failed this way, none of them for a pivot reason.)

Two details the obvious fix gets wrong:

- **Scope the key to YDB** — `[PrimaryKey(Configuration = ProviderName.Ydb)]`, or `[PrimaryKey(ProviderName.Ydb, n)]` for a composite, per the `Tests/Model/ParentChild.cs:23` precedent. An unconditional `[PrimaryKey]` changes the DDL on *every* provider, and a `string` column in a key is rejected by several of them once it maps to a long-text type.
- **YDB enforces PK uniqueness on insert**, so a natural key is not always available. Where fixture rows are deliberately non-unique — duplicate rows that make a `Distinct()` count differ from a row count, several rows per group so `AVG`/`MIN`/`MAX` differ from `SUM` — a natural key silently *merges* rows and voids exactly the discrimination the test was built for. Add a surrogate `Id` instead.

### Access has no 64-bit integer column

Access (Jet and ACE, OleDb and ODBC) has no 64-bit integer type, so a `CreateLocalTable` whose class has a `long` / `ulong` column fails with `Syntax error in field definition` on all four Access legs, direct and remote. Keep `Int64` cells in a sibling test with `[DataSources(TestProvName.AllAccess)]` and that measured failure on the line above, so the rest of the test still runs on Access (the repo's existing `Int64` tests exclude `AllAccess` the same way). (#5943: 16 Access cases on GitHub run 39446372309.)

### ClickHouse and YDB don't report rows affected — assert the stored value

An entity `Update` returns 0 on ClickHouse and -1 on YDB, so `.ShouldBe(1)` on the count fails there for a correct query. When the test is about *which* row changed, drop the count and assert the stored value afterwards — that is the outcome a wrong key or column set breaks anyway. Keep a count assertion only where the count is the subject, behind `context.IsAnyOf(TestProvName.AllClickHouse) ? 0 : 1` (`Issue1925Tests`). (#6145: `EntityUpdateFollowsHandleSchema`, 8 ClickHouse/YDB cases.)

### `CreateTempTable(…, setTable)` defaults to a temporary table, which YDB refuses

The `setTable` overloads default `tableOptions` to `TableOptions.IsTemporary`, and YDB fails with *"Creating temporary table is not supported."* When the test needs the overload for something other than temporariness (its mapping swap, its column set), pass `tableOptions: TableOptions.NotSet` so the test runs on YDB instead of gating it. (#6145: `EntityUpdateFollowsHandleSchemaUnderTempTable`.)

### Firebird types a multi-row insert's literal column from the first row

`CreateLocalTable(data)` on Firebird writes the rows as one multi-row insert of literals, and the column's type comes from the first row's literal: `1.23456789` makes it `NUMERIC(9,8)`, so a later `123456789.25` fails the whole insert with `numeric value is out of range` before the query under test runs. The direct leg fails and the LinqService leg can pass, which reads like a remote divergence. Keep each column's rows in one literal shape (same integer and fractional digit counts), or put the widest value first. (#5943: `ScalarThroughText` and a probe table, both direct-only on Firebird 5.)

### YDB: a failing query under `CreateLocalTable` reports `Connection is closed`

On YDB a reader failure closes the connection, so the `using var t = db.CreateLocalTable(...)` dispose that follows — `TempTable.Dispose` → `DropTable` — throws `InvalidOperationException : Connection is closed`, and that is the exception the direct `YDB` context reports. The real error is gone from the failure message. Read the `.LinqService` leg, which surfaces it (e.g. `Value does not fit into decimal`), or the log's `Rows Count:` line, which shows how far the reader got. (#5943: `Round20("YDB")` reported `Connection is closed` after 4 of 6 rows; `Round20("YDB.LinqService")` showed the decimal overflow.)

### A runtime value set read from an unordered query moves the generated SQL

A test that feeds a **runtime** set into the query it asserts — a pivot's value list, a dynamic column set — and reads that set from a query with no `ORDER BY` has made its *emitted SQL* depend on the row order the provider happened to return. The assertions still pass, because they are keyed by name; the recorded baseline does not, and the test fails in `TearDown` with *"Baselines for remote context doesn't match direct access baselines"*. That message points at the remote path, which is innocent — this is the nondeterministic-input-order case of [*The shape of the `.sql` vs `.sql.other` diff names the cause*](#the-shape-of-the-sql-vs-sqlother-diff-names-the-cause), reached through the projection rather than through a `UNION ALL`. Order the set (`.Distinct().OrderBy(x => x)`); it stays a query and still cannot fold to a constant. (#5708: `PivotsRuntimeValuesIntoPivotRow` passed CI on every provider and failed locally on `DuckDB.LinqService`, the two baselines differing only in whether the `2000` or the `2010` `CASE` came first.)

### `[ThrowsForProvider]` covers the `.LinqService` context, and tolerates the remote wrapper

`ThrowsForProviderAttribute` expands each provider it names to `<name>` **and** `<name>.LinqService`, so one attribute covers both contexts. The match is deliberately asymmetric (`ThrowsWhenAttribute.ExecuteInner`): the direct case requires the result message to **start with** the expected exception's full name, the remote case only to **contain** it. That is what makes the attribute usable for a failure the remote path re-wraps — an `InvalidOperationException` arriving as `FaultException : LinqToDBConvertException … ---> System.InvalidOperationException` still matches. `ErrorMessage` is a `Contains` on the message, or a pattern when it carries `{0}` placeholders, so an `ErrorHelper` constant can be named rather than copied with its arguments filled in.

### A provider refusal under a filtered `AsSubQuery()` loses its message — exclude, don't gate

When the refused construct sits in a projection that is then filtered through `AsSubQuery()` (`windowed.Count(r => r.Lag < x)`), the exception names only the comparison: `The LINQ expression 'x.Lag < …' could not be converted to SQL.` The provider's reason (`Error_WindowFunction_LeadLagDefault`, `Error_WindowFunction_FirstLastValue`, …) appears under `Additional details` only for the plain projection. So a `[ThrowsForProvider(…, ErrorMessage = ErrorHelper.…)]` copied from a sibling test cannot match. Gating on the generic text instead would hold for any translation failure. For this shape, exclude the provider from the data source with a reason line naming the sibling test that asserts the throw. The cause is filed as [#6080](https://github.com/linq2db/linq2db/issues/6080). (#5959 round 6: the copied `LeadLagDefault` gate failed on YDB for the wrong reason. `LagOverASecondPrecisionColumnComparedWithSubSecondLiteral` now excludes YDB / MariaDB / SQL Server 2008-, and `LagWithDefaultOverAConvertedColumn` asserts the throw.)

### An exception pin is only as stable as the failure it names

A `[ThrowsForProvider]` pin asserts an exception **type** and **message**, so a driver fault that varies produces a test that goes red on a run nobody changed anything for. Observing the failure once is not enough to pin it — and the **second** wrong pin is the signal to stop pinning, not to write a third: exclude the provider from that test, file the defect, and cite the issue in the test comment. Splitting the test first keeps the cases that *do* work covered on that provider rather than losing them to a whole-test gate.

Three independent reasons the same fault changes shape:

- **The driver itself.** On [#5954](https://github.com/linq2db/linq2db/issues/5954), `System.Data.OleDb`'s `DbBuffer.ReadNumeric` raised `InvalidCastException` *"The numerical value is too large to fit into a 96 bit decimal"* on one CI run and `ArgumentException` out of `Decimal.SetBits` on the next, for **byte-identical generated SQL** — confirmed by diffing the two legs' logs, which is also how you rule out a change of your own as the cause.
- **linq2db's mapper fallback.** `QueryRunner.cs:98` catches `FormatException`, `InvalidCastException`, `LinqToDBConvertException` and `*NullValueException` and retries in slow mode; anything else propagates raw. So a caught type reaches the test wrapped in `LinqToDBConvertException` (*"Mapping of column '…' value failed"*) via `ColumnReader.GetValue`, while an uncaught one arrives bare from the compiled row mapper — the same defect matching or missing the pin depending on which it was. The trace line *"Mapper has switched to slow mode"* in the run log tells you which path a given failure took.
- **The build configuration.** Shouldly renders the asserted expression into its message from debug information, and CI builds with `-c Azure`, which sets `DebugSymbols=false` (`Tests/Directory.Build.props`). So the same assertion reads `descriptor.Columns…SequenceName should not be null` locally and `null should not be null` on CI. Pin on a custom assertion message (`ShouldNotBeNull("SequenceName")`) or on exception / compiler text, never on Shouldly's rendering of the expression. (#6037: the #3749 pin was green locally and red on both `Scaffold tests` legs.)

### `Except` / `Intersect` in a `[DataSources]` test need the YDB correlated-subquery gate

A distinct set operation only reaches SQL when the provider sets `IsDistinctSetOperationsSupported` (`ExceptAll` / `IntersectAll` need `IsAllSetOperationsSupported`). Where the flag is false — YDB, Sybase, Access, SqlCe, Firebird, MySQL ≤ 5.7 — `SetOperationContext.Emulate` rewrites the operation as `WHERE NOT EXISTS (<correlated subquery>)`. YDB rejects correlated subqueries, so the query fails to **build**, with `ErrorHelper.Error_Correlated_Subqueries` (*"Provider does not support correlated subqueries."*) — not at execution, and not as a wrong result.

So a new `[DataSources]` test using `Except` / `ExceptAll` / `Intersect` / `IntersectAll` needs `[ThrowsRequiresCorrelatedSubquery(simple: true)]`, the same gate `SetOperatorTests.TestExcept` / `TestExceptAll` already carry. `simple: true` scopes the expectation to YDB alone: ClickHouse sets `IsAllSetOperationsSupported = true` and emits native `EXCEPT DISTINCT`, so it never emulates and must not be listed. The attribute asserts both the exception type and the message, so a gated test cannot pass vacuously, and providers outside its list still run the body's own assertions.

**Sybase is the control that shows the emulation itself isn't the problem** — same false flag, so it emulates identically, but it *does* support correlated subqueries and passes. A set-operation test failing on YDB alone is this gate missing, not a defect in the operation. (Surfaced on #5833: `ExceptBranchProjectingDerivedType` reached CI ungated and failed the YDB leg on both the direct and `LinqService` contexts, while Sybase passed in the same leg.)

### An apply-join test gates ClickHouse and YDB as correlated subqueries, not outer joins

A correlated `SelectMany` source becomes an apply join, and `[ThrowsRequiredOuterJoins]` lists the providers without one. ClickHouse and YDB never reach that check: the correlation itself is rejected first, with `ErrorHelper.Error_Correlated_Subqueries`. Leave them out of the outer-join list and add `[ThrowsRequiresCorrelatedSubquery]` instead. Use `simple: true` (YDB only) only for a shape ClickHouse has been seen to run — an `Any(…)` correlated sub-query passed there, the `SelectMany` apply did not. (#5708: `UnpivotOverACorrelatedSource` listed both under the outer-join gate and cost a CI round.)

### A date range that straddles a daylight-saving transition makes an exact span assertion environment-dependent

A date/time column that stores a wall-clock reading the **server** resolves in its own zone — ClickHouse
`DateTime` / `DateTime64` / `Date32`, and any other provider whose timestamp type carries a session or server
timezone — makes the *absolute* distance between two stored readings depend on the zone the server runs in. Pick
two dates either side of a daylight-saving transition and the span is an hour shorter or longer than the CLR
computes from the same two `DateTime` values, so an exact `.Ticks` / `.TotalDays` / shifted-date expectation is
right on a UTC container and wrong on a server in an observing zone.

This is the worst shape of flake: it is green wherever it was written, it never fails twice in the same place,
and nothing in the test says it depends on the host. **Choose the range, don't discover it** — a window inside
one transition period is free to pick, and June–August is clear in both hemispheres (northern transitions fall
in March and October/November, southern in April and September/October). Where a fixture already owns a shared
origin constant, check that `origin + span` lands in the same window too, not just the two endpoints.

If a range genuinely has to cross one, derive the expectation from the server rather than the CLR, and say in
the test why.

(Surfaced on [#5959](https://github.com/linq2db/linq2db/pull/5959): three new tests spanned 2026-03-08, a US DST
transition, over `DataType.DateTime` and `DataType.Date32` columns. All green on the local UTC container; the
diff review caught them before CI did.)

### ClickHouse: `CreateLocalTable` needs no engine; ASOF runs on Memory tables

ClickHouse `CREATE TABLE` requires an `ENGINE`, but you don't specify one for `db.CreateLocalTable<T>()` — the builder auto-emits `ENGINE = MergeTree() ORDER BY <pk>` when the mapping has a `[PrimaryKey]`, else `ENGINE = Memory()` (`ClickHouseSqlBuilder.BuildEndCreateTableStatement`; there's a `// TODO` for an engine-config API, so custom engines still need raw SQL). So a keyless test type lands on `Memory()`, which is fine for query tests. `LEFT ASOF JOIN` and `GLOBAL LEFT ASOF JOIN` **execute** against Memory-engine local tables on a single-node container, and `CreateLocalTable` works over the LinqService remote context — so ASOF hint tests can (and should) execute rather than assert on `ToSqlQuery().Sql`. Note bespoke test tables (e.g. `AsofTrade`/`AsofQuote`) are **not** in the ClickHouse test schema (unlike the T4-scaffolded `ReplacingMergeTreeTable`), which is why they need `CreateLocalTable` rather than `GetTable<T>`.

### Affected-rows assertions need `SupportsRowcount`

`.Update()` / `.Insert()` / `.Delete()` return an affected-row count, but **ClickHouse Driver** and **YDB** return `0` for every UPDATE regardless of how many rows actually changed. A bare `affected.ShouldBe(1)` in a `[DataSources]` test breaks on those providers.

Guard the assertion with `context.SupportsRowcount()` (defined in `Tests/Base/ProviderNameHelpers.cs`):

```csharp
var affected = db.GetTable<Foo>()
    .Where(x => x.Id == 1)
    .Set(x => x.Test1, x => !x.Test2)
    .Update();

if (context.SupportsRowcount())
    affected.ShouldBe(1);

// The substantive assertions (row content after update) run unconditionally.
```

Pattern used 10+ times in `Tests/Linq/Update/InsertTests.cs`.

### `[Sql.Expression]` with `bool` return type needs `IsPredicate = true`

When the template emits a SQL predicate (`({0} > 0)`, `{0} IS NULL`, `{0} = {1}`, …) and the CLR method returns `bool`, set `IsPredicate = true`. Otherwise the translator wraps the predicate in a bool→bit coercion (`IIF((pred) = 1, …)`) that emits invalid SQL on **SQL Server**, **Oracle**, **Sybase**, **SAP HANA**, **Access**, **ClickHouse**, and **Firebird 2.5**. PostgreSQL and MySQL/MariaDB tolerate the wrap because they have native `boolean`.

```csharp
[Sql.Expression("({0} > 0)", ServerSideOnly = true, IsPredicate = true)]
static bool IsPositive(int x) => throw new InvalidOperationException();
```

Other examples in code: `Tests/Linq/Linq/BooleanTests.cs:726`, `Tests/Linq/Linq/OperatorsTests.cs:128-129`, `Tests/Linq/DataProvider/PostgreSQLTests.cs:2799`.

### Column nullability is not inferred from C# NRT

linq2db does **not** derive column nullability from C# nullable-reference annotations: an un-annotated `[Column] string Foo` (non-nullable CLR type) still maps to a **nullable** column, so `CanBeNullable(NullabilityContext)` returns `true` for it at SQL-build time. A test that needs a provably non-null column — e.g. asserting a provider omits a `… IS NULL` guard — must say so explicitly with `[Column(CanBeNull = false)]` or FluentMapping `.IsNullable(false)`; the CLR type alone won't make the column non-null.

```csharp
sealed class Entity
{
    [PrimaryKey]                public int     Id  { get; set; }
    [Column(CanBeNull = false)] public string  Req { get; set; } = ""; // NOT NULL column
    [Column(CanBeNull = true)]  public string? Opt { get; set; }        // nullable column
}
```

### A `static readonly` derived from a field in another partial-class file can read its default

Fixtures are split across partial-class files (`IntervalTranslationTests.*.cs`, `DateTimeFunctionsTests` and friends), and C# gives static field initializers in *different* files of one partial class no defined order. `static readonly DateTime B = A.AddMilliseconds(500);` with `A` declared in a sibling file can run first and read `default(DateTime)`: the query renders `0001-01-01 00:00:00.5` and the test fails for a reason unrelated to what it pins. Spell the value out, or derive it in the file that declares `A`. (#5959)

### Verifying server-side function translations

When a test asserts a method translates to a server-side function, wrap the call in `Sql.AsSql(...)` (e.g. `select Sql.AsSql(Sql.NewGuid7())`). Without it, a provider that *lacks* the translation can silently client-evaluate the method and the test still passes — a false green that hides a missing translation. The mirror is a false red: an argument the server accepts but the CLR body rejects (e.g. `Sql.Round(x, -1)` — `Math.Round` throws on a negative precision) fails client-side and hides the server-side behaviour under test. `Sql.AsSql` is needed there too. (#5943)

The same false green hides any projection member whose translation is the point: a projection falls back to the client, so a row comparison cannot tell an `IN` list from a client calculation. Assert the SQL — and **per member**, not once per query: a single `ShouldContain("COALESCE")` over three members stays green when one of them falls back, because the other two still supply the token. Count the occurrences, or give each spelling its own query. (#5983: `AsQueryable().Contains` regressed to the client in a projection and to a translation error in a `WHERE`; the combined check could see neither.)

A non-`ServerSideOnly` `Sql.*` method with a CLR body (e.g. `Sql.NewGuid` / `Sql.NewGuid7`) falls back to client-side evaluation wherever no server translation is registered. So one `[DataSources]` test covers the whole matrix: providers with the translation exercise the SQL function, the rest the client fallback. Assert the observable property (e.g. the GUID version nibble), and wrap in `DisableBaseline` when the generated value is non-deterministic (the value, not the SQL shape, varies per run). Don't infer "can't client-evaluate" from another test's provider-exclusion list — those exclusions are often roundtrip-specific, not translation-capability statements.

### A new member-translator registration owes a `PreferClientCalculation` decision and a batched test

Every `Registration.RegisterMethod` in a `*MemberTranslatorBase` is implicitly a decision about
`LinqOptions.PreferClientCalculation`: a registration inside a `TranslationRegistration.OptionalScope()` declines when
the caller prefers client calculation, so the expression is computed client-side; one outside stays server-side always.
Adding a registration without choosing picks "mandatory" silently, which is safe but leaves the option under-delivering.

**A registration may be optional only when re-evaluating it on the client, over the materialized values of its
arguments, gives the same answer.** It must stay mandatory when it is SQL-only (aggregates, window functions, anything
whose delegate can reach `AggregateFunctionBuilder`), marks intent (`Sql.*`), is non-deterministic or ambient
(`NewGuid`, current timestamp), carries nullability semantics (`Sql.ToNullable` / `Sql.AsNullable`), or has no client
body / throws unconditionally (`SqlMethods.Like`, `string.CompareTo(object)`).

**Test it in a batch, not one test per member.** `PreferClientCalculationTests` projects many members in a *single*
projection and asserts `Select.Columns.All(c => c.Expression is SqlField).ShouldBe(preferClient)` — which fails if *any*
member in the batch stayed server-side, so a new registration joins an existing test by adding one line to its
projection rather than adding a test. Keep one batch per translator family, plus a mirrored batch of the members that
must stay server-side. Reviewing a PR that adds a translator: ask which batch the new member was added to, and if the
answer is "neither", the optional-vs-mandatory decision was never made.

The blanket safety net is a full `Tests.Linq` run with the option forced on globally — the only thing covering the
registrations no batch names. Treat its failures as correctness findings; SQL-baseline diffs from such a run are
expected noise and must not be committed.

### Asserting on a parameter's declared type — `LastQuery` does not carry it

`DataConnection.LastQuery` holds the **command text alone**. The `DECLARE @p <Type>` block that precedes it — the only place a parameter's *declared* type is visible — belongs to the captured trace, not to the command, so an assertion on `LastQuery` for a `DECLARE` line can never match and fails with `But was: "SELECT …"`. Use `GetCurrentBaselines()` (`Tests/Base/TestBase.Utils.cs`), which exposes the accumulated trace and is already the accessor for ~70 assertion sites. `LastQuery` is the right tool for the statement itself — the shape of the SQL, an alias, a hint — and the wrong one for anything the provider renders *around* it. `GetCurrentBaselines()` also holds the **server-side** SQL of a `.LinqService` case (the server's trace is routed to the test's context) and needs no `BaselinesPath`; remote contexts have no `LastQuery`, so it is the accessor for asserting SQL on both the direct and the remote case of a `[DataSources]` test. (#6055)

Worth an assertion rather than leaving it to the baseline: a parameter type name can vary with the **runtime**, not just the provider (`System.Data.SqlDbType` gained `Json` only in .NET 9, so `(SqlDbType)35` renders as a bare `35` on net462/net8). A divergence like that is invisible on the PR pipeline when the newest TFM is the only one running the main suite, and surfaces as an unexplained baseline diff after a release instead — see [`baselines-repo-layout.md`](baselines-repo-layout.md) → *A baseline file's path carries the provider and nothing else*. (Surfaced on [#5917](https://github.com/linq2db/linq2db/pull/5917).)

### Excluding a provider from one *combination*, not from the whole test

`[DataSources(TestProvName.AllX)]` removes the provider from **every** case the method generates, including each arm of a `[Values]` parameter it is crossed with — the filter runs before the parameter exists, so the attribute cannot express "this provider, only on that arm". Reaching for it when a single arm is unsupported silently throws away the coverage the other arms still had.

Guard the combination inside the test instead:

```cs
if (strategy == EagerLoadingStrategy.KeyedQuery && context.IsAnyOf(TestProvName.AllAccess))
	Assert.Ignore("KeyedQuery emits its key set as a FROM-less UNION ALL derived table, which Access rejects.");
```

Two properties of `IsAnyOf` (`Tests/Base/ProviderNameHelpers.cs`) make the one-liner cover a whole family: it calls `StripRemote()` first, so a `.LinqService` context matches its base provider name, and it splits comma-joined constants, so `TestProvName.AllAccess` covers all four Jet/Ace × OleDb/Odbc configs.

Precedent: `Tests/Linq/Linq/StringConcatTests.cs` does this in five places for Sybase ASE's empty-string padding, which diverges only when a `[Values] bool …Nullable` arm is true — a whole-test `[DataSources(TestProvName.AllSybase)]` would have dropped Sybase from the non-nullable arms as well.

The cost is that the skipped arm now hides in the run's `skipped` count rather than simply not existing, so cross-check `summary.skipped` after any run you cite as verification — see *A skipped test is "not tested"* above. (#5938: two new eager-load tests failed on all four Access configs under `KeyedQuery` only, while the `Default` arm passed and was worth keeping.)

**`[ActiveIssue]` has the same blind spot.** It selects by provider, by direct vs `LinqService`, and by platform (`ActiveIssueAttribute.AppliesTo`), never by a `[Values]` value. When a known issue fails only one value, a gate on the whole method reports every other value as `Test passed but is marked with [ActiveIssue]`. Split the failing value into its own method and gate that method. Don't use `Assert.Ignore` here: it hides a known failure that the gate would otherwise check. (#5972: an inlined `ulong` failed only with `InlineParameters = true`, so `Issue5972_UInt64` and `Issue5972_UInt64Parameter` became separate methods.)

**A tracked provider failure on one arm: `[ThrowsForProvider]` with `AlsoWhenParameter` / `AlsoWhenValue`.** Unlike `[ActiveIssue]` it does select by a `[Values]` value, and unlike `Assert.Ignore` it keeps checking the failure. It also matches the `RpcException`-wrapped error on `.LinqService`. Precedent: `EagerLoadingStrategyKeyedQueryTests.Select_KeyedQuery_DetailTakeIsPerParent`, `Issue5935Tests` (#5940 on SAP HANA).

A gate whose `ErrorMessage` is the direct/remote baseline check (`Baselines for remote context doesn't match direct access baselines`) fires only when `BaselinesPath` is set. On a run without baselines the test passes and the gate reports "passed but marked". So a local "passed but marked" for such a gate is no evidence to delete it — only a run with baselines enabled (CI `test-all`) exercises the check. (#6015: the PostgreSQL remote gate on `Issue5972_UInt64` came off as "now passes" and failed all 13 `PostgreSQL.*.LinqService` configs on CI.)

### Test-proofing a gated provider capability

To empirically determine whether a database actually supports a feature gated off by a capability flag (`Is…Supported` on a translator, a `SqlProviderFlags` bool, etc.) — rather than trusting docs:

1. **Flip the gate** to `true` in the provider's translator/builder.
2. **Enable only that provider** in `UserDataProviders.json` and **disable providers whose containers are down** — otherwise their connection-timeouts dominate the run and bury the signal (start the container the probe needs; a stopped container makes the run crawl).
3. **Run the gated tests** for that feature. A test whose `[ThrowsForProvider]` now reports *"Expected a `LinqToDBException` … but found `''`"* means the DB **executed** the SQL → **supported**. A native DB exception (e.g. `HanaException`, `DB2Exception`, `… does not exist`) means **unsupported**. (The throw-expectation "failing" is the signal — read the failure mode, not the pass/fail.)
4. **Revert the experimental flip** (`git checkout HEAD -- <translator>`); proofing edits are throwaway.

To then *enable* the capability for real, mirror the per-test `[ThrowsForProvider]` gating of a **sibling provider with the same capability profile** (e.g. YDB was the precedent for SAP HANA ROWS-frame support — both ROWS-only), and expect baseline regeneration for the now-executing tests. Watch for coarse flags that can't express asymmetric support: `WindowFunctionsMemberTranslator`'s `IsVarianceSupported` gates `STDDEV_POP/SAMP` + `VAR_POP/SAMP` as one group and `IsVarianceBareSupported` gates bare `STDDEV` + `VARIANCE` together, yet SAP HANA has `VAR_POP/SAMP` + bare `STDDEV` without bare `VARIANCE`, Informix the reverse, and SQL Server needs per-name mapping (`STDEV`/`VAR`/`STDEVP`/`VARP`) — enabling those needs finer flags first. This is the technique used to find the PR #5468 SAP HANA / Informix statistical-window gaps.

### Testing query cache HIT / MISS behaviour

Three idioms, each proves something different. Full mechanics in [`query-cache-mechanics.md`](query-cache-mechanics.md).

- **Same query, re-execute → HIT.** Build `query` once, call `.ToArray()` twice, assert the second call doesn't bump `GetCacheMissCount()`. Mark the test `[QueryCacheTest]`, like every idiom here: the counter is per entity type, so a concurrent test on the same type — including this test's own case for another provider — bumps it between the two captures ([`query-cache-mechanics.md`](query-cache-mechanics.md) → *A cache-dependent test needs `[QueryCacheTest]`*; #6103: 4 → 5 on SqlServer.2022 in a parallel fixture run, green alone). Catches the most common bug: `MarkAsNonParameter`'s stored value type disagreeing with the accessor expression's runtime type (the `value1.Equals(value2)` compare returns false for `"abc".Equals(['a','b','c'])` etc.).

- **Local function with captured-value parameter → HIT across invocations.** Build the query inside a local helper that takes the cache-keyed value as a parameter; call the helper twice with equivalent values; assert miss count unchanged. Use this when both values have to exist in the *same* test case, because different C# local variables become different closure-display-class fields with different `MemberInfo` — they don't share cache shape even when content is identical. The local-function param shape collapses both calls onto the same display class with the same field, so structural compare matches and the value-compare layer runs.

- **Mutate captured array → MISS on content change.** Hold a reference to a captured array, run `query.ToArray()`, mutate the array in place, run `query.ToArray()` again. With a content-aware cache key the second invocation registers as a miss (counter goes up). Catches stale-SQL bugs where mutation isn't reflected in the cache.

- **`[Values(1, 2)] int iteration` → HIT across test *cases*.** The repo's most-used shape, and the one to reach for when each execution needs its own fresh value (a re-created collection, a different parameter). Add `[Values(1, 2)] int iteration` to the signature, build the value and the query inside the method, capture `GetCacheMissCount()`, execute, then assert the count is unchanged **only when `iteration == 2`** — case 1 warms the cache, case 2 asserts the hit. It works because `[QueryCacheTest]` deliberately does **not** clear the cache: it lifts `QueryCache.Default.MaxEntriesOverride` for the test's duration and restores it afterwards, precisely so these entries survive between cases (NUnit fires `ITestAction` per test *case*, so a clear would land between them — see the attribute's own remarks). It also derives from `ParallelizableAttribute(ParallelScope.None)`, so nothing runs concurrently to disturb the counter. In use across ~35 fixtures — `PostgreSQLArrayTests.ArrayParameterCacheTest_*`, `AnalyticTests`, `Issue5302Tests`, `Issue5769Tests`, `MappingTests`.

`GetCacheMissCount()` reads `Query<T>.CacheMissCount` — a static per-entity-type counter shared across the AppDomain. Within a single test method, sequential invocations are deterministic; the assertion is always "delta from a captured baseline", never "absolute count".

**A caching fix's test asserts reuse directly — never only the SQL text.** A rebuilt query emits the same `LastQuery` as a reused one, so `db.LastQuery.ShouldBe(sql)` across two argument values cannot go red for a "rebuilds per value" regression. For `IQueryable` queries, assert a `GetCacheMissCount()` delta. `CompiledQuery` builds bypass `Query<T>.CacheMissCount` entirely, because `CompiledTable<T>` keeps its own cache. There, assert that the two invocations return the same built query: `query2.GetCompiledQueryInfo().ShouldBeSameAs(query1.GetCompiledQueryInfo())`. The `QueryUtils` helper reads the compiled table's internal `Info` by reflection, since nothing public exposes it. (#6003: three compiled `FromSql` tests asserted `LastQuery` equality and stayed green while each new argument value triggered a full rebuild. The `BuildsOnce` tests caught it.) **Executing one `IQueryable` instance twice is not a reuse test:** after the first execution `ExpressionQuery` returns its memoised `Info`, so a second-execution `ShouldBeSameAs` cannot fail. A single instance can only assert that `Info` was memoised at all — `GetCompiledQueryInfo()` throws on null. (#6003 round 3: `FromSql_RawSqlString_TopLevel_QueryReused`.)

### Testing a build step against a schema-snapshot divergence

A table handle keeps the mapping schema it was created under; `UseMappingSchema` / `AddMappingSchema`, and `CreateTempTable(..., setTable)` while it lives, replace the data context's schema. A test that a build step reads the handle's schema rather than the live one needs an input where the two **disagree on the facet that read consumes**:

- **Pick the facet, not a rename.** A column rename separates only a site that emits names (`FromSql`'s raw table). Most reads decide another facet: the column set, primary key or skip-on-insert (entity DML, Merge default insert); association presence or an inheritance mapping; a discriminator code's conversion; a parameter's conversion. Write each cell against the facet its site reads. (#5951: a rename was the planned input for 11 cells and separated one.)
- **Prefer "handle created inside the scope, queried after it".** The live schema is `CombineSchemas(added, old)`, so it differs from a snapshot only where the scope adds or overrides. Creating the handle inside a scope that adds the facet and querying after the scope closes makes the snapshot the superset, so the fixed path is the one that works (an association resolves, a row is found) and master's live read is the one that fails. The pre-scope shape ("handle before, query inside") asserts only that a facet is *not* applied.
- **A facet seen only on read-back cannot separate.** The reader converts values and fills NULL defaults with the runtime context's schema (`ConvertFromDataReaderExpression.cs`), so a converter or default that shows only in the read value agrees on both arms. For a type-level conversion, use an override arrangement: the base schema (`GetDataContext(context, o => o.UseMappingSchema(baseSchema))`) carries the read-back conversion and value A of the facet under test, and the scope overrides it with B.
- **Isolate a per-member site with a two-handle join.** In `from p in parents join c in scoped …`, the join context carries the outer handle's schema, so a member of the second handle (an association, an `is` test) separates only if its own site picks the member's source.
- **Prove red after the fix is in.** With the branch's builder changes committed, run the new tests with `git checkout origin/master -- Source/LinqToDB/Internal/Linq/Builder`, then restore it with `git checkout HEAD -- …`. Before committing, `git stash push -- Source/LinqToDB` does the same.
- **Shared model types collide with `TestBase` properties.** Inside a `TestBase` fixture, write `Model.Parent` / `Model.Child` for the types; `Parent` / `Child` are the in-memory collections.
- **A `CreateTempTable(…, setTable)` cell with `IEnumerable` items excludes remote contexts.** That overload fills the table by BulkCopy even for an empty list, which throws `ArgumentException: Data context must be of DataConnection or DataContext type` on `.LinqService`. Use `[DataSources(false)]`, or pass an `IQueryable` (INSERT … SELECT) to keep remote coverage. (#5951)

Inputs measured not to separate are in [`dead-ends.md`](dead-ends.md) → *MAPPING: inputs that do not separate a handle's schema from the live one*.

## Reading test output

Always read the **full** test run log — not just the tail. NUnit and `dotnet test` interleave relevant information across the log: `_CreateData` failures appear near the top, setup exceptions and warnings can come well before the failing assertion, and stack traces may be truncated if you jump to the end. Do not use `tail`, `head`, `head_limit: 1`, or similar tricks to skim the output; read the entire log and scroll back for context when a failure is surprising. The only exception is when you have already read the log once and are fetching a specific slice you've already identified.

**A passing test's `TestContext.Out` is not in the log — write probe output to an absolute file instead.** The MTP runner prints per-test console output only for **failed** (and skipped) tests, so a diagnostic probe that passes emits nothing at all: the log shows `Test run summary: Passed! total: 1` and none of the `TestContext.Out.WriteLine` lines the probe was written to produce. That reads as "the instrumentation didn't run", which it did. For any in-test instrumentation — a review probe, an input census, a side-by-side comparison — `File.AppendAllText` to a **hardcoded absolute path** under `.build/.agents/` and `Read` that file, rather than relying on captured stdout. Absolute because a relative path follows the invoking process's working directory ([`worktree.md`](worktree.md) → *Run artifacts follow the invoking process's working directory*), and remember the `lock` if the test can run on several provider lanes at once ([`evidence-discipline.md`](evidence-discipline.md) → *Every probe write needs a lock*). (Cost a full extra build-and-run on #5766, where the first probe passed and printed nothing.)

**`Zero tests ran` has a fourth cause, and it is success.** Three ways to read that string are already documented as defects — a filter that matched nothing, an MSBuild switch forwarded to the test application, and the bare-NUnit hosts that reject `--test-progress` (all exit 5). The fourth is benign: MTP prints `Test run summary: Zero tests ran` whenever **no test passed**, including a run where every selected test was *skipped*. Under the run-and-verify `[ActiveIssue]` a holding gate reports `Inconclusive`, which the platform folds into `skipped`, so a filter that selects only gated tests produces `Zero tests ran / total: 1 / failed: 0 / skipped: 1` **and exit code 0** — the expected green result, not a miss. Read `total` and the exit code before treating the phrase as a failure: a real filter miss has `total: 0`, and the flag traps exit 5.

**An `[Explicit]` scratch test does not run under a name filter.** `--filter "FullyQualifiedName~<Name>"` leaves it unselected, so the run reports only the `CreateDatabase` cases and `worktree-test.ps1` lists the probe under `missingTests`. Use a plain `[Test]` for a probe and delete it before committing.

**Two analyzer errors that only the Release build reports in new test code:** IDE0350 on a lambda whose explicit parameter types the compiler can infer (`(QuarterlySales row, string q, …) => …`), and CA1825 on `new T[0]` (use `Array.Empty<T>()`). Debug and `Testing` runs pass them silently, so build `Tests/Linq` in Release before pushing new tests.

## Running a long full suite

For a full-suite run (tens of minutes — e.g. all of one provider across the direct + `LinqService` configs), build the test project first, then run `dotnet test … --no-build` as a **main-agent `run_in_background` Bash task**, and read that task's own output file for the result. Don't delegate the long run to a `test-runner` subagent: the subagent tends to background the `dotnet test` itself and return *before* it finishes, leaving no result to retrieve — and a follow-up agent reading a shared log (e.g. a redirected `ydb-test-full.log`) can pick up a **stale** prior run and report a false pass/fail (this produced a phantom `CalledWithCorrectNames` failure that had actually passed). The `--no-build` flag also avoids the `MSB4166` mid-suite truncation under disk pressure (see [`windows-dev-gotchas.md`](windows-dev-gotchas.md) → *Iterative-build gotchas*). For a small filtered run the `/test` skill / `test-runner` is still the right tool; this is specifically about the long, unattended full-suite case.

**`run_in_background` is not enough on its own when the build is cold — the tool's own 600 s cap is the wall.** The recipe above assumes you can build first and then `--no-build`, but a *cold* `Tests/Linq` build already exceeds 600 s on this machine, so the build step alone times out and there is nothing to run `--no-build` against. `test-runner` will tell you this rather than fake it (it returns `status: "blocked"` naming the timeout, which is the correct answer, not a failure). Launch the whole thing **detached** instead, so the tool call returns immediately and the run outlives it:

```powershell
$wt = '<repo-or-worktree-root>'
$p = Start-Process -FilePath 'dotnet' -WorkingDirectory $wt -PassThru -WindowStyle Hidden `
  -ArgumentList @('test','--project',"$wt\Tests\Linq\Tests.csproj",'-c','Debug','-f','net10.0',
                  '--settings',"$wt\.runsettings",'--provider','SQLite.Classic,SQLite.MS','--test-progress') `
  -RedirectStandardOutput "$wt\.build\.agents\full-suite.log" `
  -RedirectStandardError  "$wt\.build\.agents\full-suite.err.log"
$p.PriorityClass = 'BelowNormal'
```

Then poll `test-status.ps1` at natural intervals and read the **run's own summary** from the log at the end. Two things to get right: set `PriorityClass` on the returned object (a detached process does not inherit the shell's), and treat the heartbeat as a progress indicator only — a suite whose OneTimeSetUp fails or is skipped never reaches its tests, so a completed run can still show `completed < total` while the log's `Test run summary` reconciles exactly (`succeeded + skipped == total`). Report counts from the log, after checking that identity. (Measured on #5814: 21317 tests over both SQLite providers in 36m27s, of which >10 min was the cold build.)

## Diagnosing hung test runs

A `dotnet test` that has been running **>30 s with zero test-output lines** AND a live MTP **test-app process** (named after the test assembly — `linq2db.Tests*` — or `dotnet` when it hosts the test dll) at **>1 GB resident memory** is almost certainly in an infinite-recursion loop — typically a visitor that hands its own output back to itself (`Visit(Optimize(converted))` re-entering its own `VisitXxx` with a structurally-equivalent element). Confirm via `Get-Process linq2db.Tests*,dotnet` (under VSTest this was `testhost.exe`); a normal test run keeps it well under 500 MB.

Recovery and triage:

1. `Get-Process linq2db.Tests*,dotnet -ErrorAction SilentlyContinue | Where-Object { $_.WorkingSet64 -gt 1GB } | Stop-Process -Force` — kill the runaway (filter by memory so unrelated `dotnet` processes aren't touched). The background `dotnet test` wrapper will exit shortly after.
2. Re-read the captured output. The recursion's terminal exception is usually `System.InsufficientExecutionStackException: Too many stack hops (> N). Recursion cannot safely continue.`, thrown from `LinqToDB.Internal.Common.StackGuard.RunOnEmptyStack` — that's linq2db's internal stack-overflow guard re-throwing after the runtime ran out of fresh-thread hops. The top of the truncated stack names the offending visitor method.
3. The fix is virtually always idempotence: the visitor's transformation must produce a fixed point (a re-entry on the transformed element returns it unchanged) — check whether the rewrite wraps an operand in a shape the next visit pass will fail to recognize as already-wrapped, and add a structural guard.

## LinqService host startup failures

Remote (`*.LinqService`) test configs spin up an in-process HTTP host on a **dynamically probed free port** — `ServerContainerBase.GetFreePort()` asks the OS for an ephemeral port, and `StartHostWithRetry()` re-probes up to 3 times to absorb the probe-to-bind race (`Tests/Base/Remote/ServerContainer/ServerContainerBase.cs:31,91`). Ports are per-slot: one shared host by default, or one per thread when `KeepSamePortBetweenThreads = false`.

Because the port is never fixed, a leaked host from an earlier run **cannot** block a new one, and "address already in use" is no longer an expected failure mode. If a `.LinqService` config fails at host startup while the non-remote configs of the same tests pass, treat it as a real signal and read the actual exception — don't go hunting for an orphaned listener on a hard-coded port.

Stray `testhost` / runaway processes from earlier iterations are still worth clearing (see the section above) — they consume memory, not a fixed port.

> Historical note: hosts used to bind a fixed port (`22654`), where the leaked-listener diagnosis was correct. Any recipe keyed to that port number (`Get-NetTCPConnection -LocalPort 22654`) is obsolete.

## Debugging linq2db translators

When debugging query translation or provider issues,
use `Console.WriteLine` to output intermediate values or SQL fragments.
Do not introduce logging dependencies.

### `Should.Throw` / `Should.ThrowAsync` don't resolve inside `Tests.*` — `Tests.Should` shadows Shouldly's

`Tests/Base/Should.cs` declares a `public static class Should` in the `Tests` namespace (NUnit `StringConstraint` helpers — `Should.Contain(...)`, `Should.Not.Contain(...)`). Inside `Tests.*` that name wins over `Shouldly.Should`, so **both** `Should.Throw<T>(…)` and `Should.ThrowAsync<T>(…)` fail to compile with `error CS0117: 'Should' does not contain a definition for 'Throw'` / `'ThrowAsync'`, even though Shouldly 4.3 provides them. The sync form is the one you reach for most often and fails identically — assert it as `Action act = () => …;` then `act.ShouldThrow<T>()`. Use the extension form, which also mirrors the sync `Action` + `ShouldThrow<T>()` shape the fixtures already use:

```csharp
Func<Task> act = () => db.SomeApiAsync(record);
await act.ShouldThrowAsync<LinqToDBException>();
```

Both *are* usable from test projects outside the `Tests` namespace (e.g. `Tests/LinqToDB.CLI/QueryCommandTests.cs`), so grepping the repo for a precedent can mislead you into the form that won't compile where you need it. (Cost a build cycle on #5643 for the async form, and another on #5750 for the sync one — writing `Should.Throw<LinqToDBException>(() => …)` in a `Tests.Playground` probe. And a third on #5833, in `Tests/Linq/UserTests` — the fully-qualified `Shouldly.Should.Throw<T>(…)` compiles fine and is what `SqlRowTests.cs:675` uses, which is the escape when you want the static form's return value for a `.Message` assertion. A fourth on #5704, where the doc was not consulted at all; a fifth on #5879, `Should.NotThrow`.)

### `nameof(Parent.Children)` inside a `TestBase` fixture names the wrong thing

`TestBase` exposes the in-memory model data as properties named after the model types — `Person`, `Parent`, `Child`, `GrandChild`, … — each an `IEnumerable<T>`. Inside a fixture deriving from it, a bare type name in an *expression* position binds to that property, not to the type. So `nameof(Parent.Children)` fails with `CS1061: 'IEnumerable<Parent>' does not contain a definition for 'Children'`, while `typeof(Parent)` in the same file still means the model type. This bites hand-built expression trees (`Expression.Property(p, nameof(…))`) above all. Qualify the type, as in `nameof(Model.Parent.Children)`, or `Model.Person` throughout. Also note that `Person.ID` is a **field**, so the tree needs `Expression.Field`, not `Expression.Property`. (#5879: three compile errors in one build of the hand-built `LoadWith` and association tests.)

**Write `Action act = () => { … };`, not `var act = …` — the `var` form is type-dependent.** Shouldly's sync overload is `ShouldThrow<T>(this Func<object?> actual)` alongside the `Action` one, so `var act = () => q.ToList();` compiles *only* because `Func<List<T>>` converts to `Func<object?>` by reference covariance. Point the same idiom at an expression of a **value** type and the covariance is gone: `var act = () => Helper(db);` on an `int`-returning helper infers `Func<int>` and fails with `error CS1929: 'Func<int>' does not contain a definition for 'ShouldThrow'`. Copying the `var` shape from a passing fixture (`Exceptions/JoinTests.cs:60`) is what walks you into it. An explicit `Action` with a statement body discards the result and works for both. (#5704.)

### `Person` inside a `TestBase` fixture is the property, not the type — and `Person.ID` is a field

`TestBase` declares `protected IEnumerable<Person> Person`, so in a fixture `nameof(Person.ID)` binds to that property and fails with `CS1061: 'IEnumerable<Person>' does not contain a definition for 'ID'`. Qualify the type: `nameof(Model.Person.ID)`. When hand-building an expression tree over `Tests.Model.Person`, use `Expression.PropertyOrField` — `ID` is a field, and `Expression.Property` throws `Instance property 'ID' is not defined`. (#6008: one rebuild each.)

### `ShouldBe` on a LINQ query operator's result needs a materializing call first

`ShouldBe(IEnumerable<T>)` is resolved by extension-method overload lookup, and it does **not** bind against `IOrderedEnumerable<T>` — the compiler picks the `IEnumerable<string>` overload and reports `error CS1929: 'IOrderedEnumerable<int>' does not contain a definition for 'ShouldBe' and the best extension method overload … requires a receiver of type 'System.Collections.Generic.IEnumerable<string>'`. The misleading part is the message, which names `string` for a sequence of `int` and reads as a type-inference bug rather than a receiver-shape problem.

So a chain ending in `OrderBy` / `ThenBy` — which is the natural way to write an order-insensitive sequence assertion — has to be materialized:

```csharp
rows.Select(x => x.Id).Distinct().OrderBy(x => x).ToArray().ShouldBe(new[] { 1, 2, 3 });
```

`.ToList()` works equally well. (Cost a build cycle on #5833, across four assertions written the same way.)

### Finding the tests that depend on a thrown exception

When a change alters *which exception* a member throws — or removes a throw entirely — the question is which tests assert on it. A regex sweep gets this wrong by default, because this repo expresses exception expectations in **five** unrelated shapes, and the obvious one (`Assert.Throws<T>(…)`) is only the first:

| Shape | Example | Where it sits |
|---|---|---|
| NUnit generic | `Assert.Throws<T>(…)` / `Assert.ThrowsAsync<T>(…)` | at the call |
| NUnit constraint | `Assert.That(() => …, Throws.InstanceOf<T>())`, `Throws.TypeOf<T>()`, `Assert.Catch<T>()` | at the call |
| Shouldly delegate | `Action act = () => …;` then `act.ShouldThrow<T>()` / `await act.ShouldThrowAsync<T>()` | **two lines apart** |
| Shouldly static | `Should.Throw<T>(…)` — only outside the `Tests` namespace (see above) | at the call |
| Attribute-borne | `[ThrowsForProvider(typeof(T))]`, `Tests/Linq/ExpectedExceptionAttribute.cs` | on the **test method**, arbitrarily far from anything |

Two consequences. **A proximity window around the member is not a sweep** — the Shouldly delegate form splits the assertion across lines, and the attribute forms are not near the code at all. And **`Assert.Throws<`-only greps read as complete**, because they return plausible-looking hits. Sweep by *member name across the whole test tree*, then cross with all five shapes, plus `catch (T)` for tests that swallow rather than assert.

(#5788: a ±5-line `Throws<…>` window over 137 changed members returned three hits and happened to be right; an idiom-complete census was needed to know that. `ExpressionTests.cs:386` is a `Throws.InstanceOf<LinqToDBException>()` six lines from a changed member and appeared in none of the three.)

### Shouldly inside `Assert.EnterMultipleScope()` aborts at the first failure

NUnit's multiple-assert scope only accumulates failures reported through NUnit's own assertion machinery. **Shouldly throws a plain `ShouldAssertException`**, which propagates straight out of the block — so a fixture wrapping a dozen `ShouldBe` assertions in `using (Assert.EnterMultipleScope())` still stops at the first mismatch and reports exactly one failure.

Consequence when reading such a test's CI failure: **the reported mismatch is not necessarily the only one.** Don't fix just that row and assume green. Get the whole picture in one run with a temporary probe that collects every actual value into a list and ends with `Assert.Fail(string.Join(...))` — the `Assert.Fail` is required, since MTP hides a passing test's stdout (see *Capturing a passing test's exception / stack* below). Revert the probe before committing.

(Surfaced on #5678: `MySqlConnectorProviderSpecificReadMatrix` reported one `Int32`/`Int64` mismatch on MariaDB.11; the probe showed two rows diverged.)

### Capturing a passing test's exception / stack

The MTP runner surfaces per-test stdout only for **failed / skipped** tests — a passing test's `TestContext.Out.WriteLine` / `Console.WriteLine` is generated but never routed to the run output (also why `/test` reports succeeded tests by count only). So when a test passes via `Assert.Throws<T>` and you need the *caught* exception's full stack — e.g. to find where deep in the pipeline it's thrown — printing it from inside the test shows nothing.

To get the stack, make the test **fail** so MTP prints it:

- Replace `Assert.Throws<T>(() => x())` with a bare `x();` — the exception propagates and the failure carries the complete trace (the deepest `LinqToDB.*` frame is the throw site); or
- When you've added a probe `throw` that an enclosing `Assert.Throws<T>` would catch, throw a type `T` won't match (e.g. `NotImplementedException` against an expected `InvalidOperationException`) so it escapes and fails the test.

Do this in a throwaway worktree or local checkout only — never commit the assertion change.

### Inspecting generated SQL offline (reproducing "could not be converted to SQL")

Use `query.ToSqlQuery().Sql` to see a query's SQL without running it. `IQueryable.ToString()` returns the query *type* name (`ExpressionQueryImpl`1[…]`), **not** SQL. Translation failures ("The LINQ expression '…' could not be converted to SQL") are raised at SQL-build time, so `ToSqlQuery()` — or a `CreateLocalTable<T>()` + query in the playground — reproduces them with no populated database.

- **Plain linq2db** emits SQL fully offline when the provider version is explicit: `new DataConnection(new DataOptions().UseSqlServer("Server=.;Database=x", SqlServerVersion.v2022, SqlServerProvider.MicrosoftDataSqlClient))`. A dummy connection string works — nothing is opened. Run this from `Tests.Playground` (link the file in), **not** a hand-rolled console placed under the repo root — `Directory.Build.props` / central package management cascade into any project beneath the root and break a stray project's restore (`Unable to find package <name>`, plus unwanted multi-targeting).
- **EF Core `.ToLinqToDB()`** on SQL Server opens a real connection to auto-detect the server version (`ProviderDetectorBase.DetectServerVersion` → `SqlConnection.Open()`), so it needs a live server even just to emit SQL. SQLite EF Core emits offline.

#### Comparing a PR head against master offline

A finding whose mechanism shows in the emitted SQL is settled by comparing the SQL both heads emit, with no container. Examples: a cast dropped or added, a literal's type, a collection expanded or bound whole. One worktree serves both arms:

1. **Write the probe.** Make it an untracked `Tests.Playground` test. It builds each query on a `DataConnection` with a dummy connection string and an explicit provider name (`ProviderName.ClickHouseOctonica`, `ProviderName.Ydb`, `ProviderName.SybaseManaged`, `ProviderName.SqlServer2022`), and never executes it. Write `ToSqlQuery()`'s `Sql` together with each of its `Parameters` (name, `DataType`, value) to a file named by an environment variable. A captured collection appears as one parameter whose value is the whole collection, so the parameter types matter as much as the text. Give each finding a control shape that should *not* change.
2. **Run master.** Build and run the probe on master, writing the first file.
3. **Run the PR head.** `git checkout --detach origin/pr/<n>` (the untracked probe survives the checkout). Build and run again, writing a second file.
4. **Check the rebuild.** Before reading the second file, confirm that `linq2db.dll` in the playground's output postdates the first run. An incremental build that skipped the library compares master with itself.
5. **Compare.** Diff the two files, then check out the original branch again.

This settles the mechanism and whether it is new against master. The server's answer — an error code or a wrong row — still needs a run, so record which of the two a finding rests on. (#5959 round 8: five findings that had only been read from the source, settled in two ~30-second builds. One was refuted, because master emitted the same SQL; four were confirmed.)

#### One probe run, then read it

A repro run usually has to answer several questions — did it throw, what was the message, what SQL came out, what did the rows materialize as. Capture the whole run **once** and then `Grep` / `Read` that capture per question; re-running the same test with a widened filter costs a full build-and-run cycle and returns nothing the first run didn't already contain. Two things make the first capture sufficient:

- **`--output Detailed`** — without it MTP hides a *passing* test's stdout, which is the usual reason a second run happens (the SQL and the row dump are both `TestContext.Out`).
- **Persist it** — `$o = dotnet test … 2>&1; $o | Set-Content <path>` from the PowerShell tool, then filter the file. Filtering the live variable is fine too, as long as it's the same run.

(Surfaced 2026-08-25 on the set-operation concat regression: one playground test was run four times — pass/fail, then the exception message, then the row values, then the SQL — and the pre-regression baseline worktree four more, for seven avoidable build cycles.)

#### Which `SqlErrorExpression` site raised it

The message names the offending expression but not the code that rejected it, and there are ~35 `SqlErrorExpression` / `CreateSqlError` construction sites across the builder — reading them is slower than asking. Temporarily append `Environment.StackTrace` to a file from the 4-argument `SqlErrorExpression` ctor (`Source/LinqToDB/Internal/Expressions/SqlErrorExpression.cs`), gated on an env var so ordinary runs are unaffected, and log the expression with it:

```csharp
if (Environment.GetEnvironmentVariable("L2DB_ERR_TRACE") == "1")
    System.IO.File.AppendAllText(@"<abs-path>\errtrace.txt",
        "=== EXPR: " + expression + " | MSG: " + message + "\n" + Environment.StackTrace + "\n\n");
```

The stack names the translator, the visitor entry point, and — through the frame names — the build purpose and flags, which is what identifies the branch. Expect **several** traces per query: errors created inside `TryConvertToSql` are discarded by design, so match on the trace whose frames reach the failing consumer (`MergeProjectionHelper.BuildProjectionExpression`, `SelectContext.MakeExpression`, …) rather than the first one logged. Log to an **absolute** path — a relative one follows the invoking process's cwd. Remove the probe with the fix.

## Baselines

Many tests compare emitted SQL against a stored baseline file. Baselines live **outside the main repo** under the path configured by `BaselinesPath` in `UserDataProviders.json` → `MyConnectionStrings`. With `BaselinesPath` set, a mismatched test overwrites the baseline with the new SQL; subsequent runs compare against the updated file. With `BaselinesPath` unset, baselines are neither written nor compared.

Baseline capture is **not** gated on `AssertQuery` / `GetSql`. Emitted SQL is captured at the harness level (`Tests/Base/BaselinesWriter.cs`) for any query a test executes through `GetDataContext`, so a plain `GetDataContext` + `ToList()` + `ShouldBe` test with no `AssertQuery` call still writes `.sql` baselines. Never infer "no baselines" from the assertion style — check the baselines output.

### When a substring assertion is vacuous — prefer baselines for shape-changing fixes

A `ToSqlQuery().Sql.ShouldContain` / `ShouldNotContain("COALESCE")`-style assertion only guards a fix if the substring actually differs pre/post on the providers the test runs on. Two normalizations silently defeat it:

- **No-op stripping.** `Coalesce(x, NULL)` is reduced to bare `x` by `ConvertCoalesce` on every standard provider, so a fix that *stops emitting* such a no-op produces byte-identical SQL — the assertion passes before and after, catching nothing.
- **Function aliasing.** Providers that fold COALESCE to a native construct (Informix `Nvl`, Access `IIF`) never emit the literal `COALESCE`, so a `COALESCE` substring check is vacuous there regardless of the bug.
- **The match is case-insensitive.** Shouldly's `ShouldContain` / `ShouldNotContain` on a string ignore case by default, so an identifier in the SQL that holds the token — a table, column or alias name — satisfies `ShouldContain("CAST")` and defeats `ShouldNotContain("CAST")` regardless of the shape under test. Pin a token with punctuation (`"CAST("`) and keep fixture names free of it. (#5943 round 7: a `CastPairValue` table made every `CAST` pin read its own name.)
- **The path under test never fires.** When the assertion targets an *emulated* or *conditionally-optimised* shape, the parameters have to actually trigger the emulation — otherwise the SQL never contains the construct and the assertion passes for a reason unrelated to the fix. NULLS-position ordering is the recurring case: the position is only lowered into a synthetic `CASE`/`IIF` key when it **differs from the provider's natural order**, so on SQL Server (ASC → NULLs first, DESC → NULLs last) `OrderBy(x, Sql.NullsPosition.First)` emits no key at all, while `NullsPosition.Last` — or `OrderByDescending` with `First` — does. Pick the combination that forces emulation, and **add an anti-vacuous guard asserting the path fired** (`Assert.That(sql, Does.Contain("IIF("), sql)`) next to the real assertion, so the test fails loudly if the provider stops emulating instead of silently testing nothing. (Surfaced on #5732: a NULLS-ordering SQL-shape test written with `NullsPosition.First` on SQL Server passed against known-defective code — a full build-and-run cycle spent before the shape was corrected.)

When a fix changes provider-specific SQL *shape* (especially provider-specific folds), the regression artifact is the per-provider **baseline** `.sql` file, not a substring assertion. (Surfaced on #5531: the bug was only observable as Informix `Nvl(x, NULL)`; a SQLite `ShouldNotContain("COALESCE")` test could not go red.)

### Assertions that pass on nothing

- **`(await store.FindAsync(…))?.Id.ShouldBe(y)` skips the assertion when the lookup returns `null`** — the null-conditional short-circuits the whole chain, `ShouldBe` included. Write `.ShouldNotBeNull().Id.ShouldBe(y)`; `ShouldNotBeNull()` returns the non-null value.
- **A literal NUnit → Shouldly conversion creates that trap.** `Assert.That(x?.Id, Is.EqualTo(y))` is sound — `null` fails `EqualTo` — but its mechanical Shouldly form `x?.Id.ShouldBe(y)` is not. Every `?.` inside an `Assert.That` argument needs the `ShouldNotBeNull()` rewrite, not a transliteration.
- **A round-trip whose DDL and DML share one mapping schema cannot prove a mapping change.** Create the table and query it from the same overridden schema, and a lost rename round-trips just as well under the default names. Pin the physical names through an **independent** mapping — a local `[Table("MyUsers")]` class with `[Column("EmailAddress")]` — that goes red if the override never reached the SQL.

(Surfaced on #5640: three findings of one review — a rename round-trip, a `?.` login lookup, and five `?.` sites that a Shouldly conversion would have silently weakened.)

### Enabling baselines locally

Open `UserDataProviders.json`, find the `MyConnectionStrings` section, and add:

```json
"BaselinesPath": "../linq2db.baselines"
```

Path is arbitrary but the sibling-clone convention — `../linq2db.baselines` — matches the upstream baselines repo's layout and keeps the diff against CI clean.

**The directory must already exist.** `TestConfiguration` keeps `BaselinesPath` only when `Directory.Exists` — a missing directory disables baselines silently, with nothing in the run output saying so. Create it before the run when pointing at a scratch path (e.g. a worktree's `.build/.agents/bls`). (#6014: a probe run wrote no baselines until the directory was created.)

### Getting a "before" snapshot for diffing

Baselines regenerate in place during the test run. To see "before vs after" you need a snapshot of the prior state. Two options:

1. **Regenerate locally**: check out `master` (or the PR base), run the relevant tests to populate baselines at `BaselinesPath`, then switch back and re-run — diff is between the two generations.
2. **Use the remote baselines repo**: clone `https://github.com/linq2db/linq2db.baselines.git` to `../linq2db.baselines` (or fetch into the existing sibling) and compare `BaselinesPath/<Provider>/…` against `../linq2db.baselines/<Provider>/…` directly. No pre-change test run needed; this is the authoritative "before" for branches based on `master`.

For option 2 against a PR's baselines branch, use [`baselines-capture-compare.ps1`](../scripts/baselines-capture-compare.ps1) (`-Pr <n> -CapturePath <BaselinesPath> [-Fetch]`) rather than hand-rolling the comparison. It answers "did my local run reproduce CI?" per file — `matches-branch` yes, `matches-master` no — and encodes the three things the hand-rolled version gets wrong: byte equality instead of a pattern match (a regex for the suspect shape matches the clean shape too, and reports every provider as affected), `-LiteralPath` for names containing `[`/`]`, and intersecting with the branch's own delta first so it doesn't spawn a `git show` per captured file. Checking a change made *on top of* the branch is the exception: its drift lands outside the branch's delta, so add `-AllCaptured -Since <run start>`.

### Unexpected "changed" baselines on a broad run — confirm with a deterministic re-run

A large-suite run against a stale local `BaselinesPath` can report many `changed` baselines — including tests outside your filter and unrelated to your change. That's usually the local `.bls` catching up to current branch code (the cache lagged behind commits made since it was last populated), **not** your change's effect. Before attributing the churn to your work: re-snapshot and re-run the *same* set — a deterministic second run that diffs to ~0 `changed` confirms the first run was cache catch-up. Small focused runs hide this because their few baselines already matched the cache, so the drift only surfaces the first time you run a big suite locally. Corollary: a change that only alters a runtime *value accessor* (e.g. the source a parameter's value is read from) is SQL-text-neutral and cannot move a baseline; if it appears to, suspect stale-cache drift first.

## Known flaky baselines

Tests whose SQL baselines are known to reorder / churn without a real code change. Surfacing reorders here in a PR's baselines diff is **not** a finding — the PR didn't cause it, and flagging it wastes reviewer attention. Mention in passing at most when the diff otherwise runs clean.

- **`Tests.SchemaProvider.SchemaProviderTests.NorthwindTest` on `Northwind.SQLite` / `Northwind.SQLite.MS`** — enumerates views in non-deterministic order (e.g. `[Products by Category]`, `[Alphabetical list of products]`, and `[Summary of Sales by Quarter]` swap positions between runs). The SQL text per view is unchanged; only ordering moves. Confirmed on PR #5443 as pre-existing behavior. The real fix is sorting views by name in the test; out of scope for unrelated PRs.

## `.sql.other` files — direct-vs-remote SQL trace mismatch

When a test runs in both direct (`DataConnection`) and remote (`LinqService` → `DataConnection`) modes for the same provider config, `Tests/Base/BaselinesWriter.cs:62-79` compares the captured SQL across the two runs. If they differ, the second run's body is written to `<test>.sql.other` and the test fails with `"Baselines for remote context doesn't match direct access baselines"`.

**The pair is evidence only about the run that wrote `.other`.** Any later run that touches the same test under the same `BaselinesPath` — a mutation run, a single-leg re-run, a direct-only filter — starts with an empty `_baselines` map, rewrites `<test>.sql` with *its* SQL and leaves the old `.other` in place. The two files then come from different trees, and their diff points at whatever the later run changed. Diff `.other` against the direct SQL in the failing run's own `--output detailed` log, or re-run the pair alone before diffing. (#5943 A-11: after five mutation runs the diff blamed `NoneSame`; the real divergence, in the green run's log, was `PlusL`.)

**If the two sides differ only by one more copy of the same wrapper on the remote side, suspect a convert rewrite that re-matches its own output.** The convert visitor runs several passes over a statement, and the server runs one more on a remote query. A rewrite whose result still satisfies its own trigger therefore stacks N times on direct and N+1 times on remote. The fix belongs in the rewrite: return a node that is already in the target form unchanged. Don't look in serialization. (#6116: `toDateTime64(…)` ×3 on direct and ×4 on remote over a ClickHouse IN-list operand.)

`.sql.other` is therefore a **failure indicator**, not an alternate-acceptable form. New PR-introduced `.sql.other` entries warrant root-cause analysis. **Pre-existing entries — always on Oracle — are usually flaky CI artifacts, not a reproducible bug** (#5513):

- Oracle and Access test jobs run with `retry: true` (`retryCountOnTaskFailure: 2`, set because those providers crash / have resource-management issues — see `Build/Azure/pipelines/templates/test-matrix.yml`). A flaky attempt that writes a `.sql.other` (or a crash leaving a partial `.sql`) fails the first `dotnet test`; the retry re-runs, the flake doesn't recur, the job goes **green** — but the failed attempt's files persist in the baselines working tree and the `Commit test baselines` step (condition `succeeded()`) commits them. Nothing prunes `.sql.other`, so they accumulate (e.g. the long-standing `AnalyticTests.TestMin(Oracle.21.Managed).sql.other`).
- The original "#5513 = remote-mode trace drops scalar `IQueryable<T>` aggregate queries" framing was **disproven**: those analytic aggregates trace fine in remote mode on both SQLite and Oracle.21.Managed in isolation. PR #5572 resets the baselines working tree before each retried attempt to stop the leak.
- So: a pre-existing `.sql.other` on a `retry: true` provider that doesn't reproduce locally is flake. Confirm by **blob-comparing** `<test>.sql` vs `<test>.sql.other` (`git ls-tree -r <ref>`): identical blob = stale never-pruned leftover; differing = a real divergence that was captured.
- **But the reverse inference does not hold: a green `retry: true` leg is not evidence of flake.** A retry re-runs only the failed case, so for a `*.LinqService` failure the sibling *direct* case does not run in that process — `BaselinesWriter._baselines` is empty, and the write-vs-compare branch takes **write**. The remote body is stored as `<test>.sql` and nothing is compared, so a *fully deterministic* divergence passes on attempt 2 exactly like a flake does, reported as `Retry summary: Passed! after 2/3 attempts / flaky: 1`. Consequence: `retry: true` is per-matrix-entry, so one leg can be red while its sibling on the same dialect is green **on the identical defect** — don't read that split as provider-specific behaviour and don't go looking for what makes the red provider special. Check `retry` in `Build/Azure/pipelines/templates/test-matrix.yml` first. (Surfaced on #5740 / build 23411: `Access_MDB` has no `retry`, so `Delete5("Access.Jet.Odbc.LinqService")` failed the leg; both `Access_ACE` legs hit the same mismatch, wrote their `.sql.other`, and reported green. Those committed `.other` files were the only artifact anywhere showing both sides — a second reason the retry green is worse than useless: it also means the *red* leg never reaches its `Commit test baselines` step, so the evidence you want exists only on the legs that hid the failure.)

Investigation tip — when the CI logs for an old committed `.sql.other` have expired, look for the same or similar artifacts in the unmerged `linq2db.baselines/baselines/pr_*` branches; those carry fresh CI logs (and the per-job commit message — e.g. `[Linux / Oracle 21c] baselines` — names the exact job that produced it).

### The *shape* of the `.sql` vs `.sql.other` diff names the cause

Once you have both files, the diff discriminates between the two mechanisms that produce this failure, which otherwise look identical from the message alone:

- **A pure reordering** — same statements, same values, only the sequence differs (classically the operands of a merge source's `UNION ALL`) — is **nondeterministic input order**, not a tracing fault. Something materialized a collection without an `ORDER BY` / `.OrderBy`, and the two runs got different orders from the database.
- **Missing or extra statements** on one side is **capture misrouting** — a query's trace resolved to the wrong test's context. That is the failure `Tests/Base/CustomTestContext.cs`'s `Get()` documents (the server executes on pooled transport threads whose `CurrentTestId` can resolve to a concurrently-running direct test).
- **Only a parameter *name* differs** — same statements, same values, same order, one side emitting `@x_0` where the other emits `@x_1` — is a **query-cache-state** difference: one side reused a cached query and replayed its build-time name, the other rebuilt. Neither side is the bug. The bug is upstream, in whatever made a build-time name depend on something the cache key does not cover, and it reproduces with no remoting at all once you toggle `UseDisableQueryCache`. Don't chase the two execution paths. (Surfaced on #5740, where a constant array index was folded into the parameter name; `code-reviewer.md` rule 2 carries the review-time tell.)
- **Only a column facet differs, on `SqlServer.SA[.MS]` only** — same statements and values, but a parameter's size or type changes (`NVarChar(50)` direct, `NVarChar(4000)` remote) — is **mapping-metadata order dependence**. The SA direct and remote contexts combine the test's mapping schema with the extra SA schema in opposite order (`Tests/Base/TestBase.Context.cs`), so any metadata where the first match wins (`EntityDescriptor` keeps the first `ColumnAttribute` per member) resolves differently on the two sides. That is a product bug in whoever emits the competing metadata, not in the harness. CI logs carry no SQL; a local run of the SA provider writes the `.other` next to the baseline. (#5707: the F# option reader's synthetic `ColumnAttribute` shadowed `[<Column(Length = 50)>]`.)
- **A `CAST` around a computed expression on the direct side only** — same statements, but direct wraps a binary (`a * b`, `x / 10^p`) in a non-mandatory cast that remote lacks — is **binary-expression type loss over LinqService** ([#6055](https://github.com/linq2db/linq2db/issues/6055)): the serializer writes a `SqlBinaryExpression` by `SystemType` only, and the server's optimizer folds the cast whose re-inferred source now equals its target. Until #6055 lands, the translator-side fix is to type the intermediate with the type it actually computes in, so no cast is generated on either side. (#5943 A-11: `Multiply` / `Div` typed with a Decimal-storage `double` made the convert visitor add `CAST(… AS Double)` directly; typing them Double removed it.)

Reach for the diff before theorising: the two have unrelated fixes, and the message is the same either way.

To reproduce an ordering case deterministically instead of waiting for the orders to differ by luck, perturb one side on purpose — materialize the collection and reverse it only when `context.IsRemote()`. Then the red case is on demand, and re-running with the ordering fix applied **while the perturbation is still active** is what proves the fix rather than proves the coincidence went away. (Used on #5864 for `MergeTests.DeleteReservedAndCaseNamesFromList("Firebird.4.LinqService")`: the `.other` differed from the direct baseline in exactly the `UNION ALL` operand order across otherwise identical 248-line files.)
