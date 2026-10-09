---
area: BUILD
kind: area-index
sources: [code]
confidence: high
last_verified: 2026-10-09
last_verified_sha: 05150894edc2511f0dd0bc7829b2a309cec36ec9
coverage_tier_1: 3/4
coverage_tier_2: 115/115
---

# BUILD

CI and build infrastructure for linq2db. Controls: TFM matrix, feature flags, versioning, analyzer gating, SDK pinning, solution shape, the provider test matrix (now consolidated into ~22 multi-database legs, run on Azure Pipelines and, for most Linux legs and docker-free Windows legs, on GitHub Actions), third-party license notices, and GitHub issue triage forms. Azure Pipelines remains the release/publish CI; GitHub Actions workflows (`.github/workflows/`) now carry the database-free PR build and the offloaded test legs.

## Key types

This area has no C# types. Its artifacts are MSBuild/YAML/shell/PowerShell configuration files.

## Files (Tier 1 / Tier 2)

**Tier 1:**

| File | Role |
|---|---|
| `Directory.Build.props` | Global MSBuild anchor: TFMs, version numbers, feature flags, analyzer gating, polyfills, NuGet metadata, assembly signing. Imported by every project in the solution. |
| `global.json` | SDK pin: .NET 10.0.100 with `rollForward: latestFeature`, `allowPrerelease: false`. Also pins the `dotnet test` CLI to the `Microsoft.Testing.Platform` (MTP) native runner via `"test": {"runner": "Microsoft.Testing.Platform"}`. |
| `linq2db.slnx` | Solution file (VS 2022 XML format). Lists all projects across 7+ folders. |
| `Build/BannedSymbols.txt` | **MISSING** -- the actual banned-API list is at `Source/BannedSymbols.txt`. |

**Tier 2 (all read or characterized):** `Build/Azure/pipelines/*.yml` (3 top-level + 9 templates incl. new `test-cli.yml`; `test-workflow-macos.yml` deleted), `Build/Azure/scripts/*.ps1` (`verify-nuget-sizes.ps1`, `ensure-baselines-branch.ps1`, plus new `mssql-container.ps1`, `publish-azure-artifacts.ps1`, `ramdisk.ps1`, `third-party-notices.ps1`, `verify-analyzer-delivery.ps1`) + `*.sh` (consolidated; see test-matrix section), `.github/workflows/*.yml` (4, new), `.github/ISSUE_TEMPLATE/*.yml` (13), `.github/copilot-instructions.md`, `Build/CI/*` (8, new), `Build/licenses/*` (README, `components.json`, 16 generated notices, 31 license texts; new), `Data/Create Scripts/DuckDB.sql`, `.editorconfig` (root), `Build/Azure/scripts/db2.provider.sh`, `Build/Azure/net{80,90,100,fx}/*.json` provider-activation configs, `Build/Azure/README.md`.

## Subsystems

### TFM matrix and feature flags (`Directory.Build.props`)

`<TargetFrameworks>net462;netstandard2.0;net8.0;net9.0;net10.0</TargetFrameworks>` -- applies to all projects unless overridden. The `Testing` configuration pins to `net10.0` only for fast iteration.

Feature flags are `DefineConstants` conditioned on `IsTargetFrameworkCompatible(..., net8.0)` (or `net472` for `SUPPORTS_READONLY`):

| Flag | Meaning |
|---|---|
| `SUPPORTS_COMPOSITE_FORMAT` | `CompositeFormat` type available |
| `SUPPORTS_DATEONLY` | `DateOnly` + `TimeOnly` types available |
| `SUPPORTS_ENSURE_CAPACITY` | `List.EnsureCapacity`, `Enumerable.TryGetNonEnumeratedCount` |
| `ADO_ASYNC` | Async transaction/connection APIs (`DbConnection.CloseAsync`, etc.) |
| `ADO_IS_TRANSIENT` | `DbException.IsTransient` |
| `SUPPORTS_SPAN` | `Span<T>` operations |
| `SUPPORTS_READONLY` | `IsReadOnlyAttribute` (net8+ or net472) |
| `SUPPORTS_REGEX_GENERATORS` | Source-generated regex |
| `SUPPORTS_INT128` | `(u)int128` types |

All flags gated on `net8.0` compatibility; `netstandard2.0` and `net462` receive none of them.

### Version variables (`Directory.Build.props`)

| Property | Value | Notes |
|---|---|---|
| `<Version>` | `6.6.0` | Main product version (6.3.0 -> 6.4.0 -> 6.6.0) |
| `<EF3Version>` | `3.35.0` | EF Core 3.x package |
| `<EF8Version>` | `8.9.0` | EF Core 8.x package |
| `<EF9Version>` | `9.8.0` | EF Core 9.x package |
| `<EF10Version>` | `10.7.0` | EF Core 10.x package |
| `<BaselineVersion>` | `6.0.0` | API compatibility baseline |
| `<EF3BaselineVersion>` / `<EF8BaselineVersion>` / `<EF9BaselineVersion>` / `<EF10BaselineVersion>` | `3.28.0` / `8.2.0` / `9.1.0` / `10.0.0` | Per-EF API compatibility baselines |

`<VersionSuffix>` defaults to `-local.1` and `<ApplyVersionSuffix>` defaults to `true`. CI stamps `-dev.<BuildId>` (Azure) / `-dev.<run_number>` (GitHub) on every branch except `release`, where `ApplyVersionSuffix=false`.

### Roslyn analyzer gating (`Directory.Build.props`, `Source/Directory.Build.props`)

`<RunAnalyzersDuringBuild>` is `false` by default and enabled only when `$(Configuration) == Release`. `<EnforceCodeStyleInBuild>` is likewise `false` by default and enabled only when `$(Configuration) == Release` -- as of PR #5523, IDE-style analyzers are now Release-only in both properties. `<TreatWarningsAsErrors>true` is unconditional. `<WarningLevel>9999</WarningLevel>` activates all Roslyn warnings. `<AnalysisLevel>preview-All</AnalysisLevel>` pulls in preview analyzers.

Analyzers added globally via `<PackageReference>` in `Directory.Build.props`: `AsyncFixer`, `Lindhart.Analyser.MissingAwaitWarning`, `Meziantou.Analyzer`, `Microsoft.CodeAnalysis.BannedApiAnalyzers`, `Microsoft.SourceLink.GitHub`.

`RunApiAnalyzersDuringBuild` is opt-in per-project.

`<NoWarn>` gained `MA0202;MA0209;MA0210` (build-time cost: MA0209/MA0210 cost ~275 s/build for 2 trivial findings, MA0202 ~100 s for 1). A comment in the props records that `NoWarn` -- not `severity=none` in `.editorconfig` -- is what reclaims the time, because a disabled analyzer still executes (measured on 6.4.0: disabled MA0204 still cost 3.6 s).

### EditorConfig analyzer rules (`.editorconfig`)

The root `.editorconfig` governs the full analyzer diagnostic severity catalog for all `*.{cs,vb}` files. Key structure:

- Global `dotnet_analyzer_diagnostic.severity = error` enables all analyzers by default for source files.
- **Public API analyzers** (RS0016--RS0061): most set to `error`; RS0026/RS0027/RS0041/RS0051/RS0056 set to `none`.
- **Active diagnostics** (explicitly configured): CS8618, CS4014, CS1998; CA1018/CA1050/CA1200/CA1305/CA1507/CA1510--CA1513/CA1725/CA1805/CA1823/CA1825--CA1830/CA1834/CA1836/CA2007/CA2012/CA2016/CA2101/CA2200/CA2201/CA2208/CA2215; IDE0001--IDE0003/IDE0009/IDE0036/IDE0047/IDE0048/IDE0051/IDE0052/IDE0060/IDE0070/IDE0330; `LindhartAnalyserMissingAwaitWarningVariable`; AsyncFixer02--06.
- **Meziantou.Analyzer active rules**: MA0044/MA0047/MA0048/MA0056/MA0069/MA0075/MA0076/MA0079/MA0080/MA0106/MA0107/MA0129/MA0151, plus the full MA0008--MA0200 catalog introduced for `Meziantou.Analyzer` 3.0.85 (each entry individually configured with rationale comments for `none` cases -- e.g. MA0032 disabled for no-token public overloads, MA0104 disabled for `DataType` enum clash, MA0137/MA0138 disabled for `IAsyncEnumerable` naming conflicts, MA0191 disabled for 438 deliberate `!` uses in NRT escape hatches).
- **Inactive diagnostics** (not reviewed yet): large catalog including CA1001/CA1501--CA1509/CA1816/CA2000/CA2231/CA3076; IDE0004/IDE0005/IDE0055/IDE0370/SYSLIB1054; MA0002/MA0009/MA0016/MA0018/MA0036/MA0038--MA0042/MA0045--MA0046/MA0051/MA0071/MA0099/MA0101/MA0110/MA0113/MA0127/MA0136/MA0159/MA0165/MA0182/MA0185/MA0190/MA0193/MA0197.
- **Test overrides** (`Tests/**.{cs,vb}`): relaxes ~60 rules including IDE0001/IDE0039/IDE0004/IDE0051/IDE0078/IDE0083; CA1027/CA1044/CA1050/CA1304/CA1305/CA1307/CA1309/CA1310/CA1311/CA1515/CA1802/CA1812/CA1827/CA1829/CA1849/CA1847/CA1851/CA1852/CA1858/CA1860/CA1861/CA1862/CA1866/CA2007/CA2237; MA0001/MA0002/MA0004/MA0005/MA0006/MA0007/MA0009/MA0011/MA0020/MA0021/MA0023/MA0028--MA0031/MA0044/MA0047/MA0048/MA0053/MA0062/MA0063/MA0073--MA0080/MA0089/MA0095/MA0097/MA0098/MA0107/MA0111/MA0112/MA0132/MA0133/MA0150/MA0169/MA0172/MA0175/MA0176/MA0186; SYSLIB1045; NUnit2045; AsyncFixer01/02/04/06.
- ReSharper properties: `resharper_csharp_allow_far_alignment = true`, `resharper_int_align_switch_sections = true` (preserve column-aligned formatting in VS/Rider).

### Banned-API enforcement (`Source/BannedSymbols.txt`)

287-line list consumed by `Microsoft.CodeAnalysis.BannedApiAnalyzers`. Key ban categories:

- **Flawed concurrent collections**: `ConcurrentBag<T>` banned (PR #2066).
- **ADO.NET interfaces**: All `IDataReader`, `IDbCommand`, `IDbConnection`, etc. banned; use `DbDataReader`, `DbCommand`, `DbConnection`.
- **Attribute reflection without cache**: All `GetCustomAttribute`/`GetCustomAttributes`/`IsDefined` direct calls banned; use `AttributesExtensions.GetAttribute<T>()`.
- **Culture-dependent formatting**: Parameterless overloads of `DateTime.ToString`, `Decimal.Parse`, `String.Format`, `StringBuilder.Append`, `Convert.ToString` banned.
- **Expression.Compile direct call**: `LambdaExpression.Compile()` banned; use `CompileExpression` extension.
- **Reflection invocation**: `MethodBase.Invoke`, `Activator.CreateInstance`, `Delegate.DynamicInvoke` banned.
- **DbCommand.Dispose direct**: `DbCommand.DisposeAsync`/`Component.Dispose` banned; use `IDataProvider.DisposeCommandAsync`/`DisposeCommand`.
- **CurrentCulture string.IndexOf**: `string.IndexOf(string)` without `StringComparison` banned (issue #5188).
- **Type.GetInterfaceMap**: Banned; use `GetInterfaceMapEx` extension.

### Polyfills (`Directory.Build.props`)

`Meziantou.Polyfill` is configured via `<MeziantouPolyfill_IncludedPolyfills>`. Polyfills span: `System.Diagnostics.CodeAnalysis`, `HashCode`, `Index`/`Range`, `System.Threading.Lock`, `ArgumentNullException.ThrowIfNull`, `ArgumentException.ThrowIfNullOrEmpty/WhiteSpace`, `ArgumentOutOfRangeException.ThrowIf*`, `ObjectDisposedException.ThrowIf`, `Enum.GetNames<T>`, `AsyncEnumerable.FirstAsync/SingleAsync/ToArrayAsync/ToListAsync`. Added since the prior run: `T:System.Reflection.Nullability` (prefix covers `NullabilityInfo`/`NullabilityInfoContext`/`NullabilityState`; replaces the `Nullability.Source` package) and `Enumerable.ToHashSet(IEnumerable, IEqualityComparer)`.

### `global.json` -- SDK pin and test runner

`sdk.version: "10.0.100"`, `rollForward: "latestFeature"`, `allowPrerelease: false`. (Prior runs recorded `10.0.200` / `minor`; the file now carries an inline `//` comment explaining the change: `minor` prefers the highest patch of the requested feature band (10.0.2xx) over rolling forward, so on a machine with 10.0.2xx and 10.0.4xx side by side it picks 2xx, whose Roslyn is 5.3, while `CodeGenerators` is built against Roslyn 5.6 and fails to load with CS9057. `latestFeature` takes the newest installed 10.0.x.) This is load-bearing on GitHub Actions, where `setup-dotnet` installs alongside preinstalled SDKs instead of isolating them like Azure's `UseDotNet@2`.

Adds `"test": { "runner": "Microsoft.Testing.Platform" }` -- pins the `dotnet test` CLI to the MTP-native test host instead of legacy VSTest. Consequence: `dotnet test` needs `--project <csproj>`; a bare project path is rejected (see the `analyzer-tests` job comment in `.github/workflows/build.yml`). This is also the switch that makes the CI-side MTP argument changes (see "CI test invocation" subsystem below) apply to local `dotnet test` invocations too.

### Solution shape (`linq2db.slnx`)

Four build configurations: `Azure`, `Debug`, `Release`, `Testing`. Key project folders:

| Folder | Contents |
|---|---|
| `/Source/` | `LinqToDB.csproj`, `LinqToDB.CLI` (now built in all configurations, including `Testing`), `LinqToDB.Analyzers`, `LinqToDB.Analyzers.CodeFixes` (new), `LinqToDB.EntityFrameworkCore.*` (EF3/8/9/10), `LinqToDB.Extensions`, `LinqToDB.FSharp`, `LinqToDB.LINQPad`, `LinqToDB.Remote.*`, `LinqToDB.Scaffold`, `LinqToDB.Tools`, `CodeGenerators.csproj`, `CodeMetricsConfig.txt` |
| `/Tests/` | `Tests.csproj`, `Tests.Base`, `Tests.EntityFrameworkCore.*`, `Tests.FSharp`, `Tests.VisualBasic`, `Tests.Benchmarks`, `Tests.Playground`, `Tests.T4`, `Tests.Model`, `Tests.SingleFile`, `Tests.Analyzers`, `Tests.Analyzers.Internal`, `Tests/LinqToDB.CLI/Tests.LinqToDB.CLI.csproj` (last three new) |
| `/Packaging/` | NuGet wrapper projects per provider |
| `/Build/` | `Directory.Build.props`, `Directory.Packages.props`, `linq2db.snk`, Azure pipeline YMLs/JSONs/scripts |
| `/Build/licenses/` | `README.md`, `components.json` (new) |
| `/.agents/` | Replaces the former `/.claude/**` and `/.github/**` file listings (which enumerated every agent doc, skill, script and issue template). Now holds stub projects `.github/.github.csproj` and `.claude/.claude.csproj` (both `Build Project="false"`) plus `AGENTS.md`, `.gitmodules`, `CLAUDE.md`. `.claude/` is a git submodule (linq2db/agents). |

`Tests.SingleFile` is excluded from `Azure`, `Release`, and `Testing` solution configurations -- it is smoke-test only. A `linq2db.Testing.slnf` solution filter (referenced by `test_solution_filter` in `build-vars.yml` and `TEST_SOLUTION_FILTER` in `tests.yml`) restricts the test-artifact build to the publish graph.

### GitHub Actions workflows (`.github/workflows/`, new this run)

The area previously stated that no GitHub Actions workflows exist. Four now do. All actions are pinned by SHA and limited to GitHub-owned ones (repo policy `allowed_actions: selected` + `github_owned_allowed`).

| Workflow | Trigger | Purpose |
|---|---|---|
| `build.yml` | every PR; push to `master`/`release` | Database-free port of the Azure `build` definition: `build` (Release build + pack of `linq2db.slnx` on `windows-2025`, hot-spot pre-build of `CodeGenerators`/`LinqToDB.Analyzers`/`.CodeFixes`/`LinqToDB` to dodge intermittent CS2012 dotnet/roslyn#77538, then `verify-nuget-sizes.ps1`, `verify-analyzer-delivery.ps1`, `third-party-notices.ps1 -Action check` and `-Action verify`, uploads `nugets` and `linq2db_linqpad_lpx` artifacts; nothing is published), `examples` (`Examples/Examples.slnx`, Debug), `analyzer-tests` (Ubuntu; `dotnet test --project Tests/Tests.Analyzers` and `Tests.Analyzers.Internal`), `singlefile-smoke` (PublishSingleFile win-x64, #5488 guard), `cli-tests` (ubuntu + windows matrix, runs the MTP exe per net8/9/10). Analyzers stay off (`RunAnalyzersDuringBuild=false`) until dotnet/roslyn#80621 ships. Anything under `Tests/` is built with `-c Azure` because `Tests/Directory.Build.props` derives the `AZURE` symbol from the configuration name, which selects the `*.Azure` connection strings and `BaselinesPath`; `-c Release` there is silently wrong. |
| `tests.yml` | `workflow_call` (from `tests-comment.yml`) and `workflow_dispatch` (`surface`, `full_run`, `ref`, `baselines_branch`, `pr`) | Provider test legs on GitHub: `prepare` (parses `Build/Azure/pipelines/templates/test-matrix.yml` with inline PyYAML, selects entries whose `filters` contain the surface and that carry `gh_linux` / `gh_windows`, emits JSON matrices, fails on an empty/unknown surface or on a `gh_windows` entry with Azure `${{ }}` conditional keys), `build` (Windows publish of net8/9/10 x64 + netfx; stages `testing/<tfm>/{main,efcore}/x64`, copies `DataProviders.json` and `.runsettings`, merges `Build/CI/*` into the scripts artifact), `build_x86` (separate `-a x86` publish with `-p:X86STUBS=True` for netcore, per-TFM artifacts), `linux-tests` (matrix; checkout baselines, `free-disk-space.sh`, global setup script, per-TFM download -> `run-provider-tests.sh` -> delete), `windows-tests` (same shape; `.exe` apphosts, x86 SDK install on x86 legs, `run-provider-tests.ps1`), then `report-trx.ps1` and `push-baselines.ps1`. Concurrency group per ref+surface with cancel-in-progress. |
| `tests-comment.yml` | `issue_comment` created, body starting `/azp run` | Bridges the Azure bot command to GitHub: `authorize` (author_association must be MEMBER/OWNER, otherwise posts a refusal comment; resolves the surface from `surfaces:` in `test-matrix.yml`; ref `refs/pull/<n>/merge`; baselines branch `baselines/pr_<n>`; adds a rocket reaction; sets a pending commit status `tests <surface>` on the PR head), `tests` (calls `tests.yml` with `secrets: inherit`), `report` (always(); closes the status success/failure unless a newer run owns the context). Calling rather than dispatching is what makes fork PRs work. `issue_comment` always runs the default branch's copy, so changes here take effect only after merge. |
| `publish-mcp.yml` | `release: published` (non-prerelease) and `workflow_dispatch` (`tag`) | MCP Registry publication for `linq2db.cli`: derives the version from the tag, patches `Source/LinqToDB.CLI/server.json` (committed as 0.0.0), polls nuget.org's `ReadmeUriTemplate/6.13.0` resource until the published README carries the `mcp-name:` marker, installs pinned `mcp-publisher` v1.8.1, validates, `login github-oidc`, publishes. Needs `id-token: write`. |

### Build/CI shared scripts (`Build/CI/`, new this run)

CI-agnostic helpers copied into the `test_scripts` artifact next to `Build/Azure/scripts/*` (Azure `build-job.yml` does `xcopy /i Build\CI testing\scripts`; `tests.yml` does `Copy-Item Build/CI/*`), so a leg invokes them by the same path on either CI:

- `run-provider-tests.sh` / `run-provider-tests.ps1` -- body of the former per-TFM loop in `test-workflow-linux.yml` / `test-workflow-windows.yml`: config -> local setup -> main suite (optional) -> EF.Core suite -> remove binaries. Switches `--tfm --flag --config --setup --retry --main` (Linux) / `-Tfm -Flag -Arch -Config -SetupCmd -SetupPs1 -PreTest -PostTest -Retry -Main` (Windows).
- `ci-setvar.sh` -- sourced `ci_setvar <name> <value>`; writes `$GITHUB_ENV` when set, otherwise the Azure `task.setvariable` logging command.
- `docker-liveness.sh` -- sourced `require_running <container>`; asserts `docker inspect` state because readiness gates grep `docker logs`, which outlive a crashed container.
- `free-disk-space.sh` -- frees ~23.6 GB on hosted Ubuntu (android, ghcup, CodeQL, swift, jvm, llvm) so Oracle/SAP HANA legs fit; extracted from an inline Azure block.
- `checkout-baselines.ps1`, `push-baselines.ps1` -- clone/commit/rebase `linq2db.baselines` for a leg (run branch if it exists, master otherwise; `-GitHubAnnotations` for GitHub logging).
- `report-trx.ps1` -- stand-in for `PublishTestResults@2` including `failTaskOnMissingResultsFile`: fails a leg whose test app wrote no `.trx`.

### Azure Pipelines: top-level pipelines

| File | Trigger | Purpose |
|---|---|---|
| `Build/Azure/pipelines/build.yml` | All PRs | Compile-only check; now passes `with_analyzer_tests: true` to `build-job.yml` |
| `Build/Azure/pipelines/default.yml` | Push to `master`/`release`; PRs to `release` | Full pipeline; also `with_analyzer_tests: true`. `mac_enabled: false` removed (macOS support deleted) and the `[all][metrics]` `db_filter` became `[all]` (the metrics matrix entry and `sqlserver.2022.metrics.json` configs are gone). Deliberately does NOT set `offload_*_to_github`, so the release run keeps every leg on Azure. |
| `Build/Azure/pipelines/testing.yml` | Manual (`/azp run test-<db>` bot commands) | Test-only. The 34-line `if eq(Build.DefinitionName, ...)` db_filter chain is gone; `db_filter` is resolved inside `test-matrix.yml` from its `surfaces:` map keyed by definition name. Includes `test-cli.yml` for `test-all` and `test-cli`; `with_tests` is false for `test-cli`; passes `offload_linux_to_github: true` and `offload_windows_to_github: true`. |

`Build/Azure/README.md` documents the `/azp run` command catalog and the per-database/TFM test matrix table; rewritten this run for the consolidated legs (152 lines changed).

### Azure Pipelines: build job (`build-job.yml`)

Build pool image: `windows-2025`. `timeoutInMinutes: 120`. Key steps:

- Installs .NET SDK 9.x then 10.x via `UseDotNet@2`.
- `PublishSingleFile` smoke test: publishes `Tests.SingleFile.csproj` as win-x64 self-contained single file and executes it; guards against `Assembly.Location` / `File.Exists` regressions in provider detectors (PR #5488).
- New `with_analyzer_tests` parameter (default false): provisions the .NET 8 runtime (the windows-2025 image no longer ships an x64 .NET 8 runtime; `Tests.Analyzers` targets net8.0) and runs `Tests/Tests.Analyzers` and `Tests/Tests.Analyzers.Internal` via `DotNetCoreCLI@2 test`. Internal tests are a separate project because `CodeGenerators` builds against Roslyn 5.6 and cannot load in the 4.8 host pinned to the shipped package's consumer floor.
- "Build Solution for Tests" now builds `$(test_solution_filter)` (`linq2db.Testing.slnf`) rather than the whole solution: `LinqToDB.CLI` has the slowest restore (1.4 min) and `Tests.T4` compiles last, together ~2.3 min of serial prefix. Nothing is left unchecked since the `build` pipeline compiles all of `linq2db.slnx` and `Tests.LinqToDB.CLI` has its own `test-cli` pipeline.
- Publishes test binaries for NETFX, net8.0, net9.0, net10.0 (x64); includes EF Core 3/8/9/10 tests. The EF3 net462 x64 publish pins an explicit `-a x64` RID (comment: SQLitePCLRaw's net4x native target only ships the x86 `e_sqlite3`, which an x64 EF test process can't load without the RID pin). `Build\CI` is xcopy'd into `testing\scripts`.
- Copies `.runsettings` alongside each published test app (`main` and `efcore`, all TFM/arch combos) -- comment: "MTP does not auto-discover it, NUnit honors it via `--settings` (`AssemblySelectLimit`)".
- New separate job `build_x86_job` (`windows-2025`, 60 min): all win-x86 publishes (`-a x86`, `/p:X86STUBS=True` for netcore; net462 without stubs) moved off the critical path into their own artifact (`artifact_test_x86_binaries` = `test_x86_binaries` in `build-vars.yml`), so Linux legs no longer download win-x86 binaries they cannot execute. Only the Access legs (`x86: true`) consume it. Comment block records the margin is thin (finished 36 s ahead of `build_job` on build 23050).
- The x86 stub MSBuild property for `Tests/Linq/Tests.csproj` is `/p:X86STUBS=True` (formerly `/p:DB2STUB=True`; stub source `Tests/Base/X86Stubs/DB2Stubs.cs` -- see TESTS area).
- Builds and packs for NuGet on Release configuration; publishes nugets and LINQPad LPX artifacts.
- New "Check third-party notices are up to date" and "Verify third-party notices cover the packed output" steps (`third-party-notices.ps1 -Action check` / `-Action verify`), gated on `with_nugets`. They live here, not in `nuget-job.yml`, because `nuget-job` only runs from `default` (so a PR adding a bundled dependency would pass and fail on master) and the `.lpx` exists only in this job. `.github/workflows/build.yml` carries the same two steps.
- Creates GitHub Release draft (via `gh`) when building the release branch.

### CI test invocation: `dotnet test` -> Microsoft Testing Platform (MTP) native execution

The OS test-workflow templates (`test-workflow-linux.yml`, `test-workflow-windows.yml`; the `test-workflow-macos.yml` template has been deleted along with all macOS support) replace `dotnet test <dll> -f <tfm> -l trx $(extra) --blame-hang-timeout 5m` with direct execution of the published test host: `dotnet ./net{8,9,10}.0/{main,efcore}/x64/linq2db*.Tests.dll ...` on Linux, and the bare `.exe` (no `dotnet` prefix) on Windows, e.g. `net10.0\main\x64\linq2db.Tests.exe`. The MTP-native argument set is `--filter "TestCategory != SkipCI" --settings <path>\.runsettings --report-trx --report-trx-filename <tfm>-<suite>-<arch>.trx --results-directory TestResults --hangdump --hangdump-timeout 5m`, replacing VSTest's `-f <tfm> -l trx --blame-hang-timeout 5m`. The per-TFM loop body now lives in `Build/CI/run-provider-tests.{sh,ps1}` (see Build/CI section) and is invoked from both Azure templates and `tests.yml`.

The `$(extra)` variable (`--arch x86` / `--arch x64`, previously injected per Access matrix entry in `test-matrix.yml`) is removed entirely -- per-architecture selection now comes from the publish output path (`.../x86/` vs `.../x64/`), not a `dotnet test` CLI flag. `test-matrix.yml`'s `extra` parameter documentation and all `extra:` entries are deleted.

The templates add a `DownloadPipelineArtifact@2` step for `$(artifact_test_scripts)` earlier in the sequence (before the baselines-branch self-heal step, see below), and drop the old later duplicate download of the same artifact.

`build-vars.yml` has `test_retry_args: '--retry-failed-tests 2 --retry-failed-tests-max-tests 5'` for crash/resource-unstable providers (Access, Oracle; entries with `retry: true`). MTP re-runs only the failed tests in-process on a flaky failure, so a single flaky test no longer trips `retryCountOnTaskFailure` into re-running the whole ~50-min test leg; the max-tests cap skips retry on mass failures (real breakage, not flakiness). `tests.yml` and `build.yml` mirror it as `TEST_RETRY_ARGS`.

New `Build/Azure/pipelines/templates/test-cli.yml` (`test_cli_job`, Windows + Linux matrix, 30 min, `dependsOn: build_job`): installs SDK 10 and .NET 8/9 runtimes, builds `Tests/LinqToDB.CLI/Tests.LinqToDB.CLI.csproj`, runs the `linq2db.CLI.Tests` exe for net8/9/10 with the same MTP arguments and `$(test_retry_args)`, publishes `CliTestResults/*.trx`. Selected by the `test-cli` and `test-all` definitions.

### Baselines branch creation (`Build/Azure/scripts/ensure-baselines-branch.ps1`)

Extracted from an inline `PowerShell@2` script previously embedded directly in `test-jobs.yml`'s `create_baselines_branch` job. Same `linq2db.baselines` repo create/rebase logic, parameterized (`-Branch`, `-PrId`, `-BaselinesMaster`, `-BaseHash`, `-Rebase`, `-EmitOutputs`) and shared by two callers:

- **Central** (`create_baselines_branch`, once per run): `-PrId "$(source_pr_id)" -BaselinesMaster "$(baselines_master)" -Rebase -EmitOutputs`. Creates the branch if missing, rebases it onto `baselines_master` when it already exists but is behind, and exports `baselines_branch` / `baselines_head` / `baselines_new_branch` as task-output variables.
- **Self-heal** (`test_windows_job` / `test_linux_job`, one step each, before their `baselines` clone): `-Branch "$(baselines_branch)" -BaselinesMaster "$(baselines_master)" -BaseHash "$(baselines_head)"`. Re-creates the branch at the recorded `baselines_head` hash if a prior completed run already deleted it via empty-branch cleanup. Without this, an Azure Pipelines "rerun failed jobs" restart fails because `create_baselines_branch` is not re-run on a partial restart and its branch was already removed by `create_baselines_pr` (referenced incident: build 21555).

Branch creation is race-tolerant: when several test jobs self-heal a missing branch concurrently, only one wins the `git/refs` POST; the losers re-query and proceed once they see the branch created by a sibling job.

`test-jobs.yml` adds `baselines_head` as a second job-output variable (alongside `baselines_branch`) so the self-heal steps can read it. The script was modified again after the prior run (delta list shows `M`, not individually re-characterized). The GitHub side (`tests-comment.yml`) derives the same `baselines/pr_<n>` branch name so both CIs append to one branch.

### Azure Pipelines: test matrix (`test-matrix.yml`, `test-jobs.yml`)

The matrix was restructured from ~40 per-database entries into ~22 multi-database legs. Entry keys carry a letter prefix `a_`..`y_` ordered by measured leg duration (longest first) and the file is kept sorted by key, because `maxParallel` releases legs in declaration order and the agent pool serves released legs alphabetically (measured on builds 23024/23028/23050: test phase 157.0 -> 140.6 min). Numeric prefixes `01_`.. were tried and failed (names must start with a letter).

Entries (key -> title): `a_SqlServer2014`, `d_SqlServer2012`, `e_SqlServer2008`, `f_SqlServer2016`, `o_SqlServer2005` (one version per job, Windows, netfx+net8/9/10), `l_SqlServer2017_2019` and `m_SqlServer2022_2025` (merged, Windows+Linux, `win_efcore_only`), `n_SqlServer2019Extras`; `b_ClickHouse` (Driver/MySql/Octonica lanes on one server, separate databases); `c_PostgreSQL2` (13-19, `pgsql2.sh`) and `i_PostgreSQL1` (9.2-12, `pgsql1.sh`); `g_SqlCE`; `h_SAPHANA2`; `j_Oracle1819`, `q_Oracle2123`, `t_Oracle1112` (`retry: true`); `k_Firebird` (all versions, `firebird.sh`); `p_MySQL` (MySQL/MariaDB, `mysql.sh`); `r_Access_MDB`, `v_Access_ACE_Odbc`, `x_Access_ACE_OleDb` (x86; ACE split in two because about 14.9k tests in one x86 process hit a deterministic OutOfMemoryException when NUnit serializes the result document), `y_Access_ACE_x64` (disabled, dotnet/runtime#46187); `s_SQLite`; `u_YdbSybase` (YDB + Sybase ASE concurrent lanes, `ydbsybase.sh`); `w_DB2InformixDuckDB` (DB2 + Informix + DuckDB; Windows leg runs DuckDB alone and only on `full_run`, with `win_tfms_always: true`). DuckDB no longer has its own entry. macOS entries and the `mac_enabled` parameter no longer exist.

Selection is data: each entry carries a `filters` string such as `[all][sqlserver.all]` (a concatenated string; a YAML list compiled but matched nothing, producing an empty matrix and a green run with zero tests on build 23192) tested with `contains()` against `db_filter`. A top-level `surfaces:` map (definition name to filter, e.g. `test-ydb` to `[ydb.all]`, `test-sqlserver-2019` to `[sqlserver.2019]`, `test-all` to `[all]`) replaces the if-chain that was in `testing.yml`. New filter values: `[sqlserver.2019]` (2017+2019) and `[sqlserver.2022]` (2022+2025); `[metrics]` removed.

New entry/matrix properties: `win_tfms_always` (windows leg keeps net8/9/10 even though a linux leg exists), `win_efcore_only` (Windows runs only the EF.Core suite on non-release runs; netfx main suite becomes release-run only), `gh_linux` / `gh_windows` (leg runs on GitHub Actions when the caller passes `offload_linux_to_github` / `offload_windows_to_github`; `test-jobs.yml` then skips it on Azure). The `linux_max_parallel` parameter caps concurrent Linux legs (default 0 = uncapped). Every Linux entry carries `gh_linux`; `gh_windows` is set on docker-free Windows legs (SqlCE, the Access x86 legs, SQLite) while the SQL Server Windows legs stay on Azure (multi-GB Windows container images).

Provider-activation configs under `Build/Azure/net{80,90,100,fx}/` were consolidated the same way: deleted `access.ace.json`, `clickhouse.{driver,mysql}.json`, `db2.json`, `informix.json`, `firebird{25,3,4}.json`, `mariadb11.json`, `mysql57.json`, `oracle{11,18,21}.json`, `pgsql{13..18}.json`, `sqlite.extras.json`, `sqlserver.2017/2022*.json`, `ydb.json`; added `access.ace.{odbc,oledb}.json`, `pgsql1.json`, `pgsql2.json`; renamed (with edits) to `clickhouse.json`, `db2informixduckdb.json`, `firebird.json`, `oracle1112/1819/2123.json`, `sqlserver.2017_2019.json`, `sqlserver.2022_2025.json`, `sqlserver.fts.2017_2019.json`, `ydbsybase.json`. Existing `sqlite.json`, `mysql.json`, `sqlserver.2008..2016.json` modified in place. Setup scripts follow: `firebird.sh`, `pgsql1.sh`, `pgsql2.sh`, `oracle1112/1819/2123.sh`, `db2informixduckdb.sh`, `ydbsybase.sh`, `sqlserver.2017_2019.{cmd,sh}`, `sqlserver.2022_2025.{cmd,sh}` replace the per-version scripts; `mac.*.sh`, `db2.sh`, `informix14.sh`, `sybase.sh`, `ydb.sh` are deleted.

`test-jobs.yml`: the inline baselines-branch script is replaced by a call to `ensure-baselines-branch.ps1`; `create_baselines_branch` downloads `$(artifact_test_scripts)` first; the macOS job is removed (two OS jobs remain: `test_windows_job`, `test_linux_job`); `baselines_head` output added; per-entry selection honors `gh_linux` / `gh_windows` with the offload parameters.

### Test container setup scripts (`Build/Azure/scripts/`)

The per-version scripts described in earlier runs (`pgsql19.sh`, `mac.pgsql19.sh`, `ydb.sh`) no longer exist; their roles moved into consolidated scripts:

- `pgsql2.sh` (Linux): starts PostgreSQL 13-19 in separate containers on host ports `54NN` (13 -> 5413 ... 19 -> 5419), TCP only (no `--net host`, no shared socket mount), image `postgres:<ver>` except 19 which stays `postgres:19beta1`; then waits for each and creates `testdata`. `pgsql1.sh` does the same for 9.2-12.
- `ydbsybase.sh`: starts YDB (`ydbplatform/local-ydb:latest`, port 2136, `YDB_FEATURE_FLAGS=enable_temp_tables`, `YDB_USE_IN_MEMORY_PDISKS=true`; must be the literal `true`, the earlier `1` was silently inert) and Sybase (`linq2db/linq2db:ase-16.1`, port 5000, self-contained configure/stop-twice/restart block) as concurrent lanes in one job.
- `mssql-container.ps1` (new): called by every `sqlserver.*.cmd`; probes the docker daemon first, runs `docker rm -f` before each attempt so retries are idempotent, retries "container up and answering" instead of assuming one `docker run` suffices. Motivated by build 23263 where one agent had an unreachable docker daemon and the old 100-iteration loop spent 106 s waiting on a container that never existed.
- `ramdisk.ps1` (new, dormant): mounts a RAM-backed NTFS volume on a Windows agent via the inbox iSCSI Target `ramdisk:` provider and loopback initiator (needs `AllowLoopBack=1` and the private NIC IP). Gated behind the undefined `use_ramdisk` variable because the ~4 min feature install outweighed the gain for the SqlCe suite.
- `clickhouse.sh`, `hana2.sh`, `mysql.sh`, `sqlserver.extras.{cmd,sh}`, `sqlserver.2005..2016.cmd` were modified (not individually characterized).

### DuckDB test schema (`Data/Create Scripts/DuckDB.sql`)

DDL for the DuckDB test database. Uses DuckDB-native type names (`HUGEINT`, `UHUGEINT`, `UINTEGER`, `UBIGINT`, `UTINYINT`, `USMALLINT`, `BITSTRING`, `TIMESTAMPTZ`, `TIMESTAMP_S`, `TIMESTAMP_MS`, `TIMESTAMP_NS`, `TIMETZ`, `TIME_NS`, `BIGNUM`, `INTERVAL`) in the `AllScaffoldTypes` table. DuckDB is embedded (no container), so it rides along in `w_DB2InformixDuckDB` at near-zero agent cost; the `duckdb.json` configs remain for the Windows DuckDB-only leg.

### NuGet package size guard and pre-publish gates (`verify-nuget-sizes.ps1`, `verify-analyzer-delivery.ps1`, `nuget-job.yml`)

Added after the 6.3.0 release-publish job hit HTTP 413 on `linq2db.cli.6.3.0.nupkg` (~416 MB) against the nuget.org 250 MB upload limit. The push had no pre-flight size check: pack succeeded, then push failed atomically after other packages had already been pushed.

`verify-nuget-sizes.ps1` parameters: `-PackagesDir` (required), `-WarnMB 180` (default), `-FailMB 200` (default), `-AzdoLogs $true` (default; emits `##vso[task.logissue]` markers). Exit codes: `0` = clean or warnings-only; `1` = any package over `$FailMB` (release-blocking); `2` = invalid args / no nupkgs found. The script was modified this run; `build.yml` (GitHub) calls it with a `-NoAzdoLogs` switch (a switch because `pwsh -File` passes every argument as a string and a `[bool]` parameter rejects strings).

`nuget-job.yml` inserts a `PowerShell@2` task (Verify nupkg sizes fail-fast before publish) before both the Azure Artifacts and nuget.org push tasks, with `-WarnMB 180 -FailMB 200` against `.build/nugets/`. The nuget.org push task is conditioned on `$(Build.SourceBranchName) == $(release_branch)`, so the size check gates all publishes.

New this run in `nuget-job.yml`:

- **`verify-analyzer-delivery.ps1`** runs before publish. `linq2db` depends on `linq2db.Analyzers`, and every satellite package must leave `analyzers` out of `PrivateAssets` on its `linq2db` / `linq2db.Tools` reference. Nothing at build time notices a cut, and the .NET SDK currently hands analyzers to csc across an excluding edge anyway, so the mistake would surface releases later. The script asserts the packed artifact (nuspecs), not the mechanism: (1) `linq2db.nuspec` declares a `linq2db.Analyzers` dependency in every group, (2) no package excludes `Analyzers` on those dependencies, (3) `linq2db.Analyzers` carries both analyzer assemblies under `analyzers/**/cs`, (4) it carries the `EnableLinqToDBAnalyzers` opt-out targets in `build/` and `buildTransitive/`, (5) every shipped rule id (from `AnalyzerReleases.*.md`) appears in the packed readme of both `linq2db` and `linq2db.Analyzers`.
- **`publish-azure-artifacts.ps1`** replaces `NuGetCommand@2 push` for the Azure Artifacts feed (preceded by `NuGetAuthenticate@1`, conditioned on the master branch). The feed has a fixed storage allowance; when full it answers HTTP 402, which turned every master build red (build 22947). The feed is a convenience mirror, not a release channel, so 402 now warns while any other push failure still fails (a blanket `continueOnError` would hide real breakage). Parameters `-PackagesDir`, `-Source`, `-NoAzdoLogs`. nuget.org publishing is unchanged.

### Third-party license notices (`Build/licenses/`, `Build/Azure/scripts/third-party-notices.ps1`, new this run)

Closes linq2db/linq2db#5731. Three artifact families physically contain foreign binaries while declaring `PackageLicenseExpression=MIT`: `linq2db.cli` (pointer + 7 RID sub-packages, `PackAsTool` publishes ~90 packages / 158 assemblies per RID), the 14 T4 packages (SQL CE, SAP HANA client from `Redist/`, IBM `clidriver` tree), and `linq2db.LINQPad.lpx` (whole `net472` output).

Layout: `components.json` (inventory, one entry per redistributed component), `texts/` (31 license/notice bodies referenced by it), `generated/THIRD-PARTY-NOTICES.<artifact>.txt` (16 files, tracked in git on purpose so the shipped text is reviewable in the PR; never hand-edited). `.gitattributes` pins `generated/**` and `texts/**` to `eol=lf` so the byte comparison is identical on Windows and Linux.

`third-party-notices.ps1` actions: `generate` (render `generated/`), `check` (regenerate to temp and byte-compare; CI on every PR), `verify` (open the produced `.nupkg` / `.lpx` and assert every shipped binary maps to a component; reads the artifact, not the csproj, so a transitive bump announces itself), `harvest` (propose changes after a dependency bump; never writes). Run from both `build-job.yml` and `.github/workflows/build.yml`.

### DB2 provider setup scripts (`Build/Azure/scripts/db2.provider.sh`)

The script is TFM-aware. It detects the active TFM from the directory path and selects the correct `Net.IBM.Data.Db2-lnx` package version:

- net10.0: `DB2_PKG_VERSION=10.0.0.100`
- net8.0 / net9.0: `DB2_PKG_VERSION=9.0.0.400`

This version must be kept in lockstep with the `Net.IBM.Data.Db2*` entries in `Directory.Packages.props`. The script downloads the package from nuget.org (wget + unzip, replacing the deprecated `nuget install`), swaps in the linux DLL, and sets `PATH`/`LD_LIBRARY_PATH` for DB2 CLI driver. `mac.db2.provider.sh` was deleted with macOS support; `db2.provider.sh` itself shows as modified in this delta (the version split above is from the prior run and was not re-verified line by line). It is now invoked as `script_linux_local` of `w_DB2InformixDuckDB`.

### .github/ISSUE_TEMPLATE: issue triage forms

13 YAML forms in two series: Bug reports (01--09) and Feature requests (11--19). Unchanged this run.

### .github/copilot-instructions.md: Copilot PR review rules

Instructs Copilot to ignore intentional formatting differences (column-aligned code, minor spacing) and comment only on clearly problematic formatting (3+ consecutive blank lines, trailing whitespace on multiple lines, visibly broken indentation, mixed tabs/spaces). Testing guideline: prefer Shouldly for assertions over NUnit Assert.

## Inbound / outbound dependencies

**Inbound (everything depends on this area):**
- Every C# project in `Source/` and `Tests/` imports `Directory.Build.props`.
- `Source/Directory.Build.props` adds `Source/BannedSymbols.txt` as an `<AdditionalFiles>` input.

**Outbound:**
- The CI test matrix touches every PROV-* provider area.
- `build-job.yml` and `.github/workflows/tests.yml` publish test binaries for every TESTS-* area (`Tests/Directory.Build.props` maps the `Azure` configuration to the `AZURE` symbol).
- `nuget-job.yml` publishes packages produced by all packaging projects; runs `verify-nuget-sizes.ps1` and `verify-analyzer-delivery.ps1` as pre-flight gates before any push.
- `.github/workflows/publish-mcp.yml` reads `Source/LinqToDB.CLI/server.json`.
- `third-party-notices.ps1` reads the `linq2db.cli`, T4 and LINQPad packaging outputs.

## Known issues / debt

- **`Build/BannedSymbols.txt` pin is stale.** Listed as a Tier-1 pin but does not exist. Actual file is `Source/BannedSymbols.txt`.
- **Roslyn analyzer disabled in the PR build on both CIs.** `with_analyzers: false` / `RunAnalyzersDuringBuild=false` due to Roslyn issue #80621.
- **macOS tests removed.** The `test-workflow-macos.yml` template, `mac.*.sh` scripts and `mac_enabled` parameter are deleted; macOS provider legs no longer exist (previously disabled by default).
- **Access ACE x64 disabled.** Due to dotnet/runtime#46187.
- **ClickHouse Octonica always disabled.** Carried over from the prior run; the `clickhouse.octonica.json` slnx entries were removed, so verify before relying on it.
- **DuckDB no netfx support.** Does not support .NET Framework.
- **PostgreSQL 19 CI job targets a pre-release Docker image.** `pgsql2.sh` pins `postgres:19beta1`; expect a tag swap once PostgreSQL 19 reaches GA.
- **Two CIs, one matrix.** `test-matrix.yml` is parsed by Azure natively and by inline PyYAML in `tests.yml` and `tests-comment.yml`. Azure template conditionals inside an entry (as with `enable_os_windows` in `w_DB2InformixDuckDB`) are invisible to the stock parser; `tests.yml` hard-fails if a `gh_windows` entry contains one. The `workflow_call` and `workflow_dispatch` input blocks of `tests.yml` must be kept in step by hand (Actions has no anchors).
- **`issue_comment` workflows run the default branch copy.** Changes to `tests-comment.yml` take effect only after merge; testing `tests.yml` changes pre-merge requires `gh workflow run`.
- **Leg ordering is load-bearing.** `test-matrix.yml` must stay sorted by key; reletter when a leg duration drifts.
- **`global.json` `rollForward: latestFeature`** is required for `CodeGenerators` (Roslyn 5.6); reverting to `minor` breaks machines with side-by-side 10.0.2xx/4xx SDKs.
- **Stale references after the consolidation.** `.claude` docs (`test-databases.md`, `ci-tests.md`) and Azure UI definitions (for example `test-metrics`, which has no matrix entry any more) may still name deleted scripts and configs.

## See also

- [architecture overview](../../architecture/overview.md)
- [CLAUDE.md](../../../CLAUDE.md) -- build commands reference
- `.claude/docs/testing.md`
- `.claude/docs/ci-tests.md`
- `Build/licenses/README.md` -- third-party notices workflow

<details><summary>Coverage</summary>

- Tier 1 (visited / total): 3 / 4
  - Directory.Build.props -- read in full
  - global.json -- read in full
  - linq2db.slnx -- read in full
  - Build/BannedSymbols.txt -- MISSING on disk
  - Source/BannedSymbols.txt -- read in full (actual location)
- Tier 2 (visited / total): 115 / 115 (100%; denominator kept at or above the prior value although about 80 per-version scripts and configs were deleted)
  - Read (prior run, delta): Build/Azure/net{80,90,100}/duckdb.json; test-matrix.yml (DuckDB entry); testing.yml (test-duckdb filter); Directory.Build.props (EnforceCodeStyleInBuild Release-only, DuckDB DatabasePackageTags); Directory.Packages.props (DuckDB.NET.Data.Full); DataProviders.json (DuckDB entry); Tests/linq2db.Providers.props (DuckDB ref); Data/Create Scripts/DuckDB.sql (new)
  - Read (prior run -- delta 2): Build/Azure/scripts/verify-nuget-sizes.ps1 (ADDED); Build/Azure/pipelines/templates/nuget-job.yml; Directory.Build.props (version 6.3.0 -> 6.4.0); global.json (SDK pin 10.0.0 -> 10.0.200); Directory.Packages.props (DuckDB.NET.Data.Full 1.5.2, Npgsql 10.0.2); linq2db.slnx; Source/BannedSymbols.txt; .github/copilot-instructions.md
  - Read (prior run -- delta 3): `.editorconfig` (full Meziantou.Analyzer 3.0.85 catalog); `Build/Azure/pipelines/build.yml` / `default.yml` (no structural change); `build-job.yml` (windows-2025 pool, PublishSingleFile smoke test, EF10 publish steps); `test-matrix.yml` (PostgreSQL 18, SQL Server 2025, SqlServer2019Extras entries); `test-workflow-linux.yml` / `test-workflow-macos.yml` / `test-workflow-windows.yml` (structure baseline, NET10 x86 steps); `db2.provider.sh` / `mac.db2.provider.sh` (TFM-aware version split); `Directory.Packages.props` (per-TFM DB2 versions, Npgsql/DuckDB/BenchmarkDotNet/FSharp.Core/NUnit3TestAdapter/Meziantou.Analyzer/SourceLink bumps); `linq2db.slnx` (Tests.SingleFile project added)
  - Read (prior run -- delta 4):
    - `Build/Azure/README.md` -- adds `/azp run test-ydb` line; adds PostgreSQL 19 row (OS/TFM matrix + `ProviderName.PostgreSQL19` reference row); adds YDB row (OS/TFM matrix + `ProviderName.Ydb` reference row).
    - `Build/Azure/net100/pgsql19.json`, `Build/Azure/net80/pgsql19.json`, `Build/Azure/net90/pgsql19.json` -- new provider-activation configs, each `{"NET{80,90,100}.Azure": {"Providers": ["PostgreSQL.19"]}}`.
    - `Build/Azure/net100/ydb.json`, `Build/Azure/net80/ydb.json`, `Build/Azure/net90/ydb.json` -- new provider-activation configs, each `{"NET{80,90,100}.Azure": {"Providers": ["YDB"]}}`.
    - `Build/Azure/pipelines/templates/build-job.yml` -- copies `.runsettings` next to each published test app (MTP does not auto-discover it); renames x86 stub property `DB2STUB` -> `X86STUBS`; EF3 net462 x64 publish now pins explicit `-a x64` RID (SQLitePCLRaw native-asset comment).
    - `Build/Azure/pipelines/templates/build-vars.yml` -- adds `test_retry_args: '--retry-failed-tests 2 --retry-failed-tests-max-tests 5'` for MTP in-process failed-test retry.
    - `Build/Azure/pipelines/templates/test-jobs.yml` -- inline baselines-branch PowerShell script replaced by a call to `ensure-baselines-branch.ps1`; downloads `$(artifact_test_scripts)` earlier (before the baselines step); drops the `extra` variable passthrough for all three OS jobs; adds `baselines_head` job-output variable alongside `baselines_branch`.
    - `Build/Azure/pipelines/templates/test-matrix.yml` -- adds `PostgreSQL19` matrix entry (Linux+macOS, net8/9/10, `pgsql19.sh`/`mac.pgsql19.sh`) and `YDB` matrix entry (Linux+macOS, net8/9/10, `ydb.sh`); removes the `extra` parameter doc-comment and all `extra: --arch x86`/`--arch x64` Access-entry properties.
    - `Build/Azure/pipelines/templates/test-workflow-linux.yml` -- switches all `dotnet test <dll> -f <tfm> -l trx $(extra) --blame-hang-timeout 5m` invocations to direct MTP host execution (`dotnet ./<tfm>/{main,efcore}/x64/linq2db*.Tests.dll ... --settings .../.runsettings --report-trx ... --hangdump --hangdump-timeout 5m [$(test_retry_args)]`); adds `DownloadPipelineArtifact` for test scripts earlier + a new "Ensure test baselines branch" self-heal step (`ensure-baselines-branch.ps1`) before the baselines clone; removes the old later duplicate scripts-artifact download.
    - `Build/Azure/pipelines/templates/test-workflow-macos.yml` -- same MTP invocation switch + self-heal step + download reordering as the linux template.
    - `Build/Azure/pipelines/templates/test-workflow-windows.yml` -- same MTP invocation switch (bare `.exe`, no `dotnet` prefix, e.g. `net10.0\main\x64\linq2db.Tests.exe`) + self-heal step + download reordering; covers netfx x86/x64 and net8/9/10 x86/x64 legs.
    - `Build/Azure/pipelines/testing.yml` -- adds `test-ydb` -> `[ydb.all]` `db_filter` mapping alongside the existing `test-duckdb`/`test-clickhouse`/etc. mappings.
    - `Build/Azure/scripts/ensure-baselines-branch.ps1` -- NEW; factors the baselines-branch create/rebase logic out of `test-jobs.yml` into a shared, parameterized script with a central create/rebase mode (`-Rebase -EmitOutputs`) and a per-job self-heal mode (`-BaseHash`); addresses a "rerun failed jobs" restart failure referencing build 21555.
    - `Build/Azure/scripts/mac.pgsql19.sh`, `Build/Azure/scripts/pgsql19.sh` -- NEW; docker container setup for PostgreSQL 19 (`postgres:19beta1` image), poll-and-create the `testdata` database.
    - `Build/Azure/scripts/ydb.sh` -- NEW; docker container setup for YDB (`ydbplatform/local-ydb:latest`, `YDB_FEATURE_FLAGS=enable_temp_tables`), polls container logs for the "Table profiles were not loaded" startup marker.
    - `global.json` -- adds `"test": {"runner": "Microsoft.Testing.Platform"}`; SDK version/rollForward unchanged (`10.0.200`, `minor`, `false`).
  - Read (this run -- delta): 290 changed entries since 36ee4f82f; Tier-1 overlaps read in full, the rest read or characterized by group.
    - `Directory.Build.props` (diff + grep) -- Version 6.4.0 -> 6.6.0; EF3/8/9/10 versions bumped to 3.35.0/8.9.0/9.8.0/10.7.0; NoWarn gains MA0202/MA0209/MA0210 with build-time rationale; polyfills gain `System.Reflection.Nullability` and `Enumerable.ToHashSet(comparer)`.
    - `global.json` (read in full) -- version `10.0.100`, `rollForward: latestFeature` (prior notes said `10.0.200` / `minor`) with explanatory comment (Roslyn 5.3 vs 5.6, CS9057); MTP runner pin retained.
    - `linq2db.slnx` (diffed) -- `/.claude/**` and `/.github/**` file listings replaced by `/.agents/` stub projects; adds `LinqToDB.Analyzers(.CodeFixes)`, `Tests.Analyzers(.Internal)`, `Tests.LinqToDB.CLI`, `Build/licenses`, `CodeMetricsConfig.txt`; Azure config/script lists renamed to the consolidated names; `LinqToDB.CLI` now built under `Testing`.
    - `.github/workflows/build.yml`, `tests.yml`, `tests-comment.yml`, `publish-mcp.yml` (A, read in full) -- see "GitHub Actions workflows".
    - `Build/Azure/pipelines/templates/test-matrix.yml` (M, read in full) -- about 22 consolidated legs, `surfaces:` map, `filters` strings, `gh_linux`/`gh_windows`/`win_tfms_always`/`win_efcore_only`, `linux_max_parallel`, letter-prefix ordering.
    - `Build/Azure/pipelines/templates/test-cli.yml` (A, read in full) -- CLI test job.
    - `Build/Azure/pipelines/testing.yml`, `default.yml`, `build.yml`, `build-vars.yml`, `nuget-job.yml`, `build-job.yml` (M, diffed) -- see Azure sections.
    - `Build/Azure/pipelines/templates/test-jobs.yml` (M, grepped for offload/maxParallel/mac) and `test-workflow-linux.yml` / `test-workflow-windows.yml` (M) -- characterized via `tests.yml`, which mirrors them; `test-workflow-macos.yml` (D).
    - `Build/Azure/scripts/*.ps1` new: `mssql-container.ps1`, `publish-azure-artifacts.ps1`, `ramdisk.ps1`, `verify-analyzer-delivery.ps1` (headers read), `third-party-notices.ps1` (via `Build/licenses/README.md` and workflow usage); `verify-nuget-sizes.ps1`, `ensure-baselines-branch.ps1` (M, not re-read in full).
    - `Build/Azure/scripts/*.sh` / `*.cmd`: `pgsql2.sh`, `ydbsybase.sh` (headers read); `firebird.sh`, `pgsql1.sh`, `oracle1112/1819/2123.sh`, `db2informixduckdb.sh`, `sqlserver.2017_2019.*`, `sqlserver.2022_2025.*` (A, characterized by name and matrix usage); about 35 deleted per-version scripts including all `mac.*.sh`, `db2.sh`, `informix14.sh`, `sybase.sh`, `ydb.sh`, `pgsql13..19.sh`; `clickhouse.sh`, `db2.provider.sh`, `hana2.sh`, `mysql.sh`, `sqlserver.2005..2016.cmd`, `sqlserver.extras.*` (M, not read).
    - `Build/CI/*` (8, A): `ci-setvar.sh`, `docker-liveness.sh`, `free-disk-space.sh`, `run-provider-tests.sh` (read); `run-provider-tests.ps1`, `report-trx.ps1`, `checkout-baselines.ps1`, `push-baselines.ps1` (characterized from `tests.yml` usage).
    - `Build/licenses/README.md` (read), `components.json` (A, characterized by name); `generated/*` (16) and `texts/*` (31): generated/license-text taxonomy only, not read.
    - `Build/Azure/net{80,90,100,fx}/*.json` (about 100 entries, A/D/R/M) -- three-line provider-activation configs; grouped as consolidation per the test matrix section; not individually read. `Build/Azure/README.md` (M, not re-read; regenerated for consolidated legs).
- Tier 3 (skipped, logged): 0
  - Build/Azure/{net80,net90,net100,netfx}/*.json (150+ files, minus the provider-activation configs called out by name above) -- Tier-3 test data
  - Build/Azure/scripts/*.cmd -- Tier 3
  - Build/licenses/generated/* (16) and Build/licenses/texts/* (31) -- generated or verbatim license text
</details>
