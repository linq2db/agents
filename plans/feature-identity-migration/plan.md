# Work plan — `feature/identity-migration` (PR #5640): the three CI failures

- **Tier:** M
- **Status:** implementing
- **Scope note:** the branch (the LinqToDB.Identity monorepo migration) predates this plan. This plan covers
  only the three CI failures diagnosed and fixed in this session.

## P1 Problem

Three independent failures on PR #5640 at head `1c30ea5`.

**F-1 — `LockoutEnd` breaks `CreateTable` on 8 provider configurations.**
`IdentityUser<TKey>.LockoutEnd` is `DateTimeOffset?` and `DefaultMappings.SetupIdentityUser` maps it with no
`DataType`, so each provider's SQL builder is asked to render `DataType.DateTimeOffset`. Seven have no case
for it and `BasicSqlBuilder.BuildDataTypeFromDataType` falls back to printing the enum name. Measured on CI
run [35389792476](https://github.com/linq2db/linq2db/actions/runs/35389792476): 556 of 557 real failures
across 9 legs. SAP HANA: `incorrect syntax near "DateTimeOffset"`. DB2 LUW: `SQL0204N "DATETIMEOFFSET" is an
undefined name`. Access: `Syntax error in field definition.` Firebird 2.5/3 emit the FB4+
`TIMESTAMP WITH TIME ZONE` unconditionally and get `Dynamic SQL Error`.

**F-2 — `linq2db.Identity` suppresses the analyzer subtree for its consumers.**
`Build/Azure/scripts/verify-analyzer-delivery.ps1` fails the `Build and pack` job with 5 violations, one per
TFM group: `dependency linq2db in group net10.0 has exclude=Build,Analyzers`. The `ProjectReference` carried
no `PrivateAssets`, so NuGet's default (`contentfiles;analyzers;build`) makes pack write the exclusion.

**F-3 — Oracle test runs fail and hang on a stale cached cursor.**
`Schema` / `KeyedSchema` execute a byte-identical drop block twice on one connection with `CreateTable` in
between, so ODP.NET re-executes a cached cursor after a server-side metadata change. Reproduced locally on
Oracle 11 (45 Identity tests): `ORA-24449: could not reexecute statement after server side metadata changes`
×4, `ORA-00932: expected BINARY got NUMBER` on a block with no binds, and 2 `NullReferenceException`s from
corrupted driver state. `ORA-24449` is the same error CI's Oracle 21/23 leg reported. Per the maintainer,
random Oracle cursor errors are also why Oracle legs get CI restarts and were never ported to GitHub
Actions — never filed as an issue.

## P2 Success criteria

- **SC-1** (F-1) — `CreateTable<IdentityUser<TKey>>` emits a valid datetime column type for `LockoutEnd` on
  Access, SqlCe, Sybase, SAP HANA, Informix, DB2 LUW, Firebird 2.5 and Firebird 3.
- **SC-2** (F-1) — providers that already render `DataType.DateTimeOffset` emit **exactly** what they emit
  today: SQL Server, PostgreSQL, Oracle, MySQL, DuckDB, YDB, DB2 zOS, Firebird 4, Firebird 5. Failable by
  the DDL-text instrument in `TO-2`, **not** by a baseline diff — see `P11 A-2`.
- **SC-3** (F-1) — no file under `Source/LinqToDB/` changes.
- **SC-4** (F-2) — `verify-analyzer-delivery.ps1` reports 0 violations for `linq2db.Identity`.
- **SC-5** (F-3) — the Identity suite passes on Oracle with the driver's statement cache disabled; the
  ORA-24449 / ORA-00932 / NRE family does not occur.

## P3 Constraints & anti-goals

- **No linq2db core change for F-1.** Maintainer instruction: *"we don't need to change linq2db, we need to
  annotate column with proper DataType enum value with per-provider configuration."*
- **F-3 is fixed in test connection strings only.** Maintainer instruction: *"it doesn't make sense to cache
  it in tests where caching only create problems."* Disclosed cost in `P10`.
- **Anti-goal: the offset value.** Pinning to a local datetime type discards the UTC offset — which the
  providers' existing value converters already did before this change.
- **Anti-goal: ClickHouse and YDB.** Their Identity failures are `InsertOrUpdate`/identity-support gaps,
  unrelated to `DateTimeOffset`.

## P4 Unknowns

| # | Assumption | Resolution |
|---|---|---|
| U-1 | A configuration-scoped attribute is resolved in preference to an unscoped one | resolved-by probe — `MappingSchema.cs:1225-1234`: config-matched attributes are added first in `ConfigurationList` order, unscoped appended after, **non-matching scoped ones excluded entirely** |
| U-2 | A provider's **base** configuration name is in the runtime list for its variants | resolved-by probe — schemas nest: `AccessMappingSchema.cs:123-126`, `SybaseMappingSchema.cs:86-88` |
| U-3 | DB2 zOS must not be caught by a DB2-wide registration | resolved-by probe — `DB2MappingSchema.cs:260,319` are siblings under base `DB2`; zOS renders correctly already. Pin `ProviderName.DB2LUW` |
| U-4 | Firebird 4/5 must not be caught | resolved-by probe — `FirebirdMappingSchema.cs:234,254,259,269` are siblings under base `Firebird`. Pin `Firebird25` + `Firebird3` only |
| U-5 | `LockoutEnd` is the only `DateTimeOffset` column | resolved-by probe — passkey `CreatedAt` is inside a JSON column (`DefaultMappings.cs:270`) |
| U-6 | The insert/read round-trip works on the 8 pinned providers | **reasoned, not probed** for the *parameter* path. `E-1` moves parameter binding from `DataType.DateTimeOffset` to `DateTime2` with a `DateTimeOffset` CLR value. Access and SqlCe convert unconditionally (`AccessDataProvider.cs:139-140`, `SqlCeDataProvider.cs:91-92`); Sybase, SAP HANA, Informix have no such handling in `SetParameter`. Untestable locally (no containers). `TO-3` is the instrument |
| U-7 | Both ODP.NET keywords are needed | resolved-by probe — `Statement Cache Size=0` alone still produced 9/45 failures; self-tuning re-enables the cache |

## P5 Decisions

**D-1 — how the per-provider `DataType` is registered** *(rewritten after the critic refuted the original)*

- **chosen:** `.Property(e => e.LockoutEnd).HasAttribute(new DataTypeAttribute(dataType) { Configuration = … })`,
  one per pinned configuration, driven off a static table.
- **rejected:** `FluentMappingBuilder.Entity<TUser>(configuration).Property(…).HasDataType(…)` — **does not
  work.** `FluentMappingBuilder.GetAttributes<T>(MemberInfo)` (`FluentMappingBuilder.cs:84-88`) filters by
  attribute *type* only, with no `Configuration` filter, so `EntityMappingBuilder.cs:800` finds the existing
  unscoped `ColumnAttribute` and `:822` mutates it. Eight registrations would write eight `DataType`s onto
  one unscoped attribute. Corroborated in-repo by `Issue3136Test`
  (`Tests/Linq/Mapping/FluentMappingTests.cs:833-859`), `[ActiveIssue(3136)]`, whose recorded failure is
  *"The configuration-scoped Entity overload is expected to add a second ColumnAttribute; only one is
  returned."*
- **rejected:** a configuration-scoped `ColumnAttribute` via `HasAttribute`. Works, but `EntityDescriptor`
  dedupes by member and the scoped attribute would **replace** the unscoped one wholesale, so anything later
  added to the shared mapping (column name, nullability) would silently not apply on the 8 pinned
  configurations. Maintainer: *"we have DataTypeAttribute to not mess with multi-purpose ColumnAttribute."*
- **why this:** `ColumnDescriptor.cs:125-136` consults `DataTypeAttribute` **only** when the column
  attribute left `DataType` undefined — exactly our case — so the shared `ColumnAttribute` is never touched
  and the two attributes compose instead of competing.
- **failure mode of the choice:** if a pinned configuration name is absent from a provider's runtime
  `ConfigurationList`, that provider silently keeps emitting `DateTimeOffset`; `U-2` is the probe and `TO-1`
  the detector.

**D-2 — which `DataType` per provider**

Each is what that provider's builder already renders for its widest datetime type (citations re-derived
from the branch after the critic caught stale-clone drift — `P11 A-3`):

| Configuration | `DataType` | Renders as | Source |
|---|---|---|---|
| `ProviderName.Access` | `DateTime` | `DATETIME` | `AccessSqlBuilderBase.cs:155` |
| `ProviderName.SqlCe` | `DateTime2` | `DateTime` | `SqlCeSqlBuilder.cs:96` |
| `ProviderName.Sybase` | `DateTime2` | `DateTime` | `SybaseSqlBuilder.cs:115` |
| `ProviderName.SapHana` | `DateTime2` | `Timestamp` | `SapHanaSqlBuilder.cs:128` |
| `ProviderName.Informix` | `DateTime2` | `datetime year to fraction` | `InformixSqlBuilder.cs:136` |
| `ProviderName.DB2LUW` | `DateTime2` | `timestamp` | `DB2SqlBuilderBase.cs:204` |
| `ProviderName.Firebird25` | `DateTime2` | `TimeStamp` | `FirebirdSqlBuilder.cs:151` |
| `ProviderName.Firebird3` | `DateTime2` | `TimeStamp` | `FirebirdSqlBuilder.cs:151` |

- **rejected:** `DateTime2` on Access — `AccessSqlBuilderBase.cs:156` maps it to `timestamp`, not the Jet/ACE
  column type.
- **failure mode:** a misread builder shows up as a DDL error on that leg only — visible, not silent.

**D-3 — F-3 is fixed in the test connection strings, not in product code**

- **chosen:** append `Self Tuning=false;Statement Cache Size=0;` to all 8 managed-Oracle entries in
  `DataProviders.json`.
- **rejected:** changing `Schema`/`KeyedSchema` to drop on a fresh connection — fixes the Identity fixtures
  only, leaves the general Oracle cursor flakiness the maintainer reports across the suite.
- **why this:** the failure is not Identity-specific; per the maintainer it is the reason Oracle legs get CI
  restarts and were never ported to GitHub Actions.
- **failure mode of the choice:** CI stops exercising the driver's default configuration, so a future
  statement-cache interaction becomes invisible to the suite. Recorded in `P10`.

## P6 Edit-points

- **E-1** `Source/LinqToDB.Identity/Mapping/DefaultMappings.cs` — add `_lockoutEndDataTypes` and, in
  `SetupIdentityUser<TKey,TUser>`, a loop adding one configuration-scoped `DataTypeAttribute` per entry.
  Mapped by `TO-1`, `TO-2`, `TO-3`.
- **E-2** `Source/LinqToDB.Identity/LinqToDB.Identity.csproj:31` — `PrivateAssets="contentfiles;build"` on
  the `LinqToDB.csproj` reference. Mapped by `TO-4`.
- **E-3** `DataProviders.json` — append the ODP.NET statement-cache disable to the 8 managed-Oracle
  connection strings. Mapped by `TO-5`.

All five `ConfigureMappings` overrides across `IdentityDataConnection.cs` and `IdentityDataContext.cs` route
through `SetupIdentityUser`, so `E-1` needs no second site.

## P7 Impact map

| Row | Verdict |
|---|---|
| Callers of `SetupIdentityUser` — `IdentityDataConnection.cs:34,76,171`, `IdentityDataContext.cs:33,75` | covered by E-1 — the `<TUser>` overload delegates to `<TKey,TUser>` |
| Mirrored site: `IdentityDataContext` vs `IdentityDataConnection` | covered by E-1 — same method |
| Other `DateTimeOffset` columns | `U-5` — none |
| Providers not in `D-2` | out-of-scope by `SC-2`; `MappingSchema.cs:1228` excludes non-matching scoped attributes |
| `Source/LinqToDB/**` | out-of-scope by `P3` |
| Consumers writing their own Identity mappings (`readme.md:89`) | out-of-scope — they own their column types |
| Other packable projects' `PrivateAssets` | searched — the other 7 referencing `LinqToDB.csproj` already carry `contentfiles;build`; `linq2db.Identity` was the only gap |
| Non-managed Oracle configs (Devart, Native) | `deferred:` — Devart has its own settings and no connection strings in `DataProviders.json`; `E-3` covers only ODP.NET managed |
| `linq2db.baselines` | `deferred:` — Identity fixtures set `BASELINE_DISABLED` (`IdentityTestData.cs:21-25`), so no baseline covers this |

## P8 Test obligations

- **TO-1** (`SC-1`, red→green) — one row per pinned provider, not one for "the legs": Access ×3, SqlCe,
  Sybase, SAP HANA, Informix, DB2 LUW, Firebird 2.5, Firebird 3. **What proves it fired:** the failure
  message changes. A leg still reporting a `DateTimeOffset`-named DDL error means the scoped attribute never
  applied (`D-1` failure mode) — distinct from a leg that now fails later.
- **TO-2** (`SC-2`, control) — DDL-text assertion, since leg pass/fail cannot see this: `CreateTable` then
  read the emitted type for `LockoutEnd` on one **pinned** provider (SqlCe — runnable locally, no container)
  and one **non-pinned** provider with a lane (SQL Server / Firebird 5 — must stay `datetimeoffset` /
  `TIMESTAMP WITH TIME ZONE`). **Mutation that proves it can go red:** register `D-2` against
  `ProviderName.Firebird` instead of the two dialects and confirm the FB5 type changes.
- **TO-3** (`U-6`, round-trip) — `IdentityStoreTests.UserLockout` writes a non-null `LockoutEnd` on
  `[DataSources]`; it is the instrument for the parameter path on Sybase / SAP HANA / Informix / DB2 /
  Firebird, which `U-6` leaves reasoned-but-unprobed. A failure there is caused by `E-1`, not "a new
  observation".
- **TO-4** (`SC-4`) — `verify-analyzer-delivery.ps1` over the packed output reports 0 violations.
- **TO-5** (`SC-5`, red→green, **done**) — Identity suite on Oracle 11: 8/45 failed before `E-3`, 0/45 after.
  Three arms measured; see `G-01`.
- **TO-6** (`SC-3`, characterization) — `git diff --stat` lists no file under `Source/LinqToDB/`.

## P9 Verification gates

- `G-01`: **pass** (F-3, 2026-09-19, worktree `5640-identity-migration`) — same 45 tests, same binaries,
  only the connection string differing: default → 8 failed; `Statement Cache Size=0` alone → 9 failed;
  `Self Tuning=false;Statement Cache Size=0` → 0 failed. Logs under
  `.build/.agents/run-oracle11-identity-{all,size0only,nocache}.log`.
- `G-01`: **pass** for `TO-1` (SqlCe arm) / `TO-2` / `TO-3` (2026-09-19, worktree, after `E-1`) —
  `linq2db.Tests.exe --provider SqlCe --provider Oracle.11.Managed`, filter `Tests.Identity`:
  **88 total, 0 failed**. DDL read from `.build/.agents/run-verify-sqlce-oracle.log`:
  SqlCe (pinned) `[LockoutEnd] DateTime NULL` at `:2250`, previously rejected as `DateTimeOffset`;
  Oracle 11 (non-pinned control) `"LockoutEnd" timestamp with time zone NULL` at `:10628` and
  `DECLARE @LockoutEnd TimeStampTZ -- DateTimeOffset` at `:10851`, both byte-identical to the pre-change
  log. `TO-3`'s `UserLockout` ran green on both.
- `G-01`: **pending** for `TO-1`'s other 7 provider families (no local containers), `TO-4`, `TO-6`.
- `G-05`: **pass for the changed file, blocked for the project** (2026-09-19) —
  `dotnet build Source/LinqToDB.Identity/LinqToDB.Identity.csproj -c Release -f netstandard2.0` returns
  `1 Error(s)`: `MA0215` at `Stores/UserOnlyStore.cs:410`, a file this session did not touch and which CI's
  `Build and pack` compiled clean in Release across every TFM (all 41 nupkgs produced before the job failed
  at the analyzer-delivery step). This is the known local Release-analyzer divergence. The error is in the
  **same project** as `E-1`, so the compilation did process `DefaultMappings.cs` and reported nothing for it
  — the collection expression, the `ValueTuple` array, `DataTypeAttribute` and the `ProviderName` constants
  all resolve on `netstandard2.0`, and Release analyzers found nothing in it. `-f net462` returns the
  identical single error in the same untouched file, so both portable TFMs are covered for `E-1`.
- `G-06`: **pass** — `git diff --stat` is 3 files (`DataProviders.json`,
  `LinqToDB.Identity.csproj`, `DefaultMappings.cs`), all in `P6`; no reformatting.
- `G-08`: n/a — no cross-cutting core change (`SC-3`).
- `G-09`: pending.

## P10 Adjudicated

- **The UTC offset is discarded on the 8 pinned configurations.** Not a new loss — their existing
  `SetValueToSqlConverter(typeof(DateTimeOffset), …)` already truncated to `.DateTime`. Consequence:
  `LockoutEnd` round-trips with offset zero and `UserManager.IsLockedOut` compares against
  `DateTimeOffset.UtcNow`.
- **CI no longer exercises ODP.NET's default statement-cache configuration** (`D-3` failure mode). Accepted
  on the maintainer's instruction; the trade is against a long-standing source of Oracle CI flakiness.
- **The underlying Oracle drop→create→drop behaviour is unfixed for users.** `E-3` is a test-side setting.

## P11 Amendments

- **A-1** — `D-1`'s mechanism replaced. The critic refuted the
  `Entity<TUser>(configuration).Property(…).HasDataType(…)` route with a verified trace
  (`FluentMappingBuilder.cs:84-88` → `EntityMappingBuilder.cs:800,822`); it mutates the unscoped
  `ColumnAttribute` instead of adding a scoped one. Replaced with an explicit scoped attribute; then
  narrowed again from `ColumnAttribute` to `DataTypeAttribute` on the maintainer's instruction, which also
  removes the replace-not-merge coupling the critic raised as a missing decision.
- **A-2** — `SC-2`'s "failable by baseline diff" clause struck. The critic showed it contradicts `P7`:
  Identity fixtures set `BASELINE_DISABLED`. Replaced with the `TO-2` DDL-text instrument.
- **A-3** — `D-2`'s Access citations corrected from `:143/:144` to `:155/:156`. They were read from the
  primary clone on `master`; the branch differs (`agent-rules.md` → a working-tree search is evidence about
  *your checkout*).
- **A-4** — scope widened from F-1 only to F-1/F-2/F-3, adding `E-2` and `E-3`. This voids the (never
  granted) approval of the narrower edit set.

## P12 Critic verdict

**refuted** (`plan-critic`, fable). Objections and dispositions:

| Objection | Disposition |
|---|---|
| `D-1`'s registration route mutates the unscoped `ColumnAttribute` rather than adding a scoped one; `SC-2` would fail silently on 9 providers and `TO-1` would read green on 7 of 8 legs | **accepted** — verified independently against `FluentMappingBuilder.cs:84-88` and `EntityMappingBuilder.cs:800,822`, plus `[ActiveIssue(3136)]`. `A-1` |
| `SC-2`'s failability clause contradicts `P7`; `TO-2` had no instrument; DB2 zOS has no CI lane | **accepted** — `A-2` |
| `U-6` was resolved against the pre-change state; the parameter path on Sybase/HANA/Informix/DB2/Firebird is unprobed | **accepted** — `U-6` downgraded to reasoned-not-probed, `TO-3` added |
| Missing `D-n` for the replace-not-merge coupling of a scoped `ColumnAttribute` | **superseded** — `DataTypeAttribute` does not replace the `ColumnAttribute` at all (`D-1`) |
| `D-2`'s Access citations stale by 12 lines | **accepted** — `A-3` |

The critic also confirmed, by independent search, every provider-side fact in `D-2`, `U-2`, `U-3` and `U-4`,
and that `P7`'s call-site enumeration is complete.
