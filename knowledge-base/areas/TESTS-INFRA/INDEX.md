---
area: TESTS-INFRA
kind: area-index
sources: [code]
confidence: high
last_verified: 2026-10-09
last_verified_sha: 05150894edc2511f0dd0bc7829b2a309cec36ec9
coverage_tier_1: 16/16
coverage_tier_2: 89/89
---

# TESTS-INFRA

Test harness shared by all `Tests/` projects. Provides provider selection via parameterized NUnit attributes, configuration loading, per-test context management, SQL baseline recording, remote-transport containers, resource-lane parallel execution, and extensibility hooks for downstream forks.

## Subsystems

### Provider selection (`Tests/Base/Attributes/`)

`DataSourcesBaseAttribute` is the root of the provider-selection tree. It implements `IParameterDataSource`, making it usable as an NUnit parameter source. `GetData()` returns the filtered provider list; if `IncludeLinqService` is true, each provider name is duplicated with the `LinqServiceSuffix` appended.

`DataSourcesAttribute` -- excludes a given set from all `TestConfiguration.UserProviders`. `IncludeDataSourcesAttribute` -- intersects the supplied list with `UserProviders`.

`CreateDatabaseSourcesAttribute` -- now delegates provider selection to the single-source-of-truth `TestConfiguration.GetCreateDatabaseProviders(Providers)` (default provider if not in `UserProviders`, plus `UserProviders` entries that are in `TestConfiguration.Providers` and not excluded), shared with the readiness wait in `TestBase.OnBeforeTest` so the two cannot drift.

`InsertOrUpdateDataSourcesAttribute` -- extends `DataSourcesAttribute`; hardcodes `Unsupported = { TestProvName.AllClickHouse, TestProvName.AllYdb }` (neither supports the upsert shape these tests exercise); constructors mirror the other `DataSourcesAttribute` subclasses (`params string[] except`, plus an `includeLinqService` overload). `Tests/Base/Attributes/InsertOrUpdateDataSourcesAttribute.cs`.

Feature-scoped attributes live under `Attributes/FeatureSources/` and extend `IncludeDataSourcesAttribute` (or `DataSourcesAttribute`). Examples:
- `AllJoinsSourceAttribute`: `AllSqlServer`, `AllOracle`, `AllFirebird`, `AllPostgreSQL`, `AllClickHouse`, **`AllDuckDB`**.
- `CteContextSourceAttribute` -- exposes `CteSupportedProviders` covering `AllSqlServer`, `AllFirebird`, `AllPostgreSQL`, `DB2`, `Ydb`, `AllSQLite`, `AllOracle`, `AllClickHouse`, `AllMySqlWithCTE`, `AllInformix`, `AllSapHana`, **`AllDuckDB`**.
- `IdentityInsertMergeDataContextSourceAttribute` -- restricts to `AllSybase`, `AllSqlServer2008Plus`, `AllPostgreSQL15Plus`, **`AllDuckDB`**.
- `SupportsAnalyticFunctionsContextAttribute` -- restricts to `AllSqlServer`, `AllOracle`, `AllClickHouse`, **`AllDuckDB`**.
- `SupportsDateTimeOffsetContextAttribute` -- `DataSourcesAttribute` subclass (`AttributeTargets.Parameter`, linq service included by default) that excludes providers with no offset-carrying column type: `AllSqlCe`, `AllAccess`, `AllSapHana`, `AllDB2`, `AllSybase`, `AllFirebird` (2.5 has no type, 4+ rejects the offset on write), `AllInformix`. Excluded rather than declared as expected failures because the refusal is about the type, not the feature under test. Providers that carry an offset stay in scope even when they answer wrongly. `Tests/Base/Attributes/FeatureSources/SupportsDateTimeOffsetContextAttribute.cs`.

`ActiveIssueAttribute` -- no longer just marks configurations `RunState.Explicit`. It is now an `IApplyToTest` + `IWrapSetUpTearDown` attribute (`AllowMultiple = true`, method-only) that **runs the test and asserts it still fails**: the inner result is rewritten by the pure function `Decide(...)` -- failed the declared way becomes `ResultState.Inconclusive` (run stays green, summary carries the `[ActiveIssue] ` marker), passed becomes `Failure` ("issue fixed, remove the attribute"), failed some other way becomes `Failure` (regression or moved message), skipped/ignored/inconclusive is left alone. Declared shape: `ActiveIssue(int)` (builds `https://github.com/linq2db/linq2db/issues/<n>`), `ActiveIssue(string)`, or parameterless, plus `Details`, `Configuration`/`Configurations`, `SkipForLinqService`/`SkipForNonLinqService`, `Platforms` (`TestPlatform` flags enum `Any/Windows/Linux/MacOS`, for RID-dependent native-binary failures), `ErrorType`/`ErrorTypeName` (mutually exclusive) and `ErrorMessage` (matched via `ThrowsWhenAttribute.MessageMatches`, so `{0}` placeholders match as patterns). Remote cases match the type with `Contains`, direct ones with `StartsWith`. With several instances `SelectGoverning` prefers an explicitly targeted one over a blanket one; two equally specific matches fail the test as an authoring error. When a `ThrowsWhenAttribute` on the same method already governs the case (`GovernsCurrentCase`), `Decide` defers (returns null) so nesting order is irrelevant. Adds NUnit category `ActiveIssue`. The command brackets itself with `TestProgressTracker.BeginDeferred`/`CommitDeferred` (see Test progress reporting). `Tests/Base/Attributes/ActiveIssueAttribute.cs`.

`ThrowsWhenAttribute` -- wraps a test command to assert that an exception of a given type is thrown when a parameter matches a specific value. Two constructors: one accepting `Type expectedException`, one accepting `string expectedException` (full type name). Inner `ThrowsWhenCommand : DelegatingTestCommand` runs the test then checks the result message. Virtual `ExpectsException(object)` handles string-contains matching; virtual `ExpectsFirst(object)` controls whether the message must *start with* the exception type (true for non-LinqService provider variants, false for LinqService suffix -- the exception type appears later in the message). New: `AlsoWhenParameter`/`AlsoWhenValue` add a second parameter condition on the same instance (stacking two instances does not work because each wraps independently); internal `MessageMatches(actual, expected)` treats `{n}` placeholders as `.*?` (Singleline regex) so tests can name an `ErrorHelper` format constant; internal `GovernsCurrentCase`/`AlsoWhenMatches`/`GetParameterIndex` expose its decision to `ActiveIssueAttribute`; `Execute` now defers progress booking like `ActiveIssueCommand`. `SkipCIAttribute` is `CategoryAttribute` with `TestCategory.SkipCI`.

`ThrowsCannotBeConvertedAttribute` -- sealed subclass of `ThrowsForProviderAttribute`. Hardcodes exception type to `LinqToDBException` and matches error message fragment `"could not be converted to SQL."`, covering both multi-line (`"The LINQ expression could not be converted to SQL.\nExpression:\n..."`) and single-line (`"The LINQ expression '<expr>' could not be converted to SQL."`) formats produced by `SqlErrorExpression.CreateException`. `Tests/Base/Attributes/ThrowsCannotBeConvertedAttribute.cs`.

`ThrowsRequiresCorrelatedSubqueryAttribute` -- sealed subclass of `ThrowsForProviderAttribute`. Constructor takes `bool simple = false`. When `simple=false`, expects `LinqToDBException` with `ErrorHelper.Error_Correlated_Subqueries` from both `ProviderName.Ydb` and `TestProvName.AllClickHouse`. When `simple=true`, only `ProviderName.Ydb` is in the throws-list (ClickHouse supports simple correlated subqueries via `IsSupportedSimpleCorrelatedSubqueries`). Also adds NUnit category "CorrelatedSubquery" to the test via `ApplyToTest`. `Tests/Base/Attributes/ThrowsRequiresCorrelatedSubqueryAttribute.cs`.

Parallelism-marker attributes: `QueryCacheTestAttribute` -- sealed, derives from `ParallelizableAttribute(ParallelScope.None)` (so it publishes the same `ParallelScope` property as `[NonParallelizable]` and lands on the exclusive lane) and implements `ITestAction`: `BeforeTest` lifts `QueryCache.Default.MaxEntriesOverride` to null (the configured cap, captured once, is restored in `AfterTest`) so the cap on netfx/32-bit legs cannot evict entries the test expects to hit. For tests asserting `GetCacheMissCount()` deltas or query identity. `UsesRemoteContextAttribute` -- marker for tests that append the LinqService suffix to a non-remote parameter in the body, so `DatabaseLaneStrategy` still takes the secondary mutex (see Parallel execution).

### Configuration loading (`TestConfiguration`, `SettingsReader`)

`TestConfiguration` is a static class whose constructor runs once per test assembly:
1. Searches upward from the assembly directory for `DataProviders.json` and `UserDataProviders.json`.
2. Deserializes both via `SettingsReader.Deserialize()` which merges them: user settings win; the `BasedOn` field allows inheritance; `++`/`---` shorthand expands/clears; `-` prefix removes individual entries. `TestSettings` gained `MaxParallelLanes` (`int?`, merged with `??=`).
3. Populates `UserProviders`, `SkipCategories`, `DefaultProvider`, `BaselinesPath`, **`MaxParallelLanes`** (cap on concurrent provider lanes; null means the dispatcher host defaults it, documented as `2 x Environment.ProcessorCount` in `SettingsReader`), and registers all connection strings into `TxtSettings.Instance` (non-framework) or `DataConnection.AddOrSetConfiguration` (net462).
4. Exposes `Providers` -- the master compile-time list of all recognizable provider names. **As of PR #5451, `TestProvName.AllDuckDB` is included in this list.** `EFProviders` now includes `AllMySqlConnector` on every TFM (the old `#if !NET10_0` exclusion is gone).
5. Applies the `--provider` command-line override (see *Command-line integration* below) to `UserProviders`/`EFProviders` before either is exposed.
6. `GetCreateDatabaseProviders(IReadOnlyCollection<string> exclude)` -- the providers `a_CreateData.CreateDatabase` generates a case for (narrower than `UserProviders`: Northwind contexts and TestNoopProvider reach tests and become lane keys without a CreateDatabase case).

`TxtSettings` -- implements `ILinqToDBSettings`. Queried at connection-open time on non-netfx TFMs.

### Environment switches (`TestEnvironment`)

Static class reading the `L2DB_*` environment switches once at type load (mirrors the table in `CONTRIBUTING.md`): `QueryCacheMax` (`L2DB_TEST_QUERYCACHE`, `int?`, default policy deliberately left to the caller since it depends on bitness/TFM), `AssertState` (`L2DB_ASSERT_STATE` set to 1, per-test shared-table comparison), `ParallelDiagnostics` (`L2DB_PARALLEL_DIAG` set to 1, dispatcher routing trace). `Tests/Base/TestEnvironment.cs`.

### Command-line integration (`TestCommandLine`, `TestRunCommandLineProvider`)

`TestCommandLine` (static) parses linq2db's test-run options directly from `Environment.GetCommandLineArgs()` rather than through an MTP service, because the values (`Providers`, `TestProgress`) are needed during static-constructor / NUnit-discovery time, before any Microsoft.Testing.Platform service is resolvable, and independent of how the run was launched (`dotnet test` vs the bare test executable). Two options: `--provider` (`ProviderOption`, repeatable, space- or comma-separated; `GetValues` handles both `--provider a b,c` and `--provider=a,b` forms) and `--test-progress` (`TestProgressOption`, `ArgumentArity.ZeroOrOne`; `GetSingle` returns `null` when absent, `""` when bare, else the supplied directory/`.json` path).

`TestRunCommandLineProvider : ICommandLineOptionsProvider` declares both options to Microsoft.Testing.Platform so the NUnit MTP runner lists them under `--help`; `TestRunBuilderHook.AddExtensions(ITestApplicationBuilder, string[])` registers the provider and is wired via the `TestingPlatformBuilderHook` MSBuild item declared in `linq2db.BasicTestProjects.props`. `Tests/Base/Tests.Base.csproj` adds a `Microsoft.Testing.Platform` package reference to host this provider. The `--test-progress` help text now names the default path `.build/.agents` (was `.build/.claude`). `Tests/Base/TestRunCommandLineProvider.cs`.

`TestConfiguration.ProviderOverride` (a `HashSet<string>?` built from `TestCommandLine.Providers`) changes provider selection two different ways depending on target: for the main test set it **replaces** `UserProviders` wholesale -- any provider with a connection string in `DataProviders.json`/`UserDataProviders.json` can run without editing the file; a provider named via `--provider` with no matching connection string only gets a `TestContext.Out.WriteLine` warning, not a hard failure (it fails later, at connection-open time). For `EFProviders` it **intersects** instead (`ApplyEFProviderOverride`), since forcing an EF-unsupported provider into the curated list would just break every EF fixture.

### Parallel execution (`Tests/Base/Parallelization/`, `DatabaseLaneStrategy`)

Tests now run in parallel across providers while tests on one physical database stay serial. The generic engine lives in namespace `NUnit.ParallelByResource` (nunit/nunit#165 and #3122 workaround); the linq2db policy is `DatabaseLaneStrategy` in `Tests`.

- `ResourceLaneDispatcher : IWorkItemDispatcher` -- installed over NUnit's `ParallelWorkItemDispatcher` by `ResourceLaneDispatcherInstaller.TryInstall(strategy, diagnostics, maxLanes, out levelOfParallelism, out installed)` from assembly one-time setup (no-op returning false on a non-parallel run). `Dispatch` order: (1) already holding the gate on this thread -> run inline; (2) `[NonParallelizable]` (detected via the `ParallelScope.None` property, because a method-level mark yields `ExecutionStrategy.Direct`) -> **exclusive lane**; (3) `CompositeWorkItem` -> forwarded to the original dispatcher; (4) leaf -> `IResourceLaneStrategy.Classify(test)` (null == `GatedInline`). `Start` throws (must never reach it). `CancelRun` cancels the original and completes lanes; `Shutdown(report, timeout)` joins each lane thread (skipping the current thread) and reports lanes stuck on a named test.
- Lane kinds (`SerialLane`, one background thread each, `LaneGating`): **Read** (resource lane, per `ResourceKey`, case-insensitive: takes the shared `ReaderWriterLockSlim` read lock, a `_laneThrottle` permit capped at `maxLanes`, and optionally the global `_secondaryMutex` semaphore), **Write** (exclusive lane: write lock, waits for all resource lanes to go idle, not throttled), **None** (ungated lane in a separate keyspace for resource preparation: no lock, no permit, own thread). Per-thread `ThreadLocal<bool> _gateHeld` lets synchronous nested dispatches skip the non-recursive gate. A per-item exception is contained and logged so a lane thread never dies silently. `Enqueue` after `Complete` runs the item inline.
- `LaneDisposition` enum (`GatedInline`, `SerialLane`, `Ungated`) and `LaneAssignment` readonly struct with factories `GatedInline()`, `Serial(key, requiresSecondaryMutex)`, `Ungated(key)`. `IResourceLaneStrategy.Classify(ITest)` is the single customization seam. `IParallelDiagnostics` (`Log(string)`) with `NullParallelDiagnostics.Instance` (default) and `DelegateParallelDiagnostics(Action<string>)`.
- `ResourceReadinessLatch` -- per-key one-shot `ManualResetEventSlim` gate (`MarkReady`, `WaitReady(key, timeout)`). linq2db holds one in `CustomTestContext` (`MarkDatabaseReady`, `AwaitDatabaseReady` with a 2-minute bound, `IsDatabaseReady` non-blocking probe).
- `DatabaseLaneStrategy.Classify`: no provider context -> `GatedInline`; a `CreateDatabase` case (`NUnitUtils.IsCreateDatabase`) -> `Ungated(context)`; otherwise `Serial(context, requiresSecondaryMutex)` where the mutex is required for a remote variant or a `[UsesRemoteContext]` test. Direct and remote variants of one provider share a lane (`NUnitUtils.GetContext` strips the remote suffix), and the secondary mutex serializes tests that share the single in-process LinqService host.
- `NUnitUtils` helpers added: `UsesRemoteContext(test)` (method or class `[UsesRemoteContext]`), `IsGloballyExclusive(test)` (walks parents for `ParallelScope.None`), plus existing `IsCreateDatabase` and `GetContext`.
- `TestBase.ParallelExecutionEnabled` (static, set by `TestsInitialization` when the dispatcher is installed) gates the readiness wait in `OnBeforeTest`: non-CreateDatabase tests block on `AwaitDatabaseReady(provider)`; on timeout they `MarkDatabaseReady` themselves so other waiters do not each pay the full wait. `OnAfterTest` signals readiness for a CreateDatabase case before its try block so a failed create still unblocks waiters.
- `TestInMemoryDatabases` -- `AddKeepAlive(IDisposable)` / `DisposeAll()` holding connections open for the run: shared in-memory SQLite/DuckDB databases, expensive-first-open Access over ODBC, and Access over OLE DB (teardown races access-violate the process). No-op when nothing is registered.

### Provider name registry (`TestProvName`)

`TestProvName` -- static class of `const string` fields. Each entry is a comma-separated list of provider configuration names for one logical group. As of PR #5451 (DuckDB): **`AllDuckDB = ProviderName.DuckDB`** was added. DuckDB is **not** in `WithWindowFunctions` or `WithApplyJoin`. DuckDB uses `$` as its query parameter prefix.

SQL Server coverage now extends to 2025: `AllSqlServer2025`, `AllSqlServer2025MS`, `AllSqlServer2025Plus` (includes `AllSqlAzure` + `AllSqlAzureMi`), and `AllSqlServer2022Plus` / `AllSqlServer2019Plus` / etc. ranges updated accordingly. PostgreSQL coverage now extends to v19: `AllPostgreSQL17Plus`, `AllPostgreSQL18Plus = ProviderName.PostgreSQL18`, and **`AllPostgreSQL19Plus = ProviderName.PostgreSQL19`** (PR #5644); `AllPostgreSQL18Plus` chains into it (`{ProviderName.PostgreSQL18},{AllPostgreSQL19Plus}`), and the `AllPostgreSQL15Plus` / `AllPostgreSQL` ranges include it transitively. Newer range groups: `AllPostgreSQL12Plus = {PostgreSQL12},{AllPostgreSQL13Plus}`, `AllPostgreSQL93Minus = {PostgreSQL92},{PostgreSQL93}`, `AllPostgreSQL10Minus = {AllPostgreSQL9},{PostgreSQL10}`.

### Provider-name comparison helpers (`ProviderNameHelpers`)

Extension methods on `string` (context/provider name), extracted from what used to be `TestBase` instance/static members: `IsAnyOf(this string context, params string[] providers)` (strips the remote suffix, matches against comma-split provider lists), `IsRemote()` / `StripRemote()` (based on `TestBase.LinqServiceSuffix`), `SupportsRowcount()` (**now reads `DataConnection.GetDataProvider(context.StripRemote()).SqlProviderFlags.IsAffectedRowsCountSupported`** instead of hardcoding ClickHouse/Ydb, so tests and the library cannot drift), `IsUseParameters()` (false for ClickHouse), `IsUsePositionalParameters()` (true for SapHana/Access), `SplitAll(this IEnumerable<string>)` (flattens comma-lists to individual provider names). `TestBase.Utils.cs`, `TestBase.Context.cs`, `TestBase.Identity.cs`, and `TestConfiguration.Providers`'s `.SplitAll()` call all consume these as free-standing extensions rather than calling into `TestBase` itself. `Tests/Base/ProviderNameHelpers.cs`.

### Base test class (`TestBase`)

`TestBase` is `abstract partial`. Key partials:
- `TestBase.cs` -- static constructor sets `DataConnection.WriteTraceLine`; `[SetUp]`/`[TearDown]`. `LastQuery` is now stored per test in `CustomTestContext` (`LASTQUERY` key) rather than a static field. `OnBeforeTest` clears any stale server-provider marker (`CustomTestContext.SetServerProvider(null)`), calls `CustomTestContext.Begin(isRemote, provider)`, and performs the parallel readiness wait (see Parallel execution).
- `TestBase.Context.cs` -- `GetDataContext` / `GetDataConnection` factory methods.
- `TestBase.AssertQuery.cs` -- executes query against DB, re-evaluates LINQ expression in-memory, calls `AreEqual`. Expression rewriting handles `SqlQueryRootExpression` (replaces with a `ConstantExpression` of the `DataContext`) in addition to `ExpressionConstants.DataContextParam`. `RemapNullsOrdering` translates `LinqExtensions.OrderBy/OrderByDescending/ThenBy/ThenByDescending` overloads with a `Sql.NullsPosition` argument into two-step standard LINQ ordering: a null-grouping key (`0`/`1` constant) followed by the actual value key, reproducing NULLS FIRST/LAST semantics in-memory.
- `TestBase.Asserts.cs` -- `AssertState` toggle `_assertStateEnabled` is now a `readonly` field initialised from `TestEnvironment.AssertState` (`L2DB_ASSERT_STATE=1`), so the shared-table pollution check can be switched on without recompiling.
- `TestBase.Tables.cs` -- lazy-loaded cached properties for every test model entity.
- `TestBase.Concurrent.cs` -- `ConcurrentRunner` thread-pool parallelization. Results are now a `ConcurrentRunOutcome<TParam,TResult>` record: the `checkAction` runs on the worker thread and a passing result is dropped immediately (retaining all peaked ~570MB for one EagerLoadMultiLevel lane), only failures keep result/last query/parameters. Query exceptions and check failures are rethrown through `ExceptionDispatchInfo.Capture` (original stack preserved); the diagnostic re-run on the shared connection is guarded so its own failure cannot replace the reported one.
- **`TestBase.Identity.cs`** -- `ResetPersonIdentity`, `ResetAllTypesIdentity`, `ResetTestSequence`. Covers Access, DB2, Firebird, Informix, MySQL, Oracle, PostgreSQL, SAP HANA, SQL Server, SqlCe, Sybase, SQLite, Ydb, and **DuckDB**. DuckDB lacks `ALTER SEQUENCE RESTART` and cannot drop a sequence a column default depends on, so it now runs four statements: `ALTER TABLE ... DROP DEFAULT`, `DROP SEQUENCE IF EXISTS`, `CREATE SEQUENCE START N`, then `ALTER TABLE ... SET DEFAULT NEXTVAL(...)` (Person.PersonID, AllTypes.ID, SequenceTest3.ID).
- **`TestBase.Utils.cs`** -- `LinqServiceSuffix = ".LinqService"`, `GetProviderName`, `GetParameterToken` (DuckDB returns `'$'`), `IsCaseSensitiveDB`, `IsCaseSensitiveComparison` (includes `AllDuckDB` as case-sensitive).

### Custom test context (`CustomTestContext`)

No longer a single global instance (the old comment "because we don't use parallel test run" is gone). Contexts are per test: `Begin(isRemote, provider)` (called from `TestBase.OnBeforeTest`) creates a fresh context stored in `_byTest` keyed by NUnit `CurrentTest.Id` (AsyncLocal is unreliable under NUnit's async flow). A remote (LinqService) test also publishes it in `_remoteByProvider` keyed by provider so the shared in-process server can resolve it. `TestLinqService.CreateDataContext` calls `SetServerProvider(configuration)` (an `AsyncLocal<string?>`), and `Get()` checks that server marker **first**, then the current test id, then falls back to `_shared`. `Release()` removes both entries. The fallback `_shared` instance (for writes outside any test) refuses to store `TRACE` and `BASELINE` buffers so it cannot grow unbounded. Well-known keys: `BASELINE`, `TRACE`, `TRACE_CAPTURED`, `BASELINE_DISABLED`, `TRACE_DISABLED`, and new `LASTQUERY`. `TRACE_CAPTURED` is set inside `TestBase.cs`'s `DataConnection.WriteTraceLine` callback whenever a trace line is recorded for the current test; `OnAfterTest` checks it (alongside `FailCount > 0`) before appending the accumulated trace to the NUnit failure message, so trace-echo suppression under CI (`EchoTraceToConsole = false`) doesn't also suppress failure diagnostics -- the two are independent. The database-readiness latch API also lives here (see Parallel execution).

### Baseline management (`BaselinesManager`, `BaselinesWriter`)

`BaselinesWriter` -- writes per-test `.sql` files. Strips noise: `BeforeExecute\n`, `(asynchronously)` suffixes, **all `BeginTransaction(*)` variants (including async `BeginTransactionAsync(*)`), `DisposeTransaction\n`, and `DisposeTransactionAsync\n`** (5 transaction markers stripped, expanded in PR #5451).

Parallel-safety changes: `BaselinesManager.LogQuery` serializes the get-or-create of the per-test `StringBuilder` and the append under a `Lock` (concurrent queries in one test previously could each create a builder and lose a capture). `BaselinesManager.Dump` now returns early when `TestContext.CurrentContext.Result.FailCount > 0` so a failed test never leaves a partial baseline file. `BaselinesWriter` replaced the last-writer-wins static `_context` with a local, and wraps `Directory.CreateDirectory`, the `_baselines` overwrite-detection map and the file writes in one `Lock _sync` (direct and remote variants of one provider share a lane, so their two writes to the same path stay ordered). `NormalizeFileName` additionally escapes the pipe character and every control character as `0xNNNN`. `WriteMetrics` returns early only when no baselines were captured, and the metrics file is now `<Platform>.Metrics.txt` without a provider prefix (the report is process-wide).

### Remote transports (`Tests/Base/Remote/`)

Four transport containers spin up in-process hosts. All four now extend `ServerContainerBase<TService>` which uses dynamic port allocation via `GetFreePort()` (probes `TcpListener(IPAddress.Loopback, 0)`, releases the ephemeral port, reuses the number) rather than fixed ports. A TOCTTOU race (another process claims the probed port between probe and actual bind) is handled by `StartHostWithRetry` with up to `MaxStartAttempts = 3` attempts. Thread slots use raw `Environment.CurrentManagedThreadId` as a key (0 = shared slot when `KeepSamePortBetweenThreads = true`). `Lock _syncRoot` (the .NET 9 `System.Threading.Lock` type). `KeepSamePortBetweenThreads` is now backed by an `AsyncLocal<bool?>` (default true) so a test turning it off cannot move a concurrent remote test on another lane onto a per-thread host. `CreateContext` first calls `AssertClassifiedAsRemote()`, which throws `InvalidOperationException` unless the current test is globally exclusive, has a remote parameter value, or carries `[UsesRemoteContext]` -- the "latest caller wins" `_connectionFactory` (and `TestLinqService.MappingSchema`) is only safe because the secondary mutex admits one remote test at a time.

- `GrpcServerContainer` -- non-netfx; wraps `TestGrpcLinqService`; HTTPS via a runtime-generated self-signed certificate (`CreateServerCertificate`, PKCS#12 round-tripped so Kestrel's TLS stack can use the private key) rather than the ASP.NET Core dev cert -- MTP runs tests as a bare executable, so `dotnet test`'s automatic dev-cert provisioning isn't available; the gRPC client accepts any server cert via `DangerousAcceptAnyServerCertificateValidator`. The service is registered as `services.AddSingleton(GrpcLinqService)` (instance, not factory).
- `HttpServerContainer` -- non-netfx; wraps `TestLinqService`; HTTP with `UsePathBase("/remote/linq2db")`.
- `SignalRServerContainer` -- both TFMs (netfx uses `WebHost.CreateDefaultBuilder`; non-netfx uses `Host.CreateDefaultBuilder`); hub path `/remote/linq2db`.
- `WcfServerContainer` -- netfx only; `net.tcp` binding; `MaxReceivedMessageSize` = 10MB.

Previously documented fixed ports (22655, 22656, 22654) are **no longer correct** -- port is probed dynamically by the OS.

### Test progress reporting (`TestProgressReporter`, `TestProgressState`, `TestProgressTracker`)

`TestProgressReporterAttribute` -- assembly-level NUnit `ITestAction`. Delegates `BeforeTest`/`AfterTest` to the static `TestProgressTracker`. Applied as `[assembly: TestProgressReporter]` in `Tests/Tests.Playground/AssemblyInfo.TestProgress.cs`.

`TestProgressTracker` -- writes a JSON heartbeat file (`test-progress.<tfm>.<pid>.json`) under `.build/.agents/` (or a user-specified path). Opt-in via the `--test-progress` command-line option (`TestCommandLine.TestProgress`; formerly documented as an env var -- it is now read through `TestCommandLine`, consistent with the `--provider` option). Throttled to ~1 write/second (`WriteThrottleMs = 1000`). File write is atomic via `File.Replace(tmp, target, null)`. JSON fields: `tfm`, `pid`, `startedUtc`, `updatedUtc`, `done`, `total`, `completed`, `started`, `passed`, `failed`, `skipped`, **`inconclusive`**, `currentTest`, `elapsedSec`, `testsPerSec`, `etaSec`, `recentFailures` (up to 20 entries). The `_current` field retains the most-recently-started test between writes (not cleared on AfterTest) to keep the snapshot useful during throttle gaps.

The accounting moved into `TestProgressState` (no file IO, no statics, directly testable, takes a `publish(force)` callback invoked under its lock): counters, bounded `MaxRecentFailures = 20` list with messages trimmed to 500 chars, and a **deferred-commit protocol**. Result-rewriting wrappers (`ThrowsWhenAttribute`, `ActiveIssueAttribute`) call `BeginDeferred` before the inner command and `CommitDeferred(fullName, final status, message)` after, because NUnit nests the reporter action inside them and it would otherwise sample the pre-rewrite outcome. While a deferral is open `CompleteTest` only samples. Deferrals nest (outermost books), and the protocol self-corrects if ordering flips (no deferral in flight -> books immediately, commit is a no-op). `MarkDone` books any unit left pending. `_booked` makes `[Repeat]`/`[Retry]` iterations of one case count once (re-booking moves it between buckets via `Unbook`). `Inconclusive` is tracked separately because it is where a still-failing `[ActiveIssue]` lands and the platform summary folds it into skipped. When `completed >= total` the run is marked done even if root-suite teardown ordering surprises.

### Interceptors (`Tests/Base/Interceptors/`)

Test-only `IInterceptor` implementations: `SaveQueriesInterceptor`, `CountingConnectionInterceptor`, `CountingContextInterceptor`, `SaveCommandInterceptor`, `SaveAndSkipCommandInterceptor`, `SaveWrappedCommandInterceptor`, `SequentialAccessCommandInterceptor`, `BindByNameOracleCommandInterceptor`, `CustomizationSupportInterceptor`. `SaveAndSkipCommandInterceptor` is a sealed `SaveCommandInterceptor` subclass whose `ExecuteNonQuery` returns `Option<int>.Some(1)` so the command is captured but never run. `SaveCommandInterceptor` (a non-sealed `public class`) records `Parameters` and `Command` in `CommandInitialized`.

### TestProviders (`Tests/Base/TestProviders/`)

- `TestNoopProvider` -- in-memory `DynamicDataProviderBase` that executes no SQL.
- `SQLiteMiniprofilerProvider` -- extends `SQLiteDataProvider`; wraps connections with `ProfiledDbConnection`.
- `UnwrapProfilerInterceptor` -- unwraps `ProfiledDb*` types.

### Compile-time provider stubs (`X86Stubs/`)

Compile-symbol-gated stub types so an x86 test build compiles without an x64-only vendor driver reference (the tests themselves never run against the stubbed provider in an x86 run). `DB2Stubs.cs` (pre-existing, `#if DB2STUBS`) stubs IBM DB2 types. `HanaStubs.cs` (new) mirrors the same pattern for `Sap.Data.Hana.HanaDecimal`, gated by `#if HANASTUBS`: `Tests/Linq/Tests.csproj` and `Tests/Tests.Playground/Tests.Playground.csproj` skip the `Sap.Data.Hana.Net.v8.0` reference when the MSBuild property `X86STUBS` is `True` (that driver is x64-only and throws `ReflectionTypeLoadException` on x86, dropping NUnit's discovered-test count to 0).

### Test utilities

`TestUtils` -- `GetNext()` (atomic counter), `GetSchemaName`/`GetServerName`/`GetDatabaseName` (provider-specific SQL functions -- **DuckDB maps to `current_schema()` and `current_database()`**), `GetValidCollationName` (provider-specific collation name constants -- **DuckDB returns `"NOCASE"`**), `CreateLocalTable<T>`, `Clean(string?)`, `GetConfigName`. Firebird pool eviction changed: the table-scope `Dispose`/`DisposeAsync` and `ClearDataContext` now call `ClearFirebirdPool(dataContext, connection)`, which evicts only **this** database's pool (`FirebirdTools.ClearPool(DbConnection)` when a live `DataConnection` connection is available, else `ClearPool(connectionString)` for the remote path) instead of process-wide `ClearAllPools()`, which broke concurrently running Firebird versions.

`ScopedSettings` -- collection of `IDisposable` scope guards: `RestoreBaseTables`, `CultureRegion`, `InvariantCultureRegion`, `OptimizeForSequentialAccess`, `ThreadHopsScope`, `DisableBaseline`, `DeletePerson`, `SerializeAssemblyQualifiedName`, `DisableLogging`.

`TestData` -- static constants for test values: `DateTimeOffset`, `DateTime`, `DateOnly`, `TimeSpan`, six `Guid` constants. `Binary(int)` and `SequentialGuid(int)`.

## Key types

| Type | File | Role |
|---|---|---|
| `TestBase` | `Tests/Base/TestBase.cs` (+ partials) | Abstract base for every test fixture |
| `DataSourcesBaseAttribute` | `Tests/Base/Attributes/DataSourcesBaseAttribute.cs` | NUnit `IParameterDataSource` |
| `DataSourcesAttribute` | `Tests/Base/Attributes/DataSourcesAttribute.cs` | Excludes listed providers |
| `IncludeDataSourcesAttribute` | `Tests/Base/Attributes/IncludeDataSourcesAttribute.cs` | Restricts to listed providers |
| `InsertOrUpdateDataSourcesAttribute` | `Tests/Base/Attributes/InsertOrUpdateDataSourcesAttribute.cs` | Excludes ClickHouse/Ydb (no upsert support) |
| `ActiveIssueAttribute` | `Tests/Base/Attributes/ActiveIssueAttribute.cs` | Runs known-failing provider/test combos and asserts they still fail (Inconclusive) |
| `ThrowsCannotBeConvertedAttribute` | `Tests/Base/Attributes/ThrowsCannotBeConvertedAttribute.cs` | Asserts `LinqToDBException` "could not be converted to SQL." for given providers |
| `ThrowsRequiresCorrelatedSubqueryAttribute` | `Tests/Base/Attributes/ThrowsRequiresCorrelatedSubqueryAttribute.cs` | Asserts correlated-subquery error for Ydb (+ ClickHouse when `simple=false`) |
| `ThrowsWhenAttribute` | `Tests/Base/Attributes/ThrowsWhenAttribute.cs` | Wraps test command; asserts exception thrown when parameter matches expected value |
| `QueryCacheTestAttribute` | `Tests/Base/Attributes/QueryCacheTestAttribute.cs` | Exclusive-lane marker that lifts the query-cache cap for the test |
| `UsesRemoteContextAttribute` | `Tests/Base/Attributes/UsesRemoteContextAttribute.cs` | Declares a hidden remote-context use so the secondary mutex is taken |
| `SupportsDateTimeOffsetContextAttribute` | `Tests/Base/Attributes/FeatureSources/SupportsDateTimeOffsetContextAttribute.cs` | Excludes providers lacking an offset-carrying type |
| `CteContextSourceAttribute` | `Tests/Base/Attributes/FeatureSources/CteContextSourceAttribute.cs` | CTE-capable providers (incl. DuckDB) |
| `IdentityInsertMergeDataContextSourceAttribute` | `Tests/Base/Attributes/FeatureSources/IdentityInsertMergeDataContextSourceAttribute.cs` | Providers supporting identity-insert merge (incl. DuckDB) |
| `SupportsAnalyticFunctionsContextAttribute` | `Tests/Base/Attributes/FeatureSources/SupportsAnalyticFunctionsContextAttribute.cs` | Window/analytic function providers (incl. DuckDB) |
| `AllJoinsSourceAttribute` | `Tests/Base/Attributes/FeatureSources/AllJoinsSourceAttribute.cs` | All-joins-capable providers (incl. DuckDB) |
| `TestConfiguration` | `Tests/Base/TestConfiguration.cs` | Loads `DataProviders.json` + `UserDataProviders.json`; applies `--provider` override; `MaxParallelLanes`, `GetCreateDatabaseProviders` |
| `TestEnvironment` | `Tests/Base/TestEnvironment.cs` | `L2DB_*` environment switches |
| `TestCommandLine` | `Tests/Base/TestCommandLine.cs` | Parses `--provider` / `--test-progress` from raw process args |
| `TestRunCommandLineProvider` / `TestRunBuilderHook` | `Tests/Base/TestRunCommandLineProvider.cs` | Declares linq2db's MTP command-line options; registers the provider |
| `ProviderNameHelpers` | `Tests/Base/ProviderNameHelpers.cs` | `string` extensions: `IsAnyOf`, `IsRemote`, `StripRemote`, `SupportsRowcount`, `IsUseParameters`, `IsUsePositionalParameters`, `SplitAll` |
| `TestProvName` | `Tests/Base/TestProvName.cs` | Comma-list constants for every provider group |
| `CustomTestContext` | `Tests/Base/CustomTestContext.cs` | Per-test SQL trace + baseline accumulator; remote-server resolution; readiness latch |
| `DatabaseLaneStrategy` | `Tests/Base/DatabaseLaneStrategy.cs` | linq2db `IResourceLaneStrategy`: lane = provider database |
| `ResourceLaneDispatcher` | `Tests/Base/Parallelization/ResourceLaneDispatcher.cs` | Custom NUnit `IWorkItemDispatcher` with per-resource serial lanes, exclusive lane, ungated lane |
| `ResourceLaneDispatcherInstaller` | `Tests/Base/Parallelization/ResourceLaneDispatcherInstaller.cs` | Swaps the dispatcher in at assembly setup |
| `ResourceReadinessLatch` | `Tests/Base/Parallelization/ResourceReadinessLatch.cs` | Per-key one-shot readiness gate |
| `LaneAssignment` / `LaneDisposition` / `IResourceLaneStrategy` | `Tests/Base/Parallelization/` | Strategy contract and routing decision |
| `BaselinesManager` / `BaselinesWriter` | `Tests/Base/Baselines*.cs` | SQL-baseline capture and file write |
| `TestInMemoryDatabases` | `Tests/Base/TestInMemoryDatabases.cs` | Run-long keep-alive connections |
| `IServerContainer` | `Tests/Base/Remote/ServerContainer/IServerContainer.cs` | Contract for remote transport hosts |
| `ServerContainerBase<TService>` | `Tests/Base/Remote/ServerContainer/ServerContainerBase.cs` | Dynamic-port host lifecycle; probe-then-retry port allocation; remote-classification assert |
| `TestProgressReporterAttribute` | `Tests/Base/TestProgressReporter.cs` | Assembly NUnit action; delegates to `TestProgressTracker` |
| `TestProgressTracker` | `Tests/Base/TestProgressReporter.cs` | Throttled JSON heartbeat writer for long test runs |
| `TestProgressState` | `Tests/Base/TestProgressState.cs` | Counters, recent failures, deferred-commit protocol |
| `TestData` | `Tests/Base/TestData.cs` | Canonical test value constants |
| `TestUtils` | `Tests/Base/TestUtils.cs` | Schema/server/DB name query; collation names; temp table factory; per-database Firebird pool eviction |
| `ScopedSettings` | `Tests/Base/ScopedSettings.cs` | IDisposable scope guards |

## Files (Tier 1 / Tier 2)

**Tier 1 (read in full):** `TestBase.cs`, all primary `Attributes/*.cs` (DataSources, IncludeDataSources, ActiveIssue, ThrowsWhen, SkipCI, CreateDatabaseSources, FeatureSources/AllJoinsSource, FeatureSources/MergeDataContextSource, FeatureSources/RecursiveCteContextSource), `TestConfiguration.cs`, `TestProvName.cs`, `Tests/Linq/Tests.csproj`, plus (added this delta) `DatabaseLaneStrategy.cs` and `Parallelization/ResourceLaneDispatcher.cs`.

**Tier 2 (sampled / filled):** see Coverage block. New this delta: `Attributes/QueryCacheTestAttribute.cs`, `Attributes/UsesRemoteContextAttribute.cs`, `Attributes/FeatureSources/SupportsDateTimeOffsetContextAttribute.cs`, `Interceptors/SaveAndSkipCommandInterceptor.cs`, `Parallelization/{DelegateParallelDiagnostics,IParallelDiagnostics,IResourceLaneStrategy,LaneAssignment,LaneDisposition,NullParallelDiagnostics,ResourceLaneDispatcherInstaller,ResourceReadinessLatch}.cs`, `TestEnvironment.cs`, `TestInMemoryDatabases.cs`, `TestProgressState.cs`. `Tests/Linq/Tests.csproj` additionally wires the `Extensions/ClickHouseTests.tt` T4 pair and links `Source/LinqToDB.CLI/.../QueryValueFormatter.cs` (non-net462).

## Inbound / outbound dependencies

**Inbound:**
- `TESTS-LINQ`, `TESTS-EFCORE`, `TESTS-FSHARP`, `TESTS-T4`, `TESTS-VB`, `TESTS-BENCHMARKS`, `TESTS-MODEL` -- all share the attribute family and `TestConfiguration`.

**Outbound:**
- **CORE** -- `DataConnection`, `DataOptions`, `Configuration`, `QueryCache.Default` (`QueryCacheTestAttribute`), `SqlProviderFlags.IsAffectedRowsCountSupported` (`SupportsRowcount`).
- **All PROV-*** -- `TestConfiguration.Providers` enumerates every provider name; **PR #5451 adds `ProviderName.DuckDB`**; `FirebirdTools.ClearPool` (PROV-FIREBIRD).
- **REMOTE-CLIENT** -- `IServerContainer` implementations wrap `LinqService`.
- **TESTS-MODEL** -- `TestBase` lazy-loads model entities.
- **NUnit (internal execution APIs: `IWorkItemDispatcher`, `WorkItem`, `TestExecutionContext`), Shouldly, StackExchange.MiniProfiler, Microsoft.Testing.Platform** (`TestRunCommandLineProvider` command-line option provider).

## Known issues / debt

- `CustomizationSupport.Interceptor` is a non-thread-safe mutable static field.
- `AssertState()` is off by default (now toggled by `L2DB_ASSERT_STATE=1` via `TestEnvironment.AssertState` rather than a hard-coded `false`) -- dead code in CI unless the switch is set.
- `BaselinesWriter._baselines` is a static `Dictionary` without per-run reset (now guarded by `Lock _sync`).
- `Tests.csproj` excludes the entire `WindowFunctionsTests.*` partial-class family via `<Compile Remove>`.
- `MergeNotMatchedBySourceDataContextSourceAttribute` second constructor parameter is `excludeLinqService` and passed as `!excludeLinqService` -- inverted convention.
- `WcfServerContainer.Host_Faulted` throws `NotImplementedException` unconditionally.
- `SkipCategoryAttribute` returns early without applying when `ProviderName != null` -- planned but unfinished.
- **DuckDB identity-reseed detaches the column default, drops/recreates the sequence, then reattaches the default** -- correct but structurally different from every other provider's pattern.
- **`WithWindowFunctions` and `WithApplyJoin` in `TestProvName` do NOT include `AllDuckDB`** -- DuckDB window-function and lateral-join tests may be silently excluded if they use those constants directly.
- `ServerContainerBase.GetFreePort()` has a TOCTTOU race (probe-then-bind): `StartHostWithRetry` retries up to 3 times but a persistent port-churn environment can still exceed that threshold.
- `TestConfiguration.ProviderOverride` (`--provider`) only warns (`TestContext.Out.WriteLine`) when a requested provider has no connection string in `UserDataProviders.json` -- it doesn't fail fast at startup, so a misspelled `--provider` value surfaces as a connection failure deep into the run instead of immediately.
- `ResourceLaneDispatcher` builds on NUnit internals (`NUnit.Framework.Internal.Execution`), so an NUnit upgrade can break it. Its own comment notes the lane-count cap bounds memory but the host default derives from CPU count, loosest on many-core / modest-memory agents.
- Remote (LinqService) tests are serialized globally by the secondary mutex and any remote context created from a test the classifier cannot see as remote now throws (`AssertClassifiedAsRemote`) -- missing `[UsesRemoteContext]` is a hard failure, not silent.
- `ActiveIssueAttribute`'s class summary still says "Unlike `ActiveIssueAttribute`, which hides the test from discovery" (self-reference, stale wording from the older explicit-run implementation).

## See also

- [architecture/overview.md](../../architecture/overview.md)
- [areas/REMOTE-CLIENT/INDEX.md](../REMOTE-CLIENT/INDEX.md)
- [areas/TESTS-LINQ/INDEX.md](../TESTS-LINQ/INDEX.md)
- [areas/TESTS-MODEL/INDEX.md](../TESTS-MODEL/INDEX.md)

<details><summary>Coverage</summary>

- Tier 1: 16/16
- Tier 2: 89/89 (100%) -- accounting from prior 74/74: +15 new Tier-2 files read this delta (`QueryCacheTestAttribute.cs`, `UsesRemoteContextAttribute.cs`, `SupportsDateTimeOffsetContextAttribute.cs`, `SaveAndSkipCommandInterceptor.cs`, 8 `Parallelization/*` support files, `TestEnvironment.cs`, `TestInMemoryDatabases.cs`, `TestProgressState.cs`). Tier 1 +2 (`DatabaseLaneStrategy.cs`, `ResourceLaneDispatcher.cs`).

**Read (prior delta run -- PR #5451 DuckDB additions):**
- `Tests/Base/Attributes/FeatureSources/AllJoinsSourceAttribute.cs` -- `AllDuckDB` added
- `Tests/Base/Attributes/FeatureSources/CteContextSourceAttribute.cs` -- `AllDuckDB` added
- `Tests/Base/Attributes/FeatureSources/IdentityInsertMergeDataContextSourceAttribute.cs` -- `AllDuckDB` added
- `Tests/Base/Attributes/FeatureSources/SupportsAnalyticFunctionsContextAttribute.cs` -- `AllDuckDB` added
- `Tests/Base/BaselinesWriter.cs` -- 5 transaction noise markers stripped
- `Tests/Base/TestBase.Identity.cs` -- DuckDB cases added
- `Tests/Base/TestBase.Utils.cs` -- `GetParameterToken` `'$'` for DuckDB; `IsCaseSensitiveComparison` includes `AllDuckDB`
- `Tests/Base/TestConfiguration.cs` -- `AllDuckDB` added to `Providers`
- `Tests/Base/TestProvName.cs` -- `AllDuckDB = ProviderName.DuckDB`
- `Tests/Base/TestUtils.cs` -- DuckDB `current_database`/`current_schema` helpers

**Read (prior delta run -- ThrowsCannotBeConverted):**
- `Tests/Base/Attributes/ThrowsCannotBeConvertedAttribute.cs` -- new sealed attribute deriving from `ThrowsForProviderAttribute`; hardcodes `LinqToDBException` + message fragment `"could not be converted to SQL."` covering both `SqlErrorExpression.CreateException` output formats
- `Tests/Base/TestUtils.cs` -- `GetValidCollationName` confirmed with `AllDuckDB => "NOCASE"` branch (not previously documented); `GetSchemaName` DuckDB branch confirmed; no other new methods
- `Tests/Tests.Playground/Tests.Playground.csproj` -- structural only; two `<Compile Include>` links (`TestsInitialization.cs`, `CreateData.cs`); no test-infra API changes

**Read (prior delta run -- ThrowsRequiresCorrelatedSubquery / remote transports / progress reporter):**
- `Tests/Base/Attributes/ThrowsRequiresCorrelatedSubqueryAttribute.cs` -- new sealed attribute; `bool simple` param; `simple=false` expects throw from Ydb + ClickHouse; `simple=true` expects throw from Ydb only; uses `ErrorHelper.Error_Correlated_Subqueries`; adds NUnit category "CorrelatedSubquery" via `ApplyToTest`
- `Tests/Base/Attributes/ThrowsWhenAttribute.cs` -- full implementation confirmed: two constructors (Type/string overloads for exception type), virtual `ExpectsException`/`ExpectsFirst` methods, inner `ThrowsWhenCommand : DelegatingTestCommand`; `ExpectsFirst` distinguishes non-LinqService vs LinqService-suffix variants
- `Tests/Base/Remote/HttpContext/HttpServerContainer.cs` -- extends `ServerContainerBase<ITestLinqService>`; dynamic port via base class; sets `RemoteClientTag = "HttpClient"`; `Startup` uses `UsePathBase("/remote/linq2db")` + `MapControllers()`
- `Tests/Base/Remote/ServerContainer/ServerContainerBase.cs` -- refactored to dynamic port allocation: `GetFreePort()` via `TcpListener(IPAddress.Loopback, 0)`; `StartHostWithRetry` with `MaxStartAttempts = 3`; slot key is raw `Environment.CurrentManagedThreadId`; uses .NET 9 `Lock` type; `_connectionFactory` refreshed on every `CreateContext` call; fixed ports 22655/22656/22654 no longer apply
- `Tests/Base/Remote/SignalR/SignalRServerContainer.cs` -- extends `ServerContainerBase<ITestLinqService>`; hub path `/remote/linq2db`; both TFM branches confirmed
- `Tests/Base/Remote/WCF/WcfServerContainer.cs` -- extends `ServerContainerBase<TestWcfLinqService>`; `net.tcp` binding; 10MB message limits; `Host_Faulted` still throws `NotImplementedException`
- `Tests/Base/Remote/gRPC/GrpcServerContainer.cs` -- extends `ServerContainerBase<TestGrpcLinqService>`; HTTPS; `Startup.GrpcLinqService` static handshake; `UseDeveloperExceptionPage`
- `Tests/Base/TestBase.AssertQuery.cs` -- `RemapNullsOrdering` added: translates `LinqExtensions` OrderBy/ThenBy overloads with `Sql.NullsPosition` to two-step standard LINQ ordering; `SqlQueryRootExpression` now also replaced with `ConstantExpression(dc)` alongside `ExpressionConstants.DataContextParam`
- `Tests/Base/TestProgressReporter.cs` -- new file: `TestProgressReporterAttribute` (assembly `ITestAction`) + `TestProgressTracker` (throttled JSON heartbeat to `.build/.agents/test-progress.<tfm>.<pid>.json`); opt-in via `LINQ2DB_TEST_PROGRESS` env var; atomic write via `File.Replace`; up to 20 recent failures captured
- `Tests/Base/TestProvName.cs` -- SQL Server 2025 entries added (`AllSqlServer2025`, `AllSqlServer2025MS`, `AllSqlServer2025Plus`, ranges updated); PostgreSQL 17/18 entries added (`PostgreSQL17`, `AllPostgreSQL17Plus`, `AllPostgreSQL18Plus = ProviderName.PostgreSQL18`)
- `Tests/Tests.Playground/AssemblyInfo.TestProgress.cs` -- applies `[assembly: TestProgressReporter]` to the Playground project; no other test-infra API changes

**Read (prior delta run -- ProviderNameHelpers / command-line / ProviderOverride):**
- `Tests/Base/Attributes/FeatureSources/CteContextSourceAttribute.cs` -- re-verified unchanged (`AllDuckDB` already present from prior run)
- `Tests/Base/Attributes/FeatureSources/MergeDataContextSourceAttribute.cs` -- re-verified unchanged (Tier-1 anchor)
- `Tests/Base/Attributes/FeatureSources/RecursiveCteContextSourceAttribute.cs` -- re-verified unchanged (Tier-1 anchor)
- `Tests/Base/Attributes/FeatureSources/SupportsAnalyticFunctionsContextAttribute.cs` -- re-verified unchanged
- `Tests/Base/Attributes/InsertOrUpdateDataSourcesAttribute.cs` -- newly visited Tier-2 file (previously the uncounted file behind the prior 69/70); excludes `AllClickHouse`/`AllYdb`
- `Tests/Base/Attributes/ThrowsRequiresCorrelatedSubqueryAttribute.cs` -- re-verified unchanged from prior delta run's description
- `Tests/Base/CustomTestContext.cs` -- `TRACE_CAPTURED` constant confirmed; prior doc's `LIMITED` constant does not exist in current source, corrected in Subsystems (see AUDIT-NOTE)
- `Tests/Base/ProviderNameHelpers.cs` -- NEW file; extension methods `IsAnyOf`/`IsRemote`/`StripRemote`/`SupportsRowcount`/`IsUseParameters`/`IsUsePositionalParameters`/`SplitAll` extracted onto `string`
- `Tests/Base/Remote/gRPC/GrpcServerContainer.cs` -- adds `CreateServerCertificate()` runtime self-signed cert for Kestrel HTTPS (MTP bare-executable dev-cert workaround); rest unchanged from prior delta run's description
- `Tests/Base/ScopedSettings.cs` -- re-verified unchanged (8 guard classes; `OptimizeForSequentialAccess` actually lives in `TestBase.Context.cs`, not this file)
- `Tests/Base/TestBase.Context.cs` -- re-verified; consumes `ProviderNameHelpers` extensions (`IsRemote`/`IsAnyOf`) rather than `TestBase`-local helpers; no other behavioral change
- `Tests/Base/TestBase.Identity.cs` -- re-verified; DuckDB branches already present (prior delta), no further change
- `Tests/Base/TestBase.Tables.cs` -- re-verified unchanged (Parent/Child model graph build via `EnsureModel`/`_modelSync` double-checked lock, from #5614 parallelization work)
- `Tests/Base/TestBase.Utils.cs` -- re-verified; calls now route through `ProviderNameHelpers` extensions; `GetParameterToken`/`IsCaseSensitiveDB`/`IsCaseSensitiveComparison` unchanged
- `Tests/Base/TestBase.cs` -- re-verified; `TRACE_CAPTURED` set in the `WriteTraceLine` callback, checked in `OnAfterTest` (see Custom test context update)
- `Tests/Base/TestCommandLine.cs` -- NEW file; parses `--provider`/`--test-progress` from raw process args ahead of MTP service resolution (see Command-line integration)
- `Tests/Base/TestConfiguration.cs` -- `ProviderOverride`/`ApplyEFProviderOverride` added (replace for the main set, intersect for `EFProviders`); reads `TestCommandLine.Providers`
- `Tests/Base/TestExtensions.cs` -- re-verified unchanged (`OmitUnsupportedCompareNulls` for ClickHouse/Ydb)
- `Tests/Base/TestProgressReporter.cs` -- re-verified; opt-in switched from the `LINQ2DB_TEST_PROGRESS` env var (prior doc) to the `--test-progress` command-line option via `TestCommandLine` -- corrected in Subsystems (see AUDIT-NOTE)
- `Tests/Base/TestProvName.cs` -- PostgreSQL coverage extended to v19 (`AllPostgreSQL19Plus = ProviderName.PostgreSQL19`); no other new provider groups
- `Tests/Base/TestRunCommandLineProvider.cs` -- NEW file; `TestRunCommandLineProvider : ICommandLineOptionsProvider` + `TestRunBuilderHook` registering it via `TestingPlatformBuilderHook`
- `Tests/Base/TestUtils.cs` -- re-verified unchanged (DuckDB `current_schema()`/`current_database()`, `GetValidCollationName` `"NOCASE"` confirmed again)
- `Tests/Base/Tests.Base.csproj` -- adds `<PackageReference Include="Microsoft.Testing.Platform" />` to host `TestRunCommandLineProvider`
- `Tests/Base/X86Stubs/HanaStubs.cs` -- NEW file; `#if HANASTUBS` stub for `Sap.Data.Hana.HanaDecimal`, mirrors pre-existing `DB2Stubs.cs`
- `Tests/Linq/Tests.csproj` -- re-verified (Tier-1 anchor); comment clarifies the x86/`X86STUBS` HANA-driver skip mirroring the DB2 stub pattern
- `Tests/Tests.Playground/AssemblyInfo.TestProgress.cs` -- re-verified unchanged (`[assembly: TestProgressReporter]`)
- `Tests/Tests.Playground/Tests.Playground.csproj` -- re-verified; same SAP HANA `X86STUBS` conditional-reference pattern as `Tests/Linq/Tests.csproj`

**Read (this run -- delta):**
- `Tests/Base/Attributes/ActiveIssueAttribute.cs` -- rewritten from explicit-run marker to run-and-assert-still-fails wrapper (`Decide`, `TestPlatform`, `ErrorType`/`ErrorMessage`, `SelectGoverning`, deferred progress booking)
- `Tests/Base/Attributes/CreateDatabaseSourcesAttribute.cs` -- delegates to `TestConfiguration.GetCreateDatabaseProviders`
- `Tests/Base/Attributes/FeatureSources/SupportsDateTimeOffsetContextAttribute.cs` -- NEW; excludes SqlCe/Access/SapHana/DB2/Sybase/Firebird/Informix
- `Tests/Base/Attributes/QueryCacheTestAttribute.cs` -- NEW; `ParallelScope.None` + lifts query-cache cap per test
- `Tests/Base/Attributes/ThrowsWhenAttribute.cs` -- `AlsoWhenParameter`/`AlsoWhenValue`, `MessageMatches` placeholder patterns, `GovernsCurrentCase`, deferred progress booking
- `Tests/Base/Attributes/UsesRemoteContextAttribute.cs` -- NEW marker attribute
- `Tests/Base/BaselinesManager.cs` -- locked `LogQuery`; `Dump` skipped for failed tests
- `Tests/Base/BaselinesWriter.cs` -- `Lock _sync`, no static `_context`, pipe/control-char escaping, provider-less metrics file name
- `Tests/Base/CustomTestContext.cs` -- per-test contexts (`_byTest`, `_remoteByProvider`, `_serverProvider`), `LASTQUERY`, readiness latch API, fallback context drops buffers
- `Tests/Base/DatabaseLaneStrategy.cs` -- NEW; lane classification
- `Tests/Base/Interceptors/SaveAndSkipCommandInterceptor.cs` -- NEW; capture and skip `ExecuteNonQuery`
- `Tests/Base/Interceptors/SaveCommandInterceptor.cs` -- minor (class is the non-sealed base for the skip variant)
- `Tests/Base/NUnitUtils.cs` -- `UsesRemoteContext`, `IsGloballyExclusive` added
- `Tests/Base/Parallelization/DelegateParallelDiagnostics.cs`, `IParallelDiagnostics.cs`, `IResourceLaneStrategy.cs`, `LaneAssignment.cs`, `LaneDisposition.cs`, `NullParallelDiagnostics.cs`, `ResourceLaneDispatcher.cs`, `ResourceLaneDispatcherInstaller.cs`, `ResourceReadinessLatch.cs` -- all NEW; resource-lane dispatcher engine
- `Tests/Base/ProviderNameHelpers.cs` -- `SupportsRowcount` reads `SqlProviderFlags.IsAffectedRowsCountSupported`
- `Tests/Base/Remote/ServerContainer/ServerContainerBase.cs` -- `AsyncLocal` `KeepSamePortBetweenThreads`; `AssertClassifiedAsRemote`
- `Tests/Base/Remote/TestLinqService.cs` -- `CustomTestContext.SetServerProvider(configuration)` in `CreateDataContext`
- `Tests/Base/Remote/gRPC/GrpcServerContainer.cs` -- `AddSingleton(GrpcLinqService)` instance registration
- `Tests/Base/TestBase.Asserts.cs` -- `_assertStateEnabled` driven by `TestEnvironment.AssertState`
- `Tests/Base/TestBase.Concurrent.cs` -- `ConcurrentRunOutcome` record, early check, `ExceptionDispatchInfo` rethrow, guarded diagnostic re-run
- `Tests/Base/TestBase.Identity.cs` -- DuckDB reseed now detaches/reattaches the column default
- `Tests/Base/TestBase.cs` -- per-test `LastQuery`, `ParallelExecutionEnabled`, `CustomTestContext.Begin`, readiness wait/signal
- `Tests/Base/TestConfiguration.cs` -- `MaxParallelLanes`, `GetCreateDatabaseProviders`; `AllMySqlConnector` unconditional in `EFProviders`
- `Tests/Base/TestEnvironment.cs` -- NEW; `L2DB_*` switches
- `Tests/Base/TestInMemoryDatabases.cs` -- NEW; keep-alive resources
- `Tests/Base/TestProgressReporter.cs` -- `inconclusive` field, deferred-commit hooks, accounting delegated to `TestProgressState`
- `Tests/Base/TestProgressState.cs` -- NEW; counters and deferred-commit protocol
- `Tests/Base/TestProvName.cs` -- `AllPostgreSQL12Plus`, `AllPostgreSQL93Minus`, `AllPostgreSQL10Minus`
- `Tests/Base/TestRunCommandLineProvider.cs` -- help text path `.build/.agents`
- `Tests/Base/TestUtils.cs` -- per-database `ClearFirebirdPool` replaces `ClearAllPools`
- `Tests/Base/Tests.Base.csproj` -- whitespace only
- `Tests/Base/Tools/SettingsReader.cs` -- `TestSettings.MaxParallelLanes`
- `Tests/Linq/Tests.csproj` -- ClickHouseTests.tt T4 pair, `QueryValueFormatter.cs` link
</details>
