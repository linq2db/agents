# Work plan: feature-efcore-fsharp-10 — Enable EntityFrameworkCore.FSharp 10.0.0 in the EF10 tests

**Tier:** M  ·  **Status:** approved  ·  **Approved-at:** 2026-10-28 (user, after critic round 1 weak + responses)  ·  **Branch:** feature/efcore-fsharp-10
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

## P1 Problem

`EntityFrameworkCore.FSharp` was frozen at 6.0.7 (net6.0, EF Core 6) until v10.0.0 (2026-10-27, net10.0, `Microsoft.EntityFrameworkCore.Design`/`Relational` >= 10.0.5, `FSharp.Core` >= 10.0.102 — nuspec read from nuget.org). linq2db pins 6.0.7 (`Directory.Packages.props:235`) for `Tests/EntityFrameworkCore.FSharp` (net8.0, references `LinqToDB.EntityFrameworkCore.EF8.csproj`), which only `Tests.EntityFrameworkCore.EF8.csproj:11` references. The C# side, `Tests/EntityFrameworkCore/Tests/FSharpTests.cs:1`, is under `#if EF8`, a symbol no test project defines (only `EF10` is defined, `Tests.EntityFrameworkCore.EF10.csproj:7`) — since #5151 (9e8819da4) the F# EF integration tests compile into no assembly and have never run. Measured: with the wiring moved to EF10 but 6.0.7 kept, `Issue4646TestEF` / `Issue4646TestLinqToDB` fail on SQLite.MS with `MissingMethodException: ISqlExpressionFactory.Convert(SqlExpression, Type, RelationalTypeMapping)`.

## P2 Success criteria

- SC-1 The F# EF tests compile into `Tests.EntityFrameworkCore.EF10` and run against EFCore.FSharp 10.0.0 → TO-1
- SC-2 `Issue4646TestEF` and `Issue4646TestLinqToDB` pass with no `[ActiveIssue]` — on SQLite.MS locally, and on the server EF providers via the CI EF10 legs (G-01) → TO-2, TO-3
- SC-3 The tests reach EFCore.FSharp's member translator (the path 6.0.7 breaks) → TO-4
- SC-4 Release build of the EF10 test project is analyzer-clean → TO-5

## P3 Constraints & anti-goals (M/L)

- No `Source/` change, no public API, no baselines change beyond new F# test SQL for EF10 (the tests never ran, so their baselines are added, not changed).
- EF3 / EF8 / EF9 test projects keep running unchanged; EF8 loses only a ProjectReference to an assembly whose tests never compiled.
- No EF11 (#5942 branch) wiring here — master has no EF11 test project.

## P4 Unknowns (M/L)

- U-1 Does 10.0.0's transitive `Microsoft.EntityFrameworkCore.Design` 10.0.5 clash with central pins (e.g. `Microsoft.CodeAnalysis.CSharp.Workspaces` 4.8.0)? — resolved-by probe: `CentralPackageTransitivePinningEnabled=false` (`Directory.Packages.props:4`); measured: Debug build of EF10 tests exit 0, zero warnings (`.build/.agents/efcore-fsharp-build1.log`); resolved in `.build/obj/Tests.EntityFrameworkCore.EF10/project.assets.json`: `EntityFrameworkCore.FSharp` 10.0.0, `Microsoft.EntityFrameworkCore`/`.Relational` 10.0.12 (`$(Net10Latest)` via the test provider packages, so the source project's `Relational` 10.0.0 floor at `Directory.Packages.props:122` is lifted, no NU1605), `Microsoft.EntityFrameworkCore.Design` 10.0.5, `FSharp.Core` 10.1.401.
- U-2 Why did `Issue4646TestLinqToDB` fail once un-dead? — resolved-by probe: measured `Sequence contains more than one element`; its INSERT binds `@Value = NULL, @ValueN = NULL` correctly, but `Issue4646TestEF` runs first in the same database (`ContextTestBase.cs:109-110` re-creates the DB only when the context type changes), so `Single()` sees two rows. A test-isolation defect, not #4646 (closed, 6.4.0).
- U-3 Is the `ISqlExpressionFactory.Convert` path really exercised, or do the tests pass vacuously? — resolved-by probe: measured control — same tree with 6.0.7 → both `Issue4646*` fail with the `MissingMethodException` (`worktree-test-…-35376-….log`); with 10.0.0 → 3/3 pass.
- U-4 Does the `Testing` solution config (net10.0-only) now build the fsproj? — resolved-by scout: `linq2db.slnx:392` excluded it from `Testing` because it was net8.0-only; `linq2db.Testing.slnf:28` already lists it. Remove the exclusion (E-6).
- U-5 Server providers (SqlServer / PostgreSQL / MySQL) — resolved-by CI: local containers are stopped; the EF10 leg runs them in Azure (`build-job.yml:142,377`) and GitHub (`tests.yml:288,429`).

## P5 Decisions (M/L; rejected alternatives mandatory at L)

### D-1 — Move the F# EF tests from EF8 to EF10 rather than keep EF8

- **chosen:** fsproj → net10.0 + `LinqToDB.EntityFrameworkCore.EF10.csproj`; ProjectReference moves EF8 → EF10 test project; guard `#if EF8` → `#if EF10`.
- **rejected:** keep 6.0.7 on EF8 and define `EF8` — 6.0.7 targets EF Core 6, and EF8 coverage was never live either; multi-targeting the fsproj for EF8+EF10 needs two EFCore.FSharp versions under one central pin.
- **why this:** 10.0.0 ships only net10.0 / EF Core 10; one live EF line beats one dead one.
- **failure mode of the choice:** F# EF coverage exists for EF10 only; an EF8/EF9-specific F# regression goes unseen (it already did).

### D-2 — Fix the order dependency by clearing the table, not by re-gating

- **chosen:** `db.GetTable<Issue4646Table>().Delete();` at the start of both `Issue4646*` tests — precedent `IssueTests.cs:1285` (`Issue5975Seed`).
- **rejected:** keep `[ActiveIssue(4646)]` — #4646 is closed and the measured failure is the test's own state leak; a transaction — `Issue4646TestLinqToDB`'s F# helper opens its own `CreateLinqToDBConnection()`.
- **why this:** smallest change that makes each test independent of order.
- **failure mode of the choice:** isolation still rests on `ContextTestBase.cs:109-110` (DB re-created when the context type changes) for other fixtures, and a parallel run on one database would still collide, as for every EF fixture.

## P6 Edit-points

- E-1 `Directory.Packages.props:EntityFrameworkCore.FSharp` — 6.0.7 → 10.0.0
- E-2 `Tests/EntityFrameworkCore.FSharp/Tests.EntityFrameworkCore.FSharp.fsproj:TargetFrameworks` — net8.0 → net10.0; ProjectReference EF8 → EF10 source project
- E-3 `Tests/EntityFrameworkCore/Tests.EntityFrameworkCore.EF8.csproj:ProjectReference` — drop the fsproj reference
- E-4 `Tests/EntityFrameworkCore/Tests.EntityFrameworkCore.EF10.csproj:ProjectReference` — add the fsproj reference
- E-5 `Tests/EntityFrameworkCore/Tests/FSharpTests.cs:FSharpTests` — `#if EF8` → `#if EF10`; drop `[ActiveIssue(4646)]` + its comment; clear `Issue4646Table` in both `Issue4646*` tests
- E-6 `linq2db.slnx:Tests.EntityFrameworkCore.FSharp` — drop the `Testing|*` build exclusion

## P7 Impact map (M/L)

- `Directory.Packages.props:235` (sole `EntityFrameworkCore.FSharp` pin; searched `EntityFrameworkCore\.FSharp` repo-wide excluding `.claude/`) — covered by E-1
- `Tests/EntityFrameworkCore.FSharp/*.fs` (only `open EntityFrameworkCore.FSharp[.Extensions]` consumers, same search) — compile unchanged against 10.0.0 (measured build) — out-of-scope
- `Tests/EntityFrameworkCore/Tests.EntityFrameworkCore.EF8.csproj:11` (only fsproj referrer; searched `Tests.EntityFrameworkCore.FSharp.fsproj`) — covered by E-3
- `Tests/EntityFrameworkCore/Tests.EntityFrameworkCore.EF10.csproj` — covered by E-4
- `Tests/EntityFrameworkCore/Tests/FSharpTests.cs:1,58` (only `#if EF8` in `Tests/EntityFrameworkCore`; only `ActiveIssue(4646` in `Tests/`) — covered by E-5
- `linq2db.slnx:392` — covered by E-6
- `linq2db.Testing.slnf:28` (already lists fsproj) — out-of-scope
- `Tests/linq2db.BasicTestProjects.props:21` (comment names the F# project as not referencing Tests.Base — still true) — out-of-scope
- `CONTRIBUTING.md:56` (project table row, TFM-neutral) — out-of-scope
- `Build/Azure/pipelines/templates/build-job.yml:136,142,371,377`, `.github/workflows/tests.yml:288,429` (publish EF8/EF10 test projects x64 and x86; searched `EFTests|Tests.EntityFrameworkCore.EF`) — F# assembly now ships with the EF10 publish; no pipeline edit — out-of-scope
- `Test.cmd:29,31` (runs EF8/EF10 exes) — out-of-scope
- `Tests/EntityFrameworkCore/ContextTestBase.cs:109-110` (DB reuse within a context type, source of U-2) — covered by E-5

## P8 Test obligations (M/L)

- TO-1 `FSharpTests` discovered in `Tests.EntityFrameworkCore.EF10` (3 tests, `-ExpectTests` none missing) — providers: SQLite.MS — proof: red→green (master: 0 discovered, file under `#if EF8`)
- TO-2 `Issue4646TestEF` passes, row reads back `Value = null`, `ValueN = null` — providers: all EF providers (SQLite.MS local, rest CI) — proof: red→green (6.0.7 on EF10: `MissingMethodException`)
- TO-3 `Issue4646TestLinqToDB` passes with no gate, after `Issue4646TestEF` in the same run — providers: all EF providers (SQLite.MS local, rest CI) — proof: red→green (without the table clear: `Sequence contains more than one element`)
- TO-4 control: same tree with E-1 reverted to 6.0.7 fails TO-2/TO-3 with the `ISqlExpressionFactory.Convert` `MissingMethodException` — providers: SQLite.MS — proof: control (mutation: E-1 reverted)
- TO-5 `dotnet build Tests/EntityFrameworkCore/Tests.EntityFrameworkCore.EF10.csproj -c Release` exits 0 — providers: n/a — proof: characterization

## P9 Verification gates

- G-01: pass (local) — final tree, `worktree-test.ps1 -PerProvider -Filter FullyQualifiedName~FSharpTests`: SQLite.MS 3/3, SqlServer.2022.MS 3/3, PostgreSQL.18 3/3, none missing (TO-1..TO-3); control (TO-4) measured pre-plan. MySQL (Microting) and the x64/x86 publish path stay unverified until the EF10 legs (Azure `build-job.yml:142,377`, GitHub `tests.yml:288,429`) are green on the PR head — record run ids + head SHA here
- G-02: — (pending) baselines PR for the new F# EF10 SQL: confirm it only adds `*.EF10` `FSharpTests` files (P3), none pre-existing in linq2db.baselines
- G-06: pass — `git diff` touches only the E-1..E-6 lines; column alignment of the `PackageVersion` row kept
- G-07: pass — no `Tests/Tests.Playground/` change in `git status`
- G-09: — (pending) 
- TO-5: pass — `dotnet build Tests/EntityFrameworkCore/Tests.EntityFrameworkCore.EF10.csproj -c Release` → Build succeeded, 0 warnings (`.build/.agents/efcore-fsharp-release.log`)

## P10 Adjudicated (M/L)

- F# EF coverage is EF10-only (D-1): EFCore.FSharp 10.0.0 ships net10.0 only.

## P11 Amendments (M/L)

_None._

## P12 Critic verdict (M/L)

- Round 1 — **weak** — `plan-critic` on `sonnet` (configured `fable` hit its quota mid-run; substituted per skill step 7). Searched: `EntityFrameworkCore\.FSharp|FSharpTests` repo-wide; `DefineConstants|EF8|EF10` under `Tests/EntityFrameworkCore`; `Build/` + `Test.cmd` publish/run lines; F# `ToTable` mapping (`FSharpContext.fs:40`); `ContextTestBase.cs:60-113`; the diff vs E-1..E-6. Objections and response:
  - SC-2 "every EF provider" rests on SQLite.MS only; U-5 defers to CI — response: G-01 now names the EF10 x64/x86 legs as the proof and states server providers unverified until they are green.
  - Resolved `Relational` / `Design` versions unrecorded vs the 10.0.0 `Relational` pin — response: measured in `project.assets.json`, recorded in U-1 (10.0.12 / 10.0.5).
  - P7's pipeline rows gave no publish/x86 evidence — response: folded into G-01.
  - D-2 "failure mode: none" ignored the reliance on `ContextTestBase.cs:109-110` — response: D-2 reworded.
  - Baselines: no check for pre-existing F# EF10 files — response: G-02 now owns it.
