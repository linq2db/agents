# Work plan: feature-access-libred — the LibRed managed Access provider

**Tier:** L  ·  **Status:** approved  ·  **Approved-at:** 2026-09-20  ·  **Branch:** feature/access-libred
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

Branch 3 of the .NET 11 track — **PR #5956**, draft, milestone `6.x`, base `feature/csharp15-runtime-async`.
Cut off that branch (PR #5944) at `77800f967`; head `dbf09e571`, three commits (provider core / test
environment / type coverage + gating). Branch 1 is PR #5942, branch 2 is PR #5944; all three stay unmerged
until .NET 11 RTM because `global.json` pins an exact prerelease SDK.

**Session of 2026-09-22 (second) — the dependency moved.** `LibRed.Ado` **11.0.0-alpha.3** published that
day, and it fixes most of what this branch worked around; the bump and the resulting revert set are
**A-17**, which supersedes parts of D-4, D-6, D-10, D-11 and D-13 and empties much of P13. Read A-17 before
any row below that names alpha.2. Phases A, B and C are committed and pushed at `5926952da`; Phase D (CI
leg) and Phase E (CLI scaffold) were untouched as of the previous session. Open work is listed under
*Resuming* at the end of P11.

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

- SC-1 The test configurations `Access.LibRed.Mdb` and `Access.LibRed.Accdb` both resolve to the single LibRed `IDataProvider` (D-1, amended A-1) and the Access test suite executes against both, with the per-test outcome recorded and the create-data step green. → TO-1, TO-8
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

**Amended 2026-09-21 (A-1) — one data provider, not two.** The original text is kept below the rule so
the superseded reasoning stays readable; the paragraph immediately following is what the branch does.

- **chosen:** add `AccessProvider.LibRed = 3` and **one** provider name, **`Access.LibRed`**, resolving
  to a single `AccessLibRedDataProvider`. `Access.LibRed.Mdb` and `Access.LibRed.Accdb` are **test
  configuration names** — two entries in `DataProviders.json` / `UserDataProviders.json` differing only
  by connection string — not `ProviderName` constants and not distinct `IDataProvider`s. Five concrete
  data providers result, not six.
- **why:** `AccessVersion` selects exactly one thing for Access — the member translator — and its Jet
  arm exists for exactly one reason: `AccessJetMemberTranslator` returns `null` for `Replace` because
  *Microsoft's* JET driver has no `REPLACE`. **Measured** against this repo's own
  `Data/TestData.mdb` through LibRed: `SELECT REPLACE([FirstName],'o','X') FROM [Person]` → `JXhn`. The
  Jet/Ace split therefore says nothing about this transport, and a per-format provider would be a
  distinction the engine does not make. The single provider carries `AccessVersion.Ace`.
- **rejected:** two providers keyed `(AccessVersion, AccessProvider)` as the original D-1 specified —
  the user's correction (2026-09-21): the two names were always meant as test providers. It also fails
  on its own terms: with `REPLACE` working on an `.mdb`, the Jet arm would have mistranslated.
- **consequence for detection:** `DetectServerVersion` is **not** on LibRed's path at all — there is no
  version to detect. `AccessProviderDetector.DetectProvider(ConnectionOptions)` short-circuits to the
  LibRed provider as soon as the flavour resolves, so no connection is opened to probe a version.

~~**superseded:** add `AccessProvider.LibRed = 3` and two provider names, **`Access.LibRed.Mdb`** and
**`Access.LibRed.Accdb`**, plus the alias `Access.LibRed` mirroring the existing `Access` /
`Access.Odbc` alias pair. Six concrete data providers result from the same
`(AccessVersion, AccessProvider)` matrix — `Mdb` maps to `AccessVersion.Jet`, `Accdb` to `Ace`.~~
- **rejected:** `Access.Jet.LibRed` / `Access.Ace.LibRed`, which is what the existing four names would
  suggest — the user's call (2026-09-20): for this transport the **file format** is the axis a user
  actually chooses, and the engine generation is an implementation detail of it. *(Still the reason the
  test configuration names are format-shaped.)*
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
  views — see A-3 for how a *readable* view is separated from an action query),
  `[INFORMATION_SCHEMA.COLUMNS]`, `[INFORMATION_SCHEMA.INDEXES]` ⋈
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
- **mechanic to get right:** `RunScript` matches `SKIP {configString} BEGIN` on the **exact** configuration
  string, and each LibRed config runs the script twice — once as `Access.LibRed.Mdb` and once as
  `Access.LibRed.Mdb.Data` — so every skipped region needs **four** stacked marker lines, not two. The
  stacked form is the existing idiom (`Firebird.sql` stacks four versions the same way). Three regions
  are needed, because `Scalar_DataReader` and `AddIssue792Record` are not adjacent to the
  `Person_Insert`/`Update`/`Delete` run. `ThisProcedureNotVisibleFromODBC` is **not** skipped: it is a
  parameterless append query, which LibRed does create.
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
- E-2 `Source/LinqToDB/ProviderName.cs:29-59` — add the single `AccessLibRed` (`"Access.LibRed"`) const
  + docs (A-1: the `.Mdb`/`.Accdb` names are test configurations, not `ProviderName` constants).
- E-3 `Source/LinqToDB/Internal/DataProvider/LibRedProviderAdapter.cs` (**new**) — `IDynamicProviderAdapter`
  over `LibRed.Ado` by reflection: connection/command/parameter/reader/transaction types, connection
  factory, and the static `DatabaseExists`/`DropDatabase`/`ClearPool` helpers (A-2: `CreateDatabase` is
  not expressible through `TypeMapper` and has no consumer).
- E-4 `Source/LinqToDB/Internal/DataProvider/Access/AccessProviderAdapter.cs:21-47,61-99` — third
  private ctor taking `LibRedProviderAdapter`, a third cached singleton, `GetInstance` arm.
- E-5 `Source/LinqToDB/Internal/DataProvider/Access/AccessDataProvider.cs:23-26,37-88,95-130,142,174,209,290-308`
  — **one** new `sealed` provider class (A-1); three-way `CreateSqlBuilder` / `GetSchemaProvider` /
  `GetQueryParameterNormalizer`; `IsParameterOrderDependent` per flavour (D-3); the reader-field arm per
  D-13 (and **not** the ODBC `SetToType<sbyte,int>("INTEGER")` family at `:79-82`, which is keyed the
  same way and equally unmatchable); `SetParameter`/`SetParameterType` arms;
  `MappingSchemaInstance.Get` gains one `(_, LibRed)` arm (A-1).
- E-5a `Source/LinqToDB/Internal/DataProvider/Access/AccessDataProvider.cs` — **`IsDBNullAllowed`
  override returning `true` when `Provider == LibRed`** (U-19). Without it every materialized `SELECT`
  throws inside `DataProviderBase.cs:307-311`'s unguarded `GetSchemaTable()`. Shape follows
  `ClickHouseDataProvider.cs:169-173` (per-flavour) rather than Firebird's unconditional `true`.
- E-6 `Source/LinqToDB/Internal/DataProvider/Access/AccessLibRedSqlBuilder.cs` (**new**) —
  `AccessSqlBuilderBase` subclass, ctors + `CreateSqlBuilder` only. **No `GetProviderTypeName`
  override** (A-4): `BasicSqlBuilder.GetProviderTypeName:4873-4885` already maps from
  `DbParameter.DbType`, and `LibRedParameter` exposes no provider-specific type enum to read instead.
- E-7 `Source/LinqToDB/Internal/DataProvider/Access/AccessLibRedSchemaProvider.cs` (**new**) — D-4
  (amended A-3 for views), plus a `GetDataTypes` override (the base calls `GetSchema("DataTypes")`,
  which LibRed does not implement). **No `GetDatabaseName` override** — see U-21.
- E-11a `Source/LinqToDB/Internal/DataProvider/Access/AccessDmlService.cs` — table-not-found for LibRed
  covers **both** measured shapes (U-22): `SqlBindException` "… does not exist." and a plain
  `InvalidOperationException` "… no such table." from `DROP TABLE`.
- E-9 `Source/LinqToDB/Internal/DataProvider/Access/AccessMappingSchema.cs:104-126` — **one** public
  `LibRedMappingSchema` leaf rooted in the base `Instance`, overriding the `Guid` value-to-SQL converter
  to the unbraced form (D-6). No intermediate layer is needed with a single leaf (A-1). *(No member
  translator is added — see D-5; there is no `E-8`.)*
- E-10 `Source/LinqToDB/Internal/DataProvider/Access/AccessProviderDetector.cs:13-163` — **one** `Lazy`
  field, a `(LibRed, _)` `GetDataProvider` arm placed **before** the `AutoDetect` arm, `DetectProvider`
  provider-name arms, an early return in the configuration-string block so no connection is opened to
  probe a version, `CreateConnection` arm, and the bare `"LibRed"` configuration-string marker.
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
- `Build/licenses/components.json:63-69,491,601` — the `linq2db.Access` NuGet component and its notices; this branch produces no new package — ~~out-of-scope~~ **WRONG, corrected 2026-09-23 (`c44d367bb`)**: the notices key on *files inside a packed artifact*, not on new packages. E-31's net11.0-conditional `LibRed.Ado` reference puts `LibRed.Ado/.Core/.Engine/.Sql` and their transitive `Antlr4.Runtime.Standard` into `tools/net11.0/<rid>/` of the existing `linq2db.cli` package, and the verify action failed on all seven RID payloads with 35 unmapped DLLs. The reusable form of the miss: **"no new package" is the wrong test for the notices; the test is "does any packable artifact gain a file"** — which a new `PackageReference` on an already-packed project does by construction. Five components added, plus `texts/antlr4-bsd3.txt`
- `.claude/docs/test-databases.md:31`, `.claude/docs/baselines-repo-layout.md:10`, `.claude/knowledge-base/areas/PROV-ACCESS/INDEX.md:14` — corpus docs stating "two driver families, four concrete providers" and listing four baseline directories — deferred: corpus edits land after the branch's shape settles

## P8 Test obligations (M/L)

- TO-1 (SC-1) — proof: control — the Access suite on both new configs via `/test run <filter> worktree <path>` with `--provider Access.LibRed.Mdb` and `Access.LibRed.Accdb`, each producing a per-test pass/fail list discriminated against the same filter on `Access.Ace.OleDb`, where the discriminating inputs are the tests that differ only by transport (parameter-heavy queries from D-3's naming change, GUID literals from D-6, `CHAR` padding from D-13) and a run reporting zero tests is a failure rather than a pass; **the expected-red set is enumerated before the run, not discovered by it** — the census is `TestProvName\.AllAccess(Odbc|OleDb|Jet)|ProviderName\.Access(Jet|Ace)(Odbc|OleDb)` over `Tests/**/*.cs` — **82 hits across 23 files** — of which the ones that matter are the gates keyed to the four concrete names LibRed does not inherit (`PredicateTests.cs:136-648` ten `ThrowsForProvider` pairs, `Issue1363Tests.cs:27-33`, `DateTimeFunctionsTests.cs:1817-1819`, `IntervalTranslationTests.Queries.cs:653,708,836`), the **binary transport branches in the test tree** where LibRed silently takes the OLE DB arm (`AccessTests.cs:47,48,53,61,139` `isODBC`, `Issue1925Tests.cs:58-65`, `DropTableTests.cs:89`, `MergeTests.Types.cs:561`, `QueryGenerationTests.cs:140,156`, `TypesTests.cs:502,513`), the two hint tests (E-22b), the 13 procedure tests (E-22a), `DataTypesTests.cs:44` (`supportLiterals: !Odbc` — the D-6 GUID-literal instrument) and `Access.sql:276,279`'s `char(20)`/`nchar(20)` columns (the D-13 padding instrument)
- TO-10 (SC-1, D-12) — **done 2026-09-23** — proof: control — the provider lists really do exclude LibRed below net11: staging the LibRed job config as `UserDataProviders.json` and listing tests from a net10.0 build of `Tests/Linq` (note `-c Testing` is net11.0-only on this branch, `Directory.Build.props:225-226`) yields **zero** cases for `Access.LibRed.Mdb` and `Access.LibRed.Accdb`, while the same config on a net11.0 build yields both; the discriminating arm is the net10.0 one, which is what a `full_run` release leg exercises (`test-workflow-linux.yml:7-8,149`) and the only place the omission can be observed. **Measured**: net11.0 lists 15 529 cases, 7 313 `Access.LibRed.Mdb` + 7 313 `Access.LibRed.Accdb`; net10.0 lists 903 and **0** of either (the three `LibRed` hits in that log are the `UserDataProviders.json` banner the harness echoes at discovery, not case names). **Correction to this row's instrument**: it must be built `-c Azure`, not `-c Debug`. `TestConfiguration.cs:62-65` appends `.Azure` to the TFM config name only under the `AZURE` symbol, and the job config declares its providers under `NET110.Azure` — so a `-c Debug` pair resolves zero on *both* TFMs and the control cannot disagree
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

- G-01: — (partial, 2026-09-21) — TO-8 green on both LibRed configs (3/3, `CreateData.CreateDatabase`),
  and verified against an artifact rather than the runner's word: both containers grew and report
  `hasUserTables=True`, the `.mdb` still `Version4`. TO-11 **red→green proven** — with E-5a removed,
  `SelectTests.SimpleDirect("Access.LibRed.Mdb")` fails `System.NotSupportedException` at
  `System.Data.Common.DbDataReader.GetSchemaTable()`; restored, it passes. TO-3's instrument
  (`SchemaProviderTests`) is 14/14 green across both configs. TO-9 green on `Access.Ace.OleDb` and
  `Access.Ace.Odbc`; the two Jet flavours need an x86 run (both Jet drivers are 32-bit only) and are
  left to CI. **TO-4 green: 72/72** across the four locally reachable flavours (A-11, A-12).
  TO-1/TO-5 still pending.
- G-01b: — (done, 2026-09-22) — **TO-5 re-control after the alpha.3 bump, narrowed to the shared path this
  session actually edits.** The branch's shared-file surface *shrank*: `Access.sql` and `TestBase.Identity.cs`
  are byte-identical to the merge base again (`git diff <merge-base>` empty), so the only edit the Microsoft
  flavours still execute is `AccessProceduresTests` — its parameter names, now matching the declarations, and
  two per-flavour assertion arms. Control: create-data + `AccessProceduresTests` + `AccessTypeTests` +
  `AccessTests` on **`Access.Ace.OleDb` (84 cases, 0 failures)** and **`Access.Ace.Odbc` (98 cases, 0
  failures)**, each in its own host. That is narrower than G-01a's full run and deliberately so; the full
  control at G-01a still stands for everything else.
- G-01a: — (done, 2026-09-21) — **TO-5 control: the full suite on `Access.Ace.OleDb` is 7 680 tests with
  exactly 1 failure, `TestExpressionVisitorHops(10)`** — provider-independent (no provider in the case
  name), present on the LibRed run too, therefore pre-existing on this branch stack and not ours. So none
  of the shared-file edits regressed the reference flavour: `Access.sql`'s explicit FK columns and `SKIP`
  markers, `TestBase.Identity.cs`, `TypeTestsBase`'s name hook, the `AllNativeAccess` narrowings, and the
  `[ActiveIssue(3893)]` re-scoping. It is also what makes the LibRed failure list *interpretable*: every
  cluster left there is LibRed's, because the same tests pass on Access through Microsoft's driver.
- G-02: — (done, 2026-09-23) — **TO-2 captured and cross-compared.** Both LibRed configurations and
  `Access.Ace.OleDb` captured over the full suite into an isolated `BaselinesPath` under the worktree's
  `.build/.agents/` — not the shared `c:\GitHub\linq2db.bls`, which concurrent sessions write to — seeded
  per `worktree.md` with only the TFM bucket, its `BasedOn` and an absolute path, so `--provider` and every
  connection string still resolve from the tracked `DataProviders.json`. 3 592 baseline files per LibRed
  config; the runs were 1 failure each, `TestExpressionVisitorHops(10)`.

  **`Access.LibRed.Mdb` vs `Access.LibRed.Accdb`: 3 592 pairs, 0 differing, 0 unpaired.** D-1's claim that
  one provider serves both file formats is now measured rather than argued, and it is what validated the
  comparison tooling before the real comparison ran.

  **`Access.LibRed.Mdb` vs `Access.Ace.OleDb`: 3 569 pairs, 2 393 identical, 1 176 differing, 23/19
  unpaired.** Every difference falls into three mechanisms, and the unpaired files all trace to a
  documented decision (the MARS supported/not-supported pair, `CreateDatabase`'s ADOX gate, the
  `AllNativeAccess` narrowings, the `WITH OWNERACCESS` exclusions, and the tests LibRed now passes).

  The plan's predicted delta set did **not** materialise: parameter *names* are identical (both flavours
  use the base normalizer), and `DateValue` is identical. What remains is
  - **≈1 130 — the parameter-type comment in the baseline preamble**, the fourth category TO-2 says is a
    finding. `DECLARE @ID  -- Int32` against OLE DB's `DECLARE @ID Integer -- Int32`. Mechanism measured,
    not inferred: both Microsoft flavours **override** `GetProviderTypeName` to read their provider enum
    (`OleDbParameter.OleDbType` / `OdbcParameter.OdbcType`), while `BasicSqlBuilder`'s base maps only six
    `DbType` values and returns `null` for the rest — so Int32, Boolean, DateTime, Guid, Int64, Int16,
    Double, Single and Byte print blank. A-4 declined the override on the grounds that `LibRedParameter`
    exposes no provider type; re-probed on alpha.3, that is still true (its only type member is `DbType`),
    so there is nothing to read and no override to write. **Trace-only — it never reaches the database.**
    Recorded rather than fixed, and A-4's reasoning stands while its stated consequence understated the
    reach.
  - **16 — the database-qualified name**, `[Database\TestData].[Issue681Table]` dropped to
    `[Issue681Table]`. Expected: the `BuildObjectName` override, A-5.
  - **3 — the GUID literal**, `'{…}'` against OLE DB's `{guid {…}}`. Expected, and OLE DB is the outlier
    here: that escape comes from its own mapping schema, and LibRed uses the base braced form that A-17
    restored.

  Not run through `baselines-reviewer`: that agent reads the `linq2db.baselines` clone, and this capture
  is a local isolated directory, so the comparison was done with a purpose-built script instead
  (`.build/.agents/compare-baselines.ps1`, pairs by test identity, drops the per-statement provider header,
  buckets by the shape of the first differing line).
- G-03: — (done) — `PublicAPI.Unshipped.txt` carries every new public type and member (E-13), hand-written
  per the no-local-RS0016-check rule; XML docs on `AccessProvider.LibRed` and `ProviderName.AccessLibRed`.
- G-04: — (done) — no `CompatibilitySuppressions.xml` in the diff.
- G-05: — (done) — TO-7: `Source/LinqToDB` builds clean in Release on `netstandard2.0`, `net462` and
  `net11.0`. The portable arm earned its place: `Enumerable.ToHashSet()` does not exist on
  netstandard2.0 (the polyfill's overload requires a comparer), caught only by that build.
- G-06: — (partly discharged 2026-09-23) — provider-matrix coverage: the new configs run under
  `[access.all]` on CI (E-24) and the leg is green under both a filtered run and a `full_run` pass
  (TO-10). The `full_run` half is settled locally — TO-10 measured zero LibRed cases on net10.0 and
  both configs on net11.0 — so what remains is CI actually running the leg green.
- G-07: — (pending) — no playground scratch on the linq2db branch; the probe lives in the **corpus**
  beside this plan (`probe/`), never under `Tests/Tests.Playground/`.
- G-08: — (pending) — engine-code edit: none outside `DataProvider/Access` + the new sibling adapter.
- G-09: — (pending) — Tier L; derive with `work-plan.ps1 -Action gates`.

## P10 Adjudicated (M/L)

> **Four entries below were retired by the alpha.3 bump (A-17, A-18)** and no longer describe the branch:
> *LibRed supports no stored procedures* (it does, and the schema provider reports them), *`CHAR(n)` comes
> back space-padded* (`GetDataTypeName` now names the store type, so the trim is registered as for the
> Microsoft flavours), *a LibRed schema reports fewer views and their columns are approximate* (the driver
> classifies them and types their columns), and *no mutating stored query is ever executed* (still true, but
> it is now the driver honouring `CommandBehavior.SchemaOnly` rather than our `Flags` gate). They are left
> in place so a reviewer reading an older round still finds the reasoning.

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
- **A LibRed schema reports fewer views than the OLE DB flavour, and their columns are approximate.**
  Access "views" are stored queries; LibRed cannot bind a *parameterised* SELECT query as a table source
  at all, so those are absent, and a view column's nullability and exact store type are unknowable from
  the only metadata available (A-3). A review finding that view coverage or view column types diverge
  from `Access.Ace.OleDb` is answered by this entry.
- **No mutating stored query is ever executed during schema discovery.** The `MSysObjects.Flags` low-byte
  gate runs before the column probe, not after it (A-3). This is the safety property to re-check if the
  view-discovery code is ever reordered.

## P13 Upstream defect register — collected, not yet triaged

> **Re-measured against `LibRed.Ado` 11.0.0-alpha.3 on 2026-09-22 (A-17).** Rows **1, 3, 4, 5, 10, 12, 14,
> 15, 18, 19, 21, 24, 25, 27** are **fixed upstream** and are kept here only as history — do not report them.
> Row **2 inverted** (the braced literal is now the correct one). Row **22** was recorded from the wrong
> layer and is re-scoped: `GetValue` returns the zero date correctly while `GetDateTime` returns
> `DateTime.MinValue`. Rows **6, 7, 11, 13, 16, 17, 20, 23, 26** are unchanged and are what remains to
> report, together with the corrected 22. Per-row evidence: `findings-alpha3.md`.

The user's direction (2026-09-20): a provider gap that forces a workaround here is a candidate
**upstream** report, so collect them as they surface and triage the list in one pass rather than
filing ad hoc. Each row is a measurement from `findings.md` (beside this plan), with the workaround
this branch applies. Nothing here is filed yet; check each against existing
[CirrusRedOrg/EntityFrameworkCore.Jet](https://github.com/CirrusRedOrg/EntityFrameworkCore.Jet) issues
and PR #301 (which is unmerged and moves this surface) before reporting.

**Recording rule (added 2026-09-21, after rows 12 and 13 were nearly lost):** a limitation found while
*implementing* gets a row here **as well as** its P11 amendment. The amendment records what this branch did
about it; the row is what gets reported upstream. Rows 12 and 13 existed only as A-11 and A-5 for half a
session — the amendment reads like a complete write-up, which is exactly why the register entry gets
skipped. Every `SqlParseException`, `NotSupportedException` or bare `InvalidOperationException` that forces
a LibRed-specific code path is a row.

| # | Measured behaviour | Why it is a candidate | Workaround here |
|---|---|---|---|
| 1 | `DbDataReader.GetSchemaTable()` throws `NotSupportedException`; `IDbColumnSchemaGenerator` is not implemented | Every ORM that derives nullability from reader metadata breaks; linq2db's default `IsDBNullAllowed` is an unguarded call to it | `IsDBNullAllowed` override (E-5a) |
| 2 | A **braced** GUID string literal `'{…}'` parses and matches **zero rows**, while the unbraced form matches | Access/ACE accept the braced form, so the same SQL silently returns different results — a wrong-answer bug, not a capability gap | unbraced GUID literal (D-6) |
| 3 | `GetDataTypeName` returns CLR type names (`String`, `Int32`), not Access store types, for every column | Callers cannot distinguish `CHAR` from `VARCHAR`/`MEMO` at read time, though `[INFORMATION_SCHEMA.COLUMNS]` knows; `CHAR(n)` also reads back space-padded | no trim registration; `char`-typed mapping only (D-13) |
| 4 | `FOREIGN KEY … REFERENCES <table>` without a column list is rejected | Access accepts it and this repo's own scripts used it | explicit column lists (D-11, E-18, E-18a) |
| 5 | `CREATE Procedure` with parameters on an action query, and `UPDATE`/`DELETE` procedure bodies, are unsupported; `Scalar_DataReader` raises `NullReferenceException` | A `NullReferenceException` out of a SQL engine is a defect regardless of the feature gap | procedures skipped for LibRed (D-10) |
| 6 | `DROP TABLE` / `DROP PROCEDURE` on a missing object raises a bare `System.InvalidOperationException` (`no such table.` / `no such procedure.`); `SELECT` raises `SqlBindException`; none carries a `Number` | Inconsistent error typing, and `LibRedException.Number` exists but is unused for these. A bare `InvalidOperationException` is also indistinguishable from a client-side bug, so every caller has to match on message text | match all three shapes (E-11a) |
| 7 | `WITH OWNERACCESS OPTION`, `CAST(x AS t)`, `LIKE … ESCAPE`, `TOP n WITH TIES`, `VALUES` as a table source, `{ts …}`/`{guid …}` escapes, `NZ()` are all rejected | Ordinary dialect gaps — lowest priority, and PR #301 may already move some | none needed (linq2db emits none of them except the hint) |
| 8 | `Database` and `DataSource` both return the full file path | Probably fine on its own; listed because of the linq2db-side consequence in row 9 | none |
| 10 | `CommandBehavior.SchemaOnly` is ignored — the query runs and returns rows (4 / 1 / 12 measured on three queries) | Every consumer that reads result-set shape without wanting the rows is silently executing the statement; for an action query that would be destructive | force the empty set in SQL with `WHERE 1 = 0` (A-3) |
| 11 | A parameterised stored SELECT query cannot be used as a table source: `SELECT * FROM [Person_SelectByKey]` → `SqlParseException: token recognition error at: ']'` | Access permits it, and the parse-level failure suggests the definition is inlined rather than bound | such queries are not reported as views (A-3) |
| 12 | `CONSTRAINT x PRIMARY KEY CLUSTERED (col)` → `SqlParseException: extraneous input 'CLUSTERED' expecting '('` | **Highest impact of the set.** Access accepts `CLUSTERED` and linq2db emits it for all four Microsoft flavours, so *every* `CREATE TABLE` carrying a primary key fails — which is what an ORM emits by default | `BuildCreateTablePrimaryKey` override dropping the keyword (A-11) |
| 14 | `CREATE TABLE … (Id int IDENTITY, …)` → `extraneous input 'IDENTITY' expecting {')', ','}` — **58 direct failures, the largest single cluster** | Access accepts `IDENTITY` as a column attribute; LibRed requires the `COUNTER` type instead. Any ORM that models identity as an attribute rather than a type emits this | `BuildCreateTableFieldType` emits `COUNTER` for an identity field and `BuildCreateTableIdentityAttribute2` emits nothing — the form `Access.sql` already uses (A-13) |
| 15 | `UPDATE a, b SET …` (comma-joined multi-table update) → `mismatched input ',' expecting SET` — 16 failures | Access supports both this and the `UPDATE a INNER JOIN b ON … SET …` form; LibRed only parses the latter (measured working in the probe phase) | pending |
| 16 | `IS TRUE` / `IS FALSE` / `IS UNKNOWN` / `IS DISTINCT FROM` → `mismatched input '<token>' expecting {NOT, NULL}` — 5 failures | LibRed's `IS` predicate accepts only `NULL` / `NOT NULL` | pending |
| 17 | Database/owner-qualified identifiers rejected in `SELECT`, `UPDATE` and `INSERT` alike — `mismatched input '.'`, 33 failures across four distinct parser states | The same root as row 13, but this is its real blast radius: it is not only cross-database queries, it is any qualified name | pending |
| 21 | A date-part expression comes back as `Int16` where Access returns `Int32` — `InvalidCastException: Unable to cast object of type 'System.Int16' to type 'System.Int32'` on a `month_1` column, 2 failures in `UnionGroupByTest1/2` | Narrowing a scalar's return type to the smallest that fits makes the column's CLR type depend on its *values*, so a mapped `int` member breaks unpredictably | none yet |
| 22 | The Access zero date reads back as `DateTime.MinValue` (`0001-01-01`) instead of the Jet epoch `1899-12-30`, 1 failure in `TestZeroDate` | Access stores date/time as a serial with 1899-12-30 as zero; returning the .NET minimum loses the distinction between "zero date" and "no value" | none yet |
| 23 | A `DATETIME` retains sub-second precision that Access truncates — expected `09:44:34`, got `09:44:34.6530000`, 1 failure in `TestMergeTypes` | Access's DATETIME has no sub-second component, so a value read back with one did not come from Access semantics. Arguably *more* precise, but it makes round-trips through LibRed disagree with round-trips through the Microsoft drivers on the same file | none yet |
| 20 | `NotSupportedException: Cannot encode GUID index key from String` when a GUID column carries an index and is compared to a string | Internal engine failure rather than a dialect refusal; the message names an internal encoder | none yet |
| 19 | `UPDATE` whose target is a **derived table** — `UPDATE ((SELECT …) [cross_1] INNER JOIN …) SET [cross_1].[col] = …` → `System.NotSupportedException: Cannot UPDATE/DELETE the derived table 'cross_1'.` at `LibRed.Engine.Execution.StatementExecutor.TargetTable`, 7 failures | Access supports updatable queries, and this is precisely how linq2db lowers a multi-table update for Access, so it is not an exotic shape. Same root as row 15 (both are multi-table update forms). **Note the exception is a bare `System.NotSupportedException`** — see row 6: by type alone it is indistinguishable from a client-side error, and it was mis-classified as a linq2db exception here until the stack was read | none yet |
| 18 | `DATEADD` returns the raw OLE Automation serial as a **Double** instead of a `DATETIME` — `Cannot convert value '43890.7457653125: System.Double' to type 'System.DateTime'`, 6 failures in `DateTimeAddTimeSpan` | Access returns a Date/Time from `DATEADD`; returning the underlying serial makes every date-arithmetic projection unreadable without a client-side cast. Probably the same root as the `Mapping of column 'X' value failed` failures in `UnionGroupByTest1/2` | none yet |
| 27 | A 64-bit **minimum as a literal** overflows the parser: `SELECT cdbl(-9223372036854775808)` raises `OverflowException: Value was either too large or too small for an Int64.` before evaluation — 2 failures in `AccessTests.TestNumerics`. **The control is the same value as a parameter**, which round-trips exactly (`cdbl(@p)` → `-9.223372036854776E+18` → `Int64 -9223372036854775808`), so the value is representable and only the literal path is not | The digits are evidently consumed as a positive `Int64` before the unary minus is applied, so the exact boundary value cannot be written in SQL at all. Also seen: `clng(9223372036854775807)` overflows *Int32*, i.e. `CLng` is 32-bit here | gated `[ActiveIssue]` on `TestNumerics` |
| 25 | A bare integer in `ORDER BY` is an inert **constant expression**, not an **ordinal** column reference — 12 failures in `EnableConstantExpressionInOrderByTest{,2,3}`. **Measured**, with a discriminating control: `ORDER BY 1, [LastName]` returns rows in pure `[LastName]` order, and `ORDER BY 2` — which under the ordinal reading would give `[LastName]` order — returns natural order instead, so neither literal contributes anything | Access, and standard SQL, read the literal as the *n*-th select column. Silent wrong **row order**, no error. `SELECT` shape and `ORDER BY` are both unremarkable, so any caller emitting a computed ordinal gets a differently-ordered result set through this transport | LibRed excluded from the three tests, matching the `SqlCe` exclusion already there for the same gap |
| 26 | `CVar(1)` returns a typed `Int32` `1` rather than a Variant that reads back as the string `"1"` — 2 failures in `AccessTests.TestSqlVariant` | `CVar` exists to *produce* a Variant; returning the unconverted argument makes the function a no-op | pending |
| 24 | A multi-column `SET` is evaluated **sequentially**: each right-hand side reads what earlier assignments in the same `UPDATE` already wrote. **Measured directly** (not inferred from the failures): `UPDATE t SET [A] = [B], [B] = [A]` on `(A=100, B=200)` yields `(200, 200)`, where Access and standard SQL yield `(200, 100)` — 12 failures in `UpdateTestAssociationSimple`/`AsUpdatable` and `UpdateWithTypeConversion` | **Silent wrong results, no exception** — a column swap collapses and any `SET` whose right-hand side names a column assigned earlier in the same statement reads the new value. Access evaluates every right-hand side against the pre-update row, so identical SQL gives different data through the two transports. Nothing in the emitted SQL is non-standard, so no ORM can avoid it | gated `[ActiveIssue]` on the three tests; not fixable in linq2db — the correct SQL is what is already being emitted |
| 13 | No database-qualified table name in any form — `[<file>].[T]`, `[<file-no-ext>].[T]`, `[<file>]..[T]` all give `mismatched input '.'`, and Access's own `SELECT … FROM [T] IN '<file>'` gives `mismatched input 'IN'` | Access supports both forms; this is how a query reaches a table in a second `.mdb`, so cross-database queries are unreachable | no database name is reported for LibRed (A-5) |

**Rows 14-17 are from the first full-suite run** (2026-09-21, `Access.LibRed.Mdb`, 8 196 tests): 1 440
failures first pass, 331 after fixing the `AccessDmlService` classification defect that the remote
transport exposed, of which 178 are the direct context and ~117 of those are `SqlParseException`. Each row
is a *cluster*, counted, not a single test. **Before reporting any of them upstream, confirm the same SQL
executes on a Microsoft flavour** — the evidence that linq2db emits it for Access is not by itself evidence
that Access accepts it, and some of these constructs may be reaching Access only through tests that are
already provider-gated. The remaining direct failures (~60: conversion errors, assertion mismatches, and
5 tests that *pass* on LibRed while carrying an `[ActiveIssue]` gate keyed to Access) are untriaged.

One row is **linq2db-side, not upstream**:

| # | Behaviour | Action |
|---|---|---|
| 9 | `AccessSchemaProviderBase.GetDatabaseName:16-24` yields an absolute path as the scaffolded database name when `DbConnection.Database` is non-empty | The user's read is that the Microsoft Access providers already do this. Confirm against `Access.Ace.OleDb`/`Access.Ace.Odbc`, and if it reproduces, file it on linq2db as a pre-existing bug — not fixed on this branch (U-21) |

## P11 Amendments (M/L)

### A-1 — One LibRed data provider, not two (2026-09-21, user correction)

`Access.LibRed.Mdb` / `Access.LibRed.Accdb` were always meant as **test provider names** (`TestProvName`
+ two `DataProviders.json` entries), and D-1 promoted them into `ProviderName` constants and two
`IDataProvider`s off the `(AccessVersion, AccessProvider)` matrix. Corrected: one `ProviderName.AccessLibRed`
= `"Access.LibRed"`, one `AccessLibRedDataProvider` carrying `AccessVersion.Ace`, one mapping-schema leaf,
one `Lazy` in the detector. The two test configuration names survive unchanged and both resolve through
the detector's bare `"LibRed"` configuration-string marker.

Grounded rather than merely conceded: `AccessVersion` selects only the member translator, and the Jet arm
exists solely because Microsoft's JET driver has no `REPLACE`
(`AccessJetMemberTranslator.TranslateReplace` returns `null`). Measured through LibRed against this
repo's `Data/TestData.mdb`: `SELECT REPLACE([FirstName],'o','X') FROM [Person]` → `JXhn`. A per-format
provider would have mistranslated `Replace` on the `.mdb` side. Touches D-1, SC-1, E-2, E-5, E-9, E-10.

### A-2 — `LibRedProviderAdapter` omits `CreateDatabase` (E-3)

Its signature is `CreateDatabase(string, Nullable<LibRed.Catalog.Collation>, JetVersion)` and
`LibRed.Catalog.Collation` is a **struct** (`System.ValueType`, per the signature dump); `TypeMapper` has
no wrapper precedent for a nullable value-type parameter, and D-7 (Microsoft-created containers) leaves
the method with no consumer on this branch. `DatabaseExists`, `DropDatabase` and `ClearPool` are present.

### A-3 — Views are surfaced, but only after a Flags gate and a bind probe (D-4, E-7)

D-4 said "`MSysObjects` `Type = 5` for views" as if `Type = 5` were the whole test. Measured on
`Data/TestData.mdb` it returns **14 rows** — every stored query, action queries included — and
`[INFORMATION_SCHEMA.TABLES]`/`COLUMNS` return **zero** rows for any of them. Two measurements set the
mechanism:

- **`CommandBehavior.SchemaOnly` is not honoured** — LibRed executed the query and returned 4 / 1 / 12
  rows on three different queries. The empty result set has to be forced in SQL (`WHERE 1 = 0`). This is
  load-bearing: `SQLiteSchemaProvider` relies on `SchemaOnly` for the same job, so copying that shape
  would have *run* every candidate during schema discovery.
- **`MSysObjects.Flags` carries the DAO query type in its low byte** — `Person_Insert` /
  `AddIssue792Record` `0x…40` (append), `Person_Update` `0x…30`, `Person_Delete` `0x…20`. Only `0x00`
  (select), `0x10` (crosstab) and `0x80` (set operation) are probed, so no mutating query is ever
  executed. The gate must precede the probe; the probe cannot be the only filter.

A surviving candidate is read with `SELECT * FROM [q] WHERE 1 = 0`; anything that throws is not a view.
That drops parameterised SELECT queries, which fail with `SqlParseException: token recognition error at:
']'` (LibRed evidently inlines the definition), and `Scalar_DataReader`, which the binder refuses
outright. `~`-prefixed hidden queries are skipped. Final result on this file: 5 views
(`LinqDataTypes Query`/`Query1`/`Query2`, `Person_SelectAll`, `Patient_SelectAll`).

**Accepted consequences:** a view column has only a name and a CLR type, so nullability is reported as
`true` and the store type is reverse-mapped from the CLR type — `Decimal` cannot distinguish `CURRENCY`
from `DECIMAL`, `String` cannot distinguish `VARCHAR` from `MEMO`, and no length is available. The probe
catches broadly, so a genuine connection failure mid-discovery shrinks the view list instead of
surfacing. One command per surviving candidate, run once in `GetTables` and cached for `GetColumns`.

### A-5 — `TestUtils.GetDatabaseName` gets no LibRed arm (E-17)

E-17 assumed a database name could be produced. **Measured**: LibRed accepts no database-qualified table
name in any form — `[<file>].[Person]`, `[<file-without-extension>].[Person]` and `[<file>]..[Person]`
all fail with `SqlParseException: mismatched input '.'`, and Access's `SELECT … FROM [Person] IN '<file>'`
fails with `mismatched input 'IN'`. The correct result is therefore `NO_DATABASE_NAME`, which is what the
existing `_ =>` arm already returns for a config matching neither `AllAccessOleDb` nor `AllAccessOdbc`, so
**E-17 is a no-op**. `DropTableTests.cs:112` branches on `!= NO_DATABASE_NAME`, so the qualified-name
half of that test simply does not run for LibRed.

### A-6 — `TestProvName.AllNativeAccess`, not per-site LibRed exclusions (E-14, E-21b, E-22a, E-22b)

The user's call (2026-09-21): rather than writing `AllAccess && !AllAccessLibRed` at each site that means
"Microsoft's drivers", add a positive constant. `AllNativeAccess = AllAccessOleDb + AllAccessOdbc`, and
`AllAccess = AllNativeAccess + AllAccessLibRed`. Every site that must exclude the managed engine names
`AllNativeAccess` — `ProviderNameHelpers.IsUsePositionalParameters` (E-21b), and the narrowed
`AccessProceduresTests` / `WithOwnerAccessOptionTest` parameters (E-22a, E-22b) — so a future Access
transport joins the right set by construction instead of by remembering to add another exclusion.

### A-7 — The Jet container must be created by the **32-bit** host (D-7, E-19)

`Microsoft.Jet.OLEDB.4.0` is 32-bit only, and ADOX under 64-bit PowerShell falls back to
`Microsoft.ACE.OLEDB.12.0`, which **ignores the `.mdb` extension** and writes an ACCDB-format file.
Measured: the first attempt produced two byte-identical 172 032-byte files, both reporting
`ServerVersion=Version12_2007`, so the `.mdb` config would have tested the ACCDB format under another
name. Creating it through `C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe` gives a 65 536-byte
file reporting `Version4`, matching this repo's own `Data/TestData.mdb`. The generator is
`.build/.agents/make-libred-dbs.ps1` (scratch, not committed); **verify `ServerVersion` after regenerating**
— the wrong-format failure is silent.

### A-8 — The `LibRed.Ado` reference lives in `Tests/linq2db.Providers.props` (E-20)

E-20 named `Tests/Linq/Tests.csproj`; every other test provider package is declared in the shared
`linq2db.Providers.props` that project imports, so the `net11.0`-conditional `ItemGroup` goes there
alongside them. `Directory.Packages.props` carries the version as E-20 said.

### A-9 — A `SKIP` region must end **inside** the `GO` boundary, and carry no comment before `BEGIN` (E-18)

`RunScript` removes the span from `SKIP <cfg> BEGIN` to `SKIP <cfg> END`, so a region whose `END` markers
sit *after* the region's terminating `GO` deletes that `GO` too — and whatever precedes the `BEGIN` marker
is then concatenated with the next statement. The first version of E-18 put an explanatory `--` comment
above each `BEGIN` block, which made the following chunk read
`-- LibRed raises NullReferenceException on this one\n\nDROP TABLE LinqDataTypes`. `CreateData.cs:102-106`
decides whether a failure is tolerable with `command.TrimStart().StartsWith("DROP")`, which is now **false**,
so the harmless fresh-database `DROP TABLE 'LinqDataTypes': no such table.` became the create-data
failure — a test failure two hundred lines away from its cause. Measured: red, then green after moving
every `END` block above its `GO` and deleting the two comments. Rule for the script: `BEGIN` directly
after a `GO`, `END` directly before one, nothing else in between.

### A-10 — E-22b covers both tests in `Tests/Linq/Extensions/AccessTests.cs`, not one

E-22b named `WithOwnerAccessOptionTest` (`:32`). `QueryHintTest` (`:15`) emits the same construct through
`QueryHint(AccessHints.Query.WithOwnerAccessOption)` and calls `ToList()`, so it executes against the
database and fails on LibRed identically. Both are narrowed to `AllNativeAccess`.

### A-11 — E-6 gains a `BuildCreateTablePrimaryKey` override; `TypeTestsBase` gains a table-name hook (E-22)

Writing TO-4's fixture turned up two blockers neither the plan nor the probe had reached, both because
every earlier measurement used hand-written DDL rather than the builder's:

- **`AccessSqlBuilderBase.BuildCreateTablePrimaryKey:205` hardcodes `PRIMARY KEY CLUSTERED`**, and LibRed's
  grammar has no `CLUSTERED`: `SqlParseException: extraneous input 'CLUSTERED' expecting '('`. Every
  `CreateTable` with a primary key fails, which is why all 17 type tests failed identically on both LibRed
  configs while passing on OLE DB. Fixed by an override in `AccessLibRedSqlBuilder` — additive, beside the
  existing arm, no change to the shared base. Worth noting the create script never exposed this: it spells
  its own `CONSTRAINT … PRIMARY KEY (…)` by hand.
- **`TypeTable<TType, TNullableType>` maps to the CLR name `TypeTable`2`, and Access forbids a backtick in
  an object name.** `TypeTestsBase` therefore cannot run on any Access flavour as written. Added
  `protected virtual string? TypeTableName => null` and applied it to the **fluent mapping**, not to
  `CreateLocalTable`: the three bulk-copy blocks call `db.BulkCopy(options, data)`, which resolves the
  table from the mapping schema, so a name passed only to `CreateLocalTable` creates `[TypeTests]` and then
  inserts into `[TypeTable`2]` — measured, as the second failure after the first fix. Default `null`
  leaves all seven existing fixtures byte-identical; `DuckDBTypeTests` was run as the control and stayed
  green.

### A-12 — `TestGuid` excludes the ODBC flavours (E-22)

Not a defect: `AccessODBCSqlBuilder.BuildValue:62-77` deliberately forces every GUID to a parameter, so
`TypeTestsBase`'s literal block — which asserts `cmd.Parameters Is.Empty` unconditionally — can never pass
there. The existing precedent is `DataTypesTests.cs:44`'s `supportLiterals: !Odbc`. GUID coverage stays on
OLE DB and LibRed, which is where D-6's unbraced-literal decision needs an instrument anyway.

**Result, measured on all four locally reachable flavours** (`Access.Ace.OleDb`, `Access.Ace.Odbc`,
`Access.LibRed.Mdb`, `Access.LibRed.Accdb`): **72/72 green**. P10's prediction that the fixture would
surface pre-existing defects in the Microsoft flavours did **not** materialise for this type set — the only
two findings were the two above, one LibRed dialect gap and one deliberate ODBC behaviour. `TestChar`
passing with its `padded` branch is also independent confirmation of D-13 through linq2db's own read path.
The two Jet flavours need an x86 run and are left to CI.

### A-13 — TO-1 first pass: 1 440 → 331 → 229 failures, and two of the three causes were ours

Full suite on `Access.LibRed.Mdb`, 8 196 tests, three runs:

| Run | Failed | What the fix was |
|---|---|---|
| 1 | 1 440 | — |
| 2 | 331 | `AccessDmlService` matched `exception is InvalidOperationException`, a **concrete type test**. The remote (`LinqService`) transport wraps every exception in `Grpc.Core.RpcException`, so the arm never fired and ~1 100 `DROP TABLE`-on-missing-table errors escaped. `DmlServiceBase.TypeOrMessageContains` exists precisely for this — its sibling `HResultMatches` even documents "the remote-transport message wrapper". Using it is the fix; `no such procedure` was added at the same time. |
| 3 | 229 | Register row 14 (`IDENTITY` → `COUNTER`), −102. |
| 4 | 156 | Rows 13/17: `BuildObjectName` override dropping the database component, modelled on `SqlCeSqlBuilder:168-178` — a file database addresses one database and never names it. Implementing `TestUtils.GetDatabaseName` would not have worked: the gap is in LibRed's *grammar*, so a real path fails to parse exactly as the `UNUSED_DB` placeholder does. −37 direct. Plus narrowing the unscoped `[ActiveIssue(3893)]` on `Issue3893Test_Rejected` to `AllNativeAccess`, which its own `Details` text was already describing ("through both drivers", "an ODBC 'COUNT field incorrect'"). |

**The methodological point is the second row.** 84 % of the first run's failures were a single defect of ours
that only the *remote* context could expose, and the direct-context count never moved (178 → 178 → 126).
Any triage that had started from the direct failures, or from a run that skipped the remote contexts, would
have reported a provider in far worse shape than it is. Run the remote half before drawing conclusions.

| 5 | 143 | Gating only, no product change: `[ThrowsForProvider("LibRed.Sql.Parsing.SqlParseException", AllAccessLibRed)]` on the 5 `PredicateTests` feature probes that actually throw (the other 4 Access-gated probes pass on LibRed, so gating them would assert a throw that never happens), and LibRed exclusions on the 4 remaining `WITH OWNERACCESS OPTION` sites. |

| 6 | 125 | Gating only: the A-14 four-way `Issue3893` split, three more `[ThrowsForProvider]` probes, and the D-13 padding group (`StringTrimming`, `StartsWith`/`EndsWithTests`, `FullWhiteSpaceTest`) narrowed with citations — P10 had already adjudicated that divergence, so these needed a reference rather than a decision. |

| 7 | 79 | Rows 15 and 19 gated with `[ActiveIssue(Configuration = AllAccessLibRed)]` across 23 tests — the user's call (2026-09-22), and the right one: `[ActiveIssue]` **asserts the failure still happens**, so when LibRed fixes either form the gate turns into a failure demanding its own removal, where a `[DataSources]` exclusion would drop the coverage silently and permanently. No gate reported "passed but marked", so all 23 match reality. |

| 8 | 60 | Rows 18, 21, 22 and 23 gated (8 tests), plus a retrofit of all 23 run-7 gates to the repo's conventional form: `ErrorTypeName` set, `Details` prefixed `no-issue:` / `no-declaration:`. The retrofit is self-verifying — a wrong `ErrorTypeName` makes the gate fail — and nothing regressed. |

**Run 8 leaves 60 = 21 remote + 37 direct**, and the direct set is now singletons: 8 `Concat_*`
nullable-argument mismatches, 4 association-update `ThrowsNothing` assertions, 3
`EnableConstantExpressionInOrderBy`, 2 procedure-count (D-10), 2 `GuidToString`, 3 `[ActiveIssue]`-passing
un-gating candidates (`TestIssue4261`, `ConcatInAny`, `FullJoinCondition_Regression`), and ~15 others.
No cluster larger than 4 remains.

**Superseded — run 7 left 79 = 30 remote + 47 direct.** Direct: 6 `DateTimeAddTimeSpan` + 2 `UnionGroupByTest` (row
18), 8 `Concat_*` nullable-argument mismatches, 4 association-update `ThrowsNothing` assertions, 2
procedure-count assertions (a D-10 consequence — LibRed creates none of the skipped procedures and reports
no procedures at all), and ~25 singletons.

**Superseded — run 6 left 125 = 53 remote + 70 direct**, and the remaining direct set is now dominated by two
register rows: 23 multi-table `UPDATE` failures (row 15's comma form ×16, row 19's derived-table form ×7)
and 6 `DATEADD`→Double (row 18). The other ~41 are assertion-level singletons.

**Superseded — run 5 left 143 = 57 remote + 80 direct.** Three register rows account for 29 of the 80 — row 15
(comma-joined `UPDATE`, 16), row 19 (derived-table `UPDATE`, 7), row 18 (`DATEADD`→Double, 6). The other
~51 are assertion-level and need individual adjudication. Because the control run failed exactly one
provider-independent test, every one of these corresponds to a test that **passes** on Access through OLE
DB — with the caveat that the two runs do not enumerate an identical case set (8 188 vs 7 680), so a
per-test check is still owed for any row before it is reported upstream.

Direct clusters after run 4 (superseded by run 5, kept for the shape): 16 comma-joined
`UPDATE` (row 15 — `UpdateTestWhere`, `UpdateParentTableFromChild`, `Test1`), 8 value-assertion mismatches,
7 `Cannot UPDATE/DELETE the derived table` (a **linq2db** exception, not LibRed — check against the
Microsoft flavours before assuming it is ours), 6 `DATEADD`-returns-Double (row 18), 4 more
`WITH OWNERACCESS OPTION` sites beyond the two E-22b narrowed, 3 `IS TRUE/FALSE/DISTINCT` (row 16), 2 more
`[ActiveIssue]`-passing tests on a different issue, and a tail of singletons including a LibRed-internal
`NotSupportedException: Cannot encode GUID index key from String`.

**The one ambiguous cluster, and the reasoning error it exposed.** `Cannot UPDATE/DELETE the derived table`
is a bare `System.NotSupportedException`, which I read as *linq2db* refusing to lower the update — making
it look pre-existing rather than LibRed's. Two checks corrected that. The control run: `DeleteFromWithTake`
(`[DataSources]`) and `UpdateWhenTableSecond` (`[DataSources(AllInformix, AllClickHouse)]`) both run on
Access and both **pass** on `Access.Ace.OleDb`. Then the stack: `at
LibRed.Engine.Execution.StatementExecutor.TargetTable` — it is LibRed's, thrown as a BCL type. Row 19.

**Generalise that:** LibRed raises `System.NotSupportedException` and `System.InvalidOperationException`
from its engine, so *exception type is not a layer boundary here*. Read the stack before attributing a BCL
exception to linq2db. The same shape already cost a mis-implementation once (E-11a's concrete-type test,
A-13 run 2) and a mis-classification here.

### A-14 — Gate per engine *and* per case: split the `ValueSource`, don't scope one gate

`Issue3893Test_Rejected` gates identifiers Access refuses. Scoping its `[ActiveIssue]` to
`AllNativeAccess` was half a fix: LibRed accepts most of those identifiers but refuses five, so the test
went from 5 wrongly-gated passes to 5 real failures. The user's correction (2026-09-22) — *"gate native and
libred separately on cases where they fail"* — is what the fixture was already built for: its own comment
says *"Split three ways by what Access actually does with each identifier: a gate cannot target a
ValueSource argument"*. So the answer is a **fourth** `ValueSource`, not a cleverer `Configuration`:

- `_identifiersRejected` (5) — refused by the Microsoft drivers only, gated `AllNativeAccess`.
- `_identifiersRejectedByAll` (5: `` ` ``, `!`, `.`, `[`, `]`) — refused by every engine, gated unscoped.

I had read the sibling test's prose note (*"neither can be targeted by argument"*) as a statement about the
attribute's capability and concluded no clean split existed. It was a note about that test's two arms.

**The same measure-per-engine rule applies to the `[ThrowsForProvider]` feature probes**, and the exception
type differs per engine: `LibRed.Sql.Parsing.SqlParseException` for `IS TRUE/FALSE/UNKNOWN`, `IS DISTINCT
FROM`, `IS`, and `<=>`; `System.InvalidOperationException` for `<>/= UNKNOWN` (LibRed parses `UNKNOWN` as
an identifier — *"Column 'UNKNOWN' was not found"*); `System.NotSupportedException` for `DECODE`. Eight
probes gated in total; the remaining Access-gated probes pass on LibRed and are deliberately left alone,
because gating them would assert a throw that never happens.

Verified across `Access.LibRed.Mdb`, `Access.LibRed.Accdb`, `Access.Ace.OleDb` and `Access.Ace.Odbc`
together: **213 cases, 0 failures**. Gating one flavour at a time would not have caught the `char ]`
mis-assignment.

### A-15 — Bulk gating went through a script, and the script was wrong twice

23 `[ActiveIssue]` insertions across 6 files is the "rule of three → codify" case, so it went through
`.build/.agents/gate-libred-updates.ps1` (dry-run first, exact-declaration match, idempotency guard) rather
than 23 hand-edits. Both of its bugs are worth recording because neither showed up in the dry run:

- **The idempotency guard scanned the whole file prefix** for `AllAccessLibRed`, so the second and later
  tests *in the same file* were reported `ALREADY` and silently skipped — 11 of 22. It has to inspect only
  the attribute block immediately above the declaration.
- **It emitted unescaped `"` into a C# string literal.** The `Details` text quotes the engine's own error
  message, so it needs `\"`. 22 sites broke the build at once; recovery was `git restore` on the four files
  the script owned (no hand edits in them) and a re-run.

Generalising: a generator whose output is source needs a **compile** as its gate, not a dry run. The dry
run proved the *targeting* was right and said nothing about the *text*. Both bugs would have been caught
one edit earlier by applying to a single file and building.

### A-4 — `AccessLibRedSqlBuilder` needs no `GetProviderTypeName` override (E-6)

`BasicSqlBuilder.GetProviderTypeName:4873-4885` already maps `DbParameter.DbType` to a type name, which
is exactly what E-6 asked for, and `LibRedParameter` exposes only `DbType` — there is no provider enum to
read instead. The class is ctors + `CreateSqlBuilder`.

### A-16 — The full-suite triage: 119 failures, nine causes, one of them ours (2026-09-22)

A clean full run over **both** LibRed configurations (15 381 cases, direct + `LinqService`) reported **119
failures**, and every one of them reconciles into nine causes. The OLE DB control run alongside it was
**8 214 cases with exactly one failure** — `TestExpressionVisitorHops(10)`, provider-independent and
pre-existing — so TO-5 holds and the LibRed list is interpretable.

**Run the two flavours in separate hosts.** A first attempt with `Access.Ace.OleDb` in the same process
died at 10 minutes with a native `0xC0000005` inside `UnsafeNativeMethods.ICommandText.Execute`, taking
the LibRed lanes down with it. That is the access-violation hazard `AccessOleDbSchemaProvider.cs:52-55`
already documents; run alone, the same control passed clean.

**The largest cause was ours, not LibRed's — 40 of the 119.** `GuidMemberTranslator.TranslateGuildToString`
emits `LCase(Mid(CStr(g), 2, 36))`, where the `Mid` strips the brace Access's `CStr` produces. Measured:
LibRed's `CStr` renders a GUID **unbraced** (`Len` 36) and its `Mid` is 1-based like VBA's, so the `Mid`
ate the first hex digit. The two hypotheses — unbraced `CStr` vs. a 0-based `Mid` — produce byte-identical
output, and only a probe separates them; the control was `Mid('ABCDEF', 2, 3) = BCD`. → new
`AccessLibRedMemberTranslator` (E-6a), selected in `CreateMemberTranslator` by `Provider`, not `Version`.

Twelve more were **over-broad gates**: `TestIssue4261`, `ConcatInAny` and `FullJoinCondition_Regression`
are keyed to `AllAccess` and *pass* on LibRed, which the run-and-verify attribute reports as a failure.
Narrowed to `AllNativeAccess` — the same one-word fix `TestDateOnly`'s Access gate needed, there so that
LibRed falls onto the unscoped `#3929` gate whose message it actually matches.

Twenty were **test-side corrections rather than defects**: opening `"BAD"` as a file database throws
`FileNotFoundException`, which the invalid-connection-string assertions did not list; LibRed *supports* a
second reader on one command, so it moved into `MARS_…_Supported`; `nchar(20)` padding is asserted
directly (D-13) instead of gated, following `AccessTypeTests`.

The rest are gated or excluded against **rows 24-27**, all measured with a discriminating control rather
than inferred from the assertion arithmetic. Two of those controls changed the answer: `ORDER BY 2` proved
the `ORDER BY` literal is inert rather than a mis-resolved ordinal, and the parameter arm proved the 64-bit
literal defect is in the *parser*, not in the value's representability.

**A verified gate reports as `skipped`, not `succeeded`.** Its line reads `[ActiveIssue] Known issue (…),
still failing as expected:` followed by the observed failure. So a bare `failed: 0` does not distinguish a
correct gate from a test that never ran — read the skip reason, and for a non-gated change confirm
execution from the baseline file's mtime.

### A-17 — `LibRed.Ado` 11.0.0-alpha.3 retires most of the workaround set (2026-09-22)

alpha.3 published the same day this branch's first full triage finished, and it moves nearly every surface
the branch had to work around. The bump is `Directory.Packages.props` alone (`Tests/linq2db.Providers.props`
carries no version). **Nothing here was taken from the release notes**: each row is a re-measurement against
the committed containers and, for the schema half, the suite's own populated database — the notes were the
hypothesis, the probe was the evidence. `findings-alpha3.md` beside this plan is the measured report.

**Reverted, because the behaviour is fixed:**

| Was | Now | What went |
|---|---|---|
| `GetSchemaTable`/`IDbColumnSchemaGenerator` unimplemented (row 1) | both work, `AllowDBNull` correct | E-5a `IsDBNullAllowed` override |
| `GetDataTypeName` returned CLR names (row 3) | returns the store type — `Char`, `VarChar`, `LongText` | the `char`-only registration; `SetCharField("Char", TrimEnd)` now matches the other flavours, so every CHAR-padding gate and the two `padded` flags go |
| `PRIMARY KEY CLUSTERED` rejected (row 12) | accepted | `BuildCreateTablePrimaryKey` override |
| trailing `IDENTITY` rejected (row 14) | accepted, and the column really is an identity | `BuildCreateTableFieldType` + `BuildCreateTableIdentityAttribute2` overrides |
| bare `REFERENCES <table>` rejected (row 4) | resolves to the parent's primary key | D-11 entirely: `Access.sql` and `TestBase.Identity.cs` are back to base |
| five `CREATE Procedure` shapes rejected (row 5) | all five create; `CommandType.StoredProcedure` executes | D-10's `SKIP` regions and the `AccessProceduresTests` narrowing |
| `ORDER BY n` inert (row 25), comma-joined and derived-table `UPDATE`/`DELETE` unparseable (rows 15/19), sequential multi-column `SET` (row 24), `DATEADD` as a Double (row 18), date parts as `Int16` (row 21), 64-bit minimum literal (row 27) | all behave as Access does | ~35 `[ActiveIssue]` gates across 13 files, reverted whole-file to base |

**Inverted — the workaround had become a wrong answer:**

- **Row 2, the GUID literal.** On alpha.2 the braced form matched zero rows and the unbraced one matched;
  on alpha.3 it is **the other way round** (measured `braced=1 unbraced=0`). D-6's override was therefore
  producing silently empty results, so `LibRedMappingSchema` drops it and inherits the base braced form.
  The failure shape D-6 existed to prevent had simply changed sides.
- **A-16's `CStr`.** `CStr(guid)` now renders **braced** (`Len` 38), so `GuidMemberTranslator`'s
  `LCase(Mid(CStr(g), 2, 36))` is correct again and `AccessLibRedMemberTranslator` (E-6a) is deleted.

**Kept, re-measured and re-stamped to alpha.3:** `CVar` is still a no-op (row 26); an indexed `GUID`
column still cannot be compared to a string literal (row 20) — the braced form and a literal `INSERT` fail
too, but the A/B control shows alpha.2 refused those identically, so the scope did not widen;
`DATETIME` still keeps sub-second precision (row 23);
`IS TRUE`/`IS FALSE`/`IS DISTINCT FROM` (row 16), `WITH OWNERACCESS OPTION`, `CAST`, `LIKE … ESCAPE`,
`TOP … WITH TIES`, `VALUES` as a table source and the `{ts}`/`{guid}` escapes (row 7) still do not parse;
database-qualified names still do not (rows 13/17), so `BuildObjectName` and `NO_DATABASE_NAME` stay; the
missing-object error shapes are unchanged (row 6), so `AccessDmlService` keeps all three arms.

**alpha.3 also regressed two things, found by running the battery against both versions rather than by
reading the new failure list.**

- **The reader contradicts itself on a computed column.** For `[x] + [x]` where `x` comes from a `CURRENCY`
  `SUM`, alpha.2 reported `GetFieldType = Decimal` and returned a `Decimal`; alpha.3 reports `Int32` /
  `Long` from `GetFieldType` **and** `GetSchemaTable`, and still returns a `Decimal`. A materializer
  compiled from the declared type — what linq2db does — then throws
  `Unable to cast object of type 'System.Decimal' to type 'System.Int32'`. Six failures
  (`AggregatesKeepTheDeclaredUnit`, `Issue1601`), probably ten if `Issue3360`'s GUID byte-array error is the
  same family. **Nullability was the first hypothesis and it was wrong**: `AllowDBNull` is correct for every
  expression column, so removing E-5a is not what exposed this.
- **A text column compared against a numeric literal** — `[S] = 11`, `IN (11, …)`, `NOT IN (11, …)` over a
  `VARCHAR` — evaluated on alpha.2 and now throws `InvalidCastException: Type mismatch: '<text>' cannot be
  read as a number`, on any non-numeric text, not merely on an empty string. Four failures
  (`Issue2608Test`). Ordinary SQL that linq2db emits for every provider, and ACE accepts it.

The GUID-literal flip and the `CStr` brace change are breaking too, but in the corrective direction.
Both are written up for the upstream author in **`findings.md`** (the file they monitor) rather than filed
as issues — the user's call, 2026-09-22: collect there, triage and report later. `findings-alpha3.md` §4
records the *method*, which is what the verdict rests on: the A/B control overturned three claims this
amendment first made from the failure list alone.

**Row 22 was recorded wrong, and the correction is the sharper finding.** `TestZeroDate` still fails, but
not because "LibRed reads the Access zero date as `DateTime.MinValue`": raw ADO round-trips 1899-12-30
through a parameter, a `#…#` literal *and* `DateSerial(1899, 12, 30)` — which is what linq2db actually
emits. The loss is in the reader: on the same column `GetValue` returns `12/30/1899` and **`GetDateTime`
returns `01/01/0001`**. The gate is restored with that mechanism, and it is now an upstream report with a
one-line repro instead of a symptom.

### A-18 — the schema provider moves to `GetSchema`, and D-4 is superseded (2026-09-22)

D-4 chose SQL-over-`[INFORMATION_SCHEMA.*]` because U-4 measured that **no** ADO schema API existed.
alpha.3 implements 20 collections, so the premise is gone. The user asked for the two sources to be
compared rather than for the release notes to be trusted; measured side by side on the populated suite
database, `GetSchema` is a superset on every fact the provider needs except one:

- **Tables** — `INFORMATION_SCHEMA` lists 15 base tables and no views; `GetSchema("Tables")` lists the same
  15 plus the 4 `MSys*` as `SYSTEM TABLE` and 3 as `VIEW`.
- **Views** — the whole A-3 apparatus (12 `MSysObjects Type = 5` candidates → a hand-written DAO `Flags`
  low-byte gate → one `SELECT … WHERE 1 = 0` bind probe each) is replaced by three rows carrying
  `VIEW_DEFINITION` and `IS_UPDATABLE`. The engine classifies the 6 parameterised selects and 3 action
  queries as procedures, so the "no mutating stored query is ever executed" property stops being ours to
  maintain.
- **View columns** — were a name and a CLR type with nullability forced `true`; now full rows with
  `TYPE_NAME`, `IS_NULLABLE` and length (`Patient_SelectAll.Diagnosis` → `VarChar(255)`).
- **Columns** — `TYPE_NAME` (`Long`/`VarChar`/`LongText`/`Char`) instead of the lowercase Access spellings;
  all 17 names the engine returns were already covered by `AccessSchemaProviderBase.GetDataType` and by
  this provider's own `_dataTypes` list, which `SchemaProviderBase` looks up `OrdinalIgnoreCase`. Identity
  arrives as `IS_AUTOINCREMENT` rather than being inferred from `DATA_TYPE = 'counter'`.
- **Keys** — `PrimaryKeys` and `ForeignKeys` replace the `INDEXES ⋈ INDEX_COLUMNS` join and the
  `MSysRelationships` read, and the FK rows add `UPDATE_RULE`/`DELETE_RULE` (`CASCADE` reported correctly
  for `PersonDoctor`/`PersonPatient`).
- **Procedures** — no source at all before; now 9 procedures with definitions and 18 parameters with type,
  length and direction. `GetProcedures`/`GetProcedureParameters` are implemented from them, which retires
  the P10 entry "LibRed reports no procedures" and un-gates both `Issue792Tests`.
- **The one gap:** `GetSchema("DataTypes")` carries no `CreateFormat`, so the scaffolder could not spell a
  column type back out. The hand-written `_dataTypes` list therefore stays — re-keyed to the engine's
  spellings — and `GetDataTypes` remains overridden. Two other shape differences are normalised rather than
  inherited: a length of `0` is reported for the unbounded types and a precision for every numeric, so both
  are carried only when the type's `CreateParameters` can spell them (the `AccessOleDbSchemaProvider`
  idiom), and `SYSTEM TABLE` maps to `IsProviderSpecific`.

**The safety question was measured before the code was written, not after.** `SchemaProviderBase` describes
each procedure by executing it with `CommandBehavior.SchemaOnly`; on alpha.2 `SchemaOnly` was ignored and
the statement ran (row 10), which for an action query would mean schema discovery mutating the database.
Measured on alpha.3: describing `Person_Insert`, `Person_Update`, `Person_Delete` and `AddIssue792Record`
leaves `Person` at 4 rows and `AllTypes` at 2, and each returns an empty column set, while the select
queries describe fully **without parameter values**. So `GetProcedureSchemaExecutesProcedure` stays `false`
— the OLE DB flavour's `KeyInfo` route, which does execute, refuses outright here
(`Procedure … declares 1 parameter(s) but was executed with 0 argument(s)`). `Issue792Tests.TestWithoutTransaction`
asserts exactly this property, which is why un-gating it is the verification rather than a side effect.

### Resuming — open work as of 2026-09-22

1. **Failure triage — done** (A-16), then **mostly undone by the alpha.3 bump** (A-17): ~35 of the gates it
   produced were reverted because the engine now behaves, and the whole-file reverts were taken against the
   merge base rather than hand-edited. What remains gated is the nine-row residue named in the P13 banner.
   **The post-bump full run is measured, not arithmetic this time: 15 513 cases, 28 failures, 284 verified
   skips** (2 h 11 m, both configs, direct + `LinqService`), against A-16's 119 on 15 381. The 28 resolve
   into: 10 alpha.3 regressions (A-17), 8 defects of this session's own changes — 6 from LibRed binding
   stored-query parameters **by name** where the Microsoft drivers bind positionally, so three test helpers
   passing arbitrary names had to be corrected, and 2 from the rewritten schema provider needing a
   `GetProcedureResultColumns` override (`SchemaProviderBase` reads an `IsIdentity` column that is not an
   ADO standard name; LibRed carries the standard `IsAutoIncrement`) — 4 needing a re-gate on a changed
   mechanism, 2 that now *pass* and needed a pre-existing non-LibRed gate narrowed, 1 gRPC transport flake
   in the `LinqService` harness, and 1 pre-existing provider-independent failure. **All dispositioned and
   re-verified**: procedures + schema provider + `Issue792` + create-data are **44/44** on both configs, the
   regressions are gated (and report as verified skips), `Issue2815Test1` passes once its gate is narrowed
   to `AllNativeAccess`, and `CountTestAsync2` passed on re-run, confirming the gRPC flake. The full run has
   not been repeated since — the residue is arithmetic again, but every cluster was re-run individually.
   Three follow-on divergences surfaced while fixing the procedure path, all in the schema provider and all
   settled by mirroring `AccessOleDbSchemaProvider` rather than the base: the result-column `MemberType`
   comes from the reader's own `DataType` while `SystemType` goes through `GetSystemType` (the base uses one
   value for both, which turned `Gender` into `char` where the other flavours report `string`); the
   `CreateFormat` casing follows the `TypeName` so a scaffolded type reads `VarChar(50)` as OLE DB spells it;
   and LibRed propagates the base column's nullability into a procedure's result schema where the Microsoft
   drivers report everything nullable, which is a genuine transport difference and gets a test arm.
2. **P13 triage** — **14 of the 27 rows are fixed upstream** and must not be reported (P13 banner). The nine
   that remain, plus the re-scoped row 22, are what to file: check each against existing
   EntityFrameworkCore.Jet issues before reporting, and confirm the same SQL runs on a Microsoft flavour —
   that linq2db emits it for Access is not by itself evidence Access accepts it. Then backfill the tracking
   links into the `[ActiveIssue]` gates, which are deliberately linkless (user's call, 2026-09-22).
3. **Phase D** (CI leg, E-23..E-25) — **done 2026-09-22**: `Build/Azure/configs/access.libred.json` with its
   providers under `NET110.Azure` (D-12), the `z_Access_LibRed` Linux-only entry in `test-matrix.yml`, the
   `linq2db.slnx` registration and both `Build/Azure/README.md` tables. TO-10 (a net10.0 pass of the leg's
   own config resolving zero LibRed cases) **ran green on 2026-09-23** — see its P8 row for the numbers and
   for the `-c Azure` correction to the instrument. **Phase E** (CLI scaffold, E-26..E-31) — the code
   half is done (`DatabaseType.AccessLibRed` + its `ScaffoldCommand` arm, the `McpInfoTool` row, the
   `LegacySchemaProvider` system-table skip, a net11.0-conditional `LibRed.Ado` reference in
   `LinqToDB.CLI.csproj`); the generated half (E-29/E-30/E-31) is not. Two corrections to E-26/E-28 found
   while writing it:
   - **`LinqToDB.CLI` already targets `net10.0;net11.0`**, so the net11.0 asset can load `LibRed.Ado` and the
     ".NET 11 track" note that the CLI needs a real net11.0 TFM is stale. The net10.0 asset cannot, so the
     arm is `#if`-guarded with a message rather than left to fail inside the reflection adapter.
   - **E-28 said the two `LegacySchemaProvider` flavour flags were correct to leave `false` for LibRed. They
     are not.** `LegacySchemaProvider.cs:360-367` *throws* on a table with `IsProviderSpecific` unless the
     provider is one of the two Microsoft Access flavours, and the rewritten schema provider reports the four
     `MSys*` tables that way (A-18) — `GetSchema("Tables")` lists them where `[INFORMATION_SCHEMA.TABLES]`
     did not. So LibRed joins that condition. Nothing in the main suite covers it; it surfaces only through
     the CLI.
   - **D-9's "over the `.accdb`" cannot be taken literally**: the T4 scaffold path
     (`.build\bin\NuGet\Debug\net462\Database`) holds no `.accdb`, and the two committed LibRed containers
     are empty until a test run fills them. The key points at that path's `TestData.mdb` — the same file the
     OLE DB key uses, which makes the two outputs directly comparable and needs no new artifact.
   - **Phase E is done** (2026-09-22): the five `.tt` rows, the `CLI.ttinclude` connection string, the
     `release-test-cli-scaffold.ps1` matrix row (corpus) and **89 committed files / ~4 585 lines**, which
     lands inside U-13's ~89-file estimate. TO-6 holds — a second run regenerates them byte-identical, and
     `Tests.T4` compiles with them.
   - **Running the scaffolder found a schema-provider gap no test covers.** `GetSchema("Tables")` marks the
     four catalog tables as `SYSTEM TABLE` but reports `MSysAccessStorage`, `MSysAccessXml` and the four
     `MSysNavPane*` tables as ordinary tables, where OLE DB calls them `ACCESS TABLE` and the scaffolder
     skips them — so the first generated model carried six `MSys` entities the other Access keys do not, 28
     files against OLE DB's 22. `GetTables` now also treats Access's reserved `MSys` name prefix as
     provider-specific, and the two models have the same 22 entities. Worth noting for the altitude of the
     obligation set: TO-3's instrument (`SchemaProviderTests`) is green either way, and only generating real
     scaffold output exposed it.
   - **Diffing the generated model against the OLE DB one exposed a second, larger defect — upstream this
     time.** For a `PARAMETERS` clause **Access itself wrote**, LibRed reports the `[ ]` quoting as part of
     the parameter name (`[@firstName]`) and re-emits the definition double-quoted
     (`PARAMETERS [[@firstName]] TEXT(50)`), which then does not parse: the query cannot be described or
     executed by any spelling. A query written *through* LibRed round-trips correctly, which is why nothing
     in the suite sees it — the suite's own database is LibRed-written, and the CLI scaffolds
     `Data/TestData.mdb`, which ACE wrote. The name is unquoted in `GetProcedureParameters`; the result-set
     loss has no client-side remedy and the committed output shows it (`ExecuteProc` returning `int` where
     OLE DB produces `QueryProc<…Result>`). `findings.md` carries the repro.
   - **Three model differences that are LibRed being more accurate, not defects:** it detects identity
     (`IsIdentity`/`SkipOnInsert`/`SkipOnUpdate` on `AllTypes.ID` and `DataTypeTest.DataTypeID`) where the
     OLE DB flavour hard-codes `IsIdentity = false` for #3149; it reports `Binary(10)` where OLE DB
     coarsens `binary(10)` to `VARBINARY(10)`; and it types a procedure parameter from the declaration
     (`VarChar(50)`) where OLE DB's regex over the definition yields `Text`/`NText`. One difference goes the
     other way and is worth watching: `bitDataType` is declared `NULL` in the script and LibRed honours
     that (`bool?`), while ACE reports it non-nullable (`bool`) because a Yes/No column cannot physically
     hold NULL — the OLE DB model is the more useful one there.
4. **TO-2 baselines — done 2026-09-23**, see G-02 for the result. What follows is the mechanism, kept
   because it is what made the capture work: seed a worktree-local
   `UserDataProviders.json` carrying **only** the TFM bucket and an absolute `BaselinesPath` (per
   `worktree.md`), which leaves `--provider` and every connection string resolving from the tracked
   `DataProviders.json`. Sets were captured for `Access.LibRed.Mdb`, `.Accdb` and `Access.Ace.OleDb`, but
   **pre-fix**, so they are stale — and the alpha.3 bump moved the GUID literal back to the braced form and
   removed the `COUNTER`/no-`CLUSTERED` create-table divergences, which shrinks TO-2's expected delta set to
   parameter names alone. Re-capture before comparing. The cross-comparison itself is still unrun.
5. **Two Jet flavours unverified locally** — both Jet drivers are 32-bit only and the runner is x64, so
   `Access.Jet.OleDb` / `Access.Jet.Odbc` rest on CI's x86 legs.
6. **Inherited, not ours**: `dotnet restore Tests/Linq -p:Configuration=Testing` fails `NU1510` on
   `LinqToDB.Extensions`, reproduced with this branch's package edits reverted. `Debug` is fine, so
   `test-runner` and CI are unaffected; only the `-c Testing` fast path is broken on this branch stack.

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


