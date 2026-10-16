# DisableBaseline census (2026-10-16, origin/master 1b51ed369)

Source: read-only scout over `git grep -n "new DisableBaseline(" -- Tests` (175 hits, S001–S175 in grep file order). Spot-checked by the plan critic (30 sites read, split confirmed). Re-derive line numbers from the grep before editing; they move.

Forms: a = `using var x = new DisableBaseline(...)`; b = `using (new DisableBaseline(...)) { ... }`; c = `cond ? new DisableBaseline(...) : null`; d = second-argument bool.

## Kept as scope (54) — do not migrate

- Tests/Base (30, infra): ScopedSettings.cs:24 RestoreBaseTables.Dispose; TestBase.Asserts.cs:232 AssertState; TestBase.Identity.cs:18,142,292; TestBase.Tables.cs:29,44,89,124,205,222,288,303,323,347,361,376,398,419,433,447,461,476,508; TestBase.cs:219 (SAP HANA plan-cache clear); TestUtils.cs:231,237,290,308,335.
- EF (12 infra): ContextTestBase.cs:57; CustomContextIssueTests.cs:72,152,209,250,330(S036, whole-test but reason "create db" — kept),380,450,497,566; IdTests.cs:186,198.
- Tests/Linq infra: CreateData.cs FirebirdAction (S045); SqlServerTests.cs InitIssue1294/CleanupIssue1294 (S069,S070); SqlServerTypesTests.cs SqlTypes.Data (S074); AK107Tests.cs CreateUser (S076); BooleanTests.cs TestSybase (S077); OrmBattleTests.cs Setup (S159); MergeTests.Operations.IdentityInsert.cs PrepareIdentityData (S165).
- Fragments (4): MiniProfilerTests.TestMySqlConnector (S048); MySqlTests.TestDataTypes (S051, S052 nested); PostgreSQLTests.TestBigInteger direct-only BulkCopy (S066, by design).
- Parameter-dependent (1): Issue681Tests.TestTableFQN (S175, depends on `withServer`).

## Migrate to [NoBaselines] — conditional sites (Configuration)

- S068 SqlServerTests.TestDataTypes2, S071–S073 SqlServerTypesTests.TVP (TableValuedParameterProcedureTest, ...InQueryUsingFromSqlTest, ...InMergeSource): `IsMsProvider(context)` → `TestProvName.AllSqlServerMS + "," + TestProvName.SqlAzureMiMS`.
- S135 IntervalTranslationTests.Difference DateDifferenceFromServerNow: AllFirebird, AllYdb, AllSqlServer, AllPostgreSQL, AllMySql, AllDB2, AllInformix, AllSybase, AllSapHana.
- S163/S164 InsertTests DistinctInsert1/2: AllSapHana, AllYdb.
- (bug-flavoured conditional ones are in the bug list below)

## Migrate — helpers (attribute on every caller, delete helper scope)

- S057 OracleTests.BulkCopyRetrieveSequence → callers BulkCopyRetrieveSequencesProviderSpecific, ...MultipleRows, ...RowByRow, ...ProviderSpecificUsingOptions, ...MultipleRowsUsingOptions, ...RowByRowUsingOptions.
- S058 OracleTests.BulkCopyRetrieveSequenceAsync → the six ...Async counterparts.

## Migrate — class-level (16 sites → 4 class attributes)

- MultiThreadingTests (5, "Multi-threading"); TemporalTableTests (8, "Current datetime parameters used"; TemporalNoOptimization executes no SQL); Issue1398Tests (2, "Multi-threading"); Issue278Tests (helper TestIt S172, "Multi-threading").

## Issue256Tests (2) — not NoBaselines

S170/S171 "test name conflicts": 12 ValueSource delegates share one FullName → give cases distinct names, remove scopes (E-12).

## Bug-flavoured (18) — measure per D-6

S047 DataConnectionTests.TestDisposeFlagCloning962Test1 (AllAccess, CI); S049 MiniProfilerTests.TestSqlServerImpl helper (callers TestRetryPolicy, TestSqlServer; SqlServer); S050 MiniProfilerTests.TestSqlServerMS (SqlServer); S082–S089 ComplexTests2 (TestQueryForBaseType, TestLoadWithWithCast, TestNestedLoadWithWithCast, TestComplexPropertyLoading, TestStringAndConverterEnums, TestUpdateWithTypeAndBaseType, TestInsertUsingDerivedObjectUsingFluentMapping, TestInheritanceByBaseType; all providers); S144 QueryGenerationTests.ToSqlQuery_WithParametersDeduplication (AllAccessOleDb, CI); S146 StringFunctionTests.LastIndexOf2 + S147 StringJoinTests.JoinAggregateArrayNotNullAndFilter (AllYdb — measured 2026-10-16: no mismatch, also on unmodified master → remove gate); S158 FluentMappingAliasTests.AliasingTest; S160 SchemaProviderTests.IncludeExcludeSchemaTest (ProviderName.DB2, CI); S166 MergeTests.Types.TestTypesInsertByMerge (AllPostgreSQL); S167 Issue1046Tests.TestInheritance.

Everything else (83 sites) is an unconditional whole-test method attribute; reason = the scope's reason string verbatim.
