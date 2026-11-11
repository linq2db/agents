---
area: TESTS-WASM
kind: area-index
sources: [code]
confidence: high
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
coverage_tier_1: 6/6
coverage_tier_2: 2/2
---

# TESTS-WASM

Regression guard for #5158 / #5159 (`Tests/Tests.Wasm/WasmRuntimeTests.cs:23`): the remote HTTP client (`LinqToDB.Remote.HttpClient.Client`) running inside the browser-wasm .NET runtime, hosted by Node, against an in-process Kestrel server. No database is involved: the client only fetches `GetInfo` and generates SQL client-side, so the check is "does the client work, trim, and serialize under WASM", not "does the query run".

Two projects: `Tests/Tests.Wasm.App` (the app compiled to a browser-wasm bundle, never run by NUnit directly) and `Tests/Tests.Wasm` (NUnit host plus the server, `net10.0`, `linq2db.Tests.Wasm`). The host never references the app project: bundles are published out of band by `publish-wasm-bundles.ps1` into `.build/wasm/<mode>/` and the host only launches `node` on them.

## Subsystems

### 1. Bundle publishing (`publish-wasm-bundles.ps1`, `Tests.Wasm.App.csproj`, `Directory.Build.props`)

- `publish-wasm-bundles.ps1` runs one `dotnet publish Tests/Tests.Wasm.App/Tests.Wasm.App.csproj --configuration <cfg> -p:WasmBundleMode=<mode>` per mode (`Tests/Tests.Wasm/publish-wasm-bundles.ps1:72`). Default is all four modes, `-Mode A,B` selects a subset (comma-split manually because `pwsh -File` passes it as one string).
- Four modes (script table `publish-wasm-bundles.ps1:36-41`, MSBuild groups `Tests.Wasm.App.csproj:24-44`):

| Mode | Configuration | Trimmed | Reflection-based JSON |
|---|---|---|---|
| `Debug` | Debug | no | on |
| `TrimPartial` | Release | yes, `TrimMode=partial` | on |
| `TrimFull` | Release | yes, `TrimMode=full` | on |
| `NoReflectionJson` | Debug | no | off (`JsonSerializerIsReflectionEnabledByDefault=false`) |

- Output dir: `PublishDir = .build/wasm/$(WasmBundleMode)/` (`Tests.Wasm.App.csproj:17`). `Directory.Build.props:9` sets `ArtifactsProjectName = <project>_<mode>` so each mode has its own obj/bin and never reuses another mode's trimmed output. It must be set there, before the SDK derives `BaseIntermediateOutputPath`. `WasmBundleMode` defaults to `Debug`, and `CheckWasmBundleMode` (`Tests.Wasm.App.csproj:55`) fails the build for unknown values.
- The WebAssembly SDK trims every publish unless `PublishTrimmed` is set explicitly, hence the explicit `false` in the Debug and NoReflectionJson groups.
- Staleness guards: every mode's output dir is deleted first (a mode left out of `-Mode` is reported missing by the host rather than run from an old publish, `publish-wasm-bundles.ps1:52-58`). The ILLink `linked` dir under `.build/obj/Tests.Wasm.App_<mode>/<cfg>/browser-wasm/linked` is cleared before each publish and then its presence proves trimming happened. After publishing, the script verifies `wwwroot/main.mjs` exists, trimmed-ness matches the mode, and `linq2db.Tests.Wasm.App.runtimeconfig.json` has the expected `System.Text.Json.JsonSerializer.IsReflectionEnabledByDefault`. Exit 1 on any mismatch.
- The app project references only `LinqToDB.Remote.HttpClient.Client` (with `GlobalPropertiesToRemove="WasmBundleMode"`), sets `SuppressTrimAnalysisWarnings` (trim cleanliness of linq2db is #6168 / AOT work), and removes the Tests-wide `BannedSymbols.txt` because the app writes to `System.Console`.

### 2. The WASM app (`Tests.Wasm.App/Program.cs`, `wwwroot/main.mjs`)

- `wwwroot/main.mjs` is the Node entry: boots `dotnet` from `./_framework/dotnet.js`, patches `globalThis.Request` so `new Request("")` (the streaming-request feature check) resolves under Node where `location` is absent, then `runMain('linq2db.Tests.Wasm.App', process.argv.slice(2))`. It flushes stdout before `process.exit` because POSIX pipes are asynchronous.
- `Program.Main` (`Program.cs:21`) takes `<server url> <round-trip configuration> <configuration>...` (exit 2 on fewer than 3 args). For each configuration it builds an `HttpClientDataContext(serverUrl, WasmReport.Route, o => o.UseConfiguration(configuration))` and calls `InitHttpClientAsync` first, because sync APIs block on the single-threaded runtime.
- Operations per configuration, each caught individually into an `Operation(Name, Result, Error)`: `Init`, `Select`, `SelectParameterized`, `Update`, `Insert`, `Merge` (`Program.cs:101-144`). All except `Init` end in `ToSqlQuery().Sql`, so the result is generated SQL text. `Merge` uses a non-empty source with `UpdateWhenMatched` + `InsertWhenNotMatched` only. For the round-trip configuration an extra `RoundTrip` op reads `WasmPerson` ordered by id and returns ids joined by comma.
- An `AppDomain.AssemblyResolve` handler records failed assembly names into `_resolveAttempts` (reported per configuration, never failed) because the SqlServer mapping schema probes optional assemblies on purpose.
- A configuration-level exception is recorded as an `Unexpected` operation so the configuration still gets a report line. Main returns 0 regardless: the host decides what is red.
- Reports are written with `Utf8JsonWriter` rather than `JsonSerializer` (`Program.cs:175`) because NoReflectionJson disables reflection serialization and TrimFull trims the metadata it needs. One line per configuration on stdout, prefixed `L2DB-WASM-REPORT `.
- `WasmReport.cs` is the shared contract (compiled into both app and host via `<Compile Include ... Link>` in `Tests.Wasm.csproj:18-19`): route `api/linq2db`, report prefix, operation names, JSON property names. `WasmPerson.cs` is the shared `[Table]` entity (`Id`, `Name`, `BirthDate`).

### 3. NUnit host (`WasmRuntimeTests.cs`, `WasmBundleRunner.cs`, `WasmServer.cs`)

- `WasmServer.StartAsync` (`WasmServer.cs:41`): creates a shared-cache in-memory SQLite `DataConnection` (kept alive for the round trip), creates and seeds `WasmPerson` (ids 1, 2), then starts a `WebApplication.CreateSlimBuilder()` Kestrel on `http://127.0.0.1:0` (ephemeral port, read back from `IServerAddressesFeature`). Application parts are cleared and reset to this assembly only, because referenced test assemblies carry other `LinqToDBController` subclasses. `WasmLinqController` (`WasmServer.cs:116`, public because MVC discovers public controllers only) is routed at `WasmReport.Route`.
- `MatrixLinqService : LinqService` overrides `CreateDataContext(configuration)` to map the configuration name to a `MatrixRow` and build a `DataConnection` with `row.CreateProvider()` explicitly, so no provider detection or connection opening takes place. The round-trip row gets the real SQLite connection string, all others a dummy string (`GetInfo` never opens).
- `WasmBundleRunner.RunAsync` (`WasmBundleRunner.cs:35`): resolves `.build/wasm/<mode>/wwwroot/main.mjs` from the repo root (found via `TestUtils.TryFindRepoRoot`, throws if `linq2db.slnx` is not above), fails with the publish command if the bundle is missing, spawns `node main.mjs <server> <roundtrip> <configs...>`, 2 minute timeout (`Timeout`, kills the process tree), parses stdout lines starting with `WasmReport.Prefix` into `ConfigurationReport` records, and returns a `ModeRun` with exit code, timeout flag and a log of the remaining stdout/stderr.
- `WasmRuntimeTests` (`[TestFixture]`, #5159) in `[OneTimeSetUp]` starts the server and runs a per-row preflight: construct the provider in-process and call `Service.GetInfoAsync(configuration)`. The error (or null) is stored in `_preflight`, so a provider that cannot load on the runner is never blamed on the client. One node run per mode is cached in `_runs` (`GetRunAsync`) and covers every available, preflight-clean configuration. Test cases:

| Test | Modes / rows | Notes |
|---|---|---|
| `ClientWorks` | Debug, TrimPartial x rows without `LoadsProviderAssembly` | the green path |
| `ClientLoadsProviderAssembly` | Debug, TrimPartial x rows with `LoadsProviderAssembly` | `[ActiveIssue(6167)]` "Cannot load assembly" |
| `ClientFailsUnderFullTrimming` | TrimFull x all rows | `[ActiveIssue(6168)]` "DeserializeNoConstructor" |
| `ClientFailsWithoutReflectionJson` | NoReflectionJson x all rows | `[ActiveIssue(6168)]` "JsonSerializerIsReflectionDisabled" |
| `UnavailableOnRunner` | rows with `!IsAvailable` | asserts the preflight error does contain "Cannot load assembly" and the listed assembly, so a stale exclusion goes red |
| `ResolveAttemptsAreCaptured` | Debug, TrimPartial | some report has a `Microsoft.SqlServer.Types*` resolve attempt |
| `BundleExitsCleanly` | all four modes | no timeout, exit code 0 |
| `MatrixRowsConstructTheirProvider` | all rows | constructed provider name (plus SqlServer client library for `.MS` rows) equals the row's expected one |
| `ProviderNamesAreCovered` | matrix | every public `ProviderName` constant has a row or an `Aliases` entry, no dup configurations, `UnavailableOn` consistent with assembly/reason |

- `AssertClientAsync` (`WasmRuntimeTests.cs:208`): server preflight errors and missing reports are printed to `TestContext.Out` and then thrown as `ShouldAssertException` (not rethrown raw, so a "Cannot load assembly" text cannot accidentally match an `[ActiveIssue]` gate). Per operation: no `Error`, non-blank SQL (except `Init`/`RoundTrip`). `Merge` on a `MergeOutcome.Throws` row must fail with "doesn't support SQL MERGE statement". The operation name list must equal `Init, Select, SelectParameterized, Update, Insert, Merge` (plus `RoundTrip` for the round-trip configuration, whose result must be `"1,2"`).
- Empty `[SetUp]` (`WasmRuntimeTests.cs:78`) exists so `[ActiveIssue]` can rewrite a result (#6174).

## Provider matrix (`ProviderMatrix.cs`)

`ProviderMatrix.Rows` is a hand-written list of 61 `MatrixRow(Configuration, ProviderName, CreateProvider, Merge, LoadsProviderAssembly, UnavailableOn, UnavailableAssembly, UnavailableReason)` records. A row is a configuration name the client sends plus a factory that constructs the exact provider server-side.

- Families and counts: Access (4: Jet/Ace x OleDb/ODBC), DB2 (2: LUW, `DB2.zOS` keyed without '/' because of #6176), Firebird (4: 2.5-5), Informix (2), SqlServer (16: 2005-2025, each with System.Data and `.MS` Microsoft.Data client), MySql/MariaDB (6: MySql.Data and MySqlConnector), Oracle (6: v11 and v12 x Native/Managed/Devart), PostgreSQL (9: 9.2-19), SqlCe (1), SQLite (2: Classic, MS), Sybase (2), SAP HANA (2), ClickHouse (3), YDB (1), DuckDB (1).
- Round trip: `RoundTripConfiguration = ProviderName.SQLiteMS` is the only row that touches a real DB (in-memory SQLite, `SqliteConnectionString`).
- `MergeOutcome`: `Refused` for builders that throw "doesn't support SQL MERGE statement" (Access, ClickHouse, MySql, SQLite, SqlCe, Ydb families), `Built` otherwise.
- `LoadsProviderAssembly` marks rows whose client library is loaded by the client side (DB2, InformixDB2, MySql family, PostgreSQL, ClickHouse driver, DuckDB). These are the ones gated on #6167.
- Unavailable on every OS (`RunnerOS.Any`, 6 rows): `Informix` (IBM.Data.Informix, net462 only), `Oracle11Native` and `OracleNative` (Oracle.DataAccess, net462 only), `SqlCe` (not a package), `Sybase` native (not referenced, factory goes through `DataConnection.GetDataProvider("Sybase.Native", ...)` because of #6177), `SapHanaNative` (SAP NuGet not referenced). `IsAvailable` is `(UnavailableOn & CurrentOS) == 0`.
- `Aliases` lists `ProviderName` constants that are families or aliases needing detection (a connection) and therefore have no row.

## CI wiring

- Job `wasm-tests` ("WASM runtime tests") in `.github/workflows/build.yml:281`, `ubuntu-24.04`, 20 minute timeout. It is a regression guard for #5158 / #5159 and needs no database.
- Steps: setup-dotnet 10.x, setup-node 24, `pwsh -NoProfile -File Tests/Tests.Wasm/publish-wasm-bundles.ps1` (all four modes), `dotnet build Tests/Tests.Wasm/Tests.Wasm.csproj --configuration $TEST_CONFIGURATION`, then a step that puts the IBM DB2 `clidriver` (copied into `.build/bin/Tests.Wasm/<cfg>/clidriver`) on `PATH` and `LD_LIBRARY_PATH` (DB2 and Informix.DB2 load native libraries, mirroring `Build/Azure/scripts/db2.provider.sh`), then `dotnet test --project Tests/Tests.Wasm/Tests.Wasm.csproj ... --no-build --report-trx --report-trx-filename wasm.trx`, and an always-run upload of `WasmTestResults/*.trx` as artifact `wasm-test-results`.
- Grep of `Build/` (Azure pipelines) for "wasm" finds nothing: the area runs on GitHub Actions only. `linq2db.slnx:438` lists `Tests/Tests.Wasm/Tests.Wasm.csproj`. `Tests.Wasm.App` is intentionally not in the solution (built only by the publish script).
- Locally: publish first (`pwsh -NoProfile -File Tests/Tests.Wasm/publish-wasm-bundles.ps1`), Node.js must be on `PATH`, then run the `Tests.Wasm` project. A missing bundle gives an `InvalidOperationException` with the publish command.

## Files (Tier 1 / Tier 2)

Tier 1 (6, all read in full): `Tests/Tests.Wasm/WasmRuntimeTests.cs`, `Tests/Tests.Wasm/WasmBundleRunner.cs`, `Tests/Tests.Wasm/WasmServer.cs`, `Tests/Tests.Wasm/ProviderMatrix.cs`, `Tests/Tests.Wasm/publish-wasm-bundles.ps1`, `Tests/Tests.Wasm.App/Program.cs`.

Tier 2 (`**/*.cs`, 2, all read): `Tests/Tests.Wasm.App/WasmPerson.cs`, `Tests/Tests.Wasm.App/WasmReport.cs`.

Not matched by the Tier-2 glob but read for this index (4 non-`.cs` files, not counted): `Tests/Tests.Wasm/Tests.Wasm.csproj`, `Tests/Tests.Wasm.App/Tests.Wasm.App.csproj`, `Tests/Tests.Wasm.App/Directory.Build.props`, `Tests/Tests.Wasm.App/wwwroot/main.mjs`.

## Inbound / outbound dependencies

**Outbound:**

- `Source/LinqToDB.Remote.HttpClient.Client` (app) and `Source/LinqToDB.Remote.HttpClient.Server` (host): `HttpClientDataContext`, `LinqService`, `LinqToDBController`, `ILinqService`. See [`areas/REMOTE/INDEX.md`](../REMOTE/INDEX.md) if that area exists in this KB.
- Every provider tools class (`AccessTools`, `DB2Tools`, `FirebirdTools`, `InformixTools`, `SqlServerTools`, `MySqlTools`, `OracleTools`, `PostgreSQLTools`, `SqlCeTools`, `SQLiteTools`, `SybaseTools`, `SapHanaTools`, `ClickHouseTools`, `YdbTools`, `DuckDBTools`) and several `LinqToDB.Internal.DataProvider.*` adapters (assembly-name constants) for `ProviderMatrix`.
- `Tests/linq2db.TestProjects.props`, `TestUtils.TryFindRepoRoot`, `ActiveIssue` attribute, NUnit, Shouldly.
- `ProviderName` constants: a new provider name must get a matrix row or an `Aliases` entry or `ProviderNamesAreCovered` fails.

**Inbound:** only the `wasm-tests` CI job and the solution file. Nothing depends on these projects.

## Known issues / debt

- `[ActiveIssue(6167)]` "Cannot load assembly" for client libraries loaded in the WASM runtime (`LoadsProviderAssembly` rows), `[ActiveIssue(6168)]` for TrimFull (`DeserializeNoConstructor`) and NoReflectionJson (`JsonSerializerIsReflectionDisabled`). A fix to #6168 will expose #6167 on the `LoadsProviderAssembly` rows under those modes (comment at `WasmRuntimeTests.cs:105`), so the cases must be split then.
- #6176: the client does not escape the configuration name in the request path, so `DB2.zOS` is used in place of `DB2.z/OS`. #6177: `SybaseTools.GetDataProvider(Unmanaged)` returns the managed provider when the native assembly is absent. #6174: `[ActiveIssue]` rewrites a result only if a SetUp command has turned the exception into one.
- Six unavailable rows are excluded permanently on all runner OSes and are verified by `UnavailableOnRunner`, so they never exercise the client. Native-library rows (DB2) depend on the CI `clidriver` step.
- The matrix is hand-maintained (61 rows): adding a provider version requires editing `ProviderMatrix.cs` by hand, guarded only by `ProviderNamesAreCovered` at the name level, not the version level.
- Tier-1 list was provisional when the area was added (kb-areas.md): this pass confirms the six anchors.

## See also

- [`areas/TESTS-BENCHMARKS/INDEX.md`](../TESTS-BENCHMARKS/INDEX.md) -- other non-`Tests.Linq` test-side harness.
- `.github/workflows/build.yml` job `wasm-tests`.
- Issues #5158, #5159 (origin), #6167, #6168, #6174, #6176, #6177.

<details><summary>Coverage</summary>

Tier 1: 6 / 6 files read in full (`WasmRuntimeTests.cs`, `WasmBundleRunner.cs`, `WasmServer.cs`, `ProviderMatrix.cs`, `publish-wasm-bundles.ps1`, `Tests.Wasm.App/Program.cs`).

Tier 2: 2 / 2 files read (`WasmPerson.cs`, `WasmReport.cs`). The area has 12 files: 6 Tier 1, 2 Tier-2 `.cs`, and 4 non-`.cs` files outside the Tier-2 glob (two `.csproj`, `Directory.Build.props`, `wwwroot/main.mjs`) that were read as well and are not counted in the Tier-2 numbers.

Other reads: `.github/workflows/build.yml` lines 270-319 (the `wasm-tests` job), Grep for "wasm" over `.github`, `Build/` (no matches) and `*.slnx/*.slnf/*.yml/*.props` (only `linq2db.slnx:438`).

Confidence `high`: every Tier-1 file read in full, all claims cited to source. Counts (61 rows, 6 unavailable) were tallied by hand from `ProviderMatrix.cs`.

</details>
