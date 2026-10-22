# Work plan — `feature/identity-migration` (PR #5640): the three CI failures

- **Tier:** M
- **Status:** implementing
- **Approved:** `A-9` edit set (`E-4`…`E-12`), 2026-10-11, after the critic's `weak` verdict was folded in.
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

- **SC-1** (F-1) — `CreateTable<IdentityUser<TKey>>` emits a valid datetime column type for `LockoutEnd` on Access, SqlCe, Sybase, SAP HANA, Informix, DB2 LUW, Firebird 2.5 and Firebird 3. → TO-1, TO-3
- **SC-2** (F-1) — providers that already render `DataType.DateTimeOffset` emit **exactly** what they emit today: SQL Server, PostgreSQL, Oracle, MySQL, DuckDB, YDB, DB2 zOS, Firebird 4, Firebird 5. Failable by the DDL-text instrument in `TO-2`, **not** by a baseline diff — see `P11 A-2`. → TO-2
- **SC-3** (F-1) — no file under `Source/LinqToDB/` changes. → TO-6
- **SC-4** (F-2) — `verify-analyzer-delivery.ps1` reports 0 violations for `linq2db.Identity`. → TO-4
- **SC-5** (F-3) — the Identity suite passes on Oracle with the driver's statement cache disabled; the ORA-24449 / ORA-00932 / NRE family does not occur. → TO-5

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
| U-8 | EF Core's .NET 10 Identity added `TUserPasskey` additively | resolved-by probe (`gh api` on `dotnet/aspnetcore@release/10.0`, 2026-10-11) — `UserOnlyStore.cs:69-70` the 6-arity derives from a new 7-arity closed with `IdentityUserPasskey<TKey>`; `UserStore.cs:93-94,126` 9→10 likewise; `IdentityUserContext.cs:60,88` 5-arity derives from a new abstract 6-arity; `CreateUserPasskey` is `protected virtual TUserPasskey` (`UserOnlyStore.cs:563`); `IdentityDbContext.cs:77,111` the 8-arity derives from a new abstract 9-arity, which derives from the user-only 6-arity — so EF's 8-arity also left the 5-arity chain. EF's DI (`IdentityEntityFrameworkBuilderExtensions.cs:49-89`): roles path always builds `UserStore`10` from the 9-arity incl. `[8]`; user-only path finds the 6-arity but builds `UserOnlyStore`6`, dropping a custom `TUserPasskey` |
| U-9 | A generic type's base class may differ by TFM without breaking the non-net10 surface | reasoned, unprobed — only net10 gains the new types; on other TFMs the existing declarations compile unchanged under `#else` |
| U-10 | Existing overrides of the passkey members keep compiling once they move to the 7-arity base | reasoned, unprobed — on the closed 6-arity `TUserPasskey = IdentityUserPasskey<TKey>`, so the inherited signatures are identical; `TO-10` compiles an override against the 6-arity |

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

**D-4 — a `TUserPasskey` type parameter, EF Core's shape** *(A-9)*

- **chosen:** on `net10.0` only, add higher-arity types carrying `TUserPasskey : IdentityUserPasskey<TKey>, new()`
  — `UserOnlyStore`7`, `UserStore`10`, `IdentityDataContext`/`IdentityDataConnection` user-only `6` and full `9`
  — and re-base each existing arity onto its new sibling closed with `IdentityUserPasskey<TKey>`, exactly as
  `U-8` measured. The class body moves to the new type under `#if NET10_0_OR_GREATER`; the existing
  declaration keeps it under `#else`. The full 8-arity context re-bases onto the 9-arity (which derives from the
  user-only 6-arity), so on net10 it no longer derives from the user-only 5-arity — EF made the same change.
- **DI (`AddLinqToDBStores`):** on net10 — roles path: find the **9-arity** base, read `TUserPasskey` at `[8]`;
  user-only path: find the **6-arity** base, read `TUserPasskey` at `[5]`. Stock `IdentityUserPasskey<TKey>` →
  today's `UserStore`9` / `UserOnlyStore`6` (resolved store type unchanged for every existing context, incl. a
  full context registered without roles, which today reaches the 5-arity through 8→5); custom →
  `UserStore`10` / `UserOnlyStore`7`. Deliberately not EF's dispatch (`U-8`): EF always builds the 10-arity on
  the roles path, and its user-only path drops a custom passkey type.
- **no stock-passkey mirror:** unlike claims/logins (`IdentityDataContext.cs:186-188`), the 6-arity does not
  also map `IdentityUserPasskey<TKey>` when `TUserPasskey` is custom — no navigation returns passkeys
  (`IdentityNavigations.cs`). Consequence: a hand-built `UserOnlyStore`6` / `UserStore`9` over a custom-passkey
  context queries an unmapped table; the readme (`E-9`) says a custom passkey type needs the 7/10-arity store or DI.
- **invariant for the `#if` arms:** members move strictly *up* the hierarchy on net10, never sideways or down,
  so a consumer compiled against a portable TFM and run on net10 still binds (CLR resolves memberrefs up the
  base chain).
- **rejected:** shipping without it and adding later — `U-8` shows it is additive, but the user chose to ship
  it now (review walk G7).
- **rejected:** a parallel 9-arity that does not share the 8-arity's body — duplicates the role mappings.
- **`PublicAPI`:** new types and the moved passkey members go to `PublicAPI/net10.0/PublicAPI.Unshipped.txt`.
  The root file's entries for members now declared on the net10 base (6-arity store, 5/8-arity contexts) become
  per-TFM drift; left to `/release-publicapi -Action fix-drift` (accepted intra-release lag).
- **failure mode:** a missed `#if` arm compiles on net10 and breaks a portable TFM, or vice versa — `G-05`
  builds `netstandard2.0` + `net10.0` Release.

## P6 Edit-points

- **E-1** `Source/LinqToDB.Identity/Mapping/DefaultMappings.cs` — add `_lockoutEndDataTypes` and, in
  `SetupIdentityUser<TKey,TUser>`, a loop adding one configuration-scoped `DataTypeAttribute` per entry.
  Mapped by `TO-1`, `TO-2`, `TO-3`.
- **E-2** `Source/LinqToDB.Identity/LinqToDB.Identity.csproj:31` — `PrivateAssets="contentfiles;build"` on
  the `LinqToDB.csproj` reference. Mapped by `TO-4`.
- **E-3** `DataProviders.json` — append the ODP.NET statement-cache disable to the 8 managed-Oracle
  connection strings. Mapped by `TO-5`.

- **E-4** `Source/LinqToDB.Identity/Stores/UserOnlyStore.cs` — `UserOnlyStore`7`; 6-arity re-based (D-4).
- **E-5** `Source/LinqToDB.Identity/Stores/UserStore.cs` — `UserStore`10`; 9-arity re-based (D-4).
- **E-6** `Source/LinqToDB.Identity/Context/IdentityDataContext.cs` — 6- and 9-arity contexts; 5/8-arity
  re-based; `UserPasskeys` table accessor on the 6-arity (D-4).
- **E-11** `Source/LinqToDB.Identity/Context/IdentityDataConnection.cs` — the same as `E-6` (mirrored family).
- **E-7** `Source/LinqToDB.Identity/Mapping/DefaultMappings.cs` — `SetupIdentityUserPasskey<TKey, TUserPasskey>`.
- **E-8** `Source/LinqToDB.Identity/IdentityLinqToDBBuilderExtensions.cs` — net10 dispatch on `TUserPasskey`.
- **E-9** `Source/LinqToDB.Identity/PublicAPI/net10.0/PublicAPI.Unshipped.txt` — new surface.
- **E-12** `Source/LinqToDB.Identity/readme.md` — customization section: custom passkey type, and that it
  needs the 7/10-arity store or DI.
- **E-10** `Tests/Linq/Identity/*` — `TO-7`…`TO-10`.

- **E-0** — pre-plan migration surface (`ceb633163`..`47a07a901`, 2026-06-20/21), recorded by A-11 so
  reconcile stops reporting it; listed, not approved design:
  - `Source/LinqToDB.Identity/Extensions.cs`
  - `Source/LinqToDB.Identity/Resources.cs`
  - `Source/LinqToDB.Identity/PublicAPI.Shipped.txt`
  - `Source/LinqToDB.Identity/PublicAPI/net10.0/PublicAPI.Shipped.txt`
  - `Directory.Packages.props`
  - `README.md`
  - `Tests/Linq/Tests.csproj`
  - `linq2db.slnx`
- **E-13** — A-10: Access ODBC binds `DataType.Text` / `NText` as `OdbcType.Text` / `NText`:
  - `Source/LinqToDB/Internal/DataProvider/Access/AccessDataProvider.cs`
  - `Tests/Linq/DataProvider/AccessTests.cs` — core test `LongTextParameter`
- **E-14** — A-10 and review round 1:
  - `Source/LinqToDB.Identity/Stores/RoleStore.cs` — dependent-row delete, YDB support
  - `Source/LinqToDB.Identity/IdentityNavigations.cs` — `Roles()` / `Users()` return types
  - `Source/LinqToDB.Identity/PublicAPI.Unshipped.txt`
  - `Build/licenses/README.md` — bundle-nothing rule
- **E-15** — A-11, NIT001:
  - `linq2db.Testing.slnf` — lists `LinqToDB.Identity.csproj`
- **E-17** — A-13, MIN029:
  - `Tests/Tests.FpuJit/Tests.FpuJit.csproj` — `ProjectReference` to `LinqToDB.Identity.csproj`
  - `Tests/Tests.FpuJit/Program.cs` — `"linq2db.Identity"` in `ExpectedAssemblies`
- **E-16** — A-12, same mechanism as E-1:
  - `Source/LinqToDB.Identity/Mapping/DefaultMappings.cs` — `(ProviderName.SqlServer2005, DataType.DateTime)` row
    in `_lockoutEndDataTypes`

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
| (D-4) users of `IdentityUserPasskey<TKey>` in `Source/LinqToDB.Identity` — searched `Passkey` | `UserOnlyStore.cs:459-609` (E-4), `DefaultMappings.cs:403-445` (E-7), `IdentityDataContext.cs:39,82,183` / `IdentityDataConnection.cs:40,83,184` (E-6); none in `UserStore.cs`, `IdentityNavigations.cs` |
| (D-4) reflection over store/context arities — searched `MakeGenericType`, `typeof(UserOnlyStore<` | `IdentityLinqToDBBuilderExtensions.cs:43-83` only (E-8) |
| (D-4) `PublicAPI` — searched the root `PublicAPI.Unshipped.txt` for the 6/9-arity store and 5/8-arity context members | 69 entries become net10 drift — `deferred:` to `/release-publicapi` (D-4) |
| (D-4) tests naming the stock passkey type — searched `IdentityUserPasskey` under `Tests/` | `IdentityTestData.cs:54`, `IdentityStoreTests.cs:509` — unchanged, they use the stock type |

## P8 Test obligations

- **TO-1** (`SC-1`) — proof: red→green — one row per pinned provider, not one for "the legs": Access ×3, SqlCe,
  Sybase, SAP HANA, Informix, DB2 LUW, Firebird 2.5, Firebird 3. **What proves it fired:** the failure
  message changes. A leg still reporting a `DateTimeOffset`-named DDL error means the scoped attribute never
  applied (`D-1` failure mode) — distinct from a leg that now fails later.
- **TO-2** (`SC-2`) — proof: control — DDL-text assertion, since leg pass/fail cannot see this: `CreateTable` then
  read the emitted type for `LockoutEnd` on one **pinned** provider (SqlCe — runnable locally, no container)
  and one **non-pinned** provider with a lane (SQL Server / Firebird 5 — must stay `datetimeoffset` /
  `TIMESTAMP WITH TIME ZONE`). **Mutation that proves it can go red:** register `D-2` against
  `ProviderName.Firebird` instead of the two dialects and confirm the FB5 type changes.
- **TO-3** (`U-6`, round-trip) — proof: characterization — `IdentityStoreTests.UserLockout` writes a non-null `LockoutEnd` on
  `[DataSources]`; it is the instrument for the parameter path on Sybase / SAP HANA / Informix / DB2 /
  Firebird, which `U-6` leaves reasoned-but-unprobed. A failure there is caused by `E-1`, not "a new
  observation".
- **TO-4** (`SC-4`) — proof: red→green — `verify-analyzer-delivery.ps1` over the packed output reports 0 violations.
- **TO-5** (`SC-5`, **done**) — proof: red→green — Identity suite on Oracle 11: 8/45 failed before `E-3`, 0/45 after.
  Three arms measured; see `G-01`.
- **TO-6** (`SC-3`) — proof: characterization — `git diff --stat` lists no file under `Source/LinqToDB/`.
- **TO-7** (D-4; the 9-arity context does not exist today) — proof: red→green — custom `AppUserPasskey :
  IdentityUserPasskey<string>` (extra member) with a 9-arity connection and `UserStore`10`: add / find / update /
  remove a passkey, and `DeleteAsync` at `Version3` removes it. The extra member is set by a test-side
  `UserStore`10` subclass overriding `CreateUserPasskey` (the store itself writes only `UserId` /
  `CredentialId` / `Data`, `UserOnlyStore.cs:559-580`) and read back through `GetTable<AppUserPasskey>()`.
- **TO-8** (D-4) — proof: red→green — metadata: the custom passkey type maps to `AspNetUserPasskeys` with the stock column shape
  (`CredentialId` length 1024, per-provider scoped attributes) on the 6- and 9-arity contexts.
- **TO-9** (D-4, DI; control for the stock rows) — proof: red→green — custom-passkey context resolves `UserStore`10` (roles) / `UserOnlyStore`7` (user-only);
  every existing DI test keeps asserting today's resolved types (`UserOnlyStore`6` for `AppUserOnlyConnection`);
  **new case** — the full 8-arity `AppIdentityConnection` registered without `AddRoles` resolves
  `UserOnlyStore<AppUser, AppIdentityConnection, string, AppUserClaim, AppUserLogin, AppUserToken>` — the one
  shape whose base chain D-4 changes (8→9→6 instead of 8→5). Runs on net10.0; the `#else` arm is covered by
  CI's net9.0/net8.0 legs.
- **TO-10** (`U-10`) — proof: characterization — a test-side subclass of the 6-arity store overriding `CreateUserPasskey` returning
  `IdentityUserPasskey<string>` compiles and is called.
- Full Identity suite on SQLite.MS + SqlCe stays green (net10.0). Build gate for `E-4`…`E-8`: a local Release
  build of `LinqToDB.Identity.csproj` across all five TFMs, read for **new** diagnostics only (it cannot go
  green locally — the known `MA0215` at `UserOnlyStore.cs:410`, `P9 G-05`); the authoritative gate is CI's
  Release `Build and pack` on the branch head.

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
- `G-01`: **blocked** for `TO-1`'s other 7 provider families (no local containers — CI legs), `TO-4`, `TO-6`.
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
- `G-09`: **blocked** — on implementation of `A-9` and the final diff.
- `G-05` for `A-9` (`E-4`…`E-8`): **blocked** — on CI's Release `Build and pack` on the branch head after push.
  Local all-TFM Release build of `LinqToDB.Identity.csproj` (2026-10-11, `0bcdf28fd`): exit 0, no diagnostics
  (`.build/.agents/pr5640-a9-build-release.log`) — the `MA0215` recorded above no longer reproduces.
- `G-01` for `A-9` (`TO-7`…`TO-10`): **pass** (2026-10-11, `0bcdf28fd`) — full Identity suite, net10.0,
  SQLite.MS + SqlCe: 159/159, the five new tests included. Informix/ClickHouse/YDB gates are CI-only.
- `G-01` for `A-11`: **pass** (2026-10-12, per PR body round 3) — Identity suite 168/168 on SQL Server 2019 (MS) +
  SQLite.MS, net10.0. Release builds of `linq2db.Identity` (all TFMs) and `Tests/Linq` (net10.0) clean.
- `G-01` for `A-12`: **pass locally** (2026-10-12): `UserLockout` red→green against the local instance with the
  `SqlServer.2005` dialect; Identity suite 80/80 on that configuration. **CI: blocked.** GitHub `tests [all]` run
  [38236420765](https://github.com/linq2db/linq2db/actions/runs/38236420765) on `7faa94562` is green on all 22
  legs, but no GitHub leg runs SQL Server 2005. The Azure `test-all` on `7faa94562`
  (24189) was **canceled** on 2026-10-12, and none has run on `7faa94562` / `f90bec55c` since. The CI arm of `E-16`
  is therefore unverified.
- `G-01` for `A-13`: **pass** (2026-10-22, worktree `5640-identity-migration`, net10.0): Identity suite +
  `AccessTests.LongTextParameter` / `LongAnsiTextParameter` on SQLite.MS, SQLite.Classic, SqlCe, Access.Ace.Odbc,
  Access.Ace.OleDb, Firebird.5, Sybase.Managed, SapHana.Native, DB2 — **731/731**. SUG006 red→green measured on
  Access.Ace.Odbc. FPU JIT harness (x86 net462): `linq2db.Identity ok=606 faults=0`.
- `G-05` for `A-13`: **pass** — Release `linq2db.Identity` (all TFMs) and `Tests/Linq` (net10.0) build clean.

## P10 Adjudicated

- **The UTC offset is discarded on the 8 pinned configurations.** Not a new loss — their existing
  `SetValueToSqlConverter(typeof(DateTimeOffset), …)` already truncated to `.DateTime`. Consequence:
  `LockoutEnd` round-trips with offset zero and `UserManager.IsLockedOut` compares against
  `DateTimeOffset.UtcNow`.
- **CI no longer exercises ODP.NET's default statement-cache configuration** (`D-3` failure mode). Accepted
  on the maintainer's instruction; the trade is against a long-standing source of Oracle CI flakiness.
- **The underlying Oracle drop→create→drop behaviour is unfixed for users.** `E-3` is a test-side setting.
- **`DeleteAsync` removes dependents in separate statements, outside any transaction.** A cancellation or error
  mid-sequence can strand dependents. Maintainer (review round 2, MIN016): callers use an explicit transaction - the
  readme's "not atomic" section documents the pattern. Do not re-raise.

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
- **A-5** — **`U-6` realized, and wider than it was written.** The critic's objection was that the
  *parameter* path was unprobed; CI's run on `77a981e38` confirmed it on Sybase and SAP HANA, whose drivers
  reject a `DateTimeOffset` value outright. Measuring locally then showed the defect is not confined to those
  two: **every** pinned configuration round-trips the value through the *machine's local offset* — Firebird 3
  wrote `13:52:49Z` and read back `13:52:49+02:00`. `P10`'s adjudication ("round-trips with offset zero") was
  therefore wrong, and wrong in a way CI structurally cannot see, because CI runs in UTC. `E-1` now pairs each
  `DataTypeAttribute` with a configuration-scoped `ValueConverterAttribute` storing UTC. **The general lesson
  for this plan's successors: a success criterion phrased over DDL text cannot fail on a value defect, and a
  UTC-only CI cannot fail on an offset defect — `SC-1` and `TO-2` were both blind to this by construction.**
- **A-6** — **new edit-point: dropping a per-provider primary key.** Access, Informix and Firebird 2.5 cannot
  index the keys the EF-compatible schema declares (1024-byte `CredentialId` on all three; the three-column
  `AspNetUserTokens` key on FB 2.5). Those tables now emit without the constraint. Two findings worth carrying
  forward: a configuration-scoped `ColumnAttribute` that merely **omits** `IsPrimaryKey` does *not* drop the
  key — fluent `.IsPrimaryKey()` registers a separate `PrimaryKeyAttribute` that `ColumnDescriptor.cs:112-123`
  consults whenever the column attribute leaves the flag unset, so it must be `IsPrimaryKey = false`. And
  `Context.UpdateAsync(entity)` on a keyless entity is **not** safe: `GetKeys(true)` returns every field
  (`SqlTable.cs:374`), leaving nothing to SET, so it throws — or silently no-ops under `IgnoreEmptyUpdate`.
  `Context.DeleteAsync(entity)` degrades safely by the same mechanism (over-specified `WHERE`), which is why
  only the passkey update needed reworking and the token table needed no store change at all.
- **A-7** — **anti-goal "ClickHouse and YDB" discharged as gates, plus Informix passkeys.** Per the
  maintainer: `[ActiveIssue]`, no issues filed. Gated per test, not per provider — both engines host the
  schema and pass the read-only and claim tests. Verified against all three ClickHouse drivers and YDB: 85
  cases held, none over-firing.
- **A-8** — **`SC-2` narrowed: MySQL leaves its set and joins `D-2`'s pins.** `SC-2` checked that MySQL
  *renders* `DateTimeOffset`, not that the rendering holds the values Identity writes: the CREATE TABLE arm is
  `TIMESTAMP` (`MySqlSqlBuilder.cs:173`), which ends 2038-01-19, so a permanent lockout fails with
  `datetime field overflow`. Pinned `(ProviderName.MySql, DataType.DateTime2)` → `DATETIME`, with the UTC
  converter. Surfaced by review round 1 (`gaps.md`, MIN005); `UserLockout` now writes `MaxValue.AddDays(-1)`
  — `MaxValue` itself trips a separate SQLite reader defect on non-UTC machines (`GetDateTime` → local time).
- **A-9** — **`TUserPasskey` type parameter added (`D-4`, `E-4`…`E-10`, `TO-7`…`TO-10`).** Review walk G7
  raised "no `TUserPasskey`, breaking to add after release". `U-8` refuted the premise (EF added it
  additively), and the user then chose to add it before release anyway. Widens `P6` by seven edit-points and the
  public type structure on net10; any prior approval of the edit set is void and re-earned on this amendment.
- **A-10** — **review round 2 (`gaps.md`, round 2), commits `10eaf908e`..`c799473d4`.** Widens scope well past the CI
  failures, each item user-approved in the walk:
  - **`SC-3` broken on purpose:** `Source/LinqToDB/Internal/DataProvider/Access/AccessDataProvider.cs` binds ODBC
    `Text`/`NText` as long text (an over-255-character `LongText` value failed with HY104). Core-layer test
    `AccessTests.LongTextParameter`, red→green on `Access.Ace.Odbc`.
  - **`P3` anti-goal "ClickHouse and YDB" discharged:** the stores now run on YDB (find-then-insert role add,
    delete decided by row presence when `SqlProviderFlags.IsAffectedRowsCountSupported` is false, two-step
    `RemoveFromRoleAsync`); ClickHouse keeps only the update-refresh and identity-key gates, each pinning its expected
    failure. `A-7`'s gates superseded.
  - **`D-2` / `SC-2` extended:** YDB `LockoutEnd` → `Timestamp64`; the UTC converter stores whole seconds so
    `DateTimeOffset.MaxValue` fits every pinned type. Reverses `A-8`'s narrowing of `UserLockout`'s input.
  - **`A-6` premise corrected:** Informix `BYTE` cannot be compared, so the passkey id is hex text in `LVarChar(2048)`;
    Informix name/email `LVarChar(1024)`; SQL CE passkey `Data` `NText`; Firebird `DbType` strings carry `UNICODE_FSS`.
  - **Public surface:** four duplicate `ConfigureMappings` overrides removed; `IdentityNavigations.Roles()` / `Users()`
    return `IdentityRole<TKey>` / `IdentityUser<TKey>` through internal link-hop associations, with stock role/user
    mirror mappings in the role-aware contexts.
  - Verified locally: 1007-test batch over 11 providers (YDB, ClickHouse ×3, Informix, Access ACE ×2, MySQL 8 ×2,
    SqlCe, SQLite.MS) green apart from two load-induced Octonica timeouts that pass alone; Release build of
    `LinqToDB.Identity` clean on all five TFMs. SQL Server, PostgreSQL, Oracle, DB2, Sybase, SAP HANA and Firebird
    are CI-only.
- **A-11** — **review round 3 (igor-tkachev's agentic review on `96bebf54e`), commits `366b57a23`..`e3f85ade0`.** Each
  item was dispositioned by the maintainer:
  - MIN004: the readme's migration section no longer promises that standalone-created databases work unchanged. The
    standalone package mapped no table names, so `CreateTable` produced CLR-named tables. The section gives the
    rename / `ConfigureMappings` options (`E-12`).
  - MIN005: `PasswordHash` / `SecurityStamp` / `PhoneNumber` widened from 100 / 40 / 20 to 256 (`E-1` file). String
    keys stay 36 because composite-key index limits apply on several providers; the readme documents the width and
    the override. `UserProfileFields` now writes values over the old widths: red on SQL Server 2019 with a
    truncation error, green after (`E-10`).
  - NIT001: `E-15`. Release `IDE0200` / `IDE0340` in two Identity test lines (`E-10`).
  - Records `E-0` and `E-14`. These files were changed before the plan or in rounds 1–2 without a `P6` row, and
    `-Reconcile` reported them as unplanned.
  - conventions: `testing.md` → *Test layout*, *A narrowed provider set is a claim*, *Gating an assertion failure*.
    Swept `git diff cbfc89b15 e3f85ade0 -- Tests/` by hand, because no worktree exists for `test-diff-sweep.ps1`:
    3 files, 0 added one-line chains, 0 added or changed narrowed provider sets, 0 gates.
- **A-12** — **SQL Server 2005 `LockoutEnd`, `7faa94562` (+ readme `f90bec55c`).** Azure `test-all` 24180 on
  `e3f85ade0` was red only on SQL Server 2005 `UserLockout`: `DateTimeOffset.MaxValue` overflowed `DATETIME`
  (*SqlDateTime overflow*). 2005 has no `datetimeoffset`, so the column was already `DATETIME`; the value was not
  converted. `E-16` adds the row, which gives 2005 the whole-second UTC converter of `D-2` / `A-10`. The readme's
  *Provider support* section lists the whole-second-UTC providers. Its migration section notes that a value an
  earlier version stored in server-local time reads back shifted until rewritten. Extends `SC-1`'s pinned set by
  one configuration. `SC-3` is unaffected.
  - re-derives: `D-2` (pinned set), `P10` first bullet (offset discarded on pinned configurations — now 10, still
    the adjudicated trade).
  - The affected part of the approval (`E-16`) is void until re-confirmed. **Re-approved 2026-10-22.**
- **A-13** — **review round 4 (`gaps.md`, round 4), on `8c381eb99` (master merge) .. `afb9ba0e9`.** Each item was
  dispositioned by the maintainer in the walk:
  - MIN025 (`E-4`): the passkey members throw `InvalidOperationException` below `IdentitySchemaVersions.Version3`
    (new `Resources.PasskeysRequireVersion3`), matching EF Core, which drops the entity from its model there.
    Previously a store without options, or with the `StoreOptions` default, accepted passkeys that `DeleteAsync` then
    left behind. `UserDeleteRemovesPasskeys(schemaV3: false)` asserts the refusal; the passkey tests pass `Version3`.
  - MIN026 (`E-0`): the package-validation comment says validation stays off until the next major resets
    `BaselineVersion`, as for `Remote.HttpClient.Server` / `Analyzers.CodeFixes` / `CLI`.
  - MIN027 **withdrawn on measurement**: an unsized `NVarChar` is `NVarChar(255)` in `CREATE TABLE` on SqlCe, Sybase,
    SAP HANA and DB2, not the builder's `Length is null` width, so `_claimValueTypes`' comment holds and 2000 widens.
  - MIN028, SUG005, OOS2 (`E-12`): readme migration example compiles; *Provider support* states the Access 255 and
    `ClaimValue` 2000 caps and Firebird's #5915 reason; the migration note lists Firebird 4+ / YDB `LockoutEnd` types.
    OOS2 measured: an EF-style `TIMESTAMP WITH TIME ZONE` `LockoutEnd` on Firebird 5 round-trips
    (raw `2030-01-02 03:04:05.0000 Etc/UTC`, UTC session, UTC+1 client). Non-UTC sessions and YDB unchecked.
  - SUG006 (`E-13`): `AccessTests.LongAnsiTextParameter` — HY104 on `Access.Ace.Odbc` with the `DataType.Text` arm
    removed, green with it.
  - NIT009, NIT010, NIT015, NIT016: comment / XML-doc fixes. NIT014: permanent-lockout carve-out narrowed to SQLite.MS,
    citing #6031 (SQLite.Classic passes with `MaxValue`).
  - NIT011–NIT013 (`E-10`): every rule-1 chain the sweep found rewritten (one call per line, query syntax for the
    navigation `SelectMany`s).
  - MIN029 (`E-17`): `linq2db.Identity` added to master's x86 FPU JIT sweep after merging `origin/master`.
  - MIN030 rejected (forwarding arities; the stock-type mirror is covered by `NavigationAssociations`). OOS1
    (core Access release note) left to `/release-notes`.
  - conventions: `testing.md` → *Test layout*, *A narrowed provider set is a claim*. `test-diff-sweep.ps1` over
    `origin/master...` + working tree: before 148 chains / 18 narrowed sets; after 37 chains (34 constructor /
    initializer false positives, 3 call arguments) / 18 narrowed sets (all `[DataSources(false)]` or with a reason).

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

**A-9 delta — weak** (`plan-critic`, fable, 2026-10-11). Searched: `Passkey` worktree-wide; every
`IdentityData*<` / `*Store<` / `AddLinqToDBStores` site; the DI index readers; `is/as` casts on store/context
types in `Tests/`; the PublicAPI analyzer wiring (`RunApiAnalyzersDuringBuild` off on master-targeting PRs, so
the drift deferral is safe); `Identity.Stores` package versions per TFM. Confirmed `U-10`, the mapping-schema
cache move, and that the source-level enumeration is complete.

| Objection | Disposition |
|---|---|
| `TO-9` cannot see the one changed DI shape (full context, no roles: 8→5 becomes 8→9→6); "highest-arity base" is ambiguous and `[5]` on the 9-arity is `TUserLogin` | **accepted** — `D-4` DI line made exact (9-arity `[8]`, 6-arity `[5]`); `TO-9` new case |
| `TO-7`'s extra-member round-trip cannot fail — the store never writes it | **accepted** — test-side `CreateUserPasskey` override, read via `GetTable` |
| "EF made the same change" for 8→9→6 unmeasured | **accepted, measured** — `IdentityDbContext.cs:77,111` (`U-8`); EF's DI also measured and found to differ, recorded in `D-4` |
| No build gate that can go green for a five-TFM `#if` split | **accepted** — all-TFM local Release for new diagnostics, CI `Build and pack` as the gate (`P8`, `P9`) |
| Stock-passkey mirror undecided | **accepted** — decided "no mirror" in `D-4`, readme line in `E-9` |
