# Work plan: issue-6077-npgsql-dateonly-ns20 — netstandard2.0 build reads Npgsql 10 date/time/daterange into classic types

**Tier:** L  ·  **Status:** approved  ·  **Approved-at:** 2026-10-20 (E-1…E-6)  ·  **Branch:** issue/6077-npgsql-dateonly-ns20
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

## P1 Problem

linq2db/linq2db#6077. On a modern runtime that loads linq2db's **netstandard2.0** asset, Npgsql 10 returns modern BCL types for classic columns, and the ns2.0 build has no conversion back to the classic property types. Every one of these conversions sits behind `SUPPORTS_DATEONLY`, which is defined for net8.0+ only (`Directory.Build.props:70`). That asset is what an app gets through a netstandard2.0 library, and what every net8/net9 app gets once #5942 drops those TFMs.

Measured on master `c1d9d7656` with `worktree-test.ps1 -LinqToDBAsset netstandard2.0` (linq2db built at net10.0 with the ns2.0 define set), PostgreSQL.18. Each test passes on the normal net10.0 build:

- `PostgreSQLTests.TestDate`: `LinqToDBConvertException: Cannot convert value '12/12/2012: System.DateOnly' to type 'System.DateTime'`
- `TestRange` / `TestRangeBulkCopy` / `TestRangeBulkCopyAsync`: `Cannot convert value '[2/3/2000,3/4/2000): NpgsqlRange<DateOnly>' to type 'NpgsqlRange<DateTime>'` (ColumnName `DateRangeInclusive`)
- `TestTableFunction`: `Cannot convert value '12:12: System.TimeOnly' to type 'System.TimeSpan'` (ColumnName `timeDataType`). On net10.0 this test fails later, with an unrelated pre-existing `Reading as 'System.Object' is not supported`.

Mechanism (scout, `ConvertBuilder.cs:483-522`, `:30`): `Converter.GetConverter(DateOnly, DateTime)` (`:488`) finds nothing on ns2.0. Neither a schema conversion nor a reflection strategy applies, so `ConvertDefault` calls `Convert.ChangeType`, which throws.

## P2 Success criteria

- SC-1 With the ns2.0 define set, a PostgreSQL `date` value read into `DateTime` / `DateTime?` returns the date at midnight, with no exception → TO-1
- SC-2 With the ns2.0 define set, a `daterange` column mapped to `NpgsqlRange<DateTime>` reads back the same normalized bounds as net10.0 → TO-2
- SC-3 With the ns2.0 define set, a `time` value read into `TimeSpan` (scalar, entity, and entity over a remote context — every shape U-1 measured red) returns the time of day → TO-3a, TO-3b
- SC-4 With the ns2.0 define set, a `time` value read into `DateTime` returns `0001-01-01` plus the time of day, the same value net10.0 returns → TO-4
- SC-5 net10.0 and net462 behaviour is unchanged: the same PostgreSQL fixture and the core `ConvertTests` pass before and after; the new `time` tests are green on net10.0 before the fix → TO-5a, TO-5b, TO-6, TO-3c
- SC-7 With the ns2.0 define set, a PostgreSQL `date` value read into `string` returns `"2012-12-12"`, the value net10.0 returns, through Npgsql and DB-less through `MappingSchema.Default` → TO-8, TO-9
- SC-6 The core conversion is provider-agnostic: `Converter`/`ConvertTo<DateTime>.From(DateOnly)` works with the ns2.0 define set, without any provider → TO-7

## P3 Constraints & anti-goals (M/L)

- No new public API, and no change to public signatures. `PublicAPI.*.txt` stays untouched.
- No DateOnly/TimeOnly **property** support on ns2.0: DateTime→DateOnly, string→DateOnly, DateOnly literals and parameters, arrays and `IPNetwork` stay net8-only. That is feature parity, available on request only (`code-design.md` → *A TFM gate may withhold a feature…*).
- The net8+ builds keep their behaviour: the same registrations, keys and values.
- No generated-SQL change on any provider. These are read-side conversions only, so no baselines move.
- Sibling providers with the same gap shape are not touched here, as a scope choice: DuckDB TIMETZ/TIME, MySQL VECTOR, the ClickHouse.Driver insert, and ClickHouse `DateOnly`→`DateTimeOffset`. Several are measured red on the ns2.0 path (P7), and each is filed or deferred to its own provider issue (linq2db#6084, #6085, #6086). The exception is Octonica's `DateOnly`→`DateTime`, which the core E-1 closes.

## P4 Unknowns (M/L)

- U-1 Which `time`→`TimeSpan` read shapes fail on ns2.0 with Npgsql 10. Measured (probe tests on master, `-LinqToDBAsset netstandard2.0`, PostgreSQL.18): all of them. `Execute<TimeSpan>` / `Execute<TimeSpan?>` over `Cast('12:12:12' as time)`, an entity with a `[Column(DbType="time")] TimeSpan` read through LINQ, and the same entity on `PostgreSQL.18.LinqService` each throw `Cannot convert value '12:12: System.TimeOnly' to type 'System.TimeSpan'`. `TestDataTypes` did not "pass" in the sweep: it was skipped, because it runs on the disabled `PostgreSQL` config ("Provider is disabled") — resolved-by probe
- U-2 Whether `time`→`DateTime` (the `PostgreSQLMappingSchema.cs:77` FromDatabase conversion) is reachable and red on ns2.0. Measured, same run: `Execute<DateTime>` over `Cast('12:12:12' as time)` throws `Cannot convert value '12:12: System.TimeOnly' to type 'System.DateTime'` — resolved-by probe
- U-3 `TestTableFunction` cannot be the obligation for SC-3: `AllTypes.dateDataType` is `DateOnly?` under `SUPPORTS_DATEONLY` in the test build (`PostgreSQLTests.cs:830-834`), so the test reads `date` into `DateOnly` on the ns2.0 path and stays red by design (P3) — resolved-by scout
- U-4 Does `Type.GetType("System.DateOnly")` from inside linq2db resolve a polyfill copy? Measured: `Directory.Build.props:135-198` enables no DateOnly/TimeOnly polyfill, so it resolves the BCL type from CoreLib on .NET 6+ and returns null on .NET Framework — resolved-by scout
- U-5 `new DateTime(DateOnly, TimeOnly)` (used by `PostgreSQLMappingSchema.cs:77`) exists only from .NET 8 (reasoned, unprobed), and the ns2.0 asset may run on .NET 6/7. `new DateTime(timeOnly.Ticks)` gives the same value, because `default(DateOnly)` is 0001-01-01 and ticks 0 — resolved-by D-3, with TO-4 asserting the value
- U-6 Do the non-generic registration APIs store the same keys as the typed calls? `SetProviderField<TP,T>(Type providerFieldType, …)` (`DataProviderBase.cs:216`) gives `{ToType, ProviderFieldType, DataTypeName=null, DataReaderType=null}`, identical to `SetProviderField<TP,T,TS>` at the current call site (`:221`, no reader type passed). `MappingSchema.SetConvertExpression(Type, Type, LambdaExpression, bool, ConversionType)` (`MappingSchema.cs:566`) stores what the generic `:642` stores — resolved-by scout

## P5 Decisions (M/L; rejected alternatives mandatory at L)

### D-1 — Resolve DateOnly/TimeOnly at runtime on every TFM, instead of adding `#else` branches

- **chosen:** take the three classic-target registrations out of `#if SUPPORTS_DATEONLY` and express them with `Type.GetType("System.DateOnly")` / `"System.TimeOnly"` plus reflected members. The same code then runs on net8+ and ns2.0, and is skipped where the types don't exist (.NET Framework). The core `Converter` entry also becomes a runtime-built lambda.
- **rejected:** keep the typed net8 code and add an `#else` reflection branch — two implementations of one rule, and the ns2.0 one is exercised by no CI leg. Also rejected: ship a `net8.0`-style asset for older runtimes — out of scope; #5942 decides the TFMs.
- **why this:** one path covered by every CI leg on net8+; the ns2.0 run differs only in whether the types resolve. Trim (#6075) uses the same shape.
- **failure mode of the choice:** net8+ now goes through reflection-built lambdas. Built wrongly, they would change net8 behaviour silently. TO-5/TO-6 (net10.0 and net462 runs of the same fixtures) are the guard. Two constraints keep it safe:
  - **No throw in a constructor.** `Converter`'s static ctor initialises every conversion in the library, so a dereferenced null there is a `TypeInitializationException` on first use. Each registration resolves its type and every member it needs first, and registers only when all are non-null; otherwise it skips the whole registration. The "type resolves but a member doesn't" branch is unreachable on any shipped runtime (DateOnly, TimeOnly and their members all arrived together in .NET 6), so the guard cannot be covered by a test; it is defensive by construction. The same rule applies in the E-2/E-3 constructors, including `NpgsqlRangeTType.MakeGenericType(dateOnly)`.
  - **Same expression shape as today on net8+.** `ExpressionBuilder.Equal` (`ExpressionBuilder.cs:639-652`) inlines the converter's body into the LINQ tree. The reflected bodies therefore copy the compiler's shape: `Expression.Call(v, ToDateTime(TimeOnly), Expression.Property(null, TimeOnly.MinValue))` (a static `MemberExpression`, not a constant) and `Expression.Call(v, ToString(string, IFormatProvider), …)` for D-4.

### D-2 — Keep the core `Converter` DateOnly→DateTime entry, rather than a PostgreSQL-only reader

- **chosen:** register DateOnly→DateTime in `Converter`'s static ctor, as net8 does (`Converter.cs:58`).
- **rejected:** a PostgreSQL `SetProviderField<DbDataReader, DateTime>(dateOnlyType, rd => rd.GetFieldValue<DateTime>(i))` reader — it fixes only Npgsql. Octonica ClickHouse hits the same core gap: `ClickHouseTypeTests.TestDateType("ClickHouse.Octonica")` was measured red with `DateOnly`→`DateTime` on the ns2.0 path. The core entry is exactly what net8 relies on.
- **why this:** mirrors net8 one-to-one; its only consumer is `ConvertBuilder.cs:488`, and an entry keyed (DateOnly, DateTime) can only turn a throw into a value (scout §2).
- **failure mode of the choice:** a user who maps a `DateOnly` member and reads it into `DateTime` on ns2.0 gets a value where they previously got an exception. That is a widening, not a regression.

### D-3 — Build TimeOnly→DateTime from `Ticks`, not from the `DateTime(DateOnly, TimeOnly)` constructor

- **chosen:** `v => new DateTime(v.Ticks)`, built by reflection.
- **rejected:** reflect `DateTime(DateOnly, TimeOnly)` — it is absent on .NET 6/7 (U-5), so the registration would silently not happen there.
- **why this:** same value on every runtime where TimeOnly exists.
- **failure mode of the choice:** a different expression shape on net8, so the stored conversion differs textually from today's. Values are equal; TO-4 runs on net10.0 as well.

### D-4 — Also ungate the default schema's DateOnly→string converter

- **chosen:** `MappingSchema.cs:1488-1490` (`SetConverter<DateOnly, string>(v => v.ToString("yyyy-MM-dd", InvariantInfo))`) moves to a runtime-resolved registration with the same shape: `Invoke(Constant(delegate), p)` stored through `SetConvertInfo`, exactly as `SetConverter<TFrom,TTo>` (`MappingSchema.cs:697-713`) builds it. The delegate comes from `Compilation.CompileExpression()` (`Common/Compilation.cs:41`), because `LambdaExpression.Compile` is banned (`BannedSymbols.txt:238,241`). `CompileExpression` yields the `Func<DateOnly,string>`-typed delegate that `GetConverter<TFrom,TTo>()` casts (`MappingSchema.cs:550`). No `MethodBase.Invoke` either (`BannedSymbols.txt:255`): every reflected member is used through `Expression`. That shape keeps the conversion client-side, which is what the comment at `:1486` asks for.
- **rejected:** leave it gated (critic objection 1). The divergence is measured and silent: `Execute<string>("SELECT Cast('2012-12-12' as date)")` returns `"12/12/2012"` on the ns2.0 path and `"2012-12-12"` on net10.0 (same probe, PostgreSQL.18). Also rejected: `SetConvertExpression` with a plain `ToString` body, which would let a `ToString` translator take it server-side and change what the conversion means.
- **why this:** source that compiles on net462 (`Execute<string>` over a `date` column) returns a different value per asset. That is a hard fail under the policy, just a silent one.
- **failure mode of the choice:** it is a second reflection site in a core static ctor, under the same no-throw rule as D-1.

## P6 Edit-points

- E-1 `Source/LinqToDB/Common/Converter.cs:Converter()` — add a runtime-resolved DateOnly→DateTime entry outside `#if SUPPORTS_DATEONLY`; the typed `SetConverter<DateOnly, DateTime>` line is removed in favour of it. DateTime→DateOnly and string→DateOnly stay gated.
- E-2 `Source/LinqToDB/Internal/DataProvider/PostgreSQL/PostgreSQLDataProvider.cs:PostgreSQLDataProvider()` — the TimeOnly→TimeSpan provider-field reader and the `NpgsqlRange<DateOnly>`→`NpgsqlRange<DateTime>` `GetFieldValue` reader leave `#if SUPPORTS_DATEONLY`, using runtime-resolved types.
- E-3 `Source/LinqToDB/Internal/DataProvider/PostgreSQL/PostgreSQLMappingSchema.cs:PostgreSQLMappingSchema()` — the TimeOnly→DateTime FromDatabase conversion leaves the `#if` block, built by reflection per D-3. The DateOnly literal and `IPNetwork` scalar types stay gated.
- E-4 `Tests/Linq/DataProvider/PostgreSQLTests.cs` — new `Issue6077*` tests for SC-3 / SC-4 (the shapes U-1 / U-2 confirm red).
- E-5 `Tests/Linq/Common/ConvertTests.cs` — core-layer test for SC-6.
- E-6 `Source/LinqToDB/Mapping/MappingSchema.cs:DefaultMappingSchema` (ctor, `:1488-1490`) — runtime-resolved DateOnly→string converter per D-4. The `AddScalarType` rows at `:1457-1462` stay gated (feature parity).

## P7 Impact map (M/L)

- `Source/LinqToDB/Internal/Linq/Builder/ExpressionBuilder.cs:639-652` — `Equal` inlines `ConvertBuilder.GetConverter`'s body into the LINQ tree, so net8+ translates whatever body E-1 builds. `ToDateTime` has no SQL translator (searched `ToDateTime` across Source/LinqToDB), so only client-evaluated DateOnly values reach it. D-1 pins the body to the compiler's shape — covered by E-1
- `Source/LinqToDB/Internal/Conversion/ConvertBuilder.cs:488` — the only caller of `Converter.GetConverter` (searched `Converter\.GetConverter|_expressions` over Source) — covered by E-1
- `Source/LinqToDB/Common/Converter.cs:95,106` — the only readers and writers of `_expressions`. Not part of any configuration ID (`ConvertInfo.cs:178+`) — covered by E-1
- `ConvertInfo.cs:169`, `Common/Convert{TFrom,TTo}.cs:32`, `Internal/Linq/Builder/ExpressionBuilder.cs:639-640` — callers of `ConvertBuilder.GetConverter` that now see a DateOnly→DateTime entry on ns2.0: throw → value only (searched `ConvertBuilder\.`) — covered by E-1
- `PostgreSQLDataProvider.cs:24-32` — version subclasses (92…19) are one-line ctors that inherit the base registrations (searched `class \w+\s*:\s*PostgreSQLDataProvider\b`) — covered by E-2
- `PostgreSQLMappingSchema.cs:202-214` — version schemas chain `Instance` and have no bodies (searched `PostgreSQLMappingSchema`) — covered by E-3
- `PostgreSQLMappingSchema.cs:73,79-82,120-123,168-173` — DateOnly literal, `IPNetwork` scalars, DateOnly/TimeOnly arrays, `BuildDate`. Feature parity, stays gated — out-of-scope
- `PostgreSQLSchemaProvider.cs:127-134` — `cidr`→`IPNetwork` schema mapping, unrelated to dates — out-of-scope
- `DuckDBDataProvider.cs:79-80` — TIMETZ `DateTimeOffset`→`TimeSpan` reader, gated. Measured on master, `-LinqToDBAsset netstandard2.0`: `DuckDBTypeTests.TestTimeTZ` throws `Cannot convert value '…: System.DateTimeOffset' to type 'System.TimeSpan'`, green on net10.0. A different provider and a separable fix — deferred: linq2db#6084 (Backlog), not this PR
- `DuckDBDataProvider.cs:61-66` — TIME `TimeOnly`→`TimeSpan`/`DateTime` readers. **Unprobed.** `DuckDBTypeTests.TestTime` fails first on its `TimeOnly`-property case (`DuckDBTypeTests.cs:383`, feature parity), so its `TimeSpan` cells (`:386-387`) never ran on the ns2.0 path. An earlier claim that "DuckDBTests" was clean was void: no fixture of that name exists, and the filter matched nothing — deferred: probe under linq2db#6084 together with TIMETZ
- `MySqlMappingSchema.cs:42-44` — VECTOR `ReadOnlyMemory<float>`→`float[]`, gated. Measured: `MySqlTypeTests.TestVectorType` (MySqlConnector.8.0) throws on the ns2.0 path, green on net10.0 — deferred: linq2db#6085 (Backlog), not this PR
- `ClickHouseDataProvider.cs` (ClickHouse.Driver write path) — `ClickHouseTypeTests.TestDateType("ClickHouse.Driver")` fails on the ns2.0 path with `Unknown expression identifier p1` on a parameterised insert, green on net10.0. Cause not isolated — deferred: linq2db#6086 (Backlog), investigate there
- `ClickHouseTypeTests.TestDateType("ClickHouse.Octonica")` — measured red on the ns2.0 path with `Cannot convert value '2/29/2020: System.DateOnly' to type 'System.DateTime'`: the same core DateOnly→DateTime gap E-1 closes. The test also has `DateOnly`-property cases (`:325-328`, feature parity), so it cannot be a clean obligation — covered by E-1 (TO-7 is the core proof)
- `ClickHouseMappingSchema.cs:79-80` — DateOnly→DateTimeOffset conversion. **Unprobed, masked.** In `ClickHouseTypeTests.TestDateType` (`:322-331`) and `TestDate32Type` (`:354-365`) the `DateTimeOffset` cells run after the `DateOnly`-property cells. Those fail first on the ns2.0 path, and still will after E-1 — deferred: same class; probe with a dedicated test under linq2db#6086 (ClickHouse)
- `Source/LinqToDB/Internal/Remote/SerializationMappingSchema.cs:35-37,62-64` — the serializer's gated `DateOnly`↔`string` pair, the nearest shape-mirror of E-6. Reached only when `LinqService.cs:329` sets `FieldTypes[i]` to `DateOnly`, i.e. a `DateOnly`-typed query member. Classic targets are converted server-side by `ColumnReader` (`:363-377`) before `Serialize` (`:380`) — out-of-scope
- Write side: the DateOnly parameter conversions in 11 providers (scout §3 A′) take a user `DateOnly` value — out-of-scope (feature parity)
- `Tests/Linq/DataProvider/ProviderSpecificReaderValueTests.cs:182` — `#if !NETFRAMEWORK` matrix expecting provider-specific `date`→DateOnly, `time`→TimeOnly, `daterange`→`NpgsqlRange<DateOnly>`. It reads provider-specific values, which E-2 doesn't change; TO-5 runs it — out-of-scope
- Localized - searched `#if !SUPPORTS_DATEONLY` and `ConvertTo<DateTime>` from DateOnly across Tests/, no test asserts that DateOnly→DateTime fails or relies on the converter being absent.

## P8 Test obligations (M/L)

- TO-1 `PostgreSQLTests.TestDate` (`PostgreSQLTests.cs:313`, `[IncludeDataSources(TestProvName.AllPostgreSQL)]`) on PostgreSQL.18 with `-LinqToDBAsset netstandard2.0`; discriminating input `Cast('2012-12-12' as date)` read as `DateTime` — proof: red→green
- TO-2 `PostgreSQLTests.TestRange` / `TestRangeBulkCopy` / `TestRangeBulkCopyAsync` (`:1950`, `:1980`, `:2024`, `AllPostgreSQL`) with `-LinqToDBAsset netstandard2.0`; discriminating input `daterange` into `NpgsqlRange<DateTime>` — proof: red→green
- TO-3a new `Issue6077TimeToTimeSpanScalar` (E-4, `[IncludeDataSources(TestProvName.AllPostgreSQL)]`): `Execute<TimeSpan>` and `Execute<TimeSpan?>` over `Cast('12:12:12' as time)` equal `new TimeSpan(12, 12, 12)`, with `-LinqToDBAsset netstandard2.0` (red measured on master, U-1) — proof: red→green
- TO-3b new `Issue6077TimeToTimeSpanEntity` (E-4, `[IncludeDataSources(true, TestProvName.AllPostgreSQL)]`): a `CreateLocalTable` row with a `time` `TimeSpan` column reads back equal, direct and `.LinqService`, with `-LinqToDBAsset netstandard2.0` (red measured on master for both contexts, U-1) — proof: red→green
- TO-4 new `Issue6077TimeToDateTime` (E-4, `AllPostgreSQL`): `Execute<DateTime>` / `Execute<DateTime?>` over `Cast('12:12:12' as time)` equal `new DateTime(1, 1, 1, 12, 12, 12)`, with `-LinqToDBAsset netstandard2.0` (red measured, U-2) and on net10.0 (the value D-3 must keep) — proof: red→green
- TO-5a `PostgreSQLTests` on net10.0 and net462, PostgreSQL.18, same result set before and after (symmetry guard on the unchanged net8 and netfx paths). net462 uses Npgsql 8.0.9 (`Directory.Packages.props:162-163`) and has no DateOnly type, so there it proves only D-1's `Type.GetType == null` skip branch (no throw), not a value — proof: characterization
- TO-9 new `ConvertTests.DateOnlyToString` (E-5): `ConvertTo<string>.From(new DateOnly(2012, 12, 12))` is `"2012-12-12"`. This is a DB-less discriminator for E-6: `Convert<TFrom,TTo>` resolves through `MappingSchema.Default` (`Convert{TFrom,TTo}.cs:32`, `ConvertBuilder.cs:562`), and before the fix it returns `"12/12/2012"` via `GetToStringInvariant` (`ConvertBuilder.cs:517`). `#if NET8_0_OR_GREATER` (test TFM); red with `-LinqToDBAsset netstandard2.0` before, green after and on net10.0 — proof: red→green
- TO-5b `ProviderSpecificReaderValueTests.PostgreSQLProviderSpecificReadMatrix` on net10.0 only (the file is `#if !NETFRAMEWORK`), PostgreSQL.18, before and after — proof: characterization
- TO-3c net10.0 control: `Issue6077TimeToTimeSpanScalar` / `Issue6077TimeToTimeSpanEntity` green on the normal net10.0 build before E-2. This shows the ns2.0 red comes from the asset gate and not from Npgsql 10 itself. The `.LinqService` arm converts server-side, through the provider's `ReaderExpressions` (`LinqService.cs:329-377`) — proof: characterization
- TO-6 `Tests.Common.ConvertTests` (`Tests/Linq/Common/ConvertTests.cs`) on net10.0 and net462, SQLite.MS — proof: characterization
- TO-8 new `Issue6077DateToString` (E-4, `AllPostgreSQL`): `Execute<string>("SELECT Cast('2012-12-12' as date)")` is `"2012-12-12"`. Measured `"12/12/2012"` with `-LinqToDBAsset netstandard2.0` and green on net10.0 before the fix — proof: red→green
- TO-7 new `ConvertTests.DateOnlyToDateTime` (E-5): `ConvertTo<DateTime>.From(new DateOnly(2012, 12, 12))` equals `new DateTime(2012, 12, 12)`, run with `-LinqToDBAsset netstandard2.0` (red before E-1) and on net10.0. `#if NET8_0_OR_GREATER` in the test (the test TFM, not linq2db's) — proof: red→green

## P9 Verification gates

- G-01: — (pending)
- G-02: — (pending)
- G-05: — (pending)
- G-06: — (pending)
- G-07: — (pending)
- G-08: — (pending)
- G-09: — (pending)

## P10 Adjudicated (M/L)

_None yet._

## P11 Amendments (M/L)

_None._

## P12 Critic verdict (M/L)

**Round 1 (plan-critic on `fable`): weak.** It searched `SUPPORTS_DATEONLY` across Source (78 blocks); the `Converter.GetConverter` / `_expressions` consumers; the reader path `ConvertFromDataReaderExpression` → `DataProviderBase.GetReaderExpression` → `ConvertBuilder`; the non-generic registration overloads (U-6 holds); the remote arm (`LinqService.cs:291-388`, which converts server-side); and the trimming/AOT and banned-API settings (no risk). Objections and responses:

1. `date`→`string` is a silent classic-target sibling (`MappingSchema.cs:1488`) → probed: `"12/12/2012"` on ns2.0 vs `"2012-12-12"` on net10.0. Added D-4, E-6, SC-7, TO-8.
2. The DuckDB row cited a fixture that doesn't exist → re-swept with the real fixtures (`DuckDBTypeTests`, `ClickHouseTypeTests`, `MySqlTypeTests`) on the ns2.0 path, with net10.0 controls. Found three more ns2.0-only failures (DuckDB TIMETZ, MySQL VECTOR, ClickHouse.Driver insert), now deferred P7 rows for separate issues. Octonica `DateOnly`→`DateTime` is covered by E-1. D-2's DuckDB citation is replaced by the Octonica measurement.
3. Static-ctor reflection must not throw → D-1 now requires null-guarded, all-or-nothing registration in every ctor.
4. `ExpressionBuilder.Equal` inlines the converter body on net8+ → D-1 pins the reflected bodies to the compiler's shape; new P7 row.
5. TO-3a/3b had no net10 control → TO-3c added. It was measured green on net10.0 (all 7 `Issue6077*` cases).
6. TO-5 listed net462 for a `#if !NETFRAMEWORK` test → split into TO-5a and TO-5b.

**Round 2 (delta, `fable`): weak.** It searched the `SUPPORTS_DATEONLY` blocks outside the providers; every `DateOnly`→`string` registration (only the default schema's); `Equal` inlining against `ConvertInfo.Get` (`FromDatabase` entries never reach it, so D-3's shape freedom holds); `SetConverter`/`SetConvertInfo`/`SetNullableConversion` (the E-6 shape claim is complete, and a `string` target needs no nullable twin); the `LinqService` field-type path; trim analyzers (none on `LinqToDB.csproj`). Objections and responses:

1. `LambdaExpression.Compile` is banned (`BannedSymbols.txt:241`) → D-4 now uses `CompileExpression()`; no `MethodBase.Invoke`.
2. The P3 sibling sentence contradicted the P7 measurements → rewritten as a scope choice with issue numbers.
3. The ClickHouse `DateTimeOffset` row was a masked negative → relabelled "unprobed, masked" and deferred to linq2db#6086.
4. SC-7 had no core-layer obligation → TO-9 added (`ConvertTo<string>.From(DateOnly)`).
5. The `SerializationMappingSchema` mirror was missing → P7 row added, out-of-scope with its reachability reason.
6. Deferrals cited no issue → they now cite linq2db#6084, #6085, #6086 (Backlog), filed before this round's revision.

Also addressed: TO-5a states that net462 runs Npgsql 8 and proves only the skip branch; D-1 states that the member-null branch is unreachable by construction.

**Residual (carried forward, not re-critiqued):** the round-2 fixes are textual, plus one new obligation (TO-9). No third critic pass was run, per the one-revision cap.
