---
area: TESTS-BENCHMARKS
kind: area-index
sources: [code]
confidence: low
last_verified: 2026-10-09
last_verified_sha: 05150894edc2511f0dd0bc7829b2a309cec36ec9
coverage_tier_1: 0/0
coverage_tier_2: 33/45
---

# TESTS-BENCHMARKS

BenchmarkDotNet harness measuring query execution overhead, SQL emission latency, query-plan-cache internals, and TypeMapper expression-compilation cost across four runtime targets. No Tier-1 anchors are designated yet; see the AUDIT-NOTE below.

## Subsystems

### 1. Queries/ -- live-query benchmarks (MockDb, no real DB)

Ten benchmark classes under `Tests/Tests.Benchmarks/Benchmarks/Queries/`. Each follows the pattern:

- `[GlobalSetup]` wires a `MockDbConnection` + `DataConnection` (or `Db` subclass) backed by a static `QueryResult` payload.
- `[Benchmark]` methods compare LINQ, `CompiledQuery`, and raw ADO.NET execution paths.
- `[Benchmark(Baseline = true)]` is always the raw ADO.NET path so ratios are LINQ/compiled overhead over pure ADO.

| Class | Provider | Measures |
|---|---|---|
| `SelectBenchmark` | PostgreSQL v9.5 | Single-row SELECT: Linq, Compiled, FromSql_Interpolation, FromSql_Formattable, Query, Execute, RawAdoNet |
| `FetchSetBenchmark` | SQL Server 2022 | 31 465-row `SalesOrderHeader` materialisation: Linq, Compiled, RawAdoNet |
| `FetchIndividualBenchmark` | SQL Server | Single-entity fetch variants |
| `FetchGraphBenchmark` | SQL Server 2022 | `LoadWith` eager-loading (1 000 headers + 4 768 details): Linq, LinqAsync, Compiled, CompiledAsync |
| `InsertSetBenchmark` | SQL Server 2022 | `BulkCopy` MultipleRows, batch size 100 over 1 000 rows |
| `UpdateBenchmark` | PostgreSQL v9.5 | UPDATE via LinqSet, LinqObject, Object, CompiledLinqSet, CompiledLinqObject, RawAdoNet |
| `ConcurrentBenchmark` | PostgreSQL v9.5 | 16/32/64 threads, `[ParamsSource]`; compiled vs LINQ, stress-tests query-cache lock contention |
| `Issue3253Benchmark` | SQLite (Microsoft) | Small/Large INSERT and UPDATE with variable vs static parameters; `Query.ClearCaches()` variant; async variants |
| `Issue3268Benchmark` | SQL Server 2008 | UPDATE with nullable vs non-nullable columns; compiled vs dynamic; measures `DataConnection` creation overhead with `_Full` variants |
| `CacheActivityBenchmark` | SQLite (Microsoft) | 18-method query-plan-cache suite: bucket fill, chain-hash partitioning, `MappingSchema` churn, realistic hit/miss mix, long chains, `NoLinqCache` scope, hot/cold tiering, bucket/global cap eviction, `CompiledQuery` reuse, concurrent reads/writes, memory footprint |

`Issue3253Benchmark` uses `LinqToDB.Internal.Linq.Query.ClearCaches()` to force cache-miss regressions -- it was introduced for issue #3253 which tracked query-plan cache bloat with high column counts.

`CacheActivityBenchmark` (`Benchmarks/Queries/CacheActivityBenchmark.cs:35`) exercises `LinqToDB.Internal.Linq.Query`'s cache internals through public APIs only (`IQueryable.ToSqlQuery()`, `Query.ClearCaches()`, `CompiledQuery.Compile`, `NoLinqCache.Scope()`) so the same file compiles unmodified on master and on a query-cache refactor branch -- diffs between runs are attributable to the cache change. Its nested `BenchmarkConfig : ManualConfig` forces `InProcessEmitToolchain` (`Benchmarks/Queries/CacheActivityBenchmark.cs:41-44`) so BenchmarkDotNet doesn't spawn child processes, working around environments where antivirus/EDR blocks dynamic child-process execution. `RunManually(warmups, iterations)` (`Benchmarks/Queries/CacheActivityBenchmark.cs:481`) is an alternate Stopwatch-based runner covering the same 18 benchmark methods, invoked when BDN's toolchain itself is blocked; it trades statistical rigor for a stable branch-vs-master comparison and prints a Markdown table tagged by the `CACHE_BENCH_TAG` environment variable.

### 2. QueryGeneration/ -- SQL emission only (no DB round-trip)

`QueryGenerationBenchmark` (`Tests/Tests.Benchmarks/Benchmarks/QueryGeneration/QueryGenerationBenchmark.cs:1`) builds `NorthwindDB` over a `MockDbConnection(Array.Empty<QueryResult>())` -- no data ever flows. It runs `.ToString()` on the IQueryable (which internally drives the full LINQ->SQL translation pipeline) without executing. Providers: Access OleDb + Firebird v5 (active); SQLite, PostgreSQL, SQL Server variants are commented out. `[ParamsSource(nameof(ValuesForDataProvider))]` parameterizes across the active provider map. Three benchmarks:

- `VwSalesByYear` -- grouped join with year filter (stable query shape, caches hit after first run).
- `VwSalesByYearMutation` -- same shape but year changes on each iteration (cache misses each iteration by design).
- `VwSalesByCategoryContains` -- multi-join + `Contains` on category name (complex predicate, tested with JetBrains profiler support via `#if JETBRAINS`).

Delta 2026-10-09 -- three more SQL-emission benchmarks live in the same folder, each paired with a `RunManually` Stopwatch runner (BDN's child-process toolchain cannot restore its generated project in this repo layout, NU1101 / PackageSourceMapping) dispatched from `Program.cs`:

- `WeakJoinScanBenchmark` (`Benchmarks/QueryGeneration/WeakJoinScanBenchmark.cs:17`) -- Firebird v5 over `MockDbConnection(..., ConnectionState.Open)` with `.UseDisableQueryCache(true)` so every call rebuilds the query. `[Benchmark]` methods `DeepChain13` (13-level `LoadWith` self-association chain, the issue #5265 shape) and `Wide20` (20 one-to-one `LoadWith` associations on `WideRoot`) measure the cost of scanning many removable (weak) association joins. Returns `ToSqlQuery().Sql`; manual runner prints mean/median/min ms and SQL length, tag env var `WEAKJOIN_BENCH_TAG`.
- `ParameterReuseBenchmark` (`Benchmarks/QueryGeneration/ParameterReuseBenchmark.cs:16`) -- Access OleDb/Ace via `NorthwindDB`. Measures the cost of confirming that two occurrences of one expression evaluate to the same value (running the user expression at build time) before sharing one SQL parameter: `NoDuplicates` (baseline), `OneDuplicate`, `ManyDuplicates` (one captured value over four chained `Where` calls, eight predicates), `DivergingValues` (a `Counter.Next()` call returns a different value each time, so the pair is not merged and repeated builds also exercise cached-query rejection). Manual runner reports mean/median us and allocated KB/op, tag env var `PARAM_BENCH_TAG`.
- `DeepJoinChainBenchmark` (`Benchmarks/QueryGeneration/DeepJoinChainBenchmark.cs:18`) -- SQL Server 2017 (Microsoft.Data.SqlClient) mock, query cache disabled. Query-generation cost of the `Tests.Linq` `JoinTests.StackOverflow` shape: `Child` joined to `Parent`, then `Parent` re-joined onto the previous `Parent` N times. `Parent` has no unique key so `JoinsOptimizer` cannot collapse the chain. It has **no `[Benchmark]` attributes on purpose** (one operation at depth 100 costs seconds, which would dominate the default `*.QueryGeneration.*` run) -- only `RunManually(warmups, iterations, onlyDepth)` sweeping depths 10/25/50/100 and printing ms/join to show whether cost is linear in join count.

### 3. TypeMapper/ -- expression-compilation micro-benchmarks

Fourteen benchmark classes under `Tests/Tests.Benchmarks/Benchmarks/TypeMapper/`. All use `TypeMapper` from `LinqToDB.Internal.Expressions.Types` and `ExpressionGenerator` from `LinqToDB.Internal.Expressions`. Each pair compares the type-mapped indirection path against a direct call marked `[Benchmark(Baseline = true)]`.

| Class | Aspect benchmarked |
|---|---|
| `BuildActionBenchmark` | `TypeMapper.BuildAction` / `MapActionLambda` overhead |
| `BuildFuncBenchmark` | `TypeMapper.BuildFunc` variants |
| `BuildGetterBenchmark` | property getter via mapped delegate |
| `BuildSetterBenchmark` | property setter via mapped delegate |
| `CreateAndWrapBenchmark` | `BuildWrappedFactory` / `BuildFactory` for 9 constructor signatures |
| `EnumConvertBenchmark` | cast-convert vs dictionary-convert vs flags-convert for `[Wrapper]` enums |
| `WrapActionBenchmark` | wrapped void method call |
| `WrapBenchmark` | wrapped string method, wrapped instance return, `GetEnumerator` over wrapper |
| `WrapEventBenchmark` | wrapped event: empty fire, add/fire/remove, subscribed fire |
| `WrapGetterBenchmark` | wrapped property getters (string, int, long, bool, wrapped type, enum, Version) |
| `WrapInstanceBenchmark` | `TypeMapper.Wrap<T>` instance creation cost |
| `WrapSetterBenchmark` | wrapped property setters |
| `NpgsqlBulkCopyRowWriterBenchmark` | `ExpressionGenerator`-built row-writer vs direct `NpgsqlBinaryImporter.Write`; includes `ColumnDescriptor.GetProviderValue` |
| `OracleReaderExpressionsBenchmark` | 8 benchmarks: TypeMapper-built vs direct for `DateTimeOffset` reads from `OracleTimeStampTZ`/`LTZ` and `OracleDecimal` conversions; includes the workaround for issue #2032 |

All TypeMapper benchmarks use synthetic `Original.*` / `Wrapped.*` classes defined in `TestClasses/TypeMapperWrappers.cs`; `[MethodImpl(MethodImplOptions.NoInlining)]` on every original method prevents JIT inlining from eliminating the overhead being measured.

## Provider mocks

`TestClasses/ProviderMocks/` (namespace `LinqToDB.Benchmarks.TestProvider`) contains 7 classes that implement the full ADO.NET `DbConnection`/`DbCommand`/`DbDataReader`/`DbParameter`/`DbParameterCollection`/`DbTransaction` hierarchy against an in-memory `QueryResult`:

- `QueryResult` -- payload: `Names[]`, `FieldTypes[]`, `DbTypes[]`, `Data object?[][]`, `Return int`, optional `Match Func<string,bool>` predicate for multi-result routing.
- `MockDbConnection` -- supports single-result and multi-result (`QueryResult[]`) constructors; routes via `MockDbCommand`. The delta-added QueryGeneration benchmarks pass `(Array.Empty<QueryResult>(), ConnectionState.Open)` to hand linq2db an already-open connection.
- `MockDbCommand` -- calls `GetResult()` which applies `Match` predicate for multi-result routing; `ExecuteNonQuery()` returns `QueryResult.Return`.
- `MockDbDataReader` -- `Read()` increments row index into `Data`; `IsDBNull` checks for null; typed getters cast directly. `GetSchemaTable()` returns `QueryResult.Schema` (needed for column-metadata discovery).
- `MockDbParameter` / `MockDbParameterCollection` / `MockDbTransaction` -- minimal stub implementations.

These mocks eliminate network and serialisation cost, making every `[Benchmark]` measure only linq2db's own translation and materialisation overhead.

## Key types

| Type | File | Role |
|---|---|---|
| `Config` | `Config.cs` | `IConfig` singleton; jobs: .NET 4.6.2 (baseline), 8.0, 9.0, 10.0; RyuJIT x64; MemoryDiagnoser; GitHub Markdown exporter; `FilteredColumnProvider` strips Job/Error/Median/Gen*/Ratio/StdDev columns |
| `Program` | `Program.cs` | Entry point; four manual-runner CLI modes bypass BenchmarkDotNet entirely: `manual-cache [iterations] [warmups]` (`Program.cs:24-30`, `CacheActivityBenchmark.RunManually`), `manual-paramreuse [iterations] [warmups]` (`Program.cs:35-41`), `manual-weakjoin [iterations] [warmups]` (`Program.cs:44-50`), `manual-deepjoin [iterations] [warmups] [onlyDepth]` (`Program.cs:53-60`); otherwise default filter `*.Queries.* *.QueryGeneration.*` (TypeMapper benchmarks opt-in only); `BenchmarkSwitcher.FromAssembly` |
| `MockDbConnection` | `TestClasses/ProviderMocks/MockDbConnection.cs` | Core mock entry point |
| `QueryResult` | `TestClasses/ProviderMocks/QueryResult.cs` | Mock result payload |
| `NorthwindDB` | `Models/Northwind/NorthwindDB.cs` | `DataConnection` subclass wired to `MockDbConnection(Array.Empty<QueryResult>())`; used by `QueryGenerationBenchmark` and `ParameterReuseBenchmark` |
| `NortwindExtensions` | `Models/Northwind/NortwindExtensions.cs` | LINQ-expressed Northwind views (`VwSalesByYear`, `VwSalesByCategory`, etc.) used as query generation targets |
| `Northwind` | `Models/Northwind/Northwind.cs` | `public static partial class` holding Northwind entity classes (`Category`, `Customer`, `Product`, `ActiveProduct`/`DiscontinuedProduct` etc.); delta: the two Product subclasses now use C# 12 empty-body `class X : Product;` syntax (formatting only) |
| `Db` | `TestClasses/RawDataAccessBencherMappings.cs` | `DataConnection` subclass for query benchmarks; `SalesOrderHeader`, `SalesOrderDetail`, `Customer`, `CreditCard` entity definitions with pre-built `SchemaTable`/`Names`/`FieldTypes`/`DbTypes`/`SampleRow` statics |
| `TypeMapperWrappers` | `TestClasses/TypeMapperWrappers.cs` | `Original.*` / `Wrapped.*` type pairs for all TypeMapper benchmarks; `Wrapped.Helper.CreateTypeMapper()` centralises `TypeMapper` setup |
| `CacheActivityBenchmark` | `Benchmarks/Queries/CacheActivityBenchmark.cs` | Nested `BenchmarkConfig : ManualConfig` forces `InProcessEmitToolchain`; 18 `[Benchmark]` methods exercising `LinqToDB.Internal.Linq.Query` cache internals; `RunManually()` static Stopwatch-based fallback runner reachable from `Program.cs` `manual-cache` mode |
| `WeakJoinScanBenchmark` | `Benchmarks/QueryGeneration/WeakJoinScanBenchmark.cs` | Delta: `DeepChain13` / `Wide20` weak-join scan cost; `manual-weakjoin` |
| `ParameterReuseBenchmark` | `Benchmarks/QueryGeneration/ParameterReuseBenchmark.cs` | Delta: cost of duplicate-parameter equality checks; `manual-paramreuse` |
| `DeepJoinChainBenchmark` | `Benchmarks/QueryGeneration/DeepJoinChainBenchmark.cs` | Delta: deep self-join chain depth sweep, no `[Benchmark]` methods; `manual-deepjoin` |

## Files (Tier 1 / Tier 2)

No Tier-1 files are declared in `kb-areas.md` for this area. All 45 files are Tier 2 (42 prior + 3 added by delta 2026-10-09).

**Read (33 / 45; +1 via delta 2026-07-05, +4 via delta 2026-10-09):**

| File | Notes |
|---|---|
| `Program.cs` | Entry point; default filter; `manual-cache` dispatch (delta 2026-07-05); `manual-paramreuse`, `manual-weakjoin`, `manual-deepjoin` dispatch (delta 2026-10-09) |
| `Config.cs` | Job matrix (net462/net80/net90/net10), exporters, columns |
| `linq2db.Benchmarks.csproj` | OutputType=Exe; refs LinqToDB.csproj + BenchmarkDotNet; TFMs from `..\linq2db.Providers.props` |
| `Benchmarks/Queries/SelectBenchmark.cs` | SELECT benchmark; representative Queries pattern |
| `Benchmarks/Queries/FetchSetBenchmark.cs` | Multi-row fetch |
| `Benchmarks/Queries/FetchGraphBenchmark.cs` | LoadWith eager loading |
| `Benchmarks/Queries/InsertSetBenchmark.cs` | BulkCopy MultipleRows |
| `Benchmarks/Queries/UpdateBenchmark.cs` | UPDATE variants |
| `Benchmarks/Queries/ConcurrentBenchmark.cs` | Thread-count parameterised concurrency |
| `Benchmarks/Queries/Issue3253Benchmark.cs` | Issue #3253 perf regression; cache-clear variant |
| `Benchmarks/Queries/Issue3268Benchmark.cs` | Issue #3268 nullable column overhead |
| `Benchmarks/Queries/CacheActivityBenchmark.cs` | New (delta 2026-07-05): query-plan-cache benchmark suite, 18 methods; forces `InProcessEmitToolchain`; `RunManually` fallback runner |
| `Benchmarks/QueryGeneration/QueryGenerationBenchmark.cs` | SQL emission only |
| `Benchmarks/QueryGeneration/WeakJoinScanBenchmark.cs` | New (delta 2026-10-09): weak-association-join scan cost (Firebird v5 mock) |
| `Benchmarks/QueryGeneration/ParameterReuseBenchmark.cs` | New (delta 2026-10-09): shared-parameter equality-check cost (Access/Ace) |
| `Benchmarks/QueryGeneration/DeepJoinChainBenchmark.cs` | New (delta 2026-10-09): deep self-join chain, manual runner only |
| `Benchmarks/TypeMapper/BuildActionBenchmark.cs` | TypeMapper action overhead |
| `Benchmarks/TypeMapper/CreateAndWrapBenchmark.cs` | Factory/constructor mapping |
| `Benchmarks/TypeMapper/EnumConvertBenchmark.cs` | Enum conversion strategies |
| `Benchmarks/TypeMapper/WrapBenchmark.cs` | Wrapped method/instance/enumerator |
| `Benchmarks/TypeMapper/WrapEventBenchmark.cs` | Wrapped event handling |
| `Benchmarks/TypeMapper/WrapGetterBenchmark.cs` | Property getter mapping |
| `Benchmarks/TypeMapper/NpgsqlBulkCopyRowWriterBenchmark.cs` | ExpressionGenerator bulk-copy path |
| `Benchmarks/TypeMapper/OracleReaderExpressionsBenchmark.cs` | Oracle timestamp/decimal reader expressions |
| `TestClasses/ProviderMocks/MockDbConnection.cs` | Mock ADO.NET connection |
| `TestClasses/ProviderMocks/MockDbCommand.cs` | Mock ADO.NET command |
| `TestClasses/ProviderMocks/MockDbDataReader.cs` | Mock ADO.NET reader |
| `TestClasses/ProviderMocks/MockDbParameter.cs` | Mock parameter |
| `TestClasses/ProviderMocks/QueryResult.cs` | Mock result payload |
| `TestClasses/Mappings.cs` | `User`, `Workflow` entity definitions |
| `TestClasses/RawDataAccessBencherMappings.cs` | `Db`, `SalesOrderHeader`, `SalesOrderDetail`, `Customer`, `CreditCard` |
| `TestClasses/TypeMapperWrappers.cs` | `Original.*`/`Wrapped.*` synthetic type pairs |
| `Models/Northwind/NorthwindDB.cs` | Northwind DataConnection |
| `Models/Northwind/NortwindExtensions.cs` | LINQ-expressed Northwind views |
| `Models/Northwind/Northwind.cs` | Delta 2026-10-09: entity definitions (read head and the delta diff); change is `ActiveProduct`/`DiscontinuedProduct` switched to `class X : Product;` (no behavioural change) |

**Not read (12 / 45):**

| File | Skip reason |
|---|---|
| `Benchmarks/Queries/FetchIndividualBenchmark.cs` | Same pattern as FetchSetBenchmark; single-entity variant |
| `Benchmarks/TypeMapper/BuildFuncBenchmark.cs` | Same pattern as BuildActionBenchmark; func variant |
| `Benchmarks/TypeMapper/BuildGetterBenchmark.cs` | Same pattern as WrapGetterBenchmark; setup variant |
| `Benchmarks/TypeMapper/BuildSetterBenchmark.cs` | Same pattern as WrapSetterBenchmark; setup variant |
| `Benchmarks/TypeMapper/WrapActionBenchmark.cs` | Same pattern as WrapBenchmark; void method variant |
| `Benchmarks/TypeMapper/WrapInstanceBenchmark.cs` | Same pattern as CreateAndWrapBenchmark; wrap-only cost |
| `Benchmarks/TypeMapper/WrapSetterBenchmark.cs` | Same pattern as WrapGetterBenchmark; setter variant |
| `TestClasses/ProviderMocks/MockDbParameterCollection.cs` | Minimal stub; same pattern as MockDbParameter |
| `TestClasses/ProviderMocks/MockDbTransaction.cs` | Minimal stub; BeginTransaction only |
| `Models/Northwind/Northwind.Views.cs` | View projections for Northwind model |

## Inbound / outbound dependencies

**Outbound (this area depends on):**

- `Source/LinqToDB/LinqToDB.csproj` -- direct project reference (sole project dependency in csproj).
- `LinqToDB.Internal.Linq.Query` (`Query.ClearCaches()`) -- used in `Issue3253Benchmark`, and extensively in `CacheActivityBenchmark` (bucket fill, tier promotion/decay, cap eviction, concurrent reader/writer paths).
- `LinqToDB.Linq.NoLinqCache` (`NoLinqCache.Scope()`) -- used in `CacheActivityBenchmark.NoLinqCacheScope` to measure the do-not-cache short-circuit.
- `DataOptions.UseDisableQueryCache(true)` -- used by `WeakJoinScanBenchmark` and `DeepJoinChainBenchmark` so each build re-translates the query (delta 2026-10-09).
- `ToSqlQuery().Sql` -- SQL-emission entry used by the delta-added QueryGeneration benchmarks.
- `LinqToDB.Internal.Expressions.Types.TypeMapper` + `LinqToDB.Internal.Expressions.ExpressionGenerator` -- used by all TypeMapper benchmarks.
- `LinqToDB.DataProvider.PostgreSQL`, `.SqlServer`, `.SQLite`, `.Access`, `.Firebird` -- provider-specific `GetDataProvider()` calls in benchmark setups.
- `LinqToDB.Async` -- `ToListAsync()` in `FetchGraphBenchmark`.

**Inbound (who depends on this area):** None at runtime; this is an executable benchmark harness. The solution filter `linq2db.Benchmarks.slnf` is the only structural inbound reference.

## Known issues / debt

- `QueryGenerationBenchmark` has most providers commented out -- only Access and Firebird are active. The commented block suggests intended multi-provider parameterisation that was never fully enabled. Any new provider added to the benchmark would produce richer regression data.
- `Program.cs` contains a large commented-out manual-run block (now lines 62-139, shifted from 32-112 by the delta-added `manual-paramreuse` / `manual-weakjoin` / `manual-deepjoin` dispatches, and originally 22-97) that duplicates all benchmark class invocations. This is development scaffolding; it is not dead code (uncommenting enables profiler-guided runs) but it adds noise.
- `Program.cs` now carries four near-identical `args[0] == "manual-*"` dispatch blocks, each re-declaring `iters`/`warmups` parsing; the fourth uses distinct local names (`dn`/`dw`/`dd`) to avoid pattern-variable clashes. Not yet factored into a table-driven dispatcher.
- Three of the four manual runners (`WeakJoinScanBenchmark`, `ParameterReuseBenchmark`, `DeepJoinChainBenchmark`) duplicate the mean/median/Stopwatch/GC.Collect loop from `CacheActivityBenchmark.RunManually`. `DeepJoinChainBenchmark` and `WeakJoinScanBenchmark` explicitly cite BDN restore failure (NU1101), `ParameterReuseBenchmark` cites NuGet PackageSourceMapping.
- `ParameterReuseBenchmark` has a public constructor that calls `Setup()` in addition to `[GlobalSetup]` (same pattern as `QueryGenerationBenchmark`), and `DivergingValues` mutates shared `_counter` state, so its results depend on call order within a process.
- `OracleReaderExpressionsBenchmark` documents a workaround for issue #2032 (complex reader expressions) via double-compile. The issue link is `https://github.com/linq2db/linq2db/issues/2032` -- worth verifying if it has since been resolved.
- No `results/` directory state documented -- BenchmarkDotNet artifacts path is set to `..\..\..\..\..\..\Tests\Tests.Benchmarks`, meaning results land in the project root, which is committed. The `.gitignore` status of this directory is not validated here.
- `FetchIndividualBenchmark.cs` is structurally identical to `FetchSetBenchmark.cs` (single-entity form); deduplication with `[Params]` row count was not pursued.
- `linq2db.Benchmarks.csproj` imports `<Import Project="..\linq2db.Providers.props" />` -- TFMs are resolved from that shared props file rather than declared directly, so the actual TFM list (`net462;net8.0;net9.0;net10.0`) is not visible in the project file alone.
- `CacheActivityBenchmark.RunManually` trades BenchmarkDotNet's statistical rigor for a Stopwatch-based fallback when the AV/EDR blocks BDN's child-process toolchain; its output (mean/median/allocated-KB over `iterations` runs after `warmups`) is not directly comparable across machines the way BDN's `Job` statistics are -- it is intended only for stable branch-vs-master deltas on the same machine, tagged via `CACHE_BENCH_TAG`.

## See also

- `linq2db.Benchmarks.slnf` -- solution filter for benchmark-only builds.
- `Tests/Tests.Benchmarks/results/` -- committed BenchmarkDotNet output (Markdown tables).
- [`areas/INTERNAL-API/INDEX.md`](../INTERNAL-API/INDEX.md) -- `TypeMapper`, `ExpressionGenerator` implementation.
- [`areas/PROV-POSTGRES/INDEX.md`](../PROV-POSTGRES/INDEX.md) -- `NpgsqlBulkCopyRowWriterBenchmark` exercises the Npgsql bulk-copy hot path.
- [`areas/PROV-ORACLE/INDEX.md`](../PROV-ORACLE/INDEX.md) -- `OracleReaderExpressionsBenchmark` exercises the Oracle reader expression path.

<details><summary>Coverage</summary>

Tier 1: 0 / 0 files (no Tier-1 anchors declared).

Tier 2: 28 / 41 files read (68%). 13 files deferred -- all confirmed to follow the same structural pattern as siblings read in the same subdir. Confidence set to `medium` because the 90% Tier-2 threshold was not reached; no claims rest on unread files.

**Read (this run -- delta):**

- `Tests/Tests.Benchmarks/Benchmarks/Queries/CacheActivityBenchmark.cs` -- new file: realistic-workload query-plan-cache benchmark suite (18 `[Benchmark]` methods) exercising `LinqToDB.Internal.Linq.Query` cache buckets/tiers/eviction/concurrency through public APIs only; nested `BenchmarkConfig : ManualConfig` forces `InProcessEmitToolchain`; includes a `RunManually` Stopwatch-based fallback runner. Counted as a new Tier-2 file (no Tier-1 anchors declared for this area).
- `Tests/Tests.Benchmarks/Program.cs` -- modified: `Main` now special-cases `args[0] == "manual-cache"` to call `CacheActivityBenchmark.RunManually(warmups, iterations)` directly and return, before falling through to the existing `BenchmarkSwitcher.FromAssembly(...).Run(...)` path; shifts the pre-existing commented-out manual-run scaffolding block down to lines 32-112.

Tier 2 (cumulative after delta): 29 / 42 files read (69%). Denominator increased by 1 for the new `CacheActivityBenchmark.cs` file. Confidence remains `medium` -- still below the 90% Tier-2 threshold; no claims rest on unread files.

**Read (this run -- delta, 2026-10-09):**

- `Tests/Tests.Benchmarks/Benchmarks/QueryGeneration/DeepJoinChainBenchmark.cs` -- added: deep self-join chain query-generation cost (`Build(depth)`), no `[Benchmark]` methods, `RunManually(warmups, iterations, onlyDepth)` sweeps depths 10/25/50/100 on a SQL Server 2017 mock with query cache disabled.
- `Tests/Tests.Benchmarks/Benchmarks/QueryGeneration/ParameterReuseBenchmark.cs` -- added: four `[Benchmark]` methods (`NoDuplicates` baseline, `OneDuplicate`, `ManyDuplicates`, `DivergingValues`) over `NorthwindDB` on Access/Ace; `RunManually` reports us and KB/op, `PARAM_BENCH_TAG`.
- `Tests/Tests.Benchmarks/Benchmarks/QueryGeneration/WeakJoinScanBenchmark.cs` -- added: `DeepChain13` and `Wide20` on a Firebird v5 mock with cache disabled; `RunManually`, `WEAKJOIN_BENCH_TAG`.
- `Tests/Tests.Benchmarks/Models/Northwind/Northwind.cs` -- modified (formatting only): `ActiveProduct` / `DiscontinuedProduct` use empty-body `class X : Product;` syntax. Previously listed as not read; now counted as read.
- `Tests/Tests.Benchmarks/Program.cs` -- modified: added `manual-paramreuse`, `manual-weakjoin`, `manual-deepjoin` dispatch blocks (default iterations/warmups 2000/200, 8/2, 3/1 plus optional depth) and a `using LinqToDB.Benchmarks.QueryGeneration` import; commented scaffolding block now at lines 62-139. Already counted as read, no numerator change.
- Citation re-verification: `QueryGenerationBenchmark.cs:1` anchors the file (class declared at line 15), `CacheActivityBenchmark.cs:35` (class), `:42` (`InProcessEmitToolchain`, inside the cited 41-44), `:481` (`RunManually`) all confirmed against current source.

Tier 2 (cumulative after this delta): 33 / 45 files read (73%). Denominator +3 (three new files), numerator +4 (three new files + `Northwind.cs`). Confidence remains `low` per the prior audit demotion (not re-promoted by this delta); still below the 90% Tier-2 threshold.

</details>
