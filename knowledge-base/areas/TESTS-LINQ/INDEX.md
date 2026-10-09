---
area: TESTS-LINQ
kind: area-index
sources: [code]
confidence: medium
last_verified: 2026-10-10
last_verified_sha: 05150894edc2511f0dd0bc7829b2a309cec36ec9
coverage_tier_1: 4/4
coverage_tier_2: 700/700
---

# TESTS-LINQ

Integration and regression test suite under Tests/Linq/. The largest area in the KB: ~667 files across 23 subdirectories. The area KB value is taxonomic -- knowing *what feature surface each subdirectory exercises* and *which production area it validates*, not the content of individual fixtures.

All test classes extend TestBase (from Tests.Tools). Provider selection uses [IncludeDataSources(...)] / [DataSources(...)] NUnit parameterized-fixture attributes; TestProvName.* constants identify provider sets. The single assembly [SetUpFixture] is TestsInitialization (root, no namespace).

## Assembly setup

Tests/Linq/TestsInitialization.cs -- NUnit [SetUpFixture], no namespace (intentional). [OneTimeSetUp] runs once per assembly:

- Pre-loads the SQLite native runtime (e_sqlite3) via NativeLibrary.SetDllImportResolver on .NET 8+, or forces a SQLiteConnection construction on .NET Framework to ensure SDS loads before other providers.
- **(updated, issue #5538)** On Linux (.NET 8+), registers a second SetDllImportResolver on IBM.Data.Db2.DB2Connection.Assembly that resolves libdb2.so from <baseDir>/clidriver/lib/libdb2.so -- fixing intermittent CI failures where LD_LIBRARY_PATH does not propagate reliably to the testhost subprocess on CI.
- Registers ActivityHierarchyFactory (debug) or ActivityStatistics.Factory (metrics) via ActivityService.
- Forces ClickHouseOptions.Default with UseStandardCompatibleAggregates = true -- required for test expectations.
- Registers SqlCE provider factory from a hardcoded path on non-NETFX.
- Sets OracleConfiguration.SqlNetAllowedLogonVersionClient = Version11 (enables Oracle 11 protocol with v23 client).
- On NETFX (non-Azure): installs AppDomain.AssemblyResolve handler to resolve IBM.Data.DB2 and IBM.Data.Informix from GAC.
- Calls TestNoopProvider.Init(), SQLiteMiniprofilerProvider.Init(), CustomizationSupport.Init().
- [OneTimeTearDown]: dumps ActivityStatistics.GetReport() and optionally writes metrics baselines via BaselinesWriter.WriteMetrics.

Tests/Linq/AssemblyInfo.TestProgress.cs -- assembly-level [assembly: TestProgressReporter] attribute; provides a live heartbeat for long test runs. **(updated, this delta)** opt-in switched from the LINQ2DB_TEST_PROGRESS environment variable to a --test-progress command-line option -- see .claude/docs/testing.md for monitoring details (the prior delta entry describing the env-var form is now out of date; corrected here, see AUDIT-NOTE).
**(updated, delta 2026-10-09)** TestsInitialization.cs (Tier 1, re-read in full) now does considerably more than the list above:

- `[assembly: Parallelizable(ParallelScope.All)]` plus `NUnit.ParallelByResource`: OneTimeSetUp installs a `ResourceLaneDispatcher` with a `DatabaseLaneStrategy`, so each provider context gets its own lane and same-database tests never overlap. Concurrency ceiling is `TestConfiguration.MaxParallelLanes` or 2 x CPU count. Sets `TestBase.ParallelExecutionEnabled`. Lane tracing is opt-in via `TestEnvironment.ParallelDiagnostics`. OneTimeTearDown calls `_dispatcher.Shutdown(...)` and `TestInMemoryDatabases.DisposeAll()`.
- Providers that reach tests as arguments but have no `CreateDatabase` case (Northwind contexts, TestNoopProvider) are pre-marked ready via `CustomTestContext.MarkDatabaseReady`, otherwise their lane blocks on the readiness latch for the full timeout (pinned by Infrastructure/ParallelExecutionTests.cs).
- Process-wide query cache is capped (`QueryCache.Default.MaxEntriesOverride`, 100 entries) on x86 and on NETFRAMEWORK legs, overridable via `TestEnvironment.QueryCacheMax` (env L2DB_TEST_QUERYCACHE). 64-bit non-netfx legs keep the default because a small cap breaks exact-miss-count cache tests.
- `SetupInMemoryDatabases()` keeps one shared-cache in-memory connection open per SQLite config (SQLite.Classic, .MPU, .MPM, SQLite.MS, Northwind.SQLite, Northwind.SQLite.MS) and for DuckDB (non-NETFX), preloading from the committed on-disk file (SQLite online backup, DuckDB EXPORT/IMPORT DATABASE via Parquet). Only activates when the connection string is in-memory (CI).
- `SetupAccessKeepAlive()` holds one Access connection open per transport (ODBC, OLE DB) for the whole run, registered in the same keep-alive list. Rationale is measured and documented inline (ACE driver has no pooling, leaks handles on every connect). It is explicitly not a crash guard for dotnet/runtime#46187.
- SQLite native resolution now also sets the `PreLoadSQLite_BaseDirectory` environment variable (see SQLite.Runtime.props for the netfx deployment gap).

**(updated, delta 2026-10-09)** Tests.csproj: ClickHouseTests.tt/.generated.cs T4 pair registered next to the MySql/Oracle/PostgreSQL/SqlCe/SqlServer pairs, and `Source/LinqToDB.CLI/CommandLine/Commands/QueryExecution/QueryValueFormatter.cs` is compiled into the test assembly as `DataProvider/QueryValueFormatter.cs` (all TFMs except net462) so that DataProvider/ProviderSpecificReaderValueTests.cs exercises the exact formatter source the CLI uses.

## Subsystems (subdirectory taxonomy)

| Subdirectory | File count | Purpose | Representative files | Production area(s) validated |
|---|---|---|---|---|
| Linq/ | ~189 | Per-LINQ-operator/feature fixtures. Core of the suite. **(grew this delta)** new EagerLoadingStrategy*/EagerLoadingWideKey, ImplicitCollectionLoading, PreferClientCalculation, QueryCacheEviction, TphInheritance fixtures; WindowFunctionsTests family grew 13 -> 46 files and is now compiled (see Delta section). | JoinTests.cs, GroupByTests.cs, CteTests.cs, EagerLoadingTests.cs, WindowFunctionsTests.cs | EXPR-TRANS, SQL-PROVIDER, SQL-AST |
| UserTests/ | ~267 | Issue-numbered regression repros (Issue<N>Tests.cs). **(grew this delta)** Issue5347/5575/5616/5625/5666Tests.cs added. | Issue2296Tests.cs, Issue5302Tests.cs, Issue3586Tests.cs | All areas (cross-cutting) |
| Update/ | ~53 | DML operations: Insert, Update, Delete, Merge, BulkCopy, CreateTable, TempTable, TruncateTable, MultiInsert, OutputWithRows. **(grew this delta)** new entity-builder DML (EntityInsertTests.cs, EntityUpdateTests.cs, EntityDmlApiParametersValidationTests.cs) and the Upsert<T> API family (UpsertTests.Single/Enumerable/Queryable/ApiParametersValidation.cs). Merge family has 19 partial files. InsertWithOutput/DeleteWithOutput/UpdateWithOutput cover SQL Server, Firebird, PostgreSQL, SQLite, Ydb output-clause support. | MergeTests.cs (+18 partials), EntityInsertTests.cs, UpsertTests.Single.cs, BulkCopyTests.cs | EXPR-TRANS, SQL-PROVIDER, PROV-* |
| DataProvider/ | ~35 | Provider-specific type-mapping and vendor feature tests. Root files cover Access, DB2, Informix, SqlCe, SqlServer, PostgreSQL (array + extensions), SQLite, Ydb. **(new this delta)** YdbRetryPolicyTests.cs, YdbTransientExceptionDetectorTests.cs. Types/ subfolder has 8 per-vendor type-framework files. | SqlServerTests.cs, OracleTests.cs, PostgreSQLTests.cs, YdbRetryPolicyTests.cs | PROV-SQLSERVER, PROV-ORACLE, PROV-POSTGRES, PROV-YDB, etc. |
| Extensions/ | ~19 | Query hints, table aliases, vendor SQL extensions (SqlServer, MySQL, Oracle, PostgreSQL, SQLite, Access, ClickHouse). **(new this delta)** Extensions/YdbTests.cs (YdbHints.Unique/Distinct, AsYdb()). .generated.cs files are T4 output (see below). | QueryHintsTests.cs, SqlServerTests.cs, YdbTests.cs, DocExampleTests.cs | SQL-PROVIDER, PROV-* |
| Mapping/ | ~14 | Fluent mapping, attribute mapping, MappingSchema, value converters, enum mapping, dynamic columns, column aliases, expression methods, ConversionType. **(new this delta)** ValueConverterColumnDbTypeTests.cs. | FluentMappingTests.cs, MappingSchemaTests.cs, ValueConverterColumnDbTypeTests.cs | METADATA |
| Data/ | ~9 | DataConnection, transactions, retry policy, tracing, interceptors, stored procedures, QueryMultipleResult, MiniProfiler integration. | InterceptorsTests.cs, DataConnectionTests.cs, TransactionTests.cs, MiniProfilerTests.cs | INTERCEPTORS, INTERNAL-API |
| Common/ | ~13 | Utility/runtime helpers: ChangeType, Convert, Extensions, DefaultValue, ValueComparer, reserved words, EnumerableHelper, DataTools, ConnectionBuilder, SettingsReader, MemberInfoEqualityComparer. Also: AssemblyAvailabilityTests. | ConvertTests.cs, ValueComparerTests.cs, ReservedWordTest.cs | INTERNAL-API |
| Exceptions/ | ~9 | Validates that unsupported operations throw expected exception types. Mirrors Linq/ categories but tests error paths. Includes StackUseTests.cs for ExpressionVisitorBase / QueryElementVisitor stack-hop behavior. | CommonTests.cs, JoinTests.cs, AggregationTests.cs, StackUseTests.cs | EXPR-TRANS, SQL-AST |
| Infrastructure/ | ~6 | Test infrastructure self-tests: ActiveIssue attribute behavior, DataOptions builder, IdentifierBuilder, nullability context, Annotatable. **(grew this delta)** DataOptionsTests.cs gained WithDefaultEagerLoadingStrategyTest, WithImplicitCollectionLoadingTest, OptimizeForSequentialAccessConfigurationIDTest. | ActiveIssueConfigurationTests.cs, DataOptionsTests.cs, AnnotatableTests.cs, NullabilityContextTests.cs | TESTS-INFRA, INTERNAL-API |
| Metadata/ | ~3 | Attribute reader, XML reader, System.Data.Linq attribute reader (NETFX-only). | AttributeReaderTests.cs, XmlReaderTests.cs, SystemDataLinqAttributeReaderTests.cs | METADATA |
| SchemaProvider/ | ~3 | Schema introspection: SchemaProviderTests.cs, PostgreSQLSchemaProviderTests.cs, SqlServerTests.cs. | SchemaProviderTests.cs | SCAFFOLD |
| Scaffold/ | ~3 | Code generation name resolution and type-mapping: NameGenerationTests.cs, SchemaProviderTests.cs, TypeParserTests.cs. | NameGenerationTests.cs | SCAFFOLD, IN-TREE-TOOLS |
| TypeMapping/ | ~2 | Dynamic type-mapping wrapper tests (Oracle and generic). MappingTests.cs exercises ExpressionTypeMapper, delegate mapping, event wrapping. | OracleWrappingTests.cs, MappingTests.cs | PROV-ORACLE, INTERNAL-API |
| Reflection/ | ~2 | TypeAccessor and attribute reflection tests. AttributesTests.cs includes DynamicColumnInfo attribute API coverage. | TypeAccessorTests.cs, AttributesTests.cs | INTERNAL-API |
| Tools/ | ~5 | ComparerBuilder, DecimalHelper, ToDiagnosticString, entity-service identity map, mapper tests. MapperTests.cs exercises MapperBuilder<TFrom,TTo> and Map.GetMapper<T1,T2>(). | MapperTests.cs, IdentityMapTests.cs | IN-TREE-TOOLS |
| Samples/ | ~4 | Illustrative usage patterns: concurrency check, exception intercept, join operator, JSON conversion. JsonConvertTests.cs demonstrates MappingSchema-based JSON column converter via Newtonsoft.Json. | ConcurrencyCheckTests.cs, JsonConvertTests.cs | INTERNAL-API |
| OrmBattle/ | ~3 | Tests ported from the [ORMBattle.NET](http://ormbattle.net) benchmark suite (originally by Alexis Kochetov, 2009; T4-generated, updated 2015). Uses Northwind test model. Helper/ contains ExpressionUtils and GenericEqualityComparer. | OrmBattleTests.cs, Helper/ExpressionUtils.cs, Helper/GenericEqualityComparer.cs | EXPR-TRANS, SQL-PROVIDER |
| Microsoft/ | ~1 | OData query-composition integration test against Microsoft.AspNetCore.OData (net8+) and Microsoft.AspNet.OData (net462). | MicrosoftODataTests.cs | INTERNAL-API, EXPR-TRANS |
| ThirdParty/ | ~1 | Third-party LINQ extension compatibility (LinqKit.Core -- PredicateBuilder, AsExpandable()). | LinqKitTests.cs | EXPR-TRANS |
| AST/ | ~1 | SQL AST unit tests: SqlDataTypeTests.cs. Single test: SqlDataType.GetDataType(DataType.Boolean).SystemType. | SqlDataTypeTests.cs | SQL-AST |
| Create/ | ~1 | CreateData.cs -- utility class (no namespace, class a_CreateData) that populates test-database tables for all providers. Uses BulkCopy for seed rows and per-provider DbConnection action callbacks for binary/text data. [Order(-1)] ensures it runs first. **(updated this delta)** the YDB seed-script dispatch now matches context.IsAnyOf(TestProvName.AllYdb) instead of the single ProviderName.Ydb case. | CreateData.cs | TESTS-INFRA |

Counts in the table above date from earlier runs. The 2026-10-09 delta below adds Linq/ (IntervalTranslationTests x7, ParameterTests.Naming/Reuse, ConcurrencyRefreshTests, SqlRawSqlTableTests, WindowFunctionsTests.ConstantOrderBy), Infrastructure/ (ActiveIssueTests, BaselinesManagerTests, ParallelExecutionTests, TestProgressStateTests), Mapping/DurationMappingTests, DataProvider/ProviderSpecificReaderValueTests, Extensions/ClickHouseTests (.tt + .generated.cs), Scaffold/SqlServerDecimalOverflowProtectionTests and 6 UserTests/ regressions (27 files added, 2 deleted).

## Delta since prior run (sha 7f972dbce -> 4a478ff14)

~70 files changed across six cross-cutting PRs:

### PR #5451 -- DuckDB provider tests

New file: DataProvider/Types/DuckDBTypeTests.cs -- sealed DuckDBTypeTests : TypeTestsBase tagged [TestFixture] under #if SUPPORTS_DATEONLY. Exercises the full DuckDB type surface via TypeTestsBase.TestType<TType,TNullableType>():

- **Boolean:** bool.
- **Integer:** sbyte/byte/short/ushort/int/uint/long/ulong, BigInteger (Int128 / UInt128 / variable-length HugeInt/BigNum). Provider bug with UHugeInt range commented out; BigNum (VARINT) uses literal-only mode (expectedParamCount: 0) due to provider read corruption.
- **Float/Double:** including NaN, PositiveInfinity, NegativeInfinity.
- **Decimal:** DECIMAL(18,3) default plus precision 1..38 with scale sweep.
- **String/Binary:** VARCHAR (string + char), BLOB (byte[] + System.Data.Linq.Binary), BITSTRING (BitArray + string + byte[] with DataType.BitArray; provider: expectedParamCount: 0, BulkCopy excluded).
- **UUID:** Guid.
- **Date/Time:** DATE (DateOnly + DateTime.Date + DuckDBDateOnly with infinity); TIME (TimeOnly + TimeSpan + precision 0/5/6; TIME_NS p=7/9 disabled due to provider ArgumentException); TIMETZ (TimeSpan + DateTimeOffset); INTERVAL (TimeSpan + DuckDBInterval; negative interval support missing); TIMESTAMP (DateTime x TIMESTAMP/TIMESTAMP_S/TIMESTAMP_MS/TIMESTAMP_NS precision ladder + DuckDBTimestamp native type); TIMESTAMPTZ (DateTimeOffset).
- **JSON:** string with DataType.Json.
- TestBulkCopyType local function skips BulkCopyType.ProviderSpecific for types the provider does not support in bulk copy.
- Known provider limitations documented in comments: UTINYINT range bug, \0/\x1 char parameter issues, TIME_NS type code 39 unknown, negative INTERVAL, UHugeInt range, BigNum read corruption.

DuckDB was also added to existing fixtures (sampled from changed file list): ConflictActionTests.cs adds TestProvName.AllDuckDB to [IncludeDataSources] for IgnoreConflictsTest / IgnoreConflictsTestAsync -- validates BulkCopyOptions { ConflictAction = ConflictAction.Ignore } with MultipleRows mode ignores PK conflicts and inserts non-conflicting rows. Similar DuckDB additions are present in BulkCopyTests.cs, DateTimeFunctionsTests.cs, DateTimeOffsetTests.cs, DataTypesTests.cs, MergeTests.*, and other fixtures throughout the delta set.

### PR #5495 -- AsQueryable parameterization (issue #5424)

New file: Linq/EnumerableSourceTests.AsQueryable.cs -- partial of EnumerableSourceTests. Covers the new three-argument IEnumerable<T>.AsQueryable(IDataContext, Action<IAsQueryableBuilder>) overload added in PR #5495. Tests:

- AsQueryable_Parameterize_AllParameters -- verifies SQL contains no inlined literals when .Parameterize() is configured.
- AsQueryable_Inline_AllInlined -- verifies SQL contains inlined literals when .Inline() is configured.
- AsQueryable_Parameterize_ExceptId_InlinesId / AsQueryable_Inline_ExceptData_ParameterisesData -- .Except(p => p.Id) / .Except(p => p.Data) flip individual member between inline/parameter mode.
- Cache stability: AsQueryable_Parameterize_CacheStable_AcrossDataChanges -- same-shape but different-data second query hits cache (no GetCacheMissCount() increase).
- Cache hit across NUnit [Values(1, 2)] iterations for Parameterize, Inline, and Parameterize().Except(p => p.Id) modes.
- Scalar int list, inline array, inline-array-in-SelectMany (expects LinqToDBException with 'AsQueryable configure' message).
- JOIN and CROSS APPLY patterns through parameterized enumerable source.
- Nested member (p.Address!.Zip) in .Except().
- Error cases: non-member selector (p.Id + 1), bare parameter (p => p), captured external member (other.Id) all throw LinqToDBException.
- CompiledQuery.Compile integration -- static _compiledConfiguredAsQueryable field reused across two invocations with different row counts/seeds.
- Provider exclusions: Access and ClickHouse excluded from most tests (join/apply patterns further restrict to SQL Server 2008+, PostgreSQL 9.3+, Oracle 12+, MySqlWithApply).

### PR #5467 -- DateTime.Now translation

DateTimeFunctionsTests.cs and DateTimeOffsetTests.cs updated. Changes are at the summary level (DuckDB provider additions and per-provider now-translation behavior assertions). The precise test changes verify that DateTime.Now / DateTimeOffset.Now / DateTime.UtcNow emit the correct provider-specific SQL for DuckDB (and may adjust expectations for other providers). See PROV-DUCKDB area for translation specifics.

### PR #5517 -- DateTime.Date DbType preservation

DateTimeFunctionsTests.cs updated. Issue #5309: DateTime.Date truncation cast was dropping the column original DbType, causing incorrect type on the generated SQL parameter. Tests updated to verify the DbType is preserved after .Date access on a typed column. Involves SaveCommandInterceptor pattern to inspect DbCommand.Parameters (similar to Issue488Tests.cs pattern).

### PR #5503 -- Enum.HasFlag translation

ExpressionsTests.cs updated -- the Expressions.MapMember for Enum.HasFlag section receives additional coverage or provider-specific assertions. ClickHouse uses bitShiftLeft extension; SQL Server and others use bitwise AND. The test validates the SQL shape via ToSqlQuery().

### PR #5455 -- BulkCopy ConflictAction

ConflictActionTests.cs (new or substantially revised) -- validates BulkCopyOptions { BulkCopyType = BulkCopyType.MultipleRows, ConflictAction = ConflictAction.Ignore } against MySQL/PostgreSQL/SQLite/DuckDB. Sync and async variants. Verifies: conflicting PK rows (1, 2) retain original values; non-conflicting row (3) is inserted. Both table.BulkCopy(...) and table.BulkCopyAsync(...) paths exercised.

### Delta since prior run (sha 4a478ff14 -> 2e67bafc9) -- v6 string-concat / aggregate-nullability / trim

~23 files changed across several cross-cutting PRs (string concat, trim, aggregate nullability, AOT, issue regressions):

#### PR #5504 -- SqlConcatExpression / string concat overhaul

New file: Linq/StringConcatTests.cs -- covers the new SqlConcatExpression translation path introduced in PR #5504. Tests span basic concat forms, nullable semantics (COALESCE wrap for potentially-null operands, issue #1916), SELECT/ORDER BY positions, array-form concat, aggregate (grouping) concat (STRING_AGG / GROUP_CONCAT / LISTAGG per provider), AggregateExecute, association-subquery concat, partial translation, string-interpolation equivalence, and provider exclusions/throws.

**Updated (issue #5530):** New test Concat_Sybase_NullGuardOnlyForNullableOperands -- Sybase ASE CONCAT null guard must only apply to actually-nullable operands; non-nullable columns and string literals must not get a redundant IS NULL guard.

#### PR #5515 -- TrimStart/TrimEnd with char sets

New file: Linq/StringTrimTests.cs -- covers new TrimStart(char[]) / TrimEnd(char[]) LINQ translation for issue #5515: whitespace trim (no-arg/empty-array/null-array), single-char trim, multi-char set (literal and captured array), cache semantics, legacy TrimLeft/TrimRight null-propagation, and provider-specific SQL-shape assertions (Oracle LTRIM/RTRIM, SQL Server NVarChar N literal, MySQL 8 TRIM(LEADING/TRAILING), ClickHouse trim functions).

#### PR #5557 -- Aggregate nullability (non-nullable Sum COALESCE wrap in subquery)

New file: Linq/AggregationNullabilityTests.cs -- covers issue #5557 fix: non-nullable Sum in subquery position must wrap with COALESCE to match LINQ semantics (empty sequence returns 0), while nullable Sum, Min, Max, Average must not wrap.

#### PR #5552 -- AOT / MemberInfoEqualityComparer

New file: Common/MemberInfoEqualityComparerTests.cs -- pure unit test. Covers issue #5551: Native AOT emits a synthetic constructor type for lambda closures whose MetadataToken accessor throws.

#### New UserTests fixtures (prior delta)

- Issue5125Tests.cs -- IExpressionPreprocessor wrapping OrderBy in a NULLS FIRST Sql.Expr; optimizer must not embed directive inside subquery column. PostgreSQL only.
- Issue5154Tests.cs -- SqlQueryDependentParams + multi-level eager-loaded projection; ToSqlQuery / ToArray ordering in either direction. SQLite.
- Issue5505Tests.cs -- UPDATE SET with ServerSideOnly function (jsonb_set) on a ValueConverter-backed column. PostgreSQL 9.5+.

#### Modified fixtures (skim)

-  -- , ,  added.
-  --  added (string-aggregate parameter placement).
- , , , , , , ,  -- minor additions or provider-set expansions; no new fixture-level structures.
-  -- provider additions or MiniProfiler adapter refinements.
-  -- SQL Server-specific additions.
-  -- additional guard / async cancellation tests.
-  -- row-constructor update additions.
-  -- minor provider additions only.n
### Other changed files (cross-cutting)

The remaining ~55 changed files fall into these categories (not individually enumerated -- delta is additive, not structural):

- **Data/**: DataConnectionTests.cs, DataExtensionsTests.cs, TransactionTests.cs -- minor updates, likely DuckDB connection-lifecycle additions and/or async transaction coverage refinements.
- **DataProvider/**: FirebirdTests.cs, PostgreSQLTests.cs, SqlServerTests.cs -- provider-specific additions (DuckDB ripple or independent fixes).
- **Extensions/ClickHouseTests.cs**: ClickHouse-specific additions.
- **Infrastructure/DataOptionsTests.cs**: DataOptions builder coverage updates.
- **Linq/**: ~30 files -- primarily DuckDB provider additions to [IncludeDataSources] or [DataSources] attributes across AnalyticTests, CharTypesTests, CteTests, CteMaterializedTests, DataTypesTests, DefaultIfEmptyTests, EnumerableSourceTests, ExceptByMethodTests, GroupByExtensionsTests, IdlTests, InterfaceTests, IntersectByMethodTests, JoinTests, MinByMaxByMethodTests, ParameterTests, PredicateTests, SetOperatorTests, SqlExtensionTests, StringFunctionTests, StringFunctionsTests, SubQueryTests, TableOptionsTests, TypesTests, UnionByMethodTests, WhereTests. Also ConvertExpressionTests, ConvertTests -- expression/conversion coverage updates.
- **Mapping/**: ConversionTypeTests.cs, FluentMappingBuildTests.cs -- mapping coverage updates.
- **Update/**: BulkCopyTests.cs, DeleteTests.cs, DeleteWithOutputTests.cs, InsertTests.cs, InsertWithOutputTests.cs, MergeTests.* (10 files), UpdateFromTests.cs, UpdateTests.cs, OldMergeTests.cs -- DuckDB provider additions and possibly conflict-action coverage expansion.
- **UserTests/**: Issue1238Tests.cs, Issue269Tests.cs, Issue3432Tests.cs, Issue356Tests.cs, Issue445Tests.cs, Issue792Tests.cs, LetTests.cs -- regression additions or DuckDB provider additions.
### Delta since prior run (sha 2e67bafc9 -> b3340aa9d) -- YdbMemberNotFound removal, nested-mapping, assembly availability, NodaTime

~58 files changed across several PRs:
#### YdbMemberNotFoundAttribute removal (cross-cutting)

Tests/Linq/YdbToDoAttributes.cs -- YdbMemberNotFoundAttribute class removed. It was a YDB-specific ThrowsForProviderAttribute wrapping YdbException/InvalidOperationException with ErrorMessage matching the member-not-found message. The fix it gated is now implemented.
Across ~35 fixtures, [YdbMemberNotFound] replaced with [ThrowsRequiresCorrelatedSubquery(simple: true)]. Affected fixtures:

- Linq/AllAnyTests.cs, Linq/AssociationTests.cs, Linq/CommonTests.cs, Linq/CteTests.cs, Linq/ConcatUnionTests.cs, Linq/ContainsTests.cs, Linq/ConvertExpressionTests.cs, Linq/ConvertTests.cs, Linq/CountByMethodTests.cs, Linq/DistinctByMethodTests.cs, Linq/DistinctTests.cs, Linq/EnumMappingTests.cs, Linq/EnumerableSourceTests.cs, Linq/ExceptByMethodTests.cs, Linq/ExpressionsTests.cs, Linq/GuidTests.cs, Linq/IndexMethodTests.cs, Linq/IntersectByMethodTests.cs, Linq/IssueTests.cs, Linq/JoinTests.cs, Linq/MinByMaxByMethodTests.cs, Linq/OrderByTests.cs, Linq/ParameterTests.cs, Linq/PredicateTests.cs, Linq/ProjectionTests.cs, Linq/SelectTests.cs, Linq/SetOperatorComplexTests.cs, Linq/SetOperatorTests.cs, Linq/SetTests.cs, Linq/SqlRowTests.cs, Linq/StringFunctionsTests.cs, Linq/SubQueryTests.cs, Linq/UnionByMethodTests.cs, Linq/WhereTests.cs, Linq/CharTypesTests.cs
- Update/DeleteTests.cs (Delete3, Delete4, AlterDelete, DeleteMany1), Update/UpdateTests.cs (UpdateAssociation1Old through UpdateAssociation3, 6+ occurrences), Update/UpdateWithOutputTests.cs (Issue4193Test)
- UserTests/Issue269Tests.cs, UserTests/Issue825Tests.cs, UserTests/Issue2619Tests.cs, UserTests/Issue2816Tests.cs, UserTests/Issue3402Tests.cs, UserTests/SelectManyDeleteTests.cs, UserTests/UnnecessaryInnerJoinTests.cs

Pattern: tests previously expected YDB to throw 'Member not found'; now expect the standard correlated-subquery exception. Some fixtures also drop TestProvName.AllClickHouse from [DataSources] exclusion lists.
#### PR #5543 -- Nested member column mapping (MergeTests.ComplexProperty.cs)

New file: Update/MergeTests.ComplexProperty.cs -- partial of MergeTests (namespace Tests.xUpdate). Covers FluentMappingBuilder nested-member column mapping (column path crosses intermediate object, e.g. o => o.Nested.Field). Tests:

- ComplexProperty_UpdateWhenMatched -- [MergeDataContextSource]; UpdateWhenMatched() writes through nested path; unmatched row retains original nested value.
- ComplexProperty_InsertUpdate -- UpdateWhenMatched() + InsertWhenNotMatched() three-row scenario; both paths walk nested accessor.
- ComplexProperty_UpdateWithDelete -- Oracle-only ([IncludeDataSources(true, TestProvName.AllOracle)]); UpdateWhenMatchedAndThenDelete with nested column access.
- ExplicitInterfaceProperty_UpdateWhenMatched -- regression: explicit interface CLR name has dot (e.g. IExplicitComplexProperty.Field); dot-path splitter must NOT treat it as nested path. [MergeDataContextSource].
- ComplexProperty_NestedDiscriminator -- inheritance discriminator via nested member; OfType<NestedDiscriminatorDog>() must walk nested discriminator path. [DataSources].
- ComplexProperty_NestedPrimaryKey_OnTargetKey -- PK via [Column(MemberName = 'Key.Value')]; OnTargetKey() must dot-walk both sides of ON condition. [MergeDataContextSource].
#### TestsInitialization.cs update (issue #5538 -- Linux DB2/Informix native library resolver)

Added SetDllImportResolver for IBM.Data.Db2.DB2Connection.Assembly on Linux. Resolves libdb2.so from baseDir/clidriver/lib/libdb2.so. Guard: OperatingSystem.IsLinux() + File.Exists(path). Fixes intermittent CI failures where LD_LIBRARY_PATH does not propagate to testhost subprocess. Handle cached in IntPtr db2Handle closure.

#### Common/AssemblyAvailabilityTests.cs -- new fixture (issue #5538)

New class AssemblyAvailabilityTests (no TestBase inheritance; pure unit test). Tests LinqToDB.Internal.Common.Tools.IsProviderAssemblyPresent(name):

- ReturnsTrueForLoadedSelfAssembly -- the test assembly is loaded -> true.
- ReturnsTrueForLinqToDbCoreAssembly -- linq2db is referenced + loadable -> true.
- ReturnsFalseForNonexistentAssembly -- LinqToDB.Does.Not.Exist.ZZZ -> false; confirms internal Assembly.Load exception is swallowed.
- ReturnsTrueViaFileProbeForDeployedButUnloadableAssembly -- writes a non-PE .dll next to the linq2db assembly, verifies file-probe fallback returns true. Uses Shouldly for assertions.

#### Infrastructure/DataOptionsTests.cs update

Two new tests:

- WithDefaultNullsPositionTest -- pure unit; SqlOptions.WithDefaultNullsPosition(Sql.NullsPosition.Last) and DataOptions.UseDefaultNullsPosition(Sql.NullsPosition.First).
- ConfigurationSqlDefaultNullsPositionTest -- [NonParallelizable]; tests static Configuration.Sql.DefaultNullsPosition global; saves + restores prior value in finally.
#### DataProvider/OracleTests.cs update -- DateTimeOffset TIMESTAMP literal fix

TestDateTimeSQL updated: DateTimeOffset with positive UTC offset (Nepal +00:45) now emits local-time+offset form (e.g. TIMESTAMP '2020-01-03 04:05:06.789123 +00:45') rather than UTC-normalized form.
New test TestDateTimeOffsetToTimestampLiteral directly exercises db.MappingSchema.ValueToSqlConverter.TryConvert for zone-less TIMESTAMP column binding.

#### DataProvider/PostgreSQLTests.cs update -- NodaTime COALESCE (issue #5549)

New region Issue 5549: Issue5549Table entity (NodaTime.Instant nullable + non-nullable columns via DbType = timestamptz). Tests use UseConnectionFactory + NpgsqlDataSourceBuilder.UseNodaTime():

- Issue5549Test_BuiltInCoalesce -- (e.ClosedAt ?? e.CreatedAt) >= fromDate COALESCE via ?? operator; confirms two-row result.
- Additional variants test [Sql.Extension] builder and [Sql.Expression] raw-template approaches. Provider: TestProvName.AllPostgreSQL.

#### Update/BulkCopyTests.cs -- DateOnlyTable PK change

DateOnlyTable.Date changed from [PrimaryKey, Identity] to [PrimaryKey] (Identity removed). Reason: YDB BulkUpsert requires explicit PK; sole integer Identity PK becomes auto-SERIAL on YDB, conflicting with BulkUpsert.

#### Linq/StringConcatTests.cs update (issue #5530)

New test Concat_Sybase_NullGuardOnlyForNullableOperands -- verifies Sybase/SAP HANA CONCAT null guard emitted only for nullable operands. StringConcatNullEntity.ID decorated with [PrimaryKey].

#### UserTests/Issue5576Tests.cs -- new fixture (issue #5576)

New class Issue5576Tests : TestBase. Tests three-stage projection LEFT JOIN that previously produced spurious [item] column in VALUES clause (InvalidCastException: Failed to convert parameter value from T to Decimal). Shape: Campaign table LeftJoin with in-memory Counts[] (class, not struct) -> Stat -> WithRate (decimal arithmetic) -> Result re-mapping. [ActiveIssue(5611, Configuration = TestProvName.AllSQLite)] for SQLite integer-division issue.

#### AssemblyInfo.TestProgress.cs -- new assembly attribute

New file Tests/Linq/AssemblyInfo.TestProgress.cs. Single-line content: [assembly: TestProgressReporter]. Opt-in live test progress heartbeat via LINQ2DB_TEST_PROGRESS env var (**superseded this delta -- see below**).
### Delta since prior run (sha b3340aa9d -> 36ee4f82f) -- window-function surface expansion, entity-builder DML, Upsert API, eager-loading strategies

188 files changed under Tests/Linq/ (56 added, 131 modified, 1 deleted). The two largest structural shifts: the WindowFunctionsTests family goes from 13 excluded files to 46 compiled files, and two new DML entrypoint families land (entity-builder Insert/Update, Upsert<T>).

#### Tests.csproj -- WindowFunctionsTests family reactivated

The Compile-Remove ItemGroup that excluded 13 WindowFunctionsTests.*.cs partials (Average, Cume, DenseRank, Frame, Max, Min, NTile, PercentRank, PercentileCont, Rank, RowNumber, Sum, plus the root .cs) is deleted from Tests/Linq/Tests.csproj. The family now compiles and runs -- this directly resolves the prior Known issues / debt entry saying the family was uncompiled (see corrected entry below and AUDIT-NOTE).
Also added: an X86STUBS condition on the Sap.Data.Hana.Net.v8.0 Reference ItemGroup -- x86 builds skip the x64-only HANA native assembly and fall back to HANASTUBS stub types (mirrors the existing DB2 stub pattern), avoiding a ReflectionTypeLoadException that made NUnit discover zero tests on x86.

#### WindowFunctionsTests family growth: 13 -> 46 files (Linq/WindowFunctionsTests.*.cs)

33 new partials, all `partial class WindowFunctionsTests : TestBase` in namespace Tests.Linq: Combinations, Corr, Count, CovarPop, CovarSamp, Equality, Filter, FirstValue, FrameExclusion, HypotheticalSet, Keep, Lag, LastValue, Lead, Median, NthValue, PercentileDisc, RatioToReport, RegrAvgX, RegrAvgY, RegrCount, RegrIntercept, RegrR2, RegrSXX, RegrSXY, RegrSYY, RegrSlope, StdDev, StdDevPop, StdDevSamp, VarPop, VarSamp, Variance.

Shared shape (confirmed by full reads of Combinations, Corr, HypotheticalSet, RegrSlope): each test method takes a `[SupportsAnalyticFunctionsContext] string context` and one or more `[ThrowsForProvider(typeof(LinqToDBException), <providers without the function>, ErrorMessage = ErrorHelper.Error_WindowFunction_Category)]` attributes, asserts the SQL text via `query.ToSqlQuery().Sql.ShouldContain("FUNCTION_NAME")`, then executes `query.ToList()`. Two call forms per function: inline `w => w.PartitionBy(...).OrderBy(...)` and the shared-window form via `Sql.Window.DefineWindow(...)` plus `w.UseWindow(wnd)`.

Statistical/ordered-set/hypothetical-set functions (REGR_*, CORR, COVAR_POP/SAMP, STDDEV_POP/SAMP, VAR_POP/SAMP, VARIANCE, MEDIAN, PERCENTILE_DISC, and RANK/DENSE_RANK/PERCENT_RANK WITHIN GROUP for hypothetical-set) are native mainly on Oracle and PostgreSQL and throw LinqToDBException elsewhere via the new ErrorHelper.Error_WindowFunction_* constant family (LinearRegression, Correlation, HypotheticalSet, etc.). This is the finer-grained mechanism that the coarse Is*Supported flags could not express (see Known issues / debt).

The 13 pre-existing partials were revised in place now that they actually compile and run. WindowFunctionsTests.Frame.cs grew the most: new tests AggregateWithFilter, AggregateWithFrame, CountArgWithFrame, AggregateWithFrameExclude cover Filter()/RowsBetween/RangeBetween/frame-exclusion combinations, each gated per-provider via distinct ErrorHelper.Error_WindowFunction_AggregateWindowFunctions / FrameRows / FrameRange / FrameExclude constants. The shared entity WindowFunctionTestEntity (root WindowFunctionsTests.cs) seeds rows via a static Seed() array covering int/long/double/decimal/float/short/byte (plus nullable variants), CategoryId, Timestamp.

Related memory: this directly supersedes the earlier gap noted for HANA/Informix/SqlServer statistical-window asymmetry (project_window_fn_coarse_flags) -- the ErrorHelper.Error_WindowFunction_* plus [ThrowsForProvider] combination is the finer flag/name-mapping mechanism that note called for.

#### Entity-builder DML API (Update/EntityInsertTests.cs, Update/EntityUpdateTests.cs, Update/EntityDmlApiParametersValidationTests.cs -- all new)

New extension overloads (namespace Tests.xUpdate; LinqExtensions on the production side): Insert<T>(ITable<T>, T item, Expression<Func<IEntityInsertSpec<T>, IEntityInsertSpec<T>>> configure) plus InsertAsync, and Update<T>(ITable<T>, T item, Expression<Func<IEntityUpdateSpec<T>, IEntityUpdateSpec<T>>> configure) plus UpdateAsync. This is a fluent per-call builder (b => b.Set(x => x.Field, () => value)) alternative to the whole-object Insert/Update, matching by primary key for Update.

- EntityInsertTests.cs -- Bare, Set_ContextFree (context-free value via a captured local), Set_FromSource (server-side source expression) cases; entity EntityRow (Id/Name/Version/CreatedAt/CreatedBy) under table name EntityInsertTest.
- EntityUpdateTests.cs -- same three-case pattern against EntityUpdateTest (Id/Name/Version/UpdatedAt/UpdatedBy) plus EntityRowNoPk (no-PK negative-path table).
- EntityDmlApiParametersValidationTests.cs -- null-argument guards for all four entrypoints (Insert/InsertAsync/Update/UpdateAsync: null table, null item, null configure expression) via a FakeTable<T> double, no [DataSources] (pure unit test); mirrors the existing MergeTests/UpsertTests ApiParametersValidation convention.

#### Upsert API family (Update/UpsertTests.*.cs -- 4 new partial files, namespace Tests.xUpdate)

New extension Upsert<T> with three source shapes, each in its own partial of `partial class UpsertTests : TestBase`:

- UpsertTests.Single.cs -- Upsert<T>(ITable<T>, T, configure); single-entity, u => u.Match((t,s) => t.Id == s.Id) builder. Entity UpsertRow (Id/Name/Version/CreatedAt/CreatedBy/UpdatedAt/UpdatedBy) under table UpsertTest.
- UpsertTests.Enumerable.cs -- Upsert<T>(ITable<T>, IEnumerable<T>, configure); client-side list/array source, lowers to MERGE.
- UpsertTests.Queryable.cs -- Upsert<T>(ITable<T>, IQueryable<T>, configure); server-side query source (a sub-select inside the generated MERGE); source built via otherTable.AsQueryable().
- UpsertTests.ApiParametersValidation.cs -- null-argument guards (not individually read this delta; same shape as the other three siblings plus EntityDmlApiParametersValidationTests.cs -- see DEFERRED-COVERAGE).

All three data-shape variants share [ThrowsForProvider(typeof(LinqToDBException), <providers without MERGE-lowering support>, ErrorMessage = ErrorHelper.Error_Upsert_MergeLowering_NotSupported)] -- SAP HANA, SQL Server 2005, SQLite, PostgreSQL 14 and below, MySQL, SqlCe, Access. [InsertOrUpdateDataSources] drives the provider set (shared with the existing InsertOrUpdate API).

#### Eager-loading: new strategy coverage plus wide composite keys (Linq/)

- EagerLoadingStrategyKeyedQueryTests.cs / EagerLoadingStrategyUnionTests.cs (new) -- Company -> Department -> Employee(+Tasks) 3/4-level association hierarchies exercising the EagerLoadingStrategy enum (KeyedQuery vs the Default/separate-query strategy). Ties to the new LinqOptions.WithDefaultEagerLoadingStrategy builder (see DataOptionsTests.cs below, PR #5450).
- EagerLoadingWideKeyTests.cs (new) -- composite correlation key with 15 members (KParent.K1..K15 / KChild.F1..F15), which the key-generation machinery represents as a Rest-nested ValueTuple once past 7 members. Exercises both KeyedQuery and Default strategies on the wide-key path. This is regression coverage tied to memory note project_5450_keyedquery_composite_key (defect #2: key-carry projection previously truncated to 7 fields, mis-grouping past that width).
- ImplicitCollectionLoadingTests.cs (new) -- DataOptions.UseImplicitCollectionLoading(ImplicitCollectionLoading.Throw); an un-LoadWith-ed collection navigation projected directly (select new { p.ParentID, p.Children }) throws LinqToDBException mentioning "LoadWith" when the option is Throw, and is a no-op otherwise (Implicit_OptionOff_NoThrow). SQLiteMS only.
- Infrastructure/DataOptionsTests.cs gains WithDefaultEagerLoadingStrategyTest and WithImplicitCollectionLoadingTest (PR #5450: unit coverage for the two new LinqOptions builder methods) plus OptimizeForSequentialAccessConfigurationIDTest (PR #5639: UseOptimizeForSequentialAccess must change IConfigurationID so the query-plan cache does not share a sequential-access plan across differently-configured contexts). Also: TestProviderAutoDetect gains a TestProvName.AllYdb case mapped to UseYdb(connectionString), and ConfigurationSqlDefaultNullsPositionTest drops its [NonParallelizable] attribute.

#### TPH deep-hierarchy regression (Linq/TphInheritanceTests.cs -- new)

TphDeepPersonBase -> ... -> TphDeepPersonLeaf multi-level Table-Per-Hierarchy discriminator chain. TPH_DeepHierarchy_FindRecord / TPH_DeepHierarchy_PolymorphicResult verify that querying via GetTable<TphDeepPersonLeaf>() and the intermediate GetTable<TphDeepPersonChild>() both resolve to the correct concrete leaf instance. SQLite only.

#### Client-calculation preference (Linq/PreferClientCalculationTests.cs -- new)

DataOptions.UsePreferClientCalculation(bool). [Sql.Function("ABS", PreferServerSide = true/false)] and [Sql.Function(ServerSideOnly = true)] combinations verify whether a mapped function stays server-side or moves client-side under the preference flag; a client-only helper with no SQL mapping exercises the fall-through path for an argument that cannot become SQL.

#### Query-cache eviction unit tests (Linq/QueryCacheEvictionTests.cs -- new)

Gated behind BUGCHECK; direct unit tests of QueryCache eviction mechanics (sweep drops expired entries, cap trims oldest, ClearAll wipes) via internal test hooks (RunSweepNow, BucketCount). Stub Query<T> instances have no CompareInfo so Query.Compare always returns false -- this is fine for eviction-mechanics tests, since those code paths do not depend on Compare succeeding. Complements the existing TestQueryCache/CachingTests/ParameterTests correctness suites. [Parallelizable(ParallelScope.All)], no TestBase inheritance, no database access. Not compiled or run in normal builds -- BUGCHECK is a diagnostic-only symbol (see Known issues / debt).

#### YDB: retry policy plus transient-exception detector unit tests, new hint tests

- DataProvider/YdbRetryPolicyTests.cs (new) -- YdbRetryPolicy (LinqToDB.Internal.DataProvider.Ydb) unit tests: Retries_ImmediateCodes (BadSession/SessionBusy/SessionExpired), Retries_JitterCodes (Aborted/Undetermined/Unavailable/ClientTransport*/Overloaded), driven through Policy.Execute with zeroed backoff so tests do not sleep.
- DataProvider/YdbTransientExceptionDetectorTests.cs (new) -- YdbTransientExceptionDetector.TryGetYdbException / TryGetCodeAndTransient unit tests (top-level, nested-in-InvalidOperationException, non-YDB-exception cases). Both new files declare a same-named global::Ydb.Sdk.Ado.YdbException test double (intentional CS0436 suppressed via a pragma) because the real SDK exception type has internal constructors.
- Extensions/YdbTests.cs (new) -- YdbHints.Unique / YdbHints.Distinct query hints via .UniqueHint()/.DistinctHint() and the IYdbSpecificQueryable<T> .AsYdb() entrypoint.
- DataProvider/YdbTests.cs -- [YdbNotImplementedYet] removed from SchemaProvider_ReturnsCreatedTable and SchemaProvider_ReturnsCorrectColumnMetadata (now pass for real); the hardcoded Ctx = "YDB" constant is replaced with TestProvName.AllYdb throughout (**updated, this delta** -- corrects the prior claim that many YdbTests.cs tests remain tagged [YdbNotImplementedYet]; see corrected Notable-findings entry below).
- Create/CreateData.cs -- the YDB seed-script dispatch case switches from the single ProviderName.Ydb match to context.IsAnyOf(TestProvName.AllYdb), matching the multi-variant pattern already used for ClickHouse and DuckDB.
- DataProvider/Types/YdbTypeTests.cs -- minor update only (6 lines changed); no new structural coverage.

#### Ydb-specific ThrowsForProvider wrapper classes retired (Tests/Linq/YdbToDoAttributes.cs deleted)

The whole file is deleted this delta (it had already lost its YdbMemberNotFoundAttribute class in the prior delta). Its remaining four classes -- YdbUnexpectedSqlQueryAttribute, YdbNotImplementedYetAttribute, YdbIntoValuesNotImplementedAttribute, YdbCteAsSourceAttribute, all deriving from ThrowsForProviderAttribute -- have zero remaining usages anywhere under Tests/Linq (confirmed via a full-tree search). The generic [ThrowsForProvider(typeof(...), ProviderName.Ydb, ErrorMessage = "...")] form (used directly in the new WindowFunctionsTests/UpsertTests files) has fully superseded the YDB-specific subclass pattern -- the same-delta trend as the prior run replacement of [YdbMemberNotFound] with [ThrowsRequiresCorrelatedSubquery].

This is a Tier-1 file removal -- see the UNCLASSIFIED-FILE block. kb-areas.md TESTS-LINQ Tier-1 anchor list needs a human update to drop this entry; there is no replacement file, since the pattern moved to direct attribute usage rather than a new shared home file.

#### Value-converter DB-type resolution (Mapping/ValueConverterColumnDbTypeTests.cs -- new)

A [Column, ValueConverter(ConverterType = typeof(MoneyToDecimalConverter))] member with no explicit DataType must resolve its DB type from the converter provider type (decimal), not the member type (Money, which has no DB type of its own) -- via EntityDescriptor.Columns[...].GetDbDataType(true). Without the underlying fix the resolved DataType is Undefined.

#### Test-isolation cleanup: shared static state removed from MergeTests identity fixtures

- Update/MergeTests.Operations.Associations.cs / MergeTests.Operations.IdentityInsert.cs -- PrepareIdentityData(db, context) now returns the seeded rows (idData.Persons[...]) instead of writing into a shared static IdentityPersons field; call sites updated across both files (390 / 150 line diffs, mechanical rename, no behavioral change). Same isolation direction as memory note project_5614_merge_identity_no_polluter (no drift was actually detected there, but shared static test state was flagged as a latent risk worth removing).
- Common/ConvertTests.cs -- SetExpression and ToStringTest now wrap Convert<T1,T2>.Lambda / .Expression mutation in try/finally, restoring to null afterward, preventing static converter-registry state from leaking into later tests.

#### AssemblyInfo.TestProgress.cs -- opt-in mechanism switched

The opt-in for the live progress heartbeat switched from the LINQ2DB_TEST_PROGRESS environment variable to a --test-progress command-line option. The prior delta section above (and the Assembly setup section) described the environment-variable form; that description is now out of date and has been corrected in place (see AUDIT-NOTE). The .claude/docs/testing.md monitoring guide may also need a follow-up update outside this KB run.

#### DB2Tests.cs -- DECFLOAT special-value round-trip (issue #5663)

Three new tests: DecFloatSpecialToFloatingPoint (DECFLOAT +Infinity/-Infinity/NaN, produced via a division-by-zero CAST trick, round-trips through double/float and their nullable forms), DecFloatSpecialToDecimalAndIntegral (the same special values cannot be represented as decimal/int/long -- nullable targets read back null, non-nullable targets read back the type default), DecFloatFiniteValue (a finite DECFLOAT still round-trips exactly through decimal/double after the special-value handling).

#### UserTests: 5 new issue regressions

- Issue5347Tests.cs -- a custom MemberTranslatorBase registering string.Contains overrides that cast a jsonb haystack to text before LOWER/LIKE (PostgreSQL jsonb has no LOWER(jsonb) overload); demonstrates the ITranslationContext.TranslateToSqlExpression plus ExpressionFactory.Cast pattern for a custom member translator.
- Issue5575Tests.cs -- a nullable member left unbound in one projection (Select(c => new StatEntity { Id = c.Id }), LeadCount never assigned) then consumed via .HasValue in a later projection; previously threw InvalidOperationException with message "Called when root is not initialized".
- Issue5616Tests.cs -- UNION ALL with a built-in aggregate (Average) in one branch and a constant in the other, plus a custom [Sql.Extension("count_if(...)", IsAggregate = true)]; previously threw InvalidCastException (SqlPathExpression to SqlPlaceholderExpression) in VisitSqlReaderIsNullExpression.
- Issue5625Tests.cs -- Entity/Item/Thing multi-table nullable-join shape (only the entity definitions were read this delta; the test method bodies past line 50 were not verified -- flag for a future pass if this fixture needs deeper citation).
- Issue5666Tests.cs -- #nullable disable entity with a nullable-enum column (Enum1? Status) and an [Association] on a nullable foreign key; SQLite-only regression.
### Delta since prior run (sha 36ee4f82f -> 05150894e) -- parallel test execution, interval/duration, parameter naming, ActiveIssue rework

266 changed entries under Tests/Linq/ (27 added, 2 deleted, rest modified). The delta is mostly new test families plus infrastructure self-tests for the parallel runner. Many modified fixtures (roughly 190) are mechanical ripple edits and were not individually read (see DEFERRED-COVERAGE).

#### Test-runner infrastructure self-tests (Infrastructure/)

- ActiveIssueTests.cs (new, replaces ActiveIssueConfigurationTests.cs and ActiveIssueGenericTests.cs, both deleted) -- tests the pure decision function `ActiveIssueAttribute.Decide(attr, resultState, message, isRemote)`. A passing gated test is Failed ("Test passed but is marked ..."), a declared error type/message fragment is Inconclusive ("Known issue"), a different error type is Failed with both halves named. Not testable end-to-end because a gated test that passes fails by construction and a nested runner would share the static `TestProgressTracker`.
- BaselinesManagerTests.cs (new) -- 8 writers x 500 `BaselinesManager.LogQuery` appends race, asserts none lost in the shared StringBuilder in `CustomTestContext.BASELINE`. Takes no data source so no baseline file is written.
- ParallelExecutionTests.cs (new) -- compares provider selection of `CreateDatabaseSourcesAttribute` vs `NorthwindDataContextAttribute` / `IncludeDataSourcesAttribute` through derived probe attributes and asserts every lane key without a CreateDatabase case is pre-marked ready (matches the TestsInitialization logic above).
- TestProgressStateTests.cs (new) -- accounting of `TestProgressState` behind the `--test-progress` heartbeat, notably result-rewriting wrappers such as `ThrowsWhenAttribute` (BeginDeferred / StartTest / CompleteTest / CommitDeferred): an expected throw is never published as a failure and costs no forced write.

#### Interval / duration translation (new)

- Linq/IntervalTranslationTests.cs plus partials Arithmetic, Difference, Mapping, Members, Queries, Write (7 files, namespace Tests.Linq). Root file defines `DurationRow` with TimeSpan columns stored as Int64 (Access stores Money/CURRENCY) declared with `[Duration(DurationUnit.Second)]`, `[Duration(DurationUnit.Tick)]`, undeclared, and undeclared-with-converter variants, built through FluentMappingBuilder `HasConversion`. Point: the unit comes from the declaration, never from the storage type (a hardcoded Int64-means-ticks is silently wrong by a factor of 10 million). Only the root file was read.
- Mapping/DurationMappingTests.cs (new) -- `ColumnDescriptor.DurationUnit` resolution from attribute and from fluent mapping (Attributed and Fluent entities, nullable TimeSpan with Millisecond unit). Only the first 60 lines were read.

#### Parameter naming and reuse (Linq/ParameterTests partials, new)

- ParameterTests.Naming.cs -- a parameter is named after where the value comes from (the captured variable) rather than the compared column. For non-member expressions the name walk follows unary operators, indexed array or container, and parameterless `GetValueOrDefault` target. Assertions go against `DataParameter.Name` of `ToSqlQuery().Parameters`, e.g. `["values", "values_1"]` for `values[0]` and `values[1]`.
- ParameterTests.Reuse.cs -- repeated expressions share one parameter only when both occurrences yield the same value: an impure call (`ReuseCounter.Next()`) is evaluated per occurrence and gets separate parameters. Uses the shared `ParameterDeduplication` entity from ParameterTests.cs. Both partials use `[IncludeDataSources(TestProvName.AllSQLite, TestProvName.AllSqlServer)]`.

#### Other new fixtures

- Linq/ConcurrencyRefreshTests.cs -- `LinqToDB.Concurrency` optimistic-lock refresh API over `RefreshTable<TStamp>`, a no-parameterless-ctor entity, a two-stamp entity (Guid and int revision) and a read-only stamp member that the API must reject. Only the first 60 lines were read.
- Linq/SqlRawSqlTableTests.cs -- pure unit regression: `SqlRawSqlTable` rebuilt by `QueryElementVisitor.VisitSqlRawSqlTable` (Transform mode, via `Clone`) must keep `IsScalar`, `SQL` and `SqlTableType.RawSql`.
- Linq/WindowFunctionsTests.ConstantOrderBy.cs (#5806) -- constant window ORDER BY keys (`OrderByDesc(5)`, `ThenBy(1)`, leading `OrderBy(1)`) are dropped before reaching SQL Server, SAP HANA and MySQL 8, which reject or misread them. Asserts real-key numbering is unchanged and constant-only numbering is a complete 1..N. WindowFunctionsTests family is now 47 files.
- DataProvider/ProviderSpecificReaderValueTests.cs -- compiled only on non-NETFRAMEWORK, `DataProviderTestBase`. Matrix of provider-specific reader types vs CLR types vs formatted text per provider (SqlServer SqlBoolean/SqlDecimal/SqlXml and others, with usings for Db2, Firebird, MySql/MySqlConnector decimals, Npgsql, Oracle, DuckDB and ClickHouse numerics) via `AssertReadMatrix` / `AssertProviderSpecificRequired`. Only the SqlServer block was read. Shares `QueryValueFormatter` source with the CLI (see Tests.csproj note).
- Scaffold/SqlServerDecimalOverflowProtectionTests.cs -- `ScaffoldOptions.DataModel.GenerateSqlServerDecimalOverflowProtection`: SQL Server decimal columns with precision above 28 or a scale pushing outside CLR decimal limits get `Metadata.UseGetSqlDecimal = true`, decimal(28,0) does not, non-SQL Server databases are never marked.
- Extensions/ClickHouseTests.tt + ClickHouseTests.generated.cs -- ClickHouse hint tests are now T4-generated like the other vendors (hand-written ClickHouseTests.cs modified alongside). Not read.

#### New UserTests regressions

- Issue5683Tests.cs -- recursive CTE with paginated anchor whose recursive term projects a derived type cast to the CTE type: merged set-operation projection must keep PartId/RootPartId/RootPartSortField so the outer join resolves.
- Issue5684Tests.cs -- result compared against a LINQ-to-Objects multiset (order-independent). Scenario not read beyond the header.
- Issue5719Tests.cs -- mapper must not embed the same parameterized constructor body at every use site (counts constructor occurrences via a trace-captured MapperCreated event), otherwise `Expression.Compile` processes it N times.
- Issue5769Tests.cs -- a value read by a `Sql.IExtensionCallBuilder` from an argument (captured local field or inline collection initializer) must be part of the query cache key.
- Issue5916Tests.cs -- an `(object)`-cast set-operation branch must keep members evaluated client-side and read the same columns as the uncast form. Uses structural equality because the default `AssertQuery` comparer folds object members into an always-true comparison.
- Issue5935Tests.cs -- eager-loaded OrderBy/ThenBy whose key is not in the projection must not throw, plus SelectMany/Cast below the OrderBy (element type change without remap).

#### Modified fixtures (not individually read)

Roughly 190 modified entries -- Linq/ (about 85, including the WindowFunctionsTests.* partials, EagerLoading*, DateTime*, String*, SubQuery, Join, Where, Tph, PreferClientCalculation), Update/ (about 30, incl. Merge/Upsert/Entity DML), UserTests/ (about 40), DataProvider/ and DataProvider/Types/ (about 20), Mapping/, Data/, Extensions/, Scaffold/, SchemaProvider/, Tools/, Reflection/, Samples/, Microsoft/, OrmBattle/ -- are listed in the DEFERRED-COVERAGE fence. Their individual contents are unverified, so treat specific assertion claims about them in earlier sections as potentially stale.

## Naming patterns

- **<Feature>Tests.cs** -- primary fixture style in Linq/, Exceptions/, Update/, Data/, Mapping/, Extensions/. One class per file; class name matches file name.
- **Issue<N>Tests.cs** -- UserTests/ pattern. N is the GitHub issue number. Issues start at 10 and run to 5666+ (as of HEAD). File-per-issue, one or few test methods. Some non-issue files in UserTests/ document a reproducer without a tracked issue (e.g. GroupBySubqueryTests.cs, SelectManyUpdateTests.cs).
- **Partial-class spreads** -- used when a fixture family is too large or has provider-specific branches:
  - Linq/WindowFunctionsTests.*.cs (46 files: 13 pre-existing (Average, Cume, DenseRank, Frame, Max, Min, NTile, PercentRank, PercentileCont, Rank, RowNumber, Sum, root) plus 33 added this delta (Combinations, Corr, Count, CovarPop, CovarSamp, Equality, Filter, FirstValue, FrameExclusion, HypotheticalSet, Keep, Lag, LastValue, Lead, Median, NthValue, PercentileDisc, RatioToReport, RegrAvgX, RegrAvgY, RegrCount, RegrIntercept, RegrR2, RegrSXX, RegrSXY, RegrSYY, RegrSlope, StdDev, StdDevPop, StdDevSamp, VarPop, VarSamp, Variance)). **(updated, this delta)** the family Compile-Remove exclusion was deleted from Tests.csproj -- all 46 files now compile and run; see the Delta section above and the corrected Known issues / debt entry.
  - Linq/FullTextTests.*.cs -- three provider-specific partials (SqlServer, SQLite, MySql); [Category(TestCategory.FTS)] gates FTS tests.
  - Linq/ParameterTests.*.cs -- base + SqlServer + FSharp provider partials.
  - Linq/IsNullTests.SqlServer.cs -- SQL Server-specific IS NULL optimization tests.
  - Update/MergeTests.*.cs -- 19 partial files (root MergeTests.Issues.cs + 18 operation/sub-API files, including MergeTests.ComplexProperty.cs). See **MergeTests family** below.
  - Update/UpdateFromTests.Row.cs -- row-constructor variant of update-from.
  - Update/UpsertTests.*.cs -- **(new, this delta)** 4 partial files (Single, Enumerable, Queryable, ApiParametersValidation) for the new Upsert<T> API. See Delta section above.
- **(delta 2026-10-09)** Linq/IntervalTranslationTests.*.cs -- 7 files (root + Arithmetic, Difference, Mapping, Members, Queries, Write). Linq/ParameterTests.*.cs now also has Naming and Reuse partials. Linq/WindowFunctionsTests.*.cs gained ConstantOrderBy (47 files). UserTests/ numbering now reaches Issue5935Tests.cs.
- **.generated.cs files** -- Extensions/ has T4-generated files: MySqlTests.generated.cs, PostgreSQLTests.generated.cs, OracleTests.generated.cs, SqlServerTests.generated.cs, SqlCeTests.generated.cs. Each is a partial class extending its sibling handwritten fixture.
## Notable per-fixture findings
**AST:**
- SqlDataTypeTests.cs -- minimal single test: verifies SqlDataType.GetDataType(DataType.Boolean).SystemType == typeof(bool). Validates the DataType-to-SystemType lookup table in SqlDataType.

**Common:**
- ConvertTests.cs -- exercises Convert<TFrom,TTo>, ConvertTo<T>, ConvertBuilder.GetConverter, MappingSchema.GetConverter<T1,T2>(), LinqToDBConvertException for ambiguous [MapValue]. Covers Convert<int,string>.Lambda / .Expression setters. Also tests nullable operator-parameter edge case in ConvertBuilder.GetConverter. **(updated, this delta)** SetExpression and ToStringTest now restore Convert<T1,T2>.Lambda/.Expression to null inside a try/finally, avoiding static converter-registry leakage into later tests.
- ConnectionBuilderTests.cs -- tests DataOptions.UseLoggerFactory() / UseDefaultLogging() wiring; verifies QueryTraceOptions.WriteTrace is populated from ILoggerFactory. No database access except one SQL Server parameterized test.
- DataToolsTests.cs -- unit tests for DataTools.ConvertStringToSql (null-byte escaping, chr(N) emission for Access-style SQL) and DataTools.EscapeUnterminatedBracket (LIKE-pattern bracket escaping). No provider dependency.
- DefaultValueTests.cs -- tests DefaultValue<T>.Value get/set for all primitive types.
- DisposeTests.cs -- verifies double-dispose is safe for DataConnection, DataContext, and remote DataContext (both sync and async paths), with CloseAfterUse toggled.
- EnumerableHelperTest.cs -- tests EnumerableHelper.Batch<T>() (sync + async), including the invariant that a batch sub-sequence throws InvalidOperationException on second enumeration.
- ExtensionsTest.cs -- tests Type.GetMemberEx(MemberInfo) resolution for virtual and non-virtual properties on derived types. Uses MemberHelper.PropertyOf<T>.
- MemberInfoEqualityComparerTests.cs -- pure unit tests for MemberInfoEqualityComparer.Default; covers AOT RuntimeSyntheticConstructorInfo path where MetadataToken throws. No database access.
- AssemblyAvailabilityTests.cs -- pure unit tests for LinqToDB.Internal.Common.Tools.IsProviderAssemblyPresent(name). Covers loaded/referenced/nonexistent/file-probe-fallback cases. No database access.
- ReservedWordTest.cs -- tests ReservedWords.IsReserved(word, providerName) case-insensitivity for empty string, AllPostgreSQL, AllOracle provider names.
- SettingsReaderTests.cs -- **namespace anomaly**: class TestSettingsTests lives in Tests.Tools (not Tests.Common) despite being at path Tests/Linq/Common/SettingsReaderTests.cs. Tests SettingsReader.Deserialize(config, defaultJson, userJson) connection-merging logic with BasedOn inheritance chains.
- ValueComparerTests.cs -- tests ValueComparer.GetDefaultValueComparer<T>(true) null-handling for string, object, interface, and nullable value types.
**Create:**
- CreateData.cs -- class a_CreateData (no namespace). [Order(-1)] ensures runs first in test suite. Dispatches to per-provider SQL scripts under Database/Create Scripts/. Seeds LinqDataTypes2, Parent, Child, GrandChild, InheritanceParent2, InheritanceChild2 via BulkCopy. Per-provider DbConnection callbacks handle binary/BFILE columns (Oracle, SQLite, Informix, Access, Firebird). Oracle callback uses BindByNameOracleCommandInterceptor to avoid :NEW/:parameter confusion. **(updated, this delta)** the YDB dispatch case now matches context.IsAnyOf(TestProvName.AllYdb) instead of the single ProviderName.Ydb value.

**Data:**
- DataExtensionsTests.cs -- exercises IDataContext.Query<T>(sql), Execute<T>, QueryMultiple-groupby, DataParameter -> DataParameter converter chain, CommandInfo.ClearObjectReaderCache(). Confirms [ScalarType(false)] on structs enables multi-column reads.
- MiniProfilerTests.cs -- large fixture (~36K tokens): wraps all supported providers behind StackExchange.Profiling.Data.ProfiledDbConnection. Validates that provider type-mapping (MappingSchema) still works correctly when DbCommand/DbDataReader are wrapped. Uses extern alias to disambiguate MySqlData vs MySqlConnector.
- ProcedureTests.cs -- tests QueryProc, ExecuteProc, QueryProcMultiple with SQL Server stored procs including output-parameter rebind after enumeration. Confirms [ResultSetIndex] attribute routing.
- QueryMultipleResultTests.cs -- tests QueryMultiple<T> and QueryProcMultiple<T> with [ResultSetIndex(N)] attribute routing for IEnumerable<T>, IList<T>, scalar, and array result types. Issue #4728 regression: empty result sets on multi-result stored procs.
- RetryPolicyTest.cs -- tests IRetryPolicy contract via custom Retry implementation; tests RetryPolicyBase subclass Issue3431RetryPolicy (overrides ShouldRetryOn) and exponential-base validation (ArgumentOutOfRangeException for expBase < 1.0). Uses SqlServerRetryPolicy integration test.
- TraceTests.cs -- comprehensive TraceInfo / TraceInfoStep coverage for LINQ queries, raw SQL, DML, transactions (BeginTransaction/Commit/Rollback all emit trace steps). Tests DataOptions.UseTracing(), .UseTraceLevel(), .UseTraceWith() and confirms TraceSwitch instance vs static priority.
- TransactionTests.cs -- tests async transaction lifecycle (BeginTransactionAsync, CommitTransactionAsync, RollbackTransactionAsync) for both DataContext and DataConnection; tests IsolationLevel overload; tests AttachToExistingTransaction for every provider via <Provider>Tools.GetDataProvider(connection, transaction). Issue #3863 PostgreSQL dispose-after-commit safety.
**Exceptions:**
- AggregationTests.cs -- confirms Min/Max/Average on empty non-nullable sequences throw InvalidOperationException.
- ConvertTests.cs -- confirms LinqToDBConvertException on duplicate [MapValue] values.
- DmlTests.cs -- confirms LinqToDBException on InsertOrUpdate with missing PK / missing PK in insert setter.
- ElementOperationTests.cs -- First / Single throw InvalidOperationException as expected.
- InheritanceTests.cs -- ParentInheritance2 without required discriminator mapping throws LinqToDBException.
- JoinTests.cs -- tests that join on new A() equals new B() with mismatched keys throws LinqToDBException; also contains positive multi-join regression tests.
- MappingTests.cs -- tests LinqToDBException on p.Name usage (not a mapped column) and LinqToDBConvertException on enum with inconsistent [MapValue].
- StackUseTests.cs -- tests ExpressionVisitorBase and QueryElementVisitor stack-hop safety under ThreadHopsScope. Verifies that deeply nested Expression.Call chains (30k+ nodes) trigger controlled InsufficientExecutionStackException (not raw stack overflow) with correct nesting depth matching hops count. Issue #5265: LoadWith chain on deeply associated entities executes within 200KB stack thread.

**Extensions:**
- AccessTests.cs -- AccessHints.Query.WithOwnerAccessOption hint propagation.
- ClickHouseTests.cs -- tests ClickHouse-specific JOIN modifiers (FINAL, SEMI, ANTI, ANY, GLOBAL, ALL), SETTINGS query hint (including Sql.TableName interpolation), and union interaction with hints.
- DocExampleTests.cs -- cross-provider doc-example test: exercises each provider hint API in a single fixture; DatabaseSpecificTest exercises all provider hint chains in one query.
- MySqlTests.cs + MySqlTests.generated.cs -- manual + T4-generated MySQL hint tests covering all MySqlHints.Table.* and MySqlHints.Query.* constants via parameterized [Values].
- OracleTests.cs + OracleTests.generated.cs -- Oracle hint tests covering OracleHints.Hint.* constants; generated file covers query-level hints.
- PostgreSQLTests.cs + PostgreSQLTests.generated.cs -- PostgreSQL locking hints (FOR UPDATE, FOR KEY SHARE, etc.) and sub-query hint scoping.
- QueryExtensionTests.cs -- tests self-join optimization with table hints (SelfJoinWithDifferentHintTest); verifies query.GetTableSource().Joins count.
- QueryNameTests.cs -- tests QueryName(name) emitting /* name */ (or /*+ QB_NAME(name) */ for Oracle) in SQL; cross-provider including Access fallback.
- SqlCeTests.cs + SqlCeTests.generated.cs -- SQL CE locking hints (WITH (NoLock) etc.), index hints, TablesInScopeHint.
- SQLiteTests.cs -- INDEXED BY <index> / NOT INDEXED hints.
- TableIDTests.cs -- tests TableID(pp) + Sql.TableAlias/TableName/TableSpec SQL ID resolution.
- YdbTests.cs -- **(new, this delta)** YdbHints.Unique / YdbHints.Distinct via .UniqueHint()/.DistinctHint(), and the IYdbSpecificQueryable<T> .AsYdb() entrypoint for provider-specific query extension methods.
**Infrastructure:**
- ActiveIssueGenericTests.cs -- verifies [ActiveIssue] attribute variants (no details, details-only, URL+details, number-only). All tests are expected to skip in normal runs.
- **(delta 2026-10-09)** ActiveIssueConfigurationTests.cs and ActiveIssueGenericTests.cs (entries above) were deleted and replaced by ActiveIssueTests.cs (pure `ActiveIssueAttribute.Decide` policy tests). The ActiveIssueGenericTests entry above is historical.
- ActiveIssueTests.cs, BaselinesManagerTests.cs, ParallelExecutionTests.cs, TestProgressStateTests.cs -- **(new, delta 2026-10-09)** see the 2026-10-09 Delta section (runner infrastructure self-tests).
- IdentifierBuilderTests.cs -- tests IdentifierBuilder.Add() / CreateID() equality for null, bool, string, int, Delegate, lambda, object[], Type, and Expression.Constant. Note: two distinct lambda captures are NOT equal (false) because the C# compiler generates separate method instances.
- NullabilityContextTests.cs -- directly constructs SelectQuery / SqlTableSource / SqlJoinedTable with FULL/RIGHT/INNER join types; verifies NullabilityContext.CanBeNullSource() propagation rules. Exercises SqlExpressionOptimizerVisitor, AliasesContext, OptimizationContext, SqlSelectStatement.BuildSql.
- DataOptionsTests.cs -- WithDefaultNullsPositionTest (pure unit; SqlOptions/DataOptions DefaultNullsPosition builder chain) and ConfigurationSqlDefaultNullsPositionTest (static Configuration.Sql.DefaultNullsPosition global). **(updated, this delta)** gained WithDefaultEagerLoadingStrategyTest and WithImplicitCollectionLoadingTest (PR #5450 LinqOptions builder coverage) and OptimizeForSequentialAccessConfigurationIDTest (PR #5639 cache-key isolation for UseOptimizeForSequentialAccess); TestProviderAutoDetect gained a TestProvName.AllYdb -> UseYdb(...) case; ConfigurationSqlDefaultNullsPositionTest lost its [NonParallelizable] attribute.

**Mapping:**
- CanBeNullTests.cs -- verifies Configuration.UseNullableTypesMetadata behavior: C# nullability annotations control CanBeNull on columns/associations when the flag is set.
- ConversionTypeTests.cs -- tests MappingSchema.SetConvertExpression<T1,T2>(., conversionType: ConversionType.FromDatabase / ToDatabase) asymmetric conversion; verifies DB stores trimmed value and read-back strips padding.
- DynamicStoreTests.cs -- tests [DynamicColumnsStore] / fluent DynamicColumnsStore() on Dictionary<string,object> columns; configuration-scoped stores (SQLite vs default).
- FluentDynamicMappingTests.cs -- tests FluentMappingBuilder.HasAttribute<T>(x => Sql.Property<int>(x, colName), attr) for adding attributes to dynamic columns.
- DurationMappingTests.cs -- **(new, delta 2026-10-09)** [Duration(DurationUnit)] attribute and fluent declaration resolve `ColumnDescriptor.DurationUnit`, for TimeSpan columns of identical storage type.
- FluentMappingAliasTests.cs -- tests FluentMappingBuilder.Member(e => e.Alias).IsAlias(e => e.Real) -- column alias mapping through [ColumnAlias] and fluent builder.
- FluentMappingBuildTests.cs -- tests db.CreateTempTable(name, data, mb => mb.Property(.).IsPrimaryKey().) + InsertOrUpdate / Update on fluent-mapped temp tables.
- FluentMappingExpressionMethodTests.cs -- tests FluentMappingBuilder.Member(e => e.Computed).IsExpression(e => .) with and without materialization (true flag). Active issue #4987 marks several providers as skipped.
- MappingAmbiguityTests.cs -- tests that mixed [Column]/[NotColumn] on property+field with same name (different case) resolves correctly; verifies generated DDL column list.
- MappingSchemaTests.cs -- tests MappingSchema.SetDefaultValue, SetConvertExpression, converter chaining across parent/child schemas, XmlAttributeReader integration, and MetadataReader/AttributeReader fallback chain.
- MapValueTests.cs -- tests enum [MapValue] round-trip for string and char mapped enums via table INSERT + WHERE comparison.
- UseMappingSchemaTests.cs -- tests db.UseMappingSchema(schema) scoped override: within the using block column name maps to fluent-specified name; outside returns to original.
- ValueConverterColumnDbTypeTests.cs -- **(new, this delta)** a [ValueConverter]-decorated column with no explicit DataType resolves its DB type from the converter provider type, not the member type; covers DataType plus precision/scale propagation from the converter side.
**Metadata:**
- AttributeReaderTests.cs -- tests AttributeReader.GetAttributes(type) and GetAttributes(type, member) for TableAttribute and ColumnAttribute lookup.
- SystemDataLinqAttributeReaderTests.cs -- NETFX-only. Tests System.Data.Linq.Mapping.* attributes (Linq2SQL) read by SystemDataLinqAttributeReader.
- XmlReaderTests.cs -- tests XmlAttributeReader parse, TableAttribute from <Table> element, ColumnAttribute from <ColumnAttribute> element (both short and fully-qualified names).

**OrmBattle/Helper:**
- ExpressionUtils.cs -- utility: ExtractMember(Expression) unwraps Lambda -> Convert -> MemberAccess. No tests; used by GenericEqualityComparer.
- GenericEqualityComparer.cs -- IEqualityComparer<T> driven by property-expression list. HashCodeBuilder.Hash uses prime-multiply. No tests; used by OrmBattleTests.

**Reflection:**
- AttributesTests.cs -- tests MemberInfo.HasAttribute<T>(inherit) for virtual property/event inheritance; tests DynamicColumnInfo attribute API coverage (all CustomAttributeExtensions overloads).
- TypeAccessorTests.cs -- tests TypeAccessor.GetAccessor<T>().CreateInstance(), member access via MemberAccessor, property/field read-write.

**Samples:**
- ConcurrencyCheckTests.cs -- illustrates intercepting UPDATE statements to append optimistic-concurrency WHERE clause by cloning SqlStatement and post-executing a SELECT verify. Uses LinqToDB.Internal.SqlQuery directly.
- ExceptionInterceptTests.cs -- illustrates IRetryPolicy wrapping exceptions with context (SQLiteException -> custom exception) and counting retries.
- JoinOperatorTests.cs -- simple join pattern examples against Northwind (Category x Product, multi-column join).
- JsonConvertTests.cs -- illustrates MappingSchema.SetConvertExpression<string,T> using Newtonsoft.Json.JsonConvert for JSON-column deserialization; dynamically generates converter expressions via Expression.Call.

**Scaffold:**
- SchemaProviderTests.cs -- issue #4444: PostgreSQL dblink extension schema-load does not crash LegacySchemaProvider. [ActiveIssue] so skipped in normal runs.
- SqlServerDecimalOverflowProtectionTests.cs -- **(new, delta 2026-10-09)** scaffold option GenerateSqlServerDecimalOverflowProtection marks SQL Server decimal columns outside CLR decimal limits with UseGetSqlDecimal.
- TypeParserTests.cs -- tests IType / TypeParser (scaffold code-model type) parsing; TestType implements IType for unit testing.

**SchemaProvider:**
- PostgreSQLSchemaProviderTests.cs -- extensive expected schema for PostgreSQL TestTableFunctionSchema stored function: validates ProcedureSchema.Parameters, ResultTable.Columns including data types (int4, int8, numeric, etc.). Provider: NpgsqlTypes.
- SchemaProviderTests.cs -- TestApiImplemented confirms ISchemaProvider.GetSchema() runs without exception for all providers. Test validates table-name uniqueness and column-name uniqueness across the returned schema.
- SqlServerTests.cs (SchemaProvider/) -- SQL Server 2025+ JSON/vector column schema tests: validates jsonDataType -> typeof(string) (or SqlJson when provider-specific), vectorDataType -> float[] (or SqlVector<float>).
**Tools:**
- ComparerBuilderTests.cs -- tests ComparerBuilder.GetEqualityComparer<T>(selectors) including inherited member resolution for virtual overrides.
- DecimalHelperTests.cs -- tests DecimalHelper.GetFacets(decimal) returning (precision, scale) tuple for positive/negative and trailing-zero edge cases.
- IdentityMapTests.cs -- tests IdentityMap (from LinqToDB.Tools.EntityServices): identical-PK queries return same object reference; GetEntityEntries<T>() tracks DBCount / CacheCount.
- MapperTests.cs -- tests MapperBuilder<TFrom,TTo>, Map.GetMapper<T1,T2>(). Cross-references LinqToDB.Tools.Mapper.MapperBuilder in TOOLS area. Exercises GetMapperExpression/GetMapperExpressionEx, SetProcessCrossReferences, deep-copy semantics.
- ToDiagnosticStringTests.cs -- tests IEnumerable<T>.ToDiagnosticString() ASCII table formatter for primitive arrays and complex types.

**TypeMapping:**
- MappingTests.cs -- exercises ExpressionTypeMapper (dynamic type proxy): delegate wrapping (SimpleDelegate, ReturningDelegate with and without type mapping), event subscription/fire through mapped wrapper. Uses LinqToDB.Internal.Expressions.Types.
**Update:**

- BatchTests.cs -- BulkCopy inside/outside a DataConnection transaction; verifies commit semantics. Namespace Tests.xUpdate, [Order(10000)].
- CreateTableTests.cs -- db.CreateTable<T>() / db.DropTable<T>() round-trip with fluent mapping (PK, identity, length); async variant. Cross-provider.
- CreateTableTypesTests.cs -- comprehensive DDL type coverage: creates a table with int, long, double, bool, DateTime, enum, string, nullable variants, plus DataType.Json. Validates correct SQL type emission and round-trip for each .NET type.
- CreateTempTableTests.cs -- db.CreateTempTable(name, query, tableOptions: TableOptions.CheckExistence) API; verifies rows populate; cross-provider.
- DeleteTests.cs -- basic Delete / DeleteAsync / DeleteWithOutput API; Where-predicate DELETE.
- DeleteWithOutputTests.cs -- DeleteWithOutput / DeleteWithOutputInto across SQL Server, Firebird 5+, MariaDB, PostgreSQL, SQLite, Ydb. Feature-gated by FeatureDeleteOutputMultiple / FeatureDeleteOutputSingle / FeatureDeleteOutputInto constants.
- DropTableTests.cs -- table.Drop() / DropTable<T>(throwExceptionIfNotExists:) cross-provider; [Order(10000)].
- DynamicColumnsTests.cs -- Insert/Update/Delete using Sql.Property<T>(entity, colName) for dynamic column names.
- EntityInsertTests.cs -- **(new, this delta)** entity-builder Insert<T>(item, configure) overload: Bare, Set_ContextFree, Set_FromSource cases against table EntityInsertTest.
- EntityUpdateTests.cs -- **(new, this delta)** entity-builder Update<T>(item, configure) overload, matching by primary key: Bare, Set_ContextFree, Set_FromSource cases against table EntityUpdateTest, plus EntityRowNoPk negative-path table.
- EntityDmlApiParametersValidationTests.cs -- **(new, this delta)** null-argument guards for Insert/InsertAsync/Update/UpdateAsync via a FakeTable<T> double; pure unit test, mirrors MergeTests/UpsertTests ApiParametersValidation.
- InsertIntoTests.cs -- query.Into(destTable).Insert() (SELECT INTO) for SQLite and ClickHouse.
- InsertWithOutputTests.cs -- InsertWithOutput / InsertWithOutputInto across SQL Server, Firebird, MariaDB, PostgreSQL, SQLite, Ydb.
- MergeTests family (19 files, partial class Tests.xUpdate.MergeTests):
  - MergeTests.Issues.cs -- root file; defines [TestFixture], test-model types, helpers (GetTarget, GetSource1/2, PrepareData), and issue-regression tests.
  - MergeTests.ApiParametersValidation.cs -- null-argument guard tests for all LinqExtensions.Merge overloads; exercises async cancellation path.
  - MergeTests.Caching.cs -- validates that enumerable-source merge queries hit the query cache on repeated calls.
  - MergeTests.CommandValidation.cs -- verifies providers that do not support MERGE throw LinqToDBException.
  - MergeTests.ComplexProperty.cs -- nested-member column mapping in MERGE; FluentMappingBuilder Property(o => o.Nested.Field) paths.
  - MergeTests.DynamicColumns.cs -- MERGE with [DynamicColumnsStore] source-side property reading.
  - MergeTests.EmptySource.cs -- MERGE with zero-row enumerable source.
  - MergeTests.Hints.cs -- SQL Server MERGE with table hints.
  - MergeTests.IQueryableSource.cs -- MERGE targeting an IQueryable; [ActiveIssue(2363)] pending.
  - MergeTests.OldApiMigratedTests.cs -- regressions converted from legacy MergeInto API.
  - MergeTests.TargetSourceOn.cs -- tests On(target, source, condition) and OnTargetKey() match-condition builder methods.
  - MergeTests.Types.cs -- MERGE with all numeric/date/string types in source rows.
  - MergeTests.WithOutput.cs -- MergeWithOutput / MergeWithOutputInto across SQL Server 2008+, PostgreSQL 17/18+, Firebird 3+.
  - MergeTests.Operations.Associations.cs -- MERGE with associations on target/source. **(updated, this delta)** PrepareIdentityData now returns the seeded rows instead of writing a shared static IdentityPersons field -- see Delta section (test-isolation cleanup).
  - MergeTests.Operations.Combined.cs -- multi-operation MERGE (InsertWhenNotMatched + UpdateWhenMatched in single statement).
  - MergeTests.Operations.Delete.cs -- DeleteWhenMatched operation.
  - MergeTests.Operations.DeleteBySource.cs -- DeleteWhenNotMatchedBySource (SQL Server / Sybase extension).
  - MergeTests.Operations.IdentityInsert.cs -- InsertWhenNotMatched with identity column insert. **(updated, this delta)** same PrepareIdentityData return-value refactor as Associations.cs above.
  - MergeTests.Operations.Insert.cs -- InsertWhenNotMatched variants.
  - MergeTests.Operations.LoadTests.cs -- large-batch MERGE performance/correctness.
  - MergeTests.Operations.Parameters.cs -- MERGE with parameterized source values.
  - MergeTests.Operations.Update.cs -- UpdateWhenMatched and UpdateWhenNotMatched variants.
  - MergeTests.Operations.UpdateBySource.cs -- UpdateWhenNotMatchedBySource (SQL Server / Sybase extension).
  - MergeTests.Operations.UpdateWithDelete.cs -- Oracle-only UPDATE ... DELETE clause within MERGE.
- MultiInsertTests.cs -- Oracle MULTI-TABLE INSERT (unconditional + conditional FIRST/ALL).
- OldMergeTests.cs -- tests for the deprecated MergeInto API; [Obsolete] on class.
- TempTableTests.cs -- db.CreateLocalTable<T>(seed) + insert-from-query across providers.
- TruncateTableTests.cs -- db.TruncateTable<T>() cross-provider; verifies row count drops to 0.
- UpdateFromTests.Row.cs -- partial of UpdateFromTests; tests UPDATE SET (col1, col2) = (SELECT .) row-constructor syntax for SQLite, Oracle, PostgreSQL, Informix, Firebird 5+.
- UpdateTests.cs -- comprehensive Update / UpdateAsync / Set(.) / InsertOrUpdate / UpdateFrom API coverage; cross-provider.
- UpdateWithOutputTests.cs -- UpdateWithOutput / UpdateWithOutputInto across SQL Server, Firebird, PostgreSQL 18+, SQLite, Ydb.
- UpsertTests family (4 files, partial class Tests.xUpdate.UpsertTests) -- **(new, this delta)** the Upsert<T> API:
  - UpsertTests.Single.cs -- Upsert<T>(ITable<T>, T, configure); single-entity, Match((t,s) => t.Id == s.Id) builder.
  - UpsertTests.Enumerable.cs -- Upsert<T>(ITable<T>, IEnumerable<T>, configure); client-side list/array source.
  - UpsertTests.Queryable.cs -- Upsert<T>(ITable<T>, IQueryable<T>, configure); server-side query source, sub-select in the generated MERGE.
  - UpsertTests.ApiParametersValidation.cs -- null-argument guards; not individually read this delta (see DEFERRED-COVERAGE).
**DataProvider:**

- AccessProceduresTests.cs -- Access (OleDb + ODBC) stored procedure tests. Validates ProcedureSchema column metadata (OleDb vs ODBC schema differences). Uses ExecuteProc / QueryProc with OleDb/ODBC call syntax differences.
- AccessTests.cs -- Access (OleDb + ODBC) type mapping: all numeric, datetime, char, string, binary, GUID, XML, enum types. Tests AccessTools.CreateDatabase / DropDatabase (Jet and ACE versions).
- DB2Tests.cs -- IBM DB2 type mapping including provider-specific types (DB2Int64, DB2Real, DB2TimeStamp, DB2Clob, DB2Blob, DB2DateTime, DB2DecimalFloat, DB2Binary). High-precision timestamp (0--12 fractional digits via DB2TimeStamp). Module/package function calls. **(updated, this delta, issue #5663)** three new DECFLOAT special-value round-trip tests: DecFloatSpecialToFloatingPoint (+Inf/-Inf/NaN round-trip through double/float), DecFloatSpecialToDecimalAndIntegral (special values become null/default for decimal/int/long targets), DecFloatFiniteValue (finite values still round-trip exactly).
- ExpressionTests.cs -- minimal: exercises IDataProvider.GetReaderExpression(reader, ordinal, drExpr, typeof(int)) to build a compiled reader delegate.
- InformixTests.cs -- Informix type mapping (bigint, int8, int, decimal, money, real, float, bool, char, varchar, nchar, nvarchar, lvarchar, text, date, datetime, interval, byte). BulkCopy with KeepIdentity for IDS provider.
- MySqlTestUtils.cs -- utility: EnableNativeBulk(db, context) sets SET GLOBAL local_infile=ON for MySqlConnector. Not a test fixture.
- OracleTests.cs -- TestDateTimeSQL updated for DateTimeOffset local-time+offset form; TestDateTimeOffsetToTimestampLiteral.
- PostgreSQLArrayTests.cs -- PostgreSQL array-parameter caching: Sql.Ext.PostgreSQL().ValueIsEqualToAny(col, arr) parameterization with arrays of int, long, double, decimal, string, bool, short, float, Guid, DateTime.
- PostgreSQLExtensionsTests.cs -- PostgreSQL Unnest(array) / db.Unnest(col) table-valued function, PostgreSQLExtensions.ValueIsEqualToAny, array-column queries.
- PostgreSQLTests.cs -- region Issue 5549 with NodaTime.Instant COALESCE via ?? operator and [Sql.Extension] / [Sql.Expression] approaches.
- ProviderSpecificReaderValueTests.cs -- **(new, delta 2026-10-09)** provider-specific reader value matrix (non-NETFRAMEWORK) sharing the CLI QueryValueFormatter source.
- SqlCeTests.cs -- SQL CE type mapping. BulkCopy. SqlCeTools.CreateDatabase / DropDatabase.
- SQLiteParameterTests.cs -- SQLite: DateTime stored as Int64 via custom MappingSchema converter. double/float parameter pass-through; float.MaxValue round-trip.
- SqlServerFunctionsTests.cs -- SQL Server SqlFn.* system functions: DbTS, LangID, Language, LockTimeout, MaxConnections, NestLevel, Options, RemServer, ServerName, ServiceName, Spid, TextSize, Version, and numerous date/string/math functions.
- SqlServerTestUtils.cs -- utility (non-fixture): provides TVPRecord class and GetSqlDataRecordsMS() / GetSqlDataRecords() helper enumerables for Table-Valued Parameter tests.
- SqlServerTypesTests.cs (root partial) -- SQL Server spatial and temporal types: SqlHierarchyId, SqlGeography, SqlGeometry; DateTimeOffset, DateTime2, TimeSpan.
- SqlServerTypesTests.TVP.cs (TVP partial) -- Table-Valued Parameter tests via DataTable, IEnumerable<SqlDataRecord>, and IEnumerable<SqlDataRecordMS> factories.
- SqlServerVectorTypeTests.cs -- SQL Server 2025 VECTOR type via SqlVector<float> and float[] column mappings. Tests SqlFn.VectorDistance(metric, v1, v2) with Cosine, Euclidean, Dot metrics.
- UniqueParametersNormalizerTests.cs -- unit tests for UniqueParametersNormalizer. Tests unique-string pass-through, duplicate renaming (test -> test_1 -> TEST_2), and case-insensitive dedup.
- YdbTests.cs -- Yandex DB (YDB) provider tests: schema introspection, DML (insert/update/delete), SelectQuery / QueryProc, BulkCopy. Uses YdbDataProvider internal class. **(updated, this delta)** [YdbNotImplementedYet] removed from SchemaProvider_ReturnsCreatedTable / SchemaProvider_ReturnsCorrectColumnMetadata (now pass for real); hardcoded Ctx = "YDB" constant replaced with TestProvName.AllYdb throughout -- fewer tests remain tagged [YdbNotImplementedYet] than the prior run described.
- YdbRetryPolicyTests.cs -- **(new, this delta)** YdbRetryPolicy unit tests: immediate-retry codes (BadSession/SessionBusy/SessionExpired) and jitter-retry codes (Aborted/Undetermined/Unavailable/ClientTransport*/Overloaded), driven through Policy.Execute with zeroed backoff.
- YdbTransientExceptionDetectorTests.cs -- **(new, this delta)** YdbTransientExceptionDetector.TryGetYdbException / TryGetCodeAndTransient unit tests (top-level, nested, non-YDB cases); both this file and YdbRetryPolicyTests.cs declare a same-named YdbException test double via intentional CS0436 suppression.
**DataProvider/Types:**

- TypeTestsBase.cs -- abstract base for per-vendor type tests. Provides TestType<TType,TNullableType>(context, DbDataType, value, nullableValue, ..) which exercises: CreateTable DDL, nullable/non-nullable insert, parameter queries, inline literal queries, all BulkCopy modes, filter-by-value SELECT.
- ClickHouseTypeTests.cs -- ClickHouse type coverage via TypeTestsBase. Notes unsupported types: LowCardinality, AggregateFunction, Nested, Tuple, Map, Array, Interval. Parameters disabled (TestParameters = false).
- DuckDBTypeTests.cs -- DuckDB type coverage via TypeTestsBase. Covers Boolean, all integer widths (TINYINT--UBIGINT--HUGEINT--BIGNUM), FLOAT/DOUBLE, DECIMAL (precision/scale sweep), VARCHAR/BLOB/BITSTRING, UUID, DATE/TIME/TIMETZ/INTERVAL/TIMESTAMP/TIMESTAMPTZ/JSON. Known provider bugs documented inline. #if SUPPORTS_DATEONLY.
- MySqlTypeTests.cs -- MySQL/MariaDB VECTOR type (DataType.Vector32, float[]). MySQL 9+/MariaDB vector.
- PostgreSQLTypeTests.cs -- PostgreSQL JSON / JSONB types via DataType.Json / DataType.BinaryJson. Covers string, JsonDocument (MDS only).
- SapHanaTypeTests.cs -- SAP HANA SmallDecFloat (16-digit precision) and Decimal types via TypeTestsBase.
- SqlServerTypeTests.cs -- SQL Server 2025+ JSON type via DataType.Json. Covers string, JsonDocument (MDS v6+), SqlJson (MDS v6+).
- YdbTypeTests.cs -- YDB primitive types (bool, numerics, dates, strings, binary) via TypeTestsBase. Custom MakeListFilter using ListHas({1}, {0}) YDB SQL expression. Minor update this delta (6 lines); no new structural coverage.
**Linq:**

- AbstractionTests.cs -- multi-class interface queries; ISample abstraction over two concrete types with Association; exercises eager-load through interface-typed associations.
- AggregationNullabilityTests.cs -- subquery-aggregate nullability: non-nullable Sum wraps with COALESCE; nullable Sum, Min, Max, Average must not wrap. SQL-shape verified via ToSqlQuery().Sql.
- AggregationTests.cs -- aggregation over associations: Sum/Count/Average on IQueryable<ItemValue> association with null-value data.
- AllAnyTests.cs -- Any/All LINQ operators: subquery Any, navigation Any, correlated All, combined predicates.
- AK107Tests.cs -- Oracle-only: sequence-backed identity insert ([SequenceName]) with cross-schema sequence (c##sequence_schema). Tests SkipOnUpdate in InsertOrUpdate path.
- ConflictActionTests.cs -- BulkCopyOptions { ConflictAction = ConflictAction.Ignore } with MultipleRows mode for MySQL/PostgreSQL/SQLite/DuckDB.
- EagerLoadingStrategyKeyedQueryTests.cs -- **(new, this delta)** Company/Department/Employee/Contractor/Intern 3-level association hierarchy exercising EagerLoadingStrategy.KeyedQuery vs Default.
- EagerLoadingStrategyUnionTests.cs -- **(new, this delta)** Company/Department/Employee/EmployeeTask/Contractor 4-level hierarchy, same strategy comparison with an extra association depth.
- EagerLoadingWideKeyTests.cs -- **(new, this delta)** 15-member composite correlation key (KParent/KChild), regression coverage for the Rest-nested-ValueTuple key-carry truncation defect (project_5450_keyedquery_composite_key).
- EnumerableSourceTests.AsQueryable.cs -- configured AsQueryable(db, builder) overload tests covering parameterize/inline modes, .Except(member) per-member flip, cache stability, scalar lists, inline arrays, error cases, CompiledQuery integration.
- ImplicitCollectionLoadingTests.cs -- **(new, this delta)** DataOptions.UseImplicitCollectionLoading(ImplicitCollectionLoading.Throw); un-LoadWith-ed collection projection throws LinqToDBException mentioning LoadWith.
- PreferClientCalculationTests.cs -- **(new, this delta)** DataOptions.UsePreferClientCalculation(bool) interaction with [Sql.Function(PreferServerSide=)] / [Sql.Function(ServerSideOnly=)].
- QueryCacheEvictionTests.cs -- **(new, this delta)** #if BUGCHECK-gated direct unit tests of QueryCache eviction mechanics (sweep/cap/ClearAll); not compiled in normal builds.
- IntervalTranslationTests.*.cs -- **(new, delta 2026-10-09)** 7-file family for TimeSpan/interval translation with a declared [Duration] unit (see Delta section).
- ParameterTests.Naming.cs / ParameterTests.Reuse.cs -- **(new, delta 2026-10-09)** parameter naming from value origin and shared-parameter reuse only for same-valued repeats.
- ConcurrencyRefreshTests.cs -- **(new, delta 2026-10-09)** LinqToDB.Concurrency refresh API.
- SqlRawSqlTableTests.cs -- **(new, delta 2026-10-09)** SqlRawSqlTable clone preserves IsScalar/SQL/SqlTableType.
- WindowFunctionsTests.ConstantOrderBy.cs -- **(new, delta 2026-10-09)** constant window ORDER BY keys dropped (#5806).
- StringConcatTests.cs -- SqlConcatExpression coverage: basic concat forms, nullable semantics, SELECT/ORDER BY positions, array form, aggregate (grouping) concat, AggregateExecute, association subquery, partial translation, string interpolation equivalence.
- StringTrimTests.cs -- TrimStart(char[]) / TrimEnd(char[]) translation coverage: whitespace trim, single-char trim, multi-char set, cache semantics, legacy TrimLeft/TrimRight, provider-specific SQL-shape assertions.
- TphInheritanceTests.cs -- **(new, this delta)** TphDeepPersonBase -> TphDeepPersonChild -> TphDeepPersonLeaf multi-level TPH discriminator chain; Find and polymorphic-result queries.
- WindowFunctionsTests.*.cs -- **(46 files this delta, was 13)** full SQL:2003 window-function surface: ranking, aggregate-with-frame, navigation (Lag/Lead/FirstValue/LastValue/NthValue), statistical (Corr/Covar*/Regr*/StdDev*/Var*/Variance/Median/PercentileCont/PercentileDisc), hypothetical-set (Rank/DenseRank/PercentRank WITHIN GROUP), and combinatorial edge cases (Combinations, Equality, Filter, Keep, RatioToReport). Gated per-provider via [ThrowsForProvider] + the new ErrorHelper.Error_WindowFunction_* constants. See Delta section above for the full breakdown.
(All other Linq/ fixtures: see prior run entries -- no structural changes introduced by this delta beyond the entries above.)
**UserTests (issues 10-1838 -- batch 5):**

[Same as prior run -- no structural changes to this batch]

**UserTests (issues 1869-2832 -- batch 6):**

[Same as prior run -- no structural changes to this batch]

**UserTests (issues 2856-4654 -- batch 7):**

[Same as prior run -- no structural changes to this batch]

**UserTests (issues 475-5458 + free-form -- batch 8):**

[Same as prior run -- no structural changes to this batch. Note: Issue269Tests.cs, Issue1238Tests.cs, Issue3432Tests.cs, Issue356Tests.cs, Issue445Tests.cs, Issue792Tests.cs, LetTests.cs received minor updates (likely DuckDB provider additions to [DataSources] sets or assertion refinements matching the PR #5451 provider expansion). No new test-class structures were introduced in these files.]

**UserTests (issues 5125-5505 -- delta additions, prior run):**

- Issue5125Tests.cs -- IExpressionPreprocessor wrapping OrderBy in NULLS FIRST Sql.Expr; optimizer must not embed directive inside subquery column. PostgreSQL only.
- Issue5154Tests.cs -- multi-level eager-loaded projection with Sql.Expr + [SqlQueryDependentParams]; ToSqlQuery / ToArray ordering in either direction must not throw. SQLite.
- Issue5505Tests.cs -- UPDATE SET with ServerSideOnly function (jsonb_set) on a ValueConverter-backed column; translator must not double-wrap with converter expression. PostgreSQL 9.5+.
- Issue781Tests.cs -- minor updates only; no new test-class structures.

**UserTests (issue 5576 -- prior delta):**

- Issue5576Tests.cs -- three-stage projection LEFT JOIN of DB table with in-memory Counts[] (class, not struct) -> Stat -> WithRate (decimal arithmetic) -> Result re-mapping. Regression: spurious [item] column in VALUES clause (InvalidCastException: Failed to convert parameter value from T to Decimal). [ActiveIssue(5611, Configuration = TestProvName.AllSQLite)] for SQLite integer-division.

**UserTests (issues 5347-5666 -- new this delta):**

- Issue5347Tests.cs -- custom MemberTranslatorBase overriding string.Contains to cast a jsonb haystack to text before LOWER/LIKE. PostgreSQL.
- Issue5575Tests.cs -- unbound nullable member consumed via .HasValue in a later projection; previously threw "Called when root is not initialized".
- Issue5616Tests.cs -- UNION ALL mixing a built-in aggregate and a constant across branches, plus a custom [Sql.Extension(IsAggregate = true)]; previously threw InvalidCastException in VisitSqlReaderIsNullExpression.
- Issue5625Tests.cs -- Entity/Item/Thing multi-table nullable-join shape (entity definitions only verified this delta -- see Delta section note).
- Issue5666Tests.cs -- nullable-enum column plus nullable-FK [Association]; #nullable disable. SQLite.
**UserTests (issues 5683-5935 -- new, delta 2026-10-09):**

- Issue5683Tests.cs -- recursive CTE column loss when the recursive term projects a derived type.
- Issue5684Tests.cs -- multiset-compared regression (header only read).
- Issue5719Tests.cs -- constructor body embedded once, not per use site, in the mapper.
- Issue5769Tests.cs -- Sql.IExtensionCallBuilder-read argument value is part of the query cache key.
- Issue5916Tests.cs -- (object)-cast set-operation branch keeps client-side members.
- Issue5935Tests.cs -- eager-load OrderBy/ThenBy with key not in projection.

## Coverage-fill findings (2026-10-10) -- 40 previously deferred Tier-2 files

Taxonomic pass over Common/, Data/, DataProvider/, DataProvider/Types/, Exceptions/, Extensions/ and Infrastructure/. Each entry names the production behavior the fixture validates.

### Common/ and Data/ (runtime helpers, connection lifecycle)

- `Common/ConvertTests.cs` -- plain unit fixture (no TestBase): `Convert<TFrom,TTo>` converter registry (SameType, SetExpression, Nullable, Ctor, Parse/ParseChar, ToBinary), enum conversions in both directions (ConvertToEnum1..14, ConvertFromEnum1..5, nullable-enum variants) and `NullableParameterInOperatorConvert`. SetExpression/ToStringTest restore `Convert<,>.Lambda/.Expression` in try/finally to avoid static-registry leakage. Validates INTERNAL-API conversion and METADATA enum mapping.
- `Common/DefaultValueTests.cs` -- `DefaultValue<T>` for base types, int/uint, nullable int, enum, nullable enum, string. Pure unit.
- `Data/DataConnectionTests.cs` -- `DataConnection` lifecycle: provider resolution (UsingDataProvider, GetDataProviderTest), `ProviderDetectionDoesNotLeakConnection` (core-layer regression for AutoDetect leak, issue 5296), open/async-open and before-open events via `TestConnectionInterceptor`, DI/service-collection construction (TestServiceCollection1..4, Issue4326, Issue4476), per-DB settings, Issue4811, multiple connections, CloseAsync/DisposeAsync, CommandTimeoutTest, dispose-flag cloning, TransactionScope (Issue2676 x3), the MARS_* matrix (multiple readers on one command, supported/unsupported, parameters preserved after dispose, sync and async), MappingSchemaReuse and CustomMappingSchemaCaching. Production: INTERCEPTORS, INTERNAL-API, DataConnection core.
- `Data/MiniProfilerTests.cs` -- StackExchange MiniProfiler wrapping across drivers: Access OleDb/ODBC, SapHana native/ODBC, Firebird, SqlCe, MySql.Data/MySqlConnector, System/Microsoft SQLite, DB2, SqlServer System/MS (with retry policy), Sybase native/managed, Informix IFX/DB2, Oracle native/managed/Devart, PostgreSQL, ClickHouse, plus `TestMapperMap` and `TestLinqService`. Verifies that provider adapters unwrap profiled connections and commands to reach driver-specific APIs (bulk copy, type readers). Production: provider adapters (PROV-*), mapper builder.
- `Data/RetryPolicyTest.cs` -- `IRetryPolicy` contract: Execute/ExecuteAsync, RetryPolicyOptions, factory forms, external connection, Issue3431 (policy and connection reuse) and `GetNextDelay_*` boundary tests for the exponential back-off helper. Production: INTERNAL-API retry (cf. Tier-1 TestRetryPolicy.cs).
- `Data/TraceTests.cs` -- `TraceInfo` step reporting (BeforeExecute, AfterExecute, ExecuteReader, Commit/Rollback, BeginTransaction with isolation level) for LINQ, SQL, DataReader, Update/Insert/Delete and ExecuteObject, sync and async. Also `OnTraceConnectionShouldUseFromBuilder`, TraceSwitch/WriteTrace defaults vs builder, Issue3663Test. Production: DataConnection tracing, `DataOptions.UseTracing`.

### DataProvider/ root (vendor type matrices and vendor features)

Shared shape: TestParameters/TestDataTypes/TestNumerics/TestDateTime/TestChar/TestString/TestBinary/TestGuid/TestXml/TestEnum1-2 plus BulkCopy variants (MultipleRows, ProviderSpecific, RowByRow, sync/async) and schema-provider checks. Each file is the per-vendor ORM-level sanity suite.

- `DataProvider/AccessTests.cs` -- Access OleDb/ODBC: CreateDatabase, TestZeroDate, TestParametersWrapping, Issue1906/3893 (ODBC rejection), ConvertToDate nullable. PROV-ACCESS.
- `DataProvider/DB2Tests.cs` -- DB2 LUW: DECFLOAT special values (issue 5663), TIME/TimeSpan, BinarySize/ClobSize, Issue2763, module functions. PROV-DB2.
- `DataProvider/FirebirdTests.cs` -- Firebird: sequences/identity, Issue76, DropTable, name escaping, non-Latin procedure parameters, Fb4 types (schema, create, literals), binary mapping (Binary/String/Char), timestamp date-part. PROV-FIREBIRD.
- `DataProvider/InformixTests.cs` -- Informix: data types, BulkCopy matrix, CreateAllTypes, and the `DateParameterNextToColumnInCaseSelect/Update` family (DATETIME parameter typing next to a column inside CASE, see memory note on Informix CASE parameter typing). PROV-INFORMIX.
- `DataProvider/MySqlTests.cs` -- MySql.Data vs MySqlConnector: BigDecimal handling, BulkCopy incl. binary/bit, transactions, schema and procedure schema, FullTextIndex, TinyInt1IsByte, vector schema, Issue1993/3611/3726/4354/4439/4929, MariaDB module functions. PROV-MYSQL.
- `DataProvider/OracleTests.cs` -- Oracle managed/native/Devart: LongStringParameter (NClob inference thresholds), TreatEmptyStringsAsNulls, DateTimeOffset/TIMESTAMP literal and round-trip, BulkCopy split at SQL length limit, native identity bulk copy, XmlTable 1..9, OrderBy-first, decimal overflow, alternative BulkCopy (INSERT INTO / DUAL), CLOB/BLOB/LONG/LONG RAW, boolean mapping, procedure OUT params, Issue4172 enum/string literal variants, BlobLiteralsLimit, CoalesceWithInconsistentCharset. PROV-ORACLE.
- `DataProvider/PostgreSQLArrayTests.cs` -- array parameter cache stability per element type (int/long/short/string/double/decimal/float/Guid/DateTime/bool). PROV-POSTGRES, query cache.
- `DataProvider/PostgreSQLExtensionsTests.cs` -- `PostgreSQLExtensions` function surface: Unnest (ordinality, subquery, LATERAL), array aggregates, analytic functions, GenerateSeries (int/date) and GenerateSubscripts, system functions, and cache-reuse tests for each table-function form (FromSqlScalarCache, UnnestCache, ...). Issue4562, Issue5285.
- `DataProvider/PostgreSQLTests.cs` -- PostgreSQL: sequence insert variants and custom sequence naming, BulkCopy (binary COPY, `BulkCopyTimeoutAppliesToAllBatches` from #5980), custom aggregates and table/record/dynamic functions, ranges, custom types, UInt mapping, extra types bulk copy, DateTimeKind (Issue1742), interval, BigInteger, ObjectParam1..6, identifier escaping, partitioned tables, Issue4556/4487/4348/4780/2796/4672/5549 (NodaTime coalesce)/5325, JSON comparison by DataType and DbType.
- `DataProvider/SapHanaTests.cs` -- HANA native/ODBC: upper/lower-case column bulk copy, calculation views (`CalculationViewLinqQuery` and caching), geometry types, ByDefaultLoadCurrentSchemaOnly, module functions. PROV-SAPHANA.
- `DataProvider/SqlCeTests.cs` -- SqlCe: CreateDatabase, timestamp, table hints, ParametersInlining, Issue393/695/4436/4438/4574/4581. PROV-SQLCE.
- `DataProvider/SQLiteTests.cs` -- SQLite: DateTime round-trip modes (text/UTC/numeric) incl. bulk copy, TestDbVersion, Issue784/934/2099/2432/3766/3899/4736/4808/4904/5014, CrossApplyJoin, JSON and object types. PROV-SQLITE.
- `DataProvider/SqlServerFunctionsTests.cs` -- about 330 one-method tests, one per `SqlFn.*` wrapper in the SQL Server function catalog: system/config, CAST/CONVERT/PARSE/TRY_* (incl. style/culture and vector), date/time (DATEADD/DATEDIFF(_BIG)/*FromParts/DATENAME/EOMONTH/...), JSON (IsJson, JsonValue/Query/Modify, OpenJson1..6), math, metadata (OBJECT_*, FILEPROPERTY...), string (CHARINDEX, FORMAT, TRIM, STRING_ESCAPE, TRANSLATE...), compression, and server statistics. PROV-SQLSERVER.
- `DataProvider/SqlServerTests.cs` -- SQL Server: type matrix (incl. HierarchyID, Geometry, Geography, sql_variant, DateTime2 precision), BulkCopy AllTypes/AllTypes2, decimal overflow and `GetSqlDecimalAttribute`, hints, procedure params (anonymous, in/out), Issue1144/1294 literal-vs-parameter/1468/1613/1897/1921/449, temporal table schema (hide system tables), `TestVariantConverters`, TestNTextConcat, TestDateTime2DatePart.
- `DataProvider/SqlServerTypesTests.TVP.cs` -- partial of SqlServerTypesTests: table-valued parameters via procedure call, `FromSql`, table method, MERGE source, null TVP, TVPCachingIssue and T4-generated procedure wrapper. PROV-SQLSERVER TVP support.
- `DataProvider/SqlServerVectorTypeTests.cs` -- `SqlFn.VectorDistance` with `SqlVector<float>` (MS client, explicit mapping schema passed) and `float[]` mapping, plus Cosine/Euclidean/Dot extension forms. SQL Server 2025+.
- `DataProvider/UniqueParametersNormalizerTests.cs` -- `UniqueParametersNormalizer` name de-duplication and truncation (long strings, special characters, no infinite loop, default name, invalid properties) and an end-to-end check that commands receive normalized names deterministically (`CalledWithCorrectNames`, `ExecutesDeterministically`). SQL-PROVIDER parameter naming.

### DataProvider/Types/ (TypeTestsBase subclasses)

- `DataProvider/Types/ClickHouseTypeTests.cs` -- about 240 `TestType<>` calls over Int8..UInt256, floats, decimals, DateTime/DateTime64, strings, UUID, IP, enums. Parameters off (`TestParameters => false`). A header comment lists unsupported types (LowCardinality, Aggregate, Nested, Tuple, Map, Array, Geo, Decimal over 29 digits, DateTime precision over 8).
- `DataProvider/Types/PostgreSQLTypeTests.cs` -- JSON vs JSONB type mapping to string (no default mapping, cannot prefer JSON over JSONB) and a POCO mapping gated by `[ActiveIssue]` for missing reader support (9.3 minus has no jsonb).
- `DataProvider/Types/SapHanaTypeTests.cs` -- SMALLDECFLOAT/DECFLOAT/DECIMAL(p,s) with `HanaDecimal` (native only, ProviderSpecific bulk copy excluded) and more. RealVector not tested (cloud-only).
- `DataProvider/Types/SqlServerTypeTests.cs` -- JSON type (2025+: string, `JsonDocument`, `SqlJson`), `TestJSONParameterTypeName` (parameter type name must not vary by TFM, asserted via captured baselines), JSON fallback for 2022 and below, and VECTOR type via `SqlVector`.
- `DataProvider/Types/YdbTypeTests.cs` -- YDB primitive types (bool, Int8..UInt64, floats, decimals, strings, dates) with list-parameter filtering through a custom `ListHas` server-side expression and cross-type integer coercion sweeps.

### Exceptions/, Extensions/ and Infrastructure/

- `Exceptions/StackUseTests.cs` -- `[NonParallelizable]` because it mutates the global translation hop count via `ThreadHopsScope`. Issue 5265: deep `LoadWith` chain over five self-referencing association tables run on a 200K/150K-stack thread (`EagerLoadProjection`, `TestStackHopOption`), `TestPreserveExceptionOnHop` (custom exception survives hopping), and `TestExpressionVisitorHops` / `TestSqlVisitorHops` asserting nested `InsufficientExecutionStackException` depth equals the configured hop count for `ExpressionVisitorBase` and `QueryElementVisitor`.
- `Extensions/SqlServerTests.cs`, `SqlServerTests.generated.cs`, `SqlServerTests.tt` -- hand-written join/query/table hints, `TablesInScope`, FORCESEEK, OPTION(...), CTE and MERGE hint placement. The .tt template emits `With<X>TableTest` / `With<X>InScopeTest` for 16 table hints (ForceScan..XLock, READPAST pinned under ReadCommitted via an explicit transaction with remote disabled) and `Option*` query-hint tests (HashGroup, MaxDop, Recompile, ...).
- `Extensions/ClickHouseTests.cs`, `ClickHouseTests.generated.cs`, `ClickHouseTests.tt` -- FINAL/SETTINGS/AS OF JOIN hints by hand. The .tt generates `LeftJoin<X>HintTest` (OUTER/SEMI/ANTI/ANY/ALL and GLOBAL variants, obsolete `All*` forms under a CS0618 pragma) and `InnerJoin<X>HintTest`, asserting `LastQuery` contains the join keyword string.
- `Extensions/OracleTests.cs` -- Oracle optimizer hints: table/subquery/index/dynamic-sampling/parallel hints, query-block hints, parallel family, `TableID` hint-scoping tests (TableIDTest1..4), CTE/MERGE/UNION placement, Issue4163.
- `Extensions/PostgreSQLTests.cs` -- pg_hint_plan style hints: query/table/subquery hints, compiled-query hint from an argument, union placement, Issue4333.
- `Extensions/SqlCeTests.cs` -- SqlCe table hints, index hints, tables-in-scope plus a conflicting-scope negative test, insert and union hints.
- `Extensions/TableIDTests.cs` -- `TableID` / `Sql.TableAlias` / `Sql.TableName` / `Sql.TableSpec` resolved through a server-side-only `Sql.SqlID` expression (Access only). Production: SQL-AST table identity.
- `Infrastructure/DataOptionsTests.cs` -- `DataOptions` builder round-trips: LinqOptions, OnTrace/OnTrace2, OnEntityDescriptorCreated, command timeout (connection and context), UseOptimizeJoins, UseCompareNulls, `Try*` option probes, `TestProviderAutoDetect` (incl. AllYdb), default nulls position, eager-loading strategy, implicit collection loading, and sequential-access ConfigurationID. Production: INTERNAL-API options, IConfigurationID cache keying.

### Linq/ root, second batch (2026-10-10, 40 files, A..Ev)

Taxonomic pass over the alphabetical head of `Tests/Linq/Linq/`. Each entry names the production behavior the fixture validates.

**Query-shape and operator fixtures**
- `Linq/AllAnyTests.cs` -- `Any1..Any32`/`All1..All5` (+ `All4Async`), `SubQueryAllAny`, `AllNestedTest`, `ComplexAllTest`, `StackOverflowRegressionTest`, Issue4261/2156. EXISTS / NOT EXISTS translation of Any/All, nested predicates and deep-expression recursion guard. SQL-AST predicate building.
- `Linq/AggregationTests.cs` -- `SumByAssociationSubquery`, `LeftJoinToStringAggregate`, `ClosureList{Count,Sum,Min,Max,Average}Test` (aggregates over a closure-captured list), `MinMaxOverBooleanExpression(Grouped)`, `ValueBesideASumKeepsItsOwnPrecision`. Aggregate translation, boolean-typed Min/Max per provider, decimal precision beside Sum. See also AggregationNullabilityTests.
- `Linq/AnalyticTests.cs` -- legacy `Sql.Ext.*` analytic (window) API: ~45 `*Oracle` tests (Avg/Corr/Covar/CumeDist/DenseRank/FirstValue/Lag/Lead/ListAgg/Median/NTile/Percentile/Regr/StdDev/Var/KEEP FIRST or LAST), Issue1732 Lag/Lead/First/Last/NthValue, IGNORE NULLS, Issue1799/2842/3373/4870/5123, `LeadLagOverloads`, `WindowFunctionWithAggregate1..3`, and the `LegacyAnalytic_*` family (default vs explicit NULLS position applied to window ORDER BY, constant window order, ranking without order). Validates the legacy analytic builders against the newer window-function surface (default nulls position from `DataOptions`).
- `Linq/ConcatUnionTests.cs` -- the broadest set-operation fixture (~150 tests): Concat/Union numbered variants, object/tuple/record unions, association unions, inheritance concat, GroupBy over unions, count/sum over set ops (`*_ShouldNotRemoveSingleColumn`), nulls/literal typing (Issue3360 family, Issue3323, Issue2451 complex column), and the recent `UnionPadsAConvertedColumnWithNull`, `SetOperationRefusesAConstantBranchAgainstAConvertedColumn`, `UnionAllReadsAConstantBranchOnItsOwnTerms`. Validates set-operation projection merge and per-branch type inference (SQL-BUILDER, EXPR-BUILDER).
- `Linq/DistinctTests.cs`, `Linq/DistinctByMethodTests.cs` -- Distinct (with Take/Skip/OrderBy, subqueries, group, join) and the `DistinctBy` LINQ operator (key-selector forms, composite keys, ordering, async). Distinct handling in the query optimizer and ROW_NUMBER-based DistinctBy lowering.
- `Linq/CountTests.cs` -- Count/LongCount/Any-count forms, grouped counts, count over association, Sum/Count mixes in group aggregates (49 tests).
- `Linq/ContainsTests.cs` -- `Functional*`/`Empty*` (int, enum, class-enum), `AllNulls{Like Clr,Like Sql}` (null semantics of IN lists under `CompareNulls`), Issue3986/2608/4317, `ContainsSubqueryTest`. IN-list translation of `Contains`.
- `Linq/ComplexTests.cs`, `Linq/ComplexTests2.cs` -- composite (complex-type) column mapping: Contains/Join over composites, class vs struct composites, only-required-column selection, nested composites, Issue413/4139/5056 (ComplexTests), inheritance mapping, LoadWith with Cast, converter enums, derived insert via attributes and fluent mapping (ComplexTests2). METADATA / mapping attributes.
- `Linq/CommonTests.cs` -- grab-bag of core translation: null checks, `NewCondition`/`NewCoalesce`/`CoalesceNew`, client vs server coalesce, `PreferServerFunc`, closures, `TableAsMethod`, enum conversion, GroupBy over union/left join, Issue288/191.
- `Linq/ConstantTests.cs` -- static/readonly-struct field and instance-readonly-member constant evaluation, nullable constant definitions, and the `AsSql` throw case.
- `Linq/ConvertExpressionTests.cs` -- expression-conversion with Select/Where/Any/`LetTest1..11` and `TestConversionRemovedForEnumOfType*` (enum underlying-type convert stripping for all eight integral types), Issue3791.
- `Linq/BooleanTests.cs` -- boolean to SQL predicate vs value translation (`TestAsSqlBoolTranslation`/`TestNoAsSqlBoolTranslation`), Sybase variant, function predicates, coalesce.
- `Linq/CalculatedColumnTests.cs` -- calculated columns (Test1..5, Expression1..2) and interpolated string as expression (also in a complex query).
- `Linq/AssociationTests.cs` -- ~120 association tests: SelectMany/LeftJoin/GroupBy via associations, null/ternary/let, generic associations (compile-time and runtime), extension-method and queryable-extension associations, interface-based associations (`ViaInterface` family), expression-method associations, many-association empty checks, alias escaping, Issue148/170/845/1096/1614/1711/2933/2966/2981/3260/3557/3809/3822/3975/4274/4454. Association handling in the expression builder.
- `Linq/AbstractionTests.cs` -- insert/update by runtime type, abstract-class mappings, association select over abstractions.
- `Linq/AK107Tests.cs` -- identity/sequence insert matrix for user/contract entities (Insert, InsertWithIdentity, LINQ forms, `SequenceNameTest`) -- sequence-name attribute and identity retrieval.
- `Linq/ArrayTests.cs` -- array column CreateTable/Insert/Update, `CollectionContainsMapping`, `TestDateOnly`.
- `Linq/DynamicResultTests.cs` -- `DynamicQueryViaDynamic` and `DynamicQueryViaObject`, Issue3520: dynamic/object result materialization.
- `Linq/EvaluationTests.cs` -- `Evaluate_RemappedTimeSpan`, `Evaluate_BooleanExpression`: client-side evaluation with mapping-schema conversions.

**Caching, compiled queries, contexts, async**
- `Linq/CachingTests.cs` -- query-cache keying: `TestSqlQueryDependent` (+DecFloat/Time), `TestByCall`, `TestInlined`, `TakeHint`, extension collection-parameter same/equal query reuse, Issue4266 class/struct.
- `Linq/CompileTests.cs` -- `CompiledQuery.Compile` (table, element, queryable forms, concurrency, Contains/Any/Count/Max, custom context, LoadWith/ThenLoad, `CompiledDeleteWithOutputTest`) plus the wrapped/marked-call and rebalanced-predicate closure-survival tests (`ClosureValueSurvivesRebalancedPredicate` family, `SelfReconstructingMarkedCallDoesNotRecurse`, `WrapperWithCapturedValueArgumentIsNotSupportedTest`, `DependentArgumentCreatedByExpansionTest`). Compiled-query fold boundary.
- `Linq/CompileTestsAsync.cs` -- async mirror: First/Single/Any/Count/LongCount/Min/Max/All/Contains and the full Sum{Int,Long,Float,Double,Decimal}(N) with and without selector, Average, element-form LoadWith transaction and cancellation, Issue3266.
- `Linq/AsyncTests.cs` -- async materialization API: ToArray/ToAsyncEnumerable/ForEach/ForEachUntil (incl. eager load), First/Contains/Take/Skip, AsAsyncEnumerable and AsyncEnumerableCast variants, dispose semantics (`DisposeAsync` family, `CurrentBeforeMoveNextTest`, init-failure not masked), ToLookup, and LoadWith/temp-table/database-specific table materialization asynchronously.
- `Linq/DataContextTests.cs` -- `DataContext` null-configuration (local and remote), `ProviderConnectionStringConstructorTest1..3`, loop tests (sync/async, multiple contexts), command timeout, `TestCreateConnection`, close-after-use vs keep-open for DataContext and DataConnection, Issue210/4729.
- `Linq/ConcurrencyTests.cs` -- optimistic concurrency: auto-increment, filtered, Guid (native/string/binary), custom and DB strategy, filter extension, plus `ParallelExecutionDoesNotCorruptAliases`.
- `Linq/ConflictActionTests.cs` -- BulkCopy `ConflictAction.Ignore` (sync/async), PR #5455.

**CTE, types, dates, enums, eager loading, enumerable sources**
- `Linq/CteTests.cs` -- recursive and non-recursive CTE (85 tests): nested, joined, DML-from-CTE, and provider gating.
- `Linq/CteMaterializedTests.cs` -- `AsCte` builder: null callback throws, `HasName` null/empty, `IsMaterialized` on custom builder throws, MATERIALIZED / NOT MATERIALIZED keyword emission, ClickHouse fallback to plain AS, silent ignore on unsupported providers, distinct cache entries per hint.
- `Linq/ConvertTests.cs` -- ~115 value-conversion tests through LINQ `Sql.Convert`, `Convert.To` methods and casts across numeric, string, date and nullable types (provider SQL CAST shapes).
- `Linq/DataTypesTests.cs` -- Guid, byte, DateOnly, bool, int/string enum round-trip, Issue1918.
- `Linq/DateTimeFunctionsTests.cs` -- 121 tests of `DateTime`/`Sql` date functions (parts, add, diff, truncation) across providers.
- `Linq/DateTimeOffsetTests.cs` -- DateTimeOffset min/max, time-zone preservation, GroupBy by Date/TimeOfDay/Day/DayOfWeek/DayOfYear/Hour/Minute/Second/Millisecond/Month/Year/LocalDateTime, the GroupBy-by-AddX families and DateAdd tests.
- `Linq/EnumMappingTests.cs` -- 93 tests of enum mapping to int/string/char, nullable enums, comparisons and parameters.
- `Linq/EagerLoadingTests.cs` -- default eager-load (Blog/Post/Tag, MasterClass/DetailClass graphs, EventSchedule hierarchy): multi-level, filtered and projected eager loads.
- `Linq/EagerLoadingStrategyKeyedQueryTests.cs` -- KeyedQuery strategy (global and per-query): inline collection, nested two-level, parent-field fallbacks, `Single` multi-parent throws, per-parent Take/Skip, composite/string/nullable-FK keys, concurrent executions not sharing key state, and `WithSeparateLoadStrategy`/`WithUnionLoadStrategy` override with last-marker-wins.
- `Linq/EagerLoadingStrategyUnionTests.cs` -- the same scenario set for the Union strategy (68 tests).
- `Linq/EnumerableSourceTests.cs` -- local-collection sources: Apply/Inner/Outer joins against arrays, anonymous/class/record arrays, PostgreSQL variant, record cache reuse.
- `Linq/EnumerableSourceTests.AsQueryable.cs` -- configured `AsQueryable` (parameterize vs inline, `Except` member selection, cache stability across data changes, join/cross-apply cache hits, invalid-selector throws, compiled query with enumerable param). PR #5495 / issue #5424.

### Linq/ root, third batch (2026-10-10, 40 files, Ex..Sq)

Taxonomic pass over the middle/tail of `Tests/Linq/Linq/` (Expression*, FromSql, FSharp, FullText, Function, GroupBy, Inheritance, InSubquery, Interface, IntervalTranslation*, Issue, Join*, LoadWith, Mapping, Math, Parameter, Predicate, PreferClientCalculation, Query*, Remote, Select*, SqlRow). Class header, fixture attributes and the full test-method inventory were read for every file. Each entry names the production behavior validated.

**Expression translation, mapped members, functions**
- `Linq/ExpressionsTests.cs` -- `[ExpressionMethod]` / `Expressions.MapMember` / operator mapping: `MapOperator`, `MapHasFlag` (PR #5503), `HasFlag_OnStringMappedEnum_FailsToTranslate` and `HasFlag_OnConverterMappedEnum_*_FailsToTranslate` (negative path: a flags enum stored via string or converter cannot become a bitwise AND), `MapMember1..3`, `MethodExpression4..10`, `TestGenerics1..3`, association method expressions (sync/async), `PredicateExpressionTest1/2`, `LeftJoinTest1..3`, `CompareWithNullCheck1..28`, `NullableNullValueTest1..5`, Issue2431/2434/3472/4613/5040 (entity-filter helper). Validates EXPR-TRANS expression-method expansion and null-check generation.
- `Linq/ExpressionTests.cs` -- `PostiveTest`/`FailTest` (custom `Functions` + fake type), `TestAsProperty`, Issue4226, Issue3807Test1..14 (`SqlFnEx`/`StringValue`), Issue4674, `Test_ConditionalExpressionOptimization`, `PureExpressionDetection`/`ImpureExpressionDetection`, `CollectionParameterTranslation_IReadOnlyList/_Array`, `MapInvertOperator`. EXPR-TRANS purity analysis and conditional folding.
- `Linq/FunctionTests.cs` -- `Contains1..7`, `ContainsKey/Value*` (dictionary, hash-set and `ReadOnlySet` collection Contains), `ContainsString*`, `Equals1..4`, `NewGuid1/2`, `NewGuidOrder`, `NewGuid7_Native/_Emulated` and `Guid.CreateVersion7` (NET9+), `CustomFunc`, `CustomAggregate`, `GetValueOrDefault`, `AsNull/AsNotNull`, `Between1/2`, `MatchFtsTest` with a `Sql.ExtensionAttribute` builder (`MatchBuilder`), Issue3543, `TestDefaultFunctionNullability`. Built-in function mapping and `Sql.Extension` builders.
- `Linq/GenerateExpressionTests.cs` -- `Test1/2`, Issue4322 (Vector2/Vector3 types): expression generation for custom value types.
- `Linq/GenericExtensionsTests.cs` -- Issue326: generic `Sql.Extension` builder selected via a custom `MappingAttribute` (`ExtensionChoiceAttribute`).
- `Linq/SpecialFunctionsTest.cs` -- `Sql.Ordinal`, `Sql.Parameter`, `Sql.Constant` forcing parameter-vs-literal rendering.
- `Linq/MathFunctionTests.cs` -- 43 tests: Abs/Acos/Asin/Atan/Atan2/Ceiling/Cos/Cosh/Cot/Degrees/Exp/Floor/Log/Log2/Log10/Max/Min/Pow/PowDecimal/Round1..12/Sign/Sin/Sinh/Sqrt/Tan/Tanh/Truncate. `Math.*` / `Sql.*` translation per provider, incl. rounding-mode variants.
- `Linq/PredicateTests.cs` -- three-valued-logic predicate surface: `Test_Feature_IsTrue/IsFalse/IsUnknown/IsNull`, DistinctFrom, NullSaveEqual, `Decode`, boolean-as-predicate, predicate-vs-predicate tri-state, field/variable in subquery and list, `Test_ConditionOptimization`, `Test_PredicateOptimization`. SQL-AST predicate nodes and the condition optimizer.
- `Linq/InSubqueryTests.cs` -- `InTest*` (Take/Skip/SkipTake, object IN), `ContainsTest/ContainsExprTest/ContainsNullTest`, `ContainsWithUnion/GroupByKeepsProjectionTest`, and the NULL-semantics matrix `NotNull_In_NotNull_Test` .. `Null_NotIn_Null_Test3` (IN / NOT IN with nullable operands and subqueries).
- `Linq/SqlRowTests.cs` -- `Sql.Row(...)` row values: ServerSideOnly, IsNull/IsNotNull, Equals/NotEquals/Greater/Less(+Equals), In/NotIn, Between/NotBetween, `Overlaps`, compare to SELECT, mixed types, `UpdateRowLiteral/UpdateRowSelect/UpdateRowWithConverters`, Issue3631. SQL-AST row expression and row-comparison predicates.
- `Linq/FromSqlTests.cs` -- `FromSql` (FormattableString and raw): parameters, same-param reuse, expression-embedded, association/fluent mapping, table-valued function, scalar subquery, Unnest, split-string table, invalid alias usage, query-cache behavior (`TestQueryCaching_Interpolated_*`, `_Format_*`, `_ByParameter_*` keyed by data parameter vs value parameter vs SqlExpression), Issue3782, `InsertFromSql`. Raw-SQL source builder and cache keying.
- `Linq/FullTextTests.SqlServer.cs` -- `FullTextTests` partial, SQL Server: `FreeTextTable` / `ContainsTable` (by column, columns, all, language name/code, Top, expression-method forms), `FreeText` / `Contains` predicates, via LinqService, Issue386, `ContainsWithWindowFunction`, `ConditionConvertIssue`, property-based Contains. PROV-SQLSERVER full-text extensions.
- `Linq/FullTextTests.SQLite.cs` -- same `FullTextTests` class for SQLite FTS3/FTS4/FTS5: `Match` by table/column, `RowId`, `Rank`, `Fts3Offsets/MatchInfo/Snippet1..6`, `Fts5bm25(+Weights)/Highlight/Snippet`, the FTS command surface (`Fts3Command*`, `Fts5Command*`: optimize, rebuild, integrity-check, merge, automerge, delete, pgsz, rank, usermerge), `Fts3SegDirTableQuery`. PROV-SQLITE.
- `Linq/FSharpTests.cs` -- F# interop (95 tests, F# test-model assembly): record/union/CLIMutable mapping, option and voption round-trip and query forms (`OptionQuery_*`, `DuQuery_*`, module Option.isSome/get), nested records, Insert, LEFT JOIN (Issue1813Test1..11), Issue2678/3357/3699/3743/4132/4646/5598 (update sets only changed column, Ydb variants)/5790/5794 (plus `Issue5790RefusalTest`), `ExpressionFunctionInCteTranslationTest1/2`, `UseFSharp_StableConfigurationID`. F# support in METADATA / EXPR-TRANS (see memory notes on the F# option-member gap and the #1813 baseline).

**Joins, grouping, optimization, projection**
- `Linq/JoinTests.cs` -- 129 tests: Inner/Group/Left joins, `GroupJoinAny*`, `LeftJoinRemoval`, `SubQueryJoin`, apply joins (incl. MySql), null joins, `Sql*Join*` SQL-flavoured builders, full/right joins with inner-join combinations and record selection, `JoinBuildersConflicts`, Issue1815/1816/1455/2421/2912/3311/3560/4160/4714/5970, `NullableCoalesceJoinTest`. Join builders in EXPR-BUILDER and join nullability.
- `Linq/JoinOptimizeTests.cs` -- `InnerJoinToSelf`, `SelftJoinOptimized/Fail`, `LeftJoinProjection(Subquery)`, hint-aware self-joins, Issue4790 (association/join with and without key, nested), `LeftJoinToGroupingWithComputedKey`, `LeftJoinToDistinctWithComputedKey`, `LeftJoinToSourceWithComputedUniqueKey`. JoinsOptimizer (see memory note on keyset identity).
- `Linq/GroupByTests.cs` -- 169 tests: Simple1..14, MemberInit, SubQuery*, Aggregates*, Sum/Min/Max/Average, GroupByAssociation*, GroupByAggregate*, Scalar1..10, DoubleGroupBy, `GroupByNone`, `EmptySetAggregateNullability`, GroupByDate*, `GroupByGuard` / `NoGuardException` (client-side grouping guard), `GroupByConstants(+Empty)`, `CustomAggregate_Having/Where_As*` (Aggregate, Window, Expression), `AggregateOnGroupReachedThroughLet`, `InsertFirstFromGroup`, many Issue repros (672..5327). Group-by translation, HAVING, group-key nullability.
- `Linq/SelectQueryOptimizationTests.cs` -- 36 SQL-shape tests on `SelectQueryOptimizer`: COUNT over GROUP BY / UNION / UNION ALL column pruning, GROUP BY to DISTINCT and removal on unique key (not optimized with HAVING, aggregate ORDER BY, grouping sets), ORDER BY promotion / removal / preservation across subquery, set operation, EXISTS, CTE, Take/Skip, Distinct and join condition, `CreateSqlValueKeepsParameterizationWhenUsageIsCastWrapped`, `LeaveOnlyUsedFieldsInCte`.
- `Linq/SelectQueryTests.cs` -- `SelectQuery` union/subquery/join/first/alias-collision basics plus Issue2494/2779 (14 tests).
- `Linq/SelectTests.cs` -- 101 projection tests: Simple/New/InitObject/NewObject, MultipleSelect1..12, Coalesce*, null propagation (`SelectNullPropagation*`, `SelectReverseNullPropagation*`), conditional projection (`TestConditional*`), constructor/factory projection, ternary nullable value, `SelectWithIndexer*`, `SequentialAccessTest*` (+CacheKey), `OuterApplyTest`, `SelectExpression1..5`, Issue1788/3181/3372/4192/4198/4199/4200/4520/860. Projection builder (EXPR-BUILDER) and materializer.
- `Linq/InheritanceTests.cs` -- 64 tests of inheritance mapping: Test1..19, `TypeCastAsTest*`, `Cast1/2`, discriminator hierarchies (Test17/18), `InheritanceAssociationTest`, Issue2429/3891/4280/4666, calculated column on a subtype (single and dual-mapped), tree selection with/without default discriminator, and the DML-through-base-table family (`InsertDerivedThroughBaseTable`, `UpdateDerivedThroughBaseTable_*`, `InsertOrUpdateDerivedThroughBaseTable`, `UpdateWithOutputIntoDerivedThroughBaseTable`, positional/shadowed/unmapped derived inserts). METADATA inheritance mapping plus DML builders.
- `Linq/QueryInheritanceTests.cs` -- 20-test sibling suite on the same inheritance surface (Test1..12, TypeCast, Cast, `SimpleTest`).
- `Linq/InterfaceTests.cs` -- 30 tests: interface-typed table access, the Issue4031 matrix (Case01..16: implicit, explicit, internal, external interface base members), Issue3034/4082/4607/4715 (explicit interface descriptor and mapping), `ExtensionRegression`, `InterfaceFilterRegression`, `GenericInterface*` member/grouping/filter tests over generic constraints. Member resolution through interfaces in the expression builder.
- `Linq/LoadWithTests.cs` -- `LoadWith1..12`, `LoadWithAsTable1..4`, `LoadWithQueryIsLinqToDbSource`, `LoadWithFirstOrDefaultParameter`, transaction scope (sync/async), `LoadWithAndFilter`, `LoadWithCacheAssociation`, `LoadWithRecursive`, `LoadWithOptionalFilter*`, `ThenLoadOptionalFilter`, `OptionalFilterReusesPlan`. LoadWith eager association loading, incl. optional-filter plan reuse.
- `Linq/QueryableAssociationTests.cs` -- queryable associations (`QueryExpressionMethod`): projection/object/LoadWith, one-to-many via method and extension method, lazy, FromSql, `TestPropertiesFrom*` (DataConnection/DataContext and interface), one-to-one chained/transformed parameters, Issue3525/4596/4723.

**Parameters, filters, mapping, remote, interception**
- `Linq/ParameterTests.cs` -- parameter handling (54 tests): inline parameter, cached-parameter renaming, null-parameter cache, optimizing parameters, char-as-parameter, SqlDecimal/Binary exposure, positioned parameters, queryable-call parameters, international names, `ParameterDeduplication_*` (Insert/Update/Value/Set), IQueryable parameter evaluation (incl. multi-threaded), Issue4371 (DateOnly, DateTimeOffset, TimeSpan), Issue4359 primary parameter name, `ParameterCastDirectlyUnderExplicitCast`, Issue4963. Parameter extraction and parameter-name normalization.
- `Linq/PreferClientCalculationTests.cs` -- `DataOptions.UsePreferClientCalculation`: projection arithmetic and conditionals move to the client, `[Sql.Function(PreferServerSide)]` and ServerSideOnly stay in SQL, ToNullable/AsNullable over a missing LEFT JOIN row, aggregates stay server-side, predicate cases (`ClientConstantInPredicateIsServerSide`, `RowDependentClientOnlyInPredicateThrows`, mapped client-preferred function pre-evaluated), constants folded in ORDER BY/GROUP BY/HAVING/JOIN. EXPR-BUILDER client/server split.
- `Linq/QueryFilterTests.cs` -- global query filters: entity filters and cache, association to filtered entity, nesting, Issue4496/4508, `InsertOrUpdate`, `IgnoreFilters` (accumulation, by key, by type, key+type), named filters (AND combination, null removes, derived overrides base, func overload, interface-typed lambda fast vs dynamic path), set-operation nullability of filtered LEFT JOINs (`FilteredLeftJoinNullCheckSurvivesSetOperation`, `SetOperationBranchNullabilityReachesEnclosingQuery`), `QueryFilters_Introspection_*`, `QueryFilterAttribute_*`.
- `Linq/QueryGenerationTests.cs` -- `ToSqlQuery()` / `ToString()` diagnostics across Table, simple query, parameters (dedup, nullable), eager load, `IUpdatable`, `IValueInsertable`, `ISelectInsertable`, `ILoadWithQueryable`, multi-table same physical name, `IMultiInsert` (InsertAll/InsertFirst), `IMergeable`, provider-specific. Public SQL-introspection API.
- `Linq/QueryExpressionInterceptorTests.cs` -- `ExpressionInterceptorsTests`: `EnrichSimple`, `EnrichViaQueryableMethod` (expression interceptors rewriting a query). INTERCEPTORS.
- `Linq/RemoteContextTests.cs` -- `ILinqService` contract (GetInfo, ExecuteNonQuery/Scalar/Reader/Batch, sync and async), `TestFlagsTransfered`, remote-runner client lifetime (`RemoteRunnerDoesNotLeakClientAcrossTwoQueryPlan`, `RemoteRunnerLeavesAContextOwnedClientAlive`), `ConfigurationScopedColumnAttributeAppliesOnTheServer`, SignalR context dispose semantics. Remote LinqService / SignalR (see memory note on LinqService pool starvation).
- `Linq/MappingTests.cs` -- Enum1..9, Inner1..3, MyType1..5, MapIgnore1..3, interface mapping, `ColumnMappingException1/2`, record mapping and init-only, `ColumnReplacedWithNew1..5`, `StorageFieldTest`, `StructMapping_*` (value, collection, enumerable, int list), `MappingTypingByConstant_*` (FromEnumerable and FromQuery for Int64, UInt64, UInt32, Decimal, Double, Float), composite-name conflicts (attributes and fluent), `TestListBasedEntity`, Issue1833/2362/3060/3117/4437/4798/5057/5540, `TimespanAsTicksRegression`. METADATA mapping and constant retyping (see memory note on literal retyping).
- `Linq/L2SAttributeTests.cs` -- NETFRAMEWORK-only: `IsDbGeneratedTest` and Issue3691 over System.Data.Linq attributes. METADATA `SystemDataLinqAttributeReader`.
- `Linq/IssueTests.cs` -- misc numbered repros in one fixture: Issue38/42/60/67/75/115/173/376/424/498/508/528/535/88/909/2823, `InsertFromSelectWithNullableFilter`, `ExpressionBuilder_StackOverflow`, `IncorrectNesting*`, `AliasBug5657_*`, and `Issue5972_*` for each of SByte, Byte, Int16, UInt16, Int32, UInt32, Int64, UInt64 with a Parameter variant (integer-typed constants vs parameters).

**Interval / duration translation (IntervalTranslationTests partials, issue #5750 area)**
Six partials of `IntervalTranslationTests` (Arithmetic 36, Difference 27, Queries 35, Members 9, Mapping 5, Write 6 methods). They validate declared-unit duration columns (TimeSpan stored as ticks, seconds etc. via declaration or converter) and date differences against CLR semantics.
- `Linq/IntervalTranslationTests.Arithmetic.cs` -- duration +/- duration (refusal when declared unit or converter disagrees, `TwoDisagreeingConvertersRefuseToCombine`), duration ratio, `ADateShiftsByAComputedDuration*` (sub-millisecond, over 68 years, millennia, DateTimeOffset, SQL Server smalldatetime and coarse types), shifts in predicate, update and remote context.
- `Linq/IntervalTranslationTests.Difference.cs` -- date difference from server now, parameter, columns and outer join, `Total*` and component members vs CLR, zoned (DateTimeOffset) differences, sub-second precision, long spans and full CLR range on wide columns, differences inside subqueries and set operations.
- `Linq/IntervalTranslationTests.Queries.cs` -- durations through GroupBy, aggregates, OrderBy, Contains (same and cross unit, `ContainsAcrossASubTickUnitIsRefused`), Concat/Union (`UnionRefusesBranchesThatStoreADurationDifferently`), conditional, CTE and recursive CTE, scalar subquery, local-collection source.
- `Linq/IntervalTranslationTests.Members.cs` -- Total/component members of optional and long-stored durations, each declared unit round-trip, units finer than a tick expose no members, negative components truncate toward zero.
- `Linq/IntervalTranslationTests.Mapping.cs` -- declared unit on nested and dynamic columns, unit taken from the declaration not the storage type, negated converted column keeps its converter.
- `Linq/IntervalTranslationTests.Write.cs` -- optional duration, BulkCopy, Update, Upsert (+builder), InsertOrUpdate round-trip of the declared unit.

### Linq/ root, fourth batch (2026-10-10, 40 files, StringConcat..WindowFunctions.RegrAvgY -- re-visits of files modified on master)

Re-visit pass over the tail of `Tests/Linq/Linq/` (String*, SubQuery, TableOptions, TakeSkip, TestQueryCache, TphInheritance, Types, ValueConversion, VisualBasic, Where, and the WindowFunctionsTests.A..R partials). Class headers, fixture attributes and the full test-method inventory were read for every file, plus targeted reads of the non-trivial window-function files (Equality, RatioToReport, Frame, root entity/seed). All are re-visits: these files were previously counted, so coverage_tier_2 stays 700/700.

**String translation**
- `Linq/StringConcatTests.cs` -- `SqlConcatExpression` overhaul (PR #5504): `Concat_*` family over two/three/four args, `+` operator, nullable operands (COALESCE wrap, null treated as empty), `Concat_Sybase_NullGuardOnlyForNullableOperands` (issue #5530), SELECT/ORDER BY positions, grouping aggregates (`Concat_OverGrouping_*`: STRING_AGG/GROUP_CONCAT/LISTAGG, Guid/int ToString, null filtering, distinct), `AggregateExecute` (sync/async/outer filter), `Concat_AggregateArrayPerRow*`, `Concat_AssociationSubquery`, and untranslatable-operand cases (`*_PartialTranslation_LetBoundNonTranslatable`, `*_SetOperationOperand_Untranslatable*`) that must fall back to client evaluation inside set operations. EXPR-TRANS string translators.
- `Linq/StringJoinTests.cs` -- `string.Join` over grouping: parameter/various/ordered/distinct forms, unsupported-method and member-init fallbacks, `JoinAggregateExecute*` (nullable, filtered, async), `JoinAggregateArray*`, `JoinOnClient`, and `StringJoinAssociationSubqueryUpdate1/2` (association subquery as UPDATE source).
- `Linq/StringTrimTests.cs` -- `TrimStart/TrimEnd(char[])` (PR #5515): no-arg/empty/null array, single char, literal vs parameter char sets for VarChar/NVarChar/Char/NChar, captured-array cache semantics (`*CharsCache_HitsOnSameContent`, `_LocalFunctionWithReorderedCharsHits`, `_MutationMissesCache`, `_MutatedCapturedArray`), legacy `TrimLeft/TrimRight` null-source preservation, SQL-shape assertions (NVARCHAR literal for non-ASCII, MySQL 8 regex is case sensitive, Oracle empty result becomes NULL).
- `Linq/StringFunctionTests.cs` -- the broad `string` member suite (two fixtures in the file: provider-function wrappers `Length/Substring/CharIndex/Reverse/Left/Right/Stuff/Space/PadLeft/Replace`, then CLR-member translation): Contains/StartsWith/EndsWith constant/parameter/case/DataType variants, Like, IndexOf/LastIndexOf, Trim variants, ToLower/ToUpper, CompareTo/CompareOrdinal/Compare matrices, IsNullOrEmpty, `Explicit*/Default_*` StringComparison matrices, `String_PadLeft/PadRight_Translation`, Issue3002. Validates the string member-translation layer and LIKE escaping per provider.

**Query shape, paging, subqueries, predicates**
- `Linq/SubQueryTests.cs` -- Test1..8, `DerivedTake/DerivedSkipTake`, `ObjectCompare`, Contains, `SubSub*` nested subqueries, Count1..3, `DropOrderByFromNonLimitedSubquery`, `PreserveOrderInSubqueryWithWindowFunction_*`, `DistinctSubqueryTest`, Issue1601/383/4458/4347/3295/3334/3365/4184/4751. Subquery flattening and ORDER BY retention in the SQL optimizer.
- `Linq/TakeSkipTests.cs` -- Take/Skip/SkipTake matrices with async twins, ElementAt/ElementAtDefault, `TakeWithPercent`, `TakeWithTies`/`SkipTakeWithTies`, `TakeWithHintsFails`, Multiple{Take,Skip,TakeSkip}1..4 (limit folding), `SkipTakeCaching` (paging values as cache-key parameters). Paging emulation per provider (TOP/LIMIT/ROW_NUMBER).
- `Linq/WhereTests.cs` -- 2600-line predicate fixture: null/nullable comparison matrices (`EqualsNull*`, `CompareNullable*`, `ComparisionNullCheckOn/Off`, `CheckNull1..3`), boolean-as-predicate (`WhereBooleanTest*`, `NullableBooleanConditionEvaluation*`, `NullableBoolean_NotFalse_AsNotTrue`), `IsNullOrEmpty`, subquery filters (`Issue_SubQueryFilter1..3`, `Issue_CompareQueries*`), parenthesization (`Issue2897_ParensGeneration_*`) and many numbered issue repros. Predicate generation in the SQL builder and null-semantics handling.
- `Linq/TableOptionsTests.cs` -- `TableOptions` flags (IsTemporary, IsGlobalTemporary, CheckExistence, CreateIfNotExists, `.IsTemporary()`/`.TableOptions()` methods, fluent mapping) and one `*TableOptionsTest` per vendor (DB2, Firebird, Informix, MySql, Oracle, PostgreSQL, SapHana, SQLite, SqlServer, Sybase) asserting CREATE TABLE option syntax. SQL-PROVIDER DDL.
- `Linq/TestQueryCache.cs` -- `Query<T>` cache: `BasicOperations(+Async)`, `TestSchema`, `TestSqlQueryDepended`, `TestContextLeak` (cache must not root the data context). Complements QueryCacheEvictionTests.

**Types, conversions, inheritance, languages**
- `Linq/TypesTests.cs` -- Bool1..3/BoolField1..6/BoolResult1..3/BoolTest3x, Guid, Binary insert/update, DateTime1/21..24 and DateTimeArray/Params, `ADateBoundBeforeTheColumnsRange` (date parameter lower than the storage range of the column), nullable comparison, Unicode, CultureInfo, SmallInt, Char tests, `TestSpecialValues`, Issue4469 x4. Scalar type mapping through LINQ.
- `Linq/ValueConversionTests.cs` -- `ValueConverter`-backed columns: Select/Parameter/GroupBy/Extension/Bool/Coalesce/Union/Join/Null, Insert/Update/`InsertExpression`, and the recent set-operation and update-value conversion cases (`UnionDistinctsTheValueTheConditionChose`, `WhereChoosesBetweenTwoConvertedColumns`, `UpdateValuesWithConversion*` incl. a row-valued throw case, `ConversionSurvivesASetOperation`, `SeparatelyDeclaredConversionsAreReadTheSameWay/StillCompare`, `Insert/UpdateServerSideValueIntoClientConvertedColumn`, `SetOperationOver*Conversions`, `DivergentConversionsRefuseToCombine`, `CountOverAConvertedColumnIsNotConverted`), Issue3684/3830/5075/5310. Related to the EF Core DateTime converter fix in set operations and server-side insert/update values (#5978).
- `Linq/TphInheritanceTests.cs` -- table-per-hierarchy suite, now far beyond the deep-hierarchy pair: `TPH_DeepHierarchy_*` (find, polymorphic, BulkCopy), `TPH_SiblingColumn_*` (same physical column mapped by sibling types, divergent read shapes, differing/same value converters, name collisions), `TPH_CodeFilter/InterfaceFilter/TernaryIsTypePredicate`, projections, `TPH_Downcast_*`, `TPH_Assoc_OnDerived_*`, `TPH_MultiLevel_*`, `TPH_OfTypeAbstractIntermediate`, and the `TPH_Intermediate_{Read,Update,Join}_Via{IntermediateTable,OfType,Cast,SelectCast,Filtered}` matrix plus Insert/CreateTable. Validates discriminator-chain handling in METADATA/EXPR-BUILDER. SQLite.
- `Linq/VisualBasicTests.cs` -- VB-compiled expression shapes (`CompareString*`, `ParameterName`, `SearchCondition1..4`, Issue649, Issue2746) against the VB test assembly: VB string comparison and parameter-name lowering.

**Window functions (WindowFunctionsTests partials, namespace Tests.Linq, `[SupportsAnalyticFunctionsContext]` + `[ThrowsForProvider]` + `ErrorHelper.Error_WindowFunction_*`)**
- Root `WindowFunctionsTests.cs` -- `[TestFixture] partial class WindowFunctionsTests : TestBase` with `WindowFunctionTestEntity` (PK Id, Name, CategoryId, Value, Timestamp, int/long/double/decimal/float/short/byte plus nullable and bool variants, Access `DataType` overrides) and static `Seed()` of four rows (Alice/Bob in category 1, Charlie/Diana in 2).
- Aggregates: `Average`, `Sum`, `Min`, `Max` (each: `*WithBooleanWindow`, `*Overloads`, `*OverloadsViaWindow`, `*Distinct`), `Count` (no-arg, arg, boolean arg, filter, DefineWindow, distinct), `Filter` (`SumWithFilter`, `AverageWithFilter`).
- Ranking/distribution: `DenseRank`, `Rank` (multiple partitions, DefineWindow, nulls, no-partition, boolean order/partition), `RatioToReport` (native on Oracle/DB2, otherwise `expr / SUM(expr) OVER`, with a zero-partition-sum case yielding NULL, DB2 gated by `[ActiveIssue(5897)]`).
- Value functions: `FirstValue`, `LastValue`, `NthValue` (incl. `NthValueFromLast`), `Lag`, `Lead` (offset, default, partition, IGNORE/RESPECT NULLS, boolean).
- Frames: `Frame.cs` (ROWS/GROUPS/RANGE, explicit direction, `*ValuesShortcut`, expected sums checked against a client-side `ExpectedFrameSum`; `FrameRangeOffsetNullsEmulatedKey` -- MySQL 8 must throw "NULLS ordering is emulated" for a RANGE offset on a nullable key with explicit NULLS position, with a non-nullable control), `FrameExclusion.cs` (EXCLUDE CURRENT ROW/GROUP/TIES for ROWS/RANGE/GROUPS), `Combinations.cs` (filter+frame, mixed functions, DefineWindow reuse, window function over window-function column).
- Statistical/ordered-set: `Corr`, `CovarPop`, `CovarSamp`, `Regr*` (AvgX, AvgY, Count, Intercept, R2, SXX, SXY, SYY, Slope), `StdDev*`, `Variance/VarPop/VarSamp`, `Median` -- each two tests (`*Basic`, `*ViaWindow`) following the shared SQL-contains-then-execute shape (Median has one). `PercentileCont/PercentileDisc` (boolean order-by, grouping, filter, projection, subquery, windowed, async), `HypotheticalSet` (Rank/DenseRank/PercentRank/CumeDist WITHIN GROUP), `Keep` (Oracle KEEP DENSE_RANK FIRST/LAST).
- `WindowFunctionsTests.Equality.cs` -- not a database test: regression that `SqlExtendedFunction` argument equality is positional and symmetric (`COVAR_POP(a,b)` differs from `COVAR_POP(b,a)`, and `(a,a)` from `(a,b)`) so common-subexpression elimination and the query cache cannot merge them. SQL-AST `SqlExtendedFunction.Equals`.

### Mapping/, Update/, window-function tail and misc tail dirs, fifth batch (2026-10-10, 40 files -- re-visits of files modified on master)

Re-visit pass over files already counted in coverage_tier_2 (so 700/700 is unchanged). Class headers, fixture attributes and the full test-method inventory were read for every file, plus targeted reads of the non-trivial ones (WindowFunctionsTests.RowNumber/Sum/RegrR2, FluentMappingTests Issue3119, DeleteTests/InsertTests `[ActiveIssue]` stacks). `git log` on the directories shows why most were touched: #5882 (run-and-verify `[ActiveIssue]` replacement) rewrote the attribute stacks across Mapping/, Update/, OrmBattle/ and SchemaProvider/, and #5614 (parallel execution) / #5785 (`[QueryCacheTest]`) touched Mapping and Update fixtures.

**Cross-cutting change: `[ActiveIssue]` is now a run-and-verify attribute (#5882)**
- `Tests/Base/Attributes/ActiveIssueAttribute.cs:42` -- `ActiveIssueAttribute : NUnitAttribute, IApplyToTest, IWrapSetUpTearDown`. The test still runs and the attribute checks it fails the declared way: `ErrorTypeName`, `ErrorMessage`, `Configuration` / `Configurations = [...]`, and a `Details` string. A `Details` starting `no-issue:` or `no-declaration:` records why there is no issue number or no pinned error text. The attribute is repeated per provider group, and it defers to `[ThrowsForProvider]` where both apply.
- Examples: `Update/DeleteTests.cs:597-613` (derived-table DELETE, `TestDeleteFrom` from the EF Core tests, split per provider: PostgreSQL syntax error, Informix/MySQL/SqlCe/SQLite/Ydb `Unexpected table type SqlQuery`, Firebird, DuckDB, HANA, ClickHouse, Oracle `ORA-01732`, with Sybase left to `ThrowsForProvider(Error_OrderBy_in_Derived)`), `Update/InsertTests.cs:2421-2440` (`Issue4702Test`, KeepIdentity RowByRow per provider), `Mapping/FluentMappingTests.cs:804-805` (`Issue3119Test`/`Issue3136Test`, issue number recovered from the Test Description), `Mapping/DynamicStoreTests.cs` (`Issue2953Test1/2`, SQL Server), `Scaffold/SchemaProviderTests.cs:15` (`Issue4444Test`, PostgreSQL dblink `IsResultDynamic`).

**Window functions (WindowFunctionsTests partials, RegrCount..VarSamp tail)**
- `WindowFunctionsTests.RowNumber.cs` -- 8 tests: `RowNumberWithMultiplePartitions(+WithDefineWindow)`, `RowNumberWithNulls` (`OrderBy(x, Sql.NullsPosition.First)` / `OrderByDesc(..., Last)`, with a TODO about emulating via CASE ordering), `RowNumberWithoutPartition`, and four tests for boolean ORDER BY / PARTITION BY and real values: `RowNumberWithBoolean` (predicate and `!= null` folded into a value), `RowNumberWithBooleanComputedValues` (pinned numbering: Id 2 is the only `IntValue == 20` row, so ByOrder 9 and ByPartition 1), `RowNumberWithBooleanColumn` (a boolean column stays unfolded and must number identically to the equivalent predicate, the NULL `NullableBoolValue` row is alone in its partition), `RowNumberAndSumComputedValues` (4-row inline dataset, RN 1,2,1,2 and SUM 30,30,70,70). Validates the boolean fold in window clauses plus result values rather than SQL shape only.
- `WindowFunctionsTests.Sum.cs` -- `SumWithBooleanWindow` (SUM takes numeric only, so a boolean reaches it only through the window clause), `SumOverloads` / `SumOverloadsViaWindow` (14 numeric overloads incl. nullable int/long/double/decimal/float/short/byte, inline vs `DefineWindow`+`UseWindow`), `SumDistinct` (`w.Distinct()`, gated by `ErrorHelper.Error_WindowFunction_AggregateDistinct` on SQL Server, PostgreSQL, MySQL 8+, SQLite, Firebird 3+, HANA, DB2, Informix, Ydb, and asserting `OVER` and `DISTINCT` are both emitted where supported). The non-distinct tests are gated only on SQL Server 2008 and below via `Error_WindowFunction_AggregateWindowFunctions`.
- Two-test statistical files, each `*Basic` (inline `PartitionBy(CategoryId).OrderBy(Id)`) and `*ViaWindow` (`DefineWindow`+`UseWindow`), asserting `ToSqlQuery().Sql.ShouldContain(FUNCTION)` then executing: `RegrCount`, `RegrIntercept`, `RegrR2`, `RegrSXX`, `RegrSXY`, `RegrSYY` (two-argument `Sql.Window.RegrX(t.DoubleValue, t.IntValue, ...)`, gated on `Error_WindowFunction_LinearRegression` for SQLite, SQL Server, MySQL 8+, ClickHouse, Firebird, HANA, Informix, Ydb), and `StdDev`, `StdDevPop`, `StdDevSamp`, `Variance`, `VarPop`, `VarSamp` (single-argument over `IntValue`, gated on `Error_WindowFunction_Variance`).
- Production areas: window-function member translators and the `Sql.Window` surface (EXPR-TRANS), `SqlExtendedFunction` rendering (SQL-AST), per-provider capability gating (SQL-PROVIDER, PROV-*).

**Mapping/ (METADATA)**
- `Mapping/CanBeNullTests.cs` -- `CanBeNullTests : TestBase`, `ResetNullableOptions` setup plus `InferFromMetadata`, `OverrideMetadata`, `IgnoreNullableDisabledModel`, `DefaultValues`: `[Column(CanBeNull=...)]` versus nullable-reference-type inference (`NullableOptions`).
- `Mapping/DynamicStoreTests.cs` -- dynamic column store (`Dictionary<string, object>` property) declared by fluent, attribute and metadata reader. Helper classes cover instance and static getter/setter methods, expression-based getter/setter, SQLite-specific accessors, getter/setter vs storage conflicts, multiple and absent accessors. Tests: `TestDynamicColumnStoreFromMetadataReader`, `...FluentExtension`, `...FluentWithConfiguration`, `...AttributeWithConfiguration`, `...Instance/Static(Expression)Accessors`, `...InstanceConfigurationAccessors`, `...GetterSetterVsStorageMethods1/2/Conflict`, `...Expressions`, `...AttributeDefaultValue`, `...AccessorsDefaultValue`, `...MultipleGetterSetters`, `...NoGetterSetters`, `DynamicColumnStoreIssue1521`, `Issue3859Test1..3`, `Issue2953Test1/2` (SQL Server, `[ActiveIssue(2953)]`). SQLite plus ClickHouse.
- `Mapping/FluentDynamicMappingTests.cs` -- the string-name `FluentMappingBuilder` surface (`HasAttribute`, `Property`, `Association`, `HasPrimaryKey`, `HasIdentity`, `HasColumn`, `Ignore`, `HasDynamicColumnStore(+WithConfiguration)`, inheritance), each in two variants (1/2).
- `Mapping/FluentMappingBuildTests.cs` -- 5 tests: `InsertOrUpdatePrimaryKeyTest` (Oracle), `UpdateTest(+Async)`, `MergeTestAsync` (MergeDataContextSource) and `CacheTest`. Fluent mapping built per context, with query-cache behavior (marked `[QueryCacheTest]` in #5785).
- `Mapping/FluentMappingExpressionMethodTests.cs` -- `[ExpressionMethod]` registered fluently: `ExpressionMethodOnProperty`, `ExpressionMethodAsColumn`, and the nested-property family `ExpressionMethodOnNestedProperty(+_InFilter)`, `...OnDeeplyNestedProperty`, `...OnNestedAndNonNestedProperty` (SQLite), the regression for fluent `IsExpression` on a nested/complex property from #5635.
- `Mapping/FluentMappingTests.cs` -- the main fluent suite: `LowerCaseMappingTest`, `AddAttributeTest1/2`, `HasPrimaryKey1..4`, `IsPrimaryKeyIsIdentity`, `TableNameAndSchema`, associations, `FluentInheritance(+2,+Expression)`, `DoubleNameChangeTest`, `AttributeInheritance(+2)`, `InterfaceInheritance`, `Issue291Test1/2Attr`, `ExpressionAlias(+Fluent)`, PostgreSQL `TestSequenceHelper/TestSequenceAttribute`, `MapValueTest`, `Issue3119Test`, `Issue3136Test` (both run-and-verify gated).
- `Mapping/MappingSchemaTests.cs` -- `MappingSchemaTests : TestBase`: `DefaultValue1..3`, `BaseSchema1/2`, `CultureInfo`, `AttributeTest1..8`, `ConvertEnum1/2`, `ConvertNullableEnum`, `DoNotUseComplexAttributes`, `TestIssue3312`. Touched by #5614/#5634/#5641 (isolation of tests mutating the global `Common.Convert<,>` converter, `[NonParallelizable]` removal) and #5710.
- `Mapping/ValueConverterColumnDbTypeTests.cs` -- 2 pure-mapping tests: `ConverterColumn_ResolvesDbTypeFromProviderType` and `ConverterColumn_PropagatesProviderPrecisionAndScale` (a `ValueConverter<Money, decimal>` column resolves its DbType, precision and scale from the provider type of the converter, #5645).

**Update/ (EXPR-TRANS, SQL-PROVIDER, PROV-*)**
- `Update/BulkCopyTests.cs` -- 39 tests: KeepIdentity with SkipOnInsert true/false, `ReuseOptionTest`, `UseParametersTest`, `MaxSqlLengthForBatchSplitsStatements` and `MaxParametersForBatchRaisesProviderLimit` (batch splitting and the Oracle SQL length cap raised to 384KB and made configurable in #5828), `BulkCopyWithDataContext(+Async,+FromTable)`, `BulkCopyDateOnly(+ArrayBound)`, the `CloseAfterUse` matrix (DataContext or DataConnection, sync, async or async-enumerable, plain, KeepIdentity or OracleAlternative), `BulkCopyTPH(+Default)`, `BulkCopyAutoOnly*` / `BulkCopySkipOnly*`, `MultipleRows_TestTyping`.
- `Update/CreateTableTests.cs` -- `CreateTable1/2(+Async)`, SQL Server local temp tables (`CreateLocalTempTable1/2(+Async)`), `CreateTableWithEnum`, `CreateFormatTest`, `TestIssue160`, `Issue3223Test`, `Issue4671Test`.
- `Update/CreateTempTableTests.cs` -- `CreateTable1..3`, header/footer variants (SQLite), enumerable / async / cancellation (`CreateTableAsyncCanceled(2)`), `CreateTable_NoDisposeError(+Async)`, primary-key temp tables, schema conflicts, description and name+description variants.
- `Update/DeleteTests.cs` -- 20 test methods with `[ActiveIssue]` stacks (see above), including association deletes and the derived-table delete.
- `Update/DropTableTests.cs` -- `DropCurrentDatabaseTable*`, `DropSpecificDatabaseTableTest`, then `DropTable_*` and `Drop_*` pairs (Existing, Missing_Ignore, Missing_Fail, Fail_NotFromExistCheck_EarlyError/LateError) plus `DropTable_IfExists_IdentifierWithApostrophe` (identifier escaping in IF EXISTS).
- `Update/EntityInsertTests.cs` and `Update/EntityUpdateTests.cs` -- the entity-builder DML surface is larger than recorded earlier. Insert has `Bare`, `Set_ContextFree`, `Set_FromSource`, `Ignore`, `Multiple_SetAndIgnore`, `Async_Insert`, `NoDefaultConstructor`, `QueryCache_ParameterisesItemValues`, `Insert_NestedColumn`, `Insert_Set_DynamicColumn`, `Insert_AutoDerive_DynamicColumn`. Update adds `Set_FromTargetAndSource`, `Ignore`, `Async_Update`, `NoPrimaryKey_Throws` (YDB data sources), `Update_Set_DynamicColumn`, `Update_AutoDerive_DynamicColumn`, `Update_NestedColumn`. The nested/dynamic-column cases are SQLiteMS only and tie the builder to the dynamic-store and complex-property mapping.
- `Update/InsertTests.cs` -- 89 test methods, large `[ActiveIssue]` stacks (`Issue4702Test`) plus `Issue2243`, `Issue3927Test1/2`: insert, InsertWithIdentity, InsertOrReplace and insert-from-query shapes per provider.

**Tools/, Reflection/, Samples/, Scaffold/, SchemaProvider/, OrmBattle/, Microsoft/ (INTERNAL-API, IN-TREE-TOOLS, SCAFFOLD, EXPR-TRANS)**
- `Tools/ComparerBuilderTests.cs` -- `ComparerBuilderTests` (no `TestBase`): inherited members 0..4, complex member, method handle, GetHashCode/Equals, struct equals, no-member / one-member, `DistinctTest`, `DistinctByMember1..3Test`, `AttributeTest`.
- `Tools/Mapper/MapperTests.cs` -- `MapperTests : TestBase`: `MapperBuilder` action vs func expression, scalar/enum maps, `MapObjects1/2`, `MapObject`, `MapFilterObjects`, inner objects, `SelfReference1..3`, `DeepCopy1/2`, lists/arrays, `NoCrossRef`, recursion 1..3, `ByteArrayTest`, with `[Values] bool useAction`, and an `[Explicit]` `PerfTest`.
- `Reflection/AttributesTests.cs` -- `AttributesTests` sealed: `PropertyAttributeInheritanceTest`, `EventAttributeInheritanceTest`, `DynamicColumnInfoAttributes`.
- `Samples/ConcurrencyCheckTests.cs` -- `InterceptDataConnection` subclass with a `RowVersionAttribute` check (`CheckUpdateOK/Fail`, `InsertAndDeleteTest(+Async)`, `CheckInsertOrUpdate`), the sample counterpart to `ConcurrencyExtensions` (#5643 UpdateOptimisticWithRefresh).
- `Samples/JsonConvertTests.cs` -- `MappingHelper.GenerateConvertors` over `[JsonContent]` columns and a `Json.Value` `Sql.IExtensionCallBuilder`, single `SampleSelectTest` (SQL Server 2016+, ClickHouse). Touched by #5870 (analyzer for server-side-only contracts).
- `Scaffold/SchemaProviderTests.cs` -- one test, `Issue4444Test` (PostgreSQL, dblink function result is dynamic), run-and-verify gated.
- `SchemaProvider/SchemaProviderTests.cs` -- `TestApiImplemented`, `Test`, `NorthwindTest`, `MySqlTest`, `MySqlPKTest`, `PostgreSQLTest`, `DB2Test`, `ToValidNameTest`, `IncludeExcludeCatalogTest`, `IncludeExcludeSchemaTest`, `SchemaProviderNormalizeName`, `PrimaryForeignKeyTest`, `ForeignKeyMemberNameTest1/2`, `SchemaOnlyTestIssue2348`, `ClickHouseDataTypeTest`.
- `SchemaProvider/PostgreSQLSchemaProviderTests.cs` -- class `PostgreSQLTests` in the file `PostgreSQLSchemaProviderTests.cs` (class name differs from the file): `ProceduresSchemaProviderTest` driven by `ProcedureTestCase` data, `DescriptionTest`, `TestMaterializedViewSchema`, and the #5628 family `Issue5628SequenceDefaultExpressionIsNotIdentity`, `...ParenthesizedSequenceDefaultIsIdentity`, `...DuplicateSequenceDefaultsPreferPrimaryKey`, `...DuplicateSequenceDefaultsWithoutPrimaryKeyUseFirstColumn`, `...RealIdentityPreferredOverSequenceDefault` (PostgreSQL 10+), covering the identity detection fix for sequence defaults (#5647).
- `OrmBattle/OrmBattleTests.cs` -- `OrmBattleTests` sealed, 123 `[Test]` methods all taking `[NorthwindDataContext] string context` (Where/Select/Join/GroupBy/Union/Skip-Take families against the Northwind model, with an `OrderDTO` projection class). Touched by #5614, #5795, #5882 and 6.5.0 release prep.
- `Microsoft/MicrosoftODataTests.cs` -- `SelectViaOData`, `SelectPure`, `SelectPure2(+Simplified)` (SQLite classic, ClickHouse) with hand-written `GroupByWrapper` / `AggregationWrapper` / `FlatteningWrapper<T>` shapes standing in for the expressions OData generates, and `Issue3757Test` (any() over children, `$filter` variants, ClickHouse and Ydb excluded from data sources).

**AUDIT-NOTE (stale prior claim, preserved verbatim above):** the fourth-batch paragraph on the root `WindowFunctionsTests.cs` says the static `Seed()` has four rows. The RowNumber tests read this run assert nine seeded rows (Ids 1..9, exactly one with `IntValue == 20`, Id 9 the only NULL `NullableBoolValue`). Treat nine as current.

### Update/ Merge/Upsert/Update partials and UserTests, sixth batch (2026-10-10, 40 files -- re-visits of files modified on master)

Re-visit pass over files already counted in coverage_tier_2 (700/700 unchanged). Class headers, fixture attributes and the full test-method inventory were read for every file, plus targeted reads of the non-trivial ones (`MergeTests.Operations.Insert.cs:1635-1740`, `MergeTests.ApiParametersValidation.cs:1-130`, `MergeTests.Caching.cs`, `MergeTests.Types.cs:330-370`, `Issue228Tests`, `Issue2161Tests`, and the `[ActiveIssue]` stacks of Issue1238/1307/1363/2743/3089). What recent master changes added is mostly the #5882 run-and-verify `[ActiveIssue]` rework (see the fifth-batch cross-cutting note) plus #5614/#5785 isolation attributes. New tracker numbers surfacing here: #5896 (Sybase MERGE) and #5591/#5595 (YDB).

**Update/MergeTests partials (EXPR-TRANS merge builder, SQL-PROVIDER merge emulation, PROV-*)**
All twelve files are slices of one `public partial class MergeTests` (namespace `Tests.xUpdate`), driven by `[MergeDataContextSource]` data sources (providers with MERGE or its emulation).
- `MergeTests.ApiParametersValidation.cs` -- `_nullParameterCases` builds ~60 `Action` lambdas, one per `LinqExtensions` merge-builder overload (`Merge`, `MergeInto`, `Using`, `UsingTarget`, `On`, `OnTargetKey`, `InsertWhenNotMatched(And)`, `UpdateWhenMatched(And)(ThenDelete)`, `DeleteWhenMatched(And)`, `UpdateWhenNotMatchedBySource(And)`, `DeleteWhenNotMatchedBySource(And)`), each passing `null!` for one argument. `MergeApiNullParameter` is one `[TestCaseSource]` asserting `ArgumentNullException`. Fake `IMergeableSource/Using/On` markers (`FakeMergeSource`, `FakeMergeUsing`, `FakeMergeOn`) and `FakeTable<T>` stand in for real builders, so no database is touched. Guards the public null-check contract of the merge fluent API.
- `MergeTests.Caching.cs` -- `EnumerableSourceQueryCaching` (`[Test, QueryCacheTest]`, the #5785 marker): merges three different in-memory arrays (1, 1 and 2 rows) through `Using(source).OnTargetKey().InsertWhenNotMatched()` and asserts `GetCacheMissCount()` does not grow, i.e. enumerable source values are parameterized and not part of the cache key.
- `MergeTests.IQueryableSource.cs` -- `MergeIntoIQueryable`, `MergeIntoCte`, `MergeIntoCteIssue4107` (SQL Server 2008+ only), `MergeFromIQueryable`, `MergeFromCte`, `MergeUsingCteJoin`, `MergeUsingCteWhere` (Sybase excluded). `[ActiveIssue(2363, InvalidCastException ...)]` on the two IQueryable tests and a five-provider `[ActiveIssue(3015, ...)]` stack (Firebird, Informix DB2, DB2, HANA, Oracle `ORA-00928`) on the CTE join/where source tests.
- `MergeTests.Issues.cs` -- regression cluster: `Issue200InSource/InPredicate/InPredicate2/InInsert/InUpdate`, `Issue1007OnNewAPI`, `TestDB2NullsInSource`, `TestMergeWithInterfaces1..21` (interface-typed target/source members), `TestEnumerableSourceCaching`, `TestNullableParameterInSourceQuery`, `Issue3729Test`, `Issue3589Test`, `Issue4338Test`, `Issue2918Test`, `Issue4584Test` (parameter-token count assertion, three per-provider `[ActiveIssue(4584)]` gates), `MergeSubquery`, `Issue_EnumerableSourceDuplicateColumnAlias`, and `UnusedSource_Query/Enumerable/EmptyEnumerable` (Sybase gated separately for LinqService versus non-LinqService via `SkipForLinqService` / `SkipForNonLinqService`).
- `MergeTests.Operations.Combined.cs` -- ~23 tests combining operation kinds in one MERGE (`InsertUpdate`, `InsertDelete`, `UpdateWithConditionDelete`, `InsertUpdateBySourceWithConditionDeleteBySource`, `InsertDeleteUpdateBySource`, `UpdateInsert`, `DeleteInsert`, `UpdateWithDeleteInsert`, `InsertUpdatePKOnly`, ...): permutations of the WHEN MATCHED / NOT MATCHED / BY SOURCE clause set, with and without conditions.
- `MergeTests.Operations.Delete.cs` -- 13 tests: `SameSourceDelete(+WithPredicate)`, `DeletePartialSourceProjection_KnownFieldInCondition`, `...UnknownFieldInCondition` (expects an exception when the projection dropped the referenced column), `OtherSourceDelete*`, `Anonymous(List)SourceDeleteWithPredicate`, `DeleteReservedAndCaseNames(+FromList)` (identifier quoting), `DeleteFromPartialSourceProjection_MissingKeyField`.
- `MergeTests.Operations.DeleteBySource.cs` -- 9 tests of `DeleteWhenNotMatchedBySource(And)`: same, other, anonymous and anonymous-list sources, reserved and case-sensitive names, partial source projection.
- `MergeTests.Operations.Insert.cs` -- the largest slice (~45 tests): same-source and other-source `InsertWhenNotMatched` from table, query, query with select, collection and empty collection (each plain, `WithMatch`, `WithMatchAlternative`), cross-joined sources (`InsertFromCrossJoinedSourceQuery`, `...2`, `...3`, `...2Workaround`, `InsertFromSelectManySourceQuery`), partial-source-projection known/unknown field cases, `InsertWithPredicate/Create/ComplexSetter`, reserved names, async variants, `DataContextTest`. Newly gated in this revision: `CrossJoinedSourceWithSingleFieldSelection` carries `[ActiveIssue(5896, Configuration = AllSybase ...)]` (Sybase merge emulation reports 2 affected rows where 4 are due, the lossy step is unidentified) and `SortedMergeResultsIssue` carries two `no-issue:` gates (DB2, Oracle, PostgreSQL 15+ and DuckDB: a server-side sort does not survive the merge, and Sybase: the same row-count under-report). `InsertFromCrossJoinedSourceQuery2` is gated on a `ShouldAssertException`. Both new tests merge a `CrossJoinLeft x CrossJoinRight` projection that keeps only `RightId` into `CrossJoinResult` and expect 5 final rows (4 inserted with `Id == 0`, plus the seeded `Id 11` row), sorted on the client in the first test and on the server in the second.
- `MergeTests.Operations.Parameters.cs` -- 19 tests proving parameters work in every merge position: list-source property, match, update/insert/delete/delete-by-source/update-by-source conditions, insert create, update expressions, source filter and select, the delete condition of UPDATE-WITH-DELETE, and two Firebird tests (`TestParametersInSourceQueryFirebird`, `...EnumerableFirebird`) for its typed-parameter restriction.
- `MergeTests.Operations.UpdateBySource.cs` -- 8 tests of `UpdateWhenNotMatchedBySource(And)` (same, other, anonymous, anonymous-list source, reserved names, partial projection condition).
- `MergeTests.Operations.UpdateWithDelete.cs` -- 18 tests of Oracle-style `UpdateWhenMatchedThenDelete` / `UpdateWhenMatchedAndThenDelete`: same/other/anonymous sources, predicate and update variants, `UpdateWithDeleteDeleteByConditionOnUpdatedField` (delete predicate evaluated on the post-update value) and four `UpdateThenDeleteFromPartialSourceProjection_Unknown*` negative tests.
- `MergeTests.Types.cs` -- `TestMergeTypes` and `TestTypesInsertByMerge` round-trip a full type matrix (integers, float/double/decimal extremes, DateTime, DateTimeOffset with a -15 minute offset, byte[] with an embedded zero, Guid, date-only, TimeSpan, string- and number-backed enums) through MERGE. `TestMergeTypes` carries two gates: `[ActiveIssue(5591, AllYdb ...)]` (Timestamp-to-Date and Interval-to-Int64 conversion, see also #5593) and a `no-declaration:` gate for `Oracle21DevartDirect` (the Devart licence key is absent on this machine).

**Update/ other fixtures (EXPR-TRANS, SQL-PROVIDER, PROV-*)**
- `MultiInsertTests.cs` -- `MultiInsertTests : TestBase`, Oracle INSERT ALL / INSERT FIRST: `Insert(+Async)`, `InsertAll(+FromQuery,+Async)`, `InsertFirst(+Async)`, sync/async pairs for `ParametersInSource`, `ParametersInCondition`, `ParametersInInsert`, `Expressions`, plus `Issue2990` and `InheritanceMapping` (`[ActiveIssue(2988)]`, `ORA-01400` NULL into the inheritance table).
- `UpdateFromTests.cs` -- `UpdateFromTests : TestBase` (partial): `UpdateTestWhere(Old)`, `UpdateTestJoin(+Skip,+SkipTake,+Take)`, association variants (`UpdateTestAssociation(+AsUpdatable)`, `...Simple(+AsUpdatable)`), `UpdateParentTableFromChild`, `UpdateFromWithDuplicateSubqueryColumn_SingleOrDefault/FirstOrDefault`, `UpdateFromSubqueryShouldBeOptimized`, `Issue2330Test(Old)`, `Issue2815Test1/2` (ClickHouse `LinqToDBException` plus a SQL Server/SQLite stack under `[ActiveIssue(2815)]`).
- `UpdateFromTests.Row.cs` -- the row-value SET family: `UpdateFromSubqueryRowCorrelatedValues`, `...MixedIndependentAndDependent`, `...Single/SingleOrDefault/First/FirstOrDefault`, `UpdateFromScalarSettersSharingSubquery`, `...TwoSharedSubqueries`, `...SharedSubqueryAndPlainScalar`, `...PostgreSql`, `...NoRowFlattened`, `UpdateFromSubqueryRowShouldRemainSimple1/2`, `UpdateFromSubqueryMultipleRowSetters`, `...MixedRowAndScalar`, `...RowOnPostgreSQL`, `...RowFlattened`. Validates that several SET targets reading one correlated subquery collapse into a single `(a, b) = (SELECT ...)` row assignment where supported and are flattened to scalar subqueries otherwise.
- `UpdateTests.cs` -- `UpdateTests : TestBase`, ~100 tests: `Update1..14` (+Async), column filter, `UpdateComplex1/2`, `SetWithTernaryOperatorIssue`, `UpdateAssociation1..5` (+Old variants), `CompiledUpdate`, `UpdateSimilarNames`, `AsUpdatable*`, `UpdateNullablePrimaryKey`, Top/Take/Skip ordered and unordered variants, `UpdateIssue319Regression`, `UpdateIssue321Regression` (YDB #5591 and Sybase BIT-null gates), `UpdateMultipleColumns`, `UpdateWithTypeConversion` (YDB #5591), `UpdateByTableName(+Async)`, `TestUpdateFromJoin(Old)`, `TestUpdateFromJoinDifferentTable(Old)`, `TestSetValueCaching1..6` (set-value constants versus the query cache), `TestSetValueExpr/2`, `UpdateByAssociationOptional/Required` and `...2`, `Issue4136Test`, and four DTO-source tests (`UpdateFromNamedDto`, `UpdateFromDtoWithExactlyTypedMember`, `UpdateFromAnonymousDtoWithBaseTypedMember`, `UpdateFromDtoWithInterfaceTypedMember`) checking UPDATE setters built from DTO members whose static type differs from the column type. `Update14` carries a YDB `[ActiveIssue(5595)]` gate.
- `UpdateWithOutputTests.cs` -- `UpdateWithOutputTests : TestBase`, ~130 tests laid out as a matrix of update shape (ITable, Expression, Source, IUpdatable) x output shape (default, projection, projection without old, `...Into` table, `...IntoTempTableByTableName`) x sync/async x single-record, plus `UpdateOutputComparer<T>` and a regression tail: `Issue3044UpdateOutputWithTake(2,Subquery,Cte)`, `Issue5450_UpdateOverCte_WithMultiTableQuery`, `Issue3697Test` (YDB gate), `Issue4135Test`, `Issue4193Test`, `Issue4414Test`, `Issue4253Test`.
- `UpsertTests.ApiParametersValidation.cs` -- `UpsertApiNullParameter`, the Upsert counterpart of `MergeApiNullParameter` (null guards on the fluent Upsert builder).
- `UpsertTests.Single.cs` -- `UpsertTests : TestBase`, ~35 single-row tests on `UpsertRow`: bare upsert, `WithMatch` on PK and non-PK columns, per-branch and root `Set`/`Ignore`, server-side expressions (SQL Server expression, `DateTime.Now`), target-and-source Set, last-Set-wins, `InsertIfNotExists`/`UpdateIfExists` skip branches, conditional insert/update `When`, `Insert_DoNothing`, async, `UpsertEmulationPolicyThrow` forcing an exception, query-cache parameterisation on both the native-upsert and merge-emulation paths, a family of builder-misuse rejections (`MalformedMatch`, `SkipInsert_With_Insert`, `SkipUpdate_With_Update`, DoNothing-with-ops within and across calls), and `Set_DynamicColumn` / `Set_NestedColumn`. Validates the Upsert API recorded in the third-delta section.

**UserTests/ (regression fixtures, each `[TestFixture] ... : TestBase`)**
- `Issue133Tests` -- `NegativeWhereTest`, `PositiveHavingTest`, `PositiveWindowFunctionsWhereTest`, `PositiveWindowFunctionsHavingTest`: window functions and aggregates in WHERE versus HAVING.
- `Issue228Tests` -- single `Test`, SQLite only. A private `LimitedInListSQLiteProvider : SQLiteDataProvider` sets `SqlProviderFlags.MaxInListValuesCount = 1` on its own instance (so the shared per-provider flags singleton is not mutated under parallel execution, #5614) and the test asserts the SQL contains `NOT IN (1) AND` and `NOT IN (2)`. Pins IN-list splitting in `BasicSqlBuilder` as provider-agnostic, and the `LastQuery` assertion is needed because split and unsplit results are identical.
- `Issue1238Tests` -- upsert on a table with a nullable key: `TestInsertOrUpdate` (DB2 `[ActiveIssue(1239)]`, `SQL0418N` untyped parameter marker), `InsertOrReplaceTest`, `TestMerge`, `TestMergeOnExplicit`, `InsertOrUpdate_NonPkKey_MatchesKeyNotPrimaryKey` (uses `NonPkKeyUpsert`).
- `Issue1284Tests` -- five CTE-mapping error cases: `TestCteExpressionIsNotATable`, `TestCteNoFieldList`, `TestCteInvalidMapping`, `TestCteInvalidMappingUnion`, `TestCteReservedWords`.
- `Issue1307Tests` -- `TestDateTime` plus `Test_Insert/Update/InsertOrUpdate/Inline` for date/time literal handling. The last four share one `[ActiveIssue]` keyed on `InformixLocaleError` ("Code-set conversion function failed ...") from the Informix locale on this environment.
- `Issue1347Tests`, `Issue1412Tests`, `Issue1736Tests` -- three large DTO-model reproductions from one customer codebase (WMS DTOs: `BasicDTO`, `WmsBasicDTO<T>`, extension-data interfaces): `Issue1347Tests.Test..Test5`, `Issue1412Tests.Test`, `Issue1736Tests.Issue1736Tests` (class named `UserTest`). Exercise deep generic-inheritance mapping and join projections.
- `Issue1363Tests` -- `TestInsert` of a column-referencing INSERT value, gated on Sybase and the four Access drivers (ACE OleDb/ODBC, Jet ODBC/OleDb) as `no-issue:` stacks. SqlCe was dropped from the gate (it passes direct and remote).
- `Issue1373Tests` -- `Test1..3` and `TestExpr1..3`: custom field-type conversion in projections (records `Issue1363Record`, `Issue1363CustomRecord(2)` live inside the 1373 fixture).
- `Issue1403Tests` -- `Test1..3` over `ModelBase` subclasses (`MyClass1/2/3`). `Issue1564Tests` -- `CteTest1564`, recursive CTE path (`AdminCategoryPathItemCte`). `Issue1700Tests` -- `TestOuterApplySubFunction`, OUTER APPLY over a sub-function. `Issue1869Tests` -- `TestLeftJoin` over a five-entity `PropertyChangedNotifier` model. `Issue2052Tests` -- `TestRefTypeDoNotThrow`.
- `Issue2161Tests` -- `TestLoadWithDiscriminator` (SQLite, ClickHouse): a `CountCommandsInterceptor : CommandInterceptor` counts `CommandInitialized` calls and asserts exactly 2 commands for `LoadWith(o => o.Details)` over an inheritance-discriminated table (the original bug issued the join twice).
- `Issue2596Tests` -- `TestLoadWithInfiniteLoop`, a 24-entity invoicing model (`CustomInvoice`, `Invoice`, `Town`, `CountryState`, ...) guarding against infinite recursion while building the `LoadWith` graph.
- `Issue2743Tests` -- `IssueTestInsertViaSelect` (passes) and `IssueTestDeleteViaSelect` (`no-issue:` gate, `LinqToDBException` "does not have primary key": a delete through a projection over a complex object cannot resolve its target table).
- `Issue2832Tests` -- `TestIssue2832` over `DataGroupPermission`, `DctOu`, `Deviation`, `UacUsersDatagroup` and view `VWellTree` with a `PrimaryKeyEquality<T>` base.
- `Issue3089Tests` -- `TestUnion1..4` (nullable/time union operands). `TestUnion3/4` are gated for PostgreSQL by `[ActiveIssue(3360)]` (untyped NULL branches are emitted before the typed one).
- `Issue3148Tests` -- `TestDefaultExpression`, `TestDefaultExpression_01..22` and `TestTruncateDrop`: `default(T)` expression handling in queries and DDL against a `TestTable`.

**Gate numbering (additive to the fifth-batch list):** #5896 (Sybase MERGE emulation row count), #5591 and #5595 (YDB strict-decimal and Date/Time conversion gaps in Update and Merge type tests), #3360 (PostgreSQL union column typing), plus older merge/upsert gates now in run-and-verify form (#2363, #3015, #4584, #2988, #2815, #1239).

### Batch 7 findings (2026-10-10) -- 23 UserTests/ files, re-visits of files modified on master

All files are `[TestFixture] ... : TestBase` in namespace `Tests.UserTests` unless noted. Re-visit batch: already counted in coverage_tier_2 (700/700), no numerator change. Each entry names the production behavior validated and the provider gate.

**Associations, LoadWith, eager loading**
- `Issue3230Tests` -- `InheritedAssociation` (SQLite, ClickHouse): `LoadWith(p => p.Parent).LoadWith(p => p.Parent!.GrandParent)` on `Child` and on a subclass `ChildViewModel : Child`. Associations declared on the base type must resolve for the derived mapping. Nested types hide inherited `Parent`/`Child` with `new`.
- `Issue3926Tests` -- `LoadWithAfterFilterByAssociation` (SQLite): fluent-mapped `CALL_META`/`DIALOG_CATEGORY`/`CATEGORY_GROUP` model (abstract `GuidDataObject` base, `Ignore(x => x.IsNew)`). Filters through a two-hop association, then `LoadWith` on the same path, then `OrderByDescending`/`Take` with values read from an anonymous object. Asserts via `GetSelectQuery()` that the outer select still carries the `TelegramBotName` column (load-with must reuse the filtered join).
- `Issue4383Tests` -- `Test` (Access only, `DataSources(AllAccess)`): generic association chain `PumpLineTest<TChain,TPumpLineChain>` -> `PumpLineChainTest<TChain>` -> `SewerChainTest` -> `ChainPoints`, loaded with `LoadWith(...PipeLineChains).ThenLoad(i => i.Chain.ChainPoints)`. Pins association resolution through open generic types, interface-keyed `OtherKey = nameof(IChainTest.Id)` and class-level `[Column("CHAIN_ID", nameof(Id))]` renames.
- `Issue975Tests` -- `Test` (SQL Server 2008+): association with `ExpressionPredicate = nameof(ActualTaskExp)` (`Task.ActualStage`), composite-key join, `Distinct()`, then `.Where(it => it.ActualStage.Any(...))` including a `(int?)d.StageId == null` comparison, plus a `[Sql.Function(ServerSideOnly)] GetDate()`. Inserts use `Sql.CurrentTimestamp` and `InsertWithInt32Identity`.
- `Issue4336Tests` -- `Issue4336Test` (Access only): six layered view-style `IQueryable` helpers (`ViewCapacityAndOrderedByPeriod` and friends) mixing `DefaultIfEmpty()` joins over record projections, group sums and a custom `[Sql.Extension("COALESCE(...)")] Coalesce<T>`. Executes `Take(10)` to prove the Access SQL builder handles the nested join/group depth. Carries unused IBM DB2 usings behind `#if NETFRAMEWORK`.

**Aggregates, window functions, set operations, SQL extensions**
- `Issue3257Tests` -- `Test1..3` (SQL Server 2017+): `StringAggregate(",").ToValue()` over an association collection projected through a nested enum ternary, used inside a ternary with `Any()`, under a `Contains("H")` filter, and wrapped in a `[Sql.Expression("ISNULL({0}, {1})", ServerSideOnly)]` helper. Validates string-aggregate in scalar-subquery position.
- `Issue3259Tests` -- `SubqueryAggregation` (PostgreSQL, SQLite, SQL Server 2008+): fluent-mapped employee/leave-request/date-entry model. Subquery `SelectMany(...).Select(cond ? StartHour : EndHour).DefaultIfEmpty(0).Sum()` whose selector references the outer row (`tracking.TrackingTimeType`), compared across the built-in `Sum` and two custom `[Sql.Extension(IsAggregate = true)] SumCustom` overloads (expression-argument and sequence-argument forms), against a LINQ-to-objects expectation.
- `Issue5616Tests` -- `Average_InUnionAll`, `CustomAggregate_InUnionAll` (SQLite): `Select(_ => new { Count = 0d }).UnionAll(groupBy aggregate)`. Before the fix, building threw `InvalidCastException` (`SqlPathExpression` -> `SqlPlaceholderExpression`) in `VisitSqlReaderIsNullExpression`. The second test uses a custom `[Sql.Extension("count_if({predicate})", IsAggregate = true)]` aggregate and only asserts the SQL contains `count_if` (not executable on SQLite).
- `Issue3305Tests` -- `TestComplexQueryWms` (SQLite, SQL Server): 9 temp tables, a CTE with `RowNumber()`/`Count()` window functions and `HasUniqueKey` hints, many `LeftJoin`s and nested `new Dto { ... }` projections with `StrippedDownDTO` `[NotColumn]` flags. Runs `qry.ToList()` only. Gated for SQL Server by `[ActiveIssue(3305, ErrorMessage = "Invalid object name 'InventoryResourceDTO'.")]` (no `ErrorTypeName`: the two SqlClient packages raise distinct `SqlException` types). Same customer codebase as `Issue1347Tests`/`Issue1412Tests`/`Issue1736Tests`.

**Expression methods, translators, mapping converters**
- `Issue5283Tests` -- `Test` (SQLite): nested `[ExpressionMethod]` chain (`FormatUserNumber` -> `Hospital.GetUserNumberMaxValue` -> `GetSettingValue` -> association subquery `SingleOrDefault`), `Sql.ConvertTo<int?>.From(...) ?? 9000`, `PadLeft`, filtered by `searchLexems.Any(l => l == u.Data.UserNumberFormatted)` over a nested anonymous projection. Expects 3 rows. The class lacks `[TestFixture]` (still discovered through `[Test]`).
- `Issue3548Tests` -- `EnumEvaluationInFilter` (PostgreSQL): `[ExpressionMethod] User.InYourOrganization(User callingUser)` with four OR-ed enum/column predicates on a native PG enum (`[PgName]` + `[MapValue]`, `DataType.Enum`, `DbType = "user_type_enum"`). Creates the PG enum type by hand, builds an `NpgsqlDataSource` with `MapEnum<>`, plugs it in via `UseConnectionFactory`, calls `ReloadTypes()`, drops the type in `finally`. Validates that a captured entity argument's enum member is evaluated client-side and bound with the right type.
- `Issue5347Tests` -- `TestContainsMemberTranslator` (PostgreSQL 9.5+): custom `ContainsMemberTranslator : MemberTranslatorBase` registered via `DataOptions.UseMemberTranslator`, translating `string.Contains(string[, StringComparison])` to a cast-to-text `LIKE` with surrounding wildcards (plus `LOWER` for the ignore-case comparisons) on a `jsonb` (`DataType.BinaryJson`) column. Pins that a user translator takes precedence over the built-in predicate path (the built-in LIKE failed with `like_escape(jsonb, ...)`). Uses `ITranslationContext.ExpressionFactory` (`Cast`, `ToLower`, `Expression`, `LikePredicate`, `SearchCondition`) and `CreatePlaceholder`.
- `Issue5505Tests` -- `UpdateWithServerSideOnlyAndValueConverter` (PostgreSQL 9.5+): `Set(x => x.Data, x => JsonbSet(x.Data, "Updated", "true")).Update()` on a column with a `ValueConverterAttribute` (`JsonData?` to string, `handlesNulls: true`). Regression: the update builder wrapped the `ServerSideOnly` function result with the converter ToProvider expression and failed translation.
- `Issue693Tests` -- `Issue693Test` (`DataSources(false)`, all providers): nullable enum `Test?` stored as string via three `ms.SetConverter` registrations (`Test?` to string, `Test?` to `DataParameter`, string to `Test?`), identity entity `Entity533` over the `Person` table, `InsertWithInt32Identity` (ClickHouse uses explicit ids), `RestoreBaseTables`. Asserts null and non-null round trip. YDB gated by `[ActiveIssue(5594)]` (null parameter needs an explicit YdbDbType).
- `Issue5336Tests` -- `DynamicCreatedQueryFromPks`, `FixedQuery`, `GetExistingDtoCall`, `GetExistingAsyncCall` (SQLite, SQL Server 2008+): composite-PK predicate built dynamically with `Expression.MakeMemberAccess` from `EntityDescriptor.Columns`, executed on `IQueryable<BasicDto>` casts of derived `TestDtoWithPks`, sync and `FirstOrDefaultAsync`. Reads the context with `Internals.GetDataContext(queryable)`. Validates comparing members of a derived type through a base-typed queryable cast.

**Caching and compilation**
- `Issue447Tests` -- `TestLinqToDBComplexQuery2`, `TestLinqToDBComplexQueryCache`, `TestLinqToDBComplexQueryCacheWithExposing`, `TestLinqToDBComplexQueryWithParameters` (all `[DataSources]`): 3000-term `Expression.Or` chain predicate. Guards against `StackOverflowException` in expression visitors (it cannot be caught and kills the process) and asserts a second structurally identical predicate is served from the query cache (`GetCacheMissCount()` unchanged), including self-joined exposure (`from r in q from r1 in q`). The last test checks constant folding of `value && true && !false`.
- `Issue5302Tests` -- `ValueIsEqualToAnyCacheTest` (PostgreSQL, `[Values(1, 2)]` iteration, `QueryCacheTest`): `Sql.Ext.PostgreSQL().ValueIsEqualToAny(col, array)` with an array captured per iteration must not miss the cache on the second iteration (array parameter in `Sql.Extension` performance regression). Entity `Warehouse`.
- `Issue822Tests` -- `TestWrongValue`, `TestNullValue` (ClickHouse, `[Values(1, 2)]` dummy parameter): closure locals captured by a subquery helper `GetSource(db, id)` are re-read at execution, so mutating `ID1`/`ID2` after building the query changes the result. A null `int?` captured but unused at execution must not break. Locals instead of fixture fields avoid cross-case sharing under parallel execution.
- `Issue973Tests` -- `Test`, `TestCache` (`[DataSources]`, second is `QueryCacheTest`): file-level public `InExpressionItemBuilder : Sql.IExtensionCallBuilder` and `SqlExtensions.In<T>` (`[Sql.Extension("{field} IN ({values, ', '})", IsPredicate, BuilderType, ServerSideOnly)]` with `[SqlQueryDependent]` values, enumerable and `params` overloads). Compared with native `values.Contains` (via `AreEqual`) and checks equal value lists hit the cache while a different list misses once. The builder creates one `SqlParameter` per value.

**Provider-specific**
- `Issue773Tests` -- `TestAnonymous`, `TestDirect` (SQLite): SQLite FTS4 `MATCH` predicate through `[Sql.Extension("{table_field} match {match}", BuilderType = MatchBuilder, IsPredicate = true)] MatchFts<TEntity>`, whose builder adds a `SqlTable` parameter from the generic argument. Creates and drops the `dataFTS` virtual table itself. Verifies the predicate works before and after projection to an anonymous type, and that prefix match finds `JohnTheRipper` but not `DoeJohn`.
- `Issue3475Tests` -- `NumberLikeTests` (SQLite, ClickHouse): System.Linq.Dynamic.Core string expression `Sql.Like(it.Obj.IntNProp.ToString(), @0)` against the typed lambda equivalent, with a custom `DefaultDynamicLinqCustomTypeProvider` adding `typeof(Sql)`. Gated by `[ActiveIssue("https://github.com/zzzprojects/System.Linq.Dynamic.Core/issues/934")]`: the defect is in System.Linq.Dynamic.Core 1.6.0 (`ParseException` on `ToString` of `Object`), not in linq2db. Mutates the static `ParsingConfig.Default.CustomTypeProvider`.
- `Issue5576Tests` -- `LeftJoinLocalClassWithDecimalArithmetic` (`DataSources(AllAccess, DB2, AllInformix)`): three-stage projection (LEFT JOIN of a table to `counts.AsQueryable()`, decimal-rate `Select`, re-mapping `Select`) previously emitted a spurious whole-object `[item]` column in the `VALUES` clause (`InvalidCastException` converting to Decimal). The element must be a class (an unmapped struct takes a scalar path). `[ActiveIssue(5611, Configuration = AllSQLite)]` for SQLite integer decimal division. Guid PK added so YDB accepts the table. Uses `TestData.Guid1..3`.

**Long-running guard**
- `VeryLongRunningTest.cs` -- namespace `Tests.UserTests.VeryLongRunning`. 15 temp-table entity classes (`#tbl0101` to `#tbl1515`) with `[ColumnAlias]` enum properties, `MapValue` enums and interfaces `IInterface1`/`IInterface3`, plus `VeryLongRunningTestExtensions` with `[ExpressionMethod]` query-returning extensions (`Extension1..10`, bi-temporal `Extension7(date)` = valid-from/valid-to filter, `ExprCache.Run` compile cache) and `[Sql.Expression("TRY_CAST(...)")] TryCastToDecimal`. Fixture `Tests` (SQL Server 2012+): `Test` runs `TestImpl` on `Task.Run` and fails if it does not finish within 30 seconds, i.e. a query-build time guard against exponential expansion. `DebugTest` is `[Explicit]`. `TestImpl` drives `Update1..Update4`: temp tables from queries with fluent column options (`IsNullable`, `HasLength`, `HasPrecision`), `AsSubQuery()`, `AsSqlServer().OptionRecompile()`, `Insert(tmp8, ...)` from a join and `Update(selector, setter)` from a join. Pins SQL Server INSERT-SELECT and UPDATE-FROM builder performance with deeply nested expression-method trees.

## Cross-area validation map

| Production area | Primary test subdirs |
|---|---|
| EXPR-TRANS | Linq/ (all), Exceptions/, UserTests/ (query shape regressions), OrmBattle/, ThirdParty/ |
| SQL-PROVIDER | Linq/ (SQL generation), Extensions/, Update/ |
| SQL-AST | AST/, Linq/InternalsTests.cs, Exceptions/CommonTests.cs, Exceptions/StackUseTests.cs, Infrastructure/NullabilityContextTests.cs |
| PROV-SQLSERVER | DataProvider/SqlServerTests.cs, DataProvider/SqlServerTypesTests.cs, DataProvider/SqlServerVectorTypeTests.cs, DataProvider/Types/SqlServerTypeTests.cs, Extensions/SqlServerTests.cs, SchemaProvider/SqlServerTests.cs |
| PROV-ORACLE | DataProvider/OracleTests.cs, Extensions/OracleTests.cs, TypeMapping/OracleWrappingTests.cs, Update/MultiInsertTests.cs |
| PROV-POSTGRES | DataProvider/PostgreSQLTests.cs, DataProvider/PostgreSQLArrayTests.cs, DataProvider/PostgreSQLExtensionsTests.cs, DataProvider/Types/PostgreSQLTypeTests.cs, Extensions/PostgreSQLTests.cs, SchemaProvider/PostgreSQLSchemaProviderTests.cs |
| PROV-MYSQL | DataProvider/MySqlTests.cs, DataProvider/Types/MySqlTypeTests.cs, Extensions/MySqlTests.cs |
| PROV-SQLITE | DataProvider/SQLiteTests.cs, DataProvider/SQLiteParameterTests.cs, Extensions/SQLiteTests.cs |
| PROV-DB2 | DataProvider/DB2Tests.cs |
| PROV-FIREBIRD | DataProvider/FirebirdTests.cs |
| PROV-SAPHANA | DataProvider/SapHanaTests.cs, DataProvider/Types/SapHanaTypeTests.cs |
| PROV-SYBASE | DataProvider/SybaseTests.cs |
| PROV-INFORMIX | DataProvider/InformixTests.cs |
| PROV-CLICKHOUSE | Extensions/ClickHouseTests.cs, DataProvider/Types/ClickHouseTypeTests.cs |
| PROV-ACCESS | DataProvider/AccessTests.cs, DataProvider/AccessProceduresTests.cs |
| PROV-YDB | DataProvider/YdbTests.cs, DataProvider/Types/YdbTypeTests.cs, DataProvider/YdbRetryPolicyTests.cs *(new)*, DataProvider/YdbTransientExceptionDetectorTests.cs *(new)*, Extensions/YdbTests.cs *(new)* |
| PROV-DUCKDB | DataProvider/Types/DuckDBTypeTests.cs, Linq/ConflictActionTests.cs, Update/BulkCopyTests.cs, Linq/DateTimeFunctionsTests.cs, Linq/DateTimeOffsetTests.cs, plus DuckDB entries in ~30 other Linq/ and Update/ fixtures |
| METADATA | Mapping/, Metadata/ |
| INTERCEPTORS | Data/InterceptorsTests.cs |
| SCAFFOLD | SchemaProvider/, Scaffold/ |
| IN-TREE-TOOLS | Tools/, Scaffold/ |
| INTERNAL-API | Common/, Infrastructure/, Reflection/, Samples/, Data/DataConnectionTests.cs |
| REMOTE-CLIENT | Linq/RemoteContextTests.cs |
| TESTS-INFRA (runner self-tests) | Infrastructure/ActiveIssueTests.cs, Infrastructure/BaselinesManagerTests.cs, Infrastructure/ParallelExecutionTests.cs, Infrastructure/TestProgressStateTests.cs *(all new)* |
## Files (Tier 1 / Tier 2)

**Tier 1: 4/4**

| File | Role |
|---|---|
| Tests/Linq/TestsInitialization.cs | Assembly [SetUpFixture] -- provider registration, metrics, ClickHouse defaults, Linux DB2 native library resolver (issue #5538). **(updated, delta 2026-10-09)** also installs the ResourceLaneDispatcher (per-provider parallel lanes), query-cache cap, in-memory SQLite/DuckDB keep-alives and Access keep-alive connections |
| Tests/Linq/TestRetryPolicy.cs | No-op IRetryPolicy implementation used in tests |
| Tests/Linq/ExpectedExceptionAttribute.cs | NUnit IWrapTestMethod that replaces removed ExpectedExceptionAttribute |
| Tests/Linq/YdbToDoAttributes.cs | **DELETED this delta** (sha b3340aa9d -> 36ee4f82f). Formerly held four Yandex DB-specific ThrowsForProvider attribute subclasses; the last one (YdbMemberNotFoundAttribute) was removed the prior delta and the remaining four now have zero usages, so the whole file was deleted. Retained here at 4/4 per the delta-mode never-regress rule -- see UNCLASSIFIED-FILE block; kb-areas.md needs a human update to drop this Tier-1 entry (no replacement file). |

**Tier 2: 630/692 sampled** (see DEFERRED-COVERAGE fence for the 30 new files not individually read this delta; the pre-existing deferred queue is tracked separately in state/deferred-coverage.json)

Representative reads (prior run): Linq/CteTests.cs, Linq/AnalyticTests.cs, Linq/EagerLoadingTests.cs, Linq/WindowFunctionsTests.cs, Linq/SubQueryTests.cs, Linq/FullTextTests.SqlServer.cs, Linq/ParameterTests.cs, Update/MergeTests.cs, Update/BulkCopyTests.cs, Update/UpdateFromTests.cs, DataProvider/SqlServerTests.cs, DataProvider/PostgreSQLTests.cs, DataProvider/OracleTests.cs, Extensions/QueryHintsTests.cs, Extensions/SqlServerTests.cs, Data/InterceptorsTests.cs, Data/DataConnectionTests.cs, Exceptions/CommonTests.cs, Infrastructure/ActiveIssueConfigurationTests.cs, Infrastructure/AnnotatableTests.cs, Mapping/FluentMappingTests.cs, Microsoft/MicrosoftODataTests.cs, OrmBattle/OrmBattleTests.cs, ThirdParty/LinqKitTests.cs, UserTests/Issue2296Tests.cs, Linq/JoinTests.cs, Linq/GroupByTests.cs, Linq/AssociationTests.cs, Linq/InheritanceTests.cs, DataProvider/MySqlTests.cs, DataProvider/SQLiteTests.cs, DataProvider/FirebirdTests.cs, DataProvider/SapHanaTests.cs, DataProvider/SybaseTests.cs, Update/InsertTests.cs, Update/DeleteTests.cs, Scaffold/NameGenerationTests.cs, TypeMapping/OracleWrappingTests.cs, Infrastructure/DataOptionsTests.cs.

Delta reads (this run, 2026-10-09): see Coverage block below.

Delta reads (this run, 2026-07-06): see Coverage block below.

Delta reads (this run, 2026-06-15): see Coverage block below.

Delta reads (this run, 2026-06-02): see Coverage block below.

Delta reads (this run, 2026-05-11): DataProvider/Types/DuckDBTypeTests.cs (new, full read), Linq/EnumerableSourceTests.AsQueryable.cs (new, full read), Linq/ConflictActionTests.cs (full read -- PR #5455 update).

Batch 1 reads (2026-05-07): see Coverage block below.

Batch 2 reads (2026-05-07): see Coverage block below.

Batch 3 reads (2026-05-07): see Coverage block below.

Batch 5 reads (2026-05-07): see Coverage block below.

Batch 6 reads (2026-05-07): see Coverage block below.

Batch 7 reads (2026-05-07): see Coverage block below.

Batch 8 reads (2026-05-07): see Coverage block below.
## Inbound / outbound dependencies

**Inbound:**
- TESTS-INFRA -- TestBase, TestConfiguration, CustomTestContext, NUnit fixtures, TestProvName, test model types from Tests.Model (Parent, Child, GrandChild, Person, Northwind). All fixtures in this area inherit TestBase.
- TESTS-MODEL -- POCO entities and mapping configurations (Person, Parent, Child, GrandChild, Northwind.*).

**Outbound (production areas exercised):**
- Nearly all LinqToDB.* namespaces. LinqToDB.Data, LinqToDB.Mapping, LinqToDB.DataProvider.*, LinqToDB.Internal.SqlQuery, LinqToDB.Internal.Linq, LinqToDB.Interceptors, LinqToDB.Tools, LinqToDB.Expressions are all directly imported by fixtures in this area.
- LinqToDB.Tools.Mapper.MapperBuilder (TOOLS area) -- cross-referenced by Tools/Mapper/MapperTests.cs.
- LinqToDB.Tools.EntityServices.IdentityMap (TOOLS area) -- cross-referenced by Tools/EntityServices/IdentityMapTests.cs.
- LinqToDB.Internal.Expressions.Types (dynamic type-mapping) -- cross-referenced by TypeMapping/MappingTests.cs.
- LinqToDB.Internal.Reflection.MemberInfoEqualityComparer -- cross-referenced by Common/MemberInfoEqualityComparerTests.cs (AOT regression, PR #5552).
- LinqToDB.Internal.Common.Tools.IsProviderAssemblyPresent -- cross-referenced by Common/AssemblyAvailabilityTests.cs (issue #5538).
- LinqToDB.Internal.DataProvider.Ydb.YdbRetryPolicy / YdbTransientExceptionDetector -- **(new, this delta)** cross-referenced by DataProvider/YdbRetryPolicyTests.cs, DataProvider/YdbTransientExceptionDetectorTests.cs.
- LinqToDB.LinqExtensions entity-builder Insert/Update overloads (IEntityInsertSpec<T> / IEntityUpdateSpec<T>) and the Upsert<T> overload family -- **(new, this delta)** cross-referenced by Update/EntityInsertTests.cs, Update/EntityUpdateTests.cs, Update/EntityDmlApiParametersValidationTests.cs, Update/UpsertTests.*.cs.
- LinqToDB.Linq.Translation.ITranslationContext / MemberTranslatorBase custom-translator extension points -- cross-referenced by UserTests/Issue5347Tests.cs (custom string.Contains override for jsonb).
- NUnit.ParallelByResource (ResourceLaneDispatcher, DatabaseLaneStrategy) -- **(new, delta 2026-10-09)** third-party runner extension wired in TestsInitialization.cs and probed by Infrastructure/ParallelExecutionTests.cs.
- LinqToDB.CLI QueryValueFormatter -- **(new, delta 2026-10-09)** source-linked into Tests.csproj (non-net462) and exercised by DataProvider/ProviderSpecificReaderValueTests.cs.
- LinqToDB.Concurrency (optimistic-lock refresh) -- cross-referenced by Linq/ConcurrencyRefreshTests.cs. LinqToDB.Scaffold ScaffoldOptions -- cross-referenced by Scaffold/SqlServerDecimalOverflowProtectionTests.cs.
## Known issues / debt

- **(resolved, this delta)** WindowFunctionsTests family (formerly 13 files, now 46) is no longer excluded from compilation -- the prior claim that these files exist on disk with no active test coverage is out of date. The Compile-Remove ItemGroup was deleted from Tests.csproj; see the Delta section above. (Corrected in place; the removal is also called out in an AUDIT-NOTE for this run.)
- OrmBattleTests.cs notes the file is generated from LinqTests.tt (T4). The .tt template is not in this directory; the generated output may be stale relative to the template.
- Provider-specific test files (DataProvider/, Extensions/) duplicate some logic with PROV-* area tests; delineation is: this area tests the *ORM layer* using provider features, while PROV-* areas document the provider-layer internals.
- Common/SettingsReaderTests.cs has class TestSettingsTests in namespace Tests.Tools (not Tests.Common) -- namespace/path mismatch.
- Update/MergeTests.Issues.cs is the root partial file for the MergeTests class (defines [TestFixture]), but it is named Issues rather than a neutral root name -- naming anomaly.
- DataProvider/SqlServerVectorTypeTests.cs requires SqlServerProviderAdapter.GetInstance(..).MappingSchema to be passed explicitly because out-of-box SqlVector<float> serialization is not yet registered by default.
- Linq/BatchTests.cs (in Linq/ subdirectory, not Update/) is wrapped in #if NETFRAMEWORK1 -- this condition is never true (no such symbol is defined), meaning the file is effectively dead code across all builds.
- Linq/CursorPagination.cs contains no [TestFixture] or [Test] attributes and is a utility class (Paginator) -- it contributes no test coverage, only a sample pagination implementation.
- Linq/DataServiceTests.cs is NETFX-only (#if NETFRAMEWORK); exercises System.Data.Services WCF stack that is not available on .NET Core/5+.
- DataProvider/Types/DuckDBTypeTests.cs documents extensive provider bugs inline (negative INTERVAL, UHugeInt range, BigNum read/write, TIME_NS type code 39, backslash-zero/backslash-x1 char parameters). These are DuckDB.NET provider limitations, not linq2db issues.
- Linq/StringTrimTests.cs TrimCharsUnsupported constant covers AllSqlServer2019Minus, SqlCe, AllSybase, AllAccess, AllFirebird, AllMySql57 -- on these providers chars-trim falls back to client-side. SQL shape is validated for CharColumnPaddingMismatch providers via separate assertions.
- YdbToDoAttributes.cs: **(updated, this delta)** the file is now fully deleted (it previously held four ThrowsForProvider subclasses; the fourth, YdbMemberNotFoundAttribute, was removed the prior delta). Zero remaining usages confirmed. This is a Tier-1 anchor-list entry that needs a human kb-areas.md update -- see UNCLASSIFIED-FILE block.
- UserTests/Issue5576Tests.cs: [ActiveIssue(5611, Configuration = TestProvName.AllSQLite)] -- SQLite integer-division causes decimal rate to be computed as integer, producing wrong result. Tracked in issue #5611.
- Linq/QueryCacheEvictionTests.cs (new, this delta) is gated behind #if BUGCHECK -- not compiled or run in normal CI builds; BUGCHECK is a diagnostic-only symbol, so this coverage only exists when a developer builds with that symbol defined.
- UserTests/Issue5625Tests.cs (new, this delta) was only skimmed to its entity definitions this delta -- the actual multi-table nullable-join test method bodies were not read; a future pass should verify the full scenario before citing specific assertions from this file.
- **(delta 2026-10-09)** Tier-1 anchor YdbToDoAttributes.cs remains deleted, kb-areas.md still needs the human update noted earlier.
- **(delta 2026-10-09)** Infrastructure/ActiveIssueConfigurationTests.cs and Infrastructure/ActiveIssueGenericTests.cs were deleted (replaced by ActiveIssueTests.cs). Earlier sections of this file (Representative reads list, Notable-findings entry) still name them as historical entries.
- **(delta 2026-10-09)** About 190 modified fixtures in this delta were not read. The earlier claims in this file about their contents are from prior runs and may be stale.
- **(delta 2026-10-09)** Linq/ConcurrencyRefreshTests.cs, Linq/IntervalTranslationTests.*.cs (6 of 7 partials), Mapping/DurationMappingTests.cs and DataProvider/ProviderSpecificReaderValueTests.cs were only partially read, so test-by-test claims about them are not verified.
- **(coverage-fill 2026-10-10)** Extensions/ClickHouseTests.generated.cs and Extensions/SqlServerTests.generated.cs are T4 output of the sibling .tt files. Edit the .tt, never the .generated.cs. Data/MiniProfilerTests.cs is about 1900 lines and mixes many drivers in one fixture, so provider-specific failures there are easy to misattribute.
## See also

- [TESTS-INFRA INDEX](../TESTS-INFRA/INDEX.md) -- TestBase, TestConfiguration, shared infrastructure.
- [TESTS-MODEL INDEX](../TESTS-MODEL/INDEX.md) -- shared POCO/entity models.
- [EXPR-TRANS INDEX](../EXPR-TRANS/INDEX.md) -- LINQ-to-SQL expression translation, exercised by Linq/.
- [SQL-PROVIDER INDEX](../SQL-PROVIDER/INDEX.md) -- SQL generation layer.
- [INTERCEPTORS INDEX](../INTERCEPTORS/INDEX.md) -- interceptor contracts tested in Data/InterceptorsTests.cs.
- [METADATA INDEX](../METADATA/INDEX.md) -- mapping/schema contracts tested in Mapping/, Metadata/.
<details><summary>Coverage</summary>

**Tier 1: 4/4 read**
- Tests/Linq/TestsInitialization.cs -- read (prior run)
- Tests/Linq/TestRetryPolicy.cs -- read (prior run)
- Tests/Linq/ExpectedExceptionAttribute.cs -- read (prior run)
- Tests/Linq/YdbToDoAttributes.cs -- read (prior run); **DELETED this delta** (sha b3340aa9d -> 36ee4f82f) -- confirmed via git show at the base sha plus a full-tree search for its four class names (zero remaining usages). See UNCLASSIFIED-FILE block.

**Tier 2: 630/692 sampled**

Read (coverage-fill, 2026-10-10):
- Tests/Linq/Common/ConvertTests.cs -- read in full (structure, test inventory, production area) -- see Coverage-fill findings
- Tests/Linq/Common/DefaultValueTests.cs -- read in full (structure, test inventory, production area) -- see Coverage-fill findings
- Tests/Linq/Data/DataConnectionTests.cs -- read in full (structure, test inventory, production area) -- see Coverage-fill findings
- Tests/Linq/Data/MiniProfilerTests.cs -- read in full (structure, test inventory, production area) -- see Coverage-fill findings
- Tests/Linq/Data/RetryPolicyTest.cs -- read in full (structure, test inventory, production area) -- see Coverage-fill findings
- Tests/Linq/Data/TraceTests.cs -- read in full (structure, test inventory, production area) -- see Coverage-fill findings
- Tests/Linq/DataProvider/AccessTests.cs -- read in full (structure, test inventory, production area) -- see Coverage-fill findings
- Tests/Linq/DataProvider/DB2Tests.cs -- read in full (structure, test inventory, production area) -- see Coverage-fill findings
- Tests/Linq/DataProvider/FirebirdTests.cs -- read in full (structure, test inventory, production area) -- see Coverage-fill findings
- Tests/Linq/DataProvider/InformixTests.cs -- read in full (structure, test inventory, production area) -- see Coverage-fill findings
- Tests/Linq/DataProvider/MySqlTests.cs -- read in full (structure, test inventory, production area) -- see Coverage-fill findings
- Tests/Linq/DataProvider/OracleTests.cs -- read in full (structure, test inventory, production area) -- see Coverage-fill findings
- Tests/Linq/DataProvider/PostgreSQLArrayTests.cs -- read in full (structure, test inventory, production area) -- see Coverage-fill findings
- Tests/Linq/DataProvider/PostgreSQLExtensionsTests.cs -- read in full (structure, test inventory, production area) -- see Coverage-fill findings
- Tests/Linq/DataProvider/PostgreSQLTests.cs -- read in full (structure, test inventory, production area) -- see Coverage-fill findings
- Tests/Linq/DataProvider/SapHanaTests.cs -- read in full (structure, test inventory, production area) -- see Coverage-fill findings
- Tests/Linq/DataProvider/SqlCeTests.cs -- read in full (structure, test inventory, production area) -- see Coverage-fill findings
- Tests/Linq/DataProvider/SQLiteTests.cs -- read in full (structure, test inventory, production area) -- see Coverage-fill findings
- Tests/Linq/DataProvider/SqlServerFunctionsTests.cs -- read in full (structure, test inventory, production area) -- see Coverage-fill findings
- Tests/Linq/DataProvider/SqlServerTests.cs -- read in full (structure, test inventory, production area) -- see Coverage-fill findings
- Tests/Linq/DataProvider/SqlServerTypesTests.TVP.cs -- read in full (structure, test inventory, production area) -- see Coverage-fill findings
- Tests/Linq/DataProvider/SqlServerVectorTypeTests.cs -- read in full (structure, test inventory, production area) -- see Coverage-fill findings
- Tests/Linq/DataProvider/Types/ClickHouseTypeTests.cs -- read in full (structure, test inventory, production area) -- see Coverage-fill findings
- Tests/Linq/DataProvider/Types/PostgreSQLTypeTests.cs -- read in full (structure, test inventory, production area) -- see Coverage-fill findings
- Tests/Linq/DataProvider/Types/SapHanaTypeTests.cs -- read in full (structure, test inventory, production area) -- see Coverage-fill findings
- Tests/Linq/DataProvider/Types/SqlServerTypeTests.cs -- read in full (structure, test inventory, production area) -- see Coverage-fill findings
- Tests/Linq/DataProvider/Types/YdbTypeTests.cs -- read in full (structure, test inventory, production area) -- see Coverage-fill findings
- Tests/Linq/DataProvider/UniqueParametersNormalizerTests.cs -- read in full (structure, test inventory, production area) -- see Coverage-fill findings
- Tests/Linq/Exceptions/StackUseTests.cs -- read in full (structure, test inventory, production area) -- see Coverage-fill findings
- Tests/Linq/Extensions/ClickHouseTests.cs -- read in full (structure, test inventory, production area) -- see Coverage-fill findings
- Tests/Linq/Extensions/ClickHouseTests.generated.cs -- read in full (structure, test inventory, production area) -- see Coverage-fill findings
- Tests/Linq/Extensions/ClickHouseTests.tt -- read in full (structure, test inventory, production area) -- see Coverage-fill findings
- Tests/Linq/Extensions/OracleTests.cs -- read in full (structure, test inventory, production area) -- see Coverage-fill findings
- Tests/Linq/Extensions/PostgreSQLTests.cs -- read in full (structure, test inventory, production area) -- see Coverage-fill findings
- Tests/Linq/Extensions/SqlCeTests.cs -- read in full (structure, test inventory, production area) -- see Coverage-fill findings
- Tests/Linq/Extensions/SqlServerTests.cs -- read in full (structure, test inventory, production area) -- see Coverage-fill findings
- Tests/Linq/Extensions/SqlServerTests.generated.cs -- read in full (structure, test inventory, production area) -- see Coverage-fill findings
- Tests/Linq/Extensions/SqlServerTests.tt -- read in full (structure, test inventory, production area) -- see Coverage-fill findings
- Tests/Linq/Extensions/TableIDTests.cs -- read in full (structure, test inventory, production area) -- see Coverage-fill findings
- Tests/Linq/Infrastructure/DataOptionsTests.cs -- read in full (structure, test inventory, production area) -- see Coverage-fill findings

Read (this run -- delta, 2026-10-09):
- Tests/Linq/TestsInitialization.cs -- Tier 1, re-read in full: ResourceLaneDispatcher, query-cache cap, in-memory SQLite/DuckDB and Access keep-alives
- Tests/Linq/Tests.csproj -- diff read: ClickHouse T4 pair, QueryValueFormatter source link
- Tests/Linq/Infrastructure/ActiveIssueTests.cs -- new, first 80 lines: ActiveIssueAttribute.Decide policy tests
- Tests/Linq/Infrastructure/BaselinesManagerTests.cs -- new, full read
- Tests/Linq/Infrastructure/ParallelExecutionTests.cs -- new, first 60 lines
- Tests/Linq/Infrastructure/TestProgressStateTests.cs -- new, first 50 lines
- Tests/Linq/Linq/IntervalTranslationTests.cs -- new, first 70 lines (root of 7-file family)
- Tests/Linq/Linq/ParameterTests.Naming.cs -- new, first 60 lines
- Tests/Linq/Linq/ParameterTests.Reuse.cs -- new, first 60 lines
- Tests/Linq/Linq/ConcurrencyRefreshTests.cs -- new, first 60 lines
- Tests/Linq/Linq/SqlRawSqlTableTests.cs -- new, full read
- Tests/Linq/Linq/WindowFunctionsTests.ConstantOrderBy.cs -- new, first 60 lines
- Tests/Linq/Mapping/DurationMappingTests.cs -- new, first 60 lines
- Tests/Linq/DataProvider/ProviderSpecificReaderValueTests.cs -- new, first 60 lines
- Tests/Linq/Scaffold/SqlServerDecimalOverflowProtectionTests.cs -- new, first 60 lines
- Tests/Linq/UserTests/Issue5683Tests.cs -- new, comment/attribute skim
- Tests/Linq/UserTests/Issue5684Tests.cs -- new, header skim
- Tests/Linq/UserTests/Issue5719Tests.cs -- new, comment/attribute skim
- Tests/Linq/UserTests/Issue5769Tests.cs -- new, comment/attribute skim
- Tests/Linq/UserTests/Issue5916Tests.cs -- new, comment/attribute skim
- Tests/Linq/UserTests/Issue5935Tests.cs -- new, comment/attribute skim
- Tests/Linq/Infrastructure/ActiveIssueConfigurationTests.cs, Tests/Linq/Infrastructure/ActiveIssueGenericTests.cs -- deleted (not read), replaced by ActiveIssueTests.cs
- Tests/Linq/AssemblyInfo.TestProgress.cs -- not in changedFiles this delta, prior --test-progress description stands
- Remaining changed entries (about 230 modified or added files) -- not read, queued in DEFERRED-COVERAGE. Tier 2 numerator counts only the 19 newly read Tier-2 files (the 2 deleted files stay counted so the numerator does not regress), denominator is 667 + 27 added - 2 deleted = 692.

Read (this run -- delta, 2026-07-06):
- Tests/Linq/Tests.csproj -- project file, not a Tier-2 fixture; Compile-Remove block for WindowFunctionsTests family deleted, X86STUBS condition added for Sap.Data.Hana.Net.v8.0 reference
- Tests/Linq/AssemblyInfo.TestProgress.cs -- opt-in switched from LINQ2DB_TEST_PROGRESS env var to --test-progress CLI option
- Tests/Linq/Create/CreateData.cs -- YDB dispatch case switched to context.IsAnyOf(TestProvName.AllYdb)
- Tests/Linq/Common/ConvertTests.cs -- SetExpression/ToStringTest wrap static Convert<T1,T2> mutation in try/finally
- Tests/Linq/Linq/WindowFunctionsTests.cs -- re-read (root, family shared entity WindowFunctionTestEntity); full read
- Tests/Linq/Linq/WindowFunctionsTests.RegrSlope.cs -- new; full read; REGR_SLOPE gating pattern
- Tests/Linq/Linq/WindowFunctionsTests.Corr.cs -- new; full read; CORR gating pattern
- Tests/Linq/Linq/WindowFunctionsTests.HypotheticalSet.cs -- new; full read; RANK/DENSE_RANK/PERCENT_RANK WITHIN GROUP
- Tests/Linq/Linq/WindowFunctionsTests.Combinations.cs -- new; full read; Filter()/RowsBetween/RangeBetween combination matrix
- Tests/Linq/Linq/WindowFunctionsTests.Average.cs -- diffstat-skimmed; revised for live execution now that the family compiles
- Tests/Linq/Linq/WindowFunctionsTests.Cume.cs -- diffstat-skimmed; revised for live execution
- Tests/Linq/Linq/WindowFunctionsTests.DenseRank.cs -- diffstat-skimmed; revised for live execution
- Tests/Linq/Linq/WindowFunctionsTests.Frame.cs -- diffstat-skimmed (largest single-file diff, +261/-163); AggregateWithFilter/AggregateWithFrame/CountArgWithFrame/AggregateWithFrameExclude added
- Tests/Linq/Linq/WindowFunctionsTests.Max.cs -- diffstat-skimmed; revised for live execution
- Tests/Linq/Linq/WindowFunctionsTests.Min.cs -- diffstat-skimmed; revised for live execution
- Tests/Linq/Linq/WindowFunctionsTests.NTile.cs -- diffstat-skimmed; revised for live execution
- Tests/Linq/Linq/WindowFunctionsTests.PercentRank.cs -- diffstat-skimmed; revised for live execution
- Tests/Linq/Linq/WindowFunctionsTests.PercentileCont.cs -- diffstat-skimmed; revised for live execution
- Tests/Linq/Linq/WindowFunctionsTests.Rank.cs -- diffstat-skimmed; revised for live execution
- Tests/Linq/Linq/WindowFunctionsTests.RowNumber.cs -- diffstat-skimmed; revised for live execution
- Tests/Linq/Linq/WindowFunctionsTests.Sum.cs -- diffstat-skimmed; revised for live execution
- Tests/Linq/Linq/EagerLoadingStrategyKeyedQueryTests.cs -- new; full read; Company/Department/Employee KeyedQuery-strategy hierarchy
- Tests/Linq/Linq/EagerLoadingStrategyUnionTests.cs -- new; full read; 4-level hierarchy with EmployeeTask
- Tests/Linq/Linq/EagerLoadingWideKeyTests.cs -- new; full read; 15-member composite key, Rest-nested ValueTuple
- Tests/Linq/Linq/ImplicitCollectionLoadingTests.cs -- new; full read; UseImplicitCollectionLoading(Throw)
- Tests/Linq/Linq/PreferClientCalculationTests.cs -- new; full read; UsePreferClientCalculation + PreferServerSide/ServerSideOnly interaction
- Tests/Linq/Linq/QueryCacheEvictionTests.cs -- new; full read; #if BUGCHECK-gated QueryCache eviction unit tests
- Tests/Linq/Linq/TphInheritanceTests.cs -- new; full read; deep TPH discriminator chain
- Tests/Linq/Mapping/ValueConverterColumnDbTypeTests.cs -- new; full read; converter-provider-type DB-type resolution
- Tests/Linq/Update/EntityDmlApiParametersValidationTests.cs -- new; full read; null-argument guards for entity-builder Insert/Update
- Tests/Linq/Update/EntityInsertTests.cs -- new; full read; entity-builder Insert<T> overload
- Tests/Linq/Update/EntityUpdateTests.cs -- new; full read; entity-builder Update<T> overload
- Tests/Linq/Update/UpsertTests.Enumerable.cs -- new; full read; Upsert<T> over IEnumerable<T>
- Tests/Linq/Update/UpsertTests.Queryable.cs -- new; full read; Upsert<T> over IQueryable<T>
- Tests/Linq/Update/UpsertTests.Single.cs -- new; full read; Upsert<T> single-entity overload
- Tests/Linq/Update/MergeTests.Operations.Associations.cs -- diffstat-skimmed (390-line diff); PrepareIdentityData now returns seeded rows instead of writing a shared static field
- Tests/Linq/Update/MergeTests.Operations.IdentityInsert.cs -- diffstat-skimmed (150-line diff); same PrepareIdentityData refactor
- Tests/Linq/Update/MergeTests.Types.cs -- diffstat-skimmed (2-line diff); trivial
- Tests/Linq/UserTests/Issue5347Tests.cs -- new; full read; custom MemberTranslatorBase for jsonb-safe string.Contains
- Tests/Linq/UserTests/Issue5575Tests.cs -- new; full read; unbound nullable member plus HasValue projection
- Tests/Linq/UserTests/Issue5616Tests.cs -- new; full read; UNION ALL aggregate/constant mismatch plus custom Sql.Extension aggregate
- Tests/Linq/UserTests/Issue5625Tests.cs -- new; partial read (first 50 lines, entity definitions only)
- Tests/Linq/UserTests/Issue5666Tests.cs -- new; full read; nullable-enum column plus nullable-FK association
- Tests/Linq/DataProvider/YdbRetryPolicyTests.cs -- new; full read; YdbRetryPolicy immediate/jitter retry-code coverage
- Tests/Linq/DataProvider/YdbTransientExceptionDetectorTests.cs -- new; full read; YdbTransientExceptionDetector unit tests
- Tests/Linq/Extensions/YdbTests.cs -- new; full read; YdbHints.Unique/Distinct plus AsYdb()
- Tests/Linq/DataProvider/YdbTests.cs -- diffstat-skimmed (102-line diff); [YdbNotImplementedYet] removed from two schema-provider tests, Ctx constant replaced with TestProvName.AllYdb
- Tests/Linq/DataProvider/Types/YdbTypeTests.cs -- diffstat-skimmed (6-line diff); minor
- Tests/Linq/DataProvider/DB2Tests.cs -- diffstat-skimmed (79-line diff); three new DECFLOAT special-value tests (issue #5663)
- Tests/Linq/Infrastructure/DataOptionsTests.cs -- diffstat-skimmed (28-line diff); WithDefaultEagerLoadingStrategyTest, WithImplicitCollectionLoadingTest, OptimizeForSequentialAccessConfigurationIDTest added; TestProviderAutoDetect gained a Ydb case

Other files changed this delta (not individually examined -- ~148 modified files, mechanical/ripple changes consistent with the categories below; the 30 new-but-unsampled files are listed in the DEFERRED-COVERAGE fence, not here):
- 29 further new WindowFunctionsTests.*.cs partials (Count, CovarPop, CovarSamp, Equality, Filter, FirstValue, FrameExclusion, Keep, Lag, LastValue, Lead, Median, NthValue, PercentileDisc, RatioToReport, RegrAvgX, RegrAvgY, RegrCount, RegrIntercept, RegrR2, RegrSXX, RegrSXY, RegrSYY, StdDev, StdDevPop, StdDevSamp, VarPop, VarSamp, Variance) -- same shape as the 4 sampled siblings.
- Update/UpsertTests.ApiParametersValidation.cs -- same shape as its 3 sampled siblings plus EntityDmlApiParametersValidationTests.cs.
- ~35 Linq/ and Update/ and UserTests/ fixtures with minor DuckDB/YDB provider-set additions or gating-attribute swaps, continuing the pattern from prior deltas (e.g. Linq/AggregationNullabilityTests.cs, Linq/AnalyticTests.cs, Linq/AssociationTests.cs, Linq/AsyncTests.cs, Linq/CompileTests.cs, Linq/ComplexTests.cs, Linq/ConcatUnionTests.cs, Linq/ConvertTests.cs, Linq/CountTests.cs, Linq/CteTests.cs, Linq/DataContextTests.cs, Linq/DataTypesTests.cs, Linq/DateTimeFunctionsTests.cs, Linq/DefaultIfEmptyTests.cs, Linq/DistinctByMethodTests.cs, Linq/DistinctTests.cs, Linq/DynamicColumnsTests.cs, Linq/EnumerableInQuery.cs, Linq/EnumerableSourceTests.cs, Linq/ExpressionsTests.cs, Linq/FSharpTests.cs, Linq/FromSqlTests.cs, Linq/FunctionTests.cs, Linq/GroupByTests.cs, Linq/IdentifierTests.cs, Linq/InSubqueryTests.cs, Linq/InheritanceTests.cs, Linq/IssueTests.cs, Linq/JoinTests.cs, Linq/MappingTests.cs, Linq/MathFunctionTests.cs, Linq/OrderByDistinctTests.cs, Linq/OrderByTests.cs, Linq/ParameterTests.cs, Linq/PredicateTests.cs, Linq/QueryFilterTests.cs, Linq/QueryGenerationTests.cs, Linq/RightJoinMethodTests.cs, Linq/SelectQueryTests.cs, Linq/SelectTests.cs, Linq/SetOperatorComplexTests.cs, Linq/SetTests.cs, Linq/SqlExtensionTests.cs, Linq/SqlExtensionsTests.cs, Linq/SqlRowTests.cs, Linq/StringFunctionTests.cs, Linq/StringFunctionsTests.cs, Linq/StringJoinTests.cs, Linq/StringConcatTests.cs, Linq/SubQueryTests.cs, Linq/TableOptionsTests.cs, Linq/TakeSkipTests.cs, Linq/TypesTests.cs, Linq/WhereTests.cs.
- Update/ fixtures with likely YDB/DuckDB provider-set or gating-attribute additions: BulkCopyTests.cs, CreateTableTests.cs, CreateTempTableTests.cs, DeleteTests.cs, DeleteWithOutputTests.cs, DropTableTests.cs, DynamicColumnsTests.cs, InsertTests.cs, InsertWithOutputTests.cs, TruncateTableTests.cs, UpdateFromTests.Row.cs, UpdateFromTests.cs, UpdateTests.cs, UpdateWithOutputTests.cs.
- Data/DataConnectionTests.cs, Data/TransactionTests.cs -- minor updates.
- DataProvider/MySqlTests.cs, DataProvider/PostgreSQLTests.cs -- minor updates beyond the NodaTime region already documented.
- Exceptions/AggregationTests.cs -- minor update (4-line diff).
- Mapping/FluentMappingExpressionMethodTests.cs, Mapping/MappingSchemaTests.cs -- minor updates.
- Microsoft/MicrosoftODataTests.cs, Samples/ConcurrencyCheckTests.cs, SchemaProvider/PostgreSQLSchemaProviderTests.cs, SchemaProvider/SchemaProviderTests.cs -- minor updates.
- UserTests/ regression files with minor updates (likely provider-set or assertion refinements): ConverterInsertTests.cs, GroupBySubqueryTests.cs, Issue0082Tests.cs, Issue1238Tests.cs, Issue1305Tests.cs, Issue1549Tests.cs, Issue1556Tests.cs, Issue2461Tests.cs, Issue2468Tests.cs, Issue2619Tests.cs, Issue2665Tests.cs, Issue269Tests.cs, Issue2832Tests.cs, Issue3186Tests.cs, Issue3432Tests.cs, Issue4336Tests.cs, Issue5152Tests.cs, Issue531Tests.cs, Issue5340Tests.cs, Issue681Tests.cs, Issue693Tests.cs, Issue708Tests.cs, Issue792Tests.cs, Issue822Tests.cs, Issue928Tests.cs, SelectManyUpdateTests.cs.

Read (this run -- delta, 2026-06-15):
- Tests/Linq/TestsInitialization.cs -- re-read (Tier 1); Linux DB2 SetDllImportResolver added (issue #5538)
- Tests/Linq/YdbToDoAttributes.cs -- re-read (Tier 1); YdbMemberNotFoundAttribute class removed
- Tests/Linq/AssemblyInfo.TestProgress.cs -- new file; full read; [assembly: TestProgressReporter] opt-in progress heartbeat
- Tests/Linq/Common/AssemblyAvailabilityTests.cs -- new file; full read; IsProviderAssemblyPresent unit tests (issue #5538)
- Tests/Linq/Update/MergeTests.ComplexProperty.cs -- new file; full read; nested-member column mapping in MERGE (PR #5543)
- Tests/Linq/UserTests/Issue5576Tests.cs -- new file; full read; three-stage LEFT JOIN with decimal arithmetic regression (issue #5576)
- Tests/Linq/Infrastructure/DataOptionsTests.cs -- skimmed; WithDefaultNullsPositionTest and ConfigurationSqlDefaultNullsPositionTest added
- Tests/Linq/DataProvider/OracleTests.cs -- skimmed; TestDateTimeSQL updated for DateTimeOffset local-time+offset; TestDateTimeOffsetToTimestampLiteral added
- Tests/Linq/DataProvider/PostgreSQLTests.cs -- skimmed; Issue 5549 region added (NodaTime.Instant COALESCE via ??)
- Tests/Linq/Update/BulkCopyTests.cs -- skimmed; DateOnlyTable.Date PrimaryKey/Identity change (YDB BulkUpsert)
- Tests/Linq/Linq/StringConcatTests.cs -- skimmed; Concat_Sybase_NullGuardOnlyForNullableOperands added; StringConcatNullEntity.ID [PrimaryKey] added- Tests/Linq/Linq/AllAnyTests.cs -- skimmed; [YdbMemberNotFound] replaced with [ThrowsRequiresCorrelatedSubquery(simple: true)]
- Tests/Linq/Linq/AssociationTests.cs -- skimmed; [YdbMemberNotFound] replaced with [ThrowsRequiresCorrelatedSubquery(simple: true)]
- Tests/Linq/Linq/CommonTests.cs -- skimmed; [YdbMemberNotFound] replaced
- Tests/Linq/Linq/CteTests.cs -- skimmed; [YdbMemberNotFound] replaced
- Tests/Linq/Linq/ConcatUnionTests.cs -- skimmed; [YdbMemberNotFound] replaced
- Tests/Linq/Linq/ContainsTests.cs -- skimmed; [YdbMemberNotFound] replaced
- Tests/Linq/Linq/ConvertExpressionTests.cs -- skimmed; [YdbMemberNotFound] replaced
- Tests/Linq/Linq/ConvertTests.cs -- skimmed; [YdbMemberNotFound] replaced
- Tests/Linq/Linq/CountByMethodTests.cs -- skimmed; [YdbMemberNotFound] replaced
- Tests/Linq/Linq/DistinctByMethodTests.cs -- skimmed; [YdbMemberNotFound] replaced
- Tests/Linq/Linq/DistinctTests.cs -- skimmed; [YdbMemberNotFound] replaced
- Tests/Linq/Linq/EnumMappingTests.cs -- skimmed; [YdbMemberNotFound] replaced
- Tests/Linq/Linq/EnumerableSourceTests.cs -- skimmed; [YdbMemberNotFound] replaced
- Tests/Linq/Linq/ExceptByMethodTests.cs -- skimmed; [YdbMemberNotFound] replaced
- Tests/Linq/Linq/ExpressionsTests.cs -- skimmed; [YdbMemberNotFound] replaced
- Tests/Linq/Linq/GuidTests.cs -- skimmed; [YdbMemberNotFound] replaced
- Tests/Linq/Linq/IndexMethodTests.cs -- skimmed; [YdbMemberNotFound] replaced
- Tests/Linq/Linq/IntersectByMethodTests.cs -- skimmed; [YdbMemberNotFound] replaced
- Tests/Linq/Linq/IssueTests.cs -- skimmed; [YdbMemberNotFound] replaced
- Tests/Linq/Linq/JoinTests.cs -- skimmed; [YdbMemberNotFound] replaced
- Tests/Linq/Linq/MinByMaxByMethodTests.cs -- skimmed; [YdbMemberNotFound] replaced
- Tests/Linq/Linq/OrderByTests.cs -- skimmed; [YdbMemberNotFound] replaced
- Tests/Linq/Linq/ParameterTests.cs -- skimmed; [YdbMemberNotFound] replaced
- Tests/Linq/Linq/PredicateTests.cs -- skimmed; [YdbMemberNotFound] replaced
- Tests/Linq/Linq/ProjectionTests.cs -- skimmed; [YdbMemberNotFound] replaced
- Tests/Linq/Linq/SelectTests.cs -- skimmed; [YdbMemberNotFound] replaced
- Tests/Linq/Linq/SetOperatorComplexTests.cs -- skimmed; [YdbMemberNotFound] replaced
- Tests/Linq/Linq/SetOperatorTests.cs -- skimmed; [YdbMemberNotFound] replaced
- Tests/Linq/Linq/SetTests.cs -- skimmed; [YdbMemberNotFound] replaced
- Tests/Linq/Linq/SqlRowTests.cs -- skimmed; [YdbMemberNotFound] replaced
- Tests/Linq/Linq/StringFunctionsTests.cs -- skimmed; [YdbMemberNotFound] replaced
- Tests/Linq/Linq/SubQueryTests.cs -- skimmed; [YdbMemberNotFound] replaced
- Tests/Linq/Linq/UnionByMethodTests.cs -- skimmed; [YdbMemberNotFound] replaced
- Tests/Linq/Linq/WhereTests.cs -- skimmed; [YdbMemberNotFound] replaced
- Tests/Linq/Linq/CharTypesTests.cs -- skimmed; [YdbMemberNotFound] replaced
- Tests/Linq/Update/DeleteTests.cs -- skimmed; [YdbMemberNotFound] replaced (Delete3, Delete4, AlterDelete, DeleteMany1)
- Tests/Linq/Update/UpdateTests.cs -- skimmed; [YdbMemberNotFound] replaced (UpdateAssociation1Old through UpdateAssociation3, 6+ occurrences)
- Tests/Linq/Update/UpdateWithOutputTests.cs -- skimmed; [YdbMemberNotFound] replaced (Issue4193Test)
- Tests/Linq/UserTests/Issue269Tests.cs -- skimmed; [YdbMemberNotFound] replaced; ProviderName.Ydb excluded from TestSkipDistinct/TestDistinctSkip/TestSkip
- Tests/Linq/UserTests/Issue825Tests.cs -- skimmed; [YdbMemberNotFound] replaced
- Tests/Linq/UserTests/Issue2619Tests.cs -- skimmed; [YdbMemberNotFound] replaced
- Tests/Linq/UserTests/Issue2816Tests.cs -- skimmed; [YdbMemberNotFound] replaced
- Tests/Linq/UserTests/Issue3402Tests.cs -- skimmed; [YdbMemberNotFound] replaced
- Tests/Linq/UserTests/SelectManyDeleteTests.cs -- skimmed; [YdbMemberNotFound] replaced
- Tests/Linq/UserTests/UnnecessaryInnerJoinTests.cs -- skimmed; [YdbMemberNotFound] replaced
Read (delta run, 2026-06-02):
- Tests/Linq/Linq/StringConcatTests.cs -- new file; full read; SqlConcatExpression / string.Concat / binary-add / aggregate-concat / partial-translation coverage (PR #5504)
- Tests/Linq/Linq/StringTrimTests.cs -- new file; full read; TrimStart/TrimEnd with char sets, cache semantics, provider-specific SQL shape (PR #5515)
- Tests/Linq/Linq/AggregationNullabilityTests.cs -- new file; full read; subquery-aggregate COALESCE wrapping for non-nullable Sum; nullable Sum/Min/Max/Avg must not wrap (PR #5557)
- Tests/Linq/Common/MemberInfoEqualityComparerTests.cs -- new file; full read; AOT RuntimeSyntheticConstructorInfo MetadataToken guard (PR #5552 / issue #5551)
- Tests/Linq/UserTests/Issue5125Tests.cs -- new file; full read; IExpressionPreprocessor NULLS FIRST subquery placement regression (issue #5125)
- Tests/Linq/UserTests/Issue5154Tests.cs -- new file; full read; SqlQueryDependentParams + multi-level eager-load ToSqlQuery/ToArray ordering (issue #5154)
- Tests/Linq/UserTests/Issue5505Tests.cs -- new file; full read; ServerSideOnly function on ValueConverter column UPDATE (issue #5505)
- Tests/Linq/Linq/AggregationTests.cs -- skimmed; added SumByAssociationSubquery, ClosureList* aggregate tests
- Tests/Linq/Linq/StringFunctionsTests.cs -- skimmed; added Issue5173_ParameterLocation
- Tests/Linq/Data/MiniProfilerTests.cs -- skimmed; provider additions or MiniProfiler adapter refinements; no new fixture structures
- Tests/Linq/DataProvider/SqlServerTests.cs -- skimmed; SQL Server-specific additions; no new fixture structures
- Tests/Linq/Update/MergeTests.ApiParametersValidation.cs -- skimmed; additional guard / async cancellation tests
- Tests/Linq/Update/UpdateFromTests.Row.cs -- skimmed; row-constructor update additions
- Tests/Linq/UserTests/Issue781Tests.cs -- skimmed; minor provider additions only

Read (delta run, 2026-05-11):
- Tests/Linq/DataProvider/Types/DuckDBTypeTests.cs -- new file; full read; DuckDB type matrix
- Tests/Linq/Linq/EnumerableSourceTests.AsQueryable.cs -- new file; full read; configured AsQueryable overload tests
- Tests/Linq/Linq/ConflictActionTests.cs -- full read; PR #5455 BulkCopy ConflictAction.Ignore

Sampled (prior runs, 2026-05-07): 521 files across all subdirectories -- see batch 1-8 entries above.

Skipped / deferred Tier-2 entries carry over from prior deferred-coverage state. The remaining un-visited Tier-2 files remain in the deferred queue (not enumerated here; maintained in state/deferred-coverage.json).

**Tier 3: 0 files** (no generated bin/obj under Tests/Linq/ in scope)


Read (coverage-fill run 2026-10-10, batch 2 -- Linq/ root A..Ev, 40 files, class shape and test-method enumeration):
- Tests/Linq/Linq/AbstractionTests.cs -- taxonomy recorded under Coverage-fill findings (Linq/ root, second batch)
- Tests/Linq/Linq/AggregationTests.cs -- taxonomy recorded under Coverage-fill findings (Linq/ root, second batch)
- Tests/Linq/Linq/AK107Tests.cs -- taxonomy recorded under Coverage-fill findings (Linq/ root, second batch)
- Tests/Linq/Linq/AllAnyTests.cs -- taxonomy recorded under Coverage-fill findings (Linq/ root, second batch)
- Tests/Linq/Linq/AnalyticTests.cs -- taxonomy recorded under Coverage-fill findings (Linq/ root, second batch)
- Tests/Linq/Linq/ArrayTests.cs -- taxonomy recorded under Coverage-fill findings (Linq/ root, second batch)
- Tests/Linq/Linq/AssociationTests.cs -- taxonomy recorded under Coverage-fill findings (Linq/ root, second batch)
- Tests/Linq/Linq/AsyncTests.cs -- taxonomy recorded under Coverage-fill findings (Linq/ root, second batch)
- Tests/Linq/Linq/BooleanTests.cs -- taxonomy recorded under Coverage-fill findings (Linq/ root, second batch)
- Tests/Linq/Linq/CachingTests.cs -- taxonomy recorded under Coverage-fill findings (Linq/ root, second batch)
- Tests/Linq/Linq/CalculatedColumnTests.cs -- taxonomy recorded under Coverage-fill findings (Linq/ root, second batch)
- Tests/Linq/Linq/CommonTests.cs -- taxonomy recorded under Coverage-fill findings (Linq/ root, second batch)
- Tests/Linq/Linq/CompileTests.cs -- taxonomy recorded under Coverage-fill findings (Linq/ root, second batch)
- Tests/Linq/Linq/CompileTestsAsync.cs -- taxonomy recorded under Coverage-fill findings (Linq/ root, second batch)
- Tests/Linq/Linq/ComplexTests.cs -- taxonomy recorded under Coverage-fill findings (Linq/ root, second batch)
- Tests/Linq/Linq/ComplexTests2.cs -- taxonomy recorded under Coverage-fill findings (Linq/ root, second batch)
- Tests/Linq/Linq/ConcatUnionTests.cs -- taxonomy recorded under Coverage-fill findings (Linq/ root, second batch)
- Tests/Linq/Linq/ConcurrencyTests.cs -- taxonomy recorded under Coverage-fill findings (Linq/ root, second batch)
- Tests/Linq/Linq/ConflictActionTests.cs -- taxonomy recorded under Coverage-fill findings (Linq/ root, second batch)
- Tests/Linq/Linq/ConstantTests.cs -- taxonomy recorded under Coverage-fill findings (Linq/ root, second batch)
- Tests/Linq/Linq/ContainsTests.cs -- taxonomy recorded under Coverage-fill findings (Linq/ root, second batch)
- Tests/Linq/Linq/ConvertExpressionTests.cs -- taxonomy recorded under Coverage-fill findings (Linq/ root, second batch)
- Tests/Linq/Linq/ConvertTests.cs -- taxonomy recorded under Coverage-fill findings (Linq/ root, second batch)
- Tests/Linq/Linq/CountTests.cs -- taxonomy recorded under Coverage-fill findings (Linq/ root, second batch)
- Tests/Linq/Linq/CteMaterializedTests.cs -- taxonomy recorded under Coverage-fill findings (Linq/ root, second batch)
- Tests/Linq/Linq/CteTests.cs -- taxonomy recorded under Coverage-fill findings (Linq/ root, second batch)
- Tests/Linq/Linq/DataContextTests.cs -- taxonomy recorded under Coverage-fill findings (Linq/ root, second batch)
- Tests/Linq/Linq/DataTypesTests.cs -- taxonomy recorded under Coverage-fill findings (Linq/ root, second batch)
- Tests/Linq/Linq/DateTimeFunctionsTests.cs -- taxonomy recorded under Coverage-fill findings (Linq/ root, second batch)
- Tests/Linq/Linq/DateTimeOffsetTests.cs -- taxonomy recorded under Coverage-fill findings (Linq/ root, second batch)
- Tests/Linq/Linq/DistinctByMethodTests.cs -- taxonomy recorded under Coverage-fill findings (Linq/ root, second batch)
- Tests/Linq/Linq/DistinctTests.cs -- taxonomy recorded under Coverage-fill findings (Linq/ root, second batch)
- Tests/Linq/Linq/DynamicResultTests.cs -- taxonomy recorded under Coverage-fill findings (Linq/ root, second batch)
- Tests/Linq/Linq/EagerLoadingStrategyKeyedQueryTests.cs -- taxonomy recorded under Coverage-fill findings (Linq/ root, second batch)
- Tests/Linq/Linq/EagerLoadingStrategyUnionTests.cs -- taxonomy recorded under Coverage-fill findings (Linq/ root, second batch)
- Tests/Linq/Linq/EagerLoadingTests.cs -- taxonomy recorded under Coverage-fill findings (Linq/ root, second batch)
- Tests/Linq/Linq/EnumerableSourceTests.AsQueryable.cs -- taxonomy recorded under Coverage-fill findings (Linq/ root, second batch)
- Tests/Linq/Linq/EnumerableSourceTests.cs -- taxonomy recorded under Coverage-fill findings (Linq/ root, second batch)
- Tests/Linq/Linq/EnumMappingTests.cs -- taxonomy recorded under Coverage-fill findings (Linq/ root, second batch)
- Tests/Linq/Linq/EvaluationTests.cs -- taxonomy recorded under Coverage-fill findings (Linq/ root, second batch)

Read (coverage-fill run 2026-10-10, batch 3 -- Linq/ root Ex..Sq, 40 files, class shape and test-method enumeration):
- Tests/Linq/Linq/ExpressionsTests.cs -- class shape and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, third batch)
- Tests/Linq/Linq/ExpressionTests.cs -- class shape and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, third batch)
- Tests/Linq/Linq/FromSqlTests.cs -- class shape and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, third batch)
- Tests/Linq/Linq/FSharpTests.cs -- class shape and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, third batch)
- Tests/Linq/Linq/FullTextTests.SQLite.cs -- class shape and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, third batch)
- Tests/Linq/Linq/FullTextTests.SqlServer.cs -- class shape and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, third batch)
- Tests/Linq/Linq/FunctionTests.cs -- class shape and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, third batch)
- Tests/Linq/Linq/GenerateExpressionTests.cs -- class shape and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, third batch)
- Tests/Linq/Linq/GenericExtensionsTests.cs -- class shape and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, third batch)
- Tests/Linq/Linq/GroupByTests.cs -- class shape and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, third batch)
- Tests/Linq/Linq/InheritanceTests.cs -- class shape and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, third batch)
- Tests/Linq/Linq/InSubqueryTests.cs -- class shape and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, third batch)
- Tests/Linq/Linq/InterfaceTests.cs -- class shape and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, third batch)
- Tests/Linq/Linq/IntervalTranslationTests.Arithmetic.cs -- class shape and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, third batch)
- Tests/Linq/Linq/IntervalTranslationTests.Difference.cs -- class shape and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, third batch)
- Tests/Linq/Linq/IntervalTranslationTests.Mapping.cs -- class shape and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, third batch)
- Tests/Linq/Linq/IntervalTranslationTests.Members.cs -- class shape and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, third batch)
- Tests/Linq/Linq/IntervalTranslationTests.Queries.cs -- class shape and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, third batch)
- Tests/Linq/Linq/IntervalTranslationTests.Write.cs -- class shape and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, third batch)
- Tests/Linq/Linq/IssueTests.cs -- class shape and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, third batch)
- Tests/Linq/Linq/JoinOptimizeTests.cs -- class shape and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, third batch)
- Tests/Linq/Linq/JoinTests.cs -- class shape and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, third batch)
- Tests/Linq/Linq/L2SAttributeTests.cs -- class shape and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, third batch)
- Tests/Linq/Linq/LoadWithTests.cs -- class shape and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, third batch)
- Tests/Linq/Linq/MappingTests.cs -- class shape and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, third batch)
- Tests/Linq/Linq/MathFunctionTests.cs -- class shape and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, third batch)
- Tests/Linq/Linq/ParameterTests.cs -- class shape and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, third batch)
- Tests/Linq/Linq/PredicateTests.cs -- class shape and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, third batch)
- Tests/Linq/Linq/PreferClientCalculationTests.cs -- class shape and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, third batch)
- Tests/Linq/Linq/QueryableAssociationTests.cs -- class shape and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, third batch)
- Tests/Linq/Linq/QueryExpressionInterceptorTests.cs -- class shape and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, third batch)
- Tests/Linq/Linq/QueryFilterTests.cs -- class shape and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, third batch)
- Tests/Linq/Linq/QueryGenerationTests.cs -- class shape and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, third batch)
- Tests/Linq/Linq/QueryInheritanceTests.cs -- class shape and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, third batch)
- Tests/Linq/Linq/RemoteContextTests.cs -- class shape and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, third batch)
- Tests/Linq/Linq/SelectQueryOptimizationTests.cs -- class shape and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, third batch)
- Tests/Linq/Linq/SelectQueryTests.cs -- class shape and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, third batch)
- Tests/Linq/Linq/SelectTests.cs -- class shape and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, third batch)
- Tests/Linq/Linq/SpecialFunctionsTest.cs -- class shape and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, third batch)
- Tests/Linq/Linq/SqlRowTests.cs -- class shape and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, third batch)

Count note (batch 3): ExpressionsTests.cs, JoinTests.cs and SelectTests.cs were previously skimmed and counted, so net-new Tier-2 visits are 37. coverage_tier_2 is reconciled to the on-disk Tier-2 count (698 tracked .cs + 6 .tt - 4 Tier-1 = 700), which supersedes the earlier 692 denominator.

Read (coverage-fill run 2026-10-10, batch 4 -- Linq/ root StringConcat..WindowFunctions.RegrAvgY, 40 files, RE-VISITS of files modified on master since the last index, class shape and test-method enumeration. coverage_tier_2 unchanged at 700/700 because all were already counted):
- Tests/Linq/Linq/StringConcatTests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, fourth batch)
- Tests/Linq/Linq/StringFunctionTests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, fourth batch)
- Tests/Linq/Linq/StringJoinTests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, fourth batch)
- Tests/Linq/Linq/StringTrimTests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, fourth batch)
- Tests/Linq/Linq/SubQueryTests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, fourth batch)
- Tests/Linq/Linq/TableOptionsTests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, fourth batch)
- Tests/Linq/Linq/TakeSkipTests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, fourth batch)
- Tests/Linq/Linq/TestQueryCache.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, fourth batch)
- Tests/Linq/Linq/TphInheritanceTests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, fourth batch)
- Tests/Linq/Linq/TypesTests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, fourth batch)
- Tests/Linq/Linq/ValueConversionTests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, fourth batch)
- Tests/Linq/Linq/VisualBasicTests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, fourth batch)
- Tests/Linq/Linq/WhereTests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, fourth batch)
- Tests/Linq/Linq/WindowFunctionsTests.Average.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, fourth batch)
- Tests/Linq/Linq/WindowFunctionsTests.Combinations.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, fourth batch)
- Tests/Linq/Linq/WindowFunctionsTests.Count.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, fourth batch)
- Tests/Linq/Linq/WindowFunctionsTests.CovarPop.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, fourth batch)
- Tests/Linq/Linq/WindowFunctionsTests.CovarSamp.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, fourth batch)
- Tests/Linq/Linq/WindowFunctionsTests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, fourth batch)
- Tests/Linq/Linq/WindowFunctionsTests.DenseRank.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, fourth batch)
- Tests/Linq/Linq/WindowFunctionsTests.Equality.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, fourth batch)
- Tests/Linq/Linq/WindowFunctionsTests.Filter.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, fourth batch)
- Tests/Linq/Linq/WindowFunctionsTests.FirstValue.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, fourth batch)
- Tests/Linq/Linq/WindowFunctionsTests.Frame.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, fourth batch)
- Tests/Linq/Linq/WindowFunctionsTests.FrameExclusion.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, fourth batch)
- Tests/Linq/Linq/WindowFunctionsTests.HypotheticalSet.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, fourth batch)
- Tests/Linq/Linq/WindowFunctionsTests.Keep.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, fourth batch)
- Tests/Linq/Linq/WindowFunctionsTests.Lag.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, fourth batch)
- Tests/Linq/Linq/WindowFunctionsTests.LastValue.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, fourth batch)
- Tests/Linq/Linq/WindowFunctionsTests.Lead.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, fourth batch)
- Tests/Linq/Linq/WindowFunctionsTests.Max.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, fourth batch)
- Tests/Linq/Linq/WindowFunctionsTests.Median.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, fourth batch)
- Tests/Linq/Linq/WindowFunctionsTests.Min.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, fourth batch)
- Tests/Linq/Linq/WindowFunctionsTests.NthValue.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, fourth batch)
- Tests/Linq/Linq/WindowFunctionsTests.PercentileCont.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, fourth batch)
- Tests/Linq/Linq/WindowFunctionsTests.PercentileDisc.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, fourth batch)
- Tests/Linq/Linq/WindowFunctionsTests.Rank.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, fourth batch)
- Tests/Linq/Linq/WindowFunctionsTests.RatioToReport.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, fourth batch)
- Tests/Linq/Linq/WindowFunctionsTests.RegrAvgX.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, fourth batch)
- Tests/Linq/Linq/WindowFunctionsTests.RegrAvgY.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (Linq/ root, fourth batch)

Read (coverage-fill run 2026-10-10, batch 5 -- WindowFunctionsTests.RegrCount..VarSamp, Mapping/, Microsoft/, OrmBattle/, Reflection/, Samples/, Scaffold/, SchemaProvider/, Tools/, Update/, 40 files, RE-VISITS of files modified on master since the last index, class shape and test-method enumeration. coverage_tier_2 unchanged at 700/700 because all were already counted):
- Tests/Linq/Linq/WindowFunctionsTests.RegrCount.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (fifth batch)
- Tests/Linq/Linq/WindowFunctionsTests.RegrIntercept.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (fifth batch)
- Tests/Linq/Linq/WindowFunctionsTests.RegrR2.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (fifth batch)
- Tests/Linq/Linq/WindowFunctionsTests.RegrSXX.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (fifth batch)
- Tests/Linq/Linq/WindowFunctionsTests.RegrSXY.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (fifth batch)
- Tests/Linq/Linq/WindowFunctionsTests.RegrSYY.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (fifth batch)
- Tests/Linq/Linq/WindowFunctionsTests.RowNumber.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (fifth batch)
- Tests/Linq/Linq/WindowFunctionsTests.StdDev.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (fifth batch)
- Tests/Linq/Linq/WindowFunctionsTests.StdDevPop.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (fifth batch)
- Tests/Linq/Linq/WindowFunctionsTests.StdDevSamp.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (fifth batch)
- Tests/Linq/Linq/WindowFunctionsTests.Sum.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (fifth batch)
- Tests/Linq/Linq/WindowFunctionsTests.Variance.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (fifth batch)
- Tests/Linq/Linq/WindowFunctionsTests.VarPop.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (fifth batch)
- Tests/Linq/Linq/WindowFunctionsTests.VarSamp.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (fifth batch)
- Tests/Linq/Mapping/CanBeNullTests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (fifth batch)
- Tests/Linq/Mapping/DynamicStoreTests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (fifth batch)
- Tests/Linq/Mapping/FluentDynamicMappingTests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (fifth batch)
- Tests/Linq/Mapping/FluentMappingBuildTests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (fifth batch)
- Tests/Linq/Mapping/FluentMappingExpressionMethodTests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (fifth batch)
- Tests/Linq/Mapping/FluentMappingTests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (fifth batch)
- Tests/Linq/Mapping/MappingSchemaTests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (fifth batch)
- Tests/Linq/Mapping/ValueConverterColumnDbTypeTests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (fifth batch)
- Tests/Linq/Microsoft/MicrosoftODataTests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (fifth batch)
- Tests/Linq/OrmBattle/OrmBattleTests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (fifth batch)
- Tests/Linq/Reflection/AttributesTests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (fifth batch)
- Tests/Linq/Samples/ConcurrencyCheckTests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (fifth batch)
- Tests/Linq/Samples/JsonConvertTests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (fifth batch)
- Tests/Linq/Scaffold/SchemaProviderTests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (fifth batch)
- Tests/Linq/SchemaProvider/PostgreSQLSchemaProviderTests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (fifth batch)
- Tests/Linq/SchemaProvider/SchemaProviderTests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (fifth batch)
- Tests/Linq/Tools/ComparerBuilderTests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (fifth batch)
- Tests/Linq/Tools/Mapper/MapperTests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (fifth batch)
- Tests/Linq/Update/BulkCopyTests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (fifth batch)
- Tests/Linq/Update/CreateTableTests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (fifth batch)
- Tests/Linq/Update/CreateTempTableTests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (fifth batch)
- Tests/Linq/Update/DeleteTests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (fifth batch)
- Tests/Linq/Update/DropTableTests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (fifth batch)
- Tests/Linq/Update/EntityInsertTests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (fifth batch)
- Tests/Linq/Update/EntityUpdateTests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (fifth batch)
- Tests/Linq/Update/InsertTests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (fifth batch)

Read (this run -- batch 6, re-visits of files modified on master, already counted in coverage_tier_2):
- Tests/Linq/Update/MergeTests.ApiParametersValidation.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (sixth batch)
- Tests/Linq/Update/MergeTests.Caching.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (sixth batch)
- Tests/Linq/Update/MergeTests.IQueryableSource.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (sixth batch)
- Tests/Linq/Update/MergeTests.Issues.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (sixth batch)
- Tests/Linq/Update/MergeTests.Operations.Combined.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (sixth batch)
- Tests/Linq/Update/MergeTests.Operations.Delete.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (sixth batch)
- Tests/Linq/Update/MergeTests.Operations.DeleteBySource.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (sixth batch)
- Tests/Linq/Update/MergeTests.Operations.Insert.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (sixth batch)
- Tests/Linq/Update/MergeTests.Operations.Parameters.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (sixth batch)
- Tests/Linq/Update/MergeTests.Operations.UpdateBySource.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (sixth batch)
- Tests/Linq/Update/MergeTests.Operations.UpdateWithDelete.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (sixth batch)
- Tests/Linq/Update/MergeTests.Types.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (sixth batch)
- Tests/Linq/Update/MultiInsertTests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (sixth batch)
- Tests/Linq/Update/UpdateFromTests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (sixth batch)
- Tests/Linq/Update/UpdateFromTests.Row.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (sixth batch)
- Tests/Linq/Update/UpdateTests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (sixth batch)
- Tests/Linq/Update/UpdateWithOutputTests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (sixth batch)
- Tests/Linq/Update/UpsertTests.ApiParametersValidation.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (sixth batch)
- Tests/Linq/Update/UpsertTests.Single.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (sixth batch)
- Tests/Linq/UserTests/Issue1238Tests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (sixth batch)
- Tests/Linq/UserTests/Issue1284Tests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (sixth batch)
- Tests/Linq/UserTests/Issue1307Tests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (sixth batch)
- Tests/Linq/UserTests/Issue133Tests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (sixth batch)
- Tests/Linq/UserTests/Issue1347Tests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (sixth batch)
- Tests/Linq/UserTests/Issue1363Tests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (sixth batch)
- Tests/Linq/UserTests/Issue1373Tests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (sixth batch)
- Tests/Linq/UserTests/Issue1403Tests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (sixth batch)
- Tests/Linq/UserTests/Issue1412Tests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (sixth batch)
- Tests/Linq/UserTests/Issue1564Tests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (sixth batch)
- Tests/Linq/UserTests/Issue1700Tests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (sixth batch)
- Tests/Linq/UserTests/Issue1736Tests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (sixth batch)
- Tests/Linq/UserTests/Issue1869Tests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (sixth batch)
- Tests/Linq/UserTests/Issue2052Tests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (sixth batch)
- Tests/Linq/UserTests/Issue2161Tests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (sixth batch)
- Tests/Linq/UserTests/Issue228Tests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (sixth batch)
- Tests/Linq/UserTests/Issue2596Tests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (sixth batch)
- Tests/Linq/UserTests/Issue2743Tests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (sixth batch)
- Tests/Linq/UserTests/Issue2832Tests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (sixth batch)
- Tests/Linq/UserTests/Issue3089Tests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (sixth batch)
- Tests/Linq/UserTests/Issue3148Tests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (sixth batch)

Read (this run -- batch 7, re-visits of files modified on master, already counted in coverage_tier_2):
- Tests/Linq/UserTests/Issue3230Tests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (batch 7 findings)
- Tests/Linq/UserTests/Issue3257Tests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (batch 7 findings)
- Tests/Linq/UserTests/Issue3259Tests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (batch 7 findings)
- Tests/Linq/UserTests/Issue3305Tests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (batch 7 findings)
- Tests/Linq/UserTests/Issue3475Tests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (batch 7 findings)
- Tests/Linq/UserTests/Issue3548Tests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (batch 7 findings)
- Tests/Linq/UserTests/Issue3926Tests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (batch 7 findings)
- Tests/Linq/UserTests/Issue4336Tests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (batch 7 findings)
- Tests/Linq/UserTests/Issue4383Tests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (batch 7 findings)
- Tests/Linq/UserTests/Issue447Tests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (batch 7 findings)
- Tests/Linq/UserTests/Issue5283Tests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (batch 7 findings)
- Tests/Linq/UserTests/Issue5302Tests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (batch 7 findings)
- Tests/Linq/UserTests/Issue5336Tests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (batch 7 findings)
- Tests/Linq/UserTests/Issue5347Tests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (batch 7 findings)
- Tests/Linq/UserTests/Issue5505Tests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (batch 7 findings)
- Tests/Linq/UserTests/Issue5576Tests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (batch 7 findings)
- Tests/Linq/UserTests/Issue5616Tests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (batch 7 findings)
- Tests/Linq/UserTests/Issue693Tests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (batch 7 findings)
- Tests/Linq/UserTests/Issue773Tests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (batch 7 findings)
- Tests/Linq/UserTests/Issue822Tests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (batch 7 findings)
- Tests/Linq/UserTests/Issue973Tests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (batch 7 findings)
- Tests/Linq/UserTests/Issue975Tests.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (batch 7 findings)
- Tests/Linq/UserTests/VeryLongRunningTest.cs -- re-visit, class header and full test-method list read, taxonomy recorded under Coverage-fill findings (batch 7 findings)

</details>
