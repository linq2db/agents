# Work plan: feature-fix-debug-parameter-type-names — Name every debug-SQL parameter type on SQLite, ClickHouse and DuckDB

**Tier:** L  ·  **Status:** approved  ·  **Approved-at:** 2026-10-29 (user, after critic round 2 `weak`, both objections applied)  ·  **Branch:** feature/fix-debug-parameter-type-names
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

## P1 Problem

The trace / baseline `DECLARE` block prints an empty type for most parameters on SQLite, DuckDB and ClickHouse: `DECLARE @NonReadonlyDateTime  -- DateTime` (SQLite.MS, `ParameterTests.Issue1189Test`), `DECLARE @id  -- Int32`, `DECLARE $p  -- Int32` (DuckDB), `DECLARE @p  -- Int64` (ClickHouse, `DataExtensionsTests.TestDataParameterMapping3`). Cause: `BasicSqlBuilder.GetProviderTypeName` (`Source/LinqToDB/Internal/SqlProvider/BasicSqlBuilder.cs:4944`) names only `AnsiString`/`AnsiStringFixedLength`/`String`/`StringFixedLength`/`Decimal`/`Binary` and returns `null` otherwise; `PrintParameterType` (`BasicSqlBuilder.cs:4960`) then appends nothing before ` -- <DbType>`. Twelve provider builders override `GetProviderTypeName` with the driver's type enum; `SQLiteSqlBuilder`, `ClickHouseSqlBuilder` and `DuckDBSqlBuilder` do not. Measured on `linq2db.baselines` `origin/master` with `git grep -l -E "^DECLARE \S+  -- "`: SQLite.MS 1651 files, SQLite.Classic 1609, SQLite.Classic.MPU 1603, SQLite.Classic.MPM 1603, DuckDB 1530, SQLite.MS.EF8/9/10/31 19–20 each, Northwind.SQLite[.MS] 12 each, ClickHouse.Octonica/Driver/MySql 1 each; no other provider has a hit.

## P2 Success criteria

- SC-1 SQLite.MS prints the driver's bound storage class (`SqliteParameter.SqliteType`) for every parameter the base leaves unnamed: `Int32` value `1` → `Integer -- Int32`; `DateTime` (converted to string by `SQLiteDataProvider.SetParameter`, `SQLiteDataProvider.cs:289-294`) → `Text -- DateTime`; `DataType.Guid` (default branch converts to `byte[]`, `:275-283`) → `Blob -- Guid`; `Guid` under a text `DataType` (`:262-271` keeps a string value) → `Text -- Guid`; `Boolean` → `Integer -- Boolean`; `Double` → `Real -- Double`; `Object` + `1` → `Integer -- Object`; a null `Int32` → `Integer -- Int32` (D-2 null fallback).  → TO-1
- SC-2 SQLite.Classic prints the storage class System.Data.SQLite binds (D-2): `Int32` → `Integer -- Int32`, `Boolean` → `Integer -- Boolean`, `Guid` → `Blob -- Guid`, `Double` → `Real -- Double`, `Object` + `1` → `Integer -- Object` (the binder re-derives `Object` from the value).  → TO-1
- SC-3 DuckDB prints the D-4 name for the parameter's `DbType`: `Int32` → `INTEGER -- Int32`, `Boolean` → `BOOLEAN -- Boolean`, `VarNumeric` (BigInteger) → `BIGNUM -- VarNumeric`.  → TO-1, TO-3
- SC-4 ClickHouse prints the driver's parameter type (D-3): an `Int64` parameter prints `DECLARE @p Int64` on Octonica and MySqlConnector for both `1L` and `null`, and on ClickHouse.Driver `Int64` for `1L` and `Nullable(Nothing) -- Int64` for `null` (what that driver sends).  → TO-4
- SC-5 String, decimal and binary parameters keep their current base names on SQLite.MS, SQLite.Classic and DuckDB (`NVarChar(3) -- String`, `Decimal(…)`, `Binary(3)`), and SQLite.Classic's converted `DateTime` keeps `VarChar(23) -- AnsiString`.  → TO-2
- SC-6 Printing never throws: a driver getter that throws (SQLite.MS for a CLR type its binder does not map) falls back to today's empty type.  → TO-5
- SC-7 The real trace path (a LINQ query executed on the provider, direct and `.LinqService`) shows the new name: `DECLARE @id Integer -- Int32` on SQLite.*, `DECLARE $id INTEGER -- Int32` on DuckDB.  → TO-3

## P3 Constraints & anti-goals (M/L)

- Debug / trace output only. No change to what is bound or sent: no `SetParameter` / `SetParameterType` edit, no parameter property written by the new code (getters only).
- No public API change outside `LinqToDB.Internal.*`; the new adapter members are `internal`.
- Other providers' output unchanged (their builders already override `GetProviderTypeName`).
- Base names for string / decimal / binary kept on all three providers (user choice "a", 2026-10-29): the new name fills only where `base.GetProviderTypeName` returns `null`.
- Expected baseline delta: every `DECLARE` line with an empty type in the P1 census gains a type name, except DuckDB's 34 `-- Object` lines (all `DuckDBInterval` values from `DuckDBTypeTests.TestInterval`, critic census), which stay empty because `DbType.Object` names no type (D-4). No `DECLARE` line is added or removed, no SQL text changes. The three `TestDataParameterMapping3` lines (one per ClickHouse driver, null value) become `Nullable(Nothing) -- Int64` on ClickHouse.Driver and `Int64` on Octonica and MySqlConnector.
- A parameter with an explicit `Size` / `Precision` now prints a suffix on the new name (`BasicSqlBuilder.cs:4973-4984`), e.g. `Integer(10) -- Int32` — the base behaviour every other provider's override already has (P10).

## P4 Unknowns (M/L)

- U-1 What does `SqliteParameter.SqliteType` return when linq2db never sets it? — resolved-by probe (decompiled Microsoft.Data.Sqlite.Core 10.0.12 `SqliteParameter.cs:42-46`: `_sqliteType ?? SqliteValueBinder.GetSqliteType(_value)`; `DbType` is a plain auto-property at `:35` and does not touch `_sqliteType`; `git grep SqliteType -- Source` has no hit, so linq2db never sets it). measured.
- U-2 What does `SqliteValueBinder.GetSqliteType` do for null, `DBNull` and an unmapped CLR type? — resolved-by probe (decompiled `SqliteValueBinder.cs:314-326`: `null` → `Text`; `DBNull` is in `_sqliteTypeMapping` → `Text` (`:47-48`); an unmapped type throws `InvalidOperationException`). measured. Consequence: D-2 null fallback, D-5 catch.
- U-3 How does System.Data.SQLite bind by `DbType`? — resolved-by probe (decompiled System.Data.SQLite 2.0.4 `SQLiteStatement.BindParameter`, `SdsStatement.cs:316-374`: Date/DateTime/Time → `Bind_DateTime` (text under the default ISO8601 `DateTimeFormat`); Boolean/SByte/Int16/Int32/Int64/Byte/UInt16/UInt32/UInt64 → integer binds; Currency/Double/Single → `Bind_Double`; Binary → blob; Guid → blob when `_binaryGuid` (default true) else text; Decimal → text; default → text; `BindAllAsText` / `BindDecimalAsText` connection flags override, `:298-315`; **and before the switch a non-null value with `DbType.Object` is re-derived from its CLR type**, `:277-280`, via `SQLiteConvert.TypeToDbType`, `SdsConvert.cs:826-842` + table `:73-94`: Boolean → Boolean, Char/SByte → SByte, Byte, Int16, UInt16, Int32, UInt32, Int64, UInt64, Single, Double, Decimal, DateTime → same-named `DbType`, String → String, `byte[]` → Binary, `Guid` → Guid, any other object → String, DBNull → Object). measured (critic found the `Object` arm; re-read by the author).
- U-4 Does ClickHouse.Driver use `DbType`? — resolved-by probe (decompiled ClickHouse.Driver 1.4.0 `ParameterTypeResolution.ResolveTypeName`, `DriverTypeResolution.cs:8-42`: `ClickHouseType` → SQL type hint → resolver → value type; `DbType` never read. 0.9.0 (`DriverParameter090.cs:37-53`) has the same `QueryForm` = `{name:type}` with `ClickHouseType ?? value-derived`; both versions expose public `ClickHouseType` and `QueryForm`). measured. linq2db never sets `ClickHouseType` (`git grep ClickHouseType -- Source/LinqToDB/Internal/DataProvider/ClickHouse` no hit). measured.
- U-5 Does Octonica derive its type from `DbType`? — resolved-by probe (decompiled Octonica.ClickHouseClient 4.1.6 `ClickHouseParameter.cs:108-142`: `DbType` setter writes `ClickHouseDbType` → `_forcedType`; getter `_forcedType ?? GetTypeFromValue().DbType`). measured.
- U-6 Does DuckDB.NET bind by `DbType`? — resolved-by probe (decompiled DuckDB.NET.Data 1.5.5 `PreparedStatement.BindParameter`, `DuckDBPrepared.cs:125-138`: binds to the prepared statement's own logical parameter type, using `DbType` only as a conversion hint; `DuckDBParameter` exposes no provider type property, `DuckDBParameter.cs`). measured. Consequence: DuckDB has no driver-reported type to print → D-4.
- U-7 Are the parameters printed for baselines provider parameters (so `TryGetProviderParameter` succeeds) on both direct and remote cases? — resolved-by scout (baselines come only from `DataConnection.WriteTraceLine` `BeforeExecute`, `Tests/Base/TestBase.cs:69-74`; `TraceInfo.SqlText` prints `Command.Parameters`, `Source/LinqToDB/Data/TraceInfo.cs:144-145`; a `.LinqService` case's trace is the server-side `DataConnection`'s, per `testing.md` → *Asserting on a parameter's declared type*). Both sides print the same provider parameters, so the direct/remote comparison (`Tests/Base/BaselinesWriter.cs:62-79`) sees identical text.
- U-8 Is anything inside `PrintParameters` guarded against an exception? — resolved-by scout (`TraceInfo.cs:144-145` calls `PrintParameters` unguarded; `BasicSqlBuilder.PrintParameters` `:5005-5030` has no try). A throwing getter therefore aborts the trace → D-5.
- U-10 Which `DbType` does a DuckDB parameter carry after `SetParameter`? — resolved-by probe (`DuckDBDataProvider.SetParameter` sets `Value` first and then `SetParameterType` — "must be called after value set!", `Source/LinqToDB/Internal/DataProvider/DuckDB/DuckDBDataProvider.cs:159-163` — so linq2db's mapped `DbType` wins over the value-derived one `DuckDBParameter.Value`'s setter writes, `DuckDBParameter.cs:30-37`; `:176` maps `DataType.VarNumeric → DbType.Decimal`. Only `DataType`s `SetParameterType` does not map (Interval, Int128, BitArray, Json, Undefined) keep the value-derived `DbType`, `Object` for an unmapped CLR type. Critic census on baselines: DuckDB `-- Object` 34 (all `DuckDBInterval`), `-- VarNumeric` 42 (all `DuckDBTypeTests.TestHugeInt` / `TestUHugeInt`: a HUGEINT column with values rendered `'…'::BIGNUM`, `DataType` outside the switch so `DbType` is value-derived), NULL rows keep linq2db's `DbType`, e.g. 1504 NULL `Int32`). measured by the critic; the `:159-163` order re-read by the author.
- U-9 Can a test create each driver's parameter without a database? — resolved-by probe (decompiled public parameterless ctors: `SqliteParameter()` `SqliteParameter.cs:175`, Octonica `ClickHouseParameter()` `OctonicaParameter.cs:396`, `ClickHouseDbParameter` (implicit), `DuckDBParameter()` `DuckDBParameter.cs:55`; MySqlConnector / System.Data.SQLite parameters are standard ADO.NET types; all six packages are referenced by `Tests/linq2db.Providers.props`, Octonica and DuckDB only for `!= net462`, `:47-53`). measured by decompile; the test project compile is the confirmation.

## P5 Decisions (M/L; rejected alternatives mandatory at L)

### D-1 — Fill only where the base returns `null`

- **chosen:** each new override is `base.GetProviderTypeName(...) ?? <provider name>`.
- **rejected:** provider name for every parameter (the MySQL / Ydb / SqlCe shape) — the user chose to keep the base string / decimal / binary names; it would also change ~all SQLite string `DECLARE` lines for no gain.
- **why this:** user decision "a" (2026-10-29); smallest baseline delta that removes every empty type.
- **failure mode of the choice:** one `DECLARE` block mixes naming styles (`VarChar(23) -- AnsiString` beside `Integer -- Int32`); a string parameter's base name (`NVarChar`) can disagree with what the driver binds (`Text`).

### D-2 — SQLite: MS from the driver, Classic from a `DbType` map mirroring System.Data.SQLite's binder

- **chosen:** MS — `SqliteParameter.SqliteType.ToString()` (`Integer` / `Real` / `Text` / `Blob`) via an adapter getter, except when `Value` is `null` / `DBNull`, where the `DbType` map below is used (the driver reports `Text` for every null, U-2, though it binds SQL NULL and sends no type). Classic — map per U-3, applied to the binder's *effective* `DbType`: when `DbType` is `Object` and the value is non-null, first re-derive it from the value's CLR type as `SQLiteConvert.TypeToDbType` does (U-3). Then: Boolean, SByte, Int16, Int32, Int64, Byte, UInt16, UInt32, UInt64 → `Integer`; Currency, Double, Single → `Real`; Binary, Guid → `Blob`; every other `DbType` (Date, DateTime, DateTime2, DateTimeOffset, Time, Decimal, String, Object with a null value, …) → `Text` (the binder's date and default branches). Same `Integer`/`Real`/`Text`/`Blob` casing on both drivers. The MS null fallback uses the same map, with no `Object` re-derivation (there is no value).
- **rejected:** the `DbType` map for MS too — the MS binder ignores `DbType` (U-1), so the map can disagree with what is bound; the user asked for the driver type. Upper-case `INTEGER` (DDL casing) — `SqliteType` member names are what MS reports, and one casing across both drivers keeps the files comparable.
- **why this:** prints what each driver binds, from the driver where it reports it.
- **failure mode of the choice:** Classic output is a prediction of the binder, wrong under non-default connection flags (`BinaryGUID=False` → text Guid; `DateTimeFormat=Ticks`/`UnixEpoch`/`JulianDay`; `BindAllAsText`). MS null parameters print the `DbType` guess, not the driver's (`Text`).

### D-3 — ClickHouse: per driver

- **chosen:** Octonica — `ClickHouseParameter.ClickHouseDbType.ToString()`; MySqlConnector — `MySqlProviderAdapter.GetDbType(p).ToString()` (the adapter ClickHouse already wraps, `ClickHouseProviderAdapter.cs:189`); ClickHouse.Driver — `ClickHouseType` when set, otherwise the type inside `QueryForm` (`{name:type}` → `type`).
- **rejected:** one `DbType` → ClickHouse-name map for all three — ClickHouse.Driver ignores `DbType` (U-4), so a map would print a type the driver does not send (`Int64` where it sends `Nullable(Nothing)` for a null value). Reading the internal `ParameterTypeResolution` — not public.
- **why this:** matches the user's choice of the driver type, and each driver exposes one publicly.
- **null values:** printed as each driver reports them, with no `DbType` fallback. Octonica and MySqlConnector keep the type forced from `DbType` (U-5; MySqlConnector per its baselines' `DECLARE @p Int64` shape), so a null prints `Int64`. ClickHouse.Driver sends a null as `{p:Nullable(Nothing)}` (`DriverTypeResolution.cs:36-41`, `DriverTypeConverter.cs:188-191`), and that typed placeholder is what the server sees. This differs from D-2 on purpose: Microsoft.Data.Sqlite binds a null as SQL NULL with no type, so its `Text` describes nothing that is sent, while ClickHouse.Driver's `Nullable(Nothing)` is the declared type of the value on the wire.
- **failure mode of the choice:** `QueryForm` omits the connection-level `IParameterTypeResolver` and the SQL type hint the driver uses at execution, so the printed type can differ from the sent one when either is configured; the three drivers print different names for the same null `Int64` (`Int64` vs `Nullable(Nothing)`).

### D-4 — DuckDB: `DbType` → DuckDB type-name map

- **chosen:** map to the names `DuckDBSqlBuilder.BuildDataTypeFromDataType` uses (`Source/LinqToDB/Internal/DataProvider/DuckDB/DuckDBSqlBuilder.cs:62-123`): Boolean → `BOOLEAN`, SByte → `TINYINT`, Byte → `UTINYINT`, Int16 → `SMALLINT`, UInt16 → `USMALLINT`, Int32 → `INTEGER`, UInt32 → `UINTEGER`, Int64 → `BIGINT`, UInt64 → `UBIGINT`, Single → `FLOAT`, Double → `DOUBLE`, Currency → `DECIMAL`, VarNumeric → `BIGNUM` (`DuckDBSqlBuilder.cs:120`, and the same name the literal of those values renders, `'…'::BIGNUM`, U-10), Date → `DATE`, Time → `TIME`, DateTime / DateTime2 → `TIMESTAMP`, DateTimeOffset → `TIMESTAMPTZ`, Guid → `UUID`; `Object` and any other `DbType` → `null` (unchanged — `Object` is the value-derived fallback for an unmapped CLR type, U-10, and names no type).
- **rejected:** leaving DuckDB out — 1530 baseline files carry the same gap, and the user asked to include ClickHouse for 3 files; scope to be confirmed at approval. A driver read — DuckDB.NET has no provider type (U-6).
- **why this:** the only available source; names match the provider's own DDL.
- **failure mode of the choice:** the name is a translation of `DbType`, not what DuckDB binds (it binds to the statement's inferred type), so it can mislead where the two differ (e.g. an `INTEGER` parameter compared with a `BIGINT` column); the 34 interval rows stay unnamed.

### D-5 — A throwing driver getter falls back, never propagates

- **chosen:** wrap each driver read in `try { … } catch (Exception) { return null; }` inside the override, falling through to today's empty type.
- **rejected:** let it throw — `PrintParameters` is unguarded (U-8), so a debug-only read would abort the `BeforeExecute` trace and replace the driver's own execution error with one raised while logging.
- **why this:** diagnostic output must not change control flow.
- **failure mode of the choice:** a broken getter (e.g. a renamed driver property) fails silently as an empty type; mitigated by TO-1/TO-4 asserting a name per driver.

### D-6 — Getters are compiled once in the adapters

- **chosen:** `internal` delegate properties built with `Expression` + `CompileExpression()` when the adapter is created: `SQLiteProviderAdapter.GetSqliteType` (`Func<DbParameter, object>`, null for System.Data.SQLite), `ClickHouseProviderAdapter.GetParameterTypeName` (`Func<DbParameter, string?>`, set for all three drivers, assigned through a private `init`). The builders call `provider.TryGetProviderParameter(...)` then the delegate, as `MySqlSqlBuilder.GetProviderTypeName` does (`MySqlSqlBuilder.cs:455-465`).
- **rejected:** reflection per call — slower on every traced command; TypeMapper `[Wrapper]` classes for the parameter types and their enums — more surface for a read-only getter that only needs `ToString()`.
- **why this:** follows the existing `GetDbType` adapter pattern (MySQL `MySqlProviderAdapter.cs:95`, Ydb `YdbProviderAdapter.cs:210`) without enum wrappers.
- **failure mode of the choice:** a property missing in some driver version throws while building the adapter; mitigated by reading `GetProperty(...)` and leaving the delegate null when absent (all versions in `Directory.Packages.props` have the properties, U-1/U-4/U-5).

## P6 Edit-points

- E-1 `Source/LinqToDB/Internal/DataProvider/SQLite/SQLiteProviderAdapter.cs:SQLiteProviderAdapter` — add `internal Func<DbParameter, object>? GetSqliteType`, built for Microsoft.Data.Sqlite only.
- E-2 `Source/LinqToDB/Internal/DataProvider/SQLite/SQLiteSqlBuilder.cs:GetProviderTypeName` — new override: base, then MS getter (non-null value) or the D-2 `DbType` map, under D-5.
- E-3 `Source/LinqToDB/Internal/DataProvider/ClickHouse/ClickHouseProviderAdapter.cs:ClickHouseProviderAdapter` — add `internal Func<DbParameter, string?>? GetParameterTypeName`, set in `CreateOctonicaAdapter`, `CreateDriverAdapter` and the MySqlConnector constructor.
- E-4 `Source/LinqToDB/Internal/DataProvider/ClickHouse/ClickHouseSqlBuilder.cs:GetProviderTypeName` — new override: base, then the adapter getter, under D-5.
- E-5 `Source/LinqToDB/Internal/DataProvider/DuckDB/DuckDBSqlBuilder.cs:GetProviderTypeName` — new override: base, then the D-4 map.
- E-6 `Tests/Linq/Linq/ParameterTests.cs` — TO-1 … TO-5.
- E-7 `Source/LinqToDB/PublicAPI/PublicAPI.Unshipped.txt` — three `override …GetProviderTypeName(LinqToDB.IDataContext! dataContext, System.Data.Common.DbParameter! parameter) -> string?` entries (SQLite, ClickHouse, DuckDB builders are public, non-sealed; format as `PublicAPI.Shipped.txt:10074`).

## P7 Impact map (M/L)

- `GetProviderTypeName` overrides — searched `GetProviderTypeName` across `Source/` (Grep): 12 builders override (Access ODBC/OleDb, DB2, Firebird, Informix, MySql, Oracle, PostgreSQL, SapHana, SqlCe, SqlServer, Sybase, Ydb); SQLite, ClickHouse, DuckDB do not — covered by E-2, E-4, E-5
- Empty-type `DECLARE` lines by provider — searched `^DECLARE \S+  -- ` on `linq2db.baselines` `origin/master` (`git grep -l -E`): only SQLite*, DuckDB, ClickHouse* (counts in P1) — covered by E-2, E-4, E-5
- `PrintParameters` callers — searched `\.PrintParameters\(` across the worktree: `Source/LinqToDB/Data/TraceInfo.cs:145` (provider parameters of the executing command) — covered by E-2, E-4, E-5; `Tests/Base/TestBase.Concurrent.cs:141` (diagnostic dump of `result.Parameters.OfType<DbParameter>()`; non-provider parameters fail `TryGetProviderParameter` and fall back to base) — covered by E-2, E-4
- Tests asserting `DECLARE` text — searched `DECLARE @` under `Tests/`: `Tests/Linq/Data/MiniProfilerTests.cs` (its SQLite cases `:595-609` only call `GetSchema`, no trace assertion; the `Blob(` asserts at `:646`, `:1069` are DB2 / SAP HANA) and `Tests/Linq/DataProvider/Types/SqlServerTypeTests.cs:81` (SQL Server) — out-of-scope
- Baseline delta by `DbType` — critic census `git grep -h -o -E "^DECLARE \S+  -- \S+$"` per dir on baselines `origin/master` (SQLite.MS: Int32 4597, Int64 533, DateTime 396, Boolean 164, Guid 97, Int16 68, Double 52, Date 41, Single 37, DateTimeOffset 30, Byte 19, SByte 16, UInt16 13, VarNumeric 5, Object 3, Time 1; SQLite.Classic same families + Object 3; DuckDB Int32 8319, DateTime2 669, Int64 572, DateTime 298, Time 142, Date 117, Boolean 114, Double 106, Single 100, DateTimeOffset 96, Guid 61, Int16 57, Byte 44, UInt32 43, VarNumeric 42, UInt64 42, UInt16 38, SByte 38, Object 34; ClickHouse.* one null Int64 each) — every family is named by D-2 / D-3 / D-4 except DuckDB Object (P3) — covered by E-2, E-4, E-5
- Public surface — the 12 existing overrides are in `Source/LinqToDB/PublicAPI/PublicAPI.Shipped.txt` (e.g. `:10074`) — covered by E-7
- `DECLARE`-line tooling — searched `DECLARE` in `.claude/scripts/`, `Tests/Base/`, `Build/`: `.claude/scripts/baselines-pr-scan.ps1:153` counts `^\s*DECLARE\s` lines (added = removed for an in-place edit) and `:323` treats `DECLARE`/`SET` lines verbatim — out-of-scope
- MiniProfiler-wrapped commands — `Tests/Linq/Data/MiniProfilerTests.cs:596-609` run SQLite under `ConnectionType` wrappers; `DynamicDataProviderBase.TryGetProviderParameter` (`Source/LinqToDB/Internal/DataProvider/DynamicDataProviderBase.cs:161-164`) type-checks and returns null for a foreign parameter, which falls back to base — covered by E-2
- ClickHouse MySqlConnector adapter — `ClickHouseProviderAdapter(MySqlProviderAdapter)` `ClickHouseProviderAdapter.cs:103-117` copies members from `MySqlProviderAdapter.GetInstance(MySqlProvider.MySqlConnector)` (`:189`), whose `GetDbType` is public (`MySqlProviderAdapter.cs:95`) — covered by E-3
- Remote / direct baseline comparison — `Tests/Base/BaselinesWriter.cs:62-79`; both sides print server-side provider parameters (U-7) — Localized — searched `WriteTraceLine` / `LogQuery` in `Tests/Base`, single source `TestBase.cs:69-74`, no emitted-SQL change.
- Baselines repo — every P1 file on SQLite / DuckDB / ClickHouse changes `DECLARE` lines only (P3) — deferred: CI baselines PR review (G-02)

## P8 Test obligations (M/L)

Harness for TO-1, TO-2, TO-4, TO-5 (no database, U-9; rows marked "built directly" set `DbType` / `Value` on the parameter instead of calling `SetParameter`): the provider from `SQLiteTools` / `DuckDBTools` / `ClickHouseTools.GetDataProvider(...)`, a `DataConnection` over it with a placeholder connection string (never opened), a parameter from `Activator.CreateInstance(adapter.ParameterType)` populated by the provider's own `SetParameter(db, p, "p", dbDataType, value)`, printed with `dataProvider.CreateSqlBuilder(...).PrintParameters(db, sb, [p])`. One row per element below; the discriminating input for every red→green row is master's empty type (`DECLARE @p  -- <DbType>`, P1).

- TO-1a SQLite.MS `Int32` `1` → `DECLARE @p Integer -- Int32` — providers: SQLite.MS driver (no database) — proof: red→green
- TO-1b SQLite.MS `DateTime` → `DECLARE @p Text -- DateTime` — providers: SQLite.MS driver (no database) — proof: red→green
- TO-1c SQLite.MS `Guid` → `DECLARE @p Blob -- Guid` — providers: SQLite.MS driver (no database) — proof: red→green
- TO-1d SQLite.MS `Boolean` `true` → `DECLARE @p Integer -- Boolean` — providers: SQLite.MS driver (no database) — proof: red→green
- TO-1e SQLite.MS `Double` `1.5` → `DECLARE @p Real -- Double` — providers: SQLite.MS driver (no database) — proof: red→green
- TO-1f SQLite.MS `Int32` `null` → `DECLARE @p Integer -- Int32` (D-2 null fallback; the driver alone would say `Text`) — providers: SQLite.MS driver (no database) — proof: red→green
- TO-1m SQLite.MS `Guid` with `new DbDataType(typeof(Guid), DataType.Guid, "TEXT")` (the `(_, "TEXT")` arm, `SQLiteDataProvider.cs:262-271`, keeps a string value while `DataType.Guid` keeps `DbType.Guid`) → `DECLARE @p Text -- Guid`. (A text `DataType` such as `NVarChar` sets `DbType.String`, which the base already names — that is TO-2's path, not this one.) — providers: SQLite.MS driver (no database) — proof: red→green
- TO-1n SQLite.MS `DbType.Object` + `1` (parameter built directly, `DbType = Object`, `Value = 1`) → `DECLARE @p Integer -- Object` — providers: SQLite.MS driver (no database) — proof: red→green
- TO-1o SQLite.Classic `DbType.Object` + `1` (same construction) → `DECLARE @p Integer -- Object` (binder re-derivation, U-3) — providers: System.Data.SQLite driver (no database) — proof: red→green
- TO-1g SQLite.Classic `Int32` `1` → `DECLARE @p Integer -- Int32` — providers: System.Data.SQLite driver (no database) — proof: red→green
- TO-1h SQLite.Classic `Boolean` `true` → `DECLARE @p Integer -- Boolean` — providers: System.Data.SQLite driver (no database) — proof: red→green
- TO-1i SQLite.Classic `Guid` → `DECLARE @p Blob -- Guid` — providers: System.Data.SQLite driver (no database) — proof: red→green
- TO-1j SQLite.Classic `Double` `1.5` → `DECLARE @p Real -- Double` — providers: System.Data.SQLite driver (no database) — proof: red→green
- TO-1k DuckDB `Int32` `1` → `DECLARE $p INTEGER -- Int32` (`!NETFRAMEWORK`) — providers: DuckDB driver (no database) — proof: red→green
- TO-1l DuckDB `Boolean` `true` → `DECLARE $p BOOLEAN -- Boolean` (`!NETFRAMEWORK`) — providers: DuckDB driver (no database) — proof: red→green
- TO-1p DuckDB via the real path `SetParameter(db, p, "p", new DbDataType(typeof(BigInteger), DataType.Undefined), BigInteger.One)` (`SetParameterType` leaves `DbType` alone for `Undefined`, so `DuckDBParameter.Value`'s setter derives `VarNumeric` from the `BigInteger`, `DuckDBParameter.cs:30-37`, `DuckDBTypeMap:71-72`) → `DECLARE $p BIGNUM -- VarNumeric` (`!NETFRAMEWORK`) — providers: DuckDB driver (no database) — proof: red→green
- TO-1q DuckDB parameter built directly with `DbType = Object` and no value (a value would re-derive `DbType` in the setter, `DuckDBParameter.cs:30-37`; a null value leaves it, `:32`) → `DECLARE $p  -- Object` unchanged (P3 exception) — providers: DuckDB driver (no database) — proof: characterization
- TO-2 Unchanged base names (symmetry guard on the unchanged path): SQLite.MS, SQLite.Classic and DuckDB `NVarChar` `"abc"` → `NVarChar(3) -- String`; SQLite.Classic `DateTime` → `VarChar(23) -- AnsiString`; `Binary` `byte[3]` → `Binary(3)`; `Decimal` `1.5m` → `Decimal(` — each must equal master's output — providers: SQLite.MS, System.Data.SQLite, DuckDB drivers (no database) — proof: characterization
- TO-3 Real execution and trace: `var id = 1; db.Person.Where(p => p.ID == id).ToList()`, then `GetCurrentBaselines()` contains `DECLARE @id Integer -- Int32` (SQLite.*) / `DECLARE $id INTEGER -- Int32` (DuckDB); covers the `BeforeExecute` path and the server-side trace of `.LinqService` — providers: `TestProvName.AllSQLite`, `ProviderName.DuckDB`, `[IncludeDataSources(true, …)]` — proof: red→green
- TO-4a ClickHouse Octonica `Int64` `1L` → `DECLARE @p Int64` (`!NETFRAMEWORK`) — providers: Octonica driver (no server) — proof: red→green
- TO-4b ClickHouse.Driver `Int64` `1L` → `DECLARE @p Int64` — providers: ClickHouse.Driver (no server) — proof: red→green
- TO-4c ClickHouse MySqlConnector `Int64` `1L` → `DECLARE @p Int64` — providers: MySqlConnector driver (no server) — proof: red→green
- TO-4d ClickHouse `Int64` `null` — the only shape the three ClickHouse baselines contain (`DataExtensionsTests.cs:285`): Octonica → `DECLARE @p Int64` (`!NETFRAMEWORK`), MySqlConnector → `DECLARE @p Int64`, ClickHouse.Driver → `DECLARE @p Nullable(Nothing) -- Int64` (D-3 null rule; the MySqlConnector value is unprobed until this row runs) — providers: all three ClickHouse drivers (no server) — proof: red→green
- TO-6 Real ClickHouse path: the existing `DataExtensionsTests.TestDataParameterMapping3` run against the local `clickhouse` container (started 2026-10-29, user-approved) on all three contexts; its baseline shows the TO-4d strings — providers: `TestProvName.AllClickHouse` — proof: red→green
- TO-5 SQLite.MS parameter with `DbType = DbType.Object`, `Value = new object()` → no exception, output `DECLARE @p  -- Object`. Mutation that turns it red: removing the D-5 `catch` (`SqliteValueBinder.GetSqliteType` throws `InvalidOperationException` for an unmapped type, U-2) — providers: SQLite.MS driver (no database) — proof: control

## P9 Verification gates

- G-01: — (pending)
- G-02: — (pending)
- G-05: — (pending)
- G-06: — (pending)
- G-07: — (pending)
- G-08: — (pending)
- G-09: — (pending)

## P10 Adjudicated (M/L)

- Mixed naming styles inside one `DECLARE` block (D-1): user decision "a", 2026-10-29.
- SQLite.Classic and DuckDB names are predictions from `DbType`, not driver reports (D-2, D-4): neither driver exposes a bound type (U-3, U-6).
- ClickHouse.Driver prints `QueryForm`'s type, which ignores a configured resolver / SQL type hint (D-3): the full resolution is internal to the driver (U-4).
- Null values: SQLite.MS falls back to the `DbType` map, ClickHouse.Driver prints `Nullable(Nothing)` (D-2 vs D-3): Microsoft.Data.Sqlite sends an untyped NULL, ClickHouse.Driver sends a `Nullable(Nothing)`-typed placeholder.
- Size / precision suffix on a new name (`Integer(10) -- Int32`, P3): `PrintParameterType`'s existing behaviour for every provider override (`BasicSqlBuilder.cs:4973-4984`); not specialised here.
- DuckDB `-- Object` rows stay unnamed (34 interval rows, P3, D-4): `DbType.Object` carries no type to translate.

## P11 Amendments (M/L)

_None._

## P12 Critic verdict (M/L)

- Round 1 (2026-10-29, plan-critic on `fable`): **refuted**. Searched the per-`DbType` baseline census (`git grep -o` / `-A1` per provider dir), decompiled SQLite 10.0.12 and 3.1.32, System.Data.SQLite `SQLiteStatement`, Octonica, ClickHouse.Driver 0.9.0 / 1.4.0, DuckDB.NET `DuckDBTypeMap`, and every `PrintParameters` / `GetProviderTypeName` site. Objections and response:
  - D-2 Classic missed the binder's `DbType.Object` re-derivation (`SdsStatement.cs:277-280`) → U-3 extended (author decompiled `SQLiteConvert.TypeToDbType`), D-2 applies the map to the effective `DbType`, TO-1n/TO-1o added.
  - P3 claimed every empty line gains a name while D-4 leaves 34 DuckDB `Object` rows empty → P3 states the exception, TO-1q pins it, P10 entry.
  - U-10 had the DuckDB `SetParameter` order backwards → rewritten from `DuckDBDataProvider.cs:159-163` (re-read by the author); VarNumeric now `BIGNUM` per `DuckDBSqlBuilder.cs:120`, TO-1p.
  - D-3 had no null policy while all three ClickHouse baselines are null → D-3 states it (driver report, `Nullable(Nothing)` on ClickHouse.Driver), P10 explains the D-2 difference, TO-4d and TO-6 added.
  - lead: size / precision suffix on a new name → P3 + P10 (existing base behaviour).
  - SC-1 Guid branch → SC-1 split, TO-1m.
  - P7 MiniProfiler reason → corrected. PublicAPI → E-7.
- Round 2 (2026-10-29, plan-critic on `fable`, same agent resumed): **weak**. Searched: decompiled System.Data.SQLite `SQLiteParameter` (explicit `DbType.Object` survives to the builder — TO-1o holds), MySqlConnector 2.6.2 `MySqlParameter` (null keeps `Int64`; 44 NULL `Int64` rows in MySqlConnector.8.0 baselines — TO-4d MySqlConnector now measured), ClickHouse.Driver 1.4.0 `NullableType.ToString()` and 0.9.0 `TypeConverter` (`Nullable(Nothing)` on the net462 leg too), DuckDB.NET `DuckDBTypeMap` (`BigInteger → VarNumeric`, `Int128` / `DuckDBInterval` → `Object`), builder visibility, `init` usage, harness reachability, `.LinqService` baseline presence. Objections and response:
  - TO-1p / TO-1q "built directly" could go red for the wrong reason (`DuckDBParameter.Value` re-derives `DbType`) → TO-1p routed through `SetParameter` with `DataType.Undefined` + `BigInteger`; TO-1q states it relies on no value.
  - P3 ClickHouse line count wording → fixed.
  Not checked by the critic: no test run; `Int64Type` / `NothingType` literal text inferred from the parser key — TO-4b / TO-4d measure it.
