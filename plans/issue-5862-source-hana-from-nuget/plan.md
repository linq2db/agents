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
- SC-4 the unchanged paths stay working: net462 SapHana.Native via the kept 2.23.27 natives, SapHana.Odbc, and the x86 `X86STUBS` publish → TO-4, TO-5, TO-8 (pre-A-1), TO-10 (after A-1, where x86 carries the real client)

## P3 Constraints & anti-goals

- No public API change outside `LinqToDB.Internal.*`. `SapHanaProviderAdapter.UnmanagedAssemblyNames` is `static readonly IEnumerable<string>` in `LinqToDB.Internal.DataProvider.SapHana` (`PublicAPI.Shipped.txt:15814`); only its value changes, and `PublicAPI.*.txt` is untouched.
- No SQL or query-cache change; nothing under `SqlQuery/` or `Translation/`. Existing baselines are unchanged; A-2 adds a new `SapHana.Native` baselines tree (G-02).
- Before A-2, the CI HANA leg ran only `SapHana.Odbc`, Linux, net8/9/10 (`Build/Azure/pipelines/templates/test-matrix.yml:282-294`, `Build/Azure/scripts/hana2.sh:75-106`). A-2 (D-12) adds `SapHana.Native` to the same leg; ODBC coverage must not shrink.
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
- U-7 Whether CI exercises SapHana.Native. Scout: no. The only HANA leg is `h_SAPHANA2`, Linux, net8/9/10, `SapHana.Odbc` only (`Build/Azure/pipelines/templates/test-matrix.yml:282-294`, `Build/Azure/scripts/hana2.sh:75-106`). So native proof was local, against the `hana2` container, which exists (status Exited); starting it needs the user's go-ahead. After A-2, Linux native runs in the GitHub `h_SAPHANA2` leg (D-12, TO-14) — resolved-by scout
- U-8 Restore-time traps. Scout: CPM is on (`Directory.Packages.props:3`), so `PackageVersion` entries are needed; `packageSourceMapping` is `*` → nuget.org (`nuget.config:3-11`); there is no lock file and transitive pinning is off (`Directory.Packages.props:4`); NuGetAudit is default-on with warnings-as-errors, and the packages have no dependencies (U-3). That `requireLicenseAcceptance` does not prompt in `dotnet restore` is reasoned, unprobed; the first restore settles it, and a prompt or error stops implementation for a re-plan — resolved-by scout
- U-9 Who gains the reference by placement. Scout: `Tests/linq2db.Providers.props` is imported by `Tests/linq2db.TestProjects.props:4` (→ Tests.csproj, Tests.Playground, Tests.T4) and directly by `Tests/Tests.Benchmarks/linq2db.Benchmarks.csproj:2`. Tests.T4 and Benchmarks use no HANA client (D-2) — resolved-by scout
- U-10 How LINQPad uses the list. Scout: `Source/LinqToDB.LINQPad/DatabaseProviders/SapHanaProvider.cs:57-60,79-85,104-106,119-126` iterates `UnmanagedAssemblyNames`. `TryGetDefaultPath` derives `v10.0` from the new name and probes `%ProgramFiles%\sap\hdbclient\dotnetcore\v10.0\Sap.Data.Hana.Net.v10.0.dll`. The driver is `net8.0-windows7.0` and loads the net8.0 linq2db build, so a NET10-only entry would never reach it (D-5). The SAP installer folder name is unverified and affects only the default-path suggestion — resolved-by scout
- U-11 Who else uses `ToolsPath`'s v4.5 copy. Scout: only `linq2db.SapHana.csproj:37` and `linq2db.t4models.csproj:114` pack it, and NuGet.csproj has no `.cs`. In-repo `Tests/Tests.T4` uses `LinqToDBT4SapHanaClientPath=$(LinqToDBT4SharedTools)` = `.build\bin\NuGet\Debug\net462\` (`Directory.Build.props:224,236`). Its native template `Tests/Tests.T4/Default/SapHana.tt` loses the staged copy and resolves through U-6, as a user will; `Tests/Tests.T4/Databases/SapHana.tt:9` is ODBC — resolved-by scout
- U-12 Pre-existing quirk. Scout: `Tests/Tests.T4.Nugets/Templates/Hana.ODBC.tt:11` calls `LoadSapHanaMetadata(GetConnectionString("SapHana.Odbc"))` with no provider argument, so it defaults to Unmanaged. This change does not cause it; deferred to P10 — resolved-by scout
- U-13 Whether the x86 HANA stub still has a reason. Measured (U-3): it existed because the Redist v8.0 assembly is x64-only (`Tests/Linq/Tests.csproj:24-26`, `Tests/Base/X86Stubs/HanaStubs.cs:4`), and the package is AnyCPU. The gate is kept anyway (D-4) — resolved-by probe
- U-14 Whether the +65 MB-per-TFM native payload is accepted or trimmed (D-8, measured). User, 2026-10-26: accept; the CI HANA leg proves it fits — resolved-by user answer
- U-15 Whether v10.0 itself carries the mechanisms U-1/U-2/U-4 measured on v8.0. Critic, measured by string search of `Sap.Data.Hana.Net.v10.0.dll` 2.30.27: `HanaDecimal`, `GetHanaDecimal`, `GetRealVector`, `GetTimeSpan`, `GetDateTimeOffset`, `HanaBulkCopyColumnMappingCollection`, `HanaRowsCopiedEventHandler`, `ClearAllPools`, `SearchNativeDlls`, `CheckDllVersion`, `HDBDOTNETCORE_NOVERSION` and `runtimes` are all present, matching v8.0 2.30.27 — resolved-by probe
- U-16 What a .NET 8 LINQPad host does with a v10.0 default path. Critic, reasoned, unprobed: a `lib/net10.0` assembly fails to bind on .NET 8. Made unreachable by D-5: the net8 build no longer lists v10.0 — resolved-by probe (design: D-5 gate)
- U-18 (A-1) Whether the HANA native search can find a LINQPad-provisioned package's natives. Measured by decompiling 2.30.27 `SearchNativeDlls` to its end; the order is (1) `<assembly dir>/runtimes/<rid>/native`, (2) the assembly dir and its subdirectories, (3) the current dir and its subdirectories, (4) the entry and executing assembly dirs and their subdirectories, (5) `HDBDOTNETCORE` (process, then user, then machine), (6) later, the installed-client paths. With a NuGet-cache layout, `lib/net8.0/<asm>.dll` sits beside `../../runtimes/<rid>/native`, so steps 1–4 miss the natives and only step 5 can reach them. LINQPad's real cache layout, and whether it shadow-copies the assembly, is unmeasured; the user answered that the proof is the user's manual LINQPad check — resolved-by user answer
- U-19 (A-1) Whether an x86 netcore test process loads the package's `win-x86/native/libadonetHDB32.dll`. A RID-specific `-a x86` publish flattens `runtimes/win-x86/native` into the output root (step 2 of U-18), and the managed assembly is AnyCPU (U-3). TO-10 runs it — resolved-by probe
- U-20 (A-1) The native failure of the two split gates. Measured on master c82e21c35 and on the branch, net10.0, SapHana.Native: `TestBinaryParameterSelect` → `LinqToDB.Common.LinqToDBConvertException: Mapping of column ':1' value failed` (inner `FormatException`, Base-64); `CalculationViewLinqQuery` → `Sap.Data.Hana.HanaException: invalid table name` — resolved-by probe
- U-21 (A-1, round-2 critic) What `HDBDOTNETCORE` holds on a machine with a HANA client. Measured on this box (the TO-13 host): Machine scope `C:\Program Files\sap\hdbclient\dotnetcore`, set by the installer, holding `libadonetHDB.dll` 2.23.27; User scope empty; `HDBDOTNETCORE_NOVERSION` unset. SAP reads Process → User → Machine, version-checks each candidate and continues on a mismatch, then tries `…\hdbclient\ado.net` and every `PATH` entry, and finally throws `Cannot find a matching libadonetHDB.dll with version <v>` (decompile `:18326-18449`). So a "skip if already set" helper always skips on exactly the machines the native provider's existing users have, and the 2.30.27 client then finds only 2.23.27 natives. The helper must override the Process value — resolved-by probe
- U-22 (A-1) Whether provisioning the HANA package in LINQPad's "all packages" branch is acceptable (35 173 652-byte nupkg, measured by the critic). User: accept — resolved-by user answer
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

### D-9 (A-1, supersedes D-4) — Drop the HANA x86 stubs
- **chosen:** remove `HANASTUBS` from the `X86STUBS` defines, delete `Tests/Base/X86Stubs/HanaStubs.cs`, and reference the HANA packages on x86 too. The x86 builds keep `DB2STUBS`.
- **rejected:** keep the stub (D-4). Its only reason, an x64-only managed assembly, is gone (U-3, U-13).
- **failure mode of the choice:** an x86 process may fail to load `libadonetHDB32` through the flattened layout. TO-10 runs native HANA on x86 to rule that out.

### D-10 (A-1) — Per-provider gates
- **chosen:** split each of the two `AllSapHana` gates into a `SapHana.Odbc` gate (unchanged: `OdbcException` plus its message) and a `SapHana.Native` gate carrying the measured native failure (U-20).
- **rejected:** widen one gate to accept either type. A gate pins one failure, and two failures on two clients are two facts.
- **issue for the native defect (user, round 2) → superseded by a probe:** the plan was to treat the native `TestBinaryParameterSelect` failure as a fixable linq2db defect and file an issue. `/create-issue`'s verification step probed it instead: with the 2.30.27 native client, `SELECT :p FROM DUMMY` with a `DbType.Binary` parameter reports `GetFieldType` = `System.String` / `varchar`, returning the bytes as characters. That is a server typing limit on a bare select-list parameter in raw SQL, which linq2db cannot cast. The user chose a `no-issue:` gate, which `testing.md` permits for a probed server limit, and no issue is filed. The ODBC gates and the native `CalculationViewLinqQuery` gate (an unprovisioned view: an environment gap) stay `no-issue:`.
- **failure mode of the choice:** none known beyond the issue's own resolution.

### D-11 (A-1) — LINQPad provisions the native HANA client
- **chosen:** on the `!NETFRAMEWORK` driver, `GetNuGetPackages(SapHanaNative)` returns `Sap.Data.Hana.Net.v8.0` at the version of `Directory.Packages.props` (a new `NuGetPackageVersions.Sap_Data_Hana_Net_v8_0` constant).
  - Its `lib/net8.0` runs on LINQPad 8 and 9 hosts, and the driver's TFM expands only the net8-compatible `PackageVersion` entry (`LinqToDB.LINQPad.csproj:170-176`).
  - The native provider stops supporting a provider path: `IsProviderPathSupported`, `GetProviderAssemblyNames`, `TryGetDefaultPath` and `RegisterProviderFactory` fall back to the base defaults.
  - One idempotent helper sets the **Process-scope** `HDBDOTNETCORE` to the package's `runtimes/<rid>/native`. It derives that from the `Sap.Data.Hana.Net.v8.0` assembly's location (`<asm dir>/../../runtimes/<rid>/native`; RID = `RuntimeInformation.RuntimeIdentifier` since A-3). It sets the variable **unconditionally** whenever that folder exists, overriding any inherited value (round-2 critic, U-21), and does nothing only when the folder is missing. A-5 (critic round 5): the handler unsubscribes only after it has set the variable. `AssemblyLoad` and `GetAssemblies()` cover every load context in the process, so a copy without package natives must not end the subscription before the provisioned copy loads in another context. Examples of such a copy: an installed client's dll that a static context references by HintPath, or a byte-loaded copy. A-3 had unsubscribed on the first `FullName` match. LINQPad's load-context layout is unprobed.
  - The trigger is an `AppDomain.CurrentDomain.AssemblyLoad` handler, subscribed once when `SapHanaProvider` is constructed. Construction happens at driver init, in the driver process, through the static `DatabaseProviders` registry. The handler fires when `Sap.Data.Hana.Net.v8.0` loads; the subscription also checks the already-loaded set, in case the assembly was loaded first.
    - Why this trigger: SAP's native search runs in `static HanaConnection()` (→ `HanaUnmanagedDll.Instance`), and a failed type initialiser is sticky for the process. `AssemblyLoad` fires before any type in the assembly initialises, so it covers every path that loads the client: dynamic `GetDataProvider`, `GetProviderFactory` → `HanaFactory.CreateConnection`, `ClearAllPools`, and a **static context's** own first query (`StaticLinqToDBDriver.cs:115-118`).
    - Round 3: the round-2 three-call-site list covered dynamic paths only. `class:` every path that loads the client into the process.
  - An assembly that never loads (package not resolvable), and a missing `runtimes/<rid>/native` folder, both leave the variable untouched.
  - Accepted cost (user, U-22): the "all packages" branch (`DriverHelper.cs:379-384`, a connection being created or a static context naming no database) now also downloads the 35 MB package (80 MB extracted).
  - The LINQPad 5 (`net472`) path is unchanged.
- **rejected:** keep the provider path as an optional override. `DriverHelper.cs:272-277` makes a path mandatory whenever one is supported, and a user-picked assembly loaded with `LoadFrom` next to the provisioned package would put two `Sap.Data.Hana.Net.v8.0` copies in one process.
- **rejected:** provision v10.0 on .NET 10 hosts. The driver is a single `net8.0-windows7.0` build, so a per-host choice would need a runtime package decision the version constants cannot express. v8.0 runs on both hosts.
- **failure mode of the choice:**
  - LINQPad's cache layout may not keep `runtimes/` beside `lib/` (U-18, unmeasured). The native connection would then fail with SAP's "cannot find libadonetHDB" error, and the fallback is a re-plan.
  - A saved native connection's `ProviderPath` is still passed through `DatabaseProviders.GetDataProvider:134-135`, but `RegisterProviderFactory` is now the base no-op, so it is ignored.
  - Users whose server needs an older client lose the path override.

### D-12 (A-2) — SapHana.Native on the Linux CI leg
- **chosen (user):** run `SapHana.Native` beside `SapHana.Odbc` in the existing `h_SAPHANA2` leg (Azure, plus the GitHub twin through the same `hana2.sh`; Linux; net8/9/10). It gets one connection in `AzureConnectionStrings` and one provider-list entry per TFM in the generated `HanaDataProviders.json`.
  - The test binaries are portable publishes, so they carry `runtimes/linux-x64/native/libadonetHDB.so`, which SAP's step 1 finds.
  - On non-Windows the version check is off (decompile `:18205-18208`).
- **rejected:** a separate native leg. It pays a second HANA container start, which is minutes per TFM.
- **failure mode of the choice:**
  - The native provider has never run in CI, and most HANA `[ActiveIssue]` gates were measured on ODBC only. The first run will surface native-only failures (two are already measured on Windows, U-20). Each is triaged: fix, or a per-provider gate with its measured failure. The budget is two CI rounds; then stop and ask.
  - The leg's test phase roughly doubles. Its duration is recorded in G-11.

### D-13 (A-2) — macOS for the LINQPad 8+ driver
- **chosen:** no platform gate exists for SAP HANA (`IsPlatformSupported` defaults to `true`). The native provider was unusable on macOS only because it needed a Windows-shaped client path. With D-11's package and `HDBDOTNETCORE` handler, macOS should work: the handler takes the folder name from `RuntimeInformation.RuntimeIdentifier` (A-3; SAP's own first candidate), and the package ships `osx-x64` / `osx-arm64` natives, which SAP's loader picks by file name itself. README's macOS section marks it untested (A-4).
- **failure mode of the choice:** unmeasured. No Mac is available, so TO-13's macOS cell is waived and the README marks macOS native HANA untested (A-4).

### D-14 (A-5) — No SAP HANA in a Windows ARM64 LINQPad process
- **chosen (user):** `SapHanaProvider.IsPlatformSupported` is false when the process runs on Windows with `ProcessArchitecture == Arm64`. The connection dialogs then hide the database and `DatabaseProviders` provisions no client for it. An x64 LINQPad under emulation on ARM reports `X64` and keeps SAP HANA. README's SAP HANA line says so.
  - measured 2026-10-28 (SAP download page): the SAP HANA Client 2.0 downloads, both the install package and the components (.NET Core, ODBC, ADO.NET), list only "Windows x64" for Windows.
  - measured (restored package): `Sap.Data.Hana.Net.v8.0` 2.30.27 ships no `runtimes/win-arm64`.
  - Neither the native nor the ODBC provider can load a client in an ARM64 process.
- **rejected:** hide only the native provider. The ODBC driver is x64-only too, and `ProviderInfo.IsHidden` exists for retired provider names, not for platform gating.
- **failure mode of the choice:** a future SAP Windows ARM64 client would stay hidden until this gate is lifted. The LINQPad 5 `.lpx` (net472) reads the same check.

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
- E-21 `Tests/Directory.Build.props:7` — drop `HANASTUBS` from the `X86STUBS` defines (A-1, D-9)
- E-22 `Tests/Base/X86Stubs/HanaStubs.cs` — delete (A-1, D-9; supersedes E-10)
- E-23 `Tests/Linq/Tests.csproj`, `Tests/Tests.Playground/Tests.Playground.csproj` — HANA `PackageReference`s lose the `X86STUBS != True` condition; drop the stub comment (A-1, D-9; amends E-2/E-3)
- E-24 `Tests/Linq/DataProvider/SapHanaTests.cs:TestBinaryParameterSelect,CalculationViewLinqQuery` — split each `AllSapHana` gate into an ODBC gate and a native gate (A-1, D-10)
- E-25 `Tests/Tests.T4.Nugets/Templates/Hana.ODBC.tt:11` — pass `LinqToDB.DataProvider.SapHana.SapHanaProvider.ODBC` (A-1)
- E-26 `Source/LinqToDB.LINQPad/DatabaseProviders/SapHanaProvider.cs` — provision `Sap.Data.Hana.Net.v8.0` for native, drop the native provider-path members, set the Process-scope `HDBDOTNETCORE` from an `AssemblyLoad` handler (A-1, D-11)
- E-27 `Source/LinqToDB.LINQPad/LinqToDB.LINQPad.csproj:GenerateNuGetPackageVersions` — add the `Sap_Data_Hana_Net_v8_0` constant (A-1, D-11)
- E-29 `DataProviders.json:AzureConnectionStrings` — add `SapHana.Native` (`Provider: Sap.Data.Hana`, `Server=localhost:39017;Current Schema=TESTDB;UserID=SYSTEM;Password=Passw0rd;`) beside `SapHana.Odbc` (A-2, D-12)
- E-30 `Build/Azure/scripts/hana2.sh:HanaDataProviders.json` — add `SapHana.Native` to the NET80/NET90/NET100 `Providers` lists (A-2, D-12)
- E-31 `Source/LinqToDB.LINQPad/README.md:51-53` — macOS section: SAP HANA native uses the provisioned package's macOS client, marked untested on macOS (A-2, D-13, A-4: the macOS cell is waived, no Mac available).
- E-32a (A-2, measured 2026-10-26, Windows, net10.0, hana2) — the banner-anchored gates were red on **every** host but Linux ODBC. `DeleteTests.cs:606,651` and `DateTimeFunctionsTests.cs:2676,2707` pinned `[SAP AG][LIBODBCHDB SO][HDBODBC]`, but Windows ODBC says `LIBODBCHDB DLL` and native carries no banner; the server text is identical everywhere. They are re-anchored on `sql syntax error: incorrect syntax near "("` and `TIMESTAMP and PARAMETER are invalid for addition operator`, which is the gates' own stated "type-less, both drivers" intent. `SapHanaTypeTests.cs:164` drops `ErrorTypeName` (native raises `HanaException` with the same text). `IssueTests.cs:1022` already matches native, because its text is native-side.
- E-32b (A-2, CI round 1, GitHub 40386381883 net8 and 40387388875 net10, 2026-10-26) — `Build/Azure/scripts/hana2.sh` and `DataProviders.json` give SapHana.Native its own schema `TESTDBNATIVE`. With one shared `TESTDB` the two parallel lanes' `CreateDatabase` destroyed each other's data (run 40377212660: ~3.9k failures on both providers); the separate schema follows the SQL Server `.MS` precedent. After the split, net8 had 19 285 cases and 1 failure, so native ran in full. Two remaining native failures:
  - `Tests/Linq/DataProvider/ProviderSpecificReaderValueTests.cs:SapHanaProviderSpecificReadMatrix`: the native client returns `HanaDecimal` from both `GetProviderSpecificValue` and `GetValue` (its `return hanadecimal` option defaults to true, already in 2.23.27). The expected type is now per provider, measured locally on Windows native (string `123.45` unchanged).
  - `Tests/Linq/Linq/QueryGenerationTests.cs:ToSqlQuery_WithParametersDeduplication(SapHana.Native.LinqService, False)`: remote baseline ≠ direct, reproduced locally. Direct emits `:"firstName"` and `:"firstName_1"`; remote emits `:"firstName"` twice. Cause: `RemoteDataContextBase.QueryRunner.cs:81` renders with `NoopQueryParametersNormalizer`, while direct uses the provider's `UniqueParametersNormalizer` (`DataProviderBase.cs:505`), and HANA native is order-dependent, so the reused parameter is duplicated. This is the Access OleDb entry already tracked in #5169, so HANA native joins that test's existing `DisableBaseline`.
- E-32 `Tests/**` native gates and fixes (A-2, D-12). Known now by inspection (round 4), each to be measured on Windows native before the first CI round: `Tests/Linq/Update/DeleteTests.cs:606,651` and `Tests/Linq/Linq/DateTimeFunctionsTests.cs:2676,2707` (`AllSapHana` gates pinning the ODBC banner `[SAP AG][LIBODBCHDB SO][HDBODBC]`), `Tests/Linq/DataProvider/Types/SapHanaTypeTests.cs:164` (unscoped `OdbcException`), `Tests/Linq/Linq/IssueTests.cs:1022` (ODBC-side text). Then whatever the first Linux native CI run demands: one gate or fix per measured failure, each confirmed by a local Windows native run that fixes `Platforms` (Linux-only vs Any) and the message form (`testing.md:81`), and added here by name as triage lands. Budget: two CI rounds, then stop and ask.
- E-33 `NuGet/SapHana/CopyMe.SapHana.tt.txt:10` — the starter template notes that the native provider needs the SAP HANA client installed (A-3, review finding 8)
- E-34 `Tests/Tests.Wasm/ProviderMatrix.cs:163` — the `SapHana.Native` row's `UnavailableReason` says the client comes from SAP's NuGet packages, not `Redist` (A-5; the file arrived with the master merge of #6178). E-7 and E-8 also qualify the v10.0 entry as "(.NET 10+)" in the not-found error and in the `--provider-location` help, following the code's `NET10_0_OR_GREATER` gate (A-5, review MIN001, wording per critic round 5).
- E-35 `Source/LinqToDB.LINQPad/DatabaseProviders/SapHanaProvider.cs` — `IsPlatformSupported` is false for a Windows ARM64 process (D-14), and `PointToPackageNatives` returns true only after it sets `HDBDOTNETCORE` (D-11 as of A-5). `Source/LinqToDB.LINQPad/README.md:20` notes the ARM64 gap (A-5).
- E-28 `Source/LinqToDB.LINQPad/README.md:20` — SAP HANA native no longer needs an installed client on LINQPad 8+; keep the qualifiers that stay true (LINQPad 5 native, and ODBC, still need the installed client or driver) (A-1, D-11)

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
- `.github/workflows/tests.yml:274,286,288,324,327,424-429` and `Build/Azure/pipelines/templates/build-job.yml:108-142,360-377` (Tests build/publish; net8+ portable, net462 `-a x64`, x86 `-a x86` + `X86STUBS` on netcore) — searched `dotnet (build|publish|test)|-a |-r |X86STUBS` — out-of-scope: no edit. A portable publish keeps `runtimes/` (U-1). After A-1 (D-9), the x86 netcore publishes (`tests.yml:424-426`, `build-job.yml:363-365`) carry `Sap.Data.Hana.Net.v8.0.dll` plus the flattened `libadonetHDB32.dll` — about two 35 MB restores more on a job whose margin is thin (KB `areas/BUILD/INDEX.md:173`); proven by G-10
- `Build/Azure/pipelines/templates/test-workflow-linux.yml:159-168`, `Build/CI/run-provider-tests.sh:145` (portable binaries run on Linux) — searched `linq2db\.Tests\.dll` — before A-2: HANA ran ODBC only there (U-7). After A-2: native runs there too, finding `runtimes/linux-x64/native/libadonetHDB.so` at SAP step 1 — covered by E-29, E-30 (TO-14)
- `Tests/Linq/TestsInitialization.cs:44-105,167-195` (native or assembly resolvers) — searched `libadonetHDB|NativeLibrary|SetDllImportResolver|AssemblyResolve|HDB` — out-of-scope: no HANA resolver; nothing loads `libadonetHDB` from the output root
- `NuGet/NuGet.csproj:46-49`, `NuGet/SapHana/linq2db.SapHana.csproj:37`, `NuGet/t4models/linq2db.t4models.csproj:114` (staging and pack) — searched `Sap\.Data\.Hana\.v4\.5|ToolsPath` — covered by E-11, E-12, E-13
- `Directory.Build.props:224,236` (`LinqToDBT4SharedTools` / `LinqToDBT4SapHanaClientPath`), `NuGet/SapHana/linq2db.SapHana.props:4`, `NuGet/t4models/linq2db.t4models.props:15` (client path → `tools\`), `NuGet/SapHana/LinqToDB.SapHana.ttinclude:1` (the only `<#@ assembly`: `System.Data.Odbc.dll`) — searched `LinqToDBT4SapHanaClientPath|<#@ assembly` — out-of-scope: unchanged; the folder simply no longer holds the SAP dll (U-11). Doc covered by E-19
- `Tests/Tests.T4/Default/SapHana.tt` (native default against the shared tools folder), `Tests/Tests.T4.Nugets/Templates/Hana.Native.tt:11`, `Hana.ODBC.tt:11` (defaults to native, U-12) — searched `LoadSapHanaMetadata` — deferred: these resolve via the installed client (U-6), proven by TO-7; the Hana.ODBC quirk is P10
- `Build/licenses/components.json:2233-2256`, `Build/licenses/texts/sap-developer-license-3.2.txt`, `Build/licenses/generated/THIRD-PARTY-NOTICES.linq2db.{SapHana,t4models}.txt` — searched `sap-hana-client|sap-developer-license|SAP|Hana` over `Build/licenses` — covered by E-14, E-15, E-16
- `Build/licenses/README.md:11,96-98`, `Build/Azure/scripts/third-party-notices.ps1:12-14`, `Redist/Readme.md:1,7,11,14`, `NuGet/README.md:23` (prose claiming the SAP client is redistributed) — searched `(?i)hana` over those files — covered by E-17, E-18, E-19
- `.github/workflows/build.yml:134-140`, `Build/Azure/pipelines/templates/build-job.yml:259-273` (notices `check` + `verify` on every PR) — searched `third-party-notices` — out-of-scope: unchanged gate that proves E-11…E-16 (TO-6)
- `nuget.config:3-11` (`packageSourceMapping` `*`), `Directory.Packages.props:3-4` (CPM on, transitive pinning off) — searched `packageSourceMapping|ManagePackageVersionsCentrally|TransitivePinning` — covered by E-1 (no config change)
- `linq2db.docs` repo `source/articles/cli-help.txt:69` (carries the E-8 help text verbatim) and its T4 articles, plus the GitHub wiki (structurally unreachable from this branch) — searched `Sap\.Data\.Hana` in the sibling `linq2db.docs` clone (critic) — deferred: the docs repo is updated by the release docs PR (`/release-postpublish`); release notes are drafted per PR by `/release-notes`, not here
- `Tests/Tests.Wasm/ProviderMatrix.cs:163` (the WASM matrix's `SapHana.Native` `UnavailableReason` naming `Redist`; `:90` `NotOnNet` is Informix/Oracle only) — searched `(?i)redist|hana` over `Tests/Tests.Wasm` on the merged head 5ab7af3b9 — covered by E-34 (A-5)
- `Source/LinqToDB.CLI/**` v10.0 mentions (`ScaffoldCommand.Execute.cs:173,290`, `ScaffoldCommand.Options.cs:125`, `McpInfoTool.cs:48`) — searched `Sap\.Data\.Hana\.Net\.v10\.0|provider-location` over `Source/LinqToDB.CLI` — covered by E-7, E-8, E-9; after A-5 every user-facing mention qualifies v10.0 as .NET 10 only. `SKILL.md` names no HANA assembly.
- `Source/LinqToDB.LINQPad/**` macOS prose (`README.md:3,51-62`, `UI/Notification.cs:19,39`, `DB2Provider.cs:50`) — searched `(?i)macos|osx` over `Source/LinqToDB.LINQPad` — covered by E-31 (A-4: only `README.md:53` names SAP HANA; the rest are unrelated)
- `.claude/docs/review-rubric/rubric-packaging.md:12`, `.claude/knowledge-base/areas/T4-TEMPLATES/INDEX.md:134`, `areas/PROV-SAPHANA/INDEX.md:61` (corpus or KB prose naming the bundled SAP client or the v8.0 list) — searched `(?i)hana` over `.claude/` — deferred: a corpus commit for the rubric line after merge; the KB refreshes through `/kb-refresh`

## P8 Test obligations

- TO-1 net10.0 `Tests.DataProvider.SapHanaTests` + `Tests.DataProvider.Types.SapHanaTypeTests` with E-1/E-2 applied (the v10.0 package is the only client) and E-5/E-6 not yet applied must fail with `Cannot load assembly by name(s) Sap.Data.Hana.Net.v8.0, …`; with E-5/E-6 applied they pass. Discriminating input: the net10.0 output holds `Sap.Data.Hana.Net.v10.0.dll` and no other HANA client. Before the red run, delete `.build/bin/Tests/<cfg>/net10.0/` and the matching `obj` so that no 2.23.27 `Sap.Data.Hana.Net.v8.0.dll` or root `libadonetHDB*.dll` survives an incremental build, and record the output directory's `Sap.Data.Hana*` / `libadonetHDB*` listing as the observation — providers: SapHana.Native — proof: red→green
- TO-2 E-20 test: `DataConnection.GetDataProvider("Sap.Data.Hana.Net.v10.0", <connection string of the context>)` returns a provider whose `Name` is `ProviderName.SapHanaNative`. On master the detector has no case for that name, so the expected red is `null` (U-17). It is gated with `[IncludeDataSources(ProviderName.SapHanaNative)]`, so it runs only where the native client is configured. Run on net10.0 and net8.0 — providers: SapHana.Native — proof: red→green
- TO-3 net8.0 `SapHanaTests` + `SapHanaTypeTests` on `Sap.Data.Hana.Net.v8.0` 2.30.27 (was the 2.23.27 Redist copy). The natives resolve from `runtimes/win-x64/native` (U-1) — providers: SapHana.Native — proof: characterization (proves the package swap, no new behaviour)
- TO-4 net462 `SapHanaTests` smoke with the kept 2.23.27 natives copied to the net462 output only — providers: SapHana.Native — proof: characterization
- TO-5 net10.0 `SapHanaTests` on ODBC: symmetry guard on the unchanged ODBC path through the same detector — providers: SapHana.Odbc — proof: characterization
- TO-6 `dotnet pack` of `NuGet/SapHana/linq2db.SapHana.csproj` and `NuGet/t4models/linq2db.t4models.csproj` (Release): no `Sap.Data.Hana*` entry in either nupkg, and `third-party-notices.ps1 -Action check` and `-Action verify -PackagesDir .build/package/release` pass. Control mutation: restore E-11's `<None>` and the E-13 `<Reference>` while keeping E-14, and `verify` must fail with "maps to no component" for `tools/Sap.Data.Hana.v4.5.dll` — providers: none — proof: control
- TO-7 netfx resolution without a bundled copy, on this box (HANA client installed, U-6). Windows PowerShell 5.1 (a netfx host) loads the Release net462 `linq2db.dll` from `.build/bin/NuGet/Release/net462` (E-13 applied, so no `Sap.Data.Hana.v4.5.dll` beside it). It calls `LinqToDB.Internal.Common.Tools.TryLoadAssembly("Sap.Data.Hana.v4.5", "Sap.Data.Hana")` and must get a non-null assembly from the GAC through the machine.config factory. Its location is recorded — providers: none — proof: characterization (documents the user path D-6 relies on; no DB)
- TO-8 `dotnet publish Tests/Linq/Tests.csproj -f net8.0 -a x86 -p:X86STUBS=True` builds, and the produced test assembly loads and lists tests, so no `Sap.Data.Hana*` assembly is in the output. **Superseded by TO-10 after A-1**: D-9 puts the client on x86, so this row's "no `Sap.Data.Hana*`" assertion describes the pre-A-1 tree only — providers: none — proof: characterization

- TO-9 (A-1) The `SapHanaTests` suite on SapHana.Native and SapHana.Odbc, net10.0: `TestBinaryParameterSelect` and `CalculationViewLinqQuery` end Inconclusive (gate matched) on both providers, where before A-1 they failed on native. Discriminating input: the native failure types of U-20 — providers: SapHana.Native, SapHana.Odbc — proof: red→green (red = the measured G-01 native failures)
- TO-10 (A-1) `dotnet publish Tests/Linq/Tests.csproj -f net8.0 -a x86 -p:X86STUBS=True`: the output holds `Sap.Data.Hana.Net.v8.0.dll` and `libadonetHDB32.dll`. The x86 exe run on `SapHanaTests` with `--provider SapHana.Native` passes the suite except the two gated tests, so the 32-bit native loads — providers: SapHana.Native — proof: characterization
- TO-11 (A-1) The LINQPad driver builds on both channels (`net472` and `net8.0-windows7.0`, Release). The generated `NuGetPackageVersions` carries `Sap_Data_Hana_Net_v8_0 = "2.30.27"` — providers: none — proof: characterization
- TO-12 (A-1, rewritten after round 2) The `HDBDOTNETCORE` override, on a NuGet-cache layout and with this box's Machine `HDBDOTNETCORE=…\hdbclient\dotnetcore` (2.23.27) inherited. A net8 probe process opens a `HanaConnection` to `hana2` (green). Setup: (1) the probe loads `Sap.Data.Hana.Net.v8.0` 2.30.27 by path from the global-packages folder (`lib/net8.0`, no `runtimes/` sibling), not through a `PackageReference`, and asserts `typeof(HanaConnection).Assembly.Location` is that path; (2) it applies the E-26 handler logic; (3) its cwd and entry-assembly dir are pinned to a scratch tree that holds no 2.30.27 native, because SAP's steps 2–4 search those dirs recursively before step 5. Mutation: the same process with the handler skipped must fail with `Cannot find a matching libadonetHDB.dll with version 2.30.27`, and that arm's "Searched paths and results" list is recorded, naming the step that matched (red). Discriminating input: the inherited 2.23.27 Machine value — providers: SapHana.Native — proof: control
- TO-14 (A-2, revised after round 4) The GitHub `h_SAPHANA2` leg runs SapHana.Native on Linux. A PR run covers net10 only: `testing.yml` offloads the leg to GitHub (`full_run: false`, `offload_linux_to_github: true`), and the main suite there is net10-only (`tests.yml:595-600`). net8/net9 need one `tests.yml` `workflow_dispatch` with `surface: [saphana.all]`, `full_run: true` and the branch ref. Positive observation (round-4 objection 2): the trx must contain `CreateDatabase(SapHana.Native)` and a `(SapHana.Native)` case count comparable to `(SapHana.Odbc)`, because a config that does not take would otherwise be a green ODBC-only run. Every native test passes or ends Inconclusive under a per-provider gate; the first run's native failures are the red, and the triage commits are the green — providers: SapHana.Native — proof: red→green
- TO-13 (A-1, A-2) The real LINQPad 8/9 native HANA connection — a dynamic connection and a static context naming SAP HANA on this box (Machine `HDBDOTNETCORE` → 2.23.27), plus a macOS cell (waived by A-4: no Mac available; D-13, recording time to first native connection and any permission prompt, because SAP step 3 searches a Finder-launched app's cwd `/` recursively) — providers: SapHana.Native — proof: characterization (manual: the user's LINQPad check, U-18; not run by the agent)

E-n → TO-n map: E-1, E-2, E-3, E-4 → TO-1, TO-3, TO-4, TO-8. E-21, E-22, E-23 → TO-10. E-24 → TO-9. E-26, E-27 → TO-11, TO-12, TO-13. E-25, E-28: waived. The `.tt` fix can only be exercised by the release T4 track (a VS T4 host against `hana2`), and its committed `Hana.ODBC.generated.cs` stays as generated until that track regenerates it; E-28 is prose. E-5, E-6 → TO-1, TO-2, TO-5. E-11, E-12, E-13, E-14, E-15, E-16 → TO-6, TO-7. E-20 → TO-2. Waived, with no TO-n:
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
- G-01 (A-1/A-2): pass for the locally runnable obligations; all runs are local, net10.0, against `hana2` unless stated.
  - TO-9: `SapHanaTests` plus the E-32a set — SapHana.Native 53 cases, 0 failed, 23 gated; SapHana.Odbc 50 cases, 0 failed, 23 gated. One ODBC TearDown `connect timeout expired` on `TestBinaryFromDb` passed on rerun, a capacity transient (P10).
  - TO-10: x86 net8.0 publish carries `Sap.Data.Hana.Net.v8.0.dll` and `libadonetHDB32.dll` 2.30.27; the x86 exe `--provider SapHana.Native` on `SapHanaTests` gives 28 passed, 0 failed, 2 gated.
  - TO-11: LINQPad Release on `net472` and `net8.0-windows7.0` builds; `Sap_Data_Hana_Net_v8_0 = "2.30.27"`.
  - TO-12: green arm connected; control arm `FileNotFoundException … version 2.30.27` with only 2.23.27 candidates searched.
  - TO-13: pass (2026-10-27, user's manual check on LINQPad 8/9 with `linq2db.LINQPad` 6.6.0-local.4 from `651ab4ce7`, against `hana2`, Machine `HDBDOTNETCORE` → 2.23.27): the dynamic native connection queries; the static cell queries through a scratch net8.0 `DataConnection` context (`SapHana.Native`, no SAP assembly in its output, database set to SAP HANA). macOS cell waived (A-4).
  - TO-14: pending CI.
  - `test-diff-sweep.ps1 -IncludeWorkingTree`: 0 chains, 0 nested chains. One narrowed set, `SapHanaTests.cs:814` `[IncludeDataSources(ProviderName.SapHanaNative)]` on `ClientProviderNameResolvesToNativeProvider`, which tests the native provider name by definition.
  - The native `TestBinaryParameterSelect` gate is `no-issue:` per the probe in D-10 and the user's answer.
- G-02: n/a locally — no SQL path changed. Confirm at CI that the baselines PR shows no diff under `SapHana.Odbc/`. After A-2 it gains a new `SapHana.Native/` tree (~3.9k files, the native mirror of `SapHana.Odbc/`). Review it via `baselines-reviewer` as a cross-provider comparison against `SapHana.Odbc/` (differences are expected only in parameter syntax).
- G-03: n/a — no new public surface. Only the value of `UnmanagedAssemblyNames` (in `LinqToDB.Internal`) changes, and the Release net10.0 build (RS0016/RS0017) is clean.
- G-04: n/a — no `CompatibilitySuppressions.xml` change; the Release pack of the two T4 packages succeeded.
- G-05: pass — `Source/LinqToDB` Release `-f netstandard2.0`, `-f net462` and `-f net10.0`; `Source/LinqToDB.CLI` Release (all TFMs); `Tests/Linq` Release `-f net10.0` (analyzers on the test edit); `Tests.Playground` Debug net8.0. All exit 0.
- G-06: pass — the diff touches only E-1…E-20 lines (`-Action reconcile`: unplanned []).
- G-07: pass — no Playground scratch; the only Playground change is E-3 csproj structure.
- G-09: pass — `/code-review` on 35af4f3e5 (A-3), then `/review-pr` on 5ab7af3b9 (A-5). Three passes covered code correctness, packaging / native loading / cross-TFM, and API and tests. They returned MIN001 and NIT001, both fixed on the branch, plus one D-11 wording observation. Baselines pass skipped by the user: 4,520 files added under `SapHana.Native/`, 0 modified, 0 deleted.
- G-11: pass (2026-10-27, head `b8f85e430`) — TO-14 is green.
  - GitHub `workflow_dispatch` full run [40401830136] (`[saphana.all]`, `full_run`), `h_SAPHANA2` main suite, 0 failed throughout: net8.0 19 285 cases (19 020 passed, 265 skipped); net9.0 19 329 (19 064 / 265); net10.0 19 365 (19 100 / 265).
  - PR run [40401874022]: net10.0 19 365 cases, 0 failed, and `h_SAPHANA2` green inside its 180-min cap.
  - Native and ODBC case mentions are comparable (1 437 vs 1 425 gated/skipped lines), so the native config took.
  - Two rounds were used. Round 1 found the shared-schema collision and two test expectations (E-32b), all fixed.
- G-11 (original wording): blocked — awaits the post-A-2 GitHub runs (A-2). The `h_SAPHANA2` leg is green with SapHana.Native included and its native case count present (TO-14): net10 on the PR run, net8/net9 on a `workflow_dispatch` `full_run`. There is no Azure HANA leg on PR runs. Its duration is recorded against the GitHub HANA job of run 40353552174 (ODBC-only) and the 180-min PR cap (`tests.yml:514`).
- G-10: pass (2026-10-27).
  - Azure (`azp-job-durations.ps1`, 24753 → 24771): `Build (win-x86)` 15.1 → 14.9 min, still ending about 3 min before `Build` (18.6 → 17.9 min); `Create Test Baselines Branch` ends at +18.9 min.
  - GitHub: `Build test artifacts (win-x86)` green in PR runs 40387388875 and 40401874022, both of which carry Access legs.
  - Azure 24771 and 24776 both succeeded (14/14 jobs).
- G-10 (original wording): blocked — awaits the post-A-1 CI run (A-1). A measurement, not a colour. The margin on `build_x86_job` is time (`build-job.yml:314-319`), so on Azure it is `azp-job-durations.ps1` on the post-A-1 branch run versus the pre-A-1 run 24753, comparing `build_x86_job`'s finish against `build_job` + `create_baselines_branch`. GitHub's `build_x86` runs only on a surface that selects an Access leg (`tests.yml:385,393`), so the gate also needs a green GitHub run on such a surface. Record both run ids.

## P10 Adjudicated

- **Windows native is tested locally; Linux native is tested in CI.** TO-1…TO-4 run locally against the `hana2` container. A-2 (D-12) adds Linux native to the GitHub `h_SAPHANA2` leg: net10 on PR runs, net8/net9 via `workflow_dispatch` `full_run`. Windows native and the netfx client stay local-only, because no Windows HANA leg exists.
- **A HANA resource error or a container death on the shared leg is a capacity problem, not a native defect (A-2, round 4).** Examples: an out-of-memory statement, an exit-137 container, a lane timeout while `SapHana.Native` and `SapHana.Odbc` lanes hit one memory-tuned HANA express (`Tests/Base/DatabaseLaneStrategy.cs:14-28`, `hana2.sh:47-73`). Such a failure gets no `ActiveIssue`. It is fixed in the leg (serialise the two providers, tune memory) or escalated to the user.
- **Hana.ODBC.tt defaulting to native is pre-existing.** `Tests/Tests.T4.Nugets/Templates/Hana.ODBC.tt:11` defaults to `SapHanaProvider.Unmanaged` (U-12). This change does not alter it; it is proposed as a follow-up issue rather than fixed here.
- **`HANASTUBS` is kept although the package is AnyCPU** (D-4). Dropping it is proposed as a follow-up issue.
- **The LINQPad driver still does not provision the HANA package** through `GetNuGetPackages`. Now that `Sap.Data.Hana.Net.v8.0` exists on nuget.org it could; proposed as a follow-up issue.
- **Two `[ActiveIssue]` gates fail on SapHana.Native, and that predates this change.** `Tests/Linq/DataProvider/SapHanaTests.cs:243` (`TestBinaryParameterSelect`) and `:658` (`CalculationViewLinqQuery`) are scoped to `AllSapHana` but declare `ErrorTypeName = "System.Data.Odbc.OdbcException"`, because they were measured on CI, which runs ODBC only. On native they meet `LinqToDBConvertException` (Base-64 `FormatException`) and `Sap.Data.Hana.HanaException` (`invalid table name`). Measured identical on master c82e21c35 with the 2.23.27 Redist client, so the package swap does not cause them. Proposed as a follow-up: split each gate per provider.
- **About 65 MB more natives per net8/9/10 test output and CI artifact is accepted** (D-8, user answer U-14).
- **SAP HANA is not offered in a Windows ARM64 LINQPad process** (D-14, user, A-5). SAP ships no Windows ARM64 client, which was measured on SAP's download page and in the package's `runtimes/`. An x64 LINQPad under emulation keeps it.
- **The netfx natives stay checked in** (D-3, measured U-2). Removing `Redist/SapHana` entirely needs a nuget source for the netfx client, and none exists.

## P11 Amendments

- A-1 (2026-10-26, user: "fix 3 here" — do the four proposed follow-ups in this PR; for LINQPad, option A: implement with the `HDBDOTNETCORE` pointer, proof by the user's manual LINQPad check). Adds E-21…E-28, D-9 (supersedes D-4), D-10, D-11, U-18…U-20 and TO-9…TO-13. Approval of the original E-1…E-20 stands; E-21…E-28 need approval after the delta critique.
  re-derives: P2 (SC-4), P4 (U-13), P5 (D-4), P6 (E-2, E-3, E-10), P7 (HANASTUBS row, CI publish row, LINQPad row, Tests.T4.Nugets row), P8 (TO-8), P9 (G-10), P10 (HANASTUBS, gate, LINQPad, Hana.ODBC entries)
  conventions: embedded `testing.md` → *Test layout*, *A narrowed provider set is a claim*, *Gating an assertion failure*; swept with `test-diff-sweep.ps1` on the implemented tree (counts in G-01)
- A-2 (2026-10-26, user: the package ships macOS/Linux natives, so LINQPad 7+ (the `!NETFRAMEWORK` driver) should offer native HANA on macOS, and a Linux CI leg must run the native provider; user picked "same leg"). Adds E-29…E-32, D-12, D-13, TO-14, G-11, and a macOS cell in TO-13.
  re-derives: P3 (the CI HANA leg is no longer ODBC-only), P4 (U-7), P7 (CI rows `test-matrix.yml:282-294` / `hana2.sh`, the Linux-run row), P8 (TO-13), P10 (the "net10 client tested only locally" entry — native now runs on Linux CI)
  conventions: as A-1; E-32 gates follow `testing.md` → *Gating an assertion failure* and *A narrowed provider set is a claim*
- A-3 (2026-10-27, `/code-review` walk, user dispositions). Nine leads: 1, 3, 6 and 7 dropped (adjudicated by U-18/U-22/D-2/D-6/U-11); 2, 4, 5, 8 and 9 fixed.
  - Finding 2: HANA package references and the v10.0 `PackageVersion` use `IsTargetFrameworkCompatible` so future TFMs inherit them (E-1/E-2/E-3).
  - Finding 4: `PointToPackageNatives` uses `RuntimeInformation.RuntimeIdentifier` instead of a hand-built RID; that is SAP's own first candidate.
  - Finding 5: the handler matches on `FullName` and unsubscribes after the first match (E-26).
  - Finding 8: the starter template notes the client requirement (new E-33).
  - Finding 9: the PR body's false claim about `LinqToDBT4SapHanaClientPath` is corrected (PR text, not a repo file).
  - Also from the baselines review: the native `ToSqlQuery_WithParametersDeduplication` exemption is narrowed to `!inlineParameters` (`b0c9c6eb5`).
  - No critic re-dispatch: the delta is review fixes inside existing edit-points plus one template comment line (E-33), with no new design.
  re-derives: P6 (E-1, E-2, E-3, E-26, E-33), P7 (the `nuget.config` / `Directory.Packages.props` CPM row for the `IsTargetFrameworkCompatible` conditions, the LINQPad row for the handler, the `LinqToDBT4SapHanaClientPath` / T4 template rows for E-33; re-walked in A-5, critic round 5)
- A-4 (2026-10-27, user: no Mac is available; "mark untested"). TO-13's macOS cell is waived, and E-31's README sentence now says SAP HANA native on macOS is untested instead of claiming it works. D-13's design is unchanged and stays unmeasured. The PR can leave draft after TO-13's dynamic and static cells pass. No critic re-dispatch: it is a prose downgrade of an unproven claim, with no new design.
  re-derives: P5 (D-13 failure mode), P6 (E-31), P7 (the `Source/LinqToDB.LINQPad/**` macOS-prose row, added in A-5), P8 (TO-13)
- A-5 (2026-10-28, `/review-pr` walk on 5ab7af3b9, the master merge of #6163 / #6178 / #6161 / #6171; user dispositions). Three passes, two findings and one observation, all handled on the branch.
  - MIN001: the CLI not-found error and the `--provider-location` help offered `Sap.Data.Hana.Net.v10.0.dll` on the net8/net9 builds, which neither probe nor load it. Both now say ".NET 10 only", matching `McpInfoTool.cs:48` (inside E-7/E-8).
  - NIT001: `Tests/Tests.Wasm/ProviderMatrix.cs:163`, which arrived with #6178, still called the native client a `Redist` assembly. New E-34 rewords it.
  - Observation: `PointToPackageNatives` unsubscribed on a name match even when it set nothing. The walk chose a D-11 rewording. Critic round 5 then showed the safety argument was per load context, while the handler is process-wide. The user chose to change the code: the handler now unsubscribes only after it sets the variable (E-35).
  - Critic round 5, Windows ARM64 lead: the user decided not to offer SAP HANA there. SAP ships no Windows ARM64 client, which was measured. New D-14 / E-35 add the gate, and README `:20` notes it.
  - Critic round 5, plan text: D-11's RID text and D-13's macOS text went stale after A-3 / A-4. Both are now re-derived. E-34's string no longer claims only Tests/Linq references the packages, because Tests.Playground does too.
  - The same amendment completes the A-3 and A-4 re-derivation lines. Critic round 5 covers A-3…A-5 together; D-14 itself was added in response to round 5 and has not been attacked.
  re-derives: P5 (D-11, D-13 text, new D-14), P6 (E-7, E-8, E-34, E-35), P7 (new `Tests/Tests.Wasm` row, including the E-5 → `WasmRuntimeTests.cs:127` interaction; new `Source/LinqToDB.CLI/**` v10.0-mention row), P10 (Windows ARM64)
  conventions: embedded `testing.md` → *Test layout*, *A narrowed provider set is a claim*. `test-diff-sweep.ps1 -IncludeWorkingTree` on the worktree found 0 chains, 0 nested chains and 1 narrowed set: `SapHanaTests.cs:814` `[IncludeDataSources(ProviderName.SapHanaNative)]` on `ClientProviderNameResolvesToNativeProvider`, which is native by design because it asserts the native mapping (E-20). E-34 changes one string. Its row also asserts `error.ShouldContain(row.UnavailableAssembly)` (`WasmRuntimeTests.cs:127`), and E-5 changes that value on net10 from `Sap.Data.Hana.Net.v8.0`, as #6178 was written, to `v10.0`. measured: the GitHub `WASM runtime tests` leg passed on 5ab7af3b9 (run 40597691679), which already carries E-5, so the interaction holds. E-34's string itself is not asserted.

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

**Round 2 (A-1 delta) — `refuted`** (plan-critic, `fable`). Objections, and what changed:

1. **Refuted.** D-11's "does nothing when `HDBDOTNETCORE` is already set" fails on the TO-13 host, where the installer sets Machine `HDBDOTNETCORE` to a 2.23.27 native (re-measured by the author, U-21). Accepted: the helper now overrides the Process value unconditionally, and TO-12 is rewritten to run with that Machine value present.
2. **Lead.** `GetProviderFactory` and `ClearAllPools` reach `HanaConnection`'s static initialiser without `GetDataProvider`, and a failed cctor is sticky. Accepted: the helper is called from all three entry points.
3. **Weak.** The LINQPad "all packages" branch adds a 35 MB download for every user in that state. Put to the user, who accepted it (U-22).
4. **Weak.** D-10 gated a fixable linq2db defect `no-issue:`, against `testing.md`. Put to the user: an issue is drafted via `/create-issue`, and the native gate cites it.
5. **Weak.** `re-derives:` missed the P7 CI publish row and SC-4/TO-8, and the CI x86 path had no gate. Accepted: both rows are re-derived, TO-8 is marked superseded, and G-10 is added.
6. **Minor.** E-28 should keep the README qualifiers for LINQPad 5 and ODBC. Accepted.

Re-dispatched on the revision (round 3) per the one-revision cap.

**Round 3 (A-1 revision) — `weak`** (plan-critic, `fable`). Carried forward visibly; all four folded in:

1. **The three call sites were instance-closed.** A static LINQPad context reaches `static HanaConnection()` through none of them. Accepted: D-11/E-26 now use an `AssemblyLoad` handler (class-closed), and TO-13 gains a static-context cell.
2. **G-10's "observed green" could not see a time-margin failure, and GitHub `build_x86` is surface-gated.** Accepted: G-10 is now a duration measurement against run 24753, plus a GitHub run on an Access surface.
3. **TO-12's red arm could pass at SAP step 3** (cwd recursive search, from TO-3's build output). Accepted: cwd and entry dir are pinned, `Assembly.Location` is asserted, and the searched-paths list is recorded.
4. **An unloadable assembly as a second no-op input was unstated.** Accepted: stated in D-11.

Its strongest-point note: U-21 and TO-12 line up with the decompiled search order and failure text. The cap of one revision round is reached: no further dispatch, and the verdict stands at `weak` with the objections above.

**Round 4 (A-2 delta) — `weak`** (plan-critic, `fable`). All seven objections are folded in:

1. **PR CI has no Azure HANA leg, and GitHub runs net10 only.** TO-14 and G-11 are rewritten: net10 on the PR run, net8/net9 via `workflow_dispatch` `full_run`.
2. **There was no negative for a config that does not take.** TO-14 now requires the native case count.
3. **CI-only gates cannot decide `Platforms`.** E-32 now requires a local Windows native confirmation per gate.
4. **Five native gate mismatches are decidable now.** They are named in E-32 and measured locally first.
5. **G-02 and P3 contradicted the new baselines tree.** Both are re-derived.
6. **Stale text.** P3, U-7, the P7 Linux row and the P10 entry are rewritten.
7. **The E-31 macOS claim was unproven.** It is now gated on TO-13's macOS cell before the PR leaves draft.

The two leads are recorded as well. The lane-concurrency lead is a P10 capacity rule. The macOS lead (cwd `/` recursive search) is added to TO-13's macOS cell.

The A-1 rounds' cap applied per amendment. A-2 had one round, `weak`, so it is carried forward visibly without re-dispatch.

**Round 5 (A-3, A-4, A-5 delta) — `weak`** (plan-critic, model `opus`, by user choice after fable hit its usage limit). `opus` is also the author's model, so this round is not an independent channel. It was dispatched fresh with the plan, the commits 35af4f3e5 / 651ab4ce7 and the A-5 working-tree diff. Objections, and what changed:

1. **D-11's A-5 safety argument was scoped to one load context, while the handler is process-wide.** A copy without natives could end the subscription before the provisioned copy loads. Code changed: the handler unsubscribes only after it sets the variable (E-35). D-11 is rewritten.
2. **D-11 and D-13 text went stale after A-3, and A-4's README contradicted D-13 "macOS works".** Both are re-derived against the code and the README.
3. **Lead: Windows ARM64 has no native client.** Measured on SAP's download page (Windows x64 only, ODBC included) and in the package (no `win-arm64`). User decision: new D-14 / E-35 hide SAP HANA in a Windows ARM64 LINQPad process, README `:20` says so, and a P10 entry records it. D-14 has not been attacked.
4. **E-34's string was inaccurate, because Tests.Playground also references the packages, and the E-5 → `WasmRuntimeTests.cs:127` interaction was unrecorded.** The string is reworded and the interaction recorded. The `WASM runtime tests` leg on 5ab7af3b9 or later is its run.
5. **MIN001's ".NET 10 only" pins one TFM and rests on an unprobed load failure.** Reworded to "(.NET 10+)", which follows the code's `NET10_0_OR_GREATER` probe gate.

What the critic searched:
- `git show` of 35af4f3e5 / 651ab4ce7 and the A-5 diff.
- `AssemblyLoadContext|LoadFrom|LoadFile|AssemblyResolve` over the LINQPad driver; no HANA `LoadFrom` is left.
- `Sap\.Data\.Hana\.Net\.v10` across the worktree; the CLI sweep is complete.
- `UnavailableReason|UnavailableAssembly` over `Tests/Tests.Wasm`.
- `IsTargetFrameworkCompatible` over props/csproj; A-3 Finding 2 holds.
- The merge's conflicted files and the notices numbering.

Strongest point: A-3's `RuntimeInformation.RuntimeIdentifier` matches SAP's own first candidate, measured by decompile.
