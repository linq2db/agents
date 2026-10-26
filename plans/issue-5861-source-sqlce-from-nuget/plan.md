# Work plan: issue-5861-source-sqlce-from-nuget — Source SQL Server Compact from its NuGet package, retire Redist/SqlCe

**Tier:** M  ·  **Status:** approved  ·  **Approved-at:** 2026-10-26 (P1–P10 as of critic round 1; cold-pack fix requested in scope → A-1)  ·  **Branch:** issue/5861-source-sqlce-from-nuget
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

## P1 Problem

`linq2db.SqlCe` and `linq2db.t4models` redistribute the SQL Server Compact 4.0 runtime from 19 hand-copied files in `Redist/SqlCe/` (`NuGet/NuGet.csproj:31-44` → `$(ToolsPath)` → `NuGet/SqlCe/linq2db.SqlCe.csproj:36-37`, `NuGet/t4models/linq2db.t4models.csproj:98,127`). The component has no NuGet identity: `Build/licenses/components.json:2260` (`sqlce-runtime`) carries `"packageId": ""` and a hand-typed `"net462": "4.0"`, so `third-party-notices.ps1 -Action harvest` (which matches components by `packageId`, `third-party-notices.ps1:881`) can never report its version. Observable: `harvest` output contains no `Microsoft.SqlServer.Compact` line, and the repo carries 19 checked-in binaries that the `Microsoft.SqlServer.Compact` 4.0.8876.1 package already provides — measured 2026-10-26: SHA-256 of all 19 `Redist/SqlCe` files equals the package's `lib/net40/System.Data.SqlServerCe.dll` and `NativeBinaries/**` (19/19 SAME).

## P2 Success criteria

- SC-1 `NuGet/NuGet.csproj` obtains `System.Data.SqlServerCe.dll` and the `amd64/` natives from the `Microsoft.SqlServer.Compact` package; no file under `Redist/SqlCe/` exists and no build file references it. → TO-1
- SC-2 The packed `linq2db.SqlCe` and `linq2db.t4models` nupkgs contain exactly the same SQL CE entries (path + SHA-256) as packs built from `origin/master`. → TO-2
- SC-3 `third-party-notices.ps1 -Action harvest` matches `Microsoft.SqlServer.Compact` to the `sqlce-runtime` component with no `[version]` drift, and `-Action check` / `-Action verify` stay clean over the produced packages. → TO-3
- SC-4 The notices text and docs no longer say SQL CE comes from `Redist/` or that its migration is pending; the EULA text stays the plain-text rendering in `Build/licenses/texts/` (user decision). → TO-4

## P3 Constraints & anti-goals (M/L)

- Shipped nupkg contents unchanged byte-for-byte for every SQL CE file (SC-2); no new file packed, none dropped.
- No change to what `NuGet/SqlCe/linq2db.SqlCe.csproj` / `NuGet/t4models/linq2db.t4models.csproj` / `NuGet/Informix/linq2db.Informix.csproj` pack (A-1 changes only *when* their folder globs expand), nor to `third-party-notices.ps1` logic (header comment only).
- `Redist/SapHana` untouched (#5862 owns it).
- Issue-scope narrowing: #5861 says the licence text should be "sourced from the package rather than converted by hand". Narrowed by user decision (2026-10-26): keep `Build/licenses/texts/microsoft-sqlserver-compact-4.0-eula.txt` as the plain-text rendering of the package's `SQLCE_EULA_ENU.rtf`; the generator reads plain text only and every other package-backed text in `texts/` is produced the same way. Disclose in the PR body.
- User-visible deltas vs master: none — consumers of the T4 packages receive identical files; only the notices text wording (version string `4.0` → `4.0.8876.1`, NuGet package line, notes) changes.

## P4 Unknowns (M/L)

- U-1 Package contents equal `Redist/SqlCe` for all files, not just the five #5731 hashed — resolved-by probe: downloaded nupkg to `.build/.agents/5861-sqlce-nupkg`, SHA-256 compare 19/19 SAME (2026-10-26).
- U-2 Package carries anything that acts under `PackageReference` beyond `lib/` (a `build/*.targets`, framework assemblies, dependencies) — resolved-by probe: nuget.org catalog entry lists 27 entries — `Content/web.config.transform` (ignored: not `contentFiles/`), `lib/net40/System.Data.SqlServerCe.dll`, `NativeBinaries/{amd64,x86}/**`, `tools/{Install,Uninstall}.ps1`, `tools/VS.ps*1` (ignored by PackageReference), `SQLCE_EULA_ENU.rtf`; no `build/`, no dependencyGroups, no frameworkAssemblies.
- U-3 Restore + build under `TreatWarningsAsErrors` raises no NU warning (`requireLicenseAcceptance: true`, `lib/net40` consumed by `net462`) — resolved-by probe: implementation step 1 builds `NuGet/NuGet.csproj -c Release` before any other edit lands; a warning stops the plan (P11).
- U-4 `nuget.config` package-source mapping admits the new id — resolved-by scout: `nuget.config:7-11` maps `*` to nuget.org; `Tests/Tests.T4.Nugets/nuget.config` is a consumer-test config that restores `linq2db*` packages, not NuGet.csproj.
- U-5 `harvest` reads the package from the NuGet graph — resolved-by scout: `Invoke-Harvest` defaults include `.build\obj\NuGet\project.assets.json` (`third-party-notices.ps1:827`) and `Get-GraphPackages` keeps a package with a `runtime` section (`:796`), which `lib/net40` produces; probed again by TO-3.
- U-6 Two components (`sqlce-runtime`, `msvc90-crt`) ship from one package — resolved-by scout: `harvest` and `Test-PayloadVersions` pick the first component by `packageId` (`:881`, `:487`); `Test-PayloadVersions` runs only on tool `deps.json` payloads, not T4 nupkgs. Giving `packageId` to `sqlce-runtime` only keeps one owner (D-2).
- U-7 Is the master pack baseline itself deterministic? — resolved-by probe (2026-10-26): no. A cold `dotnet pack NuGet/SqlCe/linq2db.SqlCe.csproj` packed 49 entries with **no** `tools/amd64/**`; re-packed after `NuGet.csproj` output existed it packed 58 (the 9 natives). `linq2db.SqlCe.csproj:37` globs `$(ToolsPath)/amd64/**` at evaluation, before the referenced project builds — the same ordering `linq2db.t4models.csproj:141-151` works around for `clidriver` with a target. Published 6.5.1 contains the natives (CI builds the solution before packing). Pre-existing, independent of this change; TO-2 packs both sides warm. Disposition: P10 L-3.

## P5 Decisions (M/L; rejected alternatives mandatory at L)

### D-1 — Copy natives from `$(PkgMicrosoft_SqlServer_Compact)` with the existing item shape

- **chosen:** `<PackageReference Include="Microsoft.SqlServer.Compact" GeneratePathProperty="true" />`; keep `SqlCeNativeLibs64/86` + `<None Link="amd64\…">` items, repointed to `$(PkgMicrosoft_SqlServer_Compact)\NativeBinaries\{amd64,x86}\**`. Same pattern as `IBM.Data.DB.Provider` / `Microsoft.SqlServer.Types` in the same file (`NuGet.csproj:23,51-65`).
- **rejected:** a `Copy` target after build — evaluation-time `None` items are what the existing code uses and what `CopyToOutputDirectory` handles incrementally; a target adds a second mechanism for no gain.
- **why this:** output layout `.build/bin/NuGet/<cfg>/net462/{System.Data.SqlServerCe.dll,amd64/**}` stays identical, so the pack projects and `Tests/Tests.T4` (`LinqToDBT4SharedTools`, `Directory.Build.props:224`) need no change.
- **failure mode of the choice:** `$(PkgMicrosoft_SqlServer_Compact)` is empty during evaluation before restore — the glob then matches nothing and the natives silently drop from output and nupkg. TO-2 catches it (entry-list compare).

### D-2 — `packageId` on `sqlce-runtime` only; `msvc90-crt` keeps `""`

- **chosen:** `sqlce-runtime.packageId = "Microsoft.SqlServer.Compact"`, `versions.net462 = "4.0.8876.1"`; `msvc90-crt` keeps an empty `packageId`, notes say it ships inside that package's native folders.
- **rejected:** both entries carrying the package id — harvest's `Select-Object -First 1` (`:881`) would compare against whichever sorts first, and the generated notices would print the package line twice for one package.
- **why this:** one package → one owning component, as everywhere else in the manifest.
- **failure mode of the choice:** a future package bump updates `sqlce-runtime` via harvest while `msvc90-crt.versions` stays `9.0` — correct, since that is the CRT's own version, not the package's.

## P6 Edit-points

- E-1 `Directory.Packages.props` — `Database Providers` group: add `<PackageVersion Include="Microsoft.SqlServer.Compact" Version="4.0.8876.1" />` in alphabetical position.
- E-2 `NuGet/NuGet.csproj` — replace the `System.Data.SqlServerCe` `HintPath` reference with a `PackageReference` (`GeneratePathProperty`) and repoint both native globs (D-1).
- E-3 `Redist/SqlCe/*` — delete all 19 files.
- E-4 `Redist/Readme.md` — drop the `SqlCe` bullet (`:8`) and the "SqlCe — settled" paragraph (`:13`); line 1 / 11 wording from "two" redistributed components to one (SapHana). Restates SC-4.
- E-5 `Build/licenses/components.json` — `sqlce-runtime` (`:2258-2282`): packageId, version, `projectUrl` → `https://www.nuget.org/packages/Microsoft.SqlServer.Compact`, notes rewritten (EULA rendered from the package's RTF; no Redist / #5861 mention); `msvc90-crt` (`:2019-2043`) notes only. Restates D-2.
- E-6 `Build/licenses/generated/THIRD-PARTY-NOTICES.linq2db.SqlCe.txt` — regenerated by `-Action generate`.
- E-7 `Build/licenses/generated/THIRD-PARTY-NOTICES.linq2db.t4models.txt` — regenerated by `-Action generate`.
- E-8 `Build/licenses/README.md` — `:11` (T4 row: SQL CE no longer "out of `Redist/`") and `:96-98`: the "both `Redist/` binaries with no license file" sentence is already false on master (`sap-hana-client` carries `sap-developer-license-3.2.txt`, `components.json:2241-2243`); rewrite it to point at SAP HANA's `redistribution: unresolved` / provenance instead of "no license file". Restates SC-4.
- E-9 `Build/Azure/scripts/third-party-notices.ps1` — header comment `:12-14` only: SQL CE runtime no longer listed as "out of Redist/".
- E-10 `NuGet/SqlCe/linq2db.SqlCe.csproj` — (A-1, A-2) move the static `$(ToolsPath)/amd64/**` `None … Pack="true"` line (`:37`) verbatim into a `BeforeTargets="_GetPackageFiles"` target (the `Source/LinqToDB.LINQPad/LinqToDB.LINQPad.Pack.csproj:82-91` shape: `None` in a target, no `_PackageFiles` write).
- E-11 `NuGet/t4models/linq2db.t4models.csproj` — (A-1, A-2) same for `amd64/**` (`:98`) and `x64/**` (`:99`); under A-3 merged with the former `IncludeClidriverInPack` into one `IncludeToolsFoldersInPack`.
- E-12 `NuGet/Informix/linq2db.Informix.csproj` — (A-1, A-2) same for `clidriver/**` (`:37`).
- E-13 `NuGet/DB2/linq2db.DB2.csproj:IncludeClidriverInPack` — (A-3) convert the existing `_PackageFiles` target to the `None`-in-target form; add the pack guard.
- E-2/E-10/E-11/E-12 additionally (A-3): `NuGet/NuGet.csproj` gets a `CheckSqlCeNatives` target (`BeforeTargets="CopyFilesToOutputDirectory"`, inner build only) erroring when `@(SqlCeNativeLibs64/86)` is empty; every pack-time target gets an `<Error>` on a sentinel file per folder (`amd64/sqlceme40.dll`, `x64/SqlServerSpatial170.dll`, `clidriver/bin/db2cli.dll`); t4models' two targets merge into one `IncludeToolsFoldersInPack`. E-8 additionally: `:96-98` reworded to name SAP HANA's `unresolved` redistribution (#5862).

## P7 Impact map (M/L)

- `NuGet/NuGet.csproj:31-44` — sole build reference to `Redist/SqlCe` (searched `Redist[\\/]SqlCe` across all non-corpus files) — covered by E-2
- `NuGet/SqlCe/linq2db.SqlCe.csproj:36-37` — packs `$(ToolsPath)/System.Data.SqlServerCe.dll` and `$(ToolsPath)/amd64/**`; output layout unchanged by D-1 — out-of-scope
- `NuGet/t4models/linq2db.t4models.csproj:98,127` — same `$(ToolsPath)` inputs — out-of-scope
- `Tests/Tests.T4` via `Directory.Build.props:224,237` (`LinqToDBT4SharedTools` = `.build/bin/NuGet/Debug/net462/`) and `NuGet/SqlCe/LinqToDB.SqlCe.ttinclude:1` — reads the same output folder — out-of-scope
- `Directory.Packages.props:141-180` — CPM requires a `PackageVersion` for the new reference — covered by E-1
- `nuget.config:7-11` — source mapping `*` → nuget.org admits the id (U-4) — out-of-scope
- `Build/licenses/components.json:2258-2282,2019-2043` — `sqlce-runtime` / `msvc90-crt`; `files` globs (`System.Data.SqlServerCe.dll`, `amd64/sqlce*.dll`, `tools/amd64/sqlce*.dll`, `x86/…`, `*/Microsoft.VC90.CRT/*`) unchanged because packed paths are unchanged — covered by E-5
- `Build/licenses/generated/THIRD-PARTY-NOTICES.linq2db.SqlCe.txt`, `Build/licenses/generated/THIRD-PARTY-NOTICES.linq2db.t4models.txt` — render the two components; CI `check` byte-compares — covered by E-6
- `Build/Azure/scripts/third-party-notices.ps1:827,881,487` — harvest default graphs and packageId lookups (U-5, U-6); no logic change — covered by E-9
- `Redist/Readme.md:1,8,11,13` — searched `Redist` in `**/*.md` — covered by E-4
- `Build/licenses/README.md:11,98` — same search — covered by E-8
- `CONTRIBUTING.md:35` — "`Redist`: binaries unavailable officially at NuGet" — still true for the remaining folders — out-of-scope
- `linq2db.slnx:269-270` — lists `Redist/Readme.md` only, no SqlCe file — out-of-scope
- `.gitignore:22` (`!Redist/**`) — still needed for SapHana etc. — out-of-scope
- Corpus/KB mentions (`.claude/knowledge-base/areas/PROV-SQLCE/issues.md:17`, `areas/BUILD/INDEX.md:249`, `docs/pr-and-push.md:24`, older plans) — KB is skill-maintained, the doc cites #5861 as a historical example — deferred: `/kb-refresh` picks up the closed issue
- (A-1) `NuGet/SqlCe/linq2db.SqlCe.csproj:37` — static `$(ToolsPath)/amd64/**` glob over a build-populated folder (searched `\$\(ToolsPath\)[^"]*\*` across `NuGet/`) — covered by E-10
- (A-1) `NuGet/t4models/linq2db.t4models.csproj:98,99` — `amd64/**`, `x64/**`, same search — covered by E-11
- (A-1) `NuGet/Informix/linq2db.Informix.csproj:37` — `clidriver/**`, same search — covered by E-12
- (A-1, A-3) `NuGet/DB2/linq2db.DB2.csproj:44-54`, `NuGet/t4models/linq2db.t4models.csproj:141-151` — pre-existing `_PackageFiles` targets with unqualified `%(RecursiveDir)`, safe only as sole writer; converted to `None`-in-target so one form remains — covered by E-13, E-11
- (A-1) non-wildcard `$(ToolsPath)/…` includes in all 14 `NuGet/*/linq2db.*.csproj` (e.g. `t4models.csproj:100,134` `arm64\…`, `x86\…` SqlServerSpatial170) — a literal item survives evaluation without the file existing; measured unaffected (cold t4models 388 = warm 388) — out-of-scope
- (A-3) `.claude/docs/release/linqpad-test-checklist.md:63-99` — teaches the `_PackageFiles` injection as "the fix" and states (`:88`) that `None` with `Pack="true"` "doesn't work even from inside a Target", which G-01 TO-5 (after A-3) refutes (DB2 272/272, nuspec SHA unchanged) — out-of-scope for this branch: rewritten in corpus commit 147da6e (user-approved 2026-10-26, agents repo, unpushed)
- External: nuget.org-rendered package metadata and wiki — not reachable by grep; package readmes (`NuGet/readme.t4.*`) do not mention Redist (searched `Redist` in `**/*.md`, `**/*.txt`) — out-of-scope

## P8 Test obligations (M/L)

- TO-1 `git grep -n "Redist.SqlCe" -- ':!.claude'` returns only historical prose (none in build files), `Redist/SqlCe` absent from `git ls-files`, and `dotnet build NuGet/NuGet.csproj -c Release` succeeds with zero warnings, output folder holding `System.Data.SqlServerCe.dll` + `amd64/` (9 files: 6 `sqlce*40*.dll` + 3 under `Microsoft.VC90.CRT/`) — providers: n/a (build) — proof: characterization
- TO-2 Pack `NuGet/SqlCe/linq2db.SqlCe.csproj` and `NuGet/t4models/linq2db.t4models.csproj` (Release) on `origin/master` and on the branch, each side packed **after** `NuGet.csproj` has built (U-7); entry-list compare over all entries must match; SHA-256 compare restricted to `tools/System.Data.SqlServerCe.dll` and `tools/amd64/**` (first-party dlls and `.nuspec` carry the commit SHA via SourceLink, `Directory.Build.props:99,207`); discriminating input: D-1's failure mode (empty `$(PkgMicrosoft_SqlServer_Compact)`) drops the 9 `tools/amd64/**` entries, so the compare goes red under mutation `Include="$(PkgMicrosoft_SqlServer_Compact_X)\NativeBinaries\amd64\**"` — providers: n/a (pack) — proof: control
- TO-3 harvest, three positive cells, each after a fresh `dotnet build NuGet/NuGet.csproj` so `.build/obj/NuGet/project.assets.json` is current: (a) after E-1/E-2, before E-5 → `[note] Microsoft.SqlServer.Compact net462=4.0.8876.1 …` (`third-party-notices.ps1:883-887`); (b) after E-5 with `versions.net462` deliberately left `4.0` → `[version] Microsoft.SqlServer.Compact net462: manifest 4.0, resolved 4.0.8876.1` (`:898-899`); (c) final → neither line, and "Harvested N distinct package(s)" one higher than the master run; plus `-Action check` exit 0 and `-Action verify -PackagesDir <branch pack dir>` exit 0 — providers: n/a (script) — proof: red→green
- TO-4 regenerated notices for `linq2db.SqlCe` / `linq2db.t4models` show `Microsoft SQL Server Compact 4.0 4.0.8876.1`, `NuGet package: Microsoft.SqlServer.Compact`, and no `Redist` / `#5861` text; `git grep -n "Redist" -- Build/licenses Redist/Readme.md Build/Azure/scripts/third-party-notices.ps1` shows no SQL CE mention — providers: n/a (docs) — proof: red→green

- TO-5 (A-1) each of `linq2db.SqlCe`, `linq2db.t4models`, `linq2db.Informix` packed alone from a deleted `.build/bin/NuGet` yields the same entry list as its warm baseline (`5861-entries-master-warm.txt` / `5861-entries-master.txt` / `5861-entries-warm-before-Informix.txt`), with SHA-256 equal on every `tools/amd64/**`, `tools/x64/**`, `tools/clidriver/**` and `tools/System.Data.SqlServerCe.dll` entry; red on the unfixed csprojs is already measured (A-1: −9 / −10 / −223) — providers: n/a (pack) — proof: red→green

- TO-6 (A-3) each guard goes red on its own input: `NuGet.csproj` built with mutation `Include="$(PkgMicrosoft_SqlServer_Compact_X)\NativeBinaries\amd64\**"` fails with "SQL CE native binaries not found"; each of the six pack guards (SqlCe `amd64`; t4models `amd64`, `x64`, `clidriver`; Informix `clidriver`; DB2 `clidriver`) fails `dotnet pack --no-build` with its own message when that one folder is hidden; TO-5's green runs prove none fires on a good tree — providers: n/a (build/pack) — proof: control

## P9 Verification gates

All rows 2026-10-26 against the tree committed as e323e3192 (SQL CE switch) + e432ffdc0 (pack-time targets) on base c82e21c35 — measured on that exact content before the commits; rebased without conflicts onto d09089b15 as bd512b44e + b4b108ee5 (master's 2 new commits touch only `Source/LinqToDB*/` and `Tests/`), PR #6163; `-Action reconcile`: 31 considered, 0 unplanned; scratch evidence under `.build/.agents/5861-*` (primary clone). No `/test` run applies — every TO-n is a build / pack / script check.
- G-01 TO-1: pass — `git rm -r Redist/SqlCe` (19 files); `git grep -n "Redist.SqlCe" -- . ':!.claude'` empty; clean `dotnet build NuGet/NuGet.csproj -c Release` → `0 Warning(s)`, exit 0 (U-3 resolved); output `System.Data.SqlServerCe.dll` SHA `7F30232A…` = master pack's, `amd64/` 9 files.
- G-01 TO-2: pass — branch `linq2db.SqlCe` 58/58 entries vs master warm, 10 SQL CE entries hash-equal; `linq2db.t4models` 388/388 vs master, 234 hashed (SQL CE + x64 + clidriver) equal; only `THIRD-PARTY-NOTICES.txt` / `tools/THIRD-PARTY-NOTICES.txt` differ. Control mutation `Include="$(PkgMicrosoft_SqlServer_Compact_X)\NativeBinaries\amd64\**"` → `linq2db.SqlCe` 49 entries, the 9 `tools/amd64/**` missing (red); reverted. (A first mutation run was void — the edit had failed and the pack ran unmutated; re-run with the edit confirmed by `Select-String`.) Re-run after A-2 changed E-10 (`5861-entries-mut2-linq2db.SqlCe.txt`): same red, 49 entries, the 9 `tools/amd64/**` listed as only-before; reverted, `git grep Compact_X -- NuGet` empty.
- G-01 TO-3: pass — (a) after E-1/E-2: `[note] Microsoft.SqlServer.Compact net462=4.0.8876.1 license=…SQLCE_SP1_EULA_ENU.rtf (url)`; (b) packageId set, version `4.0`: `[version] Microsoft.SqlServer.Compact net462: manifest 4.0, resolved 4.0.8876.1`; (c) final: neither line, `Harvested 62` vs master graph (restored from stashed E-1/E-2) `Harvested 61`; `-Action check` exit 0 (16 files, 23 texts); `-Action verify -PackagesDir .build/.agents/5861-verify` (3 branch packs) exit 0, 0 unmapped.
- G-01 TO-4: pass — notices show `Microsoft SQL Server Compact 4.0 4.0.8876.1` / `NuGet package: Microsoft.SqlServer.Compact`, no `5861`; remaining `Redist/` mentions in `Build/licenses/README.md:11`, `third-party-notices.ps1:13`, `Redist/Readme.md` are SAP HANA only. E-8 `:96-98` implemented by deleting the stale "currently SQL CE and the SAP HANA client…" clause rather than re-pointing it (SAP HANA's status is stated in `Redist/Readme.md`).
- G-01 TO-5: pass (after A-2) — `5861-compare.ps1` per package, each cold (deleted `.build/bin/NuGet` before the pack) and then warm (CI order, output already built): `linq2db.SqlCe` 58/58, only-before 0, only-after 0, 10 hashed, 0 hash-diff; `linq2db.t4models` 388/388, 0/0, 234 hashed, 0 diff; `linq2db.Informix` 272/272, 0/0, 223 hashed, 0 diff — identical cold and warm (no duplicates); only `THIRD-PARTY-NOTICES.txt` / `tools/THIRD-PARTY-NOTICES.txt` differ (SqlCe, t4models). Red arm measured on master csprojs (A-1: −9 / −10 / −223). History: the pre-A-2 E-11 `_PackageFiles` form failed `NU5118` (unqualified `%(RecursiveDir)` batched over the clidriver items) — superseded by A-2.
- G-01 TO-5 (after A-3, re-run): pass — `5861-verify-all.ps1`, cold then warm: `linq2db.SqlCe` 58/58 (10 hashed, 0 diff), `linq2db.t4models` 388/388 (234, 0), `linq2db.Informix` 272/272 (223, 0), `linq2db.DB2` 272/272 vs warm master-csproj baseline `5861-entries-warm-before-DB2.txt` (223, 0); only the notices differ (SqlCe, t4models).
- G-01 TO-6: pass — six pack guards, each with its folder hidden, `dotnet pack --no-build`: exit 1 + own message for SqlCe `amd64`, t4models `amd64` / `x64` / `clidriver`, Informix `clidriver`, DB2 `clidriver`; folders restored (9 / 1 / 223 files). `NuGet.csproj` with mutation `Include="$(PkgMicrosoft_SqlServer_Compact_X)\NativeBinaries\amd64\**"`: build exit 1, `error : SQL CE native binaries not found under '…\NativeBinaries\amd64'`; reverted, `git grep Compact_X -- NuGet` empty, clean rebuild `0 Warning(s) 0 Error(s)`, notices `check` exit 0. No guard fired on any TO-5 green run.
- G-06: pass — `git diff` reviewed: only E-1..E-12 lines changed, no reformatting.
- G-07: pass — no `Tests/Tests.Playground/` change.
- G-09: pass — `/code-review medium` over the uncommitted diff, 6 findings walked one per turn with the user; dispositions and fixes in P11 A-3 (finding 1's observed missing `amd64/` was residue of the TO-2 mutation build — a plain rebuild restored 9 files).
- G-10 (A-1 CI parity): — (pending) blocked — PR CI build; compare the CI-produced `linq2db.SqlCe` / `linq2db.t4models` / `linq2db.Informix` / `linq2db.DB2` nupkgs with `5861-compare.ps1` against the master dumps. The local warm re-pack (CI order: build, then pack) is recorded under TO-5; CI itself is unmeasured until then.

## P10 Adjudicated (M/L)

- L-1 EULA text stays the hand rendering in `texts/` — user decision 2026-10-26 (P3); the generator reads plain text only and a deterministic RTF converter in `check` would need a restored package on the CI leg.
- L-2 `x86` native glob kept although `NuGet.csproj:4` pins `PlatformTarget=x64` — existing behaviour, not this change's to remove.
- L-3 _(superseded by A-1: fixed in scope)_ Cold single-project pack of `linq2db.SqlCe` omits `tools/amd64/**` (U-7).

## P11 Amendments (M/L)

- A-1 (2026-10-26, user: "fix here" for U-7) — fix the cold-pack omission in scope. Sweep `\$\(ToolsPath\)[^"]*\*` across `NuGet/` found four static globs over folders `NuGet.csproj` populates during build: `linq2db.SqlCe.csproj:37` (`amd64/**`), `linq2db.t4models.csproj:98` (`amd64/**`), `:99` (`x64/**`), `linq2db.Informix.csproj:37` (`clidriver/**`); `DB2.csproj:44-54` and `t4models.csproj:141-151` already use the target workaround for `clidriver`. Measured on master-equivalent csprojs, each packed alone from a clean `.build/bin/NuGet`: SqlCe 49 entries vs 58 warm (−9 `tools/amd64/**`); t4models 378 vs 388 warm (−9 `tools/amd64/**`, −1 `tools/x64/SqlServerSpatial170.dll`); Informix 49 vs 272 warm (−223 `tools/clidriver/**`). Non-wildcard includes (`arm64\…`, `x86\…`) are unaffected — a literal item survives evaluation whether or not the file exists yet. Published 6.5.1 `linq2db.SqlCe` carries `tools/amd64/**` (CI builds the solution first), so no shipped package was wrong. All four sites converted (E-10..E-12), not only SqlCe, because they are one defect (rule: fix the loop). Approval of P6 voided for E-10..E-12; re-earn.
  re-derives: P3 (pack-list constraint now excepts E-10..E-12), P4 (U-7), P6 (E-10, E-11, E-12), P7 (A-1 rows), P8 (TO-5), P10 (L-3 superseded)
  conventions: n/a — no `Tests/` edit-point
- A-2 (2026-10-26, critic round 2) — E-10..E-12 rewritten from `_PackageFiles` injection to `None Pack="true"` declared inside the target. The `_PackageFiles` form with unqualified `%(RecursiveDir)` is correct only while its target is the first `_PackageFiles` writer (measured: the first E-11 attempt failed `NU5118` after `IncludeClidriverInPack`), so three sites in two shapes carried a hidden ordering rule. The `None`-in-target form writes no `_PackageFiles`, so the existing DB2 / t4models `IncludeClidriverInPack` targets stay the sole writers and keep their environment.
  re-derives: P6 (E-10, E-11, E-12), P7 (`t4models.csproj:141-151` row), P9 (G-01 TO-5, G-10)
  approved: 2026-10-26 by the user — A-1 scope (all four sites incl. Informix, one PR) and A-2 shape.
- A-3 (2026-10-26, `/code-review` G-09 walk, each disposition user-decided) — (1) restore guard in `NuGet.csproj`: add; (2) pack-time guards on all four globs: add — a sentinel proves each folder existed when `_GetPackageFiles` ran, which narrows (does not close) the gap behind G-10; (3) Informix/x64 separable: keep on this PR, own commit + PR-body section; (4) one target form repo-wide: convert DB2 (new E-13) and t4models' `IncludeClidriverInPack` to `None`-in-target, t4models merged into one target; (5) `msvc90-crt` packageId: drop (D-2 stands); (6) README `:96-98`: reword to name SAP HANA's unresolved redistribution.
  re-derives: P6 (E-2, E-8, E-10, E-11, E-12, E-13), P7 (DB2 / t4models clidriver row now covered), P8 (TO-5 extended to DB2, TO-6), P9 (G-01 TO-5, TO-6)
  conventions: n/a — no `Tests/` edit-point

## P12 Critic verdict (M/L)

**weak** — `plan-critic` on `fable`, round 1 (2026-10-26). Searched: `Redist` across all non-corpus build/doc files; `SqlServerCe|SqlCe|SqlServer.Compact` across csproj/props/targets/config; `.build/obj/NuGet/NuGet.csproj.nuget.g.props:25-33` (`Pkg*` emitted per-TFM, same mechanism as `$(PkgIBM_Data_DB_Provider)`); SDK `Microsoft.PackageDependencyResolution.targets` (`CopyLocalLockFileAssemblies` true for .NETFramework); `project.assets.json` targets key `net462`; the extracted nupkg/nuspec; `third-party-notices.ps1` `check`/`verify`/`Test-PayloadVersions`/harvest; `.github/workflows/build.yml` and Azure `build-job.yml` pack legs. P7 confirmed complete; D-1, D-2, U-2, U-5, U-6 confirmed.
Objections, all folded in:
- TO-2 SHA compare over every entry would go red on SourceLink commit SHAs in first-party dlls/nuspec → SHA compare scoped to SQL CE entries, entry-list compare kept over all. Changed: P8 TO-2.
- TO-3 red and green were both absences (harvest prints nothing for a clean match or a missing assets file) → three positive cells. Changed: P8 TO-3.
- amd64 count is 9, not 10 (confirmed by the U-7 warm/cold delta 58−49). Changed: P8 TO-1, TO-2.
- E-8 would move an already-false "no license file" claim onto SAP HANA → rewrite to unresolved redistribution. Changed: P6 E-8.
Not checkable by the critic: NuGet audit advisories for the package under `TreatWarningsAsErrors` — gated by U-3's step-1 build.
Added after the verdict by the author (measured, not critiqued): U-7 / P10 L-3 cold-pack finding.

**weak** — `plan-critic` on `fable`, round 2, delta on A-1 (2026-10-26). Searched: `git diff -- NuGet`; `_PackageFiles|_GetPackageFiles|TargetsForTfmSpecificContentInPackage|TfmSpecificPackageFile` across the worktree; wildcard pack globs over build-populated folders across `**/*.{csproj,props,targets,nuspec}` (A-1 census complete: only the four sites); `dotnet pack` invocations in `Build/`, `.github/`, scripts (CI builds then packs the solution, Windows); SDK 10.0.403 `NuGet.Build.Tasks.Pack.targets` (`GenerateNuspecDependsOn`, `_GetPackageFiles`, `_WalkEachTargetPerFramework`); re-ran the scratch compares (TO-5 red and green arms confirmed).
Objections:
- E-10/E-12 used the `_PackageFiles` + unqualified `%(RecursiveDir)` shape that is safe only as the first `_PackageFiles` writer, while E-11 needed staging — one defect, two shapes, a hidden ordering rule. Folded in: A-2, all three to `None`-in-target. Changed: P6 E-10..E-12, P7 row, P11 A-2.
- The CI-parity claim was reasoned with no instrument that can say no (`verify` cannot see a missing native). Folded in: P9 G-10, blocked on PR CI.
- G-01 TO-5 recorded counts, not the entry/SHA compare. Folded in: TO-5 row re-recorded with compare output after A-2.

**weak** — `plan-critic` on `fable`, round 3, delta on A-3 (2026-10-26). Searched: the full A-3 diff; `<TargetFrameworks?>|<ToolsPath>` across `NuGet/**/*.csproj`; `nuget.g.props:25-28` + SDK `Microsoft.Common.CrossTargeting.targets` + `5861-guard-nugetcsproj.log` (`[TargetFramework=net462]` suffix) — "inner build only" now measured, holds; `NuGet.Build.Tasks.Pack.targets` (`GenerateNuspecDependsOn`, `IsPackable` gating); CI pack invocations (two, both Windows solution build-then-pack, no `--no-build`) — spurious-fire claim holds; sentinel files present in the pinned packages — holds; wildcard pack-glob and `$(Pkg…)` wildcard censuses — every site guarded, no `_PackageFiles` writer remains; the verify script's ability to say no.
Objections:
- The A-3 "one form repo-wide" sweep missed `.claude/docs/release/linqpad-test-checklist.md:63-99`, which teaches the retired form and claims the adopted one does not work. Folded in: P7 row (deferred to a user-approved corpus edit).
- E-11 still said the existing target was untouched; A-3 (2) said "closing" the G-10 gap. Folded in: both reworded ("merged"; "narrows").
