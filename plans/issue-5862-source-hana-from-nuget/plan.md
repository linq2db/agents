# Work plan: issue-5862-source-hana-from-nuget — Source SAP HANA test client from SAP's NuGet packages, probe v10.0, stop packing v4.5

**Tier:** L  ·  **Status:** approved  ·  **Approved-at:** 2026-10-26 (E-1…E-20, after critic round 1)  ·  **Branch:** issue/5862-source-hana-from-nuget
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

## P1 Problem

Issue [#5862](https://github.com/linq2db/linq2db/issues/5862), base `origin/master` c82e21c35. Three defects:

1. **Checked-in client binaries.** `Redist/SapHana` holds the SAP HANA 2.23.27 .NET client. That is `v8.0/Sap.Data.Hana.Net.v8.0.{dll,pdb,deps.json}`, plus `libadonetHDB{,32}.{dll,pdb}` at about 41 MB with PDBs. `Tests/Linq/Tests.csproj:27-31,55-60` and `Tests/Tests.Playground/Tests.Playground.csproj:24-37` consume them by `HintPath` and copy. SAP now publishes `Sap.Data.Hana.Net.v8.0` and `Sap.Data.Hana.Net.v10.0` 2.30.27 on nuget.org, with natives under `runtimes/<rid>/native/`.
2. **net8+ build can't see the v10.0 client.** The net8+ linq2db build cannot use it. `SapHanaProviderAdapter.cs:34` probes only `Sap.Data.Hana.Net.v8.0`, `v6.0` and `Core.v2.1`. `SapHanaProviderDetector.cs:26-31,72-77` maps no `Sap.Data.Hana.Net.v10.0` provider name.
   - Observable: an app or test referencing only the v10.0 package gets `InvalidOperationException: Cannot load assembly by name(s) Sap.Data.Hana.Net.v8.0, Sap.Data.Hana.Net.v6.0, Sap.Data.Hana.Core.v2.1` (`SapHanaProviderAdapter.cs:167`) on the first native connection.
   - With provider name `Sap.Data.Hana.Net.v10.0`, `DetectProvider` returns null.
3. **Unlicensed redistribution.** `NuGet/NuGet.csproj:46-49` stages the netfx client `Sap.Data.Hana.v4.5.dll`, and `NuGet/SapHana/linq2db.SapHana.csproj:37` / `NuGet/t4models/linq2db.t4models.csproj:114` pack it into `tools/`. It is redistributed without established terms: `Build/licenses/components.json` `sap-hana-client`, `redistribution: unresolved`, `revisit` → #5862. It also cannot connect without an installed client, since `libadonetHDB` is not packed.

## P2 Success criteria

- SC-1 net8.0/net9.0 builds of Tests.csproj and Tests.Playground take the HANA client from `Sap.Data.Hana.Net.v8.0` 2.30.27, and net10.0 from `Sap.Data.Hana.Net.v10.0` 2.30.27, natives included. `Redist/SapHana/v8.0/*` and `libadonetHDB*.pdb` are deleted, and SapHana.Native suites pass on net8.0 and net10.0 → TO-1, TO-3
- SC-2 the net8+ linq2db build loads `Sap.Data.Hana.Net.v10.0` when it is the only client present, and maps provider name `Sap.Data.Hana.Net.v10.0` to the native provider → TO-1, TO-2
- SC-3 the produced `linq2db.SapHana` / `linq2db.t4models` nupkgs contain no `Sap.Data.Hana*` file, `sap-hana-client` and its licence text are gone from `Build/licenses`, and `third-party-notices.ps1 -Action check` / `-Action verify` pass → TO-6, TO-7
- SC-4 the unchanged paths stay working: net462 SapHana.Native via the kept 2.23.27 natives, SapHana.Odbc, and the x86 `X86STUBS` publish → TO-4, TO-5, TO-8

## P3 Constraints & anti-goals

- No public API change outside `LinqToDB.Internal.*`. `SapHanaProviderAdapter.UnmanagedAssemblyNames` is `static readonly IEnumerable<string>` in `LinqToDB.Internal.DataProvider.SapHana` (`PublicAPI.Shipped.txt:15814`); only its value changes, and `PublicAPI.*.txt` is untouched.
- No SQL, baseline or query-cache change; nothing under `SqlQuery/` or `Translation/`.
- The CI HANA leg is unchanged. It runs only `SapHana.Odbc`, Linux, net8/9/10 (`Build/Azure/pipelines/templates/test-matrix.yml:282-294`, `Build/Azure/scripts/hana2.sh:75-106`).
- `Redist/SapHana/hdbsql.exe` (`Data/Setup Scripts/saphana2.cmd:17`), `Redist/SapHana/v4.5/*` and `Redist/SapHana/libadonetHDB{,32}.dll` stay. The net462 tests still reference them (`Tests.csproj:14-18`).
- Anti-goal from the #5731 plan (`.claude/plans/issue-5731-third-party-license-notices/plan.md:34`): do not drop the SAP client *silently*. The T4 behaviour change is stated in the PR body and in `NuGet/README.md`.
- Do not touch the already-stale XML doc at `Source/LinqToDB/DataProvider/SapHana/SapHanaProvider.cs:13`; this change does not falsify it.

## P4 Unknowns

- U-1 How the 2.30.27 client finds its native. Measured by ilspycmd decompile of `Sap.Data.Hana.Net.v8.0` 2.30.27, `HanaUnmanagedDll.SearchNativeDlls`. The search order is `<dir of typeof(HanaConnection).Assembly.Location>/runtimes/<rid candidates>/native/libadonetHDB{,32}.{dll,so,dylib}`, then that directory itself, then its subdirectories, then the current directory. The name is `libadonetHDB32` when `IntPtr.Size != 8`. So a portable build or publish resolves through `runtimes/`, a RID-specific publish through the flattened root, and netcore needs no root copy — resolved-by probe
- U-2 Native/managed version coupling. Measured: `CheckDllVersion` on Windows, unless `HDBDOTNETCORE_NOVERSION` is set, requires the native FileVersion major.minor.build to equal the managed assembly version. So the netfx `v4.5` 2.23.27 cannot use the package's 2.30.27 natives, and the Redist 2.23.27 natives stay for net462 (D-3). A stale 2.23.27 native left in a netcore output root is skipped, because `runtimes/` is searched first — resolved-by probe
- U-3 Package shape and architecture. Measured on the downloaded 2.30.27 nupkgs. The v10.0 assembly is `lib/net10.0/Sap.Data.Hana.Net.v10.0.dll`. Natives are `runtimes/{win-x64:libadonetHDB.dll, win-x86:libadonetHDB32.dll, linux-x64, linux-arm64, linux-musl-x64, osx-x64, osx-arm64}`. Both managed assemblies are PE I386 + ILOnly with no 32BITREQUIRED, i.e. AnyCPU, whereas the Redist 2.23.27 v8.0 copy is PE Amd64 (x64-only). The nuspecs have no dependencies (empty `net8.0`/`net10.0` groups) and set `requireLicenseAcceptance=true` — resolved-by probe
- U-4 API drift 2.23.27 → 2.30.27. Measured with `fuget-api-diff.ps1` against the local fuget: v8.0 2.27.23→2.30.27 is +22/-0 and v10.0 2.28.17→2.30.27 is +20/-0. The additions are pool statistics, `HanaInstrumentation(Options)`, `HanaLogging.UseLoggerFactory`, and the v8.0 `ProxyRegion`/`ReplicationRole`. A decompiled public-line diff covers the 2.23.27 → 2.27.23 → 2.30.27 gap the fuget run cannot: the only removals are members of internal types (`HanaConnectionPool`, `HanaInternalConnection`, a P/Invoke `Unmanaged_Init` overload, `StatementHash`). Every member the adapter uses (`GetDateTimeOffset`, `GetTimeSpan`, `GetHanaDecimal`, `ClearAllPools`, `HanaDbType.RealVector`, bulk copy) is still present. Nothing new serves the adapter TODOs — resolved-by probe
- U-5 Whether the `TryLoadAssembly` factory fallback (`Tools.cs:104-138`, `DbProviderFactories.GetFactory("Sap.Data.Hana")`) can mask the v10.0 red. Scout: `RegisterFactory|DbProviderFactories` over `Tests/` finds only SqlCe (`TestsInitialization.cs:267`) and the DB2/Informix netfx hooks (`:178-195`), so with only v10.0 present master should throw. Reasoned; TO-1 is the proof — resolved-by scout
- U-6 How a netfx T4 user reaches `Sap.Data.Hana.v4.5` once it is not packed. Measured on this box: a HANA client install registers `invariant="Sap.Data.Hana"` → `Sap.Data.Hana.HanaFactory, Sap.Data.Hana.v4.5, Version=2.23.27.0` in `Framework64\v4.0.30319\Config\machine.config`, and puts seven `Sap.Data.Hana.v4.5` versions in `GAC_MSIL`. The `TryLoadAssembly` factory fallback therefore resolves it on netfx, and T4 templates default to `SapHanaProvider.Unmanaged` (`NuGet/SapHana/LinqToDB.SapHana.ttinclude:84,89,99,105`). Without an installed client the bundled managed dll could not connect anyway, because no `libadonetHDB` is packed. TO-7 proves the load path — resolved-by probe
- U-7 Whether CI exercises SapHana.Native. Scout: no. The only HANA leg is `h_SAPHANA2`, Linux, net8/9/10, `SapHana.Odbc` only (`Build/Azure/pipelines/templates/test-matrix.yml:282-294`, `Build/Azure/scripts/hana2.sh:75-106`). So native proof is local, against the `hana2` container, which exists (status Exited); starting it needs the user's go-ahead — resolved-by scout
- U-8 Restore-time traps. Scout: CPM is on (`Directory.Packages.props:3`), so `PackageVersion` entries are needed; `packageSourceMapping` is `*` → nuget.org (`nuget.config:3-11`); there is no lock file and transitive pinning is off (`Directory.Packages.props:4`); NuGetAudit is default-on with warnings-as-errors, and the packages have no dependencies (U-3). That `requireLicenseAcceptance` does not prompt in `dotnet restore` is reasoned, unprobed; the first restore settles it, and a prompt or error stops implementation for a re-plan — resolved-by scout
- U-9 Who gains the reference by placement. Scout: `Tests/linq2db.Providers.props` is imported by `Tests/linq2db.TestProjects.props:4` (→ Tests.csproj, Tests.Playground, Tests.T4) and directly by `Tests/Tests.Benchmarks/linq2db.Benchmarks.csproj:2`. Tests.T4 and Benchmarks use no HANA client (D-2) — resolved-by scout
- U-10 How LINQPad uses the list. Scout: `Source/LinqToDB.LINQPad/DatabaseProviders/SapHanaProvider.cs:57-60,79-85,104-106,119-126` iterates `UnmanagedAssemblyNames`. `TryGetDefaultPath` derives `v10.0` from the new name and probes `%ProgramFiles%\sap\hdbclient\dotnetcore\v10.0\Sap.Data.Hana.Net.v10.0.dll`. The driver is `net8.0-windows7.0` and loads the net8.0 linq2db build, so a NET10-only entry would never reach it (D-5). The SAP installer folder name is unverified and affects only the default-path suggestion — resolved-by scout
- U-11 Who else uses `ToolsPath`'s v4.5 copy. Scout: only `linq2db.SapHana.csproj:37` and `linq2db.t4models.csproj:114` pack it, and NuGet.csproj has no `.cs`. In-repo `Tests/Tests.T4` uses `LinqToDBT4SapHanaClientPath=$(LinqToDBT4SharedTools)` = `.build\bin\NuGet\Debug\net462\` (`Directory.Build.props:224,236`). Its native template `Tests/Tests.T4/Default/SapHana.tt` loses the staged copy and resolves through U-6, as a user will; `Tests/Tests.T4/Databases/SapHana.tt:9` is ODBC — resolved-by scout
- U-12 Pre-existing quirk. Scout: `Tests/Tests.T4.Nugets/Templates/Hana.ODBC.tt:11` calls `LoadSapHanaMetadata(GetConnectionString("SapHana.Odbc"))` with no provider argument, so it defaults to Unmanaged. This change does not cause it; deferred to P10 — resolved-by scout
- U-13 Whether the x86 HANA stub still has a reason. Measured (U-3): it existed because the Redist v8.0 assembly is x64-only (`Tests/Linq/Tests.csproj:24-26`, `Tests/Base/X86Stubs/HanaStubs.cs:4`), and the package is AnyCPU. The gate is kept anyway (D-4) — resolved-by probe
- U-14 Whether the +65 MB-per-TFM native payload is accepted or trimmed (D-8, measured). User, 2026-10-26: accept; the CI HANA leg proves it fits — resolved-by user answer
- U-15 Whether v10.0 itself carries the mechanisms U-1/U-2/U-4 measured on v8.0. Critic, measured by string search of `Sap.Data.Hana.Net.v10.0.dll` 2.30.27: `HanaDecimal`, `GetHanaDecimal`, `GetRealVector`, `GetTimeSpan`, `GetDateTimeOffset`, `HanaBulkCopyColumnMappingCollection`, `HanaRowsCopiedEventHandler`, `ClearAllPools`, `SearchNativeDlls`, `CheckDllVersion`, `HDBDOTNETCORE_NOVERSION` and `runtimes` are all present, matching v8.0 2.30.27 — resolved-by probe
- U-16 What a .NET 8 LINQPad host does with a v10.0 default path. Critic, reasoned, unprobed: a `lib/net10.0` assembly fails to bind on .NET 8. Made unreachable by D-5: the net8 build no longer lists v10.0 — resolved-by probe (design: D-5 gate)
- U-17 TO-2's master result. Critic: `DataConnection.Configuration.cs:157-164` falls through to `defaultDataProvider`, and no test sets `DefaultDataProvider` (grep `DefaultDataProvider\s*=` over `Tests/**/*.cs` finds none). So the master red is `null` — resolved-by scout

## P5 Decisions

### D-1 — Per-TFM client package for tests
- **chosen:** `Sap.Data.Hana.Net.v8.0` 2.30.27 for net8.0/net9.0, `Sap.Data.Hana.Net.v10.0` 2.30.27 for net10.0. The `PackageVersion` entries are conditioned like `Net.IBM.Data.Db2` (`Directory.Packages.props:156-161`).
- **rejected:** v8.0 for every net8+ TFM (lib/net8.0 runs on net10). It needs no engine change, but it leaves the net10 client — the one SAP ships for net10 — untested and unsupported by linq2db. The user chose v10.0 with the engine fix bundled here.
- **rejected:** keep the 2.23.27 version. It is not on nuget.org (versions start at 2.27.23 / 2.28.17).
- **why this:** tests now exercise the client a net10 app would actually reference, and that makes SC-2 testable.
- **failure mode of the choice:** v8.0 and v10.0 can drift apart in a later bump. Mitigation: one version literal per package, bumped together by `/release-deps`.

### D-2 — Reference placement
- **chosen:** `PackageReference`s directly in `Tests/Linq/Tests.csproj` and `Tests/Tests.Playground/Tests.Playground.csproj`, where the `HintPath` references are today, under the existing `IsTargetFrameworkCompatible(net8.0) and X86STUBS != True` condition and split per TFM.
- **rejected:** `Tests/linq2db.Providers.props` inside the DB2 `<Choose>`. That was the session plan's first draft, rejected after U-9: it also hands the package (and its natives) to Tests.T4 and Benchmarks, which never use HANA.
- **why this:** the blast radius stays exactly the two projects that consume HANA today.
- **failure mode of the choice:** the two csproj files can drift (they already mirror each other by hand, `Tests.Playground.csproj:15`).

### D-3 — netfx natives stay in Redist
- **chosen:** keep `Redist/SapHana/libadonetHDB.dll` / `libadonetHDB32.dll` (2.23.27) and copy them only when `TargetFramework == net462`. Delete their `.pdb` files.
- **rejected:** take the natives from the package for net462 via `PackageDownload`. U-2 measured an exact version match requirement on Windows, so 2.30.27 natives would not load beside the 2.23.27 `v4.5` assembly.
- **rejected:** delete them and rely on an installed client for net462 tests.
- **why this:** chosen by the user, and U-2 shows it is the only working option short of a new netfx client.
- **failure mode of the choice:** about 15.6 MB of natives stay checked in until the netfx `v4.5` client gets its own source.

### D-4 — HANA x86 stubs stay
- **chosen:** keep the `X86STUBS != True` condition and `HANASTUBS`. Reword the two comments that call the reference "x64-only": `Tests.csproj:24-26`, which this change rewrites, and `HanaStubs.cs:4`.
- **rejected:** drop `HANASTUBS` now that the package is AnyCPU (U-3). That removes `Tests/Base/X86Stubs/HanaStubs.cs` and the define at `Tests/Directory.Build.props:7`, and puts the client on the x86 CI publishes (`tests.yml:424-427`, `build-job.yml:364`): a new CI surface outside this issue.
- **why this:** behaviour-preserving for x86 CI. The simplification is offered as a follow-up issue.
- **failure mode of the choice:** a stub that is no longer needed stays until the follow-up.

### D-5 — Where v10.0 goes in the probe list (revised after critic round 1)
- **chosen:** a new `#elif NET10_0_OR_GREATER` branch, `["Sap.Data.Hana.Net.v10.0", "Sap.Data.Hana.Net.v8.0", "Sap.Data.Hana.Net.v6.0", "Sap.Data.Hana.Core.v2.1"]`, ahead of the unchanged `#elif NET8_0_OR_GREATER` list (`SapHanaProviderAdapter.cs:34`). It is the same gate the CLI probe path gets (E-7). Separately, `case "Sap.Data.Hana.Net.v10.0":` is added to both detector switches unconditionally: a name→provider mapping loads nothing.
- **rejected:** prepending v10.0 to the shared net8+ list (round-1 draft). The net8.0 linq2db build is what the LINQPad driver (`net8.0-windows7.0`, LINQPad 8 = .NET 8 host) loads. `TryGetDefaultPath` (`SapHanaProvider.cs:119-127`) returns the first existing `…\dotnetcore\<vN>\<name>.dll`, `DynamicConnectionModel.cs:65` pre-fills it, and `SapHanaProvider.cs:144-145` `LoadFrom`s it. A `lib/net10.0` assembly on a .NET 8 host fails to bind. With v10.0 first, that path would win over a loadable v8.0 one (critic, reasoned; precondition — SAP's installer creating `dotnetcore\v10.0` — unverified, and this box's client has only `v6.0`/`v8.0`).
- **rejected:** a runtime-major filter in LINQPad's `TryGetDefaultPath`. It is a second mechanism for what the TFM gate already expresses.
- **why this:** a net8/net9-built consumer can never reference the v10.0 package (NuGet TFM compatibility), so the net8 build has no reason to probe it. Probing is lazy and first-hit (`SapHanaProviderAdapter.cs:162-164`).
- **failure mode of the choice:**
  - A net10 app that loads the ns2.0 or net8 linq2db asset (via a netstandard library) does not probe v10.0. That is the same shape as #6076.
  - LINQPad users on a .NET 10 host with only a v10.0 client must browse to it rather than get a default path.
  - With a `Sap.Data.Hana` factory registered (LINQPad `:145`, CLI `ScaffoldCommand.Execute.cs:268`), the factory fallback returns the registered assembly for the first name whatever its version, as today.
- **merge note:** open PR [#6083](https://github.com/linq2db/linq2db/pull/6083) collapses the `#elif NET8_0_OR_GREATER` into `#else`. Whichever merges second keeps `#if NETFRAMEWORK` / `#elif NET10_0_OR_GREATER` (v10 list) / `#else` (the v8 list).

### D-8 — Native payload of the packages
- **measured:** each 2.30.27 package carries 79.8 MB of natives across seven RIDs (linux-arm64 13.1, linux-musl-x64 14.1, linux-x64 14.0, osx-arm64 11.2, osx-x64 11.6, win-x64 8.6, win-x86 7.2 MB). The Redist pair it replaces is 14.9 MB. A RID-less build/publish copies all seven, so each net8/9/10 test output and CI artifact grows by about +65 MB. The GitHub HANA leg downloads one TFM at a time (`tests.yml:577-580`, "the SAP HANA legs only fit after free-disk-space.sh"), so its disk peak rises by about 65 MB.
- **options:** accept the growth and let the CI HANA leg prove it fits; or trim with a target in the two csproj files that keeps only `win-x64`, `win-x86` and `linux-x64` natives (about +15 MB net).
- **chosen (user, U-14):** accept, with no trimming target.
- **rejected:** trimming to `win-x64` / `win-x86` / `linux-x64`. It needs a custom MSBuild target over package assets for a disk margin not yet shown to be short.
- **failure mode of the choice:** the GitHub HANA leg runs out of disk. That shows up as a CI failure, and trimming becomes the fallback (a P11 amendment).

### D-6 — Stop packing v4.5; drop the staging reference
- **chosen:** remove the two `tools/Sap.Data.Hana.v4.5.dll` `<None>` items and the `NuGet/NuGet.csproj:46-49` `<Reference>` in one commit (#5535 / PR #5565: a `<None>` without its source is NU5019).
- **rejected:** keep the NuGet.csproj reference so the in-repo `Tests/Tests.T4` native templates keep a staged copy (U-11). The in-repo tools folder would then differ from the shipped one, and in-repo T4 would stop testing what users get.
- **rejected:** establish redistribution terms. No terms are on record, and the packaged licence (SAP DLA 3.2 §1, §2(a)) forbids it.
- **why this:** chosen by the user. The bundled copy cannot connect without an installed client, and the installed client already provides it (U-6).
- **failure mode of the choice:** a T4 user without a HANA client install gets "Cannot load assembly … Sap.Data.Hana.v4.5" instead of the native-load failure they get today. Both mean "install the client"; the PR body and `NuGet/README.md` say so.

### D-7 — Licence inventory
- **chosen:**
  - remove component `sap-hana-client` from `components.json`, together with its `revisit`;
  - delete `Build/licenses/texts/sap-developer-license-3.2.txt`, otherwise `-Action check` fails on an unreferenced text (`third-party-notices.ps1:349-353`);
  - regenerate `generated/` with `-Action generate`;
  - add no component for the test-only packages.
- **rejected:** keep the component with `redistribution: unresolved`. `verify` has no reverse check (`third-party-notices.ps1:628-724`), so the notices would keep listing SAP for a file that is no longer shipped.
- **why this:** `verify` reads only produced nupkg/lpx/publish artifacts, and Tests/ are not among them (scout, `third-party-notices.ps1:826-828`).
- **failure mode of the choice:** none known; `verify` fails loudly if a `Sap.Data.Hana*` file is still packed.

## P6 Edit-points

- E-1 `Directory.Packages.props:providers group` — add `Sap.Data.Hana.Net.v8.0` 2.30.27 (`!IsTargetFrameworkCompatible(net10.0)`) and `Sap.Data.Hana.Net.v10.0` 2.30.27 (`=='net10.0'`)
- E-2 `Tests/Linq/Tests.csproj` — replace the v8.0 `HintPath` `<Reference>` with per-TFM `PackageReference`s (v8.0 net8/9, v10.0 net10) under the existing X86STUBS condition; reword its comment; condition the `libadonetHDB*.dll` `None` items to `TargetFramework == net462`
- E-3 `Tests/Tests.Playground/Tests.Playground.csproj` — same as E-2; update the mirror comment at :15-17
- E-4 `Redist/SapHana/v8.0/*`, `Redist/SapHana/libadonetHDB.pdb`, `Redist/SapHana/libadonetHDB32.pdb` — delete
- E-5 `Source/LinqToDB/Internal/DataProvider/SapHana/SapHanaProviderAdapter.cs:UnmanagedAssemblyNames` — new `#elif NET10_0_OR_GREATER` list with `"Sap.Data.Hana.Net.v10.0"` first; net8 list unchanged (D-5)
- E-6 `Source/LinqToDB/Internal/DataProvider/SapHana/SapHanaProviderDetector.cs:DetectProvider` — add `case "Sap.Data.Hana.Net.v10.0":` in both switches (:26-31, :72-77)
- E-7 `Source/LinqToDB.CLI/CommandLine/Commands/Scaffold/ScaffoldCommand.Execute.cs:SapHanaProbePathes` — add `v10.0\Sap.Data.Hana.Net.v10.0.dll` under `#if NET10_0_OR_GREATER`; list v10.0 in the :287 error text
- E-8 `Source/LinqToDB.CLI/CommandLine/Commands/Scaffold/ScaffoldCommand.Options.cs:125` — list `Sap.Data.Hana.Net.v10.0.dll` in the `--provider-location` help
- E-9 `Source/LinqToDB.CLI/CommandLine/Commands/Mcp/McpInfoTool.cs:48` — mention `Sap.Data.Hana.Net.v10.0.dll` beside v8.0
- E-10 `Tests/Base/X86Stubs/HanaStubs.cs:4` — reword the "x64-only" comment (D-4)
- E-11 `NuGet/SapHana/linq2db.SapHana.csproj:37` — remove the `None` item that packs Sap.Data.Hana.v4.5.dll into tools
- E-12 `NuGet/t4models/linq2db.t4models.csproj:114` — remove the same item
- E-13 `NuGet/NuGet.csproj:46-49` — remove the `Sap.Data.Hana.v4.5` `<Reference>`
- E-14 `Build/licenses/components.json:sap-hana-client` — remove the component
- E-15 `Build/licenses/texts/sap-developer-license-3.2.txt` — delete
- E-16 `Build/licenses/generated/THIRD-PARTY-NOTICES.linq2db.SapHana.txt`, `Build/licenses/generated/THIRD-PARTY-NOTICES.linq2db.t4models.txt` — regenerate via `-Action generate` (never hand-edited)
- E-17 `Build/licenses/README.md:11,96-98`, `Build/Azure/scripts/third-party-notices.ps1:12-14` — drop the SAP HANA client from the "redistributed from Redist/" prose and the header comment
- E-18 `Redist/Readme.md` — v4.5 no longer redistributed; v8.0 now from nuget; natives kept for net462 only
- E-19 `NuGet/README.md:23` — `LinqToDBT4SapHanaClientPath`: the package no longer carries the SAP client; native T4 needs an installed HANA client (machine.config factory) or the property pointed at a folder that contains `Sap.Data.Hana.v4.5.dll`
- E-20 `Tests/Linq/DataProvider/SapHanaTests.cs` — new test: provider name `Sap.Data.Hana.Net.v10.0` resolves to the native provider (TO-2)

## P7 Impact map

- `Source/LinqToDB/Internal/DataProvider/SapHana/SapHanaProviderAdapter.cs:162-167` (adapter load loop over `UnmanagedAssemblyNames`) — searched `UnmanagedAssemblyNames` across the worktree — covered by E-5
- `Source/LinqToDB/Internal/DataProvider/SapHana/SapHanaProviderDetector.cs:26-31,72-77` (name `case` labels) and `:89-93` (auto-detect via `IsProviderAssemblyPresent` over the list) — searched `Sap\.Data\.Hana\.Net` — covered by E-6 (switches); `:89-93` is covered by E-5 through the list
- `Source/LinqToDB/DataProvider/SapHana/SapHanaFactory.cs:21` (ordinal compare of the config `assemblyName` against the list) — searched `UnmanagedAssemblyNames` — covered by E-5 (the net10 build now also accepts `Sap.Data.Hana.Net.v10.0`)
- `Source/LinqToDB.LINQPad/DatabaseProviders/SapHanaProvider.cs:57-60,79-85,104-106,119-126` (ClearAllPools, factory, file-dialog names, default path `…\dotnetcore\v10.0\…`) — searched `UnmanagedAssemblyNames` — covered by E-5, no LINQPad edit; the driver loads the net8.0 linq2db build, whose list E-5 leaves unchanged, so LINQPad behaviour is unchanged (U-10, U-16)
- `Source/LinqToDB.CLI/CommandLine/Commands/Scaffold/ScaffoldCommand.Execute.cs:170-177,255-256,287` (probe paths under `HDBDOTNETCORE` / `%ProgramFiles%\sap\hdbclient\dotnetcore`) — searched `hdbclient|dotnetcore|Sap\.Data\.Hana\.Net` — covered by E-7
- `Source/LinqToDB.CLI/CommandLine/Commands/Scaffold/ScaffoldCommand.Options.cs:125`, `Source/LinqToDB.CLI/CommandLine/Commands/Mcp/McpInfoTool.cs:48` (help text) — searched `Sap\.Data\.Hana\.Net` — covered by E-8, E-9
- `Source/LinqToDB/PublicAPI/PublicAPI.Shipped.txt:8931,8932,15814` (adapter constants and list field) — searched `SapHanaProviderAdapter\.` over `PublicAPI*.txt` — out-of-scope: a value change of a `static readonly` field, no signature change
- `Source/LinqToDB/DataOptionsExtensions.Provider.cs:744,764`, `DataProviders.json:134`, `UserDataProviders.json.template:837` (version-free `Sap.Data.Hana`) — searched `Sap\.Data\.Hana` — out-of-scope: no version list
- `Source/LinqToDB/DataProvider/SapHana/SapHanaProvider.cs:13` (stale XML doc "Sap.Data.Hana or Sap.Data.Hana.Core") — searched `Sap\.Data\.Hana` — out-of-scope: already stale, not falsified by this change (P3)
- `Tests/Linq/Tests.csproj:14-31,55-60`, `Tests/Tests.Playground/Tests.Playground.csproj:15-37` (HintPath and native copy) — searched `Redist[\\/]SapHana|libadonetHDB` — covered by E-2, E-3
- `Tests/linq2db.Providers.props` / `Tests/linq2db.TestProjects.props:4` / `Tests/Tests.Benchmarks/linq2db.Benchmarks.csproj:2` / `Tests/Tests.T4/Tests.T4.csproj:2` (importers) — searched `linq2db\.Providers\.props|linq2db\.TestProjects\.props` — out-of-scope by D-2 (no edit; nothing new reaches T4 or Benchmarks)
- `Tests/Directory.Build.props:7` (`HANASTUBS` define), `Tests/Base/X86Stubs/HanaStubs.cs:1-13` (stub `HanaDecimal`), `Tests/Linq/DataProvider/Types/SapHanaTypeTests.cs:8,47-158` (its only compile-time consumer) — searched `HANASTUBS|X86STUBS` — covered by E-10 (comment only, D-4); the package stays behind the X86STUBS condition, so there is no CS0433 clash with the stub
- `.github/workflows/tests.yml:274,286,288,324,327,424-429` and `Build/Azure/pipelines/templates/build-job.yml:108-142,360-377` (Tests build/publish; net8+ portable, net462 `-a x64`, x86 `-a x86` + `X86STUBS` on netcore) — searched `dotnet (build|publish|test)|-a |-r |X86STUBS` — out-of-scope: no edit. A portable publish keeps `runtimes/` (U-1), and x86 netcore stays stubbed (D-4)
- `Build/Azure/pipelines/templates/test-workflow-linux.yml:159-168`, `Build/CI/run-provider-tests.sh:145` (portable binaries run on Linux) — searched `linq2db\.Tests\.dll` — out-of-scope: HANA runs ODBC only there (U-7); the native is never loaded
- `Tests/Linq/TestsInitialization.cs:44-105,167-195` (native or assembly resolvers) — searched `libadonetHDB|NativeLibrary|SetDllImportResolver|AssemblyResolve|HDB` — out-of-scope: no HANA resolver; nothing loads `libadonetHDB` from the output root
- `NuGet/NuGet.csproj:46-49`, `NuGet/SapHana/linq2db.SapHana.csproj:37`, `NuGet/t4models/linq2db.t4models.csproj:114` (staging and pack) — searched `Sap\.Data\.Hana\.v4\.5|ToolsPath` — covered by E-11, E-12, E-13
- `Directory.Build.props:224,236` (`LinqToDBT4SharedTools` / `LinqToDBT4SapHanaClientPath`), `NuGet/SapHana/linq2db.SapHana.props:4`, `NuGet/t4models/linq2db.t4models.props:15` (client path → `tools\`), `NuGet/SapHana/LinqToDB.SapHana.ttinclude:1` (the only `<#@ assembly`: `System.Data.Odbc.dll`) — searched `LinqToDBT4SapHanaClientPath|<#@ assembly` — out-of-scope: unchanged; the folder simply no longer holds the SAP dll (U-11). Doc covered by E-19
- `Tests/Tests.T4/Default/SapHana.tt` (native default against the shared tools folder), `Tests/Tests.T4.Nugets/Templates/Hana.Native.tt:11`, `Hana.ODBC.tt:11` (defaults to native, U-12) — searched `LoadSapHanaMetadata` — deferred: these resolve via the installed client (U-6), proven by TO-7; the Hana.ODBC quirk is P10
- `Build/licenses/components.json:2233-2256`, `Build/licenses/texts/sap-developer-license-3.2.txt`, `Build/licenses/generated/THIRD-PARTY-NOTICES.linq2db.{SapHana,t4models}.txt` — searched `sap-hana-client|sap-developer-license|SAP|Hana` over `Build/licenses` — covered by E-14, E-15, E-16
- `Build/licenses/README.md:11,96-98`, `Build/Azure/scripts/third-party-notices.ps1:12-14`, `Redist/Readme.md:1,7,11,14`, `NuGet/README.md:23` (prose claiming the SAP client is redistributed) — searched `(?i)hana` over those files — covered by E-17, E-18, E-19
- `.github/workflows/build.yml:134-140`, `Build/Azure/pipelines/templates/build-job.yml:259-273` (notices `check` + `verify` on every PR) — searched `third-party-notices` — out-of-scope: unchanged gate that proves E-11…E-16 (TO-6)
- `nuget.config:3-11` (`packageSourceMapping` `*`), `Directory.Packages.props:3-4` (CPM on, transitive pinning off) — searched `packageSourceMapping|ManagePackageVersionsCentrally|TransitivePinning` — covered by E-1 (no config change)
- `linq2db.docs` repo `source/articles/cli-help.txt:69` (carries the E-8 help text verbatim) and its T4 articles, plus the GitHub wiki (structurally unreachable from this branch) — searched `Sap\.Data\.Hana` in the sibling `linq2db.docs` clone (critic) — deferred: the docs repo is updated by the release docs PR (`/release-postpublish`); release notes are drafted per PR by `/release-notes`, not here
- `.claude/docs/review-rubric/rubric-packaging.md:12`, `.claude/knowledge-base/areas/T4-TEMPLATES/INDEX.md:134`, `areas/PROV-SAPHANA/INDEX.md:61` (corpus or KB prose naming the bundled SAP client or the v8.0 list) — searched `(?i)hana` over `.claude/` — deferred: a corpus commit for the rubric line after merge; the KB refreshes through `/kb-refresh`

## P8 Test obligations

- TO-1 net10.0 `Tests.DataProvider.SapHanaTests` + `Tests.DataProvider.Types.SapHanaTypeTests` with E-1/E-2 applied (the v10.0 package is the only client) and E-5/E-6 not yet applied must fail with `Cannot load assembly by name(s) Sap.Data.Hana.Net.v8.0, …`; with E-5/E-6 applied they pass. Discriminating input: the net10.0 output holds `Sap.Data.Hana.Net.v10.0.dll` and no other HANA client. Before the red run, delete `.build/bin/Tests/<cfg>/net10.0/` and the matching `obj` so that no 2.23.27 `Sap.Data.Hana.Net.v8.0.dll` or root `libadonetHDB*.dll` survives an incremental build, and record the output directory's `Sap.Data.Hana*` / `libadonetHDB*` listing as the observation — providers: SapHana.Native — proof: red→green
- TO-2 E-20 test: `DataConnection.GetDataProvider("Sap.Data.Hana.Net.v10.0", <connection string of the context>)` returns a provider whose `Name` is `ProviderName.SapHanaNative`. On master the detector has no case for that name, so the expected red is `null` (U-17). It is gated with `[IncludeDataSources(ProviderName.SapHanaNative)]`, so it runs only where the native client is configured. Run on net10.0 and net8.0 — providers: SapHana.Native — proof: red→green
- TO-3 net8.0 `SapHanaTests` + `SapHanaTypeTests` on `Sap.Data.Hana.Net.v8.0` 2.30.27 (was the 2.23.27 Redist copy). The natives resolve from `runtimes/win-x64/native` (U-1) — providers: SapHana.Native — proof: characterization (proves the package swap, no new behaviour)
- TO-4 net462 `SapHanaTests` smoke with the kept 2.23.27 natives copied to the net462 output only — providers: SapHana.Native — proof: characterization
- TO-5 net10.0 `SapHanaTests` on ODBC: symmetry guard on the unchanged ODBC path through the same detector — providers: SapHana.Odbc — proof: characterization
- TO-6 `dotnet pack` of `NuGet/SapHana/linq2db.SapHana.csproj` and `NuGet/t4models/linq2db.t4models.csproj` (Release): no `Sap.Data.Hana*` entry in either nupkg, and `third-party-notices.ps1 -Action check` and `-Action verify -PackagesDir .build/package/release` pass. Control mutation: restore E-11's `<None>` and the E-13 `<Reference>` while keeping E-14, and `verify` must fail with "maps to no component" for `tools/Sap.Data.Hana.v4.5.dll` — providers: none — proof: control
- TO-7 netfx resolution without a bundled copy, on this box (HANA client installed, U-6). Windows PowerShell 5.1 (a netfx host) loads the Release net462 `linq2db.dll` from `.build/bin/NuGet/Release/net462` (E-13 applied, so no `Sap.Data.Hana.v4.5.dll` beside it). It calls `LinqToDB.Internal.Common.Tools.TryLoadAssembly("Sap.Data.Hana.v4.5", "Sap.Data.Hana")` and must get a non-null assembly from the GAC through the machine.config factory. Its location is recorded — providers: none — proof: characterization (documents the user path D-6 relies on; no DB)
- TO-8 `dotnet publish Tests/Linq/Tests.csproj -f net8.0 -a x86 -p:X86STUBS=True` builds, and the produced test assembly loads and lists tests, so no `Sap.Data.Hana*` assembly is in the output — providers: none — proof: characterization

E-n → TO-n map: E-1, E-2, E-3, E-4 → TO-1, TO-3, TO-4, TO-8. E-5, E-6 → TO-1, TO-2, TO-5. E-11, E-12, E-13, E-14, E-15, E-16 → TO-6, TO-7. E-20 → TO-2. Waived, with no TO-n:
- E-7, E-8, E-9 (CLI probe path and help strings). No fixture pins the CLI HANA probe list (`Sap\.Data\.Hana` over `Tests/` hits only `[ThrowsForProvider]` strings), and the release CLI scaffold track skips SapHana by default (`release-test-cli-scaffold.ps1:70-72`). They are verified by the Release build and by reading the diff.
- E-10, E-17, E-18, E-19 (comments and prose). Verified by reading the diff.

## P9 Verification gates

- G-01: pass — all runs local against `hana2` via `worktree-test.ps1` (Tests/Linq, Debug).
  - TO-1 red: net10.0, clean output holding only `Sap.Data.Hana.Net.v10.0.dll` 2.30.27 plus `runtimes/*/native`, engine unfixed. 31/32 failed with `Cannot load assembly by name(s) Sap.Data.Hana.Net.v8.0, Sap.Data.Hana.Net.v6.0, Sap.Data.Hana.Core.v2.1`.
  - TO-2 red: the v10.0 case failed `provider should not be null but was`.
  - TO-1/TO-2 green: after E-5/E-6, 30/32 passed, including both `ClientProviderNameResolvesToNativeProvider` cases.
  - TO-3: net8.0, 30/32.
  - TO-4: net462, 30/32 on the kept 2.23.27 natives.
  - TO-5: net10.0 SapHana.Odbc, 27 passed / 0 failed / 2 skipped.
  - TO-6: both Release nupkgs have no `Sap.Data.Hana*` / `libadonetHDB` entry. `-Action check` OK (22 texts, all referenced). `-Action verify` OK (SapHana: 3 components; t4models: 29; 0 unmapped). Control: restoring the E-11 `<None>` and E-13 `<Reference>` failed verify with `'tools/Sap.Data.Hana.v4.5.dll' maps to no component`; reverted.
  - TO-7: Windows PowerShell 5.1 (CLR 4.0.30319.42000, x64) loaded `.build/bin/LinqToDB/Release/net462/linq2db.dll`, which has no SAP dll beside it. `Tools.TryLoadAssembly("Sap.Data.Hana.v4.5","Sap.Data.Hana")` → `Sap.Data.Hana.v4.5, Version=2.23.27.0` from `GAC_MSIL`.
  - TO-8: the net8.0 x86 `X86STUBS` publish has no HANA files, and `--list-tests` discovered 963 tests with no load error.
  - The two 30/32 residuals, `CalculationViewLinqQuery` and `TestBinaryParameterSelect`, are pre-existing: master c82e21c35 with the Redist 2.23.27 client fails both the same way on SapHana.Native net10.0 (baseline worktree run). See P10.
- G-02: n/a locally — no SQL path changed. The CI HANA leg (ODBC) and the baselines PR should show no SapHana diff; confirm at CI.
- G-03: n/a — no new public surface. Only the value of `UnmanagedAssemblyNames` (in `LinqToDB.Internal`) changes, and the Release net10.0 build (RS0016/RS0017) is clean.
- G-04: n/a — no `CompatibilitySuppressions.xml` change; the Release pack of the two T4 packages succeeded.
- G-05: pass — `Source/LinqToDB` Release `-f netstandard2.0`, `-f net462` and `-f net10.0`; `Source/LinqToDB.CLI` Release (all TFMs); `Tests/Linq` Release `-f net10.0` (analyzers on the test edit); `Tests.Playground` Debug net8.0. All exit 0.
- G-06: pass — the diff touches only E-1…E-20 lines (`-Action reconcile`: unplanned []).
- G-07: pass — no Playground scratch; the only Playground change is E-3 csproj structure.
- G-09: — (pending) `/code-review` or `/review-pr` before the PR leaves draft

## P10 Adjudicated

- **The net10 client is tested only locally.** CI never runs SapHana.Native (U-7), so TO-1…TO-4 run locally against the `hana2` container, and CI covers only the build/pack/notices gates and the Linux ODBC leg. Adding a native CI leg is outside #5862.
- **Hana.ODBC.tt defaulting to native is pre-existing.** `Tests/Tests.T4.Nugets/Templates/Hana.ODBC.tt:11` defaults to `SapHanaProvider.Unmanaged` (U-12). This change does not alter it; it is proposed as a follow-up issue rather than fixed here.
- **`HANASTUBS` is kept although the package is AnyCPU** (D-4). Dropping it is proposed as a follow-up issue.
- **The LINQPad driver still does not provision the HANA package** through `GetNuGetPackages`. Now that `Sap.Data.Hana.Net.v8.0` exists on nuget.org it could; proposed as a follow-up issue.
- **Two `[ActiveIssue]` gates fail on SapHana.Native, and that predates this change.** `Tests/Linq/DataProvider/SapHanaTests.cs:243` (`TestBinaryParameterSelect`) and `:658` (`CalculationViewLinqQuery`) are scoped to `AllSapHana` but declare `ErrorTypeName = "System.Data.Odbc.OdbcException"`, because they were measured on CI, which runs ODBC only. On native they meet `LinqToDBConvertException` (Base-64 `FormatException`) and `Sap.Data.Hana.HanaException` (`invalid table name`). Measured identical on master c82e21c35 with the 2.23.27 Redist client, so the package swap does not cause them. Proposed as a follow-up: split each gate per provider.
- **About 65 MB more natives per net8/9/10 test output and CI artifact is accepted** (D-8, user answer U-14).
- **The netfx natives stay checked in** (D-3, measured U-2). Removing `Redist/SapHana` entirely needs a nuget source for the netfx client, and none exists.

## P11 Amendments

_None._

## P12 Critic verdict

**Round 1 — `weak`** (plan-critic, model `fable`, dispatched fresh with the plan and code only; fable contributed no design ideas this session). Objections, and what changed:

1. **v10.0 first in the shared net8+ list hands LINQPad's .NET 8 host a default path it cannot load.** `SapHanaProvider.cs:119-127,144-145`, `DynamicConnectionModel.cs:65`. Accepted: D-5 now gates v10.0 behind `#elif NET10_0_OR_GREATER` and E-5 is rewritten (U-16).
2. **The packages' natives add about 80 MB per TFM to outputs and CI artifacts, unquantified.** Measured as 79.8 MB per package against 14.9 MB of Redist natives, so +65 MB per TFM. Recorded as D-8 / U-14, which needs the user's answer.
3. **TO-1's discriminating input was asserted, not ensured** (incremental build leftovers). Accepted: TO-1 now names the clean-output step and records the directory listing.
4. **E-7…E-9 had no TO-n.** Accepted: there is now an explicit E→TO map, with E-7…E-10 and E-17…E-19 waived by name.
5. **P7 named no unreachable surface.** Accepted: there is now a row for the `linq2db.docs` `cli-help.txt:69` / T4 articles and the wiki, deferred to the release docs PR.
6. **Evidence pins.** Accepted: v10.0's own measurement is U-15, and TO-2's red is pinned to `null` (U-17).

What the critic searched:
- `Sap\.Data\.Hana|libadonetHDB|SapHana[\\/]|HANASTUBS` across the worktree, and `UnmanagedAssemblyNames` across `Source/`. Every hit is in a P7 row.
- The CI files for HANA (one leg, ODBC-only, on both CI systems).
- The x86 publishes: `X86STUBS` applies to restore and build alike, so CS0433 cannot arise.
- `third-party-notices.ps1` generate/check/verify: the E-14/E-15 coupling is confirmed, and TO-6's control message is real at `:588`.
- Strings in the v10.0 dll, both `machine.config`s, the netfx-only `AssemblyResolve`, the T4 projects (not run on CI) and the packed readmes.

Its strongest-point note: the P7 sweep was complete. No re-dispatch, because the revision narrows D-5 (it removes v10.0 from the net8 build) and adds no edit-point.
