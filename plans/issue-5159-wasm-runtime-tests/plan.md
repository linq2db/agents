# Work plan: issue-5159-wasm-runtime-tests — WASM runtime testing for the remote client

**Tier:** L  ·  **Status:** approved  ·  **Approved-at:** 2026-10-26 (user, after critic round 3)  ·  **Branch:** issue/5159-wasm-runtime-tests
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

Tier L: the edit surface spans two areas — new test projects under `Tests/` and CI under `.github/workflows/`. No `Source/` edit.

## P1 Problem

Nothing in the repo runs linq2db inside a WASM runtime, so remote-client regressions that only a WASM client hits ship unnoticed. #5158 (merged 2025-11-28) fixed client-side provider-assembly loading for SqlServer / Firebird / Oracle by hand and added no test. A manual spike on 2026-10-26 (browser-wasm console app under Node 26.12.1 against a native `LinqToDBController` server, scratch in the primary clone's `.build/.agents/wasm-spike/`) measured on master `12bc7fe14`:

- PostgreSQL.15, MySql.8.0.MySqlConnector, ClickHouse.Driver, DuckDB: `InitHttpClientAsync` throws `System.InvalidOperationException: Cannot load assembly Npgsql` (resp. `MySqlConnector`, `ClickHouse.Driver`, `DuckDB.NET.Data.`) from `RemoteDataContextBase.RemoteMappingSchema.GetMappingSchema` → `ActivatorExt.CreateInstance` — filed as #6167.
- With reflection-based JSON disabled (the default for any trimmed non-Blazor app) every configuration throws `JsonSerializerIsReflectionDisabled` in `HttpClientLinqServiceClient.GetInfoAsync`; with `TrimMode=full` every configuration throws `DeserializeNoConstructor, JsonConstructorAttribute, LinqToDB.Remote.LinqServiceInfo` — filed as #6168.
- SQLite.MS, SqlServer.2022, Oracle.Managed, Firebird.5, ClickHouse.Octonica initialize and generate a SELECT client-side (only a SELECT was measured); SQLite.MS also round-trips.

CI today only *compiles* two Blazor WASM example clients in Debug (`.github/workflows/build.yml:174`).

## P2 Success criteria

- SC-1 A `build.yml` job runs on every PR, publishes the WASM app in four modes (`Debug`, `TrimPartial`, `TrimFull`, `NoReflectionJson`) and runs each bundle under Node against an in-process server; the job fails on any case that is red and not gated; a missing bundle fails, never skips. → TO-1
- SC-2 For every available configuration in `Debug` and `TrimPartial`, the client completes async init and client-side SQL generation (`ToSqlQuery`) for SELECT, a parameterised SELECT, UPDATE and INSERT; any exception makes that (mode, configuration) case red. → TO-2
- SC-2b MERGE generation has a per-configuration expectation — `Generates`, or `Throws` with `doesn't support SQL MERGE statement` for the builders that refuse it client-side — and the case is red when the outcome differs in either direction. The MERGE is fixed in shape: a non-empty two-row in-memory source (`Using(...)`), `UpdateWhenMatched` and `InsertWhenNotMatched` only, so the other refusal paths (`BasicSqlBuilder.Merge.cs:177-193` delete/by-source operations, `:268` empty source) cannot decide the outcome. → TO-2b
- SC-3 Provider-assembly resolve attempts in the WASM process are captured, attributed to the configuration running when they fired, and reported in the test output without failing a case; a per-mode check asserts the capture works. → TO-3
- SC-4 A full round trip (`ToListAsync`) on SQLite.MS returns the server's seeded rows. → TO-4
- SC-5 Known failures are gated with run-and-verify `[ActiveIssue]`: #6167 for its measured configurations in `Debug`/`TrimPartial`, #6168 for every configuration in `TrimFull` and in `NoReflectionJson`; a fix for either issue turns its gate red. → TO-5a, TO-5b, TO-5c
- SC-6 Every concrete provider name in `ProviderName` is either a matrix row or in an explicit alias/unavailable list with a reason; a constant in neither fails a guard test. → TO-6
- SC-7 The harness catches the #5158 regression class: removing #5158's SqlServer guard turns the SqlServer cases red. → TO-7
- SC-8 A configuration whose server-side provider cannot be constructed on the runner is red unless it is listed as unavailable for that OS, and a listed configuration that does construct is red as a stale exclusion. → TO-8
- SC-9 The host project compiles in a Debug solution build and is not compiled by the Release / Azure / Testing solution builds; the WASM app is not in `linq2db.slnx`, so no solution restore pulls the browser-wasm runtime pack. → TO-9

## P3 Constraints & anti-goals (M/L)

- No edit under `Source/`. The product fixes are #6167 and #6168; this branch only adds the harness and the gates.
- No public API change; no baseline change (the harness writes no baselines).
- Existing CI jobs, their names and the required check (`build`, Azure) are unchanged; the new job is not made required here.
- The WASM app references no ADO.NET provider package — only `LinqToDB.Remote.HttpClient.Client`.
- Only the HttpClient remote transport is exercised (SignalR / gRPC clients are not; recorded in P10).
- Issue-scope reconciliation (#5159: "add some simple tests for WASM runtime"): the plan is wider than the issue, not narrower — no disclosure obligation.
- User-visible deltas vs master: none (test and CI only).

## P4 Unknowns (M/L)

- U-1 The browser-wasm app builds and publishes without the `wasm-tools` workload — resolved-by probe (spike: Debug build 14 s, Release publish 88 s, `dotnet workload list` empty).
- U-2 The bundle runs under Node, and `HttpClient` requests with a body fail before `fetch` because .NET's streaming-request check calls `new Request("")` (no `location` in Node) — resolved-by probe (spike run5: `Failed to parse URL from`; fetch trace showed no call for body requests; dotnet.runtime.js feature check located; run7: a `Request` subclass mapping `''` to `http://localhost/` makes all three body kinds return 200).
- U-3 Node version on CI — resolved-by scout (no workflow uses Node today; `actions/setup-node` is GitHub-owned, allowed by the policy at `build.yml:17-18`; v7.1.0 = `949feb2413d6458794dcd2491c4babbbce0c15c1` via `gh api`) plus decision: pin Node 24 LTS. Only Node 26 was probed locally; the Node 24 run is part of G-01 (CI).
- U-4 `TrimMode=partial` behaves like the untrimmed bundle and `TrimMode=full` fails every configuration — resolved-by probe (spike run12 from a clean `PublishDir`/`IntermediateOutputPath`, and run10/run11). The untrimmed evidence was a Debug *build* (`.build/bin/WasmSpike/Debug/...`), not a publish: the WebAssembly SDK publishes trimmed in every configuration (`Sdks/Microsoft.NET.Sdk.WebAssembly/Sdk/Sdk.props:20` sets `PublishTrimmed=true` when unset; ILLink defaults `TrimMode=full`), so an untrimmed mode must set `PublishTrimmed=false` explicitly (D-6) — resolved-by scout (critic round 2, re-checked in the installed SDK).
- U-5 An incremental re-publish with a changed `TrimMode` can reuse stale trimmed output, and a global `-p:IntermediateOutputPath` is not a fix — resolved-by probe (spike: an 18 s re-publish reported the full-trim failure under `TrimMode=partial`; the "clean" 3 min 24 s publish passed `IntermediateOutputPath` globally, and `wasm-spike/obj-partial/` then held `CodeGenerators.dll`, `LinqToDB.Analyzers*.dll`, `linq2db.dll` side by side — the whole project graph rebuilt into one flat obj, with per-project `AssemblyAttributes.cs` files sharing it). D-6 therefore scopes the per-mode directories to the app project only.
- U-6 `[ActiveIssue]` on a test without a `DataSources` parameter governs unconditionally, and a `ValueSource`/`TestCaseSource` argument cannot be targeted — resolved-by scout (`Tests/Base/Attributes/ActiveIssueAttribute.cs:200-201`, `Tests/Base/NUnitUtils.cs:50-74`; split-method precedent `Tests/Linq/DataProvider/AccessTests.cs:671-736`).
- U-7 `[ActiveIssue]` cannot be used without referencing Tests.Base (it uses internal `TestProgressTracker`, `NUnitUtils`; no `InternalsVisibleTo`) — resolved-by scout (`ActiveIssueAttribute.cs:42,343,354,368`).
- U-8 Registering configurations by name runs provider detection, which opens a connection for family names (`ProviderDetectorBase.cs:76-99`, `:95` `CreateConnection`, `:114` `Open`) and keys detection on the configuration name — resolved-by scout; avoided by D-2 (explicit `IDataProvider` per row, `DataOptionsExtensions.cs:842`).
- U-9 Server-side `GetInfoAsync` constructs `DataConnection` without opening it and every provider constructor creates its adapter eagerly, so an adapter that cannot load fails server-side — resolved-by scout (`LinqService.cs:85-102`, e.g. `SqlCeDataProvider.cs:30`).
- U-10 Which configurations cannot construct server-side on ubuntu-24.04 — resolved-by scout: SqlCe (`SqlCeProviderAdapter.cs:82-84`, no package), Oracle Native v11/v12 (`OracleProviderAdapter.cs:446-448`, net462 Redist only), Sybase native (`SybaseProviderAdapter.cs:119-121`, assembly not referenced), Informix IBM (`InformixProviderAdapter.cs:217-219`, net462 Redist), SapHana.Native (Redist, Windows native only, `Tests/Linq/Tests.csproj:27-31,55-60`); Access OleDb/ODBC and SapHana.Odbc should construct (managed reflection only). The list is an explicit table checked both ways (D-5, SC-8); its exact Linux content is confirmed by the first CI run (G-01).
- U-11 `ToSqlQuery` on `IQueryable` / `IUpdatable` / `IValueInsertable` / `IMergeable` runs client-side after init — resolved-by scout (`LinqExtensions.cs:1721-1786` → `QueryRunner.cs:1075` → `RemoteDataContextBase.QueryRunner.cs:51-128`); every sync execution blocks via `SafeAwaiter.Run` (`RemoteDataContextBase.QueryRunner.cs:156-160`), so the app uses async calls only; the default controller refuses non-SELECT execution (`LinqToDBController.cs:48`, `LinqService.cs:72-76`), so DML is generated, never executed.
- U-12 Constructing a remote context can fetch configuration synchronously when `EnableContextSchemaEdit` is on — resolved-by scout (`RemoteDataContextBase.cs:677`, default `false` at `LinqOptions.cs:218`); the app keeps the default.
- U-13 DuckDB also loads its adapter client-side for a parameterised query (`DuckDBSqlOptimizer.cs:93`, `TuneParameters` from `FinalizeStatement`) — resolved-by scout; DuckDB is already in the #6167 gate set, and the parameterised case keeps it gated after a mapping-schema-only fix.
- U-14 ILLink warnings from linq2db (709 `IL*` warnings in the spike publish) under the inherited `TreatWarningsAsErrors=true` — resolved-by decision: the app sets `SuppressTrimAnalysisWarnings=true` (D-6); trim-warning cleanliness belongs to #6168 / the AOT work, the harness measures runtime behaviour. The first Release publish is G-05x.
- U-15 Release analyzers and the `System.Console` ban (`RS0030`, `Tests/Directory.Build.props:24`) apply to the new projects — resolved-by scout: standalone projects remove the `BannedSymbols.txt` item (`Tests/Tests.Analyzers/Tests.Analyzers.csproj:41`, `Tests/Tests.SingleFile/Tests.SingleFile.csproj:33`).
- U-16 The host needs the provider packages server-side and the MTP hook — resolved-by scout: `Tests/linq2db.TestProjects.props` imports `linq2db.BasicTestProjects.props` (MTP, NUnit, Shouldly, `TestRunBuilderHook` from Tests.Base, `:23-28`) and `linq2db.Providers.props`; `Net.IBM.Data.Db2` is chosen by build-host OS (`linq2db.Providers.props:78-80`), consistent when CI builds and runs on Linux.
- U-17 The report writer must work when reflection-based JSON is disabled (the `NoReflectionJson` and `TrimFull` bundles) — resolved-by decision: the app writes its report with `Utf8JsonWriter` directly, no serializer.
- U-19 Tests.Base static initialisation in a CI job without `UserDataProviders.json` — resolved-by scout (code read, unprobed at run time): `TestConfiguration`'s static ctor walks up to the tracked root `DataProviders.json` and treats `UserDataProviders.json` as optional (`Tests/Base/TestConfiguration.cs:50-58,185-199`); `[ActiveIssue]` reads `TestConfiguration.BaselinesPath` only when `RequiresBaselines` is set (`ActiveIssueAttribute.cs:197`), which the D-5 gates do not set. First CI run confirms (G-01).
- U-20 Which builders refuse MERGE during client-side SQL generation — resolved-by scout (searched `BuildMergeStatement|doesn't support SQL MERGE` in `Source/LinqToDB/Internal/DataProvider`): throw at `YdbSqlBuilder.cs:540`, `MySqlSqlBuilder.cs:508-510` (MySql and MariaDB), `ClickHouseSqlBuilder.cs:34` (all three ClickHouse clients), `SQLiteSqlBuilder.cs:167-169`, `AccessSqlBuilderBase.cs:228-230`, `SqlCeSqlBuilder.cs:192-194`; the test-infra list `Tests/Base/Attributes/FeatureSources/MergeDataContextSourceAttribute.cs:12-22` additionally excludes SqlServer 2005 and PostgreSQL ≤ 14, whose builders do not throw (server-side limits). The per-row MERGE expectation (SC-2b) follows the builder, not the test-infra list, and is confirmed by the first local run.
- U-21 The SqlServer optional resolve probes fire once per process — resolved-by scout (critic): `SqlServerMappingSchema.cs:275` `static readonly Instance`, `SqlServerTypes.cs:104` `Lazy`, `SystemDataSqlServerAttributeReader.cs:85-91` statics; every SqlServer row shares them. TO-3 therefore asserts per mode (process), not per row.
- U-22 DB2 / Informix.DB2 on ubuntu-24.04 may need the clidriver on `PATH` / `LD_LIBRARY_PATH` at provider construction — resolved-by scout plus decision: the repo's Linux DB2 legs set both (`Build/Azure/scripts/db2.provider.sh:35-36`, `Build/CI/run-provider-tests.sh:96-104`) and `DB2ProviderAdapter.cs:148-149` touches every IBM type's static `Null` at construction; E-5 sets both variables to the host output's `clidriver/` before `dotnet test`, and D-7's in-process preflight means a construction failure is reported as server-side (SC-8), never as a misattributed #6167 gate mismatch.
- U-23 A browser-wasm project in `linq2db.slnx` makes every solution restore pull the browser-wasm runtime pack and ILLink tasks (`Build Project="false"` skips compile, not restore) — resolved-by scout (critic; `build.yml:113,116` restore the solution); unmeasured, so the app stays out of the solution (D-9) and the cost never arises.
- U-24 `wwwroot/main.mjs` lands beside `_framework/` in the publish output as a static web asset — resolved-by scout (critic round 3: same StaticWebAssets publish path as the spike's `pub-partial/wwwroot/_framework/`), unprobed as such because the spike copied `main.mjs` by hand; a wrong placement fails every case of the mode loudly (D-6 bundle-missing), and the first local publish closes it (G-10x).
- U-18 Harness capability: the host must run the bundles once and serve per-case results to NUnit cases enumerated at discovery — resolved-by decision D-7 (`TestCaseSource` rows from the static matrix; one Node run per mode, lazily on first case of that mode, cached).

## P5 Decisions (M/L; rejected alternatives mandatory at L)

### D-1 — Host the WASM runtime in Node

- **chosen:** a `Microsoft.NET.Sdk.WebAssembly` console app (`browser-wasm`, `OutputType=Exe`) started by `node main.mjs` with a 3-line `Request` shim.
- **rejected:** headless browser (Playwright) — browser install and server/page orchestration in CI, and Playwright is not a GitHub-owned action; provider-free CLR test without WASM — misses the single-thread / interpreter / trimming failures (#4618, #6168) (user choice, 2026-10-26).
- **why this:** spike proved build, run, fetch and round trip with no workload.
- **failure mode of the choice:** a browser-only defect (CORS, `location`-relative URLs, browser fetch streaming) is not covered; the shim itself could hide a real problem in the streaming check — recorded in P10.

### D-2 — In-process server with an explicit provider per configuration

- **chosen:** the NUnit host starts Kestrel on loopback with a `LinqToDBController` subclass overriding `CreateLinqService()` (as `Tests/Base/Remote/HttpContext/TestHttpLinqServiceController.cs:8-10`) returning a `LinqService` subclass whose `CreateDataContext(configuration)` (`LinqService.cs:64`) looks the name up in the matrix and returns `new DataConnection(new DataOptions().UseConnectionString(<IDataProvider>, <dummy cs>))`. SQLite.MS uses a shared in-memory database seeded and kept open by the host.
- **rejected:** `DataConnection.AddOrSetConfiguration` per name — detection keys on the name and opens connections for family names (U-8), and it shares the global registry `TestConfiguration` writes (`Tests/Base/TestConfiguration.cs:111-140`); a separate server process — second lifecycle and port handshake for no coverage gain.
- **why this:** deterministic provider choice with no detection and no connection.
- **failure mode of the choice:** a provider whose real users reach it only through detection (e.g. SqlServer client-library choice by assembly presence) is tested on the explicitly chosen variant only — the matrix lists both client libraries where two exist.

### D-3 — The matrix is an explicit table, guarded against `ProviderName`

- **chosen:** `ProviderMatrix` holds one row per concrete provider (name, `Func<IDataProvider>` via the provider's `*Tools.GetDataProvider(...)`, dummy connection string). A guard test reflects over `ProviderName`'s `public const string` fields and requires each to be a matrix row, an alias row (family/alias names: `SqlServer`, `Oracle`, `PostgreSQL`, `MySql`, `MySql.5.7`, `MySql.8.0`, `MariaDB.10`, `Firebird`, `DB2`, `Access`, `Access.Odbc`, `ClickHouse`, `SQLite`, `SapHana` — each with its resolution reason from the scout), or an unavailable row (D-5). `Sybase` (the native ASE provider, `ProviderName.cs:309`) and `Informix` (the IBM.Data.Informix provider, `ProviderName.cs:105`) are concrete providers whose assemblies are not available to a .NET host, so they are unavailable rows on every OS, not aliases. Each matrix row also carries its MERGE expectation (SC-2b, U-20).
- **rejected:** iterating `ProviderName` constants directly — family names open connections or fail detection (U-8); `DataProviders.json` — its names are test-environment names (`MySqlConnector.5.7`, `SqlServer.2019.MS`), not `ProviderName` constants, and its connection strings are irrelevant.
- **why this:** a new provider constant cannot be silently left out (SC-6).
- **failure mode of the choice:** the guard sees `ProviderName` only; a provider variant without its own constant (SqlServer System vs Microsoft client under one name) needs a deliberate row — rows are keyed by matrix name, not by constant.

### D-4 — The host references Tests.Base for `[ActiveIssue]`

- **chosen:** `Tests/Tests.Wasm/Tests.Wasm.csproj` imports `..\linq2db.TestProjects.props` (Tests.Base, providers, MTP) and uses the existing run-and-verify `[ActiveIssue]`.
- **rejected:** a custom gate attribute — duplicates `ActiveIssueAttribute.Decide` semantics; `Assert.Ignore` / `Inconclusive` by hand — a fixed issue would not announce itself (SC-5).
- **why this:** gates behave exactly like every other gate in the repo, including "test passed but is marked".
- **failure mode of the choice:** the host build pulls Tests.Base / Tests.FSharp / Tests.Extensions — slower CI job; and any Tests.Base static init (`TestConfiguration`) runs in the host — harmless because D-2 does not use the configuration registry.

### D-5 — Gating granularity: one test method per gate group

Following `AccessTests.cs:671-736`, each method is a `TestCaseSource` over (mode, configuration) pairs:

| Method | Cases | Gate |
|---|---|---|
| `ClientWorks` | `Debug`, `TrimPartial` × available configurations not in the #6167 set | none |
| `ClientLoadsProviderAssembly` | `Debug`, `TrimPartial` × #6167 set | `[ActiveIssue(6167, ErrorMessage = "Cannot load assembly")]` |
| `ClientFailsUnderFullTrimming` | `TrimFull` × all available configurations | `[ActiveIssue(6168, ErrorMessage = "DeserializeNoConstructor")]` |
| `ClientFailsWithoutReflectionJson` | `NoReflectionJson` × all available configurations | `[ActiveIssue(6168, ErrorMessage = "JsonSerializerIsReflectionDisabled")]` |
| `UnavailableOnRunner` | configurations listed unavailable for the current OS | asserts server-side construction fails (stale-exclusion check, SC-8) |

- **chosen:** the #6167 set is exactly the configurations measured red in the first full local run (at least the four in P1); each gated configuration is gated because it was measured, not predicted (`testing.md` → *A narrowed provider set is a claim*). Unavailable configurations are an explicit per-OS table with a reason per row (U-10). A MERGE refusal that matches the row's expectation is not an exception of the case (SC-2b), so a #6167 fix for a MySql or ClickHouse.Driver row turns its gate red as passed-but-marked rather than as a message mismatch.
- **rejected:** one method with one broad gate — a gate cannot target a case argument (U-6) and would mark passing configurations; `Inconclusive` for server-side failures — would hide a provider that stopped constructing.
- **why this:** a fix to #6167 for one provider turns exactly that provider's case red as "passed but marked", prompting its move to `ClientWorks`.
- **failure mode of the choice:** a provider failing #6167's way only in `TrimPartial` would be gated in both modes; accepted because the two modes measured identically (U-4).

### D-6 — Four bundles, each published into its own directories

| Mode | Configuration | Trimming | `JsonSerializerIsReflectionEnabledByDefault` |
|---|---|---|---|
| `Debug` | Debug | `PublishTrimmed=false` (the SDK would otherwise trim, U-4) | `true` (Blazor parity, `Microsoft.NET.Sdk.BlazorWebAssembly.Current.targets:22`) |
| `TrimPartial` | Release | `PublishTrimmed=true`, `TrimMode=partial` | `true` |
| `TrimFull` | Release | `PublishTrimmed=true`, `TrimMode=full` | `true` |
| `NoReflectionJson` | Debug | `PublishTrimmed=false` | `false`, set explicitly (with trimming off, "unset" would mean enabled — ILLink sets the `false` default only under `PublishTrimmed`) |

- **chosen:** `Tests/Tests.Wasm/publish-wasm-bundles.ps1` runs `dotnet publish Tests/Tests.Wasm.App/Tests.Wasm.App.csproj -c <cfg> -p:WasmBundleMode=<mode>` per mode, with no `-o`: `WasmBundleMode` is the only mode-specific global property (a global `PublishDir` from `-o` would make `LinqToDB` a distinct project instance per mode, critic round 2). The app's own `Tests/Tests.Wasm.App/Directory.Build.props` imports the parent props and sets `ArtifactsProjectName` to `Tests.Wasm.App_$(WasmBundleMode)` (the `Examples/Directory.Build.props:11` precedent, which already isolates four Blazor WASM clients; `BaseIntermediateOutputPath` is derived from it at `Sdk.props` time, `UseArtifactsOutputPath.props:20-34`), so each mode gets its own obj/bin; `Tests.Wasm.App.csproj` derives `PublishDir` (`<repo>/.build/wasm/$(WasmBundleMode)/`), `PublishTrimmed`, `TrimMode`, `JsonSerializerIsReflectionEnabledByDefault` and `SuppressTrimAnalysisWarnings=true` (U-14) from it per the table; and its `ProjectReference` carries `GlobalPropertiesToRemove="WasmBundleMode"`, so `LinqToDB` and its analyzers build once per configuration (Debug, Release), not once per mode (U-5). `main.mjs` is a project static asset under `wwwroot/`. CI and local runs call the same script; the script deletes the mode's output directory first; the host resolves `<repo>/.build/wasm/<mode>/wwwroot/main.mjs` and fails a case whose bundle is missing with the script's command line in the message.
- **rejected:** a global `-p:IntermediateOutputPath` per mode — rebuilds the whole graph into one shared obj (U-5); the host publishing from `OneTimeSetUp` — hides a multi-minute build inside a test run; an MSBuild target in the host project — every host build would publish four bundles.
- **why this:** one publish path for CI and local, no stale incremental reuse, no duplicate library builds.
- **failure mode of the choice:** a mode flag that silently does not apply produces a bundle of the wrong kind that still runs — the very failure round 2 found in the table; G-10x reads each published bundle's `runtimeconfig.json` reflection flag and the presence or absence of the mode's `linked/` directory, and fails on a mismatch with the table.

### D-7 — One Node process per mode, one JSON report

- **chosen:** before any Node run, the host calls its own `LinqService.GetInfoAsync(configuration)` in-process for every matrix row (preflight); a row that cannot construct server-side is excluded from the Node runs and decided by the unavailable table (SC-8), so a server-side failure never reaches a client gate. The host then runs `node main.mjs <server-url> <report-path> <config...>` once per mode, lazily on the first case of that mode, with a timeout; the app iterates all configurations in that process and writes one report entry per configuration with `Utf8JsonWriter` (U-17): per operation success or exception type + message + stack, plus captured resolve attempts. A missing entry (crash, timeout) fails the case with the Node stdout/stderr tail.
- **rejected:** one Node process per (mode, configuration) — ~4 × 40 process starts; stdout parsing — runtime diagnostics share stdout.
- **why this:** bounded runtime and per-case attribution.
- **failure mode of the choice:** configurations share one process, so a static cache filled by an earlier configuration could mask a later one's failure — accepted in P10 (provider assemblies cannot load at all in the bundle, and the caches involved are keyed per type/configuration).

### D-8 — What makes a case red

- **chosen:** an exception in any operation of the case. `AppDomain.AssemblyResolve` attempts are recorded and written to the test output, never failed (user decision, 2026-10-26: the base `SqlServerMappingSchema` probes `Microsoft.SqlServer.Types` / `System.Data.SqlClient` / `Microsoft.Data.SqlClient` on purpose — spike run9).
- **rejected:** red on any provider resolve attempt — fails SqlServer on deliberate optional probes; red only on `AssemblyLoad` of a provider — unreachable, the bundle ships no provider assembly.
- **why this:** separates real failures from tolerated probes while keeping silent degradation visible.
- **failure mode of the choice:** a silent swallow that degrades behaviour without throwing stays green; the report makes it visible but nothing fails on it.

### D-9 — Solution membership and CI job

- **chosen:** the host in `linq2db.slnx` under the Tests folder with `<Build Solution="Azure|*" Project="false" />`, `Release|*`, `Testing|*` (the `Tests.FpuJit` / `Tests.SingleFile` precedent, `linq2db.slnx:413-427`); the WASM app **not** in any solution (U-23), built only by the publish script. New `build.yml` job `wasm-tests` / "WASM runtime tests" on `ubuntu-24.04`, `timeout-minutes: 40` (re-set from the first measured run, G-10x): checkout, setup-dotnet `10.x`, setup-node `949feb2413d6458794dcd2491c4babbbce0c15c1 # v7.1.0` with `node-version: 24`, `pwsh Tests/Tests.Wasm/publish-wasm-bundles.ps1`, `dotnet build Tests/Tests.Wasm/Tests.Wasm.csproj --configuration Azure`, a step that fails the job when the host output has no `clidriver/` directory (`test -d`) and otherwise appends its `bin` and `lib` to `PATH` / `LD_LIBRARY_PATH` via `$GITHUB_ENV` (U-22; whether `Net.IBM.Data.Db2-lnx` copies `clidriver/` into the output is unverified — `db2.provider.sh:28` copies it by hand — so the guard makes a missing directory loud instead of a dead path), `dotnet test --project Tests/Tests.Wasm/Tests.Wasm.csproj --configuration Azure --no-build --report-trx`, upload the trx under `if: always()`.
- **rejected:** the app in `linq2db.slnx` with `Build Project="false"` — still restored by every solution restore (U-23); both projects outside the solution like `Examples/Examples.slnx` — the host would be invisible in the IDE.
- **why this:** matches the existing standalone-harness pattern without adding restore cost to unrelated jobs.
- **failure mode of the choice:** the host's Release-only analyzers never run in CI (Azure configuration) — covered by a local Release build gate (G-05x); the app's Release analyzers do run, in the `TrimPartial` / `TrimFull` publishes.

## P6 Edit-points

- E-1 `Tests/Tests.Wasm.App/*` — new browser-wasm exe project: `Directory.Build.props` (imports the parent props, `ArtifactsProjectName` per `WasmBundleMode`, D-6), `Tests.Wasm.App.csproj` (`TargetFrameworks` net10.0, `AssemblyName linq2db.Tests.Wasm.App`, `BannedSymbols.txt` removed, mode → `PublishDir` / `PublishTrimmed` / `TrimMode` / `JsonSerializerIsReflectionEnabledByDefault` / `SuppressTrimAnalysisWarnings` per the D-6 table, sole `ProjectReference` `LinqToDB.Remote.HttpClient.Client` with `GlobalPropertiesToRemove="WasmBundleMode"`), `Program.cs` (operations per SC-2/SC-2b, D-7/D-8, async only, `Utf8JsonWriter` report), the entity type in its own file, `wwwroot/main.mjs` (Node entry + `Request` shim).
- E-2 `Tests/Tests.Wasm/*` — new NUnit host: `Tests.Wasm.csproj` (imports `..\linq2db.TestProjects.props`, `TargetFrameworks` net10.0), `ProviderMatrix.cs` (D-3, D-5 tables, MERGE expectation per row), `WasmServer.cs` (D-2), `WasmBundleRunner.cs` (D-7 preflight and Node runs), `WasmRuntimeTests.cs` (D-5 methods, guard test, per-mode capture check).
- E-3 `Tests/Tests.Wasm/publish-wasm-bundles.ps1` — D-6 publish script used by CI and locally.
- E-4 `linq2db.slnx` — add the host project only, with `Build Project="false"` for Azure / Release / Testing (D-9).
- E-5 `.github/workflows/build.yml` — new `wasm-tests` job, including the clidriver `PATH` / `LD_LIBRARY_PATH` step (D-9, U-22).

## P7 Impact map (M/L)

- `.github/workflows/build.yml` — searched `needs:` / `if:` / `paths`: six independent jobs, no aggregate, no path filter (`:21-24`, only `if: always()` at `:273`), so a new job runs on every PR and push to master/release — covered by E-5
- Required checks — searched `wait-pr-checks.ps1`, `github-actions.md`: only Azure `build` is required (`.claude/scripts/wait-pr-checks.ps1:17-21`, `.claude/docs/github-actions.md:35`); the de-facto GitHub gate list is `wait-pr-checks.ps1:47-54` and `github-actions.md:13-20,27-28` — deferred: corpus edit after merge, adding "WASM runtime tests" to both lists
- Action pin policy — searched `uses:` and the policy comments: SHA-pinned GitHub-owned actions only (`build.yml:17-18`, `publish-mcp.yml:11-12`, `github-actions.md:139-145`); no existing `setup-node` — covered by E-5
- Upload of results — searched `upload-artifact`: pin `043fb46d1a93c77aae656e7c1c64a875d1fc6a0a # v7.0.1` (`build.yml:142,151,272`); dotfile trap `github-actions.md:112-123` — covered by E-5 (trx path has no dotfile)
- Standalone-project precedents — searched `Tests/*/*.csproj` headers: `Tests.Analyzers.csproj:7-8,41`, `Tests.SingleFile.csproj:6-7,33`, `Tests.FpuJit.csproj:4-6` — covered by E-1, E-2
- Build props chain — searched `Directory.Build.*`: root `Directory.Build.props:45` (warnings as errors), `:86-87` (`ArtifactsPath .build`, pivots), `:122` (Release analyzers), `:210-211` (Source/Shared compile); `Tests/Directory.Build.props:5-8,24`, and `:31-34` (`Microsoft.Bcl.Memory`, `System.Security.Cryptography.Pkcs` `PackageReference`s inherited by the app, never restored for `browser-wasm` in the spike — settled by the first local publish, G-10x) — covered by E-1, E-2
- Test props — searched `Tests/*.props`: `linq2db.TestProjects.props` (Tests/Linq/Tests.csproj:2), `linq2db.BasicTestProjects.props:4-15,23-28`, `linq2db.Providers.props:9-83` — covered by E-2
- Solution files — searched `linq2db.slnx` and `*.slnf`: standalone projects at `linq2db.slnx:405-427`; no `.slnf` lists them — covered by E-4 (host only; no `.slnf` change)
- Solution restores — searched `restore|build linq2db.slnx` in `.github/workflows/*.yml`: `build.yml:113,116` restore/build the whole solution, as does Azure `build` — covered by E-4 (the browser-wasm app is kept out of the solution, U-23)
- Client-side MERGE refusals — searched `BuildMergeStatement|doesn't support SQL MERGE` in `Source/LinqToDB/Internal/DataProvider`: `YdbSqlBuilder.cs:540`, `MySqlSqlBuilder.cs:508-510`, `ClickHouseSqlBuilder.cs:34`, `SQLiteSqlBuilder.cs:167-169`, `AccessSqlBuilderBase.cs:228-230`, `SqlCeSqlBuilder.cs:192-194`; test-infra list `MergeDataContextSourceAttribute.cs:12-22` — covered by E-2 (per-row MERGE expectation)
- DB2 native client on Linux — searched `LD_LIBRARY_PATH|clidriver` in `Build/`: `Build/Azure/scripts/db2.provider.sh:35-36`, `Build/CI/run-provider-tests.sh:96-104`; adapter statics `DB2ProviderAdapter.cs:148-149` — covered by E-5 (env step) and E-2 (preflight)
- Once-per-process SqlServer probes — searched `static readonly .*Instance|Lazy` in `SqlServerMappingSchema.cs`, `SqlServerTypes.cs`, `SystemDataSqlServerAttributeReader.cs`: `SqlServerMappingSchema.cs:275`, `SqlServerTypes.cs:104`, `SystemDataSqlServerAttributeReader.cs:85-91` — covered by E-2 (per-mode capture check, TO-3)
- Remote client instantiation sites — searched `Type.GetType|ActivatorExt.CreateInstance` in `RemoteDataContextBase.cs`: `:136-143,:164,:195,:221,:258-272,:382-404,:486-548` — out-of-scope (exercised by TO-2, not edited)
- Client-side adapter loads — searched `ProviderAdapter` in `*MappingSchema*.cs`, `*SqlBuilder*.cs`, `*SqlOptimizer*.cs`, `*MemberTranslator*.cs`, `*DmlService*.cs`: mapping schemas `DuckDBMappingSchema.cs:31`, `DB2MappingSchema.cs:273,332`, `MySqlMappingSchema.cs:142-152`, `InformixMappingSchema.cs:130-132`, `ClickHouseMappingSchema.cs:869-871`, `SapHanaMappingSchema.cs:72`, `PostgreSQLMappingSchema.cs:202-214`; optimizer `DuckDBSqlOptimizer.cs:93`; builders only behind `DataProvider is X` (null on the client) — covered by E-2 (gates) and E-1 (parameterised case)
- `DuckDBSqlOptimizer.cs:93` reach not named in #6167 — deferred: propose a comment on #6167 (outward-facing, needs the user's go-ahead)
- HttpClient client JSON — searched `ReadFromJsonAsync|PostAsJsonAsync`: `HttpClientLinqServiceClient.cs:6-7,25,31,45,59,73` — covered by E-2 (#6168 gates)
- Server extension points — searched `CreateLinqService|CreateDataContext`: `LinqToDBController.cs:44-49` virtual, `LinqService.cs:64` virtual, precedent `TestHttpLinqServiceController.cs:8-10` — covered by E-2
- Configuration registry shared with Tests.Base — searched `AddOrSetConfiguration` in `Tests/Base`: `TestConfiguration.cs:111-140` — out-of-scope (D-2 does not use the registry)
- Examples Blazor WASM build — searched `BlazorWebAssembly` in `*.csproj`: `Examples/Remote/*/…Client.csproj:1`, built by `build.yml:174` — out-of-scope (unchanged)
- FPU JIT sweep input list — searched `ExpectedAssemblies`: applies to shipped `Source/` projects only (`testing.md:199`) — out-of-scope
- Corpus test docs — searched `testing.md` for the standalone-project sections (`:145-200`): no section for the new host — deferred: corpus doc after merge ("Running the WASM runtime tests": the script, the Node requirement, the bundle path)

## P8 Test obligations (M/L)

- TO-1 The CI job publishes four bundles and the trx lists cases for each of `Debug`, `TrimPartial`, `TrimFull`, `NoReflectionJson`; mutation "delete `.build/wasm/TrimPartial` before `dotnet test`" turns every `TrimPartial` case red with the bundle-missing message, none skipped — providers: matrix (all available) — proof: control
- TO-2 `ClientWorks` passes for every ungated (mode, configuration) and each case's report carries non-empty SQL for SELECT, parameterised SELECT, UPDATE and INSERT; mutation "throw in the app's UPDATE operation" turns every `ClientWorks` case red naming the UPDATE operation — providers: matrix minus #6167 set — proof: control
- TO-2b Each `ClientWorks` case meets its row's MERGE expectation; separates: ClickHouse.Octonica (`Throws`, builder at `ClickHouseSqlBuilder.cs:34`) and Oracle.Managed (`Generates`); mutation "flip ClickHouse.Octonica's row to `Generates`" turns that case red with `doesn't support SQL MERGE statement`; mutation "flip Oracle.Managed's row to `Throws`" turns that case red as an unexpected success — providers: matrix minus #6167 set — proof: control
- TO-3 `ResolveAttemptsAreCaptured(mode)` passes for `Debug` and `TrimPartial`: the mode's report (one process, U-21) contains a resolve attempt for `Microsoft.SqlServer.Types`, attributed to whichever SqlServer row ran first, and no case fails on it; mutation "remove the `AssemblyResolve` hook" turns it red in both modes — providers: the SqlServer rows of the matrix — proof: control
- TO-4 The SQLite.MS round trip returns exactly the two seeded rows (`Id` 1 and 2); mutation "server seeds no rows" turns it red with count 0 — providers: SQLite.MS — proof: control
- TO-5a `ClientLoadsProviderAssembly` cases are Inconclusive with `Cannot load assembly`; mutation "move PostgreSQL.15 from the #6167 set to `ClientWorks`" turns that case red with `Cannot load assembly Npgsql`; mutation "uncommitted `Source` edit special-casing the PostgreSQL namespace in `RemoteDataContextBase.GetMappingSchema` to `Instance`" turns the PostgreSQL gate red as passed-but-marked; the same simulated fix on a MySqlConnector row (whose MERGE expectation is `Throws`) also yields passed-but-marked, not a message mismatch — providers: #6167 set (measured) — proof: control
- TO-5b `ClientFailsUnderFullTrimming` cases are Inconclusive with `DeserializeNoConstructor`; mutation "publish `TrimFull` with `TrimMode=partial`" turns them red as passed-but-marked (except #6167 rows, which then fail with `Cannot load assembly` — recorded per row) — providers: matrix (all available) — proof: control
- TO-5c `ClientFailsWithoutReflectionJson` cases are Inconclusive with `JsonSerializerIsReflectionDisabled`; mutation "publish `NoReflectionJson` with reflection JSON enabled" turns them red — providers: matrix (all available) — proof: control
- TO-6 The guard test passes; mutation "remove the `Firebird.4` matrix row" turns it red naming `Firebird.4`; mutation "remove `MySql.8.0` from the alias list" turns it red naming `MySql.8.0` — providers: none (reflection over `ProviderName`) — proof: control
- TO-7 Mutation "uncommitted `Source` edit removing the SqlServer branch at `RemoteDataContextBase.cs:138`" turns the SqlServer `ClientWorks` cases red with `Cannot load assembly` for the SqlClient assembly; restored, green — providers: SqlServer.2022 (both client libraries) — proof: control
- TO-8 `UnavailableOnRunner` passes for each listed configuration (the preflight fails for it); mutation "add SQLite.MS to the unavailable list" turns it red as a stale exclusion; mutation "remove SqlCe from the current OS's list" turns SqlCe's `ClientWorks` case red with the preflight's server-side construction error, not a client error — providers: per-OS unavailable table (Windows locally, Linux on CI) — proof: control
- TO-9 `dotnet build linq2db.slnx -c Debug` compiles `Tests.Wasm`; `dotnet build linq2db.slnx -c Release` does not compile it (no `Tests.Wasm ->` line in the log); `linq2db.slnx` contains no `Tests.Wasm.App` entry — providers: none — proof: characterization (proves membership only)

## P9 Verification gates

- G-01: — (pending) each TO-n with its mutation recorded; local run on Windows, CI run of `wasm-tests` on Linux (blocked until CI)
- G-02: n/a — no `Source/` edit and the harness writes no baselines (`TestConfiguration.BaselinesPath` is never set by the host); confirm no `.build/.baselines` output after the local run
- G-05x: — (pending) `dotnet build Tests/Tests.Wasm/Tests.Wasm.csproj -c Release` and the `TrimPartial`/`TrimFull` publishes (Release) are analyzer-clean
- G-10x: — (pending) first CI run's `wasm-tests` wall-clock recorded and `timeout-minutes` re-set from it; locally, the four modes publish into four separate `.build/obj/Tests.Wasm.App_<mode>/` directories; `linq2db.dll`'s timestamp is unchanged between the two publishes of one configuration (its CoreCompile does not re-run); each bundle's `runtimeconfig.json` reflection flag and the presence of `linked/` match the D-6 table
- G-06: — (pending)
- G-07: — (pending)
- G-09: — (pending)

## P10 Adjudicated (M/L)

- Resolve attempts are reported, not failed (user decision 2026-10-26; D-8).
- Configurations share one Node process per mode (D-7); a masking static cache is possible in principle and accepted for runtime.
- Node is not a browser (D-1): browser-only fetch/CORS behaviour is out of reach; the `Request` shim is the only host adaptation and is commented in `main.mjs`.
- SignalR and gRPC remote clients are not exercised (P3); #6168's notes record them as unchecked.
- The job is not a required check, and the corpus gate lists are updated after merge (P7).

## P11 Amendments (M/L)

_None._

## P12 Critic verdict (M/L)

**Round 1 (2026-10-26, plan-critic on `fable`; `fable` contributed no design input earlier in the session): refuted.**

- refuted — SC-2's uniform MERGE operation is unsatisfiable: `ClickHouseSqlBuilder.cs:34` (and MySql, YDB, SQLite, Access, SqlCe builders) throw client-side, so an ungated ClickHouse.Octonica case was red by construction, and a #6167 fix on MySql rows would show as a message mismatch. → SC-2 split into SC-2 (SELECT / parameterised SELECT / UPDATE / INSERT) and SC-2b (per-row MERGE expectation, both directions asserted), U-20, TO-2b, D-5 note, TO-5a extended; P1 narrowed to the measured SELECT.
- weak — TO-3 pinned a once-per-process probe to one row. → U-21, TO-3 asserts per mode.
- weak — a global `-p:IntermediateOutputPath` rebuilt the whole graph into one obj (critic read `wasm-spike/obj-partial/`). → U-5 corrected, D-6 rewritten: `WasmBundleMode` + app-local `ArtifactsProjectName` + `GlobalPropertiesToRemove`; G-10x measures the layout and the CI duration.
- weak — `Sybase` / `Informix` sat in both the alias and the unavailable tables. → D-3: unavailable rows on every OS.
- lead — DB2 / Informix.DB2 on Linux need the clidriver env; a server-side failure would have reached a client gate. → U-22, E-5 env step, D-7 in-process preflight, TO-8 wording.
- weak (minor) — `Build Project="false"` still restores; TO-9's "absent from the log" was untestable. → U-23, D-9: app out of the solution, TO-9 reworded.
- What the critic searched: `BuildMergeStatement` / MERGE refusals across `Source/LinqToDB/Internal`; `ToSqlQuery` and `QueryType.Merge` dispatch; SqlServer probe statics; `ActiveIssueAttribute.cs` in full, `NUnitUtils.cs`, `ThrowsWhenAttribute.cs` (U-6 and the D-5 gate semantics hold); the installed SDK's Blazor targets; `ProviderName.cs` in full; `LD_LIBRARY_PATH|clidriver` in `Build/`; the spike artifacts.

**Round 2 (2026-10-26, same critic, resumed with its round-1 context): refuted.**

- refuted — the WebAssembly SDK publishes trimmed in every configuration (`Sdks/Microsoft.NET.Sdk.WebAssembly/Sdk/Sdk.props:20`, re-checked by the author in the installed SDK 10.0.403), so the `Debug` / `NoReflectionJson` publishes were trimmed and `NoReflectionJson`'s "unset" flag would mean enabled once trimming is off; the spike's untrimmed evidence was a build. → U-4 reworded; D-6 table sets `PublishTrimmed` per mode and `JsonSerializerIsReflectionEnabledByDefault=false` explicitly for `NoReflectionJson`; G-10x checks each bundle's runtimeconfig flag and `linked/`.
- weak — `-o` makes `PublishDir` global, so `LinqToDB` is a distinct project instance per mode. → `PublishDir` derived inside the csproj, no `-o`; G-10x defines "one build" as an unchanged `linq2db.dll` timestamp.
- weak — the MERGE shape was unspecified; delete/by-source operations and an empty source throw elsewhere. → SC-2b fixes the shape.
- lead — `clidriver/` in the host output is unverified on Linux. → E-5 step fails loudly on a missing directory.
- Upgraded by the critic: the `ArtifactsProjectName` mechanism is resolved-by precedent (`Examples/Directory.Build.props:11`, `UseArtifactsOutputPath.props:20-34`); D-7's preflight and D-9 hold.
- What the critic searched: `PublishTrimmed|TrimMode` across the WebAssembly / Blazor SDKs and the cached ILLink targets; the spike build log; the artifacts-path props in full; `GlobalPropertiesToRemove` in `Microsoft.Common.CurrentVersion.targets`; the six MERGE refusal sites and `BasicSqlBuilder.Merge.cs:109-400`.

**Round 3 (2026-10-26, user-requested beyond the one-round cap, same critic): weak.**

- weak — E-1's derived-property list lagged D-6 (no `PublishTrimmed` / `PublishDir`). → E-1 reconciled.
- lead — the `Tests/Directory.Build.props:31-34` package pins reach the app and were never restored for `browser-wasm`. → added to the P7 build-props row, settled by G-10x.
- lead (minor) — `wwwroot/main.mjs` placement unlabelled. → U-24.
- Held, with the critic's evidence: project-body `PublishDir` reaches the same publish path as `-o` (`Microsoft.NET.Sdk.BeforeCommon.targets:127-137`, `Microsoft.NET.DefaultOutputPaths.targets:82`); `linked/` exists only under `PublishTrimmed=true` (`Microsoft.NET.ILLink.targets:17,97-100`; `Microsoft.NET.Sdk.WebAssembly.Browser.targets:592,822` treats `PublishTrimmed=false` as a first-class path); G-10x's runtimeconfig is the boot config's input (`Browser.targets:835`); `NoReflectionJson`'s explicit `false` follows the same path as the measured ILLink default; one `LinqToDB` build per configuration once `-o` is gone; the SC-2b MERGE shape avoids `BasicSqlBuilder.Merge.cs:177-193,268`; E-5's `test -d` is a loud negative.

Carried forward as weak with the three items above folded in; no objection outstanding.
