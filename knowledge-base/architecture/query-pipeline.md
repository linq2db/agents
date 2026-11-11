---
area: GLOBAL
kind: architecture
sources: [code]
confidence: high
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
coverage_tier_1: 8/8
coverage_tier_2: 5/5
---

# Query pipeline

The full path of an `IQueryable<T>` from `db.Customers.Where(...).ToList()` to `SELECT ... FROM ...` text on the wire and back to a `List<Customer>`. Every numbered step cites the file:line where the corresponding code lives. Since #5673 the emit/execute half (steps 6-7) is scenario-based: a provider `IDmlService` plans a `SqlCommandScenario`, `ScenarioCommandRenderer` renders it into a statement-free `BakedQuery`, and the runner interprets the steps. See also [overview](overview.md).

## 1. Capture: `IQueryable<T>` -> `Expression`

The user obtains an `ITable<T>` from `IDataContext` via `dataContext.GetTable<T>()` (`Source/LinqToDB/DataExtensions.cs:44` and the overload at `:64`). `ITable<T>` extends `IExpressionQuery<T>` (`Source/LinqToDB/ITable{T}.cs:12`), whose runtime implementation is `ExpressionQueryImpl<T>` -> `ExpressionQuery<T>` (`Source/LinqToDB/Internal/Linq/ExpressionQuery.cs:20`). Each LINQ method (`Where`, `Select`, `Join`, etc.) calls `IQueryProvider.CreateQuery<TElement>` (`ExpressionQuery.cs:273`), which builds a fresh `ExpressionQueryImpl<TElement>` carrying the appended `MethodCallExpression` (`ExpressionQuery.cs:277`). No SQL exists yet -- only an in-memory expression tree.

## 2. Termination: `ToList` / `First` / `foreach` / `ExecuteAsync`

Terminal LINQ calls go through `IQueryProvider.Execute` / `IAsyncEnumerable.GetAsyncEnumerator` / `IQueryProviderAsync.ExecuteAsync`. They all funnel into the local `ExpressionQuery<T>.GetQuery` (`Source/LinqToDB/Internal/Linq/ExpressionQuery.cs:95`):

```
Query<T> GetQuery(ref IQueryExpressions expression, bool cache, out bool dependsOnParameters)
{
    dependsOnParameters = false;
    if (cache && Info != null) return Info;
    var info = Query<T>.GetQuery(DataContext, ref expression, out dependsOnParameters);
    if (cache && info.CompareInfo?.IsFastComparable == true && !dependsOnParameters) Info = info;
    return info;
}
```

`Info` (`ExpressionQuery.cs:34`) is the per-instance fast cache. The expression container comes from `GetOwnExpressions` (`ExpressionQuery.cs:49`): a compiled table reuses its `CompiledExpressions`, otherwise a fresh `RuntimeExpressionsContainer`. The slow path delegates to the static `Query<T>.GetQuery`. `GetSqlQueries` (`ExpressionQuery.cs:58`) goes through the same `GetQuery` and then `QueryRunner.GetSqlText`.

## 3. Cache lookup

`Query<T>.GetQuery` (`Source/LinqToDB/Internal/Linq/Query{T}.cs:146`) does:

1. Run `BinaryExpressionAggregatorVisitor` on the tree (`Query{T}.cs:166`) -- flattens unbalanced `Or`/`AndAlso` chains for stable hashing.
2. Apply `IExpressionPreprocessor.ProcessExpression` (`Query{T}.cs:171`) and `IQueryExpressionInterceptor.ProcessExpression` (`Query{T}.cs:177`) so user code can rewrite the tree before caching. The interceptor runs before the lookup on every execution because the cache key is built from the rewritten tree.
3. Unless `LinqOptions.DisableQueryCache` is set (`Query{T}.cs:182`), probe the process-wide `QueryCache.Default.TryFind(typeof(T), dataContext, runtimeExpressions, queryFlags, ...)` (`Query{T}.cs:191`; `QueryCache.TryFind` at `Source/LinqToDB/Internal/Linq/QueryCache.cs:317`). The bucket key (`CacheKey`, `QueryCache.cs:101-143`) is result type + context type + `ConfigurationID` + `QueryFlags` + a chain hash of the tree structure. A hit returns immediately (`Query{T}.cs:194`), skipping everything below.
4. On miss, call `ExposeAndPrepareExpression` (`Query{T}.cs:204`, defined at `:105`) -- expands `Expression.Constant` boxing of `IQueryable` instances, captures `ExpressionMethod` lambdas, substitutes parameter accessors, and re-runs the interceptor with `ExpressionKind.ExposedQuery` (`Query{T}.cs:123`, loop guarded at 10 iterations). If exposing changed the tree, the query is marked `dependsOnParameters`, `QueryFlags.ExpandedQuery` is added and the cache is probed once more (`Query{T}.cs:222`).
5. Final miss -> `IncrementMissCount` (`Query{T}.cs:234`) then `CreateQuery` (`Query{T}.cs:240`, defined at `:256`). The result is added with `QueryCache.Default.TryAdd` (`Query{T}.cs:250`) unless `DoNotCache` is set.

## 4. AST build: `Expression` -> `SqlStatement`

`Query<T>.CreateQuery` (`Query{T}.cs:256`) instantiates `ExpressionBuilder` and calls `Build<T>` (`Query{T}.cs:263`; a second attempt with subquery validation forced on follows at `:269` when the first produced an `ErrorExpression`):

```
query = new ExpressionBuilder(query, validateSubqueries, optimizationContext, parametersContext, dataContext, expressions.MainExpression, null).Build<T>(ref expressions);
```

`ExpressionBuilder.Build<T>` (`Source/LinqToDB/Internal/Linq/Builder/ExpressionBuilder.cs:246`) opens a fresh `SelectQuery` (`new SelectQuery()` at `ExpressionBuilder.cs:250`, type at `Source/LinqToDB/Internal/SqlQuery/SelectQuery.cs:12`), calls `BuildSequence` to walk the expression tree, then `BuildQuery` (`ExpressionBuilder.cs:283`) to project the final result. The walk is a dispatcher: each `MethodCallExpression` tries every registered `ISequenceBuilder` until one accepts it (`ExpressionBuilder.cs:476` `TryBuildSequence`). The registered builders live as siblings under `Source/LinqToDB/Internal/Linq/Builder/` -- `SelectBuilder`, `WhereBuilder`, `JoinBuilder`, `GroupByBuilder`, `OrderByBuilder`, `TakeSkipBuilder`, `SelectManyBuilder`, `MergeBuilder`, `MultiInsertBuilder`, `DeleteBuilder`, etc. Each pushes constructs into the active `SelectQuery` clauses `Select` / `From` / `Where` / `GroupBy` / `Having` / `OrderBy` (`SelectQuery.cs:70-75`).

A `SelectQuery` is itself an `ISqlTableSource` (`SelectQuery.cs:12`) -- sub-queries are first-class. Statements are `SqlStatement` subclasses (`Source/LinqToDB/Internal/SqlQuery/SqlStatement.cs:8`): `SqlSelectStatement`, `SqlInsertStatement`, `SqlUpdateStatement`, `SqlDeleteStatement`, `SqlMergeStatement` (the five share `SqlStatementWithQueryBase`), plus `SqlMultiInsertStatement` which derives directly from `SqlStatement` (`Source/LinqToDB/Internal/SqlQuery/SqlMultiInsertStatement.cs:10`). A built `Query<T>` holds exactly one `QueryInfo` (`Source/LinqToDB/Internal/Linq/Query.cs:39`) -- there is no per-query `Queries[]` list any more (`GetQueries()` at `Query.cs:41` wraps the single instance for compatibility).

Side queries (eager load, CTE-union placeholders) are collected as `Harvester`s (`Source/LinqToDB/Internal/Linq/Harvester.cs:14`, formerly "preamble") in the `harvesters` list passed through `BuildQuery` (`ExpressionBuilder.cs:258-259`), attached with `Query.SetHarvesters` (`Query.cs:162`, call at `ExpressionBuilder.cs:275`) and finished in `FinalizeQueryCacheInformation` (`ExpressionBuilder.cs:277`, defined at `:350`). Harvesters are initialised per run by `Query.InitHarvesters` (`Query.cs:185`) or, for combinable eager loads, through `GetEagerEnumerable` (`Query{T}.cs:59`).

Member-call -> SQL-expression conversion goes through `IMemberTranslator` (field `_memberTranslator`, `ExpressionBuilder.cs:54`), resolved from the data context's service provider (`ExpressionBuilder.cs:187`) and wrapped in a `CombinedMemberTranslator` with user-registered translators when present (`ExpressionBuilder.cs:196`). This is how `string.StartsWith`, `DateTime.Year`, etc., become provider-specific SQL fragments.

## 5. AST optimization: `Finalize`

After build, `BuildQuery` runs `query.SqlOptimizer.Finalize` once per query (guarded by `IsFinalized`) on `queryInfo.Statement` (`ExpressionBuilder.cs:311`). The implementation in `BasicSqlOptimizer.Finalize` (`Source/LinqToDB/Internal/SqlProvider/BasicSqlOptimizer.cs:52`) does:

1. `FixEmptySelect` and `FinalizeCte` (`BasicSqlOptimizer.cs:54-55`) -- fixes selects with no projection and resolves recursive CTE references.
2. `OptimizeQueries` (`BasicSqlOptimizer.cs:64`, defined at `:2429`) -- provider-agnostic subquery flattening, redundant-join removal, predicate hoisting.
3. Conditionally `JoinsOptimizer().Optimize` (`BasicSqlOptimizer.cs:68`) when `LinqOptions.OptimizeJoins` is on, followed by a second `FinalizeCte` (`:71`).
4. `FinalizeInsert`, `FinalizeSelect`, `FixSetOperationValues` (`BasicSqlOptimizer.cs:74-76`) -- INSERT-from-SELECT simplification, distinct/UNION conversion fixups.
5. Provider-specific `FinalizeStatement` hook (call at `BasicSqlOptimizer.cs:79`, virtual definition at `:2269`) -- overridden in each `<X>SqlOptimizer` to apply dialect-specific corrections (e.g. SQL Server identity insert, Oracle hint placement, MySQL `LIMIT` translation). The base definition also runs `FinalizeInsertOrUpdate` (`:2273`).

The result is then validated via `SqlProviderHelper.IsValidQuery` (`ExpressionBuilder.cs:315`, only when the statement has a `SelectQuery`) against `SqlProviderFlags` -- if the provider can't express the query (no `OFFSET`, no `INTERSECT`, etc.), a `SqlErrorExpression` is attached (`ExpressionBuilder.cs:317`) and execution will throw a meaningful error instead of generating broken SQL.

## 6. Scenario planning and SQL emission: `SqlStatement` -> `BakedQuery`

When the query is executed, `IDataContext.GetQueryRunner` is called (`Source/LinqToDB/IDataContext.cs:112`). For `DataConnection`, this returns a `DataConnection.QueryRunner` (`Source/LinqToDB/Data/DataConnection.QueryRunner.cs:41`). `QueryRunnerBase.SetCommand` (`Source/LinqToDB/Internal/Linq/QueryRunnerBase.cs:66`) calls the abstract `SetQuery` (`QueryRunnerBase.cs:75`), overridden at `DataConnection.QueryRunner.cs:428`, which runs `CreateExecutionQuery` (`DataConnection.QueryRunner.cs:175`) -> `GetCommand` (`DataConnection.QueryRunner.cs:192`) and then `GetParameters`. `GetSqlText` (`DataConnection.QueryRunner.cs:77`) takes the same route with `forGetSqlText` set.

`GetCommand` returns the cached `QueryInfo.Prepared` when present (`DataConnection.QueryRunner.cs:209-211`), unless the run carries query hints (`hinted`, `:204`), which forces separate steps and a per-run render. Otherwise it routes the statement through `DataConnection.ProcessQuery` (`DataConnection.QueryRunner.cs:232`, setting `IsParameterDependent` when the processed SQL differs) and then calls `ScenarioCommandRenderer.PrepareStructure` (`Source/LinqToDB/Internal/SqlProvider/ScenarioCommandRenderer.cs:235`, call sites `DataConnection.QueryRunner.cs:297` and `:323`).

- `PrepareStructure` asks the provider's `IDmlService` (`Source/LinqToDB/Internal/DataProvider/IDmlService.cs:14`, default `BasicDmlService`, per-provider `*DmlService` subclasses of `DmlServiceBase`) for a `SqlCommandScenario` (`Source/LinqToDB/Internal/SqlProvider/SqlCommandScenario.cs:95`) -- an ordered list of `SqlCommandStep`s plus `OutcomeSteps` (`SqlCommandScenario.cs:104`) -- and folds it into a `SqlCommandGroupPlan` via `IDmlService.PlanScenario` (`IDmlService.cs:35`, call at `ScenarioCommandRenderer.cs:270`) that decides which steps share one physical command.
- `ScenarioCommandRenderer.RenderScenarioGroups` (`ScenarioCommandRenderer.cs:365`, called at `DataConnection.QueryRunner.cs:330`) renders each group through `BasicSqlBuilder.BuildSql(SqlStatement, StringBuilder, ISqlBuilderRenderContext, AliasesContext, NullabilityContext?, int)` (`Source/LinqToDB/Internal/SqlProvider/BasicSqlBuilder.cs:223`, protected overload at `:251`) on the provider's subclass (`SqlServerSqlBuilder`, `PostgreSQLSqlBuilder`, etc.). `BuildSql()` (`BasicSqlBuilder.cs:397`, `BuildSqlImpl` at `:402`) switches on `Statement.QueryType` into `BuildSelectQuery` / `BuildInsertQuery` / `BuildUpdateQuery` / `BuildDeleteQuery` / `BuildMergeStatement` (`BasicSqlBuilder.cs:406-414`). Each provider's `<X>SqlBuilder` overrides hooks like `BuildLimitClause`, quote-style, identifier escaping and dialect-specific function rewrites.
- Set operations (`UNION`, `EXCEPT`, `INTERSECT`) are emitted by recursing into `BuildSql` on each branch (`BasicSqlBuilder.cs:274-285`) with a fresh builder from `CreateSqlBuilder` and `MergeSqlBuilderData` to carry the parameter list back.
- Structure preparation is done once and cached for parameter-independent queries (`prepareOnce`, `DataConnection.QueryRunner.cs:262`), and redone per run for parameter-dependent ones.

The output is a statement-free `BakedQuery` (`ScenarioCommandRenderer.cs:114`, derived from the abstract `PreparedQuery` at `ScenarioCommandRenderer.cs:71`) holding one `PreparedCommand` per group -- the concat text plus optional per-statement `DbBatch` templates -- with its `SqlParameter`s. It is built at `DataConnection.QueryRunner.cs:356` and stored in `QueryInfo.Prepared` when not parameter-dependent (`DataConnection.QueryRunner.cs:366-367`). Each run wraps it in `RenderedQuery` / `ExecutionPreparedQuery` (`DataConnection.QueryRunner.cs:169-171`). Multi-statement queries (identity fetch, upsert emulation) therefore show up as several steps and `Commands` entries, not as a `CommandCount` on the builder (only `DB2SqlBuilderBase` still has one).

## 7. ADO.NET execution

The scenario interpreter (`ExecuteScenario`, `DataConnection.QueryRunner.cs:868`, async at `:1016`) walks `executionQuery.PreparedQuery.Prepared` steps and groups. `ExecuteNonQueryImpl` (`:1080`) and the scalar paths (`:1152`) delegate to it. Each command is set up by `InitCommand` (`DataConnection.QueryRunner.cs:1213`, text overload `:1224`) -> `DataConnection.InitCommand` -> `IDataProvider.InitCommand` (`Source/LinqToDB/DataProvider/IDataProvider.cs:42`, call site `Source/LinqToDB/Data/DataConnection.cs:980`), which lets the provider customise the command (e.g. set `BindByName` on Oracle, configure parameter prefixes), and is executed as `ExecuteNonQuery` / `ExecuteReader` / `ExecuteScalar`. Parameters are materialized from the baked `SqlParameter`s by `ScenarioCommandRenderer.MaterializeDbParameters` (`DataConnection.QueryRunner.cs:406`) and set through `IDataProvider.SetParameter` (`IDataProvider.cs:59`) -- the provider does any DB-specific value-conversion and `DbType` mapping. Steps backed by a `Harvester` run via `Harvester.Harvest` (`Harvester.cs:34`, called from `Source/LinqToDB/Internal/Linq/QueryRunner.cs:1037-1038`). Read paths return a `DataReaderWrapper` for tracing.

Around execution, `IExecutionScope` (`Source/LinqToDB/Internal/DataProvider/IExecutionScope.cs:5`) is the per-provider escape hatch: `IDataProvider.ExecuteScope` (`IDataProvider.cs:72`) is called when the `QueryRunner` is constructed (`DataConnection.QueryRunner.cs:47`) and the scope is disposed in `QueryRunner.Dispose` (`DataConnection.QueryRunner.cs:122-125`). The base returns `null` (`Source/LinqToDB/Internal/DataProvider/DataProviderBase.cs:181`); Informix (`InformixDataProvider.cs:101`) and SAP HANA over ODBC (`SapHanaDataProvider.cs:299`) return an `InvariantCultureRegion` to pin the thread culture for parameter encoding.

## 8. Materialization: `DbDataReader` -> `T`

The mapper that turns reader rows into `T` is built during step 4 (`ExpressionBuilder.BuildQuery` -> `FinalizeProjection<T>` (`ExpressionBuilder.cs:296`) -> `sequence.SetRunQuery(query, finalized)` (`ExpressionBuilder.cs:341`), with `SetRunQueryWithCteUnion` / `SetRunQueryWithKeyedQueryBuffer` variants for eager loads at `:333` / `:337`). It is a compiled `Expression<Func<IQueryRunner, DbDataReader, T>>` cached as `Mapper<T>` (`Source/LinqToDB/Internal/Linq/QueryRunner.cs:72`), with a per-`DbDataReader`-type `ReaderMapperInfo` cache (`_mappers`, `:80`, `ReaderMapperInfo` at `:82`). Per-row mapping calls `mapperInfo.Mapper(queryRunner, dataReader)` (`QueryRunner.cs:95`) inside an `ActivityID.Materialization` scope (`QueryRunner.cs:91`).

If a row throws `FormatException`, `InvalidCastException`, `LinqToDBConvertException`, or any provider-specific `*NullValueException` (`QueryRunner.cs:99`), the runner falls back to "slow mode" via `ReMapOnException` (`QueryRunner.cs:113`, entered from `Map` at `:105`) -- rebuilds the mapper expression with extra `IsDBNull` guards and per-column null tolerance. This is why the first malformed row is slow but subsequent rows in the same query stay fast.

The expressions referenced by the mapper come from `IDataContext.GetReaderExpression` (`IDataContext.cs:83`) -- provider supplies the column-read code (`DbDataReader.GetInt32(idx)`, `GetFieldValue<DateTime>(idx)`, etc.); per-column nullability comes from `IsDBNullAllowed` (`IDataContext.cs:90`).

## 9. Connection lifecycle wrap-up

The `DbCommand` is released by `DataConnection.DisposeCommand` (`Source/LinqToDB/Data/DataConnection.cs:1195`, called from `:904` and `:1169`), which calls `IDataProvider.DisposeCommand` (`IDataProvider.cs:43`, async twin at `:44`). `DataConnection.QueryRunner.Dispose` (`DataConnection.QueryRunner.cs:122`) disposes the `IExecutionScope` and emits the `DisposeQuery` trace. `DataContext`'s `QueryRunner` (`Source/LinqToDB/DataContext.cs:654`, created at `:651`) wraps the inner `DataConnection.QueryRunner` and calls `_dataContext.ReleaseQuery()` after disposing it (`DataContext.cs:665-668`) -- which closes the underlying connection (`ReleaseQuery` at `DataContext.cs:437`, condition at `:447`) unless `KeepConnectionAlive` (`DataContext.cs:202`) or a `ConnectionLockScope` (`DataContext.cs:968-970`) is held.

For the cache-hit case (step 3), steps 4-5 are skipped: the cached `Query<T>` supplies its `QueryInfo` (and `QueryInfo.Prepared` once a non-parameter-dependent query has been baked) plus the compiled mapper, so only steps 6 (the `GetCommand` cache return at `DataConnection.QueryRunner.cs:209`), 7, 8 and 9 run. A parameter-dependent query re-runs `ProcessQuery` + `PrepareStructure` + render on every execution.

<details><summary>Coverage</summary>

- Tier 1 (visited / total): 8 / 8 ✓
  - Source/LinqToDB/IDataContext.cs
  - Source/LinqToDB/DataContext.cs
  - Source/LinqToDB/Data/DataConnection.cs (head, GetDataConnection, lifecycle)
  - Source/LinqToDB/Data/DataConnection.QueryRunner.cs
  - Source/LinqToDB/Internal/SqlQuery/SelectQuery.cs
  - Source/LinqToDB/Internal/SqlQuery/SqlStatement.cs
  - Source/LinqToDB/Internal/Linq/Builder/ExpressionBuilder.cs
  - Source/LinqToDB/Internal/SqlProvider/BasicSqlBuilder.cs (BuildSql + dispatch)
  - Source/LinqToDB/Internal/SqlProvider/BasicSqlOptimizer.cs (Finalize)
  - Source/LinqToDB/DataProvider/IDataProvider.cs
- Tier 2 (visited / total): 5 / 5 ✓
  - Source/LinqToDB/Internal/Linq/Query.cs
  - Source/LinqToDB/Internal/Linq/Query{T}.cs
  - Source/LinqToDB/Internal/Linq/QueryRunner.cs (head, Mapper<T>)
  - Source/LinqToDB/Internal/Linq/ExpressionQuery.cs
  - Source/LinqToDB/Internal/Linq/QueryRunnerBase.cs (referenced via DataConnection.QueryRunner)
- Tier 3 (skipped, logged): 0

Read (this run -- citation repair at f90c5bcfb86d88db436a6494f0640c4c43dd691f):
  - Every `path:line` citation re-checked against the working tree and the stale ones fixed: `ExpressionQuery.cs` (20, 34, 49, 58, 95, 273, 277), `Query{T}.cs` (59, 105, 123, 146, 166-269), `ExpressionBuilder.cs` (196, 246-350 incl. 311/315), `BasicSqlOptimizer.cs` (52-79, 2269, 2429), `QueryRunner.cs` `Mapper<T>` (72-113), `DataConnection.QueryRunner.cs` (41, 122, 175, 192, 428, ...), `DataExtensions.cs` (44, 64), `DataContext.cs` (437, 654-668, 968-970), `IDataProvider.cs` (43, 44, 59, 72), `IExecutionScope.cs:5`, `Harvester.cs` call site `Internal/Linq/QueryRunner.cs:1037-1038`.
  - Narrative updated for #5673: `ScenarioCommandRenderer` / `SqlCommandScenario` / `IDmlService` + `*DmlService` planning, `BuildSql(..., ISqlBuilderRenderContext, ...)`, `Preamble` -> `Harvester`, `BakedQuery` cached on `QueryInfo.Prepared`, single `QueryInfo` (no `Queries[]`), `IExecutionScope` users (Informix, SAP HANA ODBC -- not Oracle), `CommandCount` gone from `BasicSqlBuilder`, cache key description (`QueryCache.CacheKey`).
  - Also read for this run: Source/LinqToDB/Internal/SqlProvider/ScenarioCommandRenderer.cs, SqlCommandScenario.cs, Internal/DataProvider/IDmlService.cs, Internal/Linq/QueryCache.cs, Internal/Linq/Harvester.cs, ITable{T}.cs, DataExtensions.cs.
</details>
