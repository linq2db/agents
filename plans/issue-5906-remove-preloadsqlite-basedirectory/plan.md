# Work plan: issue-5906-remove-preloadsqlite-basedirectory — remove the redundant PreLoadSQLite_BaseDirectory assignments

**Tier:** L  ·  **Status:** approved  ·  **Approved-at:** 2026-10-26 (user, E-1…E-6)  ·  **Branch:** issue/5906-remove-preloadsqlite-basedirectory
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

Base: `origin/master` @ `c82e21c35`. Tier L because the edit set spans four areas (TESTS-LINQ, LINQPAD, TESTS-T4, root build props); the change itself is mechanical.

## P1 Problem

[#5906](https://github.com/linq2db/linq2db/issues/5906): three sites set the process environment variable `PreLoadSQLite_BaseDirectory` — `Tests/Linq/TestsInitialization.cs:44` and `Source/LinqToDB.LINQPad/DatabaseProviders/SQLiteProvider.cs:26` to `AppDomain.CurrentDomain.BaseDirectory`, `Tests/Tests.T4/Shared.ttinclude:11` to `$(LinqToDBT4SharedTools)`. The issue's premise is that nothing reads the variable. **That premise is false** (U-1): System.Data.SQLite 2.0.4 `UnsafeNativeMethods.GetBaseDirectory` reads it. What is true is that each assigned value is a directory SDS's native pre-loader already searches by default (U-2), so the assignments are redundant configuration, and their comments (and `SQLite.Runtime.props:7-8`) describe a mechanism that does not exist ("SQLitePCLRaw-based … honours it just as Microsoft.Data.Sqlite does"; U-3 shows MDS never reads it). Falsifiable form: with the three assignments removed, SDS loads `e_sqlite3` from the same file in every host, and every SQLite test / template / driver path still works.

## P2 Success criteria

- SC-1 Tests/Linq (and Tests.Playground, which links the same file): with E-1 applied, SDS's pre-loader loads the identical `e_sqlite3.dll` path as before on net462 and net10.0 → TO-1, TO-2
- SC-2 SQLite.Classic and SQLite.MS test runs stay green on net462 and net10.0 locally, and on every CI SQLite leg (incl. Linux) → TO-3
- SC-3 Tests.T4 keeps the assignment (D-5), and its new comment's claim holds: in devenv SDS loads `e_sqlite3` from under `$(LinqToDBT4SharedTools)`, and the four SQLite templates regenerate unchanged → TO-4
- SC-4 LINQPad 5 driver opens a SQLite.Classic and a SQLite.MS connection, loads schema and runs a query without E-2's assignment → TO-5
- SC-5 No comment calls System.Data.SQLite "SQLitePCLRaw-based", and every remaining `PreLoadSQLite_BaseDirectory` assignment (D-5 / D-2) carries a comment naming its real reader and reason → TO-6

## P3 Constraints & anti-goals (M/L)

- No change to `SQLite.Runtime.props` targets (`CheckForAnyCPU` override, net462 `CopySQLiteRuntimes`) — the issue declined these on evidence; only its comment block changes.
- No change to native deployment (`LinqToDB.LINQPad.csproj` PostBuild2 copies, NuGet `tools/` layout) — comment text only.
- No change to the net8+ `NativeLibrary.SetDllImportResolver` block in `TestsInitialization.cs:46+`.
- No public API change; no generated SQL change; no baselines change.
- Issue-scope reconciliation: the issue asked to verify "Tests/Linq on net462+net10.0 across SQLite.Classic and SQLite.MS" (SC-1/SC-2), "a Tests.T4 SQLite template run from VS" (SC-3), "LINQPad 5 .lpx and LINQPad 7+ driver smoke rows" (SC-4). Narrowing: LINQPad 7+ is unaffected by E-2 (the static ctor is `#if NETFRAMEWORK`, `SQLiteProvider.cs:20`), so its smoke row is a cheap confirmation, not a criterion. Second narrowing: the T4 site is kept with a corrected comment (D-5), not deleted, because the VS T4 host shadow-copies SDS. Disclose both in the PR body, together with the corrected premise (read by SDS's pre-loader, redundant at two sites, needed at one).
- User-visible deltas vs master: none intended. A LINQPad 5 user who had set `PreLoadSQLite_BaseDirectory` themselves no longer has it overwritten by the driver — strictly more user control; disclose in the PR body.

## P4 Unknowns (M/L)

- U-1 Does SDS 2.0.4 read `PreLoadSQLite_BaseDirectory`? Yes — measured: `ilspycmd -t System.Data.SQLite.UnsafeNativeMethods` on `system.data.sqlite/2.0.4/lib/netstandard2.0` shows `GetBaseDirectory(bool overrideOnly)` → `GetSettingValue("PreLoadSQLite_BaseDirectory")` → `Environment.GetEnvironmentVariable(name)`, falling back to `System.Data.SQLite.dll.config` appSettings; a UTF-16 byte scan finds the literal in all three SDS builds (net471, netstandard2.0, netstandard2.1) — resolved-by probe
- U-2 Where does the pre-loader look without the variable? Measured from the decompile: `SearchForDirectory` iterates roots `[GetBaseDirectory(overrideOnly: true) (= the variable or null), GetAssemblyDirectory() (CodeBase, else Location, of System.Data.SQLite.dll), AppDomain.CurrentDomain.BaseDirectory]` × subdirs `[PROCESSOR_ARCHITECTURE, platform name, runtimes\win-<arch>\native, "" only when PreLoadSQLite_AllowBaseDirectoryOnly or non-Windows .NET Core]` and takes the first existing `e_sqlite3.dll`; so an override equal to root 2 or root 3 can at most reorder roots 2/3 — resolved-by probe
- U-3 Does Microsoft.Data.Sqlite / SQLitePCLRaw read the variable? No — measured: UTF-16 byte scan of every `lib/**/*.dll` in local `sqlitepclraw.*` (core, provider.e_sqlite3, provider.dynamic_cdecl, bundle_e_sqlite3; 2.1.2–2.1.12) and `microsoft.data.sqlite.core` (3.1.32–10.0.12) packages: zero hits — resolved-by probe
- U-4 Tests/Linq: are root 2 and root 3 the same directory, so the override is a pure no-op? Reasoned, unprobed: SDS is a copy-local reference in the test output, so its assembly directory is the output directory, which is `AppDomain.BaseDirectory` under the MTP test host; TO-1 measures the loaded path before/after on net462 and net10.0 — resolved-by probe (TO-1, executed before E-1 is committed)
- U-5 Tests.T4 in devenv: is SDS's assembly directory `$(LinqToDBT4SharedTools)`? Only by coincidence — measured (critic round 1, confirmed by author): `UnsafeNativeMethods.CheckAssemblyCodeBase` uses `CodeBase` only when its directory holds `System.Data.SQLite.dll.config` / `.altconfig` or an arch/platform marker subfolder (`x86`, `AMD64`, `x64`, …, or the dotted `runtimes.win-x64.native`); otherwise `GetAssemblyDirectory` uses `Assembly.Location`, which the netfx T4 host shadow-copies (`Source/LinqToDB.Templates/LinqToDB.Tools.ttinclude:25`). The in-repo tools dir (`Directory.Build.props:224`) qualifies only because `NuGet/NuGet.csproj:35-39` (SqlCe `amd64\`) and `:60-65` (SqlServerSpatial `x86\`/`x64\`) create marker folders. The shipped packages do not rely on the pre-loader in this host: they co-locate `tools\e_sqlite3.dll` (`NuGet/SQLite/linq2db.SQLite.csproj:40-44`, `NuGet/t4models/linq2db.t4models.csproj:118-122`), which the in-repo tools dir lacks — resolved-by probe; E-3's fate is D-5
- U-6 LINQPad 5: does the driver's static ctor run in the same AppDomain as SDS's pre-loader, with the same `BaseDirectory`? Reasoned, unprobed: the variable is process-wide and carries the `BaseDirectory` of whichever domain ran `SQLiteProvider..cctor` first, while `SearchForDirectory` reads the domain that first touches `UnsafeNativeMethods`; LINQPad 5 has a schema domain, per-query domains and a process-isolation mode, and the 6.5.0 comment "LINQPad 5 does not run the driver from its own base directory" (`SQLiteProvider.cs:25`, `4e9b8e743`) was never measured (critic lead). Natives sit as `runtimes\win-x86|x64\native` in the driver folder (`LinqToDB.LINQPad.csproj:147-148`) — resolved-by user answer: the user runs TO-5 across all three modes; D-2 restores E-2 alone if any is red
- U-7 Could a `System.Data.SQLite.dll.config` file set the value instead (U-1's fallback)? Searched `System\.Data\.SQLite\.dll\.config|PreLoadSQLite|No_SQLite` across the worktree excluding `.claude/`: only the three sites and `SQLite.Runtime.props:8` — resolved-by scout
- U-8 Does a child process inherit the variable and depend on it? Searched `ProcessStartInfo|new Process\(|Process\.Start\(` across `Tests/**/*.cs`: `Tests/LinqToDB.CLI` (CLI / MCP server, which references Microsoft.Data.SQLite only — `Source/LinqToDB.CLI/LinqToDB.CLI.csproj:102`) and `Tests/Tests.FpuJit` (no SQLite); `Tests/Tests.T4/Cli/CLI.ttinclude:54` spawns the CLI too and `Cli/*.tt` do not include `Shared.ttinclude` — resolved-by scout
- U-9 Linux / macOS CI legs: `FixUpDllFileName` appends `.dll` only on Windows, so the pre-loader looks for a file literally named `e_sqlite3` and never matches `libe_sqlite3.so`; it finds nothing with or without the variable, the net8+ resolver returns the zero handle, and default probing loads the native (critic round 1, decompile) — resolved-by probe: decompile; the CI SQLite legs in G-01 confirm (`blocked — CI` until read)
- U-11 Keep or delete the T4 assignment (D-5)? Keep, comment fixed — resolved-by user answer (2026-10-26)
- U-12 What does SDS load on net462 in Tests/Linq / Playground? Measured: process is x86 (`Environment.Is64BitProcess == False`); the output root holds an x86 `e_sqlite3.dll` (PE machine `014C`) beside `runtimes\win-{x86,x64,arm64}\native`, so `PreLoadSQLiteDll` returns without loading (`_SQLiteNativeModuleFileName == null`) and the variable is irrelevant there — resolved-by probe
- U-10 Does the net8+ resolver in `TestsInitialization.cs:49-73`, which reads `UnsafeNativeMethods._SQLiteNativeModuleHandle`, depend on the pre-load having found a file? Yes, it returns that handle; TO-1 records the handle non-zero before and after, so an unchanged path keeps the resolver's input unchanged — resolved-by probe (TO-1)

## P5 Decisions (M/L; rejected alternatives mandatory at L)

### D-1 — delete the Tests/Linq and LINQPad assignments

- **chosen:** remove the `Environment.SetEnvironmentVariable("PreLoadSQLite_BaseDirectory", …)` line and its comment at E-1 and E-2. The T4 site is D-5.
- **rejected:** keep them with corrected comments — they configure a directory SDS already searches (U-2), so they are dead weight whose only effect is a misleading rationale; and the T4 site makes the in-repo T4 run differ from what consumers of the shipped package run (U-5).
- **rejected:** replace with `No_PreLoadSQLite` plus a `NativeLibrary` resolver — larger change, not available on net462, solves no observed failure.
- **why this:** for E-1 and E-2 the assigned value is already root 3 of the default search (U-2), so removal is at most a root-2/root-3 reorder; the non-shadow-copying SDS consumers in the repo (`Tests/Tests.Benchmarks` via `Tests/linq2db.Providers.props:14`, `Examples/Compat/ConfigurationManager`) already run on that default. E-3 is not covered by this argument — see D-5.
- **failure mode of the choice:** a host where roots 2 and 3 differ and the first root found holds a wrong or missing-arch native that the override used to bypass — LINQPad 5 (U-6); TO-5 is the gate, D-2 the fallback. No automated test can tell the two designs apart there.

### D-2 — decide per site, by host result

- **chosen:** a site whose host check (TO-3/TO-4/TO-5) goes red is restored alone, with a 1–2 line comment naming SDS's pre-loader (`UnsafeNativeMethods.GetBaseDirectory`) as the reader and the host-specific reason; the other deletions stand.
- **rejected:** all-or-nothing — would keep two redundant sites to protect one.
- **why this:** the issue's own decision rule.
- **failure mode of the choice:** a partially restored set; acceptable, because the restored site then carries a true comment.

### D-3 — no committed regression test

- **chosen:** the native-path probe (TO-1/TO-2) is Playground scratch, never committed; the standing guard is the existing SQLite test corpus, which fails at the first connection if the native does not load.
- **rejected:** a committed test asserting `_SQLiteNativeModuleFileName` — it reads a private field of a third-party type that changes across SDS versions (the existing resolver already carries a "targets 2.0.2" note, `TestsInitialization.cs:55`), and it would pin a path, not behaviour.
- **why this:** the behaviour that matters (SQLite works) is already pinned by hundreds of tests on every SQLite leg.
- **failure mode of the choice:** a future change that makes SDS load a *different but working* native would not be noticed; out of scope here.

### D-4 — correct the comments that describe the non-existent mechanism

- **chosen:** rewrite `SQLite.Runtime.props:7-11`, `LinqToDB.LINQPad.csproj:142-146` and the one-clause reason in `SQLiteTests.cs:785` to say what U-1/U-2/U-3 measured: SDS 2.x has its own pre-loader that finds `e_sqlite3` under `runtimes\win-<arch>\native` next to its assembly or the app base; Microsoft.Data.Sqlite resolves it through SQLitePCLRaw. Drop "SQLitePCLRaw-based" for SDS.
- **rejected:** leave them — they would be the only remaining description of native loading and they are wrong; the user prefers consistency over a minimal diff.
- **why this:** SC-5.
- **failure mode of the choice:** wording drift from the decompile; TO-6 checks the text against U-2.

### D-5 — the T4 site (E-3)

- **chosen (user, 2026-10-26):** keep the assignment; replace its comment with the true reason — the VS T4 host shadow-copies `System.Data.SQLite.dll`, so SDS's pre-loader cannot locate the tools folder from the assembly's location, and `PreLoadSQLite_BaseDirectory` (read by `UnsafeNativeMethods.GetBaseDirectory`) names it. E-3 is comment-only.
- **rejected:** delete and document — the in-repo T4 run would find `e_sqlite3` only because SqlCe / SqlServerSpatial marker folders make SDS trust `CodeBase` (U-5); dropping either provider from `NuGet/NuGet.csproj` would silently break SQLite T4 in VS.
- **why this:** the override is SDS's supported setting for exactly this host; keeping it removes the hidden coupling instead of documenting it.
- **failure mode of the choice:** the comment's shadow-copy claim rests on `LinqToDB.Tools.ttinclude:25`, not a measurement; TO-4 measures it.

## P6 Edit-points

- E-1 `Tests/Linq/TestsInitialization.cs:TestAssemblySetup` — delete the comment + assignment at lines 42-44 and the blank line after them.
- E-2 `Source/LinqToDB.LINQPad/DatabaseProviders/SQLiteProvider.cs:SQLiteProvider()` — delete the comment + assignment at lines 23-26 and the blank line after them; the `SqliteFactory.Instance` hack stays.
- E-3 `Tests/Tests.T4/Shared.ttinclude` — comment-only (D-5): replace line 9 with a 1–2 line comment naming the shadow-copying T4 host and SDS's pre-loader as the reader; lines 10-11 unchanged.
- E-4 `SQLite.Runtime.props:comment` — rewrite lines 7-11 per D-4.
- E-5 `Source/LinqToDB.LINQPad/LinqToDB.LINQPad.csproj:PostBuild2 comment` — rewrite lines 142-146 per D-4 (the copies and ordering note unchanged).
- E-6 `Tests/Linq/DataProvider/SQLiteTests.cs:TestDbVersion comment` — line 785: replace "because both clients are SQLitePCLRaw-based and share one native package" with "because both clients load e_sqlite3 from one native package"; the conclusion and lines 786-787 stay.

## P7 Impact map (M/L)

- `Tests/Tests.Playground/Tests.Playground.csproj:11` — links `..\Linq\TestsInitialization.cs`, so E-1 applies to Playground too (searched `TestsInitialization|linq2db\.TestProjects\.props` across `Tests/**/*.{csproj,props,fsproj,vbproj}`) — covered by E-1
- `Tests/EntityFrameworkCore/TestsInitialization.cs:12` — separate SetUpFixture, never set the variable (searched `class TestsInitialization|SetUpFixture` across `Tests/`) — out-of-scope
- SDS consumers that already run without the variable: `Tests/linq2db.Providers.props:14` (imported by `Tests/Tests.Benchmarks/linq2db.Benchmarks.csproj:2`), `Examples/Compat/ConfigurationManager/ConfigurationManager.csproj:10`, `NuGet/NuGet.csproj:21` (T4 tools payload), shipped `NuGet/SQLite/LinqToDB.SQLite.ttinclude:1` (searched `System\.Data\.SQLite` across `*.{csproj,props,targets,fsproj,vbproj}`) — out-of-scope
- `NuGet/SQLite/linq2db.SQLite.csproj:40-43`, `NuGet/t4models/linq2db.t4models.csproj:118` — comments on the co-located `tools/e_sqlite3.dll` for the T4 host's assembly-directory probe; unaffected by the deletions and still accurate — out-of-scope
- `Directory.Packages.props:173-174`, `Directory.Packages.props:295-300` — "System.Data.SQLite 2.x ships no native of its own and DllImports e_sqlite3" stays true; neither mentions the variable or "SQLitePCLRaw-based" — out-of-scope
- `SQLite.Runtime.props:7-8` — only non-site mention of the variable (searched `PreLoadSQLite|No_SQLite|System\.Data\.SQLite\.dll\.config|SQLite\.Interop` across the worktree excluding `.claude/`) — covered by E-4
- `Source/LinqToDB.LINQPad/LinqToDB.LINQPad.csproj:144` — "since System.Data.SQLite is SQLitePCLRaw-based" (searched `SQLitePCLRaw-based|SQLitePCLRaw based` across the worktree excluding `.claude/`; hits: this, `SQLite.Runtime.props:7`, `TestsInitialization.cs:42`, `SQLiteProvider.cs:23`, `Tests/Linq/DataProvider/SQLiteTests.cs:785`) — covered by E-5
- `Tests/Linq/DataProvider/SQLiteTests.cs:785` — `TestDbVersion` (`[Explicit]`) comment gives "SQLitePCLRaw-based" as the reason both clients report one engine version; the conclusion holds, the reason does not (U-3) — covered by E-6
- Child processes inheriting the variable — Localized — searched `ProcessStartInfo|new Process\(|Process\.Start\(` across `Tests/**/*.cs` and `Tests/Tests.T4/Cli/CLI.ttinclude`, no spawned process uses System.Data.SQLite (U-8) — out-of-scope
- KB pages restating the variable: `.claude/knowledge-base/areas/TESTS-LINQ/INDEX.md:40`, `areas/LINQPAD/INDEX.md:65`, `areas/TESTS-T4/INDEX.md:149`, `areas/PROV-SQLITE/issues.md:20` — deferred: KB is skill-driven, `/kb-refresh` after merge
- `.claude/docs/release/nuget-package-notes.md:131` — still says SourceGear.sqlite3 deploys into `sds/runtimes/`; stale since 6.5.0 and unrelated to the variable — deferred: separate corpus fix, flagged to the user
- Surfaces a repo grep cannot reach: the LINQPad driver's nuget.org / LINQPad gallery description and the wiki — searched nothing (unreachable); neither is known to mention the variable — out-of-scope

## P8 Test obligations (M/L)

- TO-1 Native-path probe, characterization: a Playground scratch test opens a `SQLite.Classic` connection, then reads `System.Data.SQLite.UnsafeNativeMethods._SQLiteNativeModuleFileName` and `_SQLiteNativeModuleHandle` by reflection and prints them; run on net462 and net10.0 on the base tree, then with E-1 applied; pass = identical path both times, ending `runtimes\win-x64\native\e_sqlite3.dll`, handle non-zero; proves no new behaviour — providers: SQLite.Classic — proof: characterization
- TO-2 Probe control: mutation "point `PreLoadSQLite_BaseDirectory` at a decoy directory holding a copy at `decoy\runtimes\win-x64\native\e_sqlite3.dll`" (subfolder layout required: a flat `decoy\e_sqlite3.dll` is never probed on Windows, U-2, and would read as "variable ignored") in `TestsInitialization` on the base tree; separates: the decoy path appears in TO-1's output only if SDS reads the variable and the probe can see a root change — so a TO-1 "identical" result is not vacuous; run on net10.0 and net462 — providers: SQLite.Classic — proof: control
- TO-3 SQLite suites after E-1: `Tests.DataProvider.SQLiteTests` fixture on net462 and net10.0, plus CI SQLite legs (Windows and Linux); pass = green, no `DllNotFoundException` / `TypeInitializationException` from `UnsafeNativeMethods` or `SqliteConnection` — providers: SQLite.Classic, SQLite.Classic.MPU, SQLite.Classic.MPM, SQLite.MS — proof: characterization
- TO-4 T4 host (user-run): in a fresh devenv session on the branch, run Custom Tool on `Tests/Tests.T4/Default/SQLite.tt`, `Default/SQLite.Northwind.tt`, `Databases/SQLite.tt` and `Models/EquatableTest.tt`; pass = generation succeeds and `git status` shows the four `.generated.cs` unchanged; a scratch `Warning(...)` of `UnsafeNativeMethods._SQLiteNativeModuleFileName` (reflection) after the first SDS connection in `Default/SQLite.tt` records which file loaded; pass additionally requires that path to sit under `$(LinqToDBT4SharedTools)` (the override's root), confirming E-3's comment; scratch reverted — providers: SQLite.Classic (T4 SDS) — proof: characterization
- TO-5 LINQPad 5 host (user-run): install the branch's `.lpx`, create a SQLite.Classic and a SQLite.MS connection to `Data/TestData.sqlite`, expand the schema, run one query each in the default mode and one with "run each query in its own process" on; plus the LINQPad 7+ smoke row as a cheap confirmation — providers: SQLite.Classic, SQLite.MS — proof: characterization
- TO-6 Comment audit: `git grep -n -e PreLoadSQLite -e "SQLitePCLRaw-based"` on the branch outside `.claude/` returns only sites kept by D-5 or restored by D-2, each with a comment naming `UnsafeNativeMethods.GetBaseDirectory` as the reader; an independent reader checks E-4/E-5 text against U-2/U-5 — providers: none (text) — proof: characterization

## P9 Verification gates

All rows 2026-10-26 against the uncommitted E-1…E-6 tree on base `c82e21c35`.

- G-01 TO-1: pass — scratch `Tests.Playground` `NativePathProbe.ProbeNativePath` (SQLite.Classic) via `worktree-test.ps1 -NoBuild`, output `.build/.agents/5906-probe.txt`. Base: net10.0 x64 `file=…\net10.0\runtimes\win-x64\native\e_sqlite3.dll`, handle non-zero; net462 x86 `file=<null> handle=0`. After E-1: identical on both (env `<null>`). The net462 expected value in TO-1 was wrong, see A-1 / U-12.
- G-01 TO-2: pass — mutation "point `PreLoadSQLite_BaseDirectory` at a decoy directory holding a copy at `decoy\runtimes\win-x64\native\e_sqlite3.dll`" (plus `win-x86`) applied to `TestsInitialization.cs:44` on the base tree: net10.0 loaded `…\5906-decoy\runtimes\win-x64\native\e_sqlite3.dll`, net462 loaded `…\5906-decoy\runtimes\win-x86\native\e_sqlite3.dll`; mutation reverted.
- G-01 TO-3: local pass with a pre-existing red — `Tests.DataProvider.SQLiteTests`, `-PerProvider` SQLite.Classic / .MPU / .MPM / SQLite.MS on net10.0 and net462: 143–144 per run, 10 failed per run, all `DateTimeRoundtrip_BulkCopyUtc` ×8 / `DateTimeRoundtrip_InsertUtc` ×2 (#2107 `[ActiveIssue]` message mismatch: `Assert.That(result.DateTime, Is.EqualTo(dt.ToLocalTime()))` fails instead of the gated `Kind` assert). Same 10 on the base tree (stash, net10.0, SQLite.Classic + SQLite.MS, 10/92 and 10/91) — not caused by this branch; no native-load exception anywhere. CI half: blocked — PR #6160 head `32f7ffdb0`, `/azp run test-sqlite` → Azure 24742 + GitHub 40345810293, to triage.
- G-01 TO-4: pass (user-run, fresh devenv, branch tree) — scratch warnings in `Default/SQLite.tt`: `native: …\.build\bin\NuGet\Debug\net462\runtimes\win-x64\native\e_sqlite3.dll`; `sds: location=C:\Users\…\AppData\Local\assembly\dl3\…\System.Data.SQLite.dll codebase=file:///C:/Worktrees/linq2db/5906-preloadsqlite-basedirectory/.build/bin/NuGet/Debug/net462/System.Data.SQLite.dll` — the shadow copy E-3's comment claims, and the native under the override root. After removing the scratch, the four templates regenerated with no `.generated.cs` change (`git status`); a leftover blank line in `Default/SQLite.tt` was restored.
- G-01 TO-5: pass (user-run) — LINQPad 5 with the branch's `.lpx`: "works" across the TO-5 steps.
- G-01 TO-6: pass — `git grep -n -e PreLoadSQLite -e "SQLitePCLRaw-based" -- . ":!.claude"` → `SQLite.Runtime.props:9` (the comment pointing at the T4 site) and `Tests/Tests.T4/Shared.ttinclude:12` (kept by D-5); the T4 comment names SDS's native pre-loader as the reader, not the method name `GetBaseDirectory`. Independent read of E-4/E-5 text: pending G-09.
- G-02: n/a — no SQL-generating code in P6; recheck the CI baselines PR for an empty diff.
- G-03: n/a — E-2 removes a statement inside an `internal sealed` class; no member added or removed.
- G-04: n/a — no public surface change.
- G-05: pass — `dotnet build Source/LinqToDB.LINQPad/LinqToDB.LINQPad.csproj -c Release -p:GenerateLpxArtifacts=false` (net472 + net8.0-windows7.0) 0 warnings 0 errors; `dotnet build Tests/Linq/Tests.csproj -c Release -f net10.0` 0/0 (net10.0 instead of the planned net462: the test edits are comment-only, and net462 Debug built clean).
- G-06: pass — `git diff --stat`: the six E-n files, 11+ / 17-.
- G-07: pass — `Tests/Tests.Playground/NativePathProbe.cs` deleted; `git status --short` lists only E-1…E-6.
- G-09: pass — independent read-only review (`fable`) of the uncommitted diff, with the SDS decompile re-run: deletions behaviour-neutral, no orphaned `using`, untouched neighbours consistent. Three comment findings, all applied (comment-only, no rebuild needed): F1 the `Shared.ttinclude` comment said the pre-loader "can't locate" the native from a shadow copy, but it falls back to `CodeBase` when marker subfolders exist — reworded to state the coupling (U-5); F2 the `SQLite.Runtime.props` sentence claimed SDS always loads from `runtimes/<rid>/native`, false for the net462 test host (U-12) — scoped; F3 garden-path wording and wrap in `LinqToDB.LINQPad.csproj:143-146`. F4 (the kept site names "its native pre-loader", not `GetBaseDirectory`) accepted as-is, see TO-6.

## P10 Adjudicated (M/L)

- L-1 (D-3) No committed test pins which `e_sqlite3.dll` SDS loads; the SQLite corpus is the guard. Reason: the only way to pin it reads a private SDS field.
- L-2 (P3) LINQPad 7+ is not a success criterion — `SQLiteProvider.cs:20` gates the static ctor on `NETFRAMEWORK`, so E-2 cannot reach it.

## P11 Amendments (M/L)

- A-1 (2026-10-26, TO-1 measurement) — TO-1's expected net462 value ("ending `runtimes\win-x64\native`, handle non-zero") was reasoned and wrong: the net462 test host runs x86 and its output root carries an x86 `e_sqlite3.dll`, so `PreLoadSQLiteDll` declines and the CLR's DllImport loads the root copy (U-12). The criterion "identical before and after" is unchanged and held. No E-n change.
  re-derives: P4 (U-12), P8 (TO-1 expected value)

## P12 Critic verdict (M/L)

**Current verdict: weak** — every objection folded in or disposed below; no residual objection carried.

### Round 1 — `fable`, on the plan at base `c82e21c35` — weak

Searched: full decompile of `UnsafeNativeMethods` (static ctor, `Initialize`, `GetSettingValue`, `CheckAssemblyCodeBase`, `GetAssemblyDirectory`, `SearchForDirectory`, `GetBaseDirectory`, `FixUpDllFileName`, `PreLoadSQLiteDll`) on netstandard2.0, with net471 confirmed identical by hash; a whole-assembly search showing `PreLoadSQLite_BaseDirectory` has a single reader; `SQLiteConnection` ctor → `Initialize()`; pre-`OneTimeSetUp` SDS touches in `Tests/Base/*` (none); the P7 greps re-run (census holds); `Shared.ttinclude` includers (51 `.tt`); CI does not run T4; `git log -S` history (`e64d5db6e`, `20e9b1eaa`, `4e9b8e743`, `f6f7dce5f`).

Objections and dispositions:
- U-5 false mechanism (CodeBase is trusted only with marker folders; T4 shadow-copies) — accepted, author re-ran the decompile: U-5 rewritten; E-3 moved to D-5 / U-11 for the user.
- D-1 evidence wrong (shipped T4 packages co-locate `tools\e_sqlite3.dll`) — accepted: D-1 "why this" narrowed to E-1/E-2.
- TO-2 decoy layout ambiguous — accepted: subfolder layout spelled out.
- TO-6 contradicts D-2 — accepted: SC-5 / TO-6 made conditional.
- lead: U-6 AppDomain assumption — disposed: TO-5 extended to schema load, in-domain query and process isolation (user-run).
- lead: TO-4 not interpretable — disposed: TO-4 records `_SQLiteNativeModuleFileName` via scratch `Warning`.
- minor U-9 reason — accepted: rewritten (`.dll` suffix only on Windows).
