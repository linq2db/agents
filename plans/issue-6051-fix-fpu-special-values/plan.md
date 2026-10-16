# Work plan: issue-6051-fix-fpu-special-values — x86 netfx JIT faults on NaN/Infinity constants under FP-unmasking hosts

**Tier:** L  ·  **Status:** approved  ·  **Approved-at:** 2026-10-16 (user, E-1..E-14 after critic `weak` folded in)  ·  **Branch:** issue/6051-fix-fpu-special-values
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

## P1 Problem

Hosts that unmask FP exceptions (C++Builder/Delphi; reproduced with `_control87(0, EM_INVALID|EM_ZERODIVIDE|EM_OVERFLOW)` from `msvcrt.dll`) make the x86 .NET Framework JIT fail while *compiling* a method: `SEHException` / `STATUS_FLOAT_MULTIPLE_TRAPS` on clrjit 4.8.4790, stack overflow inside clrjit on 4.8.1 build 4.8.09221 (#6042 report). #6053 removed the core instance (`QueryCache.ToStopwatchTicks`) but shipped without a regression test because an in-suite test passes vacuously (methods JIT once per process, before a test could unmask the FPU).

measured (probe `.build/.agents/probe6042`, `RuntimeHelpers.PrepareMethod` over every non-generic method of `linq2db.dll`, x86 net462, FPU unmasked, post-#6053 build): 10 of 20,792 methods fail —
`DuckDBMappingSchema.BuildDouble`, `YdbMappingSchema.BuildDoubleLiteral`, the `OracleMappingSchema` ctor double literal lambda, the `FirebirdMappingSchema` ctor double literal lambda, `DB2ProviderAdapter.DecimalFloatConverters.ToDouble` / `ToSingle` / `ToDoubleNullable` / `ToSingleNullable`, `ClickHouseMappingSchema.MySqlMappingSchema.StringToFloat` / `StringToDouble`.
Common element: returning a `double`/`float` `NaN`/`±Infinity` constant, or `double.IsPositiveInfinity`/`IsNegativeInfinity` (on netfx a compare against the constant). Passing in the same sweep: `double.IsNaN`/`IsInfinity` (netfx implements them as bit tests; PostgreSQL's use passes), float `IsPositive/NegativeInfinity` compares (DuckDB `BuildFloat`, Oracle/Firebird float lambdas, YDB `BuildFloatLiteral`).

Nothing in CI would notice a new instance of this class in any netfx-shipped assembly.

## P2 Success criteria

- SC-1 A GitHub Actions job (windows-2025, every PR/push) JIT-sweeps every non-generic method of all 12 .NET Framework–shipped assemblies (linq2db, .Compat, .Extensions, .Tools, .Scaffold, .FSharp, .Remote.Grpc, .Remote.HttpClient.Client, .Remote.SignalR.Client, .Remote.SignalR.Server, .Remote.Wcf, .EntityFrameworkCore EF3) in an x86 net462 process with FP exceptions unmasked, and fails on any JIT fault, caught or process-killing → TO-1, TO-2
- SC-2 On the branch base (no fix), built Release, the gate reports exactly the 10 P1 methods and nothing else, locally and on CI (the 10 are measured for linq2db.dll only; the other 11 assemblies are predicted clean by grep — an extra hit is handled per U-10) → TO-1, TO-2
- SC-3 The gate cannot pass vacuously: it exits non-zero if the canary method does not fault, if the process is 64-bit, if the FPU control word is not unmasked at start, after the canary, after every caught fault (re-armed) and at child exit, if an expected assembly is missing or has zero prepared methods, or if any method is skipped for a dependency-load failure (`TypeLoad`/`FileNotFound`/`FileLoad`/`BadImageFormat`) not on an explicit per-assembly allowlist carrying a reason; the job has `timeout-minutes` and each child a wall-clock cap → TO-3a, TO-3b, TO-3c, TO-3d, TO-3e, TO-3f
- SC-4 With the fix the gate is green locally and on CI → TO-4
- SC-5 Generated literals and read-back values for NaN / +Inf / −Inf / a finite value are unchanged for DuckDB, YDB, Oracle, Firebird, ClickHouse(MySql string path) and DB2 — read-back NaN bit-identical to `double.NaN` / `float.NaN` → TO-5, TO-6

## P3 Constraints & anti-goals (M/L)

- No public API change: the helper is `internal`; no `PublicAPI.*.txt` / `CompatibilitySuppressions.xml` edit.
- No generated-SQL change for any provider; no baseline change.
- `DB2ProviderAdapter.DecimalFloatConverters` method names, `string` parameter and return types stay; no overload or case-variant name added (looked up by name via `Expression.Call`, `DB2ProviderAdapter.cs:155-192`).
- PostgreSQL `IsNaN`/`IsInfinity` sites, ClickHouse `SetConvertExpression((double v) => double.IsNaN(v) ? …)` lambdas and `LegacyMemberConverterBase.FiniteOrNull` are not touched: PostgreSQL and `FiniteOrNull` pass the sweep; the ClickHouse lambdas are expression trees compiled at run time and are NOT swept (U-9) — their safety rests on P1's measurement that `double.IsNaN` compiles cleanly (netfx bit test), not on the sweep.
- No Azure Pipelines change. No change to `linq2db.Testing.slnf`.
- Harness is not an NUnit project and is not part of any provider test leg.

## P4 Unknowns (M/L)

- U-1 Does the windows-2025 image's clrjit (4.8.1, reasoned, unprobed) reproduce the fault, and in which mode (catchable SEH vs process-killing overflow)? — resolved-by probe: TO-2 is the first act after commit 1; the canary (SC-3) turns a non-reproducing image into a red job, never a green one. If commit 1 is not red with the 10 methods on CI, implementation stops and P11 re-plans. Measured 2026-10-16, run 38824875867 on e3ba64f67: red with exactly the 10 methods, per-assembly counts identical to local; on windows-2025 every fault (canary included) is a process-killing stack overflow 0xC00000FD, so the restart path (U-3) ran 11 times and produced the full report.
- U-2 Which canary shape faults under the local clrjit, and do bit-built replacements (`BitConverter.Int64BitsToDouble`, `static readonly` from bits, `(float)` cast of a bit-built double, `DoubleToInt64Bits` compare) compile cleanly? — resolved-by probe — measured 2026-10-15, x86 net462 (`Is64BitProcess=False`), local clrjit 4.8, FPU unmasked, `PrepareMethod` per method: FAIL (SEHException, process exit 0xC00002B5) `=> double.NaN`, `s == "x" ? double.NaN : 0`, `=> double.IsPositiveInfinity(d)`, `=> ReadonlyNaN` where `static readonly double ReadonlyNaN = BitConverter.Int64BitsToDouble(0x7FF8000000000000L)`, `=> (float)ReadonlyNaN`; OK `=> BitConverter.Int64BitsToDouble(0x7FF8000000000000L)`, `=> BitConverter.DoubleToInt64Bits(d) == 0x7FF0000000000000L`, `=> (float)BitConverter.Int64BitsToDouble(0x7FF8000000000000L)`. The JIT folds an initialized class's `static readonly` double into a constant, so cached special values fault too (D-3 changed accordingly). First probe run was silently 64-bit (SDK-style net462 exe defaults to AnyCPU without Prefer32Bit; an incremental rebuild with `-p:PlatformTarget=x86` reused the AnyCPU exe) — the harness's x86 assertion (TO-3b) is load-bearing.
- U-3 4.8.1 kills the process (stack overflow, not catchable even with `[HandleProcessCorruptedStateExceptions]`) — resolved-by design D-2 (parent/child restart past the last progress entry), verified on CI by TO-2.
- U-4 Assemblies whose dependencies don't load (EF3 → EF Core 3.1, SignalR.Server → legacy AspNetCore, Wcf → GAC System.ServiceModel) would silently skip methods — resolved-by design D-4: expected-assembly list, per-assembly ok>0, and any dependency-load skip fails unless allowlisted with a reason (TO-3d, TO-3e); measured 2026-10-16 (TO-1, local Release build): 0 dependency-load skips in all 12 assemblies; prepared counts linq2db 20,782 (+10 faults), Compat 293, EntityFrameworkCore 584, Extensions 312, FSharp 102, Remote.Grpc 384, Remote.HttpClient.Client 327, Remote.SignalR.Client 319, Remote.SignalR.Server 301, Remote.Wcf 330, Scaffold 3,206, Tools 9,374 — allowlist stays empty.
- U-5 Can a `Tests/Linq` test call an internal helper? — resolved-by scout: no `InternalsVisibleTo` anywhere in the tree; TO-5 goes through provider `MappingSchema` converters instead. Critic correction: `DataConnection.GetDataProvider(name, cs)` with an unversioned name auto-detects and opens a connection (`OracleProviderDetector.cs:56-67`, `FirebirdProviderDetector.cs:33-61`, `ProviderDetectorBase.cs:95,114`), and the CLI precedent does the same; TO-5 uses the version-pinned factories — `OracleTools.GetDataProvider(OracleVersion.v12, OracleProvider.Managed)`, `FirebirdTools.GetDataProvider(FirebirdVersion.v5)`, `DuckDBTools.GetDataProvider()`, `YdbTools.GetDataProvider()`, `ClickHouseTools.GetDataProvider(ClickHouseProvider.MySqlConnector)` (signatures checked: `Source/LinqToDB/DataProvider/{Oracle,Firebird,DuckDB,Ydb,ClickHouse}/*Tools.cs`). DuckDB/YDB ADO packages are absent on net462 (`Tests/linq2db.Providers.props:47-53`, adapters throw `Cannot load assembly`), so their cases are `#if !NETFRAMEWORK`.
- U-6 Exe output path — resolved-by scout: `ArtifactsPivots` (`Directory.Build.props:86-87`) is expanded before the csproj body, so a singular `<TargetFramework>` drops the TFM folder; use `<TargetFrameworks>net462</TargetFrameworks>` → `.build/bin/Tests.FpuJit/Release/net462/linq2db.Tests.FpuJit.exe`. Do not pass `-r`/`-a` (adds `win-x86`).
- U-7 `-c Testing` turns Source projects net10.0-only → NU1201 for a net462 consumer — resolved-by scout: exclude from Testing in `linq2db.slnx` like SingleFile (`linq2db.slnx:418-422`).
- U-8 Runtime (not JIT-time) handling of real NaN values under an unmasked FPU — resolved-by user scope: issue is the JIT-time fault; runtime FP arithmetic on NaN data is host-side (P10). The probe's run line records that the bit-built values themselves execute without trapping.
- U-10 Commit 1 reports a method beyond the 10 (another assembly, or a linq2db method the earlier probe skipped) — resolved-by rule: an extra FP-constant site gets a new E-n on the same helper via P11 before commit 2; anything of a different shape stops for user direction.
- U-9 Blind spots of a `PrepareMethod` sweep: generic instantiations and expression trees compiled at run time — resolved-by scout: no current faulting site is generic; the 36 ClickHouse expression lambdas contain only `IsNaN` calls (no FP constants). Accepted in P10, documented in the harness header.

## P5 Decisions (M/L; rejected alternatives mandatory at L)

### D-1 — Detection is a runtime JIT sweep in a dedicated x86 net462 process

- **chosen:** standalone console exe `Tests/Tests.FpuJit` that unmasks the FPU and `PrepareMethod`s every non-generic method of the shipped netfx assemblies; GitHub `build.yml` job on windows-2025.
- **rejected:** `BannedSymbols.txt` entries for `double.NaN` etc. — the trigger set is empirical (float compares pass, double compares fault, #6042's `double >= long.MaxValue` is not a symbol), and CI builds with `-p:RunAnalyzersDuringBuild=false` (`.github/workflows/build.yml:115`), so a ban would not be enforced in CI.
- **rejected:** an NUnit test in an existing suite — runs with a masked FPU and the methods are already JIT-compiled (#6053's reason for shipping without a test); x86 net462 only exists on the Access legs.
- **rejected:** Azure parity job — `build.yml` already runs on every PR and push; branch protection requires only Azure `build` (`.claude/scripts/wait-pr-checks.ps1:17-21`), so parity adds cost without gating more.
- **why this:** exercises the real failing component (clrjit) with the real failure mode, over every method, independent of which BCL member is involved.
- **failure mode of the choice:** depends on the runner image's clrjit reproducing; a patched clrjit or image change makes the canary pass → job red with "canary did not fault" and must be retired deliberately, not silently.

### D-2 — Survive process-killing faults with parent/child restarts

- **chosen:** parent (no args) spawns itself `--child [--resume-after <id>]`; child appends each method id to a progress file before preparing it and writes a `done` marker at the end; on a child exit without `done`, parent records the last progress entry as a `crash` failure and respawns past it; cap ~100 restarts.
- **rejected:** one child process per method (~20k spawns); in-process only (4.8.1 overflow kills the process, `[HandleProcessCorruptedStateExceptions]` does not catch stack overflow).
- **why this:** cost is one spawn per crash; output names the method in both modes.
- **failure mode of the choice:** a crash *between* progress write and prepare (harness bug) is misattributed to that method; the deterministic order makes it reproducible, and the canary proves both paths on the first run.

### D-3 — Fix with an internal bit-pattern helper

- **chosen:** `internal static class FloatingPointHelper` in `Source/LinqToDB/Internal/Common/`: `IsPositiveInfinity(double)` / `IsNegativeInfinity(double)` comparing `BitConverter.DoubleToInt64Bits` with `0x7FF0000000000000` / `unchecked((long)0xFFF0000000000000)`; float overloads widen to double (netfx/ns2.0 lack `SingleToInt32Bits`, Meziantou.Polyfill 1.0.165 has no float→bits polyfill); special values produced by a call on every use — `DoubleNaN()` / `DoublePositiveInfinity()` / `DoubleNegativeInfinity()` returning `BitConverter.Int64BitsToDouble(<bits>)`, float variants returning `(float)` of those — never cached in `static readonly` fields (U-2: folded into a constant and faults). Bit patterns are the BCL's own: NaN `unchecked((long)0xFFF8000000000000)` (= `BitConverter.DoubleToInt64Bits(double.NaN)`, sign bit set), `(float)` of it = `0xFFC00000` = `float.NaN`; +Inf `0x7FF0000000000000`; −Inf `unchecked((long)0xFFF0000000000000)`.
- **rejected:** document "mask the FPU before calling .NET" only — the user asked for a fix; the host workaround stays a remark in the PR.
- **rejected:** inline bit math at each of the 6 sites — duplicated magic constants.
- **rejected:** a `public` helper (testable from `Tests/Linq`) — new public surface without a request; TO-5 tests through the providers instead.
- **why this:** removes FP constants from the JIT's view at every site with one reviewed implementation.
- **failure mode of the choice:** a wrong mask silently changes literals (e.g. −Inf rendered as finite) — TO-5 discriminates sign and NaN-vs-Inf; a later "cleanup" caching the values in `static readonly` fields reintroduces the fault (U-2) — that is exactly what the sweep (TO-4, and every later PR) catches.

### D-4 — Sweep set and per-assembly vacuity guard

- **chosen:** harness csproj ProjectReferences the 12 Source projects (incl. `LinqToDB.FSharp`, found by the critic: inherits the default TFMs, `LinqToDB.FSharp.fsproj:41` net462 condition); the child sweeps an explicit expected-name list and fails if one is missing from the app directory, prepares zero methods, or skips any method for a non-allowlisted dependency-load failure.
- **rejected:** glob `linq2db*.dll` only — a dropped reference shrinks coverage silently; including the LINQPad driver — user decision 2026-10-15 (plugin, host never unmasks the FPU).
- **why this:** the user asked for every netfx-shipped library; an explicit list makes coverage loss loud.
- **failure mode of the choice:** a new netfx library added later is not swept until someone adds it; recorded in P10.

### D-5 — Move the float twins to the helper as well

- **chosen:** the float `IsPositive/NegativeInfinity` sites next to each faulting double site (DuckDB `BuildFloat`, YDB `BuildFloatLiteral`, Oracle/Firebird float lambdas) use the helper too.
- **rejected:** touch only the 10 measured methods — leaves twin methods with different idioms, inviting the next edit to copy the faulting one.
- **why this:** consistency within each twin pair; zero behaviour change (TO-5).
- **failure mode of the choice:** slightly wider diff in four files.

### D-6 — Solution configuration

- **chosen:** add `Tests/Tests.FpuJit` to `linq2db.slnx` excluded from Testing, Release and Azure solution builds (SingleFile precedent `linq2db.slnx:418-422`); the CI job builds the csproj directly in Release.
- **rejected:** include in Release — the main `build` job would compile it twice for no gain.
- **why this:** avoids NU1201 under Testing; keeps the main build unchanged.
- **failure mode of the choice:** only Debug solution builds compile it locally; CI job is the authority.

## P6 Edit-points

- E-1 `Tests/Tests.FpuJit/Tests.FpuJit.csproj` — new: `TargetFrameworks=net462`, `PlatformTarget=x86`, `OutputType=Exe`, `IsPackable=false`, no doc file, no ref assembly, `AdditionalFiles Remove="..\BannedSymbols.txt"`, ProjectReferences to the 12 Source projects
- E-2 `Tests/Tests.FpuJit/Program.cs` — new: parent/child sweep harness, canary `=> double.NaN` (measured faulting, U-2), control-word re-arm/re-verify, dependency-skip allowlist, per-child wall-clock cap, report (D-1, D-2, D-4)
- E-3 `linq2db.slnx` — add the project with Testing/Release/Azure `Build Project="false"` entries
- E-4 `.github/workflows/build.yml:fpu-jit-sweep` — new job after `singlefile-smoke` with `timeout-minutes`: checkout, setup-dotnet 10.x, `dotnet build Tests/Tests.FpuJit/Tests.FpuJit.csproj -c Release -p:RunAnalyzersDuringBuild=false -p:RunApiAnalyzersDuringBuild=false`, run `.build/bin/Tests.FpuJit/Release/net462/linq2db.Tests.FpuJit.exe`
- E-5 `.claude/scripts/wait-pr-checks.ps1:Gate` — corpus: add the new job's display name to the default `-Gate` array
- E-6 `.claude/docs/github-actions.md` — corpus: add the job to the GitHub-legs table and list
- E-7 `Source/LinqToDB/Internal/Common/FloatingPointHelper.cs` — new internal static helper (D-3)
- E-8 `Source/LinqToDB/Internal/DataProvider/DuckDB/DuckDBMappingSchema.cs:BuildDouble,BuildFloat` — infinity checks via helper
- E-9 `Source/LinqToDB/Internal/DataProvider/Ydb/YdbMappingSchema.cs:BuildDoubleLiteral,BuildFloatLiteral` — infinity checks via helper
- E-10 `Source/LinqToDB/Internal/DataProvider/Oracle/OracleMappingSchema.cs:ctor float/double SetValueToSqlConverter lambdas` — infinity checks via helper
- E-11 `Source/LinqToDB/Internal/DataProvider/Firebird/FirebirdMappingSchema.cs:ctor float/double SetValueToSqlConverter lambdas` — infinity checks via helper
- E-12 `Source/LinqToDB/Internal/DataProvider/DB2/DB2ProviderAdapter.cs:DecimalFloatConverters.ToDouble,ToSingle,ToDoubleNullable,ToSingleNullable` — NaN via helper constants
- E-13 `Source/LinqToDB/Internal/DataProvider/ClickHouse/ClickHouseMappingSchema.cs:StringToFloat,StringToDouble` — special values via helper constants
- E-14 `Tests/Linq/UserTests/Issue6051Tests.cs` — new container-free characterization test (TO-5)

## P7 Impact map (M/L)

- `Tests/Directory.Build.props:5-6` — default `TargetFrameworks` and Testing override apply to every Tests project — covered by E-1
- `Tests/Directory.Build.props:24` + `Tests/BannedSymbols.txt:90` — `T:System.Console` ban (RS0030, Release analyzers) — covered by E-1
- `Directory.Build.props:86-87` — `ArtifactsPath` / `ArtifactsPivots` decide the exe path (plural TFM keeps the `net462` folder) — covered by E-4
- `Directory.Build.props:120-132` — Release enables analyzers, code style, doc generation with warnings-as-errors — covered by E-1
- `linq2db.slnx:327-333,353-355,395-397,418-422` — Testing exclusions for Compat/Wcf/EF3 and SingleFile's full exclusion — covered by E-3
- `linq2db.Testing.slnf:4-33` — explicit project list for Azure test builds — out-of-scope
- `.github/workflows/build.yml:21-24,115,202-216` — triggers (no path filters, no `needs:`), analyzer-off flags, SingleFile job shape — covered by E-4
- `.claude/scripts/wait-pr-checks.ps1:45-52` — default gate list of `build.yml` job names — covered by E-5
- `.claude/docs/github-actions.md:13-20,27-28` — GitHub-legs table and "six GH legs" list — covered by E-6
- `Build/Azure/pipelines/templates/build-job.yml:6,87-101` — Azure `with_singlefile_smoke` parity knob — deferred: no Azure parity (D-1)
- Source sweep `\b(double|float|Double|Single)\.(NaN|PositiveInfinity|NegativeInfinity|Epsilon)\b|\bIs(Positive|Negative)?Infinity\b|\bIsNaN\b|\bIsFinite\b` across all `Source/` — product hits only in `Source/LinqToDB`; none in EF3, Remote.*, Tools, Scaffold, Extensions, Compat, FSharp, T4 (critic re-ran with `Math.*`/FP-cast patterns: only `Math.Max` over `int`) — covered by E-8
- `Source/LinqToDB/Internal/DataProvider/PostgreSQL/PostgreSQLMappingSchema.cs:55,63` — `IsNaN || IsInfinity` (passes sweep) — out-of-scope
- `Source/LinqToDB/Internal/DataProvider/ClickHouse/ClickHouseMappingSchema.cs:104-139` — 36 expression-tree `IsNaN` lambdas, not swept; safe per P1 `IsNaN` measurement (P10 blind spot) — out-of-scope
- `Source/LinqToDB/Internal/DataProvider/Translation/LegacyMemberConverterBase.cs:657` — `FiniteOrNull` (passes sweep) — out-of-scope
- `Source/LinqToDB.Analyzers/DurationComparisonAnalyzer.cs:620,625,636` — runs inside csc — out-of-scope
- `Source/LinqToDB/Internal/DataProvider/DB2/DB2ProviderAdapter.cs:155-192` — `Register` builds `Expression.Call(typeof(DecimalFloatConverters), name, …)` by name; bodies change only — covered by E-12
- `Source/LinqToDB/Internal/DataProvider/ClickHouse/ClickHouseMappingSchema.cs:910-911` — `SetConvertExpression((string v) => StringToFloat(v))` callers; bodies change only — covered by E-13
- `Source/LinqToDB/Mapping/MappingSchema.cs:211,227` — `SetValueToSqlConverter` stores `Action` delegates (compiled IL, swept) — covered by E-10
- `Source/LinqToDB.FSharp/LinqToDB.FSharp.fsproj:5,41` — 12th netfx-shipped library (default TFMs incl. net462) — covered by E-1
- `Tests/linq2db.Providers.props:47-53` — `Ydb.Sdk` / `DuckDB.NET.Data.Full` only for non-net462 — covered by E-14
- `Source/LinqToDB/Internal/DataProvider/Oracle/OracleProviderDetector.cs:56-67`, `Firebird/FirebirdProviderDetector.cs:33-61` — unversioned provider names auto-detect by connecting — covered by E-14
- `Source/LinqToDB/Internal/Common/*.cs` declaration style (both `internal static class` and `public static class`; `DecimalHelper` public in `PublicAPI.Shipped.txt:1820`) — covered by E-7
- `InternalsVisibleTo` searched across the worktree — no grants; test goes through provider mapping schemas — covered by E-14
- `BitConverter|DoubleToInt64Bits|Int64BitsToDouble|unsafe` searched in `Source/LinqToDB` — no existing FP-bit helper to reuse — covered by E-7
- Tests exercising the changed paths: `Tests/Linq/Linq/TypesTests.cs:810` `TestSpecialValues` (inline + parameter; Oracle, Firebird, PostgreSQL, DuckDB, YDB, ClickHouse), `Tests/Linq/DataProvider/Types/YdbTypeTests.cs:267,294`, `DuckDBTypeTests.cs:199,212`, `ClickHouseTypeTests.cs:190`, `Tests/Linq/DataProvider/DB2Tests.cs:72` `DecFloatSpecialToFloatingPoint` — covered by E-14

## P8 Test obligations (M/L)

- TO-1 Local sweep on commit 1 (harness, no fix, Release build) reports exactly the 10 P1 methods as `FAIL`, canary faulted as expected, exit ≠ 0 — providers: none (no database; harness only) — proof: red→green
- TO-2 CI `fpu-jit-sweep` on commit 1 is red with the same 10 methods — providers: none (no database; harness only) — proof: red→green
- TO-3a Mutation: canary body replaced by a finite constant → harness exits ≠ 0 with "canary did not fault" — providers: none (no database; harness only) — proof: control
- TO-3b Mutation: built/run as 64-bit (`-p:PlatformTarget=x64`) → exits ≠ 0 with "must run as x86" — providers: none (no database; harness only) — proof: control
- TO-3c Mutation: `_control87` call skipped → exits ≠ 0 with "FPU control word unchanged" — providers: none (no database; harness only) — proof: control
- TO-3d Mutation: one expected assembly removed from the output dir → exits ≠ 0 naming it — providers: none (no database; harness only) — proof: control
- TO-3e Mutation: one transitive dependency (e.g. `Microsoft.EntityFrameworkCore.dll`) removed from the output dir → exits ≠ 0 reporting non-allowlisted dependency skips for that assembly — providers: none (no database; harness only) — proof: control
- TO-3f Mutation: the per-method re-arm masks the FPU instead (A-1) → exits ≠ 0 with "FPU control word masked" — providers: none (no database; harness only) — proof: control
- TO-3g Control (A-3): on unfixed sources with a masked compile of `DuckDBMappingSchema.BuildDouble` injected into the canary's prepare, restart-on-reset still reports 10 faults incl. BuildDouble; with restart disabled only 9 (the control can disagree); fixed sources → 0 — providers: none (no database; harness only) — proof: control
- TO-3h Mutation (A-3): `AllowedUnverified` emptied → exits 2 with `ERROR: unverified … DuckDB…` — providers: none (no database; harness only) — proof: control
- TO-3i Mutation (A-3): type-initializer warm-up removed → the `SqlServerMappingSchema` methods go unverified (measured 50) and the run exits ≠ 0 (hit the 100-restart cap, exit 3) — providers: none (no database; harness only) — proof: control
- TO-4 Local sweep and CI `fpu-jit-sweep` on commit 2 (fix) green: only the canary faults, all 12 assemblies with ok>0 and no non-allowlisted dependency skips — providers: none (no database; harness only) — proof: red→green
- TO-5 `Issue6051Tests`: through the version-pinned factories in U-5 (`<Tools>.GetDataProvider(...).MappingSchema.ValueToSqlConverter`, no connection; DuckDB/YDB cases `#if !NETFRAMEWORK`), assert exact literals for float and double `NaN`, `+Inf`, `−Inf`, `1.5` on DuckDB, YDB, Oracle, Firebird (expected strings copied from current source, e.g. Oracle `BINARY_DOUBLE_NAN` / `-BINARY_DOUBLE_INFINITY` / `BINARY_DOUBLE_INFINITY`), and ClickHouse MySql-interface string→double/float conversion of `inf`, `-inf`, `nan`, `1.5` with NaN asserted bit-identical to `double.NaN` / `float.NaN` (`DoubleToInt64Bits`, `BitConverter.GetBytes`) — on commit 1 this pins the current BCL-constant behaviour so a wrong NaN pattern in D-3 turns it red; written and green on commit 1, unchanged on commit 2; discriminating inputs `+Inf` vs `−Inf` (sign bit) and `NaN` vs `Inf` (mantissa); DB2 converters need IBM `DB2DecimalFloat` and are left to TO-6 — providers: DuckDB, YDB, Oracle, Firebird, ClickHouse mapping schemas only, no connection — proof: characterization
- TO-6 Existing provider tests green: `TypesTests.TestSpecialValues`, `DuckDBTypeTests.TestFloat/TestDouble`, `YdbTypeTests.TestFloat/TestDouble`, `ClickHouseTypeTests.TestFloatingPointTypes`, `DB2Tests.DecFloatSpecialToFloatingPoint` — locally for available providers, the rest via CI `/azp run` — providers: Oracle, Firebird, PostgreSQL, DuckDB, YDB, ClickHouse (TestSpecialValues set), DB2 (DecFloat tests) — proof: characterization

## P9 Verification gates

- G-01: pass (local) — TO-1/TO-4 sweep red→green locally (10 → 0 faults) and TO-2 red on CI; TO-3a..f all exit 2 with the named message (rerun after A-3: pass); TO-3g 10/10/9/0 as expected; TO-3h exit 2; TO-3i exit 3 with 50 unverified; harness Release with analyzers on clean after A-3; CI sweep on 60d68b534 (run 38901554360) green: 0 faults, 11 resets, the same 5 DuckDB methods unverified (allowed), canary exit 0xC00000FD; TO-5 `Issue6051Tests` net10.0 10/10, net462 6/6 before and after the fix (worktree-test.ps1); TO-6 DuckDB `TestSpecialValues` + `DuckDBTypeTests.TestFloat/TestDouble` 8/8; remaining TO-6 providers green on test-all (see G-02)
- G-02: pass — test-all on 11b94285c green: Azure 24322 (Win SQL Server legs) and GitHub `tests (comment)` run 38826712217 (all Lin/Win provider legs incl. Firebird, Oracle 11–23, ClickHouse, YDB, DB2/DuckDB); no linq2db.baselines branch/PR for #6058 → no SQL baseline change, as expected. Also closes TO-6's CI part.
- G-05: pass — `Source/LinqToDB` Release netstandard2.0 and net10.0 (analyzers on) exit 0; net462 built via the harness; harness Release with analyzers on clean after fixing CA1825/CA5392 and suppressing CA2153 (catching the fault is the purpose); `Tests/Linq` Release net10.0 clean
- G-06: — (pending)
- G-07: — (pending)
- G-09: — (pending) adversarial read done on 11b94285c (code-reviewer, fable): 1 MIN (MIN001 → A-3, fix in progress), helper/sites/harness otherwise confirmed; out-of-scope observation not yet put to the user: generic methods could be partly swept via canonical `object` instantiations (`PrepareMethod(handle, RuntimeTypeHandle[])`)

## P10 Adjudicated (M/L)

- Generic method instantiations and expression trees compiled at run time are not swept (`PrepareMethod` needs closed instantiations; expression lambdas are compiled by the app). No current faulting site is generic; the ClickHouse expression lambdas hold only `IsNaN` calls.
- Runtime FP arithmetic on NaN data under an unmasked FPU is not addressed — host responsibility; this change removes JIT-time faults only.
- LINQPad driver (net472) excluded — user decision 2026-10-15.
- No Azure parity job: GitHub `build.yml` runs on every PR/push and branch protection requires only Azure `build`, so an Azure copy gates nothing more (D-1).
- A future runner image whose clrjit no longer faults turns the job red via the canary — intended.
- SC-2's "exactly 10" is a prediction for the 11 non-core assemblies, not a measurement: TO-1 measures it, U-10 disposes of a surprise.
- A netfx library added to `Source/` later is not swept until added to the E-1/E-2 list (D-4).
- YDB has no NaN literal branch and DB2's `sNaN` branch is untested — pre-existing, outside #6051.

## P11 Amendments (M/L)

- A-1 (2026-10-16, within E-2, no new edit-point) — first local run stopped with `FPU control word masked (0x8009001F) after DuckDBDataProvider::.ctor()`: code run while preparing a method (type initializers / native DLL init) resets the control word. The harness now re-arms and verifies before every `PrepareMethod` (so each method is compiled unmasked) and reports resets instead of failing on them; measured 16 resets in TO-1, the first being the canary's own fault. TO-3f's mutation becomes "the per-method re-arm masks instead" → `FPU control word masked … before`.
- A-3 (2026-10-16, within E-2) — G-09 adversarial read (code-reviewer on fable) MIN001: `PrepareMethod` is a no-op for an already-compiled method, so a method compiled *inside* another prepare after a control-word reset was compiled masked and later counted OK (5 resets on the green CI run, first `DuckDBDataProvider::.ctor()`). User chose fix-here: after a prepare that leaves the FPU reset the child writes `RESTART <id> at|after` and exits (`ExitRestart = 4`), the parent resumes in a fresh process. Measured refinements of that design: (1) plain resume-after cascaded (51 local resets: each fresh process re-ran the resetting type initializer on the next method) and left the resetting method itself unverified; preloading all transitive references changed nothing (not assembly loading), so a restarted child runs the type initializers of earlier resetting methods' declaring types masked, then **retries** the method (`at`); a second reset records `UNVERIFIED`, which fails the sweep unless allowlisted (`AllowedUnverified`: DuckDB — DuckDB.NET 1.5.5 ships net8.0/net10.0 only, the adapter's failed bind in `DuckDBMappingSchema`'s type initializer resets on every attempt) → 12 resets, SqlServer retried clean; (2) a fault restarts `after` (nothing to retry); (3) a dependency skip continues in-process (a failed bind resets the word itself; every skip already fails the sweep) — TO-3e had hit the 100-restart cap. New controls TO-3g/h/i.
- A-2 (2026-10-16, timing of E-5/E-6) — the corpus edits to `wait-pr-checks.ps1` and `github-actions.md` are deferred until the linq2db PR merges (standing user rule: corpus docs describe merged state only) and parked as a PR comment with the diff.

## P12 Critic verdict (M/L)

**weak** — plan-critic on `fable`, 2026-10-15. Objections and responses:
1. `linq2db.FSharp` is a 12th netfx-shipped library — accepted, verified (`LinqToDB.FSharp.fsproj:5,41`); SC-1/D-4/E-1 now 12.
2. U-5's "no connection" claim is false for Oracle/Firebird (auto-detect opens a connection; the CLI precedent does too) — accepted, factory signatures verified; TO-5 re-routed to version-pinned factories.
3. TO-5 would be red on net462 for DuckDB/YDB (ADO packages absent, `Tests/linq2db.Providers.props:47-53`) — accepted; `#if !NETFRAMEWORK`.
4. D-3's NaN pattern `0x7FF8…` differs from `double.NaN` (`0xFFF8…`) in the sign bit; read-back would not be bit-identical — accepted; D-3 uses the BCL patterns, TO-5 asserts bit-identity on the read path.
5. Vacuity holes: dependency-load skips counted as skips; control word checked only at start; no job/child timeout — accepted; SC-3/E-2/E-4 extended, TO-3e/TO-3f added.
6. P3 said the ClickHouse expression lambdas "pass the sweep" while U-9 says they are not swept — accepted; P3/P7 reworded to rest on P1's `IsNaN` measurement.
7. SC-2 "exactly 10" is measured for linq2db.dll only, with no disposition for an 11th — accepted; U-10 added.
Critic searched: FP-constant/`Is*Infinity`/`IsNaN` regex across `Source/`; `Math.*`/FP casts across the 10 non-core netfx projects; FP terms in `LinqToDB.FSharp/*.fs`; TFM declarations across props/csproj; provider detectors and `ProviderDetectorBase.cs:50-178`; DuckDB/YDB adapters and `Tests/linq2db.Providers.props`; full reads of `build.yml`, `linq2db.slnx:310-430`, `build-job.yml:1-110`, `wait-pr-checks.ps1:1-70`, `github-actions.md:1-45` and the 6 fix-site files. Could not check: windows-2025 clrjit (U-1 stop rule), probe skip count (now measured in TO-1), CS8002 strong-name warnings under TreatWarningsAsErrors (G-05 local Release build). Revision not re-sent: the verdict was `weak`, not `refuted`, and every objection was accepted as stated.
