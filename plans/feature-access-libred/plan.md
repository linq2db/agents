# Work plan: feature-access-libred — the LibRed managed Access provider

**Tier:** L  ·  **Status:** approved  ·  **Approved-at:** 2026-09-20  ·  **Branch:** feature/access-libred
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

Branch 3 of the .NET 11 track. Cut off `feature/csharp15-runtime-async` (PR #5944) at `77800f967`;
worktree `C:\Worktrees\linq2db\5942-access-libred`. Branch 1 is PR #5942, branch 2 is PR #5944; all
three stay unmerged until .NET 11 RTM because `global.json` pins an exact prerelease SDK.

**Evidence, committed beside this plan so it outlives the worktree:** `findings.md` is the measured
capability report for the dependency, and `probe/` holds the net11.0 console app that produced it
(`Program.cs` with modes `signatures`, `smoke`, `battery`, `schema`, `access-sql`, `ms-file`,
`script`, plus `fk-probe.sql`). Every "measured:" claim below traces to a run of that app; re-running
it needs only `dotnet run` against the pinned SDK. The raw logs stayed in the worktree's scratch
directory and are reproducible rather than preserved.

## P1 Problem

linq2db can reach an Access `.mdb`/`.accdb` only through Microsoft's OLE DB or ODBC drivers. Three
consequences are checkable today:

- **Windows-only, driver-install-only.** All four Access providers resolve through
  `OleDbProviderAdapter` / `OdbcProviderAdapter` (`AccessProviderAdapter.cs:21,35`), and every Access
  CI leg is Windows with an ACE redistributable installed by a setup script
  (`Build/Azure/pipelines/templates/test-matrix.yml:372-488`, `Build/Azure/scripts/access.ace.ps1`).
  Three of the four legs are additionally x86 (`tests.yml:354`). There is no Linux Access coverage.
- **The drivers' schema surface is broken, and linq2db documents it.**
  `AccessODBCSchemaProvider.GetForeignKeys` (`:25-30`) and `GetPrimaryKeys` (`:70-75`) both
  `return []` citing `dotnet/runtime#35442`; `AccessOleDbSchemaProvider.GetColumns:138` forces
  `IsIdentity = false` for issue #3149; `AccessOleDbSchemaProvider.cs:52-55` records that
  `GetOleDbSchemaTable` can trigger an unhandled native access violation. `LinqToDB.Scaffold`'s
  `MergedAccessSchemaProvider` exists *only* to paper one driver's gaps with the other's.
- **No managed alternative is reachable.** `AccessProvider` has exactly `AutoDetect`, `OleDb`, `ODBC`
  (`AccessProvider.cs:6-20`), and `AccessProviderAdapter.GetInstance` throws
  `InvalidOperationException("Unsupported provider type")` for anything else (`:75`).

The absent capability is a managed, cross-platform Access transport. `LibRed.Ado` 11.0.0-alpha.2
(MIT, `net11.0`-only, from the EntityFrameworkCore.Jet project) is one, and it is demonstrably
adequate rather than theoretically adequate — **measured**: it opened this repo's own
Microsoft-created `Data/TestData.mdb`, listed all 15 user tables through
`[INFORMATION_SCHEMA.TABLES]`, read every value of every row in all 15, and created and populated a
new table in the same file; the same run against the ACE-created `Data/issue_10_linqpad.accdb`
read 24/24 tables.

## P2 Success criteria

- SC-1 `Access.LibRed.Mdb` and `Access.LibRed.Accdb` resolve to working `IDataProvider`s and the Access test suite executes against both, with the per-test outcome recorded and the create-data step green. → TO-1, TO-8
- SC-2 The SQL emitted for a LibRed provider is identical to the OLE DB flavour's except at the three divergences this plan names, proven by the baselines diff rather than by inspection. → TO-2
- SC-3 The LibRed schema provider returns tables, columns (nullability, length, precision, scale, identity), primary-key columns and foreign-key **column pairs** for a database Microsoft's engine created. → TO-3
- SC-4 A type-coverage fixture exists for Access and runs on **all six** Access providers, with every per-provider divergence either passing or carrying a named, justified exclusion. → TO-4
- SC-5 The four existing Access providers are unchanged: no emitted-SQL delta, no flag delta, no mapping-schema delta, zero baseline changes under their four baseline directories, and the shared create-script still builds their databases. → TO-5, TO-9
- SC-6 `dotnet linq2db scaffold` produces a model from a LibRed connection string, and the committed CLI scaffold output for the new key regenerates with an empty `git diff`. → TO-6
- SC-7 The shipped `linq2db` package references no LibRed assembly: the adapter is reflection-loaded, and the portable TFMs still build. → TO-7

## P3 Constraints & anti-goals (M/L)

- **No behaviour change for OleDb/ODBC Access.** Their `SqlProviderFlags`, mapping schemas, builders,
  optimizer, member translators and schema providers are read-only on this branch except where a new
  branch arm is *added* beside an existing one. SC-5 is the gate.
- **`SqlProviderFlags` mirror the Access set.** The only divergence is
  `IsParameterOrderDependent = false` for LibRed, which is forced rather than chosen (P5 D-3). The
  user's explicit instruction: "A only".
- **No extended dialect.** LibRed accepts window functions, `CROSS`/`OUTER APPLY`, `FULL JOIN`,
  `OFFSET`/`FETCH`, `INTERSECT`/`EXCEPT` and `CASE` (measured), and **none of them is enabled here.**
  That is a fourth branch with its own baselines churn.
- **No `PackageReference` to `LibRed.*` in `Source/LinqToDB`.** The adapter is reflection-loaded like
  every other dynamic provider adapter. `Tests/Linq` gets a `net11.0`-conditional reference.
- **No LINQPad work.** The driver targets `net472;net8.0-windows7.0`; a net11.0-only dependency cannot
  load in it. `Source/LinqToDB.LINQPad/**` is not an edit-point.
- **No `CompatibilitySuppressions.xml` regeneration** — a release task, never a feature PR
  (`definition-of-done.md:14`). `PublicAPI.Unshipped.txt` entries **are** required (`:13`).
- **No reshaping of cross-cutting core** — SQL AST, `IDataProvider`, translator interfaces. Every
  change is additive inside `DataProvider/Access` + a new sibling adapter.
- **The test-database *containers* are created by Microsoft's engine** (user's instruction, 2026-09-19,
  scoped by the answer to U-18 on 2026-09-20): the committed `.mdb`/`.accdb` files are produced with
  ADOX/OLE DB, and the schema and data inside them are then written by LibRed through the normal
  create-data flow, exactly as for every other provider.
- **Unmergeable before .NET 11 RTM**, inherited from branch 1.

## P4 Unknowns (M/L)

Full measured detail for every probe-resolved row is in `findings.md` (beside this plan) with its raw logs; the rows below state the answer and the consequence.

- U-1 Is there a published LibRed package with a usable ADO.NET surface, and which version? — Yes, `LibRed.Ado` **11.0.0-alpha.2** on nuget.org, pulling `LibRed.Engine`/`LibRed.Core`/`LibRed.Sql`/`Antlr4.Runtime.Standard`, `net11.0` only, standard ADO.NET shapes plus `LibRedFactory.Instance`; alpha.3 exists only in the open PR CirrusRedOrg/EntityFrameworkCore.Jet#301 — resolved-by probe
- U-2 Does the `LibRedSqlMode.Compatible` / extended-mode split that EntityFrameworkCore.Jet#292 describes exist? — **No**: no such type in any of the four assemblies and the connection string accepts `Data Source=` and nothing else, so the extended dialect is always on and stage 1 is "same SQL because linq2db never emits the extended forms", not "same SQL because we asked for compatible mode" — resolved-by probe
- U-3 Parameter style? — **Named only**: `?` raises `NotSupportedException: Positional ('?') parameters are not supported yet`, while `@name` works, may repeat in one statement, binds with or without the `@` prefix, works in `TOP @n`, and survived 5 000 parameters in one `IN (…)` — resolved-by probe
- U-4 Can schema be discovered, given the driver implements no ADO schema API? — Yes by SQL: `GetSchema()`/`GetSchemaTable()`/`IDbColumnSchemaGenerator` are all unsupported, but bracket-quoted `[INFORMATION_SCHEMA.TABLES|COLUMNS|INDEXES|INDEX_COLUMNS|RELATIONS]` return rows (the dotted form fails to parse), `RELATIONS` carries no column pairs while `MSysRelationships` does, and views are absent from `TABLES` but present in `MSysObjects` as `Type = 5` — resolved-by probe
- U-5 Can LibRed read a file Microsoft's engine wrote? — Yes, both formats, read and write: 15/15 tables in this repo's `Data/TestData.mdb` and 24/24 in `Data/issue_10_linqpad.accdb`, every value read, plus a new table created and populated in each — resolved-by probe
- U-6 Which SQL that linq2db's Access builders actually emit does LibRed reject? — **Exactly one: `WITH OWNERACCESS OPTION`** (`AccessHints.cs:48`). The first pass of this row also named `CAST(expr AS Date)`, which was wrong: `AccessMemberTranslator.TranslateDateTimeTruncationToDate:180-186` builds a `SqlCastExpression`, but `AccessSqlExpressionConvertVisitor.ConvertConversion:411-444` rewrites every DateTime cast with `IsDateDataType(ToType, "Date")` into a null-guarded `DateValue` call before the builder ever sees it (`AccessSqlBuilderBase.cs:272` states outright that Access has no `CAST`), and `SELECT IIF([Ts] IS NOT NULL, DateValue([Ts]), NULL)` is measured to execute on LibRed — so the probe had replayed a string the pipeline does not produce. Everything else in the inventory executed on both `.accdb` and `.mdb` — resolved-by probe, corrected by critic O-1
- U-14 Does the GUID literal the mapping schema actually emits work? — **No, and it fails silently.** The base `AccessMappingSchema.cs:30` emits a **braced** `'{00000000-…}'`, which LibRed parses but matches **zero rows**, while the unbraced form matches (measured: `braced=0 unbraced=1` against a row whose `Uid` was set by parameter). A GUID filter would therefore return no rows rather than erroring — resolved-by probe, decided in D-6
- U-15 Can the reader tell a fixed-width `CHAR` from a `VARCHAR`/`MEMO`, as `AccessDataProvider.cs:69-83` requires? — **No**: `GetDataTypeName` returns CLR names (`char`, `varchar` and `longchar` columns all report `String`), so `SetCharField("CHAR")`/`SetCharField("DBTYPE_WCHAR")` can never match. And the padding is real: a `CHAR(10)` holding `'ab'` reads back as `'ab        '` (length 10). `[INFORMATION_SCHEMA.COLUMNS].DATA_TYPE` does carry the store type (`char`/`varchar`/`longchar`), but that is schema-time, not read-time — resolved-by probe, decided in D-13
- U-16 On a release (`full_run`) leg the suite runs on every TFM, while a CI job's provider list is TFM-independent by design (`DataProviders.json:39-42`); what happens on the net10.0 pass, where `LibRed.Ado` is not referenced (E-20)? — Without care the two configs would be listed with no assembly to load and `CreateDatabase` would go red on every release run; branch 1 also removed the per-entry `enable_fw_net*` switches, so the matrix cannot express "net11 only" either. The answer is not to gate the test code but to keep the names out of the provider lists for those TFMs — resolved-by scout, decided in D-12
- U-19 Does linq2db's own read path work over LibRed? — **Not without an override.** `ConvertFromDataReaderExpression.cs:178` calls `dataContext.IsDBNullAllowed(...)` for every column not forced to a null check, and `DataProviderBase.cs:307-311` implements it as an **unguarded** `reader.GetSchemaTable()` — which LibRed does not implement. So every materialized `SELECT` would throw before its first row while DDL/DML (which never materializes) stays green, exactly the shape that would let the create-data obligation pass and everything after it fail. Six providers already override this for the same class of reason (`FirebirdDataProvider.cs:144-147`, `SqlCeDataProvider.cs:161-164`, `YdbDataProvider.cs:124`, `SapHanaDataProvider.cs:275`, `ClickHouseDataProvider.cs:169-173`, `SQLiteDataProvider.cs:242`) — resolved-by code inspection, covered by E-5, and U-20 is what stops the next one of these from being found by CI
- U-20 What else on linq2db's own path is untested? — **Everything.** Every measurement behind this plan is raw ADO from `probe/` (beside this plan); no linq2db query has ever run over LibRed, which is how U-19 escaped five probe rounds. Before Phase A is called done, one `DataConnection` round-trip (`db.GetTable<Person>().ToList()`) must run against a LibRed connection, because a second defect of U-19's shape is more likely than not — resolved-by obligation TO-11
- U-21 Does `LibRedConnection.Database` / `.DataSource` behave, given `GetSchema` does not? — Neither throws; both return the full file path, so `AccessSchemaProviderBase.GetDatabaseName:16-24` (which falls back to `Path.GetFileNameWithoutExtension` only when the base returns *empty*) yields an absolute path as the scaffolded database name. **Not a LibRed-specific defect and not this branch's to fix** — the user's read (2026-09-20) is that the Microsoft providers behave the same way today, so LibRed inherits an existing behaviour rather than introducing one; it goes on the triage register in P13 to be confirmed against OLE DB/ODBC and filed on linq2db if it reproduces — resolved-by probe + user direction
- U-22 How does a missing table surface, for `AccessDmlService`'s table-not-found classification? — Not through `LibRedException` and not through a `Number`: a `SELECT` raises `LibRed.Sql.Binding.SqlBindException` with `Table 'X' does not exist.` (which the existing Access rule's `"does not exist"` substring match would already catch) while a `DROP TABLE` raises a plain `System.InvalidOperationException` with `DROP TABLE 'X': no such table.` (which it would **not**). E-11 must cover both shapes, and `DropTableTests` is the instrument — resolved-by probe
- U-18 Does the "Microsoft-created database" constraint mean the *container* or the *populated schema and data*? The **container**: `Access.sql:26-35` drops every table before recreating them, so the LibRed configs run the normal create-data flow and everything but the file header is LibRed-written; the user was shown that consequence together with the two alternatives (commit fully populated MS-written files and skip create-data, or add a separate MS-written read-only fixture) and answered "this is fine", i.e. the container-only reading — resolved-by user answer, 2026-09-20
- U-17 Does the bare `REFERENCES Person` form used outside the create script work? — **No.** `Tests/Base/TestBase.Identity.cs:36-37` re-adds `PersonDoctor`/`PersonPatient` after every identity reset using the column-list-free form, which is measured to fail on LibRed with the same `Foreign key on 'Parent' has 1 columns but references 0`; `ResetPersonIdentity`/`ResetAllTypesIdentity` are reached from 71 sites across 17 test files — resolved-by probe, covered by D-11
- U-7 Is a Microsoft Access engine installed here, so the committed test databases can be produced by MS code per D-7? — Yes: `Get-OdbcDriver` lists `Microsoft Access Driver (*.mdb, *.accdb)` in both 32- and 64-bit, and `New-Object -ComObject ADOX.Catalog` succeeds in a 64-bit process, which is what `AccessTools.CreateDatabase` needs (`AccessTools.cs:129`) — resolved-by probe
- U-8 Does `Data/Create Scripts/Access.sql` run end to end through LibRed? — Partly: replaying all 70 statements on the `GO` divider created all 15 tables, but 2 `ALTER TABLE … REFERENCES Person` statements fail because LibRed requires the referenced column list (fix measured to work → D-11) and 5 `CREATE Procedure` statements fail — action procedures with parameters, `UPDATE`/`DELETE` bodies, and `Scalar_DataReader` — while parameterised `SELECT` procedures all succeed (→ D-10) — resolved-by probe
- U-9 How must a GUID literal be written? — As a plain `'xxxxxxxx-…'` string, which compares equal to a `GUID` column; the OLE DB `{guid {…}}` form and the ODBC escape form both fail to parse, and a `Guid` parameter round-trips and reads back as `Guid` — resolved-by probe, chosen in D-6
- U-10 Do Access's bulk-copy caps (767 parameters / 64 000 chars, `AccessBulkCopy.cs:9,13`) hold? — They are conservative for LibRed (5 000 parameters / 38 934 chars executed fine) but harmless, so keeping them avoids a second code path for no observable benefit — resolved-by probe
- U-11 Does the "65th query fails" connection-pool defect that EntityFrameworkCore.Jet#301 fixes affect alpha.2 in our usage? — Did not reproduce (100 open/close cycles and 200 commands on one connection, both clean), which is not proof of absence under the parallel test lane — TO-1 is where it would surface — resolved-by probe
- U-12 Does `DataConnection`'s configuration lookup resolve `Access.LibRed.Mdb` with no new registration? — Yes: `DataConnection.Configuration.cs:183-192` matches exactly, then by `key + '.'` prefix ordered by descending key length, so any `Access.<Version>.<Flavour>` name resolves through the already-registered Access detector at `:197` — resolved-by scout, pinned by TO-1
- U-13 How much committed output does one CLI scaffold key cost? — Five templates and ~89 files / ~4 900 lines for an Access-shaped schema (the YDB precedent `c11b1045b` was 62 files / 3 344 insertions), with no automated staleness test: compilation plus a manual `git diff` at release-prep track 4.7 is the only gate — resolved-by scout, scoped in D-9

## P5 Decisions (M/L; rejected alternatives mandatory at L)

### D-1 — LibRed is a third `AccessProvider` flavour, not a new provider family

- **chosen:** add `AccessProvider.LibRed = 3` and two provider names, **`Access.LibRed.Mdb`** and
  **`Access.LibRed.Accdb`**, plus the alias `Access.LibRed` mirroring the existing `Access` /
  `Access.Odbc` alias pair. Six concrete data providers result from the same
  `(AccessVersion, AccessProvider)` matrix — `Mdb` maps to `AccessVersion.Jet`, `Accdb` to `Ace`.
- **rejected:** `Access.Jet.LibRed` / `Access.Ace.LibRed`, which is what the existing four names would
  suggest — the user's call (2026-09-20): for this transport the **file format** is the axis a user
  actually chooses, and the engine generation is an implementation detail of it. The consequence to
  carry: `AccessProviderDetector`'s configuration-string sniffing looks for the substrings `"Jet"` and
  `"Ace"` (`:53-56`), neither of which appears in the new names, so version detection for LibRed keys
  on the name or on `LibRedConnection.ServerVersion` — measured to return `Version4` for an `.mdb` and
  `Version12_2007` for an `.accdb`, which makes `DetectServerVersion` the natural route and a more
  direct one than the string sniffing the other flavours rely on.
- **rejected:** a standalone `ProviderName.LibRed` family with its own `LibRedDataProvider`,
  `LibRedSqlBuilder`, options record and detector — it duplicates `AccessSqlBuilderBase`,
  `AccessSqlOptimizer`, `AccessSqlExpressionConvertVisitor`, `AccessMappingSchema` and the whole
  member-translator tree, none of which is transport-specific, and it would make every
  `ProviderName.Access`-keyed `Sql.*` registration (16 sites in `Sql.cs`, plus
  `Linq/Expressions.cs:882,1118,1139`) miss.
- **rejected:** an `AccessOptions` flag instead of an enum member — the flavour selects the *adapter*,
  which is chosen in `AccessProviderAdapter.GetInstance(AccessProvider)` before options are visible.
- **why this:** the engine is Jet/ACE either way; only the ADO.NET transport differs, which is exactly
  what `AccessProvider` already models. Everything keyed on the `Access` config name keeps working
  through the mapping-schema chain rooted at `AccessMappingSchema` (config `"Access"`).
- **failure mode of the choice:** every binary `OleDb ? … : ODBC` branch in `AccessDataProvider`
  silently routes LibRed to the ODBC arm. There are six (`CreateSqlBuilder:104-109`,
  `GetSchemaProvider:118-123`, `GetQueryParameterNormalizer:125-130`, the reader-field split `:69-83`,
  `SetParameter:142`, `SetParameterType:174/209`) plus `AccessProviderDetector:118-124` and the 4-arm
  `MappingSchemaInstance.Get` switch. P6 converts each to a three-way switch; P7 carries them as rows.
  `LinqToDB.LINQPad/DatabaseProviders/AccessProvider.cs:96-105` indexes `_providers[isOleDb ? 0 : 1]`,
  which is why LINQPad stays an anti-goal rather than a silent edit.

### D-2 — The adapter is reflection-loaded, like every other dynamic provider adapter

- **chosen:** a new `LibRedProviderAdapter` under `Source/LinqToDB/Internal/DataProvider/`, sibling to
  `OleDbProviderAdapter` / `OdbcProviderAdapter`, implementing `IDynamicProviderAdapter` by reflecting
  over the `LibRed.Ado` assembly; a third private `AccessProviderAdapter` constructor consumes it.
- **rejected:** a `PackageReference` in `LinqToDB.csproj` — forbidden by P3, and impossible anyway:
  `LibRed.Ado` is `net11.0`-only while the library ships `net462`, `netstandard2.0`, `net10.0`, `net11.0`.
- **rejected:** a separate `linq2db.LibRed` package holding the adapter — no other provider does this,
  and it would need a new NuGet id, licence notices entry and release-notes line for a provider whose
  package surface is one type.
- **why this:** `LinqToDB.csproj` references no ADO driver at all; the reflection pattern is the
  codebase's answer to exactly this and needs no new build concept.
- **failure mode of the choice:** reflection failures surface at first use rather than at build time,
  and a LibRed API rename between alpha.2 and alpha.3 becomes a runtime `NullReferenceException`
  inside the adapter instead of a compile error. Mitigated by TO-1 running the whole suite, and by the
  adapter's surface being tiny (connection/command/parameter/reader/transaction types plus the static
  `CreateDatabase`/`DatabaseExists`/`DropDatabase`/`ClearPool` helpers).

### D-3 — LibRed inherits the base `@name` builder, and `IsParameterOrderDependent` is `false` for it

- **chosen:** `AccessLibRedSqlBuilder : AccessSqlBuilderBase` with **no** `Convert` override, so it
  keeps `AccessSqlBuilderBase.Convert`'s `@name` placeholders (`:166-169`); `GetQueryParameterNormalizer`
  returns the base (name-normalizing) implementation as for OLE DB; and the ctor sets
  `IsParameterOrderDependent = false` when `Provider == LibRed`.
- **rejected:** reusing `AccessODBCSqlBuilder` — it overrides `Convert` to emit `?`
  (`AccessODBCSqlBuilder.cs:29-38`), which LibRed rejects outright (U-3).
- **rejected:** leaving `IsParameterOrderDependent = true` for LibRed "to stay identical to Access" —
  the flag exists because OLE DB binds `@name` positionally (`AccessDataProvider.cs:52-55`) and ODBC
  has no names at all. LibRed binds by name (measured: the same `@p` referenced twice in one statement
  resolves to one parameter), so `true` would be a false statement about the driver. It is also the
  one flag whose value is forced rather than chosen, which is why it survives the "A only" constraint.
- **why this:** it is the smallest correct configuration — one new builder class whose only override
  is `GetProviderTypeName`, and one flag whose value the driver dictates.
- **failure mode of the choice:** `IsParameterOrderDependent = false` changes parameter **naming** in
  emitted SQL relative to the ODBC flavour and therefore produces LibRed-specific baselines from day
  one; if the normalizer produces a name LibRed's parser rejects (e.g. a leading digit after
  normalization), it fails at execution, not at build. TO-1 is the detector.

### D-4 — The schema provider reads metadata with SQL, modelled on `SQLiteSchemaProvider`

- **chosen:** `AccessLibRedSchemaProvider : AccessSchemaProviderBase`, issuing
  `dataConnection.Query<T>` against `[INFORMATION_SCHEMA.TABLES]` (+ `MSysObjects` `Type = 5` for
  views), `[INFORMATION_SCHEMA.COLUMNS]`, `[INFORMATION_SCHEMA.INDEXES]` ⋈
  `[INFORMATION_SCHEMA.INDEX_COLUMNS]` for primary keys, and `MSysRelationships` for foreign-key
  column pairs; `GetDataTypes` is overridden with a static list, because
  `SchemaProviderBase.GetDataTypes` (`:561-575`) calls `DbConnection.GetSchema("DataTypes")`, which
  LibRed does not implement.
- **rejected:** deriving columns from `SELECT * FROM t WHERE 1 = 0` reader metadata — measured to give
  names and CLR types only: no nullability, no length/precision/scale, no identity, and
  `GetDataTypeName` returns `Int32`/`Decimal` rather than the Access store type.
- **rejected:** reusing `AccessOleDbSchemaProvider`'s `DataRow`-shaped code — it is built entirely on
  `GetSchema`/`GetOleDbSchemaTable`, neither of which exists here.
- **rejected:** `[INFORMATION_SCHEMA.RELATIONS]` as the FK source — it names the two tables but carries
  no column pairs, so it cannot fill `ForeignKeyInfo.ThisColumn`/`OtherColumn`.
- **why this:** it is the only route that fills every `ColumnInfo` field the scaffolder needs, and
  `AccessSchemaProviderBase.GetDataType` (`:39-78`) already maps exactly the store-type strings
  `[INFORMATION_SCHEMA.COLUMNS].DATA_TYPE` returns (`counter`, `varchar`, `longbinary`, …).
- **failure mode of the choice:** `TableID` is the join key across `GetTables`/`GetColumns`/
  `GetPrimaryKeys`/`GetForeignKeys` (`SchemaProviderBase.cs:153-161,200-201`, `StringComparer.Ordinal`)
  and must be composed identically in all four; a mismatch silently drops columns or FKs rather than
  failing. It also diverges from `AccessOleDbSchemaProvider`'s `catalog.schema.name` composition, so a
  scaffolded model's generated IDs differ between flavours. TO-3 pins the composition.

### D-5 — `WITH OWNERACCESS OPTION` is declared unsupported on LibRed; no member translator is added

- **chosen:** leave every member translator alone; the only construct LibRed rejects is the
  `AccessHints.WithOwnerAccessOption` hint, so its two tests are narrowed away from LibRed with a
  comment naming the parse error.
- **rejected (and it was this plan's first answer):** a LibRed member-translator overriding date
  truncation to emit `DateValue` instead of `CAST(expr AS Date)` — **there is no such problem.**
  `AccessSqlExpressionConvertVisitor.ConvertConversion:411-444` already turns a DateTime→`Date` cast
  into a null-guarded `DateValue` call for *every* Access flavour, so `CAST(… AS Date)` never reaches
  the SQL text; the earlier probe replayed a translator-level shape rather than builder output. That
  override would have been an edit-point for a non-existent defect, and writing it as a bare
  `DateValue` call would have **dropped the visitor's `IIF(x IS NOT NULL, …, NULL)` guard** and created
  a real divergence where none existed.
- **rejected:** making the hint flavour-aware (emitting nothing for LibRed) — a query hint that
  silently does nothing is worse than a hint that is not offered; and `AccessHints` is public surface
  keyed on the base `Access` config name (`AccessHints.cs:48`), so scoping it per flavour is a public
  behaviour change for a capability LibRed does not have.
- **why this:** the measured rejection set is one construct, and it is a hint the user asks for
  explicitly rather than something the engine emits on its own.
- **failure mode of the choice:** a user calling `.WithOwnerAccessOption()` against LibRed gets a
  `SqlParseException` at execution rather than a compile-time or capability error. P10 records it.

### D-6 — GUID literals are emitted unbraced, overriding the base mapping schema

- **chosen:** a LibRed mapping-schema layer overriding `SetValueToSqlConverter(typeof(Guid), …)` to
  emit `'xxxxxxxx-xxxx-…'` without braces.
- **rejected:** inheriting the base `AccessMappingSchema.cs:30` form `'{0:B}'`, which is what the ODBC
  leaves use — **measured to be silently wrong**: LibRed parses the braced string and matches **zero
  rows** (`braced=0 unbraced=1` against a row whose GUID was written by parameter). This is the worst
  failure shape available: no exception, just an empty result, so it is precisely what the override
  exists to prevent.
- **rejected:** the OLE DB `{guid {…}}` form — measured `SqlParseException: token recognition error at: '{g'`.
- **rejected:** the ODBC strategy of forcing every GUID to a parameter
  (`AccessODBCSqlBuilder.cs:52-77`) — it works, but it is a workaround for an ODBC escape-syntax
  conflict that does not exist here, and it makes every GUID-bearing query parameterized, diverging
  the baselines further than necessary.
- **why this:** measured to compare equal against a `GUID` column, and it keeps literal-mode tests
  (`InlineParameters = true`, which `TypeTestsBase` exercises) on the literal path.
- **failure mode of the choice:** if the engine's string→GUID coercion is lenient in one direction
  only (comparison works, `INSERT … VALUES ('…')` does not), literal inserts break while filters pass.
  TO-4's `Guid` case covers both directions, since `TestType` inserts by literal and filters by literal.

### D-12 — The LibRed configs are listed only in the net11 provider lists — no `#if` in test code

- **chosen (user's call, 2026-09-20):** *"just don't add the new provider to the test config for
  unsupported TFMs."* The two names appear only in the **net11 provider lists** — locally the `NET110`
  section of `UserDataProviders.json.template` (`:334-338`) and not the `NETFX` / `NET100` ones; on CI
  the LibRed job config declares its providers under a TFM-scoped section rather than the shared
  `Azure.TestJob` one, because that shared section is TFM-independent by design
  (`DataProviders.json:39-42`) and is exactly what would put the configs in front of a net10.0
  `full_run` pass. `TestProvName` and every fixture stay plain C# with no conditional compilation.
- **rejected:** `#if NET11_0_OR_GREATER` around the names in `TestProvName` (this plan's previous
  answer) — it expresses an environment fact as a compile-time one, it has to be applied in two places
  because the include- and exclude-shaped data-source attributes filter differently
  (`IncludeDataSourcesAttribute.cs:24` intersects `UserProviders` only, while
  `DataSourcesAttribute.cs:24` also filters through `TestConfiguration.Providers`), and a future
  LibRed-only fixture added without the wrapper silently reopens the hole.
- **rejected:** a per-entry TFM switch in `test-matrix.yml` — branch 1 deliberately deleted the
  `enable_fw_net80/90/100` booleans after measuring that all 25 entries set them identically, so
  re-introducing one undoes that simplification for a single leg.
- **why this:** the provider list *is* the test environment's own statement of what exists, so a
  provider that cannot load on a TFM simply is not in that TFM's list. Nothing in the test code has to
  know why.
- **failure mode of the choice:** the CI half depends on the LibRed job config not using the shared
  TFM-independent section, which is the convention every other job follows — so it is a deviation a
  later edit could silently undo, and nothing in `Build/Azure` would flag it. TO-10 is the guard, and
  its discriminating arm is a net10.0 run of the leg's own config.

### D-13 — LibRed maps `char` but does not trim `CHAR` padding

- **chosen:** register `SetCharFieldToType<char>("String", DataTools.GetCharExpression)` for LibRed and
  **not** `SetCharField("String", TrimEnd)`.
- **rejected:** mirroring OLE DB/ODBC with `SetCharField("CHAR"/"DBTYPE_WCHAR", TrimEnd)` — measured
  impossible: LibRed's `GetDataTypeName` returns CLR names, so `char`, `varchar` and `longchar`
  columns all report `String` and no type-name key can select the fixed-width one.
- **rejected:** registering the trim on `"String"` — it would strip significant trailing spaces from
  every `VARCHAR`/`MEMO` read, turning a cosmetic divergence into data loss.
- **why this:** the `char`-typed mapping is unambiguous (a single character cannot have meaningful
  padding), while the `string`-typed one cannot be decided from the information the reader gives.
- **failure mode of the choice:** a `CHAR(n)` column read into `string` comes back padded on LibRed and
  trimmed on the other four flavours — measured (`CHAR(10)` holding `'ab'` reads as `'ab        '`).
  That is a real behavioural divergence, and TO-4's `CHAR` case is where it surfaces; if it is judged
  unacceptable the fix belongs upstream (LibRed reporting store types from `GetDataTypeName`), which
  P10 records as a follow-up rather than a workaround here.

### D-7 — Test databases are Microsoft-created and committed; LibRed never writes the container

- **chosen:** two new committed files, `Data/TestData.LibRed.mdb` (Jet 4) and
  `Data/TestData.LibRed.accdb` (ACE), produced by `AccessTools.CreateDatabase` (ADOX/OLE DB). The test
  configs copy them like every other file database, and the normal `CreateData` flow then builds the
  schema and seeds the data through LibRed at test time.
- **rejected:** creating the files at test time with `LibRedConnection.CreateDatabase` — the user's
  explicit instruction, with the reason: a file LibRed wrote is not evidence that LibRed works against
  files the world actually has, and it couples the whole suite to LibRed's file writer.
- **rejected:** committing *populated* MS-written databases and skipping create-data for LibRed — it
  would preserve the MS-written-schema property for the whole suite, but pins the binaries to the
  current create scripts and has to be regenerated by hand whenever they change. Put to the user with
  that trade-off (U-18); the container-only reading is their call.
- **rejected:** sharing the existing `Data/TestData.mdb` — provider lanes run in parallel and each
  file-database config already gets its own file (`TestData.mdb` vs `TestData.ODBC.mdb`).
- **why this:** it makes the branch's central claim ("linq2db can talk to real Access files without
  Microsoft's drivers") the thing the suite actually tests.
- **failure mode of the choice:** producing the files needs an ACE/Jet install on whoever regenerates
  them (U-7), which is exactly the dependency the provider exists to remove — so the *artifacts* stay
  Windows-produced even though the *tests* are not. Accepted: they are committed binaries regenerated
  about never, and the alternative gives up the MS-written-file property.

### D-8 — One type-coverage fixture, shared by all six Access providers

- **chosen:** a new `Tests/Linq/DataProvider/Types/AccessTypeTests.cs : TypeTestsBase` parameterised
  with `[IncludeDataSources(TestProvName.AllAccess)]`, where `AllAccess` is extended to include the two
  LibRed names. One test per Access storage type, asserting create-table, parameter, literal and all
  bulk-copy modes via `TypeTestsBase.TestType`.
- **rejected:** a LibRed-only fixture — the user's instruction is explicit ("targeting all access
  providers — both new and existing"), and a LibRed-only fixture cannot show a divergence *between*
  flavours, which is the whole diagnostic value.
- **rejected:** extending `Tests/Linq/DataProvider/AccessTests.cs` instead — that fixture is
  behaviour-shaped; `TypeTestsBase` already owns the per-type matrix (nullable/non-nullable, parameter
  vs literal, four bulk-copy modes) and is where every other provider's type coverage lives.
- **why this:** Access is the only major provider with no `Types/` fixture, and adding a transport is
  the moment the gap becomes expensive — without it, a LibRed type defect is invisible until a user
  reports it.
- **failure mode of the choice:** it will fail on the *existing* providers too, on types nobody has
  ever asserted, and those failures are pre-existing defects arriving in a branch about something else.
  The disposition rule is in P10: an existing-flavour failure is recorded and gated, not fixed here.

### D-9 — One CLI scaffold key, and a Linux-only CI leg

- **chosen:** a single new CLI scaffold key (`AccessLibRed`, over the `.accdb`), added to all five
  `Cli/*.tt` templates and to `release-test-cli-scaffold.ps1`'s matrix; and one new Linux-only
  `test-matrix.yml` entry under the `[access.all]` filter.
- **rejected:** two keys (one per file format) — measured cost is ~89 files / ~4 900 lines of committed
  generated output per key (U-13); the second key would duplicate ~4 900 lines to prove the scaffolder
  behaves the same against a file format whose schema surface is identical.
- **rejected:** folding the LibRed tests into an existing fast leg's config (`sqlite.json`/`duckdb.json`)
  — it would make `[duckdb.all]` run Access tests, which breaks the filter's meaning.
- **why this:** one key exercises the CLI path end to end; a dedicated leg keeps `[access.all]` honest
  and gives Access its first Linux coverage, which is the capability being added.
- **failure mode of the choice:** the Linux leg is the only place the new provider runs on CI by
  default, so a Windows-specific LibRed defect (path casing, file locking) would be invisible. The
  Windows Access legs can be extended later; noted in P10 rather than solved here.

### D-10 — Stored procedures are out of scope for LibRed, by `SKIP` marker and test exclusion

- **chosen:** wrap the five unsupported `CREATE Procedure` statements in `Access.sql` in the script's
  own `SKIP <config> BEGIN/END` markers for the two LibRed configs (`CreateData.RunScript` strips them,
  `CreateData.cs:39-56`), exclude `AccessProceduresTests` (13 Access-only tests) for LibRed, and have
  `AccessLibRedSchemaProvider` inherit `SchemaProviderBase`'s `GetProcedures` default (returns `null`).
- **rejected:** keeping the statements and tolerating the failures — `RunScript` executes statements
  through `db.Execute` and a create-data failure fails the `CreateDatabase` test, which gates the whole
  provider's lane (`TestBase.AwaitDatabaseReady`, `:186-197`).
- **rejected:** rewriting the procedures into forms LibRed accepts — it would change what the other four
  flavours test, and the supported subset (parameterless action queries) is not what the tests exercise.
- **why this:** the script already has the mechanism, it is per-config, and it leaves the other four
  flavours byte-identical.
- **failure mode of the choice:** LibRed silently ships with no procedure support and nothing in the
  suite says so — a user scaffolding a database with stored queries gets a model with none. P10 records
  it; the schema provider returning `null` rather than throwing is what makes it quiet.

### D-11 — The shared create-script gains explicit FK referenced columns

- **chosen:** `Access.sql:88-93` become `… REFERENCES Person (PersonID) …`.
- **rejected:** a LibRed-specific copy of the script — `CreateData` resolves the script by provider
  family name (`"Access"`), so a second file means a second `RunScript` arm and two files to keep in
  sync for one token.
- **rejected:** `SKIP`-ping the FKs for LibRed — the `Doctor`→`Person` FK is exactly what TO-3 uses to
  prove the schema provider reads foreign keys, and `TestBase.Identity.cs:30,155` drops and re-adds
  these two constraints during identity resets.
- **not a risk, and the repo already says so:** the same script writes
  `REFERENCES RelationsTable(ID1, ID2)` at `:383,385` and has done so on all four Microsoft flavours,
  so the explicit form is proven against ACE and Jet by the existing suite rather than by inference.
- **why this:** it is standard SQL that Access accepts, it is one token per statement, and it makes the
  script say what it means.
- **failure mode of the choice:** it edits a file all four existing flavours execute, so a mistake
  breaks every Access leg rather than just the new one. TO-5 is the guard, and it must run *before*
  Phase B is called done rather than at the end.

## P6 Edit-points

**Phase A — provider core**

- E-1 `Source/LinqToDB/DataProvider/Access/AccessProvider.cs:6` — add `LibRed` member with XML doc.
- E-2 `Source/LinqToDB/ProviderName.cs:29-59` — add `AccessLibRed` (`"Access.LibRed"`),
  `AccessLibRedMdb` (`"Access.LibRed.Mdb"`), `AccessLibRedAccdb` (`"Access.LibRed.Accdb"`) consts + docs.
- E-3 `Source/LinqToDB/Internal/DataProvider/LibRedProviderAdapter.cs` (**new**) — `IDynamicProviderAdapter`
  over `LibRed.Ado` by reflection: connection/command/parameter/reader/transaction types, connection
  factory, and the static `CreateDatabase`/`DatabaseExists`/`DropDatabase`/`ClearPool` helpers.
- E-4 `Source/LinqToDB/Internal/DataProvider/Access/AccessProviderAdapter.cs:21-47,61-99` — third
  private ctor taking `LibRedProviderAdapter`, a third cached singleton, `GetInstance` arm.
- E-5 `Source/LinqToDB/Internal/DataProvider/Access/AccessDataProvider.cs:23-26,37-88,95-130,142,174,209,290-308`
  — two new `sealed` provider classes; three-way `CreateSqlBuilder` / `GetSchemaProvider` /
  `GetQueryParameterNormalizer`; `IsParameterOrderDependent` per flavour (D-3); the reader-field arm per
  D-13 (and **not** the ODBC `SetToType<sbyte,int>("INTEGER")` family at `:79-82`, which is keyed the
  same way and equally unmatchable); `SetParameter`/`SetParameterType` arms;
  `MappingSchemaInstance.Get` gains two tuple arms.
- E-5a `Source/LinqToDB/Internal/DataProvider/Access/AccessDataProvider.cs` — **`IsDBNullAllowed`
  override returning `true` when `Provider == LibRed`** (U-19). Without it every materialized `SELECT`
  throws inside `DataProviderBase.cs:307-311`'s unguarded `GetSchemaTable()`. Shape follows
  `ClickHouseDataProvider.cs:169-173` (per-flavour) rather than Firebird's unconditional `true`.
- E-6 `Source/LinqToDB/Internal/DataProvider/Access/AccessLibRedSqlBuilder.cs` (**new**) —
  `AccessSqlBuilderBase` subclass; `GetProviderTypeName` via `DbParameter.DbType`.
- E-7 `Source/LinqToDB/Internal/DataProvider/Access/AccessLibRedSchemaProvider.cs` (**new**) — D-4, plus
  a `GetDataTypes` override (the base calls `GetSchema("DataTypes")`, which LibRed does not implement).
  **No `GetDatabaseName` override** — see U-21.
- E-11a `Source/LinqToDB/Internal/DataProvider/Access/AccessDmlService.cs` — table-not-found for LibRed
  covers **both** measured shapes (U-22): `SqlBindException` "… does not exist." and a plain
  `InvalidOperationException` "… no such table." from `DROP TABLE`.
- E-9 `Source/LinqToDB/Internal/DataProvider/Access/AccessMappingSchema.cs:104-126` — an
  `AccessLibRedMappingSchema` intermediate overriding the `Guid` value-to-SQL converter to the unbraced
  form (D-6) + two leaf schemas. *(No member translator is added — see D-5; there is no `E-8`.)*
- E-10 `Source/LinqToDB/Internal/DataProvider/Access/AccessProviderDetector.cs:13-163` — two `Lazy`
  fields, `GetDataProvider` tuple arms, `DetectProvider` provider-name arms, `CreateConnection` arm,
  connection-string/configuration-string markers for LibRed.
- E-11 `Source/LinqToDB/Internal/DataProvider/Access/AccessDmlService.cs:12-23` — `LibRedException`
  table-not-found classification (reflection on `Number`, or message match).
- E-12 `Source/LinqToDB/DataProvider/Access/AccessFactory.cs:15-20` — assembly-name → `AccessProvider.LibRed`.
- E-13 `Source/LinqToDB/PublicAPI/PublicAPI.Unshipped.txt` — the flat file (the additions are
  TFM-unconditional), covering **every** new public type and member, not just the enum member and the
  three consts: `LinqToDB.Internal.*` types are tracked too (`PublicAPI.Shipped.txt:1937-1971` already
  carries `AccessODBCSchemaProvider`, `AccessOleDbSqlBuilder`, `AccessJetMemberTranslator` and their
  nested classes), so E-3, E-6, E-7 and E-9's public classes each need their lines or the Release
  build fails RS0016.

**Phase B — test environment**

- E-14 `Tests/Base/TestProvName.cs:194-198` — add `AllAccessLibRed` (`Access.LibRed.Mdb`,
  `Access.LibRed.Accdb`) and extend `AllAccess`; plain constants, no conditional compilation (D-12).
  (There is no `AllAccessAce` constant today and this branch does not invent one; `AllAccessJet` is
  engine-shaped and the new names are format-shaped, so they do **not** join it.)
- E-15 `DataProviders.json:67-74,294-297` — four new entries (`Access.LibRed.Mdb`, `.Data`,
  `Access.LibRed.Accdb`, `.Data`) + the `All.Providers` list.
- E-16 `UserDataProviders.json.template:334-338,738-760` — the two names go in the **`NET110` provider
  list only** (not `NETFX` at `:79-83`, not `NET100` at `:210-214`), plus the connection-string
  templates (D-12).
- E-17 `Tests/Base/TestUtils.cs:159-162` — database-name arm for the two LibRed configs.
- E-18 `Data/Create Scripts/Access.sql:88-93` — explicit FK referenced columns (D-11); and `SKIP`
  markers around the five unsupported `CREATE Procedure` statements (D-10).
- E-18a `Tests/Base/TestBase.Identity.cs:36-37` — the two `ALTER TABLE … REFERENCES Person` statements
  the identity reset re-adds carry the same column-list-free form and are measured to fail on LibRed
  (U-17); they take the explicit column list too, which is the same behaviour-preservation question as
  D-11 and is covered by the same obligation.
- E-19 `Data/TestData.LibRed.mdb`, `Data/TestData.LibRed.accdb` (**new binaries**, D-7).
- E-20 `Tests/Linq/Tests.csproj` — `net11.0`-conditional `PackageReference` to `LibRed.Ado`, plus its
  `Directory.Packages.props` version entry.
- E-21 `Tests/Linq/TestsInitialization.cs:312-323` — `SetupAccessKeepAlive` stays OLE DB/ODBC-only;
  the edit is a comment stating LibRed is excluded because the reason for the anchor (ACE ODBC has no
  pooling and leaks three OS handles per connect) does not apply to a managed in-process engine.
- E-21a `Tests/Linq/Create/CreateData.cs:269-272` — a LibRed arm in the Access branch of
  `CreateDatabase`, mirroring the OLE DB/ODBC pair (script + `.Data` script + the per-provider action
  that inserts the `AllTypes` row).
- E-21b `Tests/Base/ProviderNameHelpers.cs:45` — `IsUsePositionalParameters` currently returns `true`
  for every Access provider; LibRed must be excluded (D-3: it has no positional parameters).

**Phase C — type coverage**

- E-22 `Tests/Linq/DataProvider/Types/AccessTypeTests.cs` (**new**) — D-8.
- E-22a `Tests/Linq/DataProvider/AccessProceduresTests.cs` — narrow its 13 `IncludeDataSources`
  parameters from `AllAccess` to the OLE DB + ODBC pair, with a comment naming the LibRed limitation (D-10).
- E-22b `Tests/Linq/Extensions/AccessTests.cs:32` — narrow `WithOwnerAccessOptionTest` the same way,
  naming the `WITH OWNERACCESS OPTION` parse error (D-5).

**Phase D — CI**

- E-23 `Build/Azure/configs/access.libred.json` (**new**) + `linq2db.slnx:53-56` entry — its provider
  list is declared under a **TFM-scoped** section rather than the shared TFM-independent
  `Azure.TestJob` one every other job uses, so a `full_run` net10.0 pass does not see the configs
  (D-12). The deviation is deliberate and needs a one-line comment saying why.
- E-24 `Build/Azure/pipelines/templates/test-matrix.yml` — one Linux-only entry, `filters: '[all][access.all]'`.
- E-25 `Build/Azure/README.md:116-119,199-202` — the provider/category tables.

**Phase E — CLI + scaffold**

- E-26 `Source/LinqToDB.CLI/CommandLine/Commands/Scaffold/ScaffoldCommand.Execute.cs:319-372` — LibRed
  arm in the Access flavour resolution (connection-string sniffing, secondary-provider pairing rules).
- E-27 `Source/LinqToDB.CLI/CommandLine/Commands/Mcp/McpInfoTool.cs:44` — the hard-coded six-name list.
- E-28 `Source/LinqToDB.Scaffold/Schema/LegacySchemaProvider.cs:63-64` — the two flavour flags.
- E-29 `Tests/Tests.T4/Cli/{All,Default,Fluent,NoMetadata,T4}.tt` + `CLI.ttinclude:13-17` — one row each
  + the LibRed connection string.
- E-30 `Tests/Tests.T4/Cli/{All,Default,Fluent,NoMetadata,T4}/AccessLibRed/**` (**new generated output**).
- E-31 `.claude/scripts/release-test-cli-scaffold.ps1:115,132-137,206-235` — matrix row, connection-string
  variable, `$expectedDbs` entry. *(corpus edit — committed to the agents repo, not the linq2db branch)*

## P7 Impact map (M/L)

Searched in this worktree (branch base `77800f967`), never in the primary clone. Patterns are named per row; the four scout sweeps that produced them are recorded in the session, and the two largest are `AccessProvider\.(OleDb|ODBC)` over `Source/` (24 hits / 7 files) and `TestProvName\.AllAccess` over `Tests/` (644 hits / 132 files).

- `Source/LinqToDB/Internal/DataProvider/Access/AccessDataProvider.cs:104-109,118-123,125-130,69-83,142,174,209` — six binary `Provider == AccessProvider.OleDb ? … : …` branches; a third enum member silently routes to the **ODBC** arm in every one — covered by E-5
- `Source/LinqToDB/Internal/DataProvider/Access/AccessDataProvider.cs:297-305` — `MappingSchemaInstance.Get` is a 4-arm `(version, provider)` switch ending in `throw new InvalidOperationException()`, so a LibRed provider throws at construction until both arms exist — covered by E-5, E-9
- `Source/LinqToDB/Internal/DataProvider/Access/AccessProviderAdapter.cs:69-99` — `GetInstance` throws `"Unsupported provider type"` on an unknown member — covered by E-4
- `Source/LinqToDB/Internal/DataProvider/Access/AccessProviderDetector.cs:76-80` — the `(provider, version)` switch's `_` arm silently returns the **Jet OLE DB** provider, so a mis-wired LibRed request degrades to OLE DB instead of failing — covered by E-10
- `Source/LinqToDB/Internal/DataProvider/Access/AccessProviderDetector.cs:29-39,131-141` — connection-string markers (`Microsoft.ACE.OLEDB`, `Microsoft.Jet.OLEDB`, `(*.mdb, *.accdb)`, `(*.mdb)`); a LibRed string is `Data Source=<file>` with no discriminating token, so auto-detection from the string alone is impossible — covered by E-10, residual adjudicated in P10
- `Source/LinqToDB/Internal/DataProvider/Access/AccessProviderDetector.cs:128` — `if (provider is ODBC or OleDb) return provider;` is the early-out for an explicitly requested flavour, so an explicit `AccessProvider.LibRed` falls through to the assembly-probe fallback at `:160` and silently resolves to ODBC or OLE DB — this is D-1's failure mode landing inside the detector — covered by E-10
- `Source/LinqToDB/Internal/DataProvider/Access/AccessProviderDetector.cs:152-158` — the configuration-string path matches the substrings `"Access.Odbc"` / `"Access.OleDb"`, **neither of which matches a versioned name** either (`"Access.Jet.Odbc".Contains("Access.Odbc")` is false); those resolve through the connection-string tokens at `:29-39,131-141`, which a `Data Source=<file>` string does not carry, and the in-file precedent for a bare token is the `"Jet"`/`"Ace"` test at `:53-56`. So the marker E-10 adds must be the bare `"LibRed"`, or E-15 must give the LibRed JSON entries a `"Provider"` key so the name switches at `:41-47`/`:143-150` take it first; as written neither fires and `TestConfiguration.cs:121-122` (which registers an empty `ProviderName`) lands the request on `:160` — covered by E-10, pinned by TO-8
- `Source/LinqToDB/Internal/DataProvider/Access/AccessProviderDetector.cs:84-116` — `DetectServerVersion` probes the OLE DB then the ODBC adapter and returns `null` if both throw; for LibRed the version is readable from `LibRedConnection.ServerVersion` (measured: `Version4` / `Version12_2007`) — covered by E-10
- `Source/LinqToDB/Data/DataConnection.Configuration.cs:183-192,197` — configuration-name resolution is exact-then-`key + '.'`-prefix, longest key first, with the Access detector registered once at `:197`; detectors run first, so the prefix fallback is not the path a test config actually takes — out-of-scope for an edit, but it is why E-10's marker is load-bearing rather than belt-and-braces
- `Source/LinqToDB/Internal/DataProvider/DataProviderBase.cs:307-311` ↔ `Source/LinqToDB/Internal/Expressions/ConvertFromDataReaderExpression.cs:178` — `IsDBNullAllowed` is an **unguarded** `reader.GetSchemaTable()` and is called for every column not forced to a null check, so on a driver that does not implement it *every materialized query* throws before its first row while DDL/DML stays green; searched `override bool\? IsDBNullAllowed` across `Source/` — six providers already override it (Firebird `:144`, SqlCe `:161`, Ydb `:124`, SAP HANA `:275`, ClickHouse `:169`, SQLite `:242`), none of them Access — covered by E-5a
- `Tests/Base/Attributes/IncludeDataSourcesAttribute.cs:24` — intersects the attribute's own provider list with `UserProviders` and **not** with `TestConfiguration.Providers`, unlike the exclude-shaped `DataSourcesAttribute.cs:24` (`TestConfiguration.cs:237-243` documents the asymmetry); both paths ultimately read `UserProviders`, which is why D-12 solves the TFM problem in the provider lists — the one place both selection paths agree on — rather than in test code — covered by E-16 and E-23
- `Source/LinqToDB/Sql/Sql.cs` (16 `PN.Access` sites), `Source/LinqToDB/Linq/Expressions.cs:882,1118,1139`, `Sql.DateOnly.cs:66`, `Sql.DateTime.cs`, `Sql.DateTimeOffset.cs` — searched `PN\.Access|ProviderName\.Access\b`; all are keyed on the **base** `Access` config name and reached through the mapping-schema chain, so a new leaf schema inherits them provided E-9 roots the leaves in `AccessMappingSchema` — out-of-scope
- `Source/LinqToDB/DataProvider/Access/AccessHints.cs:48` — `[Sql.QueryExtension(ProviderName.Access, …)]` means the `WITH OWNERACCESS OPTION` hint reaches LibRed too and raises `SqlParseException` — deferred: D-5 excludes the hint tests for LibRed rather than making the hint flavour-aware
- `Source/LinqToDB/DataProvider/Access/AccessTools.cs:65-90,103-124` — `CreateDatabase` is ADOX/OLE DB only and hard-codes the two Microsoft provider strings, while `GetDataProvider` and the three `CreateDataConnection` overloads already take an `AccessProvider` and need no signature change — deferred: D-7 does not need a LibRed `CreateDatabase`
- `Source/LinqToDB/DataProvider/Access/AccessFactory.cs:15-27` — maps a `.config` `<dataProvider>` assembly name to a flavour; with no arm a LibRed `app.config` entry silently resolves to `AutoDetect` — covered by E-12
- `Source/LinqToDB.Scaffold/Schema/LegacySchemaProvider.cs:63-64` — `_isAccessOleDb`/`_isAccessOdbc` drive per-flavour schema fix-ups and LibRed matches neither, which is correct but must be stated rather than inherited by accident — covered by E-28
- `Source/LinqToDB.Scaffold/Schema/MergedAccessSchemaProvider.cs:10,16-20` — two-flavour by construction (`(oleDbSchema, odbcSchema)`); LibRed needs no merge, and the CLI only constructs it when a secondary connection is supplied (`ScaffoldCommand.Execute.cs:136`) — out-of-scope, provided E-26 never requests a secondary for LibRed
- `Source/LinqToDB.CLI/CommandLine/Commands/Scaffold/ScaffoldCommand.Execute.cs:319-372` — the `case ProviderName.Access:` block sniffs Jet, guards 32-bit Jet, decides `isOleDb`, and **requires** primary/secondary to use different transports at `:347-354` — covered by E-26
- `Source/LinqToDB.CLI/CommandLine/Commands/Mcp/McpInfoTool.cs:44` — a hard-coded six-name literal array, not prefix-tolerant — covered by E-27
- `Source/LinqToDB.CLI/CommandLine/Commands/Connection/ProviderDialectCatalog.cs:26,32-36` — prefix-tolerant `IsProvider(name, "Access")`, so `Access.*.LibRed` already maps to "Microsoft Access SQL" — out-of-scope
- `Source/LinqToDB.LINQPad/DatabaseProviders/AccessProvider.cs:17-21,96-105,107-113` — a two-element `_providers` list indexed as `[isOleDb ? 0 : 1]` plus a binary `GetProviderFactory`; a third entry here would break the index arithmetic — out-of-scope: P3 excludes LINQPad (a net11.0-only dependency cannot load in a `net472;net8.0-windows7.0` host) and untouched code cannot break
- `Source/LinqToDB.EntityFrameworkCore/LinqToDBForEFToolsImplDefault.cs:254,276,299` — maps EntityFrameworkCore.Jet's types to the `ProviderName.Access` **alias**, so the EF bridge keeps resolving through the detector — out-of-scope
- `Source/LinqToDB/PublicAPI/PublicAPI.Shipped.txt:656-659,662-665,8947-8952` — `AccessProvider` members carry explicit values (`AutoDetect = 0`, `OleDb = 1`, `ODBC = 2`), so appending `LibRed = 3` adds one line and rewrites none; the four per-TFM files carry one Access line each (`AccessOptions.<Clone>$()`), so nothing TFM-conditional is added — covered by E-13
- `Build/Azure/pipelines/templates/test-matrix.yml:17,38,176-177,372-488` — four Access legs, three `x86: true`; `.github/workflows/tests.yml:181-208` derives its matrix from this file and gates x86 jobs on `e.get('x86') is True`, so a non-x86 Access leg is already expressible — covered by E-24
- `Build/Azure/configs/access.{mdb,ace.oledb,ace.odbc,ace.x64}.json` + `linq2db.slnx:53-56` — each config JSON is registered in the solution file individually — covered by E-23
- `DataProviders.json:67-74,294-297,348-383` and `UserDataProviders.json.template:79-83,210-214,334-338,738-760` — every place the Access provider list and its connection strings are spelled out; note Access entries carry **no** `"Provider"` key, the engine is expressed in the connection string alone — covered by E-15, E-16
- `Data/Setup Scripts/UserDataProviders.json:8,22` and `CONTRIBUTING.md:205,233` — illustrative samples naming Access providers — deferred: documentation sweep at the end of Phase D
- `Tests/Linq/TestsInitialization.cs:312-323` — `SetupAccessKeepAlive` holds one connection per **transport** because ACE ODBC has no pooling and leaks three OS handles per connect (`:280-311` records the measurement); LibRed is managed and pools in-process (measured: 100 open/close cycles clean) — covered by E-21 as an explicit exclusion
- `Tests/Linq/Create/CreateData.cs:269-272` — the Access arm of `CreateDatabase` is a two-case switch on `AllAccessOleDb`/`AllAccessOdbc`, each running the script twice (base + `.Data`) with a per-transport action; a LibRed config matches neither, so its database would never be created and every test would run against an empty file — covered by E-21a
- `Tests/Base/ProviderNameHelpers.cs:45` — `IsUsePositionalParameters` returns `true` for `TestProvName.AllAccess`, which E-14 widens; tests branching on it (e.g. `AccessTests.cs:26`) would assert `?` placeholders against a provider that emits `@name` — covered by E-21b
- `Tests/Base/TestConfiguration.cs:218` — the `Providers` list is built from the `TestProvName.AllAccess` constant and `.SplitAll()`, so the two new names join `CreateDatabase` gating automatically once E-14 extends the constant — out-of-scope, and this is what makes E-14 load-bearing rather than cosmetic
- `Tests/Base/TestBase.Identity.cs:30,36-37,155` — Access identity reset issues `ALTER TABLE … COUNTER(n,1)` (measured to work) and re-adds the two FKs with the **bare** `REFERENCES Person` form, which is measured to **fail** on LibRed; `ResetPersonIdentity`/`ResetAllTypesIdentity` are reached from 71 sites across 17 test files, so every one of them is red without this — covered by E-18a
- `Tests/Base/DatabaseUtils.cs:10-63` — the `TestExternals` per-file switch at `:25-39` is dead code (no assignment to `TestExternals.Configuration` exists in the tree and its `"Access.Data"` key matches no current provider name); the live path at `:49-62` copies every file from `Database/` into `Database/Data/`, so the two new binaries need no copy arm — out-of-scope
- `Tests/Base/DatabaseLaneStrategy.cs:12-29` — lanes are keyed generically on the provider context name, so each LibRed config gets its own lane; the inherited hazard is that two configs pointed at the same file are not serialised against each other, which is why D-7 gives the two LibRed configs two separate files — out-of-scope
- `Tests/Linq/DataProvider/AccessProceduresTests.cs` — 13 Access-only tests over stored procedures LibRed cannot create (U-8) — covered by E-22a
- `Tests/Linq/Extensions/AccessTests.cs:32` — `WithOwnerAccessOptionTest`, `[IncludeDataSources(true, TestProvName.AllAccess)]`, exercising the hint LibRed's parser rejects — covered by E-22b
- `Tests/Linq/DataProvider/AccessTests.cs:408-443` — its own `CreateDatabase` test is already restricted to `AllAccessOleDb` because it uses ADOX, so widening `AllAccess` does not pull LibRed into it — out-of-scope
- `Tests/Tests.T4/Cli/{All,Default,Fluent,NoMetadata,T4}.tt` + `CLI.ttinclude:13-17` + five committed output trees + `release-test-cli-scaffold.ps1:115,132-137,206-235` — measured at ~89 files / ~4 900 lines per key with no automated staleness gate (compilation only) — covered by E-29, E-30, E-31, scoped to one key by D-9
- `Tests/Tests.T4/Databases/Access*.tt`, `Tests/Tests.T4/Default/Access*.tt`, `Tests/Tests.T4.Nugets/Templates/Access.*.tt` — the legacy non-CLI T4 pipeline; neither DuckDB nor YDB added anything here when they landed — out-of-scope
- `Build/licenses/components.json:63-69,491,601` — the `linq2db.Access` NuGet component and its notices; this branch produces no new package — out-of-scope
- `.claude/docs/test-databases.md:31`, `.claude/docs/baselines-repo-layout.md:10`, `.claude/knowledge-base/areas/PROV-ACCESS/INDEX.md:14` — corpus docs stating "two driver families, four concrete providers" and listing four baseline directories — deferred: corpus edits land after the branch's shape settles

## P8 Test obligations (M/L)

- TO-1 (SC-1) — proof: control — the Access suite on both new configs via `/test run <filter> worktree <path>` with `--provider Access.LibRed.Mdb` and `Access.LibRed.Accdb`, each producing a per-test pass/fail list discriminated against the same filter on `Access.Ace.OleDb`, where the discriminating inputs are the tests that differ only by transport (parameter-heavy queries from D-3's naming change, GUID literals from D-6, `CHAR` padding from D-13) and a run reporting zero tests is a failure rather than a pass; **the expected-red set is enumerated before the run, not discovered by it** — the census is `TestProvName\.AllAccess(Odbc|OleDb|Jet)|ProviderName\.Access(Jet|Ace)(Odbc|OleDb)` over `Tests/**/*.cs` — **82 hits across 23 files** — of which the ones that matter are the gates keyed to the four concrete names LibRed does not inherit (`PredicateTests.cs:136-648` ten `ThrowsForProvider` pairs, `Issue1363Tests.cs:27-33`, `DateTimeFunctionsTests.cs:1817-1819`, `IntervalTranslationTests.Queries.cs:653,708,836`), the **binary transport branches in the test tree** where LibRed silently takes the OLE DB arm (`AccessTests.cs:47,48,53,61,139` `isODBC`, `Issue1925Tests.cs:58-65`, `DropTableTests.cs:89`, `MergeTests.Types.cs:561`, `QueryGenerationTests.cs:140,156`, `TypesTests.cs:502,513`), the two hint tests (E-22b), the 13 procedure tests (E-22a), `DataTypesTests.cs:44` (`supportLiterals: !Odbc` — the D-6 GUID-literal instrument) and `Access.sql:276,279`'s `char(20)`/`nchar(20)` columns (the D-13 padding instrument)
- TO-10 (SC-1, D-12) — proof: control — the provider lists really do exclude LibRed below net11: staging the LibRed job config as `UserDataProviders.json` and listing tests from a `-c Debug -f net10.0` build of `Tests/Linq` (note `-c Testing` is net11.0-only on this branch, `Directory.Build.props:225-226`) yields **zero** cases for `Access.LibRed.Mdb` and `Access.LibRed.Accdb`, while the same config on a net11.0 build yields both; the discriminating arm is the net10.0 one, which is what a `full_run` release leg exercises (`test-workflow-linux.yml:7-8,149`) and the only place the omission can be observed
- TO-11 (SC-1, U-19, U-20) — proof: red-green — one linq2db round-trip over LibRed, run before Phase A is called done: `db.GetTable<Person>().ToList()` through a `DataConnection` on a LibRed connection string returns the seeded rows. It is red before E-5a (`NotSupportedException` out of `GetSchemaTable` inside `IsDBNullAllowed`) and green after, and it exists because every other measurement behind this plan is raw ADO — this is the first obligation that exercises linq2db's own read path at all, which is precisely how U-19 went unnoticed through five probe rounds
- TO-2 (SC-2) — proof: control — baselines for the two new configs reviewed with `baselines-reviewer` and cross-compared against `Access.Ace.OleDb`, where the expected delta set is exactly parameter names (D-3), GUID literal form (D-6) and `DateValue` vs `CAST(… AS Date)` (D-5), so **any fourth category of difference is a finding**
- TO-3 (SC-3) — proof: red-green — a schema-provider test against `Data/TestData.LibRed.accdb` asserting every user table present with no `MSys*`/`#Dual` leakage, `Person`'s columns with correct nullability/length and the identity flag on `PersonID`, `Person`'s primary key, and the `Doctor`→`Person` foreign key **with its column pair**; the FK is the discriminating input because `Access.Ace.Odbc` returns none (`AccessODBCSchemaProvider.cs:25-30`), and it is red before E-7 because the provider cannot be constructed at all; the existing instrument for the PK/FK half is `Tests/Linq/SchemaProvider/SchemaProviderTests.cs:327` `PrimaryForeignKeyTest`, whose `[DataSources(false, AllOracle12, AllAccessOdbc)]` already admits LibRed. **It must also assert per-column `SystemType` for `AllTypes`** — or diff LibRed's whole `DatabaseSchema` for that table against `Access.Ace.OleDb`'s — because `SchemaProviderBase.GetSystemType:577-585` returns `null` for any `DATA_TYPE` the overridden `GetDataTypes` list omits, which surfaces as an `object`-typed member in scaffolded output and would otherwise be committed as the baseline by TO-6's idempotence check
- TO-4 (SC-4) — proof: characterization for the four existing flavours and red-green for the two LibRed ones — `AccessTypeTests` over `TestProvName.AllAccess` with one test per Access storage type (`COUNTER`, `INTEGER`, `SMALLINT`, `BYTE`, `SINGLE`, `DOUBLE`, `CURRENCY`, `DECIMAL`, `BIT`, `DATETIME`, `GUID`, `VARCHAR`, `CHAR`, `MEMO`, `BINARY`, `VARBINARY`, `LONGBINARY`), each exercising non-nullable + nullable, parameter + literal and the bulk-copy modes `TypeTestsBase` drives, and each per-provider exclusion naming the provider and the reason
- TO-5 (SC-5) — proof: control — the symmetry guard on the unchanged path: the same Access filter on `Access.Jet.OleDb`, `Access.Ace.OleDb`, `Access.Jet.Odbc` and `Access.Ace.Odbc` before and after Phase A, with `git diff` over their four baseline directories empty; this is what covers E-5/E-9/E-10, every one of which edits a method the existing flavours also execute
- TO-6 (SC-6) — proof: characterization — `release-test-cli-scaffold.ps1` run for the new key, then an empty `git diff` over its five output directories on a second run, plus `Tests.T4` compiling with the committed output (idempotence, not behaviour)
- TO-7 (SC-7) — proof: control — `dotnet build Source/LinqToDB/LinqToDB.csproj -c Release -f netstandard2.0` and `-f net462` clean, which is the arm that would fail if a net11-only API or a LibRed type leaked into shared code, plus a search asserting `LibRed` appears in no `<PackageReference>` under `Source/`
- TO-8 (SC-1, U-8) — proof: control — `a_CreateData.CreateDatabase` green on both new configs, i.e. `Access.sql` and its `.Data` companion executed through LibRed with D-10's `SKIP` markers and D-11's FK change in place; the discriminating inputs are the two FK statements (which failed before D-11) and the five procedure statements (absent for LibRed, still present for the other four), and it runs first because `TestBase.AwaitDatabaseReady` gates every other obligation on it
- TO-9 (SC-5, D-11) — proof: control — D-11 is behaviour-preserving for Microsoft's engine: `a_CreateData.CreateDatabase` green on `Access.Jet.OleDb` and `Access.Ace.Odbc` after E-18 and E-18a, with the `Doctor`/`Patient` foreign keys present in the resulting file. The form itself is **already proven on all four MS flavours by the repo**: `Access.sql:383,385` create `FK_Nullable`/`FK_NotNullable` with `REFERENCES RelationsTable(ID1, ID2)` today, so the obligation is about the two edited statements rather than about whether ACE accepts explicit columns


## P9 Verification gates

- G-01: — (pending) — TO-1/TO-4/TO-5 suite runs.
- G-02: — (pending) — baselines (TO-2), reviewed via `baselines-reviewer`, not eyeballed.
- G-03: — (pending) — new public surface: `PublicAPI.Unshipped.txt` (E-13) + XML docs on every new
  public member (`AccessProvider.LibRed`, three `ProviderName` consts, the new public classes).
- G-04: — (pending) — no `CompatibilitySuppressions.xml` change (P3).
- G-05: — (pending) — TO-7 portable-TFM + Release builds.
- G-06: — (pending) — provider-matrix coverage: the new configs run under `[access.all]` on CI (E-24)
  and the leg is green under both a filtered run and a `full_run` pass (TO-10).
- G-07: — (pending) — no playground scratch on the linq2db branch; the probe lives in the **corpus**
  beside this plan (`probe/`), never under `Tests/Tests.Playground/`.
- G-08: — (pending) — engine-code edit: none outside `DataProvider/Access` + the new sibling adapter.
- G-09: — (pending) — Tier L; derive with `work-plan.ps1 -Action gates`.

## P10 Adjudicated (M/L)

- **LibRed auto-detection from a connection string is not possible, and is not attempted.** A LibRed
  connection string is `Data Source=<file>` with no discriminating token (measured), so
  `AccessProviderDetector`'s string sniffing cannot distinguish it from any other file path. The
  provider must be named explicitly (`ProviderName.Access*.LibRed`, a `Access.*.LibRed` configuration
  name, or `AccessProvider.LibRed` passed to `AccessTools`). A review finding that auto-detection is
  missing is answered by this entry.
- **`WITH OWNERACCESS OPTION` is unsupported on LibRed.** Measured `SqlParseException`. The hint stays
  `ProviderName.Access`-keyed and its tests are excluded for the LibRed flavours rather than the hint
  being made flavour-aware (D-5).
- **The extended dialect stays off.** LibRed accepts window functions, `APPLY`, `FULL JOIN`,
  `OFFSET`/`FETCH`, `INTERSECT`/`EXCEPT` and `CASE` (all measured), and this branch enables none of
  them. Enabling them is a new Access dialect level with large baselines churn and belongs to its own
  branch — the user's "A only" instruction.
- **Access's bulk-copy caps (767 parameters / 64 000 chars) are kept for LibRed though they are
  conservative.** Measured: 5 000 parameters executed fine. A second cap set would be a code path with
  no observable benefit.
- **The type-coverage fixture may fail on the four existing flavours.** Those are pre-existing defects
  surfaced by new coverage, not regressions of this branch: each gets a named exclusion citing the
  provider and the symptom, and a follow-up issue — not a fix on this branch.
- **LibRed supports no stored procedures that this repo's script uses, and the branch does not add any.**
  Measured (U-8): parameterised *SELECT* procedures create fine; action procedures with parameters
  (`NotSupportedException: Parameters on an action-query procedure are not stored yet`), `UPDATE`/`DELETE`
  procedure bodies (`SqlParseException`) and `Scalar_DataReader` (`NullReferenceException`) do not. The
  consequence is deliberate and stated: `AccessProceduresTests` does not run on LibRed, and
  `AccessLibRedSchemaProvider` reports no procedures (D-10). A review finding that LibRed scaffolding
  omits procedures is answered by this entry.
- **The new CI leg is Linux-only, so a Windows-specific LibRed defect would not be caught by default.**
  Accepted: Linux coverage is the capability being added, and the Windows Access legs can gain the
  config later without a code change.
- **Only the test-database *container* is Microsoft-written; its schema and rows are written by LibRed.**
  The create script drops and recreates every table, so running the normal flow means LibRed authors
  everything above the file header. The consequence was put to the user with two alternatives that
  would preserve the property, and the container-only reading is their answer (U-18). A review finding
  that the suite does not exercise LibRed against an MS-written schema is answered by this entry.
- **The committed test databases are produced on Windows with ACE installed.** The artifacts stay
  Microsoft-produced by design (D-7) even though the provider exists to remove that dependency at
  *runtime*.
- **`CHAR(n)` columns read into `string` come back space-padded on LibRed and trimmed on the other four
  flavours.** Measured: `CHAR(10)` holding `'ab'` reads as `'ab        '`, and LibRed's
  `GetDataTypeName` reports `String` for `char`, `varchar` and `longchar` alike, so the type-name key
  `SetCharField` needs does not exist (D-13). The real fix is upstream — LibRed reporting store types
  from `GetDataTypeName` — and is a follow-up issue, not a workaround on this branch.
- **`WITH OWNERACCESS OPTION` raises at execution rather than being refused earlier.** The hint stays
  `ProviderName.Access`-keyed (D-5); a user who calls it against LibRed gets a `SqlParseException`.

## P13 Upstream defect register — collected, not yet triaged

The user's direction (2026-09-20): a provider gap that forces a workaround here is a candidate
**upstream** report, so collect them as they surface and triage the list in one pass rather than
filing ad hoc. Each row is a measurement from `findings.md` (beside this plan), with the workaround
this branch applies. Nothing here is filed yet; check each against existing
[CirrusRedOrg/EntityFrameworkCore.Jet](https://github.com/CirrusRedOrg/EntityFrameworkCore.Jet) issues
and PR #301 (which is unmerged and moves this surface) before reporting.

| # | Measured behaviour | Why it is a candidate | Workaround here |
|---|---|---|---|
| 1 | `DbDataReader.GetSchemaTable()` throws `NotSupportedException`; `IDbColumnSchemaGenerator` is not implemented | Every ORM that derives nullability from reader metadata breaks; linq2db's default `IsDBNullAllowed` is an unguarded call to it | `IsDBNullAllowed` override (E-5a) |
| 2 | A **braced** GUID string literal `'{…}'` parses and matches **zero rows**, while the unbraced form matches | Access/ACE accept the braced form, so the same SQL silently returns different results — a wrong-answer bug, not a capability gap | unbraced GUID literal (D-6) |
| 3 | `GetDataTypeName` returns CLR type names (`String`, `Int32`), not Access store types, for every column | Callers cannot distinguish `CHAR` from `VARCHAR`/`MEMO` at read time, though `[INFORMATION_SCHEMA.COLUMNS]` knows; `CHAR(n)` also reads back space-padded | no trim registration; `char`-typed mapping only (D-13) |
| 4 | `FOREIGN KEY … REFERENCES <table>` without a column list is rejected | Access accepts it and this repo's own scripts used it | explicit column lists (D-11, E-18, E-18a) |
| 5 | `CREATE Procedure` with parameters on an action query, and `UPDATE`/`DELETE` procedure bodies, are unsupported; `Scalar_DataReader` raises `NullReferenceException` | A `NullReferenceException` out of a SQL engine is a defect regardless of the feature gap | procedures skipped for LibRed (D-10) |
| 6 | `DROP TABLE` on a missing table raises a bare `System.InvalidOperationException`; `SELECT` raises `SqlBindException`; neither carries a `Number` | Inconsistent error typing, and `LibRedException.Number` exists but is unused for these | match both shapes (E-11a) |
| 7 | `WITH OWNERACCESS OPTION`, `CAST(x AS t)`, `LIKE … ESCAPE`, `TOP n WITH TIES`, `VALUES` as a table source, `{ts …}`/`{guid …}` escapes, `NZ()` are all rejected | Ordinary dialect gaps — lowest priority, and PR #301 may already move some | none needed (linq2db emits none of them except the hint) |
| 8 | `Database` and `DataSource` both return the full file path | Probably fine on its own; listed because of the linq2db-side consequence in row 9 | none |

One row is **linq2db-side, not upstream**:

| # | Behaviour | Action |
|---|---|---|
| 9 | `AccessSchemaProviderBase.GetDatabaseName:16-24` yields an absolute path as the scaffolded database name when `DbConnection.Database` is non-empty | The user's read is that the Microsoft Access providers already do this. Confirm against `Access.Ace.OleDb`/`Access.Ace.Odbc`, and if it reproduces, file it on linq2db as a pre-existing bug — not fixed on this branch (U-21) |

## P11 Amendments (M/L)

_None._

## P12 Critic verdict (M/L)

**refuted** (round 1) — `plan-critic` on a different model, run against this worktree. Ten objections;
four changed the design and were re-verified here by measurement rather than taken on the critic's
word. What it searched: `AccessProvider\.(OleDb|ODBC|AutoDetect)` worktree-wide (matched this plan's
P7 census of the six binaries exactly), `AllAccess*` across `Tests/`, `ProviderName.Access*` worktree-wide,
`IsParameterOrderDependent` across `Source/` (confirming D-3), `ConvertConversion|SqlCastExpression|DateValue`
in the Access convert-visitor, `git log -S "DateValue"`, `ResetPersonIdentity|ResetAllTypesIdentity`
across `Tests/` (71 hits / 17 files), the `full_run` TFM fan-out in `test-workflow-linux.yml`, and the
`Internal.DataProvider.Access` lines in `PublicAPI.Shipped.txt`.

- **O-1 — `CAST(expr AS Date)` is never emitted; the probe replayed a string the pipeline does not
  produce.** Verified directly at `AccessSqlExpressionConvertVisitor.cs:411-444`, and the shape that
  *is* emitted (`IIF(x IS NOT NULL, DateValue(x), NULL)`) was then measured to run on LibRed. → D-5
  rewritten, its edit-point deleted, U-6 corrected to one rejected construct, TO-2 down to two
  expected delta categories.
- **O-2 — `TestBase.Identity.cs:36-37` re-adds the FKs in the bare form U-8 measured as failing, and
  the P7 row claimed the opposite.** Re-probed: bare `REFERENCES [Parent]` fails on LibRed. → new
  E-18a, new U-17, P7 row corrected from a false clean.
- **O-3 — P3's "databases created by Microsoft's engine" is contradicted by TO-8**, which runs the
  drop-and-recreate script through LibRed at test time. → U-18, the user's call.
- **O-4 — a `full_run` leg runs the suite on net10.0, where `LibRed.Ado` is not referenced.** → new
  U-16, D-12, TO-10.
- **O-5 — E-13 understated the `PublicAPI.Unshipped.txt` surface**; `LinqToDB.Internal.*` types are
  tracked (`PublicAPI.Shipped.txt:1937-1971`). → E-13 widened to every new public type and member.
- **O-6 — E-5's reader-field arm cannot be written by mirroring.** Re-probed: `GetDataTypeName`
  returns CLR names and `CHAR(10)` reads back padded. → new U-15 and D-13.
- **O-7 — D-6's alternatives omitted the braced form the base schema already emits.** Re-probed, and
  the critic's suspicion was right to raise but the answer went the other way: the braced literal
  parses and matches **zero rows**, so inheriting it would be a silent wrong-results bug. → new U-14,
  D-6 strengthened.
- **O-8 — detector `:128` lets an explicit `AccessProvider.LibRed` fall through to the ODBC/OLE DB
  fallback.** → two new P7 rows (`:128` and the `:152-158` configuration-string markers).
- **O-9 — TO-1's expected-red set was understated.** → TO-1 now enumerates the gate sites up front.
- **O-10 — G-06 was empty.** → filled.

**refuted** (round 2) — same critic, same model, run against the revision. One objection was serious,
five were weak; all six are folded in, and the two that changed the shape of the work were verified in
code here rather than accepted on report.

- **O-1 (the serious one) — nothing above the raw-ADO layer had ever been exercised, and linq2db's own
  read path is broken on LibRed.** `ConvertFromDataReaderExpression.cs:178` calls `IsDBNullAllowed`
  for every column not forced to a null check, and `DataProviderBase.cs:307-311` implements it as an
  unguarded `reader.GetSchemaTable()` — which LibRed does not implement. Verified both lines directly.
  DDL and DML never materialize, so the create-data obligation would have gone green and every query
  after it would have thrown, with nothing in the expected-red set to explain it. Six providers
  already carry this override for the same class of reason. → new E-5a, new U-19/U-20, new P7 row,
  new TO-11 (the first obligation in this plan that exercises linq2db rather than the driver).
- **O-2 — the TFM gate covered one of the two test-selection paths.** `DataSourcesAttribute.cs:24`
  filters through `TestConfiguration.Providers`, but `IncludeDataSourcesAttribute.cs:24` intersects
  with `UserProviders` alone, and `TestConfiguration.cs:237-243` documents the asymmetry. A LibRed-only
  fixture would therefore still generate cases on a net10.0 release pass. → the objection stands, but
  its fix did not survive user review: a two-place `#if` was the revision's answer, and the user
  replaced it outright with "just don't add the new provider to the test config for unsupported TFMs"
  (D-12). Both selection paths read `UserProviders`, so the provider list is the one place that closes
  both, and no test code becomes conditional. TO-10's instrument is now a net10.0 run of the leg's own
  staged config.
- **O-3 — the detector marker named in P7 could never match**, and neither can the existing
  `"Access.Odbc"`/`"Access.OleDb"` ones against a versioned name. → P7 row rewritten with the two
  routes that do work.
- **O-4 — two unmeasured `SchemaProviderBase` calls and an instrument that could not see a wrong type
  list.** Probed: `Database`/`DataSource` both return the full path, so `GetDatabaseName` must be
  overridden (U-21); `GetSystemType` returns `null` for an omitted `DATA_TYPE`, which TO-6's
  idempotence check would have committed as an `object`-typed baseline. → E-7 widened, TO-3 extended
  and pointed at the existing `SchemaProviderTests.cs:327` instrument.
- **O-5 — TO-1's pre-classified red set was a partial census** (82 hits / 23 files, not 4 files). →
  widened, including the binary transport branches in the test tree where LibRed silently takes the
  OLE DB arm.
- **O-6 — E-11's discriminating value was unmeasured.** Probed: no `Number` at all — `SqlBindException`
  "does not exist" for `SELECT`, plain `InvalidOperationException` "no such table" for `DROP TABLE`,
  and only the first would match the existing Access rule. → new E-11a, U-22.

Two of the critic's claims were re-checked and came back **in the plan's favour**: D-13's reader key
survives the `ReaderInfo` cascade (`DataProviderBase.cs:245-289`) because the `ToType = char`
narrowing means `string`-typed reads cannot hit it, and TO-9's "unprobed on ACE" caveat was
unnecessary — `Access.sql:383,385` already ship the explicit-column FK form on all four Microsoft
flavours.

**Round cap reached.** `/work-plan` allows one revise-and-resubmit; this was it, so the plan goes to
the user with both verdicts rather than to a third critic pass. The standing methodological finding —
every measurement here is raw ADO until TO-11 runs — is recorded as U-20 rather than resolved.


