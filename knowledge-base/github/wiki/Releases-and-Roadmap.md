- [Release 6.5.0](#release-650)
- [Release 6.4.0](#release-640)
- [Release 6.3.0](#release-630)
- [Release 6.2.1](#release-621)
- [Release 6.2.0](#release-620)
- [Release 6.1.0](#release-610)
- [Release 6.0.0](#release-600)
- [Release 5.4.1.9](#release-5419)
- [Release 5.4.1](#release-541)
- [Release 5.4.0](#release-540)
- [Release 5.3.2](#release-532)
- [Release 5.3.1](#release-531)
- [Release 5.3.0](#release-530)
- [Release 5.2.2](#release-522)
- [Release 5.2.1](#release-521)
- [Release 5.2.0](#release-520)
- [Release 5.1.1](#release-511)
- [Release 5.1.0](#release-510)
- [Release 5.0.0](#release-500)
- [Release 5.0.0 RC 2](#release-500-rc-2)
- [Release 5.0.0 RC 1](#release-500-rc-1)
- [Release 5.0.0 Preview 2](#release-500-preview-2)
- [Release 5.0.0 Preview 1](#release-500-preview-1)
- [Release 4.4.1](#release-441)
- [Release 4.4.0](#release-440)
- [Release 4.3.0](#release-430)
- [Release 4.2.0](#release-420)
- [Release 4.1.1](#release-411)
- [Release 4.1.0](#release-410)
- [Release 4.0.1](#release-401)
- [Release 4.0.0](#release-400)
- [Release 4.0.0 Release Candidate 2](#release-400-release-candidate-2)
- [Release 4.0.0 Release Candidate 1](#release-400-release-candidate-1)
- [Release 4.0.0 Previews 2-10](#release-400-previews-2-10)
- [Release 4.0.0 Preview 1](#release-400-preview-1)
- [Releases 3.x](https://github.com/linq2db/linq2db/wiki/Release-Notes-3.0.0)
- [Older Versions](https://github.com/linq2db/linq2db/wiki/Archived-Release-Notes)

***

### Release 6.5.0

#### LinqToDB

##### ⚠ Breaking changes

- Subtracting two dates now measures **elapsed time** instead of counting calendar boundaries. `(end - start).TotalDays` / `TotalHours` / `TotalMinutes` / `TotalSeconds` / `TotalMilliseconds` on `DateTime` and `DateTimeOffset` previously lowered to `DATEDIFF`, which counts boundary crossings — `10:59` -> `11:01` answered `TotalHours == 1`. It now answers the value .NET gives. On most providers this is a silent result change, so review queries that depend on the old behaviour; on SQL Server 2014 and below and on Informix the expression is refused instead, since neither can express an elapsed difference as a value. ([#5750](https://github.com/linq2db/linq2db/pull/5750))
- A set operation whose branches do not read a column the same way is now rejected rather than answering wrong. `Union` / `Except` / `ExceptAll` / `Intersect` / `IntersectAll` throw `LinqToDBException` when the branches differ in how a column is read — different value converters, different declared duration units, or one side converted and the other not. Previously a constant compared against a converted column was compared against the raw stored value, returning two rows where .NET says one. ([#5750](https://github.com/linq2db/linq2db/pull/5750))
- `Concat` / `UnionAll` branches that read a column on different terms are now read per branch instead of through one shared conversion — previously a branch that dropped its conversion could come back off by a factor of ten million. Such a member stays readable, but is refused if used in SQL further down the query. ([#5750](https://github.com/linq2db/linq2db/pull/5750))
- `BulkCopyOptions` gained a `MaxSqlLengthForBatch` parameter on its primary constructor. The previous positional constructor is retained for binary compatibility but marked obsolete and slated for removal in version 7, so calling it positionally now warns — an error if you treat warnings as errors — and positional deconstruction of `BulkCopyOptions` no longer matches. Use the object-initialiser or `With…` forms. ([#5828](https://github.com/linq2db/linq2db/pull/5828))
- `Union`, `Intersect` and `IntersectAll` over branches that project different but assignable types now report a clear error instead of returning rows. The rows they returned were wrong — unlike `UnionAll`, a distinct set operation has no way to tell the branches apart — so a silent data defect became a loud one. Add an explicit `Select(x => new Projection { ... })` to each branch to say which shape to build. ([#5833](https://github.com/linq2db/linq2db/pull/5833))
- A scoped table hint now applies to tables in nested scopes too, instead of all but the innermost hint vanishing:

  ```csharp
  q.AsSqlServer().WithUpdLockInScope().WithRowLockInScope().WithHoldLockInScope()
  // was:  [p] WITH (UpdLock)
  // now:  [p] WITH (UpdLock, RowLock, HoldLock)
  ```

  Chaining is one instance of it; a hint applied in an outer query now also reaches tables inside a subquery, where previously an inner scope shielded them. Two consequences. A combination the server rejects now reaches it, surfacing as a provider error when the query runs — SQL CE, for instance, refuses `NoLock` alongside `PagLock`. And a CTE body is now a scope boundary: it no longer inherits an enclosing scope hint, which previously it sometimes did depending on the query's shape. This covers the generic `TablesInScopeHint`, SQL Server's and SQL CE's `With…InScope()` methods, Oracle's and MySQL's `…InScopeHint()` methods, and ClickHouse's `FinalInScopeHint()`. `TableHint`, `IndexHint`, `JoinHint`, `SubQueryHint` and `QueryHint` are unaffected. ([#5850](https://github.com/linq2db/linq2db/pull/5850))
- Several server-side-only APIs now throw `ServerSideOnlyException` when called directly outside a query, where they previously threw `NotImplementedException` (`Sql.Row.Overlaps`) or `InvalidOperationException` (`Sql.Window.PercentileCont` and `PercentileDisc` in their grouping form, and `Sql.Like` outside .NET Framework). `ServerSideOnlyException` does not derive from either, so a `catch` written for the old type will no longer match. ([#5870](https://github.com/linq2db/linq2db/pull/5870))
- `ForEachUntilAsync` now stops when the callback returns `false`, as its documentation always said. On a LinqToDB query it did the opposite — running the whole result set when the callback returned `true`, and stopping after the first row when it returned `false` — so the same callback behaved differently on a LinqToDB query than on any other sequence. Code written against the old behaviour needs its condition inverted. ([#5893](https://github.com/linq2db/linq2db/pull/5893))

##### Added

- `UpdateOptimisticWithRefresh` / `UpdateOptimisticWithRefreshAsync` — an optimistic update that writes the regenerated lock token back onto your entity, so the same instance can be updated again without a manual re-`SELECT`. `UpdateOptimistic` left the entity holding the old token, which made the next update fail as a false concurrency conflict. The new value is read from the same statement via `UPDATE … OUTPUT` / `RETURNING` on SQL Server, PostgreSQL, SQLite, DuckDB, YDB and Firebird 5+, and via a follow-up `SELECT` by primary key elsewhere; the return value is the number of updated rows, `0` meaning a concurrency failure with the entity left untouched. Not available on ClickHouse, which reports no affected-row count. ([#5643](https://github.com/linq2db/linq2db/pull/5643))
- `TimeSpan` duration columns. Declare the unit an integral column counts in — `[Duration(DurationUnit.Second)]` or `.HasDuration(DurationUnit.Second)` — and `TimeSpan` members (`Hours`, `TotalMinutes`, `Ticks`, …), arithmetic (`±`, unary `-`, `TimeSpan / TimeSpan`, `date ± TimeSpan`) and all six comparisons translate to SQL, with reads and writes converted for you. Comparisons scale the *value* into the column's unit rather than the column into ticks, so an index on the column stays usable. Declaring a unit is opt-in — an undeclared `TimeSpan` column keeps its current provider-defined meaning. See [details](#timespan-columns-and-elapsed-time) below. ([#5750](https://github.com/linq2db/linq2db/pull/5750))
- Members of a date difference now translate. `Days`, `Hours`, `Minutes`, `Seconds`, `Milliseconds`, `Ticks` and the `Total*` family, unary `-`, `TimeSpan ± TimeSpan`, `TimeSpan / TimeSpan`, `date ± TimeSpan` and all six comparisons now lower to SQL for any `TimeSpan`, where before only five `Total*` members did and only in the literal `a - b` shape. So `(end - start).Ticks`, `(end - start).Days`, `date + (end - start)` and comparing two differences are computed on the server now. ([#5750](https://github.com/linq2db/linq2db/pull/5750))
- `IInterceptable` / `IInterceptable<T>` are public again, in the `LinqToDB.Internal.Interceptors` namespace, so a hand-written `IDataContext` can receive interceptors. Implement `IInterceptable<IEntityServiceInterceptor>` (and one per other interceptor kind you want) and store the interceptor; you will likely also need `IInfrastructure<IServiceProvider>` from `LinqToDB.Internal.Infrastructure`, which the reference implementation in this PR adds alongside it. Without them a context could accept an interceptor through `AddInterceptor` and never have it called. Thanks to [@cal-tlabwest](https://github.com/cal-tlabwest). ([#5813](https://github.com/linq2db/linq2db/pull/5813))
- `BulkCopyOptions.MaxSqlLengthForBatch` sets the per-batch generated-SQL length limit for any provider using the `MultipleRows` bulk-copy path, where previously only the provider's own hardcoded limit applied:

  ```csharp
  new DataOptions().UseOracle(cs).UseBulkCopyMaxSqlLengthForBatch(1_000_000)   // connection-wide
  db.BulkCopy(new BulkCopyOptions { MaxSqlLengthForBatch = 1_000_000 }, rows)  // per call
  options.WithMaxSqlLengthForBatch(1_000_000)                                  // on an existing options object
  ```

  Measured in characters of generated SQL; `null` keeps the provider's limit. Not consulted by Oracle's `AlternativeBulkCopy.InsertInto`, nor by Access, Informix and SAP HANA, whose `MultipleRows` mode falls back to row-by-row. ([#5828](https://github.com/linq2db/linq2db/pull/5828))

##### Improved

- `PERCENTILE_CONT` with a boolean sort key is now refused when the query is translated, with a clear message, instead of producing SQL no database can evaluate meaningfully. ([#5725](https://github.com/linq2db/linq2db/pull/5725))
- Query compilation for table-per-hierarchy mappings is no longer pathologically slow. A projection combining `InheritanceMapping` with `LoadWith` associations and many mapped columns had become dramatically slower on 6.x than on 5.4.1, and overflowed the stack outright on larger models; build times are back in line with 5.4.1. Entities with many mapped columns benefit independently of inheritance. ([#5737](https://github.com/linq2db/linq2db/pull/5737))
- A generated SQL parameter is now named after the member its value came from where that is knowable - an array or list element (`values[0]` becomes `@values`) and a value-preserving call such as `Nullable<T>.GetValueOrDefault()`. Previously such a parameter took the name of the column it was compared against, or fell back to `@p`. Parameter counts, query shapes and caching are unchanged; only the names differ, which is visible in trace output and to command interceptors. ([#5740](https://github.com/linq2db/linq2db/pull/5740))
- Queries with deep `LoadWith` association chains build substantially faster on first execution. ([#5774](https://github.com/linq2db/linq2db/pull/5774))
- Async materialization now really uses async ADO.NET for queries carrying a wrapper. `await query.LoadWith(…).ToListAsync()` fell back to a synchronous read on a thread-pool thread — blocking it for the whole read, and only observing the `CancellationToken` between rows — and `ToArrayAsync`, `ToDictionaryAsync`, `ToLookupAsync`, `ForEachAsync` and `ForEachUntilAsync` behaved the same way. `AsAsyncEnumerable` was affected too, though it read synchronously on the calling thread rather than a pooled one; that improvement applies to `CreateTempTable` results and to queries carrying a provider hint such as `AsSqlServer()` / `AsSQLite()`. ([#5809](https://github.com/linq2db/linq2db/pull/5809))
- A compiled query whose return type was inferred to a queryable wrapper interface now reports a clear error when invoked, naming both types and the remedy — declare `IQueryable<T>` or `IEnumerable<T>`. Such queries did not work before either; they just failed less helpfully. ([#5844](https://github.com/linq2db/linq2db/pull/5844))

##### Fixed

- A boolean expression used as a window function's `ORDER BY` or `PARTITION BY` key, as one of its arguments, or as a `WITHIN GROUP` / `KEEP` sort key now produces valid SQL on databases with no native boolean type. Previously the comparison was emitted raw into those clauses and the server rejected the statement. The same applies to a plain aggregate over a boolean, such as `Max(x => x.Id == 2)`. ([#5725](https://github.com/linq2db/linq2db/pull/5725))
- Eager-loading an association off a `GroupBy` entity key did not work:

  ```csharp
  from d in db.Detail.LoadWith(x => x.Master.Details)
  group d by d.Master into g
  select new { g.Key.Id, Details = g.Key.Details.Select(x => x.DetailId).ToList() }
  ```

  This applies to a whole-entity group key, in plain LinqToDB and through the EF Core integration. A scalar group key follows a different path and is unchanged. ([#5727](https://github.com/linq2db/linq2db/pull/5727))
- A repeated expression that returns a different value each time it is read was collapsed into a single SQL parameter, so the second occurrence silently filtered on the first one's value:

  ```csharp
  Where(t => t.Int1 == counter.Next() || t.Int2 == counter.Next())
  ```

  The same applied to two calls returning different `IN` collections, where the second call never ran. Two occurrences are now collapsed only when they really evaluate equal, so a captured local, property or method result that genuinely repeats still shares one parameter. Additionally, an exception thrown while evaluating your own expression is no longer swallowed and reported as *"could not be converted to SQL"* — the original exception surfaces.

  Two consequences worth knowing. A repeated collection-returning expression is now evaluated while the query is built, so an expression with side effects runs at that point. And because values are compared with `Equals`, two occurrences yielding equal but distinct collection instances now get one parameter each rather than sharing one, which changes the parameter shape of an `IN` query. ([#5733](https://github.com/linq2db/linq2db/pull/5733))
- A decimal bound placed beside a widening cast was written at the column's scale rather than its own, dropping decimal places and returning wrong rows in both directions. ([#5750](https://github.com/linq2db/linq2db/pull/5750))
- A recursive CTE whose outer projection computes over the CTE's own columns produced SQL the database rejected with a circular-reference error — `circular reference: x` on SQLite, with equivalents elsewhere. A recursive CTE whose body uses `UNION` rather than `UNION ALL` is still affected — tracked as [#5822](https://github.com/linq2db/linq2db/issues/5822). Thanks to [Ilya Chudin](https://github.com/ili). ([#5764](https://github.com/linq2db/linq2db/pull/5764))
- Updating through a DTO whose member is declared as a **base type** (or an interface) of the entity the query actually projects failed with *"Cannot find target table for UPDATE statement"*:

  ```csharp
  class ChildDto { public required Child Child { get; set; } }   // member typed as the base
  // query projects ChildView : Child
  dtos.Where(d => d.Child.ChildID == id).Select(d => d.Child)
      .Set(c => c.ParentID, c => c.ParentID)
      .Update();
  ```

  A DTO whose member is typed as exactly the projected type already worked. Thanks to [Ilya Chudin](https://github.com/ili). ([#5766](https://github.com/linq2db/linq2db/pull/5766))
- A `Sql.Window` function that references no table column threw `ServerSideOnlyException: 'Count' is server-side API` at execution instead of translating — `Sql.Window.Count(w => w) == 3`, and likewise `Count(1, …)`, `Sum(1, …)`, `RowNumber`, `Rank`, `NTile` and `Lead`. All window functions are now recognised as server-side, so they translate as written. ([#5783](https://github.com/linq2db/linq2db/pull/5783))
- A `LoadWith` filter that closes over an optional value returned **wrong data** once both closure states had run in the same process:

  ```csharp
  db.GetTable<MainItem>()
    .LoadWith(m => m.SubItems, q => q.Where(s => values == null || values.Contains(s.Value)))
  ```

  Whichever call ran first won: a later filtered call came back with unfiltered rows, or a later unfiltered call came back empty. No exception, and a single call in isolation was always correct. Applies to all three ways of filtering an association — `LoadWith(sel, q => …)`, `ThenLoad(sel, q => …)` and `LoadWith(m => m.Items.Where(…))` — and to the parent query's `EXISTS` as well as the eager-load query. ([#5801](https://github.com/linq2db/linq2db/pull/5801))
- Calling `Count()` on a query that left-joins a grouping with a computed key crashed with `InvalidOperationException: Cannot get field for …`:

  ```csharp
  from item in t1
  from g in t2.GroupBy(s => s.Code.Substring(0, 3)).LeftJoin(g => g.Key == item.No)
  select new { item.No, Qty = g.Sum(s => s.Quantity) }
  ```

  `ToList()` on the same query worked, so a paging query failed only on the total. A grouping by a plain column was unaffected — the key had to be an expression. The same crash was reachable through `Distinct()` over a computed projection and through `HasUniqueKey`. ([#5802](https://github.com/linq2db/linq2db/pull/5802))
- LinqToDB-only operations threw *"LinqToDB method 'X' called on non-LinqToDB IQueryable"* when applied to a query carrying `LoadWith` — `Insert`, `Update`, `Delete`, `Merge`, `MultiInsert`, `ElementAt` / `ElementAtOrDefault` and the analytic-function overloads. ([#5809](https://github.com/linq2db/linq2db/pull/5809))
- A compiled query whose body ends in a client-side materializer failed on first invocation:

  ```csharp
  CompiledQuery.Compile((IDataContext db, int id) =>
      db.GetTable<Person>().Where(p => p.Id == id).ToList());
  ```

  `ToArray`, `ToDictionary`, `ToLookup` and `ToHashSet` are covered too; the async forms already worked. ([#5813](https://github.com/linq2db/linq2db/pull/5813))
- A constant sort key inside `OVER (...)` was emitted verbatim — `RowNumber(w => w.OrderByDesc(5))` produced `ORDER BY 5 DESC`, and a captured local produced `ORDER BY @p`. A constant is now dropped from the window's `ORDER BY`, and where the provider requires an ordering the key is wrapped as a scalar subquery (`ORDER BY (SELECT 5) DESC`) so the direction and NULLS position are kept. `WITHIN GROUP` and Oracle's `KEEP` order lists are built separately and still pass a constant through unchanged. ([#5817](https://github.com/linq2db/linq2db/pull/5817))
- A window with no ordering — `DefineWindow(w => w.PartitionBy(x))` used through `UseWindow`, or a frame declared without an `ORDER BY` — now gets the same stand-in ordering. Previously it reached the server unordered, which every database rejects for at least some functions, and which none accepts for a `GROUPS` frame or a `RANGE` frame with a value offset. ([#5817](https://github.com/linq2db/linq2db/pull/5817))
- A projected member inside a set-operation branch that mixes translatable parts with a part that has no SQL translation failed the whole query with *"The LINQ expression … could not be converted to SQL"*, where the same projection outside a set operation falls back to .NET:

  ```csharp
  t.Where(e => e.ParentId == null).Select(e => new { id = "p_" + e.Id.ToString("N"), e.Name })
   .Concat(t.Where(e => e.ParentId != null).Select(e => new { id = "c_" + e.Id.ToString("N"), e.Name }))
  ```

  This applies to every set operation — `Concat` / `UnionAll`, `Union`, `Except`, `ExceptAll`, `Intersect` and `IntersectAll` — and to a projection over a row of an in-memory sequence. Regression in 6.3.0. A member the provider refuses outright — an interval it cannot measure, for instance — still fails rather than silently degrading. ([#5818](https://github.com/linq2db/linq2db/pull/5818))
- A `LEFT JOIN` fallback inside a set-operation branch lost its null check, so it returned **wrong values** with no error. Every branch after the first was affected:

  ```csharp
  // the joined entity must carry a query filter whose predicate is not a compile-time constant
  builder.Entity<Master>().HasQueryFilter<MyDataContext>((q, dc) => q.Where(m => m.TenantId == dc.TenantId));

  IQueryable<string> Values(int id) =>
      from d in db.Details.Where(d => d.Id == id)
      from m in db.Masters.Select(x => new { x.Id, Value = x.Value + "!" }).LeftJoin(x => x.Id == d.MasterId)
      select m != null ? m.Value : "Unknown";

  Values(1).Concat(Values(2)).Concat(Values(3));   // "Unknown" came back as null
  ```

  A non-matching join produced `NULL` instead of the fallback, and where the fallback was a value type it materialised as the default (`0` for `int`). A two-level fallback chain collapsed to the first join's column entirely. Three things had to coincide: a query filter on the joined entity, a filter predicate that is not a compile-time constant, and a computed projected column. Regression in 6.4.0. Related: `EXCEPT` and `INTERSECT` branches no longer contribute nullability, so generated SQL for those operators may carry fewer null checks than before. ([#5831](https://github.com/linq2db/linq2db/pull/5831))
- `Concat` and `UnionAll` where one branch projects a derived type read as the set operation's element type now generate valid SQL, including inside a recursive CTE. Previously every member was emitted twice — once filled, once padded with `NULL` — and the server rejected the statement. ([#5833](https://github.com/linq2db/linq2db/pull/5833))
- `Except` and `ExceptAll` over such branches now actually remove rows. Previously the branches had no column in common, so the operation removed nothing and returned everything. ([#5833](https://github.com/linq2db/linq2db/pull/5833))
- Projecting a whole constructed object through a base type — `select new Derived { ... } as Base` — no longer throws. This applies with or without a set operation involved. ([#5833](https://github.com/linq2db/linq2db/pull/5833))
- Writing a derived-type entity through a base-mapped table threw `ArgumentException: Property 'X' is not defined for type 'Base'`:

  ```csharp
  db.GetTable<BaseClass>().Insert(() => new Child1 { Id = 1, Code = 1, Child1Field = 11 });
  ```

  The derived member's column now reaches the SQL. This covers `Insert`, `Update(setter)`, `InsertOrUpdate` and constructor-based (record-style) projections. A subtype with no `[InheritanceMapping]` entry still fails, but loudly rather than dropping the column. ([#5840](https://github.com/linq2db/linq2db/pull/5840))
- Separately, `UpdateWithOutput` and `UpdateWithOutputInto` against an inheritance-mapped table now work without an explicit output expression. Previously any such call threw, whether or not a derived type was involved, because the default output projection builds whole `Deleted` / `Inserted` entities carrying every subtype's columns. ([#5840](https://github.com/linq2db/linq2db/pull/5840))
- A custom `Sql.Extension` builder that **reads** an argument value — `builder.GetValue<T>(i)`, `GetObjectValue(i)`, or straight off `builder.Arguments[i]` — baked that value into the cached SQL, so a later query differing only in that value silently ran the first query's SQL and returned its results. Values a builder reads are now part of the query-cache key. This affected any scalar argument; a *collection* argument was affected only on providers that map the collection as a scalar or array type, such as PostgreSQL.

  Note for extension authors: only the outermost call of a chained extension has its arguments registered, so a builder that reads an argument belonging to an inner element must mark that argument with `[SqlQueryDependent]` to keep its value in the key.

  Three related fixes: capturing one query inside another no longer executes the captured query on every cache lookup, and two structurally identical captured queries now share a cache entry; a collection argument is compared by content rather than by identity, so a rebuilt list with the same items reuses the cached query; and `GetExpression(argName, unwrap, inlineParameters)` now honours `inlineParameters`, which the by-name overload silently dropped. ([#5841](https://github.com/linq2db/linq2db/pull/5841))
- A compiled query ending in `LoadWith` or `ThenLoad` now runs. Previously it failed — usually with *The LINQ expression could not be converted to SQL* naming an unresolved `ps[0]`, and the `First()` / `FirstAsync()` forms failed while materialising rows instead. The eager-loading expression itself never had to use a compiled-query parameter; `LoadWith` only had to be the outermost call. `LoadWithAsTable` was never affected. ([#5844](https://github.com/linq2db/linq2db/pull/5844))
- The same failure hit any compiled query whose outermost call returns a queryable wrapper — a provider chain such as `AsPostgreSQL().SubQueryTableHint(...)`, or your own extension method returning `IQueryable<T>`. These now work too. ([#5844](https://github.com/linq2db/linq2db/pull/5844))
- A compiled query whose predicate closes over a captured local and joins four or more conditions with `&&` no longer fails. ([#5844](https://github.com/linq2db/linq2db/pull/5844))
- `Sql.Property`, `Sql.StringAggregate`, `Sql.Like` and the `Sql.GroupBy` rollup, cube and grouping-set helpers are now declared server-side-only, so they are consistently recognised as SQL-only rather than being evaluated on the client in some query shapes. ([#5870](https://github.com/linq2db/linq2db/pull/5870))
- A window function projected by an inner query and reused by the outer projection — typically as another window's `PARTITION BY` key — is now read as a column of the inner query instead of being nested inside the outer window function. Previously this produced SQL no database accepts. Regression in 6.4.0; both `Sql.Window` and the older `Sql.Ext` surface are affected. ([#5884](https://github.com/linq2db/linq2db/pull/5884))
- Disposing an async enumerator that was never advanced no longer throws a `NullReferenceException`. The same fault also struck `await foreach` / `await using` over a query whose setup fails — a cancelled token, or an error in an eager-loading query — where the disposal error replaced the real one and hid it. ([#5893](https://github.com/linq2db/linq2db/pull/5893))
- `ForEachUntilAsync` over a query using eager loading no longer fails while materialising rows, and no longer holds the reader and command open until the data context is disposed. ([#5893](https://github.com/linq2db/linq2db/pull/5893))
- An implicit transaction opened for a multi-query eager load is now released even when disposing the underlying enumerator throws. ([#5893](https://github.com/linq2db/linq2db/pull/5893))
- Reading `Current` before the first `MoveNextAsync` now throws `InvalidOperationException` with a clear message instead of a `NullReferenceException`. ([#5893](https://github.com/linq2db/linq2db/pull/5893))

##### Changed

- `MaxParametersForBatch` now overrides the provider's own parameter limit in **both** directions. Raising it above the provider limit previously had no effect; raising it past what the driver accepts now surfaces as a driver error rather than being clamped. ([#5828](https://github.com/linq2db/linq2db/pull/5828))

##### Known limitations

- Known limitation: a subtype that shadows an inherited member's name — `public new int Value` — is still written incorrectly, and does so silently rather than throwing. Tracked as [#5852](https://github.com/linq2db/linq2db/issues/5852). ([#5840](https://github.com/linq2db/linq2db/pull/5840))
- When a query combines a keyed eager load with a window value projected by an inner query and reused by the parent, the keyed eager-loading strategy falls back to the default one. The rows returned are unaffected; the query plan and its performance are. ([#5884](https://github.com/linq2db/linq2db/pull/5884))

#### LinqToDB F# Support

##### Added

- F# `option` and `voption` members now translate to SQL inside a query: `.IsSome` / `.IsNone` (and voption's `.IsValueSome` / `.IsValueNone`) become null checks, `.Value` reads the column, and the `Option.isSome` / `Option.isNone` / `Option.get` module functions and their `ValueOption` counterparts work the same way. Previously any of these inside a query failed to translate. See [details](#f-option-and-discriminated-union-support) below. ([#5704](https://github.com/linq2db/linq2db/pull/5704))
- Single-case scalar discriminated unions such as `type UserId = UserId of int` are now mapped automatically, including comparing a column against a union literal. Previously the column type could not be determined. ([#5704](https://github.com/linq2db/linq2db/pull/5704))
- An `option` over a single-case union, such as `UserId option`, is now mapped as a real column. Previously the member was silently dropped — it never appeared in the schema, was never written, and always read back as `None`. ([#5704](https://github.com/linq2db/linq2db/pull/5704))

##### Fixed

- Join and `Where` predicates that capture an outer range variable now translate. F# compiles such a lambda differently from C#, and LinqToDB failed on it with an `InvalidCastException`:

  ```fsharp
  for a in db.GetTable<Addresses>().Where(fun a1 -> n.Id = a1.Id).DefaultIfEmpty() do
  ...
  .LeftJoin(fun y -> y.ReceiptDealNumber = tr.DealNumber && y.ReceiptParcelID = tr.ParcelID)
  ```

  Chained `groupJoin … into g` followed by `for x in g.DefaultIfEmpty()` now emits real `LEFT JOIN`s as well — including three or more chained blocks — where it previously rendered as `INNER JOIN LATERAL` on providers supporting LATERAL, silently dropping unmatched rows, and did not translate at all elsewhere. Two shapes are still unsupported, and they behave differently: a `groupJoin` whose inner sequence is correlated with the outer row now fails with a clear message naming [#5790](https://github.com/linq2db/linq2db/issues/5790), while a chained `groupJoin` followed by a plain `join` is still emitted as an `INNER JOIN` and silently drops the rows it should keep — avoid that shape until [#5794](https://github.com/linq2db/linq2db/issues/5794) is fixed. On YDB two of the newly-translating shapes still fail, because of its existing restrictions on `JOIN … ON`. ([#5701](https://github.com/linq2db/linq2db/pull/5701))

#### LinqToDB for EntityFramework

##### Fixed

- Using one `DbContext` type against **two different providers** in the same process — say SQLite for fast tests and SQL Server for the real ones — gave both of them whichever model was built first, so the second got the wrong column names and types wherever the two mappings differ. Contexts of the same type that differ only by a replaced EF service — `ReplaceService<IModelCustomizer, …>`, `UseNetTopologySuite()`, Npgsql's `MapEnum<T>()` or `UseNodaTime()` — were collapsed the same way. Regression in 6.4.0. ([#5780](https://github.com/linq2db/linq2db/pull/5780))
- Long-lived caches no longer keep EF objects alive for the lifetime of the process on most providers. Under the default scoped `AddDbContext` registration this held the per-request dependency-injection scope; with service-provider caching disabled it added a permanent entry per `DbContext` instance. On Pomelo/MySQL the reference is still held, because its translator provider requires it. ([#5780](https://github.com/linq2db/linq2db/pull/5780))
- Diagnostics raised while LinqToDB probes EF's translators no longer reach the creating context's `LogTo(...)` sink or its diagnostics interceptors. `UseLoggerFactory` and `DiagnosticSource` still receive them. ([#5780](https://github.com/linq2db/linq2db/pull/5780))
- Two or more servers of the same provider family in one process shared a single cached provider when the context is configured with a `DbDataSource` or an externally supplied `DbConnection`. The dialect detected from whichever connected first was then used for all of them, silently and in first-wins order — so a server could be sent SQL for a version it does not support. The connection string is now taken from the data source or the supplied connection, falling back to the connection of an ambient transaction; where none of the three is available the collision remains. ([#5808](https://github.com/linq2db/linq2db/pull/5808))

#### LinqToDB LINQPad Driver

##### ⚠ Breaking changes

- Database client libraries are no longer all installed with the driver. LINQPad now provisions only the client the connection actually uses, on first use — so connecting to a database type you have not used before needs an internet connection. A static context provisions every client unless its new **Database** field is set, and a context assembly that references a client must be able to load it from its own folder. ([#5786](https://github.com/linq2db/linq2db/pull/5786))

##### Added

- macOS support (LINQPad 9). The connection test now runs in the driver process, and errors the driver recovers from are written to a log file rather than only surfacing as a dialog — on macOS that is the sole reporting route, since the message box is unavailable there. The log lives under LINQPad's own log folder (`%localappdata%\LINQPad\Logs.LINQPad<version>` on Windows, `~/Library/Application Support/LINQPad` on macOS). ([#5786](https://github.com/linq2db/linq2db/pull/5786))
- The static-context tab gains an optional **Database** field, restricting client provisioning to a single database instead of all of them. ([#5786](https://github.com/linq2db/linq2db/pull/5786))
- The **Context** field is now editable, so a context class name can be typed in when its assembly cannot be inspected. ([#5786](https://github.com/linq2db/linq2db/pull/5786))
- DuckDB and YDB are now listed among the supported providers. Both already worked; the driver's own description had not caught up. ([#5786](https://github.com/linq2db/linq2db/pull/5786))

##### Fixed

- The driver failed to load on LINQPad 8/9 with `Could not load file or assembly 'System.Collections.Immutable, Version=10.0.0.0'`, because it referenced a higher version than the host runtime supplies. ([#5786](https://github.com/linq2db/linq2db/pull/5786))
- On macOS, every connection failed with a `PresentationFramework` load error that also hid the real error underneath it. ([#5786](https://github.com/linq2db/linq2db/pull/5786))
- SQL Server `geometry`, `geography` and `hierarchyid` columns are readable on non-Windows hosts, and Microsoft Access and SQL CE are no longer offered on a host where they cannot work. ([#5786](https://github.com/linq2db/linq2db/pull/5786))
- A static-context assembly that failed to fully load left the Context list empty; the contexts that did load are now listed.

The LINQPad 5 `.lpx` build keeps its bundled clients and its own Roslyn; the per-connection provisioning above applies to the NuGet driver (LINQPad 8/9) only. Error logging and the fuller dialog text apply to both. ([#5786](https://github.com/linq2db/linq2db/pull/5786))

##### Changed

- A `System.Data.SQLite` connection now provisions `SQLitePCLRaw.lib.e_sqlite3` instead of `SourceGear.sqlite3`. Both SQLite clients run the same engine build as a result; it is SQLite 3.53.3, a patch below the 3.53.4 the classic client previously loaded. ([#5905](https://github.com/linq2db/linq2db/pull/5905))

#### LinqToDB Packages

##### Added

- `THIRD-PARTY-NOTICES.txt` now ships in every package that carries a third-party binary — the 14 T4 packages, `linq2db.cli` (the pointer package and all seven RID packages) and the LINQPad 5 `.lpx`. No shipped binary changed. If you redistribute these packages, two entries are worth reading: the SAP HANA provider's redistribution terms are unresolved ([#5862](https://github.com/linq2db/linq2db/issues/5862)), and the bundled `Microsoft.SqlServer.Types` 170.1000.7 carries expired pre-release licence text, so the notices reproduce 160.1000.6's terms instead. The core `linq2db` package and the `linq2db.LINQPad` nuget bundle no third-party binaries and carry no notices file. ([#5863](https://github.com/linq2db/linq2db/pull/5863))

##### Changed

- The packages that redistribute a native SQLite build — `linq2db.SQLite`, `linq2db.t4models` and the LINQPad 5 `.lpx` — now carry a single native shared by both SQLite clients, rather than two copies kept at separate paths to stop them colliding. ([#5905](https://github.com/linq2db/linq2db/pull/5905))

#### LinqToDB Remote Context

##### Added

- gRPC client proxies and their payload marshallers are now generated at compile time instead of being built by reflection, so a `GrpcDataContext` survives trimming and Native AOT. Server hosts are unaffected — `AddCodeFirstGrpc()` still binds the service as before. ([#5905](https://github.com/linq2db/linq2db/pull/5905))

##### Fixed

- A remote data context leaked one client — and the connection it holds — per `InsertOrReplace`, `InsertOrUpdate` or fluent `Upsert` that LinqToDB emulates as two statements. That happens on providers without native upsert support, and also on SAP HANA whenever the insert and update branches differ, which they routinely do for an entity with `SkipOnInsert` or `SkipOnUpdate` columns. Materially visible on the gRPC and WCF transports, which build a channel per call; the HTTP and SignalR clients are context-shared and were unaffected. ([#5762](https://github.com/linq2db/linq2db/pull/5762))
- `SignalRDataContext(HubConnection, …)` now disposes the `HubConnection` you passed in when the context is disposed — it was documented as owning it but never released it. Note that the synchronous `Dispose()` now waits for the connection to tear down, where previously it released nothing; prefer `DisposeAsync()`. If you reuse that connection after disposing the context, wrap it instead: `new SignalRDataContext(new SignalRLinqServiceClient(hubConnection))`. Likewise, the `HttpClientDataContext(Uri, string)` constructor now disposes the `HttpClient` it created for you. ([#5762](https://github.com/linq2db/linq2db/pull/5762))
- If you subclass `RemoteDataContextBase` and hand out a client you own — a shared `ILinqService` — override the new `OwnsClient` property to return `false`. It defaults to `true`, which is what makes the disposal above happen, so without the override your shared client is disposed after every query. ([#5762](https://github.com/linq2db/linq2db/pull/5762))

#### LinqToDB CLI

##### Added

- The CLI's MCP server is now published to the MCP Registry as `io.github.linq2db/linq2db.cli`, so MCP-aware clients can discover and install it without a hand-written configuration entry. ([#5894](https://github.com/linq2db/linq2db/pull/5894))

##### Improved

- `credentials set` now shows a `*` for each character typed at the password prompts, so a pasted or typed entry is visibly registered before you commit to it, and `Esc` or `Ctrl+U` clears the entry and re-prompts. Previously the prompts gave no feedback at all, so an empty entry could be stored without warning. Masking is skipped when the error stream is redirected, leaving redirected output unchanged. ([#5889](https://github.com/linq2db/linq2db/pull/5889))

#### Analyzers

##### Added

- Two rules check that a server-side-only API declares itself as one: `L2DB1003` flags a member whose body is only a `throw` but which carries no server-side-only marker, and `L2DB1004` flags a marked member that throws something other than `ServerSideOnlyException`. Both come with a code fix, and both report at `Info` level, so neither will fail a build unless you raise its severity. The exception types each rule accepts are configurable in `.editorconfig`. ([#5870](https://github.com/linq2db/linq2db/pull/5870))
- New rule `L2DB1002` flags an equality comparison between a `[Duration]`-declared column and a constant `TimeSpan` the declared unit cannot represent — comparing a whole-second column against `TimeSpan.FromSeconds(1.5)`, for instance, can never match, and the `!=` form always does. It reports at `Info` level and has no code fix, since the intended value cannot be guessed. Only units declared by attribute are seen; a unit configured through the mapping schema is not diagnosed. ([#5873](https://github.com/linq2db/linq2db/pull/5873))

#### ClickHouse

##### Fixed

- A remainder taken over a sum lost the sum's brackets, so `a % (b + c)` was sent as `a % b + c` and answered wrong. Separately, a decimal literal beside an aggregate — `g.Sum(x => x.MoneyValue) + 0.00005m` — was typed from the summed column's scale, so a small addend silently rounded to zero. A plain column-plus-literal was not affected. ([#5750](https://github.com/linq2db/linq2db/pull/5750))
- An unordered `NTILE` failed with *"Unsupported window frame type for function 'NTILE'"*; it now gets a stand-in ordering. ([#5817](https://github.com/linq2db/linq2db/pull/5817))

#### DB2

##### Improved

- `PERCENTILE_DISC` with a boolean sort key is now refused when the query is translated, instead of failing later inside the driver. ([#5725](https://github.com/linq2db/linq2db/pull/5725))

##### Fixed

- An unordered window failed with `SQL0104N` / `SQL20117N` for the ranking functions, `LAG`/`LEAD` and `NTILE`; these now get a stand-in ordering. ([#5817](https://github.com/linq2db/linq2db/pull/5817))

#### Informix

##### Improved

- `FIRST_VALUE` / `LAST_VALUE` over a boolean are now refused when the query is translated, instead of failing later inside the driver. ([#5725](https://github.com/linq2db/linq2db/pull/5725))

##### Fixed

- Every value converter (enums, `[ValueConverter]`) was lost inside a set operation, so the raw stored value was read back. ([#5750](https://github.com/linq2db/linq2db/pull/5750))
- An unordered window failed with *"The ntile, lead, lag and ranking window functions require window order"*; these now get a stand-in ordering. ([#5817](https://github.com/linq2db/linq2db/pull/5817))

#### MySQL

##### ⚠ Breaking changes

- A constant `ORDER BY` inside `OVER (...)` was read by MySQL 8 as a legacy output-column position, so the window ordered by that column instead of tying every row. ⚠ A query that relied on that reading, knowingly or not, now gets an unordered window. MariaDB keeps a stand-in ordering for the functions that require one — the ranking functions, `LAG` and `LEAD` — and drops the constant for the rest. ([#5817](https://github.com/linq2db/linq2db/pull/5817))

#### Oracle

##### Improved

- The bulk-copy SQL length limit rises from 64 KB to 384 KB, so bulk copy can send up to six times fewer statements — less where the batch-size or parameter cap binds first. Oracle uses the `MultipleRows` path with `AlternativeBulkCopy.InsertAll` by default, so the new limit takes effect for every `db.BulkCopy(...)` call unless you have chosen another path. Where batches do get larger, `RowsCopiedCallback` fires correspondingly less often; set `MaxSqlLengthForBatch = 65535` to restore the old batching. ([#5828](https://github.com/linq2db/linq2db/pull/5828))

##### Fixed

- A window with no ordering failed with `ORA-30485`; it now gets a stand-in ordering. ([#5817](https://github.com/linq2db/linq2db/pull/5817))

#### PostgreSQL

##### Fixed

- A remainder taken over a sum lost the sum's brackets, so `a % (b + c)` was sent as `a % b + c` and answered wrong. ([#5750](https://github.com/linq2db/linq2db/pull/5750))

#### SAP HANA

##### Fixed

- `RowNumber(w => w.OrderBy(1))` failed with *"Constants are not allowed on ORDER BY clause of window functions"*. SAP HANA also requires an ordering for more functions than any other provider — the ranking family, `LAG`/`LEAD`, `NTILE`, `FIRST_VALUE`/`LAST_VALUE` and `NTH_VALUE` — all of which now get one. ([#5817](https://github.com/linq2db/linq2db/pull/5817))

#### SQL CE

##### Fixed

- `%` on a 64-bit duration column was cast to 32-bit and overflowed. ([#5750](https://github.com/linq2db/linq2db/pull/5750))

#### SQL Server

##### ⚠ Breaking changes

- ⚠ On 2014 and below, date-difference expressions no longer translate at all: a projection falls back to .NET, but `WHERE` / `ORDER BY` / aggregates throw `LinqToDBException`. ([#5750](https://github.com/linq2db/linq2db/pull/5750))

##### Fixed

- A constant window sort key failed with *"do not support constants"*, and a window with no ordering failed with *"The function 'ROW_NUMBER' must have an OVER clause with ORDER BY"*. ([#5817](https://github.com/linq2db/linq2db/pull/5817))

<!-- rn:deepdive:#5704 -->
#### F# option and discriminated union support

Everything below is enabled by the existing `UseFSharp()` call — there is no new API to adopt.

**Option and voption members in a query.** Both `'T option` and `'T voption` are supported, in
every spelling:

| Form | Members |
|---|---|
| Property access | `.IsSome`, `.IsNone`, `.Value`, and voption's `.IsValueSome` / `.IsValueNone` |
| Module functions | `Option.isSome`, `Option.isNone`, `Option.get`, and the `ValueOption` counterparts |

`.IsSome` / `.IsNone` become null checks; `.Value` reads the column. They work both as a
predicate and in a projection.

**Single-case scalar discriminated unions.** A union with one case wrapping one scalar field —
`type UserId = UserId of int` — maps to a column holding the wrapped scalar, and comparing a
column against a union literal (`x.Key = UserId 10`) translates to a plain comparison against
the scalar. Reference unions, `[<Struct>]` unions and private-representation smart constructors
(`type PrivateId = private PrivateId of int`) are all supported, as is `option` / `voption` over
any of them. Multi-case unions, F# `list`, and single-case unions wrapping a non-scalar record
are not mapped.

**Two behaviours worth knowing about, both deliberate.**

`.Value` becomes the column itself, so reading it from a row where the column is NULL yields the
element type's default — `0` for an `int option` — rather than raising the way `Option.get None`
does. This matches `Nullable<T>.Value`.

A `[<Struct>]` single-case union cannot hold null, so reading a NULL column into one — an
unmatched `LEFT JOIN` row, say — yields the union wrapping the element default (`Age 0`) rather
than an absent value. Use `option` for a column that can be NULL.

**Known limitation.** Comparing `.Value` on an option-over-union against a bare union value is
not yet supported — the element reaches the provider unconverted. Tracked as
[#5886](https://github.com/linq2db/linq2db/issues/5886).

<!-- rn:deepdive:#5750 -->
#### TimeSpan columns and elapsed time

A `TimeSpan` stored as an integer — seconds, milliseconds, ticks — used to be opaque to LinqToDB: you could read and write it through a value converter, but nothing about it translated, so `.TotalMinutes` either silently disappeared from the SQL or failed to build. Declaring the unit the column counts in makes it a real duration:

```csharp
[Table("job")]
class Job
{
    [Column] public int Id { get; set; }
    [Column, Duration(DurationUnit.Second)] public TimeSpan  Elapsed  { get; set; }
    [Column, Duration(DurationUnit.Millisecond)] public TimeSpan? Timeout { get; set; }
}

// or fluent
builder.Entity<Job>().Property(e => e.Elapsed).HasDuration(DurationUnit.Second);
```

From that one declaration LinqToDB derives the read and write conversions and translates members, arithmetic and comparisons:

```csharp
db.Jobs.Where(j => j.Elapsed > TimeSpan.FromMinutes(90))
       .Select(j => new { j.Id, Hours = j.Elapsed.TotalHours, Over = j.Elapsed - TimeSpan.FromHours(1) })
```

`DurationUnit` covers `Nanosecond`, `Tick`, `Microsecond`, `Millisecond`, `Second`, `Minute`, `Hour` and `Day`. Available members are `Days`, `Hours`, `Minutes`, `Seconds`, `Milliseconds`, `Ticks` and the `Total*` family, plus `Microseconds` / `Nanoseconds` / `TotalMicroseconds` / `TotalNanoseconds` on .NET 8+. Component members truncate toward zero, matching the CLR. Supported operators are unary `-`, `TimeSpan ± TimeSpan`, `TimeSpan / TimeSpan`, all six comparisons, and `DateTime`/`DateTimeOffset ± TimeSpan`.

**The unit and the column type are separate decisions.** `[Duration]` says what the stored number *counts*; the database type it is stored in is declared the usual way, with `[Column(DataType = …)]` or `HasDataType(…)`:

```csharp
[Column(DataType = DataType.Int64), Duration(DurationUnit.Tick)]   public TimeSpan Precise { get; set; }
[Column(DataType = DataType.Int32), Duration(DurationUnit.Second)] public TimeSpan Elapsed { get; set; }
```

That is what lets a duration live in a narrow column: seconds in an `INT` rather than ticks in a `BIGINT`. Writing a duration finer than the storage unit truncates — 1.5 seconds into a seconds column keeps 1 — which follows from the storage you chose, not from the conversion.

**Comparisons stay index-friendly.** Rather than scaling the column up to ticks — which would make an index on it unusable — the *value* is scaled down into the column's declared unit, and a bound that falls between two storable values is moved outward in the direction the operator asks. `==` becomes a two-sided range, which is provably empty for a value the column cannot represent. Only `!=` scales the column.

Declaring a unit is **opt-in**: an undeclared `TimeSpan` column keeps whatever meaning your provider already gives it (`TIME` as a time of day, for instance). Declaring both a unit and a value converter on the same member is a mapping error, as is declaring a unit on a member that is not a `TimeSpan`.

**Date differences now measure elapsed time.** `(end - start).TotalHours` and friends used to lower to `DATEDIFF`, which counts boundary crossings rather than duration — `10:59` to `11:01` was one hour. They now lower to a real interval, so the answer matches .NET. On every provider that can express an elapsed difference this is a silent result change; the two that cannot — SQL Server 2014 and below, and Informix — refuse the expression instead, as the table below records.

Where a provider cannot express something, LinqToDB **refuses it by name at query-build time** rather than emitting SQL that quietly answers wrong. A plain projection then falls back to evaluating in .NET, so it still gives an exact answer; `WHERE`, `ORDER BY` and aggregates throw, because they cannot be computed client-side.

| | Providers |
|---|---|
| `end - start` lowers to an elapsed duration | ClickHouse, DB2, DuckDB, Firebird, MySQL / MariaDB, Oracle, PostgreSQL, SAP HANA, SQL CE, SQL Server 2016+, SQLite, Sybase ASE, YDB |
| `end - start` refused, but members of it still lower | Access |
| `end - start` refused entirely | SQL Server 2014 and below, Informix |
| `date ± TimeSpan` lowers | ClickHouse, DuckDB, MySQL / MariaDB, PostgreSQL, SQL CE, SQL Server, Sybase ASE |
| `date ± TimeSpan` refused | Access, DB2, Firebird, Informix, Oracle, SAP HANA, SQLite, YDB |

Each provider also has a floor below which it cannot measure — a component finer than the floor is refused rather than answered as zero. Access measures to the second; SQLite, SQL CE and Sybase ASE to the millisecond (Firebird 2.5 likewise, Firebird 3+ to the tick); DB2 and Oracle to the microsecond; SQL Server 2008+ to the nanosecond; the rest to the tick.

### Release 6.4.0

#### LinqToDB

##### Added

- Two new eager-loading execution strategies for `LoadWith` / `ThenLoad` and inline child sub-query projections, alongside the existing default. **KeyedQuery** buffers the main query, extracts the parent keys client-side, and loads each child collection with `WHERE key IN (…)` — transferring far fewer columns for wide parent entities. **CteUnion** combines multiple same-level child collections into a single `UNION ALL` CTE, collapsing several pre-queries into one round-trip when a level has two or more collections. Choose per query with `WithKeyedLoadStrategy()`, `WithUnionLoadStrategy()`, or `WithSeparateLoadStrategy()` (the explicit default), or set a global default with `DataOptions.UseDefaultEagerLoadingStrategy(EagerLoadingStrategy.KeyedQuery)`. Strategies fall back automatically (CteUnion → KeyedQuery → Default) when a query can't be expressed by the chosen one. A companion `DataOptions.UseImplicitCollectionLoading(ImplicitCollectionLoading.Throw)` makes a collection projected in a `select` without an explicit `LoadWith`/`ThenLoad` or strategy marker fail at build time (default `Allow` keeps current behavior). See [details](#eager-loading-strategies-keyedquery--cteunion) below. ([#5450](https://github.com/linq2db/linq2db/pull/5450))
- New `Sql.Window.*` fluent API for window functions, replacing the older `Sql.Ext.*().Over().ToValue()` pattern with a lambda-based builder that adds compile-time safety (ranking functions require `ORDER BY`, `FILTER` only on aggregates, frames only where valid). It covers ranking, offset (LEAD/LAG), value (FIRST_VALUE/LAST_VALUE/NTH_VALUE), aggregate, statistical, regression/covariance, ordered-set (PERCENTILE_CONT/DISC), hypothetical-set and distribution (MEDIAN, RATIO_TO_REPORT) functions, plus full ROWS/RANGE/GROUPS frames with BETWEEN and EXCLUDE, named windows (`DefineWindow`/`UseWindow`), a FILTER clause, NULLS FIRST/LAST, and Oracle KEEP. Existing code using the old `Sql.Ext.*` window API keeps working unchanged — it's translated onto the new pipeline internally at query time, with no source changes needed. Where a provider doesn't support a requested feature, a clear `LinqToDBException` is raised at translation time instead of sending invalid SQL. See [details](#window-functions) below. ([#5468](https://github.com/linq2db/linq2db/pull/5468))
- New fluent entity-level DML APIs. `Upsert(item, …)` performs an insert-or-update from a single entity with one configure lambda — `.Match((t, s) => …)` to pick the key, `.Insert(…)` / `.Update(…)` to set insert-only vs update-only columns, plus `.When(…)`, `.DoNothing()`, `SkipInsert()` / `SkipUpdate()` — superseding the older three-expression `InsertOrUpdate` overloads, and it also accepts `IEnumerable<T>` and `IQueryable<T>` sources. New entity-based `Insert(item, …)` and `Update(item, …)` take an entity plus a builder where every mapped column is written from the entity by default and `.Set` / `.Ignore` overlay individual columns (`Update` matches on the primary key). All have sync and async variants. `Upsert` maps to each provider's native construct — `ON CONFLICT` (SQLite, PostgreSQL 9.5+), `MERGE` (SQL Server 2008+, Oracle, DB2, Firebird 2+), `ON DUPLICATE KEY UPDATE` (MySQL/MariaDB), native `UPSERT` (SAP HANA) — and falls back to a multi-statement emulation elsewhere; setting `LinqOptions.UpsertEmulationPolicy` to `Throw` rejects the emulated fallback. Resolves #2528, #4153, and #1480 (as an alternative design). See [details](#fluent-upsert--entity-updateinsert-apis) below. ([#5482](https://github.com/linq2db/linq2db/pull/5482))
- Query filters can now be **named**, mirroring EF Core 10's keyed filters. New `HasQueryFilter(string filterKey, …)` overloads on the fluent `EntityMappingBuilder<T>` register multiple independent filters per entity (AND-combined at query time); passing `null` for a filter lambda (with a key) removes that filter. Named filters can also be declared **by attribute** via `QueryFilterAttribute.FilterKey`, alongside the fluent builder. The matching `IgnoreFilters(IEnumerable<string> filterKeys, params Type[] entityTypes)` overload disables filters selectively — by key, or by key×entity-type intersection — instead of all-or-nothing. Existing single (anonymous) filters and the parameterless `IgnoreFilters()` keep working. See [details](#named-query-filters) below. ([#5525](https://github.com/linq2db/linq2db/pull/5525))
- Added `NULLS FIRST` / `NULLS LAST` control to LINQ ordering. New `OrderBy` / `OrderByDescending` / `ThenBy` / `ThenByDescending` overloads accept a `Sql.NullsPosition` (`First` / `Last` / `None`), and a default placement can be set via `new DataOptions().UseDefaultNullsPosition(...)` or `Configuration.Sql.DefaultNullsPosition`. Rendered natively where supported (PostgreSQL, Oracle, DB2, Firebird, SQLite, DuckDB, ClickHouse, SAP HANA) and emulated automatically elsewhere (SQL Server, MySQL, MariaDB, Access, Sybase, etc.), with consistent results; it also flows through `DISTINCT` / set operations, `DistinctBy` / `UnionBy` / `MinBy` / `MaxBy`, indexed `Select`, and aggregate ordering. The BCL `OrderBy` / `ThenBy(keySelector, IComparer<TKey>)` overloads - which have no SQL equivalent - are now rejected with a translation error instead of being silently ignored. See [details](#nulls-first--last-ordering) below. ([#5561](https://github.com/linq2db/linq2db/pull/5561))
- New opt-in `LinqOptions.PreferClientCalculation` (default `false`; also `DataOptions.UsePreferClientCalculation(...)`, `LinqOptions.WithPreferClientCalculation(...)`, and the global `Configuration.Linq.PreferClientCalculation`). When enabled, computed expressions in the final projection — arithmetic, conditionals, unary operations, and mapped members/methods that don't require server-side evaluation — are evaluated client-side during materialization instead of being emitted as extra SQL columns, restoring the v5 projection behavior. Expressions that require server-side evaluation still translate to SQL. ([#5604](https://github.com/linq2db/linq2db/pull/5604))
- Added server-side UUIDv7 generation — a new `Sql.NewGuid7()` extension and translation of .NET 9+ `Guid.CreateVersion7()`, mirroring the existing `Sql.NewGuid()` / `Guid.NewGuid()` (v4) mechanism. Providers with a native UUIDv7 function emit it server-side (PostgreSQL 18+, DuckDB, ClickHouse, MariaDB); every other provider generates a client-side RFC 9562 v7 GUID. See [details](#uuidv7-generation) below. ([#5648](https://github.com/linq2db/linq2db/pull/5648))

##### Improved

- The query cache is now bounded and self-managing. Previously each result type kept up to 100 compiled query plans with no global ceiling and no idle eviction, so a long-running application issuing many distinct queries — multi-tenant filters, user-built reports, or frequent `MappingSchema` swaps — could accumulate large numbers of stale cached plans and grow in memory without bound. The cache now enforces a global entry cap and evicts idle entries on a periodic background sweep (rarely-used queries expire within an hour; frequently-used ones are retained longer), keeping memory bounded in long-running and dynamic-query workloads. The cap, idle timeout, and sweep interval can be tuned via `QueryCache.Default` in the `LinqToDB.Internal.Linq` namespace. ([#5501](https://github.com/linq2db/linq2db/pull/5501))
- ClickHouse and YDB now report an unsupported correlated subquery used in expression position (inside EXISTS / IN / a scalar comparison or function argument) with a clean `LinqToDBException` instead of letting the query reach the server and fail with a raw provider error. Simple correlated subqueries that ClickHouse does support continue to work. ([#5574](https://github.com/linq2db/linq2db/pull/5574))
- `DistinctBy` now generates native `SELECT DISTINCT ON (...)` on PostgreSQL and DuckDB instead of the `ROW_NUMBER()` emulation, producing simpler SQL. The key selector becomes the `ON` list and the query's `OrderBy` is arranged to lead with those keys (as the syntax requires); other providers keep the existing emulation unchanged. ([#5630](https://github.com/linq2db/linq2db/pull/5630))
- DB2, Firebird and Informix now apply a parameter cast per usage rather than marking the parameter as a whole, which removes a redundant nested cast from generated SQL — `Sql.Convert<string, int>(Sql.AsSql(x).Length)` on Firebird now renders `CAST(@p AS VARCHAR(8191))` instead of `CAST(CAST(@p AS Int) AS VARCHAR(8191))`. ([#5723](https://github.com/linq2db/linq2db/pull/5723))

##### Fixed

- A user-registered `IMemberTranslator` now takes priority over the built-in predicate translation for boolean method calls (`Contains`, `Equals`, `StartsWith`, …). Previously a custom translation for these could be ignored; the built-in translation remains as a structural fallback, so predicates inside generic helpers, `MergeInto` subqueries, and EF Core query filters still translate correctly. ([#5348](https://github.com/linq2db/linq2db/pull/5348))
- Fixed an `ArgumentOutOfRangeException` during query build when a nested `UnionAll` reordered or augmented the projected columns — for example a constant column inserted ahead of a column that then has to move to a higher index. Set-operator column re-indexing now handles the reorder. Reported as [#5617](https://github.com/linq2db/linq2db/issues/5617). ([#5450](https://github.com/linq2db/linq2db/pull/5450))
- Provider auto-detection now works in `PublishSingleFile` self-contained deployments. Previously, building an app with `dotnet publish --self-contained -p:PublishSingleFile=true` could break ADO.NET provider detection (for MySQL, SQL Server, SQLite, Oracle, ClickHouse, Access, Informix, Sybase ASE, and SAP HANA), surfacing errors such as `Cannot load assembly MySql.Data` even when the app referenced only `MySqlConnector`. Detection no longer relies on the empty `Assembly.Location` value that single-file bundles report. ([#5489](https://github.com/linq2db/linq2db/pull/5489))
- Fixed a `NullReferenceException` thrown while building a query when a client-evaluated conditional (`?:`) expression — for example one using `string.IsNullOrWhiteSpace` — had an un-taken branch that would itself throw. The C# short-circuit semantics of `?:` are now preserved so the un-taken branch is no longer evaluated. ([#5544](https://github.com/linq2db/linq2db/pull/5544))
- Server-side `string.IsNullOrWhiteSpace` translation now also recognizes U+202F (narrow no-break space) as whitespace, so a value containing only that character is treated as whitespace (matching .NET's whitespace set). ([#5544](https://github.com/linq2db/linq2db/pull/5544))
- Fixed `InvalidOperationException` ("Member '...' not found") when a column is mapped through a nested member path (e.g. `Property(o => o.Sub.Field)` or `[Column(MemberName = "Sub.Field")]`). Such mappings now work in MERGE implicit setters (`UpdateWhenMatched` / `UpdateWhenMatchedAndThenDelete`), in `OnTargetKey()` when the primary key is nested-mapped, and when an inheritance discriminator is mapped via a nested path. ([#5545](https://github.com/linq2db/linq2db/pull/5545))
- Fixed association resolution failing for interface / abstract-base member access reached through a `Select(...)` projection (e.g. `Contains()` over a projected interface filter); follow-up to [#5511](https://github.com/linq2db/linq2db/pull/5511) ([#5548](https://github.com/linq2db/linq2db/pull/5548))
- Fixed a crash under Native AOT triggered by lambda closures used in queries ([#5552](https://github.com/linq2db/linq2db/pull/5552))
- Fixed two problems with `ORDER BY` expressions that get lifted from a subquery up to the outer query:
  - custom ordering built with `Sql.Expr` / `Sql.Fragment` that includes a trailing modifier such as `NULLS FIRST` (e.g. added via an `IExpressionPreprocessor`) produced invalid SQL — PostgreSQL rejected it with a syntax error;
  - a computed expression reused in both a subquery column and the outer `ORDER BY` could be emitted referencing the wrong table alias. ([#5556](https://github.com/linq2db/linq2db/pull/5556))
- Fixed aggregation methods (`Count`/`Sum`/`Min`/`Max`/`Average`) on a captured local collection being translated into a SQL aggregate subquery instead of evaluated on the client ([#5557](https://github.com/linq2db/linq2db/pull/5557))
- Fixed an `InvalidCastException` thrown for a query containing a `Contains` (IN) call inside a correlated subquery whose source is filtered by an outer column. ([#5558](https://github.com/linq2db/linq2db/pull/5558))
- Restored `IS NULL` simplification over string concatenation: a `WHERE (column + value) IS NULL` filter again generates the simpler `column IS NULL` on null-propagating-concat providers (e.g. SQL Server, Access), instead of testing the whole concatenation for null. ([#5567](https://github.com/linq2db/linq2db/pull/5567))
- Fixed redundant nested case-conversion in generated SQL when calling `.ToLower()` or `.ToUpper()` on a Guid converted to string. The provider's own Guid-to-string conversion already lower-cases its result, so a user-supplied `.ToLower()` on top produced a doubled wrap (for example `LCase(LCase(...))` on Access or `Lower(Cast(Lower(...)))` on Firebird); the optimizer now collapses these to a single case call. ([#5570](https://github.com/linq2db/linq2db/pull/5570))
- Fixed two problems with custom expression mappings registered through `Expressions.MapMember`. A mapped member used to project a correlated aggregate directly - for example a helper method mapped to `p.Children.Count(...)` - previously threw an error during query translation instead of producing the expected subquery; it now translates the same as the equivalent hand-written association aggregate. Separately, a mapped `string.CompareTo` / `string.Compare` with a null operand could return a wrong result when evaluated in memory (the generated SQL was already correct); that comparison is now correct. ([#5577](https://github.com/linq2db/linq2db/pull/5577))
- Fixed a v6 regression where `[ExpressionMethod]` substitutions fired during entity materialization regardless of the attribute's `IsColumn` setting. An `[ExpressionMethod]` with `IsColumn = false` (the default) — meant for query-only rewrites that drive server-side SQL and are never evaluated on a materialized client value (e.g. `json_each`-style table forms, navigation chains, custom `Sql.*` helpers) — was incorrectly expanded at materialization and broke. Calculated columns (`IsColumn = true`) are now expanded specifically during entity construction, while `IsColumn = false` members are left as plain column reads (calculated columns declared on inheritance subtypes are expanded correctly too). ([#5578](https://github.com/linq2db/linq2db/pull/5578))
- Fixed a regression where subtracting two `DateTime`/`DateTimeOffset` columns in a projection (e.g. `select new { Time = t.FinishedOn - t.StartedOn }`, yielding a `TimeSpan`/`TimeSpan?`) generated invalid SQL and failed at runtime (or returned wrong results, depending on the provider). The subtraction is now evaluated client-side, preserving full tick precision; the `(a - b).TotalDays`/`TotalHours`/... forms continue to translate server-side via `DateDiff`. Forcing such a subtraction server-side with `Sql.AsSql(...)` now reports a clear "could not be converted to SQL" error. ([#5581](https://github.com/linq2db/linq2db/pull/5581))
- Fixed wrong results for `NOT IN` / negated `Contains` against a subquery on providers without correlated-subquery support (e.g. ClickHouse): when the subquery returned a `NULL` value, rows that should have been kept were incorrectly dropped. The subquery membership test now ignores `NULL` elements, matching LINQ's `Contains` semantics. ([#5582](https://github.com/linq2db/linq2db/pull/5582))
- Fixed an `InvalidOperationException` ("Called when root is not initialized") thrown at query-build time when `Nullable<T>.HasValue` (or `.Value`) was used on a member left unbound by an earlier projection — for example a two-stage `Select` where the nullable member is never assigned and is then tested with `.HasValue` in the next projection. `HasValue` now correctly resolves to `false` for such an unassigned (null) member. ([#5586](https://github.com/linq2db/linq2db/pull/5586))
- Fixed an `InvalidCastException` ("Failed to convert parameter value ... to a Decimal") thrown when a table is LEFT JOINed to a local in-memory collection (e.g. via `.AsQueryable()`) whose element is a multi-member class and one of its members feeds decimal arithmetic in a later projection. A spurious whole-object column was emitted in the generated `VALUES` clause; the join now builds correctly. ([#5587](https://github.com/linq2db/linq2db/pull/5587))
- Fixed an `InvalidCastException` thrown when an aggregate — a custom `[Sql.Extension(IsAggregate = true)]` function (e.g. `count_if`) or an analytic `Average(…, Sql.AggregateModifier)` overload — appeared in one branch of a set operation (`UNION ALL` etc.) against a constant in the other branch. Such queries now build correctly. ([#5619](https://github.com/linq2db/linq2db/pull/5619))
- The LINQ expression mapping registry (`Expressions.MapMember` / `MapBinary`) is now thread-safe. Registering a custom member/binary mapping concurrently with query compilation (or from multiple threads) could previously corrupt the internal registry; registrations and lookups are now safe under concurrent access. ([#5623](https://github.com/linq2db/linq2db/pull/5623))
- Fixed a `LinqToDBException: Table not found` thrown while building SQL when a `.Concat(…)` (set-operation) result was `.Join(…)`-ed to another table used only for filtering — a regression from 5.x. The union now stays a proper derived table and the filtering join binds correctly. ([#5629](https://github.com/linq2db/linq2db/pull/5629))
- Fixed `ORDER BY` being dropped from `OrderBy(...).Distinct().Take(n)` and `...GroupBy(...).Take(n)` queries, which let `Take` / `Skip` return arbitrary rows. The ordering is now preserved when every column it references is produced by the `DISTINCT` projection or the `GROUP BY` keys. ([#5632](https://github.com/linq2db/linq2db/pull/5632))
- Fixed fluent `IsExpression` mapping on a nested property (e.g. `c => c.Address.Postcode`) throwing `LinqToDBException: Can't convert … to expression.` at query build. Nested-property computed columns now build and materialize correctly. ([#5635](https://github.com/linq2db/linq2db/pull/5635))
- `OptimizeForSequentialAccess` is now a per-context option (`LinqOptions.OptimizeForSequentialAccess`, with `DataOptions.UseOptimizeForSequentialAccess(...)`) instead of only a process-global static. This fixes an `InvalidOperationException` ("Invalid attempt to read from column ordinal … With CommandBehavior.SequentialAccess …") that could occur when a cached materialization plan compiled with the option off was reused by a context reading with `SequentialAccess` (or vice-versa) — sequential and non-sequential plans now occupy distinct query-cache slots. The global `Configuration.OptimizeForSequentialAccess` is kept as a back-compat default. ([#5639](https://github.com/linq2db/linq2db/pull/5639))
- Fixed the fluent `Sql.AnalyticFunctions.Lead(expr, nulls)` overload silently dropping its `IGNORE NULLS` / `RESPECT NULLS` argument (it emitted a plain `LEAD(expr)`); the modifier is now applied, matching the `FirstValue` / `LastValue` / `Lag` overloads that already did. ([#5644](https://github.com/linq2db/linq2db/pull/5644))
- Fixed a column that has a `ValueConverter` but no explicit `DataType` resolving its database type from the model member type (which usually has none), so it fell back to `Undefined` and dropped precision/scale/length facets. The DB type is now resolved from the converter's provider type — for example an F# `decimal option` now maps to the provider's `decimal(18,10)` instead of collapsing to a bare `Decimal` and truncating scale. ([#5645](https://github.com/linq2db/linq2db/pull/5645))
- Fixed an uncatchable `StackOverflowException` that could crash the process on deeply nested / recursive queries instead of recovering gracefully. The deep-recursion stack guard now probes the remaining stack more frequently, so it reliably switches to its thread-hop fallback (or throws a catchable `InsufficientExecutionStackException`) before the stack is exhausted. ([#5656](https://github.com/linq2db/linq2db/pull/5656))
- Fixed a concurrency bug where executing the same cached, parameter-dependent query on multiple threads at once could render corrupted SQL — table aliases and column names could be swapped or duplicated, surfacing as `42703 column does not exist` on PostgreSQL or as wrong results on other databases. Query alias finalization no longer mutates the shared cached statement, so a cached query is now safe to render concurrently. ([#5657](https://github.com/linq2db/linq2db/pull/5657))
- Fixed raw-SQL / `ToSqlQuery()` entity materialization that maps result columns by name returning defaults or failing on providers that force aliases on the root SELECT (SqlCe, YDB, Access): the root SELECT now keeps each column's physical name instead of renaming it to the member name, and colliding root columns are given unique aliases (e.g. `PersonID` / `PersonID_1`). ([#5657](https://github.com/linq2db/linq2db/pull/5657))
- Fixed the generated SQL differing between the direct and remote (LinqService) execution paths; table aliases are now uniquified per logical source rather than per table-source wrapper, so both paths produce identical aliasing. ([#5657](https://github.com/linq2db/linq2db/pull/5657))
- Fixed an `InvalidCastException` (a regression since 6.2.0) when `LoadWith` / `ThenLoad` was called on a plain `IQueryable` that isn't a linq2db query (e.g. `Enumerable.Empty<T>().AsQueryable()`). Synchronous enumeration of such a source now passes through to the original query (mirroring EF Core `Include`); async enumeration — and accessing the linq2db `DataContext`, `GetSqlQueries`, or the debug SQL view on it — now raises a clear `LinqToDBException` rather than the previous `InvalidCastException`. ([#5658](https://github.com/linq2db/linq2db/pull/5658))
- Raw SQL queries materialized into a record or constructor-based type — `Query<T>(string)`, `QueryToList` / `QueryToListAsync`, etc. — now bind result columns by the same rules as LINQ queries: a member's `[Column("some_column")]` name is authoritative and a `[ValueConverter]` on a constructor-bound column is applied. Previously a constructor / positional-record parameter was matched to a result column **by parameter name only**, so a `[Column("some_column")]`-mapped member came back `null`/default and its `[ValueConverter]` was never applied. ⚠ Because binding now follows the mapped column name, the previous workaround of aliasing a column to the member name (`select some_column as SomeColumn`) no longer binds — select the column under its mapped name instead. Duplicate or empty column names in a raw result set are tolerated. ([#5659](https://github.com/linq2db/linq2db/pull/5659))
- Fixed several table-per-hierarchy (single-table inheritance) defects, especially in hierarchies with an abstract intermediate class: sibling subtypes that map the same C# member to *different* physical columns now read and write correctly; an association declared on a derived type now emits the discriminator on its join (no spurious matches on non-matching rows); a base-typed insert writes shared and abstract-intermediate columns for every sibling subtype; and `OfType<TIntermediate>()` over an abstract intermediate now materializes the concrete subtypes instead of throwing "Cannot construct". ([#5661](https://github.com/linq2db/linq2db/pull/5661))
- Fixed enum-column null handling in association joins: an optional association whose join condition involves an enum column emitted `column <> 0` instead of `column IS [NOT] NULL` (the enum-to-`int` conversion was compared against `0` rather than null-checked), which polluted the join condition and could silently drop rows whose enum value equals its zero-valued member. The conversion-wrapped enum null check now correctly generates `IS [NOT] NULL`. ([#5667](https://github.com/linq2db/linq2db/pull/5667))
- Fixed a 6.x regression where a recursive CTE built with `db.GetCte<T>(anchor.Concat(recursive))` whose projection type had an `object`-typed member silently dropped columns from the CTE header — later references to the dropped columns then failed (`Invalid column name` on SQL Server, `no such column` on SQLite). A `string`-typed member worked; only `object`-typed members triggered it. Union-merged CTE columns now keep their tracking and resolve regardless of member type. ([#5680](https://github.com/linq2db/linq2db/pull/5680))
- Provider version auto-detection (the `AutoDetect` dialect path) opened a caller-supplied `DbConnection` to probe the server version and then failed to close it, even though linq2db was the one that had opened it. A connection handed to linq2db closed — e.g. EF Core's shared connection obtained via `context.CreateLinqToDBConnection()` — was opened for the probe and left open, staying pinned, which could break the owner's later operations (for example an EF Core `EnsureDeleted`/`EnsureCreated` cycle failing with a broken/socket connection). linq2db now closes the probe connection only when it opened it, and leaves an already-open connection untouched. ([#5691](https://github.com/linq2db/linq2db/pull/5691))
- Fixed cached queries producing wrong SQL on re-execution. Provider SQL rewrites could modify the cached statement in place instead of rebuilding it, so the second and later runs of a query saw an already-rewritten statement. Observed on Oracle (`COALESCE` character-set handling and `VALUES`-table queries, including through the remote `LinqService` context) and on Informix (casts on a parameter used more than once). ([#5723](https://github.com/linq2db/linq2db/pull/5723))
- Fixed `DistinctBy` failing with `Table not found for '...'` when operators preceded it in the query — most commonly a `Where`. On the `ROW_NUMBER` emulation path the preceding query state was dropped, taking the filter with it, and query building then failed. ([#5732](https://github.com/linq2db/linq2db/pull/5732))

#### LinqToDB F# Support

##### Added

- F# `'T option` and `'T voption` (value-option) columns now map automatically in the `linq2db.FSharp` package — after `.UseFSharp()`, option columns round-trip with no manual `MappingSchema` configuration: the *some* case (`Some`/`ValueSome`) stores the value and the *none* case (`None`/`ValueNone`) stores `NULL`. Value-typed options such as `int option` route through `Nullable<'T>`, so *none* is stored as `NULL` instead of the value-type default (previously an `int option` `None` was stored as `0`). Only options over a scalar element type are auto-mapped, and the column's DB type — including facets like decimal precision/scale and string length — is resolved from the element type against the connection's provider schema, so it matches the equivalent non-option column. Auto-mapping is a lower-priority fallback and never overrides mappings you've configured explicitly. ([#5624](https://github.com/linq2db/linq2db/pull/5624))

##### Fixed

- Fixed F# record-copy updates. Both `table.Update(fun r -> { r with Field = v })` and `query.Update(predicate, fun r -> { r with Field = v })` — including the async `UpdateAsync` variants — previously generated an `UPDATE` that wrote **every** column (including the primary key), which some providers reject. Only the changed (non-PK) column(s) are now written. ([#5627](https://github.com/linq2db/linq2db/pull/5627))

#### LinqToDB for EntityFramework

##### Added

- EF Core 10 keyed query filters and `IgnoreQueryFilters(IReadOnlyCollection<string>)` now flow through to linq2db's named query filters. See [details](#named-query-filters) below. ([#5525](https://github.com/linq2db/linq2db/pull/5525))
- Many-to-many (skip navigation) associations now translate to SQL. Queries over a many-to-many navigation backed by an implicit join table - e.g. `share.Users.Any(...)` and nested forms, plus `All`/`Count`/`SelectMany`, reverse-direction navigation, and `Include` eager loading - previously failed with "The LINQ expression could not be converted to SQL." Composite keys, self-referencing relationships, explicit join entities with payload, and multiple distinct relationships between the same entity pair are supported (multiple *implicit* relationships between the same pair throw a clear exception). EF Core 8/9/10; EF Core 3.1 unaffected. See [details](#ef-core-many-to-many-skip-navigation-translation) below. ([#5588](https://github.com/linq2db/linq2db/pull/5588))

##### Fixed

- Fixed a connection leak in the implicit EF Core helpers `ToLinqToDB()`, `DbSet.ToLinqToDBTable()` and `DbContext.GetTable<T>()`. These create an internal linq2db context that is never disposed, so it held the EF connection open until garbage collection. The internal context now releases the connection after each command (as EF Core itself does), closing only what linq2db opened, so an ambient transaction is unaffected. The public `CreateLinqToDBContext()` is unchanged. ([#5378](https://github.com/linq2db/linq2db/pull/5378))
- Fixed a fatal crash on Mono / Android (Native AOT) when reading the EF Core model metadata. Thanks to [Tim Haasdyk](https://github.com/myieye) ([#5546](https://github.com/linq2db/linq2db/pull/5546))
- Fixed linq2db's query cache missing on every `DbContext` when EF Core doesn't share its internal service provider across contexts — pooled contexts, `EnableServiceProviderCaching(false)`, or several providers in one app. Each context produced a fresh mapping-schema identity, so every query was recompiled per context instead of being reused. The schema is now shared across contexts of the same model, while different models — including custom `IModelCacheKeyFactory` and multi-tenant setups — still get separate schemas. ([#5695](https://github.com/linq2db/linq2db/pull/5695))

#### LinqToDB LINQPad Driver

##### Fixed

- Fixed the `linq2db.LINQPad` driver failing to install from LINQPad's NuGet package manager on macOS/Linux (reported as "No compatible assemblies found"). The driver installs again on every OS; the regression was introduced in 6.2.0. ([#5571](https://github.com/linq2db/linq2db/pull/5571))
- LINQPad driver: fixed the Database Type and Provider dropdowns in the dynamic-connection dialog being clipped on narrower dialog widths; they now fill the available row width instead of using a fixed size. ([#5579](https://github.com/linq2db/linq2db/pull/5579))

#### LinqToDB CLI

##### Added

- Scaffolding can emit `[GetSqlDecimal]` for SQL Server `decimal` columns with precision or scale outside CLR `decimal` limits — `--sqlserver-decimal-overflow-protection` (off by default), or `DataModelOptions.GenerateSqlServerDecimalOverflowProtection` when driving the scaffolder in code. ([#5605](https://github.com/linq2db/linq2db/pull/5605))
- New `linq2db.cli` commands for working against a database directly, aimed at AI agent hosts as well as interactive use: `query` (one read-only SQL statement → JSON, JSON-table or CSV), `execute` (one write-capable statement, refused unless the selected profile sets `enableExecute`), `schema` (provider-aware object metadata as JSON, with schema/catalog/table filters and a compact `names` detail level), `config-init` (create or update a JSON connection profile), `credentials` (encrypted credential profiles via Windows Credential Manager, scoped to the creating account), `skill` (prints agent-oriented usage), and `mcp` — a STDIO Model Context Protocol server exposing `linq2db_info`, `linq2db_schema`, `linq2db_query`, `linq2db_execute` and `linq2db_skill`. Safe defaults throughout: read-only SQL guardrails on `query`, `execute` off unless explicitly enabled at both MCP startup and in the profile, and an 8 MiB MCP response cap that truncates on a row boundary rather than emitting invalid JSON. See [details](#linq2db-cli-query-and-mcp-server) below. ([#5678](https://github.com/linq2db/linq2db/pull/5678))

#### Analyzers

##### Added

- New analyzer package `linq2db.Analyzers`, with its first rule `L2DB1001`. It flags the legacy `Sql.Ext` window-function API — `Sql.Ext.<Fn>(...).Over()…ToValue()`, i.e. `LinqToDB.AnalyticFunctions` — as superseded by `Sql.Window`, which is slated for removal in a future major release. Reported at `Info` severity and enabled by default, with a companion code fix ("Convert to Sql.Window API") that rewrites mechanically-convertible chains and supports Fix-All across a document. Aggregates without `.Over()` are not reported — they aren't window functions, so there's no `Sql.Window` target to migrate to. Documented at [L2DB1001](https://github.com/linq2db/linq2db/wiki/L2DB1001). See [details](#linq2db-analyzers) below. ([#5703](https://github.com/linq2db/linq2db/pull/5703))
- The analyzer rules ship with the library: `linq2db` now depends on `linq2db.Analyzers`, so they arrive with a direct `linq2db` reference or through any satellite package (`linq2db.Tools`, `linq2db.Remote.*`, `linq2db.Extensions`, `linq2db.Compat`, `linq2db.Scaffold`, `linq2db.EntityFrameworkCore`) with no extra reference — on by default. Requires .NET SDK 8.0+ or Visual Studio 2022 17.8+; older hosts skip the rules silently. Severity is configurable per rule, or for every linq2db rule at once via `dotnet_analyzer_diagnostic.category-LinqToDB.severity`, and `<EnableLinqToDBAnalyzers>false</EnableLinqToDBAnalyzers>` disables them entirely. Reference `linq2db.Analyzers` directly only to run the migration rule against an older linq2db (6.1–6.3) when planning an upgrade. ([#5720](https://github.com/linq2db/linq2db/pull/5720))

#### ClickHouse

##### Added

- new ClickHouse `GLOBAL ALL` join hint (`JoinGlobalAllHint()` / `ClickHouseHints.Join.GlobalAll`), completing the GLOBAL + strictness join-hint combinations. ([#5555](https://github.com/linq2db/linq2db/pull/5555))

##### Fixed

- a standalone `ALL` ClickHouse join hint produced malformed SQL (it was matched as a compound prefix rather than a standalone strictness modifier); it now emits correctly. ([#5555](https://github.com/linq2db/linq2db/pull/5555))

##### Deprecated

- the compound `All*` join-hint aliases (`AllOuter`, `AllSemi`, `AllAnti`, …) are deprecated in favor of the standalone strictness hints (`OUTER`, `SEMI`, `ANTI`, …), matching ClickHouse's actual two-axis strictness (ALL/ANY/SEMI/ANTI/ASOF) + distribution (GLOBAL) syntax. The aliases still work for backward compatibility; recompiling maps them to the corrected standalone hints. ([#5555](https://github.com/linq2db/linq2db/pull/5555))

#### DB2

##### Fixed

- Fixed reading a DB2 `DECFLOAT` column holding an IEEE special value (`Infinity` / `-Infinity` / `NaN`) throwing `LinqToDBConvertException` / `FormatException` — such values arise naturally from division by zero in `DECFLOAT` (e.g. `RATIO_TO_REPORT` over a zero-sum partition). They now materialize correctly: `double` / `float` targets keep the special value; `decimal` and integral targets yield `null` (nullable) or the default. Finite values still round-trip exactly. ([#5669](https://github.com/linq2db/linq2db/pull/5669))

#### Firebird

##### Added

- Added `FirebirdTools.ClearPool(DbConnection)` and `FirebirdTools.ClearPool(string connectionString)` to clear the connection pool for a single Firebird database, complementing the existing process-wide `FirebirdTools.ClearAllPools()`. Use it to release one database's pooled connections — e.g. after a `DROP`/`CREATE` that Firebird would otherwise block with *object TABLE is in use* — without evicting every other Firebird pool in the process. ([#5689](https://github.com/linq2db/linq2db/pull/5689))

#### Informix

##### Fixed

- Informix: fixed a nullable-projected `Sum` (e.g. `Sum(x => (decimal?)x)`) over a non-nullable column where the generated null-guard was a no-op (`Nvl(x, NULL)`) that didn't apply the intended default; the aggregate now behaves as intended. The same no-op null-guard was also fixed in the Access `IIF` fold. ([#5568](https://github.com/linq2db/linq2db/pull/5568))

#### Oracle

##### Fixed

- Oracle: fixed `DateTimeOffset` value handling. The time-zone offset is now preserved when generating `TIMESTAMP WITH TIME ZONE` literals (previously the offset was discarded and replaced with `+00:00`, corrupting the stored instant), and casts that only change a date/timestamp's precision or add/remove a time zone now emit a plain `CAST` instead of malformed `TO_TIMESTAMP`/`TO_DATE` calls. `DateTimeOffset` values bound to a zone-less `TIMESTAMP` column are normalized to UTC. Date/datetime-to-string casts targeting an `NChar`/`NVarChar` type now emit `TO_NCHAR` (rather than `TO_CHAR`), and `DateOnly` is covered by the same cast path. ([#5466](https://github.com/linq2db/linq2db/pull/5466))
- Fixed an Oracle `UPDATE` with a correlated row-subquery setter (e.g. a non-PK join narrowed by `.Single()`) generating invalid SQL. The correlated subquery now lifts cleanly instead of leaving a dangling self-reference. Thanks to [jods](https://github.com/jods4). ([#5584](https://github.com/linq2db/linq2db/pull/5584))
- Fixed long string and XML values being bound as ordinary string parameters, which failed for `OracleXmlTable` and other long-string parameter scenarios. A string parameter with no explicit data type whose length reaches `OracleOptions.MaxStringParameterLength` (new, default `4000`) is now bound as `NText`/NCLOB; set it to `null` to disable the inference. This applies to raw SQL and `DataParameter` values — a LINQ-generated parameter is typed from its column or CLR type, so it never reaches the inference and is unaffected. ([#5600](https://github.com/linq2db/linq2db/pull/5600))

#### PostgreSQL

##### Added

- Added PostgreSQL 19 support — new `v19` dialect (`ProviderName.PostgreSQL19`), server-version detection and config-string matching. On PostgreSQL 19 the `FIRST_VALUE`/`LAST_VALUE`/`LEAD`/`LAG`/`NTH_VALUE` window functions now emit `IGNORE NULLS` / `RESPECT NULLS` in PostgreSQL's SQL-standard outside-parens form (`FIRST_VALUE(x) IGNORE NULLS`), instead of the Oracle-style inside-parens form it rejects with a `42601` syntax error. ([#5644](https://github.com/linq2db/linq2db/pull/5644))
- PostgreSQL 11 and 12 support — new `v11`/`v12` dialects (`ProviderName.PostgreSQL11`/`PostgreSQL12`), server-version detection and config-string matching, plus version-aware gating of window-function capabilities: constructs a given server doesn't support — frame `GROUPS`/`EXCLUDE` before 11, `WITHIN GROUP` ordered-set and hypothetical-set aggregates before 9.5, `AS [NOT] MATERIALIZED` CTEs before 12 — are now rejected up front with a descriptive `LinqToDBException` instead of emitting SQL the server rejects. ([#5687](https://github.com/linq2db/linq2db/pull/5687))

##### Fixed

- Fixed PostgreSQL schema discovery misclassifying identity columns: a `nextval(...)` call embedded in a larger default expression (e.g. `'PREFIX_' || nextval(...)`) is no longer treated as a native identity column — only a direct serial-style `DEFAULT nextval(...)` still is. A true identity column is preferred when present, and when a table has multiple sequence-backed defaults a primary-key column is selected first. ([#5647](https://github.com/linq2db/linq2db/pull/5647))

#### SQL Server

##### Added

- New `[GetSqlDecimal]` attribute for SQL Server `decimal` columns whose precision or scale falls outside the CLR `decimal` range. Reading such a column previously threw `OverflowException`; with the attribute the value is read through SQL Server's own `SqlDecimal` and its scale reduced to fit, which can round away least-significant digits. A value whose magnitude still exceeds `decimal.MaxValue` continues to throw. Opt-in per column, and applied only when the provider is SQL Server. ([#5605](https://github.com/linq2db/linq2db/pull/5605))

##### Fixed

- Fixed schema load returning no views at all on SQL Server 2016+ when the `IgnoreSystemHistoryTables` option was enabled — the temporal-history filter excluded views along with history tables, so scaffolding, T4 and `linq2db.cli` produced a model with no views. Affects `GetSchemaOptions.IgnoreSystemHistoryTables`, the scaffold `--ignore-system-history-tables` option, and the CLI `schema` command. ([#5734](https://github.com/linq2db/linq2db/pull/5734))

#### SQLite

##### Fixed

- SQLite schema provider (`GetSchema()`) now returns tables and views in a deterministic, platform-independent order; previously the order followed whatever the native SQLite library returned and could differ between platforms and SQLite versions. ([#5606](https://github.com/linq2db/linq2db/pull/5606))

#### Sybase ASE

##### Improved

- Sybase ASE now emits the ANSI `||` operator for string concatenation instead of the Transact-SQL `+` operator, matching the SQL shape used by the other `||` providers. Results are unchanged - `||` behaves identically to `+` on ASE (neither propagates NULL, and both still cast non-character operands), so this is a SQL-text-only change. ([#5569](https://github.com/linq2db/linq2db/pull/5569))

##### Fixed

- Sybase ASE: `Sql.Concat` no longer emits redundant `IS NULL` guards on operands that can't be NULL (string literals, non-nullable columns), producing much cleaner SQL. Regression introduced in a 6.4.0 preview. ([#5566](https://github.com/linq2db/linq2db/pull/5566))

#### YDB

##### Added

- The YDB provider is now fully implemented and supported (previously experimental) — schema API, CLI scaffolding, LINQPad driver, and broad LINQ/translation coverage. See [details](#ydb-data-provider) below. ([#5564](https://github.com/linq2db/linq2db/pull/5564))

<!-- rn:deepdive:#5450 -->
#### Eager-loading strategies (KeyedQuery / CteUnion)

```csharp
var query =
    from c in db.Companies
    orderby c.Id
    select new
    {
        c.Id, c.Name,
        Departments = db.Departments
            .Where(d => d.CompanyId == c.Id)
            .Select(d => new { d.Id, Employees = db.Employees.Where(e => e.DepartmentId == d.Id).ToList() })
            .ToList(),
    };

query.WithKeyedLoadStrategy().ToList();  // buffer parents, load children by key
query.WithUnionLoadStrategy().ToList();  // single UNION ALL CTE across all levels
```
With **KeyedQuery** the parent query runs once and each child level loads with `WHERE key IN (…)`:
```sql
SELECT [Id], [Name] FROM [Company]
SELECT ... FROM [Department] WHERE [CompanyId]    IN (1)
SELECT ... FROM [Employee]   WHERE [DepartmentId] IN (1, 2)
```
**CteUnion** instead emits a single query whose CTEs carry every level and are combined with `UNION ALL` (marked `AS MATERIALIZED` on PostgreSQL 12+, SQLite 3.35+, and ClickHouse where a CTE is referenced more than once).

<!-- rn:deepdive:#5468 -->
#### Window functions

```csharp
var query =
    from t in db.Employees
    let wnd = Sql.Window.DefineWindow(f => f.PartitionBy(t.Department).OrderBy(t.HireDate))
    select new
    {
        RN         = Sql.Window.RowNumber(f => f.PartitionBy(t.Department).OrderBy(t.HireDate)),
        RunningSum = Sql.Window.Sum(t.Salary, f => f.UseWindow(wnd)),
        NextSalary = Sql.Window.Lead(t.Salary, 1, 0m, f => f.UseWindow(wnd)),
        AvgActive  = Sql.Window.Average(t.Salary, f => f.Filter(t.IsActive).UseWindow(wnd)),
        MinFirst   = Sql.Window.Min(t.Salary, f => f.KeepFirst().OrderBy(t.HireDate).PartitionBy(t.Department)),
    };
```

Frames use explicit boundary direction, so same-direction frames are expressible:

```csharp
Sql.Window.Sum(t.Value, f => f.OrderBy(t.Id).RowsBetween.ValuePreceding(1).And.CurrentRow)
Sql.Window.Sum(t.Value, f => f.OrderBy(t.Id).RowsBetween.Unbounded.And.Unbounded.ExcludeTies())
```

`FILTER (WHERE …)` is native on PostgreSQL and emulated via `CASE WHEN` elsewhere; `NULLS FIRST/LAST` is native on PostgreSQL, Oracle and Firebird 3+ and emulated elsewhere. Configured across SQL Server, PostgreSQL, Oracle, MySQL/MariaDB, ClickHouse, SQLite, Firebird, DB2, SAP HANA, Informix, YDB, Access, SqlCe and Sybase — unsupported features raise a descriptive exception rather than emitting invalid SQL.

<!-- rn:deepdive:#5482 -->
#### Fluent Upsert + entity Update/Insert APIs

```csharp
// Upsert — insert or update a single entity
db.Users.Upsert(user, u => u
    .Match ((t, s) => t.Id == s.Id)
    .Insert(i => i.Set(x => x.CreatedAt, () => DateTime.UtcNow))
    .Update(v => v.Set(x => x.UpdatedAt, () => DateTime.UtcNow)));

// Upsert — bulk from a collection or query
db.Users.Upsert(items, u => u.Match((t, s) => t.Id == s.Id));  // IEnumerable<T>
db.Users.Upsert(query, u => u.Match((t, s) => t.Id == s.Id));  // IQueryable<T>

// Entity Insert / Update — column values come from the entity; .Set / .Ignore overlay
db.Users.Insert(user, b => b.Set(x => x.CreatedAt, () => DateTime.UtcNow).Ignore(x => x.Notes));
db.Users.Update(user, b => b.Set(x => x.UpdatedAt, () => DateTime.UtcNow));  // PK match
```
The entity `Insert` / `Update` overloads compile to the existing single-statement `INSERT` / `UPDATE` and work on every provider, including entity types without a public parameterless constructor (positional records, ctor-only DTOs).

<!-- rn:deepdive:#5525 -->
#### Named query filters

```csharp
builder.Entity<Order>()
    .HasQueryFilter("soft-delete", (o, dc) => !o.IsDeleted)
    .HasQueryFilter("tenant",      (o, dc) => o.TenantId == ((MyDb)dc).TenantId);

// disable just the tenant filter for this query
db.Orders.IgnoreFilters(new[] { "tenant" }).ToList();

// disable a filter only for specific entity types
db.Orders.IgnoreFilters(new[] { "soft-delete" }, typeof(Order)).ToList();
```

<!-- rn:deepdive:#5561 -->
#### NULLS FIRST / LAST ordering

Control where `NULL` values sort, per ordering key:

```cs
// Place NULLs last for this key
db.Table.OrderBy(x => x.Value, Sql.NullsPosition.Last)
        .ThenBy(x => x.Id);

// NULLs first on a descending key
db.Table.OrderByDescending(x => x.Value, Sql.NullsPosition.First);

// Default placement for every ordering key that doesn't specify one
var options = new DataOptions().UseDefaultNullsPosition(Sql.NullsPosition.Last);
// or globally:
Configuration.Sql.DefaultNullsPosition = Sql.NullsPosition.Last;
```

Use `Sql.NullsPosition.None` to opt a single key out of the configured default. The position is rendered as a native `NULLS FIRST` / `NULLS LAST` token where supported and emulated with a leading `CASE` key elsewhere, so the result is the same regardless of provider.

<!-- rn:deepdive:#5564 -->
#### YDB data provider

The experimental YDB provider is now first-class. Provider name: `YDB`. Supported on `net8.0`, `net9.0`, `net10.0`.

**Supported features:**

- Full CRUD with the usual LINQ surface
- CTE, window/analytic functions, `IS DISTINCT FROM`, row-constructor comparisons (equality / comparison / `BETWEEN` / `IN`)
- `RETURNING` for identity columns
- Schema introspection (tables, columns, primary keys)
- Bulk copy: native appender (`BulkUpsert`) with automatic fallback to multi-row `INSERT`
- `string.Join` / `StringAggregate` translation
- Temporary tables (`CREATE ... IF NOT EXISTS` / `DROP ... IF EXISTS`)
- Scaffold using the `linq2db.cli` tool
- LINQPad support

<!-- rn:deepdive:#5588 -->
#### EF Core many-to-many (skip navigation) translation

Skip navigations backed by an implicit join table now work through `ToLinqToDB()`:

```cs
// EF Core model: Share <-> User many-to-many via skip navigation
var shares = ctx.Shares
    .Where(share => share.Users.Any(u => u.Name == "admin"))
    .ToLinqToDB()
    .ToList();
```

Previously threw "The LINQ expression could not be converted to SQL." `Include` eager loading of the navigation is also supported. Known limitation: an entity whose key is field-mapped or shadow (no CLR property) cannot be used as the query root for eager loading.

<!-- rn:deepdive:#5648 -->
#### UUIDv7 generation

```cs
var id  = db.GetTable<Person>().Select(_ => Sql.NewGuid7()).First();
var id2 = db.GetTable<Person>().Select(_ => Guid.CreateVersion7()).First(); // .NET 9+
```

Native server-side functions: PostgreSQL 18+ `uuidv7()`, DuckDB 1.3.0+ `uuidv7()`, ClickHouse 24.5+ `generateUUIDv7()`, MariaDB 11.7+ `UUID_v7()`. PostgreSQL is version-aware — below 18 it falls back to client-side generation. For DuckDB, ClickHouse and MariaDB the native function is emitted unconditionally (linq2db doesn't probe the server version), so targeting a server older than the function's introduction raises a server-side error rather than falling back. Providers without any native generator always produce the v7 GUID client-side.

<!-- rn:deepdive:#5678 -->
#### linq2db CLI query and MCP server

`linq2db.cli` can now read and query a database directly. For agent hosts, `mcp` is the intended integration; `query` covers direct invocation where MCP isn't available or allowed.

Point the MCP server at a config file that names the database profiles:

```json
{
  "mcp": {
    "title": "Audiobooks Database",
    "description": "Application database containing audiobooks, authors, narrators, users, and listening history."
  },
  "default": {
    "provider": "PostgreSQL",
    "connectionStringEnv": "AUDIOBOOKS_CONNECTION_STRING"
  }
}
```

Agents work `linq2db_info` (profiles, providers, dialects, safety rules, response limit) → `linq2db_schema` (tables, views, columns, keys, relationships) → `linq2db_query` (one read-only statement), with `linq2db_skill` returning the full guide. The same profiles drive direct use:

```
dotnet linq2db schema --detail-level names
dotnet linq2db query --sql "select count(*) from Orders" --output json-table
```

Prefer `connectionStringEnv` to a literal connection string — a literal is written into the generated config and warns on `stderr`. Register the executable once per project or database domain, each with its own `--config`, so agents get a clear boundary. `execute` is refused unless the profile sets `enableExecute` *and* MCP was started with `--enable-execute-tool`. CSV output is for machine processing only and deliberately does no spreadsheet escaping, so a value starting with `=`, `+`, `-` or `@` may be read as a formula — use `json` or `json-table` for untrusted data.

<!-- rn:deepdive:#5703 -->
#### linq2db analyzers

linq2db now ships Roslyn analyzers with the library. The first rule, `L2DB1001`, flags the legacy `Sql.Ext` window-function API, and a code fix migrates it:

```cs
// reported by L2DB1001
long M(int x) => Sql.Ext.RowNumber().Over().PartitionBy(x).OrderBy(x).ToValue();

// after "Convert to Sql.Window API"
long M(int x) => Sql.Window.RowNumber(f => f.PartitionBy(x).OrderBy(x));
```

The rule reports at `Info` and only fires on chains containing `.Over()` — a plain `Sql.Ext.Sum(x).ToValue()` aggregate is not a window function and has no migration target, so it is left alone. Fix-All rewrites every flagged chain in a document in one pass. A chain that has no mechanical equivalent, such as one carrying `.Filter(...)`, is reported but not rewritten.

Severity is settable per rule, or for every linq2db rule at once:

```editorconfig
dotnet_diagnostic.L2DB1001.severity = warning
dotnet_analyzer_diagnostic.category-LinqToDB.severity = error
```

To turn the rules off entirely:

```xml
<PropertyGroup>
  <EnableLinqToDBAnalyzers>false</EnableLinqToDBAnalyzers>
</PropertyGroup>
```

Requires .NET SDK 8.0+ or Visual Studio 2022 17.8+; older hosts skip the analyzers silently rather than failing the build. Referencing `linq2db.Analyzers` directly is only needed to run the migration rule against linq2db 6.1–6.3 when planning an upgrade.

### Release 6.3.0

**LinqToDB**

- [#3040](https://github.com/linq2db/linq2db/pull/3040): added `Enum.HasFlag` translation to SQL
- [#4325](https://github.com/linq2db/linq2db/pull/4325): [@darko1979](https://github.com/darko1979) added [support](https://github.com/linq2db/linq2db/pull/5395) for `IgnoreConflicts` option to `MultipleRows` mode of `BulkCopy` API for `MySql`, `MariaDB`, `PostgreSQL` and `SQLite`
- [#5154](https://github.com/linq2db/linq2db/pull/5154): fix `InvalidOperationException` from `ToSqlQuery` when `SqlQueryDependentParams` attribute used in mappings, obsolete `SqlQueryDependentParamsAttribute`
- [#5302](https://github.com/linq2db/linq2db/pull/5302): fix query caching issue for `PostgreSQL` with array parameters. Array, `List<T>` and `IReadOnlyList<T>` types now recognized as scalars for `PostgreSQL`
- [#5309](https://github.com/linq2db/linq2db/pull/5309): [SQL Server][Firebird] fix conversion to date for expression with `DbType="some_type"` set in mappings
- [#5323](https://github.com/linq2db/linq2db/pull/5323): [PostgreSQL, ClickHouse, DuckDB, SQLite] add explicit configuration API for `CTE` materialization using `AsCte` overload with configuration builder parameter. Examples:
  - `AsCte(c => c.IsMaterialized())`
  - `AsCte(c => c.IsMaterialized(false))`
  - `AsCte(c => c.IsMaterialized().HasName("custom_cte_name"))`
- [#5355](https://github.com/linq2db/linq2db/pull/5355): fix issue with associations discovery on interfaces
- [#5404](https://github.com/linq2db/linq2db/pull/5404): fix SQL generation for subqueries, that select nullable aggregates using non-null returning API
- [#5413](https://github.com/linq2db/linq2db/pull/5413): fix `UPDATE FROM` translation regressions
- [#5427](https://github.com/linq2db/linq2db/pull/5427): fix remaining issues with `null` handling by `ValueConverter` for non-nullable value type
- [#5429](https://github.com/linq2db/linq2db/pull/5429): fix `StackOverflowException` due to use of `AsQueryable` calls
- [#5434](https://github.com/linq2db/linq2db/pull/5434): fix value converters support in `Sql.Row`
- [#5443](https://github.com/linq2db/linq2db/pull/5443): [Oracle] improve `COALESCE` parameter type inference
- [#5444](https://github.com/linq2db/linq2db/pull/5444): [ClickHouse] add missing whitespace before table hint
- [#5445](https://github.com/linq2db/linq2db/pull/5445): fix predicate optimization for `NULL` checks
- [#5447](https://github.com/linq2db/linq2db/pull/5447): fix SET operators flattening
- [#5454](https://github.com/linq2db/linq2db/pull/5454): type conversion handling fix
- [#5457](https://github.com/linq2db/linq2db/pull/5457): fix too aggressive column removal for `CTE`
- [#5458](https://github.com/linq2db/linq2db/pull/5458): fix issue with member access translation for SET columns
- [#5463](https://github.com/linq2db/linq2db/pull/5463): several fixes to [Create/DropTable] APIs
  - [#798](https://github.com/linq2db/linq2db/pull/798): implement `DropTable(throwExceptionIfNotExists: false)` parameter to hide only non-existing table errors, not all errors. Thanks to [Carlos Salazar](https://github.com/xamtam54) for PR
  - [Oracle] fixed issue when drop of global temp table did nothing if table had data. Now it will truncate table data before drop
  - [SAP HANA] handle table not found errors on drop on SQL level for `throwExceptionIfNotExists: false`
  - [DB2][Firebird][SAP HANA][Oracle] properly escape sql statements in `EXECUTE` blocks, generated on table create/drop operations
- [#5480](https://github.com/linq2db/linq2db/pull/5480): fix query caching issues with `FromSql` queries
- [#5504](https://github.com/linq2db/linq2db/pull/5504): internal refactoring of string concatenation. Many translation bugs fixed, added support for missing `string.Concat` overloads
- [#5505](https://github.com/linq2db/linq2db/pull/5505): don't apply `ValueConverter` to database-sourced values in UPDATE setters
- [#5510](https://github.com/linq2db/linq2db/pull/5510): fix interface member access translation issue
- [#5515](https://github.com/linq2db/linq2db/pull/5515): review and improve `TrimStart`/`TrimEnd` overloads mappings for all providers
- [#5519](https://github.com/linq2db/linq2db/pull/5519): [Access] fix re-surfaced compatibility issues with non-EN locales, fix issue for boolean conversion for read from DB could be applied in wrong places
- [#5522](https://github.com/linq2db/linq2db/pull/5522): fix exists over set (e.g. `EXISTS (... UNION ...)`) queries generation

##### `AsQueryable` parameterization control

Closes [#5424](https://github.com/linq2db/linq2db/pull/5424).

New overload of `AsQueryable` lets you choose how each column of an `IEnumerable<T>` is rendered into the `VALUES (...)` clause - as SQL parameters or inlined literals - with per-column overrides:

```cs
data.AsQueryable(db, b => b.Parameterize())
data.AsQueryable(db, b => b.Inline())
data.AsQueryable(db, b => b.Parameterize().Except(p => p.Id))
data.AsQueryable(db, b => b.Inline().Except(p => p.Address.Zip))
```

The builder is type-safe: `Parameterize()` / `Inline()` must come first, after which only `Except(...)` is available - invalid combinations don't compile.

Provider notes:
- **DB2**: parameter cells inside `VALUES` are wrapped in `CAST(@p AS <type>)` to satisfy SQL0418N.
- **ClickHouse**: parameterized `VALUES` is not supported and is skipped.

##### Improved `Now` / `UtcNow` translation with timezone awareness

Closes [#5436](https://github.com/linq2db/linq2db/pull/5436).

Server-side translation of `DateTime.Now`, `DateTime.UtcNow`, `DateTimeOffset.Now`, and `DateTimeOffset.UtcNow` is now distinct per variant, so providers that store offset (Oracle, PostgreSQL, Firebird 4+, DB2 z/OS, …) preserve timezone information instead of silently dropping it.

Behavior:

- Providers with native timezone support emit the correct expression for each of the four variants.
- Providers without timezone support don't error — `DateTimeOffset.Now` / `UtcNow` are gracefully downgraded to their `DateTime` equivalents.
- `Sql.CurrentTimestamp` / `Sql.CurrentTimestamp2` are now XML-documented.

Bug fixes uncovered along the way:

- **Oracle**: `DateTimeOffset.Now` no longer round-trips through `sys_extract_utc`, which was discarding the offset and corrupting `TIMESTAMP WITH TIME ZONE` writes.
- **SQLite**: `DateTime.Now` previously produced UTC time; now correctly returns local.

##### DuckDB data provider

Thanks to [@stdray](https://github.com/stdray) for implementing it.

Closes [#5451](https://github.com/linq2db/linq2db/pull/5451).

New first-class provider for [DuckDB](https://duckdb.org/) — an in-process analytical database with PostgreSQL-compatible SQL — built on top of [DuckDB.NET](https://github.com/Giorgi/DuckDB.NET).

Provider name: `DuckDB`. Supported on `net8.0`, `net9.0`, `net10.0`.

**Supported features:**

- Full CRUD with the usual LINQ surface
- CTE, window/analytic functions, `LATERAL` (CROSS/OUTER APPLY), `IS DISTINCT FROM`, row-constructor comparisons
- SQL `MERGE` (WHEN MATCHED / WHEN NOT MATCHED)
- `INSERT ... ON CONFLICT DO UPDATE/NOTHING` (`InsertOrUpdate`)
- `RETURNING` for identity columns
- Schema introspection (tables, columns, primary keys)
- Bulk copy: multi-row `INSERT` and native `DuckDBAppender` (provider-specific) with automatic fallback
- `STRING_AGG` translation for `string.Join` / `StringAggregate`
- Temporary tables (`CREATE IF NOT EXISTS` / `DROP IF EXISTS`)
- Scaffold using `linq2db.cli` tool
- LinqPAD support

**LinqToDB for EntityFramework**

- [#5439](https://github.com/linq2db/linq2db/issues/5439): [SqlServer] detect fields, defined using `UseSequence` API, as identity fields

**LinqToDB F# Support**

- [#5430](https://github.com/linq2db/linq2db/pull/5430):
  - [#5428](https://github.com/linq2db/linq2db/pull/5428): fix compatibility with `FSharp.Core` 10.1.x
  - fix record mapping issues for members with case-only name distinctions

**LinqToDB CLI**

PR [#5539](https://github.com/linq2db/linq2db/pull/5539).

### Per-RID packaging

`linq2db.cli` now ships as **per-RID tool packages** ([.NET 10 SDK feature](https://learn.microsoft.com/en-us/dotnet/core/tools/rid-specific-tools)). `dotnet tool install -g linq2db.cli` auto-selects the variant matching your SDK architecture. RIDs: `win-x64`, `win-x86`, `win-arm64`, `linux-x64`, `linux-arm64`, `osx-arm64`, `osx-x64`.

### Breaking: `--architecture` scaffold option removed

Bitness is fixed at install time, not per-invocation. Use `dotnet tool install -g linq2db.cli --arch x86` for 32-bit. Only `Microsoft.Jet.OLEDB` strictly requires `win-x86`; `Microsoft.ACE.OLEDB`, SQL Server Compact Edition, and SAP HANA just need the tool bitness to match the installed driver bitness. To keep both x86 and x64 available, install each via `--tool-path <dir>` (`-g` allows only one).

### New: `Microsoft.Jet.OLEDB` x86 detection

The Access scaffold now errors with a clear x86-variant hint when the connection string requests Jet and the current process isn't 32-bit, instead of failing deep inside the OLE DB factory load.

***

### Release 6.2.1

**LinqToDB**

- [#5284](https://github.com/linq2db/linq2db/pull/5284): multiple fixes to generated SQL
  - [#5283](https://github.com/linq2db/linq2db/pull/5283): fix translation issues for nested associations
  - fix issues with `UPDATE` queries with sub-queries in setters
  - fix `COALESCE` translation
  - improve joins optimization and unnesting, detect more cases when `LEFT JOIN` could be promoted to `INNER JOIN`
- [#5411](https://github.com/linq2db/linq2db/pull/5411): fix behavior of `CompareNulls.LikeSqlExceptParameters` option
- [#5416](https://github.com/linq2db/linq2db/pull/5416): fix `null` conversion to mapped enum
- [#5417](https://github.com/linq2db/linq2db/pull/5417): ignore table filters for `Drop` and `Truncate` table operations
- [#5420](https://github.com/linq2db/linq2db/pull/5420): fix invalid SQL generation for `INSERT` with sub-query setters in some cases
- [#5423](https://github.com/linq2db/linq2db/pull/5423): fix cases where `ORDER BY` generated in subqueries, that doesn't support it

**LinqToDB LINQPad Driver**

- [#5421](https://github.com/linq2db/linq2db/pull/5421): re-fix issue with settings dialog crashing on opening

***

### Release 6.2.0

**LinqToDB**

- [#5227](https://github.com/linq2db/linq2db/pull/5227): [ClickHouse] fix compatibility with `ClickHouse.Driver` `0.9.0`
- [#5256](https://github.com/linq2db/linq2db/pull/5256): fix invalid SQL generation for nested aggregations
- [#5258](https://github.com/linq2db/linq2db/pull/5258): binary/unary operators mapping improvements
  - [#5254](https://github.com/linq2db/linq2db/pull/5254), [#5259](https://github.com/linq2db/linq2db/pull/5259): fix regressions in handling of custom operators in mapping
  - add/fix support for custom operators mapping. Now you can map them using `Sql.ExpressionAttribute`, `MethodExpressionAttribute` or `IMemberTranslator` (you can see mapping examples in [tests](https://github.com/linq2db/linq2db/blob/master/Tests/Linq/Linq/OperatorsTests.cs)). Note that in general you don't need to map custom operators if their logic follow logic of mapped binary or unary operation. But if it implements non-standard behavior, which you want to reproduce n SQL, then you must provde corresponding mapping for `LINQ to DB`
- [#5259](https://github.com/linq2db/linq2db/pull/5259): adding conversion to `DataParameter` to mapping schema for struct type will automatically add it also for nullable struct type if such conversion is not registered already
- [#5262](https://github.com/linq2db/linq2db/pull/5262): some internal optimizations
- [#5263](https://github.com/linq2db/linq2db/pull/5263): fix `Sql.CurrentTimestamp2` translation regression
- [#5264](https://github.com/linq2db/linq2db/pull/5264):
  - fix `ToString` implementation for string-based enums
  - obsolete `bool Configuration.UseEnumValueNameForStringColumns` option as it doesn't have any effect
  - improve performance of enum mapping
  - [Oracle] map `DataType.NVarChar` to ``NVARCHAR2` type and fix discovered issues with `NVARCHAR2` handling
- [#5266](https://github.com/linq2db/linq2db/pull/5266): fix mapping of composite properties with overlapping names
- [#5268](https://github.com/linq2db/linq2db/pull/5268): remove unnecessary subquery nesting for `IN` predicate query
- [#5269](https://github.com/linq2db/linq2db/pull/5269): don't force translated methods conversion to SQL if they could be evaluated on client as parameters or literals
- [#5272](https://github.com/linq2db/linq2db/pull/5272): [DB2][Firebird] add decimal type facets population from value
- [#5274](https://github.com/linq2db/linq2db/pull/5274): fix support for inhertance mapping of hierarchies wth 16+ types
- [#5285](https://github.com/linq2db/linq2db/pull/5285): fix scalars support by `FromSql` API
- [#5289](https://github.com/linq2db/linq2db/pull/5289): fix `InsertOrUpdate` API use for tables with query filter
- [#5291](https://github.com/linq2db/linq2db/pull/5291):
  - [#5286](https://github.com/linq2db/linq2db/pull/5286): implement bitwise not (`~`) translation for all providers
  - improve parameter database type inference for unmapped types with mapped underlying type (e.g. enums or nullable structs)
  - [Access][MySQL] fix bitwise OR (`|`) operator precedence
  - fix/improve some binary operation optimizations
- [#5297](https://github.com/linq2db/linq2db/pull/5297): `Sql.DateAdd` will not accept `DayOfYear` and `WeekDay` date part argument values anymore. Before they were treated in same way as `Day` date part value
- [#5301](https://github.com/linq2db/linq2db/pull/5301): fix `ArgumentException : must be reducible node` error
- [#5304](https://github.com/linq2db/linq2db/pull/5304): fix handling of entites that implement `Enity : IEnumerable<Entity>` interface
- [#5307](https://github.com/linq2db/linq2db/pull/5307): improvements to SQL generation for complex queries
  - [#5305](https://github.com/linq2db/linq2db/pull/5305): fix issues with unused columns detection and removal
  - [#5103](https://github.com/linq2db/linq2db/pull/5103), [#5327](https://github.com/linq2db/linq2db/pull/5327): fix issues with missing `ORDER BY` clause for some queries with `GROUP BY/DISTINCT` clauses
- [#5310](https://github.com/linq2db/linq2db/pull/5310): fix column mappings discovery for `OUTPUT/RETURNING` special tables
- [#5314](https://github.com/linq2db/linq2db/pull/5314): fix merge if `IgnoreFilters` calls
- [#5317](https://github.com/linq2db/linq2db/pull/5317): fix association handling regression
- [#5320](https://github.com/linq2db/linq2db/pull/5320): [SQL Server] fix non-ASCII descriptions load by Schema API
- [#5321](https://github.com/linq2db/linq2db/pull/5321): improve/fix translation of `Convert.To*/Sql.Convert` APIs to SQL
  - [#5298](https://github.com/linq2db/linq2db/pull/5298): fix `Convert.To*` calls with dynamic properties
- [#5328](https://github.com/linq2db/linq2db/pull/5328): fix nullability calculation for aggregate in subqueries
- [#5332](https://github.com/linq2db/linq2db/pull/5332):
  - [#5325](https://github.com/linq2db/linq2db/pull/5325): add `DateTime.UtcNow` property mapping
  - fix convert operation translation issues
- [#5336](https://github.com/linq2db/linq2db/pull/5336): fix `Cast<T>` operator translation
- [#5340](https://github.com/linq2db/linq2db/pull/5340): fix issue with subqueries handling in `UPDATE`
- [#5341](https://github.com/linq2db/linq2db/pull/5341): fix nullability of join conditions for optional associations sequence
- [#5344](https://github.com/linq2db/linq2db/pull/5344): fix found issues with complex CTE translations, improve CTE aliases generation for `ClickHouse`
- [#5350](https://github.com/linq2db/linq2db/pull/5350): correct return value database type for some date diff operations, fix typo in SQL for diff in months for `PostgreSQL`
- [#5351](https://github.com/linq2db/linq2db/pull/5351): fix `ValueConverter` support in `UPDATE` queries, improve associations/subqueries translation for `UPDATE`
- [#5356](https://github.com/linq2db/linq2db/pull/5356): fix unused joins detection issues for nested joins
- [#5357](https://github.com/linq2db/linq2db/pull/5357): [PostgreSQL] add timeout option support for native bulk copy
- [#5361](https://github.com/linq2db/linq2db/pull/5361): fix threading issue for mapping types with non-public mapped members, including `Storage` members
- [#5362](https://github.com/linq2db/linq2db/pull/5362): fix `GroupBy` translation
- [#5366](https://github.com/linq2db/linq2db/pull/5366): fix SQL generation for queries with `DISTINCT` and `ORDER BY` over expression
- [#5368](https://github.com/linq2db/linq2db/pull/5368): support aggregation sub-queries inside non-table queries
- [#5369](https://github.com/linq2db/linq2db/pull/5369): add support for translation of following `IEnumerable/IQueryable` methods
  - `CountBy`
  - `Index`
  - `MaxBy/MinBy` (overload with comparer not supported)
  - `ExceptBy/UnionBy/IntersectBy` (overload with comparer not supported)
- [#5371](https://github.com/linq2db/linq2db/pull/5371): fix issue with name of parameter ignored when provided by `DataParameter`
- [#5373](https://github.com/linq2db/linq2db/pull/5373): fix translation of aggregation function calls with `AsEnumerable/AsQueryable` calls in chain
- [#5379](https://github.com/linq2db/linq2db/pull/5379): [SQLite] don't generate `CAST` to guid as it mess with SQLite affinity inference
- [#5381](https://github.com/linq2db/linq2db/pull/5381): don't remove subqueries with aggregates if outer query has complex clauses that could affect aggregation
- [#5382](https://github.com/linq2db/linq2db/pull/5382): fix `CTE` support for `DELETE` and `UPDATE` queries
- [#5383](https://github.com/linq2db/linq2db/pull/5383): fix hint API use with `ToSqlQuery` helper
- [#5392](https://github.com/linq2db/linq2db/pull/5392):
  - [#5390](https://github.com/linq2db/linq2db/pull/5390): don't generate precision/scale for `DateTime.Date` type
  - [Access][SQL Server 2005] don't generate precision/scale for `DateTime` type
- [#5398](https://github.com/linq2db/linq2db/pull/5398): fix handling or conversion of one enum type value to value of other enum type
- [#5401](https://github.com/linq2db/linq2db/pull/5401): [ClickHouse] add support for `ClickHouse.Driver` 1.x provider versions. We recommend to enable `ReadStringsAsByteArrays=true` option, especially if you work with binary data to avoid data loss on `binary->utf8->binary` translations

#### YDB provider updates

- implement `string.Join` translation
- fix `ORDER BY` over aliased column
- fix translation of some string-related APIs: padding, replace, indexof, substring

#### Introduce several improvements around stack use

Related issues: [#5261](https://github.com/linq2db/linq2db/pull/5261), [#5265](https://github.com/linq2db/linq2db/pull/5265)

- [#5273](https://github.com/linq2db/linq2db/pull/5273): significantly reduce stack use by expression and query visitors
- [#5270](https://github.com/linq2db/linq2db/pull/5270): support switching to additional thread(s) by visitors if there is not enough stack on current thread.

Number of additional threads to use configured using `int LinqToDB.Common.Configuration.TranslationThreadMaxHopCount` option:
- default value is set to `5`
- negative values (e.g. `-1`) will disable feature and `StackOverflowException` will be generated in case of stack end
- `0` will not use additional threads, but still test remaining stack space and generate `InsufficientExecutionStackException`, which could be intercepted
- values greater than `0` will use up to N threads before throwing `InsufficientExecutionStackException` exception if this amount is still not enough

We don't recommend to set this option to bigger values as it could lead to performance issues and thread pool starvation if you hit some bug with infinite recursion.

**LinqToDB for EntityFramework**

- [#4668](https://github.com/linq2db/linq2db/issues/4668): fix too aggressive inheritance detection
- [#5318](https://github.com/linq2db/linq2db/issues/5318): fix mapping of `PostgreSQL` enums when nullable enum type used (`SomeEnum?`). Thanks to [@denis-tsv](https://github.com/denis-tsv) for PR
- [#5388](https://github.com/linq2db/linq2db/issues/5388): fix value converters use for constant values

**Scaffold T4**

- [#5252](https://github.com/linq2db/linq2db/pull/5252): [SQL Server 2025] `JSON` and `VECTOR` types support
- [#5255](https://github.com/linq2db/linq2db/pull/5255): fix issues when `NotifyPropertyChanged` template used with scaffold

**Scaffold CLI**

- [#5281](https://github.com/linq2db/linq2db/pull/5281): [SQL Server 2025] `JSON` and `VECTOR` types support


***

### Release 6.1.0

**LinqToDB**

- [#4816](https://github.com/linq2db/linq2db/pull/4816): [SQL Server] fix separator parameter type for `STRING_AGG` to be based on type of first argument
- [#5233](https://github.com/linq2db/linq2db/pull/5233): add support for .NET 10 `LeftJoin` and `RightJoin` operators
- [#5236](https://github.com/linq2db/linq2db/pull/5236): fix exception converting null value of `Nullable<T>` type to another type using non-nullable converter
- [#5237](https://github.com/linq2db/linq2db/pull/5237): fix nuget explorer warings for packages (non-functional change)
- [#5239](https://github.com/linq2db/linq2db/pull/5239): fix incorrect update translation with `string.Join` setter expression
- [#5240](https://github.com/linq2db/linq2db/pull/5240): [SQL Server < 2025] fix v5 compatibility by mapping `DataType.Json` to `NVARCHAR(MAX)`
- [#5244](https://github.com/linq2db/linq2db/pull/5244): fix support for non-array collection parameters

**LinqToDB LINQPad Driver**

- [#5237](https://github.com/linq2db/linq2db/pull/5237): fix issue with settings dialog crashing on opening
- [#5247](https://github.com/linq2db/linq2db/pull/5247): re-enable DB2 iSeries support

***

### Release 6.0.0

<a name='release-600-preview1'></a>
<a name='release-600-preview2'></a>
<a name='release-600-preview3'></a>
<a name='release-600-preview4'></a>
<a name='release-600-rc1'></a>
<a name='release-600-rc2'></a>
<a name='release-600-rc3'></a>

Fore release notes and migration notes see [page](https://github.com/linq2db/linq2db/wiki/Linq-To-DB-6).

***

### Release 5.4.1.9

This [#5161](https://github.com/linq2db/linq2db/pull/5161) maintenance release contains **no functional changes, improvements, or bug fixes**.
Only third-party NuGet dependencies have been updated to their latest compatible versions.

- Updated third-party dependencies to improve long-term compatibility and security.
- Most Microsoft packages have been upgraded to **version 9.0.10**.
- No modifications were made to LINQ to DB core libraries or behavior.
- Intended for users who continue to rely on the stable 5.x branch in production environments.

***

### Release 5.4.1

**LinqToDB**

- [#4445](https://github.com/linq2db/linq2db/pull/4445): [PostgreSQL] improve performance of native `BulkCopy`. Thanks to [@AndreyShipunov](https://github.com/AndreyShipunov) for PR
- [#4456](https://github.com/linq2db/linq2db/pull/4456): [SQLite] Add optional `extension` parameter to `SQLiteTools.CreateDatabase` API to specify extension of created database file instead of hardcoded `.sqlite`. Thanks to [@alexey-leonovich](https://github.com/alexey-leonovich) for PR
- [#4457](https://github.com/linq2db/linq2db/pull/4457): Fix connection leak issue with `DataContext` transactions/eager load when context used with auto-released connection without context disposal

***

### Release 5.4.0

**LinqToDB**

- [#4005](https://github.com/linq2db/linq2db/pull/4005): adds metrics collection API
  - [#3405](https://github.com/linq2db/linq2db/issues/3405): see `OpenTelemetry` integration [example](https://github.com/linq2db/linq2db/tree/master/Examples/Metrics/OpenTelemetry) in our samples
  - add `Common.Configuration.TraceMaterializationActivity = false` option to enable materialization metrics collection
- [#4217](https://github.com/linq2db/linq2db/issues/4217): fixed `SQL` generation of unnecessary `IS NOT NULL` checks for some of nullable boolean comparisons
- [#4252](https://github.com/linq2db/linq2db/issues/4252): add new setting `UseEnableConstantExpressionInOrderBy(bool)` to allow constants in `ORDER BY` clause to sort using ordinals. Note that we don't recommend to use it as we don't give guaranty over column order in generated query `SQL`
- [#4327](https://github.com/linq2db/linq2db/issues/4327): fix issues with `null` handling in `IN (sub-query)/EXISTS` clauses
- [#4337](https://github.com/linq2db/linq2db/issues/4337): fix 5.3.0 regression `LinqException: ...TransparentIdentifier... cannot be converted to SQL.`
- [#4341](https://github.com/linq2db/linq2db/issues/4341): mark configuration API methods with `[Pure]` attribute to highlight that they doesn't modify options object. Thanks to [@curllog](https://github.com/curllog) for PR
- [#4368](https://github.com/linq2db/linq2db/issues/4368): add support for one-way conversions registration using `mappingSchema.SetConvertExpression.SetConverter` methods using new `conversionType = ConversionType.[From/To]Database` parameter
- [#4371](https://github.com/linq2db/linq2db/issues/4371): fix multiple issues where `CurrentCulture` used instead of `Invariant` culture
  - [#3783](https://github.com/linq2db/linq2db/issues/3783): fix issue with non-SQL compatible negative literals generated for some cultures
- [#4378](https://github.com/linq2db/linq2db/issues/4378): fix `BulkCopyOptions` copy constructor
- [#4383](https://github.com/linq2db/linq2db/issues/4383): fix inherited classes support in eager load
- [#4385](https://github.com/linq2db/linq2db/issues/4385): [Oracle] fix `DateOnly` support in array-bound bulk copy mode
- [#4387](https://github.com/linq2db/linq2db/issues/4387): [NativeAOT] fixed couple of NativeAOT issues. Note that we still doesn't support NativeAOT officially
- [#4389](https://github.com/linq2db/linq2db/issues/4389): [ClickHouse] fix bulk copy support with `ClickHouse.Client` 6.8.0+ provider
- [#4398](https://github.com/linq2db/linq2db/issues/4398): fix rare race conditions in connection options creation logic
- [#4403](https://github.com/linq2db/linq2db/issues/4403): [Oracle] fix use of fixed-size buffer in multiple-rows bulk copy mode
- [#4415](https://github.com/linq2db/linq2db/issues/4415): fix regression in nullable aggregated scalar sub-queries handling
- [#4426](https://github.com/linq2db/linq2db/issues/4426): fix `NullReferenceException` due to race conditions in context logging when user change trace levels

**LinqToDB Configuration**

- [#4326](https://github.com/linq2db/linq2db/issues/4326): fix incorrect registration logic for `AddLinqToDBContext<TContext, TContextImplementation>()` overload

**Scaffold T4**

- [#4375](https://github.com/linq2db/linq2db/issues/4375): emit procedures and functions ordered by name

**Scaffold CLI**

- [#4373](https://github.com/linq2db/linq2db/pull/4373): fixed incorrect regular expression examples in help. Thanks to [Michel Bretschneider](https://github.com/embix) for PR
- [#4428](https://github.com/linq2db/linq2db/pull/4428): add .NET 8 tool build

***

### Release 5.3.2

**LinqToDB**

- [#4313](https://github.com/linq2db/linq2db/issues/4313): fix regression in Npgsql 7- support, introduced by 5.3.1 release

***

### Release 5.3.1

**LinqToDB**

- [#4309](https://github.com/linq2db/linq2db/issues/4309): fix compatibility with Npgsql 8

***

### Release 5.3.0

**LinqToDB**

- [#3273](https://github.com/linq2db/linq2db/issues/3273): [Oracle] Prefer single `COALESCE` function over multiple nested `NVL` for calls with 3 or more parameters. Thanks to [@ddas09](https://github.com/ddas09) for PR
- [#4122](https://github.com/linq2db/linq2db/issues/4122): log elements of collection-typed query parameters (e.g. arrays). By default only first 8 elements logged. Use `Configuration.MaxArrayParameterLengthLogging` setting to change this limit
- [#4168](https://github.com/linq2db/linq2db/issues/4168), [#4174](https://github.com/linq2db/linq2db/issues/4174): fixed issue with linked server name being ignored by multiple APIs when only server name passed to API as input parameter
- [#4172](https://github.com/linq2db/linq2db/issues/4172): [Oracle] fix SQL, generated empty string comparison. Thanks to [Divyansh Bhatia](https://github.com/divyanshbhatia1) for PR
- [#4175](https://github.com/linq2db/linq2db/issues/4175): fix issue with conditional expressions parsing in output/returning clause. Thanks to [Kasper Fabæch Brandt](https://github.com/poizan42) for PR
- [#4176](https://github.com/linq2db/linq2db/issues/4176): [Access] removed wrong identifier escaping logic, when identifier with dot in name was split into multi-component identifier
- [#4182](https://github.com/linq2db/linq2db/issues/4182): fix table attributes support for `MergeWithOutputInto` output table. Thanks to [Kasper Fabæch Brandt](https://github.com/poizan42) for PR
- [#4196](https://github.com/linq2db/linq2db/issues/4196): fixed `null` values support for `value IN (subquery)` syntax. Added new option `PreferExistsForScalar` to configure generated SQL for scalar subquery conditions. This feature is useful for databases (e.g. ClickHouse), which doesn't support correlated sub-queries by converting it to non-correlated one.
  - `PreferExistsForScalar = true`: `EXISTS (SELECT * FROM sequence WHERE sequence.key = value)`
  - `PreferExistsForScalar = false` (default): `value IN (SELECT sequence.key FROM sequence)`
- [#4201](https://github.com/linq2db/linq2db/issues/4201): support associations with different key types on both sides
- [#4202](https://github.com/linq2db/linq2db/issues/4202): fix issues with sub-query hints in SET queries
- [#4203](https://github.com/linq2db/linq2db/issues/4203): fix issue with query hints in subqueries
- [#4204](https://github.com/linq2db/linq2db/issues/4204): fix issue with optimization of subquery with grouping
- [#4210](https://github.com/linq2db/linq2db/issues/4210): fix nullability tracing for ternary expressions
- [#4219](https://github.com/linq2db/linq2db/issues/4219): [Oracle] limit generated query parameter length to 30 characters for Oracle 12+ temporary while we don't have explicit support for 12.2+ Oracle dialects
- [#4228](https://github.com/linq2db/linq2db/issues/4228), [#4254](https://github.com/linq2db/linq2db/issues/4254): fix regression in parameter names generation
- [#4229](https://github.com/linq2db/linq2db/issues/4229): fixed issue, when cached query could hold reference to initial data context object, preventing it from garbage collection. This could lead to excessive memory use by query cache (sometimes huge)
- [#4256](https://github.com/linq2db/linq2db/issues/4256): fix issue with non-nullable constant values in sub-query projection to nullable projection field/property
- [#4257](https://github.com/linq2db/linq2db/issues/4257): enable support for `IDataContext.CloseAfterUse = true` context flag in `BulkCopy` API
- [#4261](https://github.com/linq2db/linq2db/issues/4261): fixed issue with embedding of enumerable collections with long path to collection
- [#4263](https://github.com/linq2db/linq2db/issues/4263): [NativeAOT] fixed issue with `Expression.DebugView` trimmed away
- [#4267](https://github.com/linq2db/linq2db/issues/4267): [NativeAOT] implemented workaround for `NativeAOT` issue with `GetInterfaceMap` API
- [#4268](https://github.com/linq2db/linq2db/issues/4268): changed `DataConnection.WriteTraceLineConnection` setter accessibility to protected to allow direct assignment from child classes. Thanks to [@Metadorius](https://github.com/Metadorius) for PR
- [#4275](https://github.com/linq2db/linq2db/issues/4275): some internal memory/performance optimizations to entity model build
- [#4280](https://github.com/linq2db/linq2db/issues/4280): fixed exception when `Update<TBase>(derivedInstance)` API called for entity with inheritance mapping
- [#4285](https://github.com/linq2db/linq2db/issues/4285): [PostgreSQL] fixed issues in identifier quotation logic
- [#4299](https://github.com/linq2db/linq2db/issues/4299): fix potential issue with default struct constructors
- [#4302](https://github.com/linq2db/linq2db/issues/4302): [Access] implement missing conversion to SQL `bool`

**Scaffold**
- [#4131](https://github.com/linq2db/linq2db/issues/4131):
  - [T4] fix Oracle templates, broken by 5.0 release
  - [#4058](https://github.com/linq2db/linq2db/issues/4058): [T4] fix issues with identifiers generation process steps, when C# keyword check applied before final name generated for some identifier types
- [#4134](https://github.com/linq2db/linq2db/issues/4134): [CLI] add `add-init-context` option to manage generation of `InitDataContext` partial method on context
- [#4255](https://github.com/linq2db/linq2db/issues/4255): [CLI] fixed multiple issues with parsing of generic types by `ITypeParser` implementation
- [#4278](https://github.com/linq2db/linq2db/issues/4278): [T4] we decided to cancel obsoletion of T4 nugets (scaffold [cli utility](https://www.nuget.org/packages/linq2db.cli) is still recomended way to scaffold database model)

***

### Release 5.2.2

**LinqToDB**

- [#4043](https://github.com/linq2db/linq2db/issues/4043): add missing support for column converters (`IValueConverter`) by `Execute[Async](string sql)` API
- [#4146](https://github.com/linq2db/linq2db/issues/4146):
  - refactor query parameter names generation to avoid issues like [#3902](https://github.com/linq2db/linq2db/issues/3902) and [#4144](https://github.com/linq2db/linq2db/issues/4144)
  - [PostgreSQL] fixed missing identifier quotation when identifier starts from non-letter and non-underscore character

**Scaffold CLI**

- [#4127](https://github.com/linq2db/linq2db/issues/4127): fix binding of output parameters for synchronous mappings of stored procedures


***

### Release 5.2.1

**LinqToDB**

- [#4025](https://github.com/linq2db/linq2db/issues/4025): fix issue with `object->DataParameter` conversion being ignored
- [#4074](https://github.com/linq2db/linq2db/issues/4074): improve discard of invalid `ORDER BY` columns from joined subqueries
- [#4090](https://github.com/linq2db/linq2db/issues/4090): fix nullability tracking for `OUTER APPLY` columns
- [#4098](https://github.com/linq2db/linq2db/issues/4098): fix issues with missing columns for queries with join to subquery
- [#4107](https://github.com/linq2db/linq2db/issues/4107): fix merge keys selection into CTE for merge-into-cte queries
- [#4113](https://github.com/linq2db/linq2db/issues/4113): fix regression in handling properties, which hide interface implementation with `new` keyword
- [#4124](https://github.com/linq2db/linq2db/issues/4124): fix database provider detection for `ProviderName.MariaDB` name

**Scaffold CLI**

- [#4111](https://github.com/linq2db/linq2db/issues/4111): fix scaffold of table functions in separate schema class

***

### Release 5.2.0

We started our own Discord server. Invite could be found [here](https://github.com/linq2db/linq2db#linq-to-db).


**LinqToDB**

- [#3034](https://github.com/linq2db/linq2db/issues/3034): fix mapping of inherited interfaces for interface mapping
- [#3776](https://github.com/linq2db/linq2db/issues/3776), [#3895](https://github.com/linq2db/linq2db/issues/3895), [EF#213](https://github.com/linq2db/linq2db.EntityFrameworkCore/issues/213), [EF#316](https://github.com/linq2db/linq2db.EntityFrameworkCore/issues/316): [PostgreSQL] fix issue with `DateTime` values `Kind` normalization, when it was converted to `Unspecified` for column of `timestamp with time zone` type. If you still have this issue, check that your column has type specified.
- [#4031](https://github.com/linq2db/linq2db/issues/4031): Improve detection of interface property implementation for mapping
- [#4045](https://github.com/linq2db/linq2db/issues/4045): [Oracle][PostgreSQL] fix issue with connection string parameter ignored by `PostgreSQLTools`/`OracleTools` in some methods
- [#4046](https://github.com/linq2db/linq2db/issues/4046): Apply `DataParameter` conversions to parameters in more cases
- [#4055](https://github.com/linq2db/linq2db/issues/4055): [MySQL] fix trailing hint generation for `INSERT` queries (e.g. `INSERT ... SELECT ... FOR UPDATE`)
- [#4065](https://github.com/linq2db/linq2db/issues/4065): [Firebird] fix incorrect SQL generation for parameter-less stored procedure, called as table function
- [#4066](https://github.com/linq2db/linq2db/issues/4066): [ClickHouse] add helpers to specify join hints, `FINAL` modifier and `SETTINGS` clause (see [tests](https://github.com/linq2db/linq2db/blob/master/Tests/Linq/Extensions/ClickHouseTests.cs) for usage examples)
- [#4070](https://github.com/linq2db/linq2db/issues/4070): [ClickHouse] fixed creation of temporary table with primary key in ClickHouse 23.3+
- [#4072](https://github.com/linq2db/linq2db/issues/4072): add static `DataConnection.DefaultOnTraceConnection` property to set default application-wide trace handler
- [#4079](https://github.com/linq2db/linq2db/issues/4079): fix `InvalidCastException` generated for some queries with `Sql.Property` API
- [#4082](https://github.com/linq2db/linq2db/issues/4082): fix materialization of entity, queried using implemented interface, where interface has read-only property and entity class implements it with setter
- [#4086](https://github.com/linq2db/linq2db/issues/4086): fix multiple issues with `DataContext`:
  - [#4057](https://github.com/linq2db/linq2db/issues/4057): async eager load operation on `DataContext` could fail with exception `InvalidOperationException: There is already an open DataReader associated with this Connection which must be closed first.`
  - `DataContext` with `KeepConnectionAlive = false` setting closes implicit eager load transaction after first query
  - `DataContext` queries caching doesn't work correctly (could affect only applications with multiple configurations for same database type)

**Scaffold CLI**

- [#4061](https://github.com/linq2db/linq2db/issues/4061): Fix regression in association names generation for composite foreign keys

***

### Release 5.1.1

**LinqToDB**

- [#4037](https://github.com/linq2db/linq2db/issues/4037): fixed issue with incorrect use of connection string parameter by some of `[Oracle|PostgreSQL|SqlServer]Tools` APIs

***

### Release 5.1.0

**LinqToDB**

- [#3966](https://github.com/linq2db/linq2db/issues/3966):
  - prefer `field IN (subquery)` SQL generation instead of `EXISTS(subquery with field filter)` for scalar subqueries
  - improve `boolean` type compatibility for `ClickHouse` for `Octonica` and `MySql` providers
- [#3997](https://github.com/linq2db/linq2db/issues/3997): don't throw exception from provider dialect detector when dialect already specified in context options and connection string is not set
- [#4001](https://github.com/linq2db/linq2db/issues/4001):
  - added new extension point for query hints/extensions generation: `QueryExtensionScope.TableNameHint`
  - [SQL Server] add temporal table extensions to filter by `FOR SYSTEM_TIME` clause: `TemporalTableHint`, `TemporalTableAll`, `TemporalTableAsOf`, `TemporalTableFromTo`, `TemporalTableBetween`, `TemporalTableContainedIn`
- [#4006](https://github.com/linq2db/linq2db/issues/4006): add `BigInteger` type support for PostgreSQL
- [#4010](https://github.com/linq2db/linq2db/issues/4010): fix potential issues with hint extensions
- [#4011](https://github.com/linq2db/linq2db/issues/4011): fix nullability tracking for deep-nested optional associations
- [#4014](https://github.com/linq2db/linq2db/issues/4014): fix overloads conflict for `UsePostgreSQL` configuration extensions
- [#4015](https://github.com/linq2db/linq2db/issues/4015): add `WhereKeyOptimistic` extension to apply query filter over primary key and lock field for specific record
- [#4016](https://github.com/linq2db/linq2db/issues/4016): disable unused left join optimization for joins with hints
- [#4022](https://github.com/linq2db/linq2db/issues/4022): fix work with inherited attributes on properties
- [#4027](https://github.com/linq2db/linq2db/issues/4027): fix regression in `DataConnection.DefaultSettings` assignment handling

**Scaffold CLI**

- [#4021](https://github.com/linq2db/linq2db/issues/4021):
  - [#945](https://github.com/linq2db/linq2db/issues/945): add support for fluent metadata generation: new `--metadata` option with values `none`, `attributes` (default), `fluent`
  - automatically pass generated mapping schema to context in generated context constructors (for fluent mapping and `PostgreSQL` tuples mapping)
  - [PostgreSQL] fix error when scaffold includes `NpgsqlTypes.NpgsqlInterval` type
  - [SQL CE] fix duplicate foreign key columns
  - fixed equality generation for nullable `System.Data.SqlTypes.Sql*` struct types and `SqlHierarchyId`
  - fixed equality generation for DB2 custom struct types (e.g. `DB2Int32`) including nullable types
  - fixed defaults rendering in `--find-methods` command help, add `none` option to disable generation of `Find*` methods

***

### Release 5.0.0

Also check [V5 migration notes](Migration-to-v5).

**LinqToDB**

- [#3975](https://github.com/linq2db/linq2db/issues/3975): fix support for `AssociationSetterExpression` for cases when `Storage` use different type compared to mapped association
- [#3981](https://github.com/linq2db/linq2db/issues/3981): simplify and clarify `IMetadataReader.GetAttributes` API contract:
  - remove use of generic arguments and set return type to `MappingAttribute[]` from `T[] where T: MappingAttribute`
  - document that implementation should return all mapping attributes for requested member/type
- [#3983](https://github.com/linq2db/linq2db/issues/3983): fix `InvalidCastException` from `InsertWithOutput*` APIs when target and output types doesn't match
- [#3986](https://github.com/linq2db/linq2db/issues/3986): fix `Contains` to `IN` conversion for collections with `null` values

***

### Release 5.0.0 RC 2

<a name='release-500-rc2'></a>

**LinqToDB**

- [#3959](https://github.com/linq2db/linq2db/issues/3959): fix issue with reverted default column order for mapping classes with inheritance. Thanks to [Guillaume Lecomte](https://github.com/guillaume86) for PR
- [#3961](https://github.com/linq2db/linq2db/issues/3961): add support for custom association setter expression, used on association load using `LoadWith`/`ThenWith` APIs (Thanks to [Guillaume Lecomte](https://github.com/guillaume86) for PR):
  - `AssociationAttribute.AssociationSetterExpressionMethod`
  - `AssociationAttribute.AssociationSetterExpression`
- [#3962](https://github.com/linq2db/linq2db/issues/3962): add additional overloads to `CreateTempTable` API to support anonymous classes
- [#3967](https://github.com/linq2db/linq2db/issues/3967): fixed incorrect equality operators implementations for `DataOptions`
- [#3969](https://github.com/linq2db/linq2db/issues/3969): ([#1592](https://github.com/linq2db/linq2db/issues/1592), [#1822](https://github.com/linq2db/linq2db/issues/1822)) replace `MappingSchema.EntityDescriptorCreatedCallback` instance delegate with
  - application-wide `MappingSchema.EntityDescriptorCreatedCallback` static delegate
  - context-specific delegate, set using `WithOnEntityDescriptorCreated`/`UseOnEntityDescriptorCreated` configuration extensions
- [#3970](https://github.com/linq2db/linq2db/issues/3970): add additional overloads to `Use<DB_NAME>` options configuration extensions without connection string parameter

***

### Release 5.0.0 RC 1

<a name='release-500-rc1'></a>

**LinqToDB**

- [#3643](https://github.com/linq2db/linq2db/issues/3643): added source table support to output/returning clause to Merge API:
  - `MergeWithOutput[Async]` (SQL Server 2008+, Firebird 3.0+)
  - `MergeWithOutputInto[Async]` (SQL Server 2008+)
- [#3840](https://github.com/linq2db/linq2db/issues/3840): fix type convert issues in mapping generation
- [#3858](https://github.com/linq2db/linq2db/issues/3858):
  - improve detection of cases when we can generate single query with `APPLY` instead of multiple queries
  - [#3799](https://github.com/linq2db/linq2db/issues/3799): fix `NotImplementedException` from eager-load queries with single-record subqueries (e.g. using `FirstOrDefault`)
- [#3952](https://github.com/linq2db/linq2db/issues/3952): due to compatibility issues between `MySql.Data` provider and recent versions on `MariaDB` we drop support for `MySql.Data` provider use with `MariaDB`. You can still use it with old `MariaDB` versions, but we don't accept issues for this provider/database combination and recommend to use `MySqlConnector` provider (for `MySql` too)

**linq2db.AspNet**

- [#3953](https://github.com/linq2db/linq2db/issues/3953): downgrade required `Microsoft.Extensions.DependencyInjection` and `Microsoft.Extensions.Logging.Abstractions` dependencies to version 6 from 7

***

### Release 5.0.0 Preview 2

<a name='release-500-preview2'></a>

**LinqToDB**

- [#553](https://github.com/linq2db/linq2db/issues/553): added API for record delete/update with optimistic lock. See [notes](#optimistic-lock-extensions) below
- [#2690](https://github.com/linq2db/linq2db/issues/2690): add support for C# Nullable Reference Types annotations to infer nullability of columns and single-record associations. To enable it, set `Configuration.UseNullableTypesMetadata = true;` option. Note that curently this is application-wide option and cannot be configured per-context
- [#3905](https://github.com/linq2db/linq2db/issues/3905): [MySql][MariaDB] added extensions to work with 'FOR UPDATE/SHARE' hints (see examples in [tests](https://github.com/linq2db/linq2db/blob/master/Tests/Linq/Extensions/MySqlTests.cs))
- [#3900](https://github.com/linq2db/linq2db/issues/3900): performance-related optimizations and refactorings
  - mapping attributes refactoring (see [below](#mapping-attributes-refactoring))
  - breaking changes to fluent mapping (see [below](#fluent-mapping-changes))
  - [**BREAKING CHANGE**] `Configuration.Linq.EnableAutoFluentMapping` was renamed to `EnableContextSchemaEdit` to better reflect affected behavior and set it to `false` by [default](#default-configuration-changes)
  - [**BREAKING CHANGE**] disable support for mapping attributes from `System.ComponentModel.DataAnnotations.Schema` and `System.Data.Linq.Mapping` namespaces by [default](#default-configuration-changes)
  - connection factory delegate accepts `DataOptions` instance now (`Func<DbConnection>` -> `Func<DataOptions, DbConnection>`). It allows user to access connection options, e.g. connection string: `options => new SqlConnection(options.ConnectionOptions.ConnectionString)`
  - [**BREAKING CHANGE**] custom `IMetadataReader` implementations should support requests for base attribute types. See more details [here](#metadata-reader-changes)
- [#3906](https://github.com/linq2db/linq2db/issues/3906): fixed `InvalidOperationException` in eager load
- [#3910](https://github.com/linq2db/linq2db/issues/3910): fixed C# NRT annotations on `LoadWith`/`ThenLoad` APIs
- [#3921](https://github.com/linq2db/linq2db/issues/3921): fixed several issues with asociations:
  - [#3658](https://github.com/linq2db/linq2db/issues/3658): respect `CanBeNull` for associations with custom predicate expression
  - prevent "unused" inner join removal by sql optimizer if it was added by association
  - fix generation of joins for associations for `Count` scalar queries
- [#3926](https://github.com/linq2db/linq2db/issues/3926): fixed issue in eager load
- [#3933](https://github.com/linq2db/linq2db/issues/3933): fix context mapping schema pollution in temporary table APIs with custom entity configuration delegate parameter
- [#3939](https://github.com/linq2db/linq2db/issues/3939): add new connection extensions to simplify database connection setup without need to define interceptor class: `UseBeforeConnectionOpened`/`UseAfterConnectionOpened`. Both extensions accept sync delegate with connection instance parameter and optional async delegate for use from async code if you need to call blocking code from setup delegate. Some examples where it could be useful:
  - Sql Server connection authentication setup using [`SqlCredential`](https://github.com/linq2db/linq2db/issues/2137) or [`AccessToken`](https://github.com/linq2db/linq2db/issues/1604)
  - SQLite database encryption setup using `PRAGMA *KEY` [directives](https://www.sqlite.org/see/doc/trunk/www/readme.wiki)
- [#3943](https://github.com/linq2db/linq2db/issues/3943): improve performance of `System.Data.Linq.Binary` .NET Core compatibility class. Thanks to [Guillaume Lecomte](https://github.com/guillaume86) for PR

**Scaffold CLI**

- [#3728](https://github.com/linq2db/linq2db/issues/3728): fix one-to-one association name generation regression
- [#3896](https://github.com/linq2db/linq2db/issues/3896): fix `PE image doesn't contain managed metadata.` error when use T4 template for interceptors (thanks to [@AndyBan](https://github.com/AndyBan) for PR)
- [#3938](https://github.com/linq2db/linq2db/issues/3938): fix SQL Server support regression in `preview-1`

#### Optimistic Lock Extensions

Namespace: `LinqToDB.Concurrency`.

There are two new extensions to leverage record update and delete operations using optimistic locks:
- `UpdateOptimistic[Async]`
- `DeleteOptimistic[Async]`

Those extensions:
- accept record object you need to update or delete with version field value set and add version check to your query;
- return number of affected records which you should check to see if operation executed successfully or nothing was updated/deleted due to version change in database or because record is not found.

To use those extensions you need to tell `Linq To DB` which field should be used as version field and how to generate new version value on optimistic update. For that you can:
- annotate it with `OptimisticLockPropertyAttribute` which provides several standard version generation strategies;
- implement your own one using `OptimisticLockPropertyBaseAttribute` as base attribute class and specify update expression in `GetNextValue` method.

Built-in strategies:
- `VersionBehavior.Auto`: use database-generated value. E.g. SQL Server `rowversion` field type or `UPDATE TRIGGER`
- `VersionBehavior.AutoIncrement`: use autoincrement strategy (by +1) on numeric field
- `VersionBehavior.Guid`: use `Guid.NewGuid()` client side generation. Could be applied to fields of `Guid`, `string` (using `guid.ToString()`) or `byte[]` (using `guid.ToByteArray()`) types

Example:
```cs
[Table]
public class MyTable
{
    [PrimaryKey, Identity]
    public int Id { get;set; }

    [Column]
    [OptimisticLockProperty(VersionBehavior.Guid)]
    public Guid Version { get;set; }

    [Column]
    public string Name { get;set; }

    // ... other fields
}

using var db = new MyContext();

var record1 = new MyTable()
{
    // initial version
    Version = Guid.NewGuid(),
    Name = "My Name"
};

// add record to database
db.Insert(record1);

record.Name = "New Name";
if (db.UpdateOptimistic(record1) == 0)
{
    // update failed - sombody managed to remove our record or change it's version
    throw new InvalidOperationException(
        $"Update failed, record with id={record1.Id} and"
            + $" version={record1.Version} wasn't found in database");
}
else
{
    // add additional condition to query
    if (db.GetTable<MyTable>().Where(r => r.Name.Contains("My")).DeleteOptimistic(record1) == 0)
    {
        // use only primary key + version as delete condition
        if (db.DeleteOptimistic(record1) == 0)
        {
            throw new InvalidOperationException(
                $"Delete failed, record with id={record1.Id} and"
                    + $" version={record1.Version} wasn't found in database");
        }
    }
}
```

#### Mapping attributes refactoring

This release introduce major refactoring to mapping attributes which includes:
- all mapping attributes now inherited from `MappingAttribute` base class, which means all of them now have `string? Configuration` property to specify configuration-specific mapping. Previously it wasn't possible to specify configuration-specific mappings using some mapping attributes;
- `interface IMetadataReader` now has generic constrain `TAttribute: MappingAttribute` which will require changes from you, if you use custom metadata readers
  - you need to add generic constrains to your implementation
  - you cannot return non-mapping attributes from reader (which already was useless, as `linq2db` doesn't query such attributes from readers anyways)
- attribute getter methods in `MappingSchema` class now also have `TAttribute: MappingAttribute` constrain now. This shouldn't affect most of users as those methods designed for use by `linq2db` itself

#### Fluent mapping changes

With this release we introduce breaking change to fluent mapping configuration, which will require changes from all users of fluent mapping.

Previously to configure mappings using fluent builder all you need to do is to create builder using `GetFluentMappingBuilder()` method on mapping schema or database context and add mappings using builder method which immediatly reflected in mapping schema.

We change this behavior to postpone configured mappings registration in mapping schema till explicit call to new `Build()` method on fluent mappings builder and remove `GetFluentMappingBuilder` from `MappingSchema` and `DataContext` and `DataConnection` classes to make this breaking change explicit.

E.g. you have following code which worked before:
```cs
// create new data context
using var db = new MyDataContext();

// create new mapping schema for fluent mappings
// and add it to context
var fluentMappings = new MappingSchema();
db.AddMappingSchema(fluentMappings);

// get mappings builder from mapping schema
var builder = fluentMappings.GetFluentMappingBuilder();
// or using context mapping schema directly
// var builder = db.MappingSchema.GetFluentMappingBuilder();
// or
// var builder = db.GetFluentMappingBuilder();

// configure mappings
builder.Entity<MyEntity>().Property(e => e.Id).IsPrimaryKey();

// all done, you can use your mappings already

// delete entity by primary key value from Id property
db.Delete(entity);
```

While it worked before, that example contains a lot of issues with performance and will not work in new version for at least two reasons:
- there is no `Build()` method call yet, so context don't know anything about new mappings;
- `AddMappingSchema(..)` method called before mappings configured - this will also not work anymore, because fluent mappings not set to mapping schema yet by `Build()` call;
- if you used `GetFluentMappingBuilder` method on context/context schema - it will also will not work as we changed library defaults and context mapping schema is not editable by default anymore.

Except those obvious breaking changes this example also has big performance issue: if you need to configure mappings you need to do it once and then use pre-configured mapping schema with all context instances otherwise you will have big performance penalty as `linq2db` will be unable to reuse cached mapping information.

Proper configuration of (fluent) mappings:
```cs
// setup mappings once, e.g. in application startup or MyDataContext static constructor:

private readonly MappingSchema _mappings;

static MyDataContext()
{
    // create shared mapping schema instance with all context mappings
    _mappings = new MappingSchema();

    // configure fluent mappings
    // create builder instance explicitly
    new FluentMappingBuilder(_mappings)
        .Entity<MyEntity>()
            .Property(e => e.Id)
                .IsPrimaryKey()
        // (!) commit mappings to mapping schema
        Build();

    // also we can configure additional mappings
    _mappings.SetConvertExpression(...);
}

// pass mapping schema to context base contructor (e.g. using DataOptions)
public MyDataContext(DataOptions options)
    : base(options.UseMappingSchema(_mappings))
{
}
```

#### Default configuration changes

We are changing some library defaults to provide better performance by default. It could break some users.

##### Data context mapping schema (`MappingSchema IDataContext.MappingSchema` property) from now is read-only by default.

It means you cannot edit it from context instance:

```cs
var db = new MyContext();

// add fluent mappings to context mapping schema
db.MappingSchema.GetFluentMappingBuilder();
// register new type conversion
db.MappingSchema.SetConvertExpression(...);
```

You can restore old behavior using following code:
```cs
// application-wide switch
Configuration.Linq.EnableContextSchemaEdit = true;

// context-wide option
var db = new MyContext(new DataOptions().UseEnableContextSchemaEdit(true));
```

But we wont recommend doing it as it will affect performance. Recommended approach is to create single mapping schema instance, configure it and use with all context instances. You can see example how to do it in [fluent mappings section](#fluent-mapping-changes).

##### disable support for mapping attributes from non-linq2db namespaces

In previous releases Linq To DB was able to consume some mapping attributes from `System.ComponentModel.DataAnnotations.Schema` and `System.Data.Linq.Mapping` namespaces.

Starting from this release support for those attributes is not enabled by default. Those mappings were used by minor part of users but calls to corresponding metadata providers are done for all users.

If you used them, you need to enable corresponding metadata readers:

```cs
// for System.Data.Linq.Mapping support
var reader = SystemDataLinqAttributeReader();
// for System.ComponentModel.DataAnnotations.Schema
var reader = SystemComponentModelDataAnnotationsSchemaAttributeReader();

// enable globally
MappingSchema.Default.AddMetadataReader(reader);

// enable for specific mapping schema (don't forget to setup
// schema once per-application to benefit from mappings caching)
mappingSchema.AddMetadataReader(reader);
```

#### Metadata Reader Changes

**_Obsoletion note: in final release we removed generics from `GetAttributes` and require from them to return all attributes always_**

If you implemented custom metadata reader in your application (`interface IMetadataReader`), you will need to make several changes to your implementation:

1. add `where T : MappingAttribute` generic constrain to `GetAttributes` methods implementation
2. change `GetAttributes` logic to support calls where `T = MappingAttribute`

From this release linq2db could call `GetAttributes` methods using base attribute type instead of concrete type. E.g. `GetAttributes<MappingAttribute>` instead of `GetAttributes<TableAttribute>`. To support this new behavior you will need to make two changes to your implementation.

Replace `T` check conditions to use `IsAssignableFrom`:

```cs

// old code
if (typeof(T) == typeof(TableAttribute))
{
   // create and return TableAttribute instance
}

// new check. takes inheritance into account
if (typeof(T).IsAssignableFrom(typeof(TableAttribute)))
{
   // create and return TableAttribute instance
}

```

Return all applicable attributes if all of them derived from `T`:

```cs

// old code
if (typeof(T) == typeof(ColumnAttribute))
{
   // create and return ColumnAttribute instance
}
else if (typeof(T) == typeof(Sql.ExpressionAttribute))
{
   // create and return Sql.ExpressionAttribute instance
}

// new code
// because T could represent base class, both supported attributes should be returned
var result = new List<T>();
if (typeof(T).IsAssignableFrom(typeof(ColumnAttribute)))
{
   // create ColumnAttribute instance
   result.Add(columnAttr);
}

if (typeof(T).IsAssignableFrom(typeof(Sql.ExpressionAttribute)))
{
   // create Sql.ExpressionAttribute instance
   result.Add(expressionAttr);
}

// return all applicable attributes
return result.ToArray();
```

***

### Release 5.0.0 Preview 1

<a name='release-500-preview1'></a>

- [#3530](https://github.com/linq2db/linq2db/issues/3530):
  - [#471](https://github.com/linq2db/linq2db/issues/471): fix issue when changing some application-wide options form `Configuration.Linq` could affect existing connections/cached queries, see more details below on options rework
  - [#472](https://github.com/linq2db/linq2db/issues/472): introduced connection-wide provider specific options instead of existing application-wide options
  - add `void RemoveInterceptor(IInterceptor interceptor)` method to contexts
  - add `DataConnection.OnRemoveInterceptor` event
  - improved SQL dialect detection logic for SQL Server, PostgreSQL and Oracle to cache detection results per-connection string
  - context options `DataOptions` instance accessible using `IDataContext.Options` property
  - [T4] added new T4 setting `string GetDataOptionsMethod` to specify name of custom static method with `DataOptions` return type, called by generated constructors
  - [t4] renamed T4 option `GenerateLinqToDBConnectionOptionsConstructors`  to `GenerateDataOptionsConstructors`
  - [SQL Server] default SQL Server dialect bumped to SQL Server 2012 from 2008
  - added support for automatic detection of SQL Server provider (`SqlServerProvider.AutoDetect`)
- [#3898](https://github.com/linq2db/linq2db/issues/3898): removed obsoleted APIs
- [#3902](https://github.com/linq2db/linq2db/issues/3902): [Sybase] fix issue with too long parameter name trimming

#### Provider Dialect Detection Changes

`AutoDetect` logic enabled by default for SQL Server, PostgreSQL and Oracle providers if user doesn't specify required dialect version explicitly:
- SQL Server provider will use `AutoDetect` logic to detect SQL dialect instread of `SQL Server 2008` (`2012` starting from this release) dialect by default. To disable it set `SqlServerTools.AutoDetectProvider` to `false`
- PostgreSQL provider will use `AutoDetect` logic to detect SQL dialect instread of `PostgreSQL 9.2` dialect by default. To disable it set `PostgreSQLTools.AutoDetectProvider` to `false`
- Oracle provider will use `AutoDetect` logic to detect SQL dialect instread of `Oracle 12` dialect by default. To disable it set `OracleTools.AutoDetectProvider` to `false`

#### Options Rework

[PR](https://github.com/linq2db/linq2db/pull/3530)

This PR introduce major options overhaul.

##### Required changes to configuration code

`LinqToDBConnectionOptionsBuilder` options builder class alongside with `LinqToDBConnectionOptions` and `LinqToDBConnectionOptions<T>` classes
replaced with `DataOptions[<T>]` classes. This will require from you to change configuration logic a bit:

```cs
// OLD CONFIGURATION APPROACH

// 1. create options builder
var optionsBuilder = new LinqToDBConnectionOptionsBuilder();
// 2. set options to builder
optionsBuilder.UseSqlServer(connectionString);
// 3. generate options object using Build() method and pass it to context or register in DI container
new DataContext(optionsBuilder.Build());

// NEW CONFIGURATION APPROACH

// 1. create immutable options object
var options = new DataOptions();
// 2. "mutate" it using same configuration methods as before
// IMPORTANT: because options object is immutable you should chaing configuration methods calls
// or save returned options object to variable
options = options.UseSqlServer(connectionString);
// 3. pass options to context/DI container
new DataContext(options);
```

As you can notice main changes are:
- two old configuration classes (builder and options) replaced with single options class
- because options are immutable (compared to old builder), you must not forget to use results of `Use*` configuration methods
- configuration build extensions not changed in general, several old extensions that were not used `Use*` naming pattern were renamed. See full list of renames below
- `AspNet` configuration extensions `AddLinqToDB`\`AddLinqToDBContext` now require that you return options instance from `configure` delegate parameter

##### Fix to application-wide options scope

Changes to application-wide configuration options (see list of options below) doesn't affect already created contexts and cached queries

- `Configuration.Linq.PreloadGroups`
- `Configuration.Linq.IgnoreEmptyUpdate`
- `Configuration.Linq.GenerateExpressionTest`
- `Configuration.Linq.TraceMapperExpression`
- `Configuration.Linq.DoNotClearOrderBys`
- `Configuration.Linq.OptimizeJoins`
- `Configuration.Linq.CompareNullsAsValues`
- `Configuration.Linq.GuardGrouping`
- `Configuration.Linq.DisableQueryCache`
- `Configuration.Linq.CacheSlidingExpiration`
- `Configuration.Linq.PreferApply`
- `Configuration.Linq.KeepDistinctOrdered`
- `Configuration.Linq.ParameterizeTakeSkip`
- `Configuration.Linq.EnableAutoFluentMapping`

Same logic applied to retry policy objects and application-wide options for them:

- `Configuration.RetryPolicy.DefaultRandomFactor`
- `Configuration.RetryPolicy.DefaultExponentialBase`
- `Configuration.RetryPolicy.DefaultCoefficient`

Also all those options now could be configured per-context using `Use<OptionName>` configuration extensions.

For `Configuration.Linq` options:
- `UsePreloadGroups`
- `UseIgnoreEmptyUpdate`
- `UseGenerateExpressionTest`
- `UseTraceMapperExpression`
- `UseDoNotClearOrderBys`
- `UseOptimizeJoins`
- `UseCompareNullsAsValues`
- `UseGuardGrouping`
- `UseDisableQueryCache`
- `UseCacheSlidingExpiration`
- `UsePreferApply`
- `UseKeepDistinctOrdered`
- `UseParameterizeTakeSkip`
- `UseEnableAutoFluentMapping`

For `Configuration.RetryPolicy` options:
- `UseRetryPolicy`
- `UseDefaultRetryPolicyFactory`
- `UseFactory`
- `UseMaxRetryCount`
- `UseMaxDelay`
- `UseRandomFactor`
- `UseExponentialBase`
- `UseCoefficient`

Added `UseBulkCopy<option_name>()` helpers to configure connection-wide bulk copy defaults.

Also for following option objects we added `With<option_name>` configuration extensions:
- `BulkCopyOptions`
- `RetryPolicyOptions`
- `QueryTraceOptions`
- `ConnectionOptions`
- `LinqOptions`

##### Provider-specific options

Introduced support for provider-specific options instead of application-wide settings, usually located in `<DB>Tools` provider classes.

Current release contains options for all providers (see list below). They could be configured globally using `<DB>Options.Default` options set or using `Use<DB>` configuration extension.

List of available options (old options were marked with `Obsolete` attribute):

- [ALL] `<DB>Tools.DefaultBulkCopyType` -> `<DB>Options.BulkCopyType`
- [MSSQL] `SqlServerConfiguration.GenerateScopeIdentity` -> `SqlServerOptions.GenerateScopeIdentity`
- [SQL CE] `SqlCeConfiguration.InlineFunctionParameters` -> `SqlCeOptions.InlineFunctionParameters`
- [SQLite] `SQLiteTools.AlwaysCheckDbNull` -> `SQLiteOptions.AlwaysCheckDbNull`
- [PostgreSQL] `PostgreSQLTools.NormalizeTimestampData` -> `PostgreSQLOptions.NormalizeTimestampData`
- [PostgreSQL] `PostgreSQLSqlBuilder.IdentifierQuoteMode` -> `PostgreSQLOptions.IdentifierQuoteMode`
- [Oracle] `OracleTools.DontEscapeLowercaseIdentifiers` -> `OracleOptions.DontEscapeLowercaseIdentifiers`
- [Informix] `InformixConfiguration.ExplicitFractionalSecondsSeparator` -> `InformixOptions.ExplicitFractionalSecondsSeparator`
- [Firebird] `FirebirdConfiguration.IdentifierQuoteMode` -> `FirebirdOptions.IdentifierQuoteMode`
- [Firebird] `FirebirdConfiguration.IsLiteralEncodingSupported` -> `FirebirdOptions.IsLiteralEncodingSupported`
- [DB2] `DB2SqlBuilderBase.IdentifierQuoteMode` -> `DB2Options.IdentifierQuoteMode`
- [ClickHouse] `ClickHouseConfiguration.UseStandardCompatibleAggregates` -> `ClickHouseOptions.UseStandardCompatibleAggregates`

#### T4 changes

T4 templates updated to:
- generate new options constructors
- added new T4 setting `string GetDataOptionsMethod` to specify name of custom static method with `DataOptions` return type, called by generated constructors
- renamed T4 option `GenerateLinqToDBConnectionOptionsConstructors`  to `GenerateDataOptionsConstructors`

#### Public API Changes/Renames

- `BulkCopyOption` changed from `class` to `class record`. Because class records are immutable, you should use `with` statement or new `With<BulkOption>()` helpers
- added `DataConnection` constructors with `Func<DataOptions,DataOptions> optionsSetter` parameter to build options using `DataConnection.DefaultDataOptions` as input
- method rename: `UseAccessODBC` -> `UseAccessOdbc`
- method rename: `WithInterceptor` -> `UseInterceptor`
- method rename: `WithTracing` -> `UseTracing`
- method rename: `WithTraceLevel` -> `UseTraceLevel`
- method rename: `WriteTraceWith` -> `UseTraceWith`
- property rename: `SqlServerTools.Provider` -> `SqlServerTools.DefaultProvider`
- property rename: `GrpcDataContext.Options` -> `GrpcDataContext.ChannelOptions`
- internal infrastructure support class `TypeExtensions` with `Type` extension methods (`UnwrapNullableType`, `IsNullableType`, `IsInteger`, `IsNumericType`, `IsSignedInteger`, `IsSignedType`) removed from public surface
- added `OracleVersion.AutoDetect`, `PostgreSQLVersion.AutoDetect`, `SqlServerVersion.AutoDetect` enum values to explicitly specify that SQL dialect should be detected by `LinqToDB` based on server version
- `LinqToDB.Common.Internal.ValueComparer[<T>]` classes removed from public surface

***

### Release 4.4.1

- [#3946](https://github.com/linq2db/linq2db/issues/3946):
  - [DB2][Firebird][Oracle] remove unnecessary wrapper subquery around `SELECT` with `CTE` for `INSERT FROM SELECT` queries
  - [DB2] fixed position of `CTE` clause in `INSERT FROM SELECT` queries
  - [#3945](https://github.com/linq2db/linq2db/issues/3945): fixed generation of addtional unnecessary columns in select sub-query with composite columns
  - [PostgreSQL][Firebird][MySql][MariaDb] don't add `RECURSIVE` keyword to simple `CTE` clauses, defined by `GetCte` API
***

### Release 4.4.0

- [#3218](https://github.com/linq2db/linq2db/issues/3218): [T4][SQLite] fixed issue with schema load where it could fail due to outdated sqlite runtime version used
- [#3579](https://github.com/linq2db/linq2db/issues/3579): corrected nullability annotations on `Sql.Collate` function
- [#3712](https://github.com/linq2db/linq2db/issues/3712): add `InsertWithOutput` extensions for `IValueInsertable` interface
- [#3751](https://github.com/linq2db/linq2db/issues/3751): treat non-nullable columns from left joins as nullable during SQL generation
- [#3760](https://github.com/linq2db/linq2db/issues/3760), [#3834](https://github.com/linq2db/linq2db/issues/3834): fixed issue where `InsertWithOutput` API cannot handle columns when column's name and property's name are different
- [#3761](https://github.com/linq2db/linq2db/issues/3761): improve mapping of `Nullable<T>.GetValueOrDefault()` to generate query parameter
- [#3762](https://github.com/linq2db/linq2db/issues/3762): [Scaffold] fix SQL Server scalar function mappings to always include schema name as required by SQL Server
- [#3777](https://github.com/linq2db/linq2db/issues/3777): [Scaffold] fixed issue where scaffold could generate classes/properties in different order between generations. From now generated code will have mappings for tables and functions ordered by name in database and columns by column ordinal
- [#3788](https://github.com/linq2db/linq2db/issues/3788), [#3872](https://github.com/linq2db/linq2db/issues/3872): improve `GroupBy(constant)` optimization to exclude unnecessary `GROUP BY` generation
- [#3791](https://github.com/linq2db/linq2db/issues/3791): fix `InvalidOperationException: No coercion operator is defined...` error when custom conversion specified between types with `TypeConverter` support
- [#3797](https://github.com/linq2db/linq2db/issues/3797): [ClickHouse] enable support for `EXCEPT ALL`/`INTERCEPT ALL` set operators
- [#3803](https://github.com/linq2db/linq2db/issues/3803): Scaffold framework improvements:
  - add `AfterSourceCodeGenerated(FinalDataModel model)` interceptor to provide access to data model used for code generation with actual indentifiers, used for generated code, set
  - add `string? ForeignKeyName` property to `AssociationModel` class
- [#3809](https://github.com/linq2db/linq2db/issues/3809): fix issue in conditional expressions handling for associated tables
- [#3810](https://github.com/linq2db/linq2db/issues/3810): [Scaffold] fixed composite foreign key association generation to use all key columns instead of first key column only 
- [#3811](https://github.com/linq2db/linq2db/issues/3811): Fix equality implementation for `System.Data.Linq.Binary` type for .net (core) runtimes
- [#3820](https://github.com/linq2db/linq2db/issues/3820): [Scaffold] add native support for `net6.0` and `net7.0` to scaffold cli tool
- [#3825](https://github.com/linq2db/linq2db/issues/3825): Fixed support for some mapping attributes in fluent mapping (`MapValueAttribute` and some more)
- [#3826](https://github.com/linq2db/linq2db/issues/3826): Improve error message for `CREATE TABLE` command when column database type cannot be determined automatically to include column member's .NET type name
- [#3829](https://github.com/linq2db/linq2db/issues/3829): [ClickHouse] add support for `ClickHouseDecimal` type from `ClickHouse.Client` provider
- [#3837](https://github.com/linq2db/linq2db/issues/3837): [Informix] Improve SQL generation for `Nvl` function
- [#3843](https://github.com/linq2db/linq2db/issues/3843): expose constructor of `DataReaderWrapper` class to unblock custom `DataReader` extensions implementation
- [#3854](https://github.com/linq2db/linq2db/issues/3854): [SQL Server] temporal tables support in schema/scaffold:
  - mark from/to validity range columns as read-only
  - mark temporal history table as read-only
  - add option to ignore history tables on schema load (`mssql-ignore-temporal-history-tables` flag in `linq2db.cli` and `GetSchemaOptions.IgnoreSystemHistoryTables` in schema API)
- [#3855](https://github.com/linq2db/linq2db/issues/3855): implement `IAsyncDisposable` on `DataContextTransaction`
- [#3863](https://github.com/linq2db/linq2db/issues/3863): disposal of transaction without explicit call to `Rollback` method will not call `Rollback` explicitly on transaction object anymore (transaction still be rolled back by database provider if needed)
  - **BREAKING** such transactions will not generate `RollbackTransaction` trace event anymore. Also we introduce new `DisposeTransaction` trace event as replacement
- [#3865](https://github.com/linq2db/linq2db/issues/3865): fixed `ValueConverter` support in remote context

***

### Release 4.3.0

- [#3462](https://github.com/linq2db/linq2db/issues/3462): support single query generation for queries with multiple `cross apply` clauses
- [#3759](https://github.com/linq2db/linq2db/issues/3759):
  - Update SQL Server 2022 support to RC.0 level (`chars` parameter support for `string.TrimEnd(string value, char[] chars)` and `string.TrimStart(string value, char[] chars)` mappings)
  - add `chars` parameter support for `string.TrimEnd(string value, char[] chars)` and `string.TrimStart(string value, char[] chars)` mappings for following databases:
    - SQLite
    - SAP HANA
    - PostgreSQL
    - Oracle
    - Informix
    - DB2
    - ClickHouse
    - SQL Server 2022
- [#3774](https://github.com/linq2db/linq2db/issues/3774): fix 4.2.0 regression with handling of `IN` clauses in columns

***

### Release 4.2.0

- [#1796](https://github.com/linq2db/linq2db/issues/1796): new `ClickHouse` database provider. See [details](#clickhouse) below
- [#3584](https://github.com/linq2db/linq2db/issues/3584): [PostgreSQL] Add `MERGE` queries support to `PostgreSQL` provider (requires PostgreSQL 15)
- [#3595](https://github.com/linq2db/linq2db/issues/3595): Add new command interceptor events `BeforeReaderDispose` and `BeforeReaderDisposeAsync` invoked before `DbDataReader` disposal
- [#3649](https://github.com/linq2db/linq2db/issues/3649): [PostgreSQL][SQLite] Improve `UPDATE ... FROM` queries support for PostgreSQL and SQLite
- [#3659](https://github.com/linq2db/linq2db/issues/3659): [SQL Server] Add initial support for SQL Server 2022:
  - new dialect `SqlServerVersion.v2022`
  - support for [INGORE NULLS](https://docs.microsoft.com/en-us/sql/t-sql/functions/first-value-transact-sql?view=sql-server-ver15) qualifier for FIRST_VALUE/LAST_VALUE window functions (requires CTP 2.0)
  - support for [IS [NOT] DISTINCT FROM](https://docs.microsoft.com/en-us/sql/t-sql/queries/is-distinct-from-transact-sql?view=sql-server-ver15) operator (requires CTP 2.1)
- [#3664](https://github.com/linq2db/linq2db/issues/3664): Fix parameters caching in `LoadWith` filters
- [#3667](https://github.com/linq2db/linq2db/issues/3667): Fix compatibility with `Npgsql` 7
- [#3668](https://github.com/linq2db/linq2db/issues/3668): Fixed `An item with the same key has already been added` error for `GroupBy` queries with eager load inroduced by 4.1.1 release
- [#3669](https://github.com/linq2db/linq2db/issues/3669): Fix duplicate columns detection for columns with conditional expressions
- [#3673](https://github.com/linq2db/linq2db/issues/3673): [Scaffold CLI] added new schema option to specify default database schema(s) explicitly (`default-schemas: string[]`)
- [#3676](https://github.com/linq2db/linq2db/issues/3676): [Scaffold CLI] fixed `transformation` option support from command line or `json` config
  - `none` value is recognized
  - help mentions proper name for `association` value (instead of non-existing `t4`)
- [#3679](https://github.com/linq2db/linq2db/issues/3679): [Scaffold] Add by-name filtering options for stored procedures, scalar and aggregate functions (table functions already covered):
  - `include-stored-procedures` / `exclude-stored-procedures`
  - `include-scalar-functions` / `exclude-scalar-functions`
  - `include-aggregate-functions` / `exclude-aggregate-functions`
- [#3683](https://github.com/linq2db/linq2db/issues/3683):
  - made changes to `Linq To DB` to support databases without transactions (e.g. `ClickHouse`)
  - added `TransientRetryPolicy` and `DbExceptionTransientExceptionDetector` classes to support new property `DbException.IsTransient` by retry policy mechanism. Available for `net6.0` tfm
- [#3684](https://github.com/linq2db/linq2db/issues/3684): fix `Argument types do not match` exception when `ValueConverter` with `HandlesNulls = true` option used
- [#3685](https://github.com/linq2db/linq2db/issues/3685): fix `null` values handling in enumerable sources to generate `NULL alias` instead of `NULLalias`, which could lead to sql errors for some databases
- [#3687](https://github.com/linq2db/linq2db/issues/3687): fix argument nullability tracking for `CAST` and some other functions to avoid null checks generation for non-nullable arguments
- [#3689](https://github.com/linq2db/linq2db/issues/3689): Fix date/time strings generation i queries to generate fixed-length components (e.g. `01:05` for time instead of `1:5`)
- [#3690](https://github.com/linq2db/linq2db/issues/3690):
  - obsolete `SqlDataType.GetDataType` method (`MappingSchema.GetDataType` should be used)
   - **[BREAKING]**: Conversion functions that doesn't specify exact type (`System.Convert.ToDecimal`, `LinqToDB.Common.Convert`) change behavior for decimal type. They will generate cast to decimal type definition, specified in mapping schema (usually `decimal` without precision and scale set). Previously they used hardcoded `decimal(29, 10)` type.
     - Workarounds:
       - register suitable decimal type mapping in mapping schema (not recommended): `mappingSchema.AddScalarType(typeof(decimal), new SqlDataType(new DbDataType(typeof(decimal), DataType.Decimal, null, null, <precision>, <scale>)));`
       - use better-typed convert API, e.g. `Sql.Convert(Sql.Types.Decimal(<precision>,<scale>), convertedValue)`
     - List of affected providers:
       - DB2: `decimal(29, 10)` -> `decimal`
       - Firebird: `decimal(18, 10)` -> `decimal`
       - SQL Sever CE: `decimal(29, 10)` -> `decimal`
       - SQL Sever: `decimal(29, 10)` -> `decimal`
       - MySQL/MariaDB: `decimal(29, 10)` -> `decimal`
       - SAP/Sybase ASE: `decimal(29, 10)` -> `decimal`
       - Oracle: `decimal(29, 10)` -> `decimal`
- [#3697](https://github.com/linq2db/linq2db/issues/3697): Fix issue when `UpdateWithOutput` could generate `NULL` instead of column in outputs for complex queries
- [#3701](https://github.com/linq2db/linq2db/issues/3701): add support for sequence name configuration for column using fluent mapping (`UseSequence` or `HasAttribute(SequenceNameAttribute)` methods)
- [#3703](https://github.com/linq2db/linq2db/issues/3703): [PostgreSQL] add support for `NpgsqlInterval` type from `Npgsql` 6
- [#3705](https://github.com/linq2db/linq2db/issues/3705):
  - [PostgreSQL] add type hint to `bytea` and `uuid` literals (`::bytea`, `::uuid`)
  - [PostgreSQL] add new SQL dialect `PostgreSQLVersion.v15`. Enables `MERGE` query generation for `InsertOrReplace/Update` APIs
- [#3709](https://github.com/linq2db/linq2db/issues/3709): [CLI] fix `ColumnType not provided by schema for table` error for `Access` scaffolding using `ODBC` provider for `decimal` columns
- [#3728](https://github.com/linq2db/linq2db/issues/3728): [Scaffold] Fix generation of association name for one-to-one relation over primary keys in CLI tool
- [#3729](https://github.com/linq2db/linq2db/issues/3729): fix `Merge` into table with query filters defined
- [#3731](https://github.com/linq2db/linq2db/issues/3731): [Oracle] reset `ArrayBindCount` property on `OracleCommand` to prevent exception on command reuse after `BulkCopy` in `AlternativeBulkCopy.InsertInto` mode
- [#3738](https://github.com/linq2db/linq2db/issues/3738): remove incorrect database type inferring logic for binary expressions
- [#3747](https://github.com/linq2db/linq2db/issues/3747): [Scaffold] CLI tool improvements
  - tolerate allow trailing commas in JSON config
  - properly detect and report conflicting options in JSON config

#### ClickHouse

This release adds initial support for `ClickHouse` database.

Following providers/protocols supported:

- MySQL interface using [MySqlConnector](https://github.com/mysql-net/MySqlConnector)
- HTTP(S) interface using [ClickHouse.Client](https://github.com/DarkWanderer/ClickHouse.Client)
- TCP (binary) interface using [Octonica.ClickHouseClient](https://github.com/Octonica/ClickHouseClient)

To see supported data type mappings and related issues with providers see [this](https://github.com/linq2db/linq2db/blob/master/Source/LinqToDB/DataProvider/ClickHouse/README.md) document.

##### Additional features

- added new bulk copy options `BulkCopyOptions.MaxDegreeOfParallelism` and `BulkCopyOptions.WithoutSession` for `ClickHouse.Client` HTTP provider
- CLI scaffold: implemented
- T4 scaffold: not planned
- query parameters: not supported/not planned
- LinqPAD support: will be added in future releases
- Custom query hints/extensions: will be added in future releases (feedback on which extensions needed is welcome)

***

### Release 4.1.1

- [#3629](https://github.com/linq2db/linq2db/issues/3629): fix `OUTPUT`/`RETURNING` into temporary table
- [#3630](https://github.com/linq2db/linq2db/issues/3630): [SQL Server] fix type load exception for self-extracting applications
- [#3633](https://github.com/linq2db/linq2db/issues/3633): fix `AddLinqToDBContext` DI helper to support context constructors with additional parameters
- [#3636](https://github.com/linq2db/linq2db/issues/3636): fix `GROUP BY` query caching
- [#3637](https://github.com/linq2db/linq2db/issues/3637): improve typing of `CASE` expression

***

### Release 4.1.0

- [#861](https://github.com/linq2db/linq2db/issues/861): fix tracing for misconfigured/failed connection
- [#3557](https://github.com/linq2db/linq2db/issues/3557): Fix cases where optional association could produce `INNER JOIN` instead of `LEFT JOIN`
- [#3585](https://github.com/linq2db/linq2db/issues/3585): [Oracle] Add support for `Devart.Data.Oracle` provider
  - [#3610](https://github.com/linq2db/linq2db/issues/3610): fix scaffolding exception with Oracle 19+
- [#3591](https://github.com/linq2db/linq2db/issues/3591): fix exception from `DataContext.ctor(IDataProvider, string)` contructor
- [#3594](https://github.com/linq2db/linq2db/issues/3594): Improve typing of `COALESCE`
- [#3596](https://github.com/linq2db/linq2db/issues/3596): [SQL Server] Add `OPENJSON` function mapping (`LinqToDB.DataProvider.SqlServer.SqlFn.OpenJson(...)`)
- [#3601](https://github.com/linq2db/linq2db/issues/3601): [Oracle] Specify `DataType.Cursor` for `ref cursor` columns in scaffold
- [#3604](https://github.com/linq2db/linq2db/issues/3604): [Scaffold] Fixed include/exclude object filter parsing when both `schema` and `name`/`regex` filters specified
- [#3611](https://github.com/linq2db/linq2db/issues/3611): [MySQL] Support `ColumnAttribute.Length` values in [256, 65535] range for `VarChar` type for `CreateTable` APIs
- [#3612](https://github.com/linq2db/linq2db/issues/3612): [Scaffold] Fix exception from `help scaffold` command from some environments
- [#3615](https://github.com/linq2db/linq2db/issues/3615): [Scaffold] Update naming options configuration approach. Now you don't need to specify all naming option properties from scratch if you want to change only one property (e.g. name casing) - values for unspecified properties will be taken from default option value

***

### Release 4.0.1

- [#1878](https://github.com/linq2db/linq2db/issues/1878): fix `Guid` compatibility issue with `Microsoft.Data.SQLite` 3+. Now it is possible to map `Guid` to text by using `Column(DbType="TEXT")` or `Column(DataType=DataType.ONE_OF_TEXT_TYPES_HERE)`. Default `Guid` mapping is still remains `binary`
- [#3563](https://github.com/linq2db/linq2db/issues/3563): add missing dependencies to `linq2db.PostgreSQL` T4 nuget
- [#3564](https://github.com/linq2db/linq2db/issues/3564): fixed issues with pre-generated scaffolding template (missing namespace and NRT warnings). Thanks to [Alexey Zagoskin](https://github.com/Powerz) for fixing it
- [#3567](https://github.com/linq2db/linq2db/issues/3567): improve scaffold tool help to include default switch values for T4 compat mode
- [#3568](https://github.com/linq2db/linq2db/issues/3568): fixed names of generated files by scaffold tool to have same name as generated class even after class renamed by scaffold interceptor
- [#3569](https://github.com/linq2db/linq2db/issues/3569): add new switch `--generated-suffix` to scaffold tool to add `.generated` suffix to generated file names
- [#3570](https://github.com/linq2db/linq2db/issues/3570): [SQL Server] fixed handling of date/time types (`DateTime`, `DateTimeOffset`, `TimeSpan`, `DateOnly`, `SqlDateTime`) to respect precision and generate typed literals in queries
- [#3575](https://github.com/linq2db/linq2db/issues/3575): fixed `linq2db.AspNet` nuget to reference proper version of `Microsoft.Extensions.DependencyInjection`
- [#3578](https://github.com/linq2db/linq2db/issues/3578): [CLI] removed database name from name of table/view/procedure, returned by schema by default. Use new option `--database-in-name` to re-enable it

***

### Release 4.0.0

No changes since RC2.

***

### Release 4.0.0 Release Candidate 2

<a name='release-400-rc2'></a>

- [#3502](https://github.com/linq2db/linq2db/issues/3502): `DateOnly` type support (all databases)
- [#3506](https://github.com/linq2db/linq2db/issues/3506): fix missing `Nullable<T>.Value` handling in some places
- [#3534](https://github.com/linq2db/linq2db/issues/3534): Scaffold tool improvements
  - adds extension points to customize generated entities, procedures, functions and associations
  - adds `--equatable-entities` option to implement functionality of `Equatable.ttinclude` T4 template in scaffold tool (generation of `IEquality<T>` interface implementation on entity classes)
- [#3536](https://github.com/linq2db/linq2db/issues/3536): add support for [database packages](#packages-support)
  - add new `Package` property in `Sql.TableFunctionAttribute`
  - automatically wrap table function call in `TABLE(...)` wrapper for `DB2 LUW` and `Oracle 11` dialects
  - [Oracle][Firebird][DB2] add support for functions and packages to Schema API
  - add support for package procedures and functions to scaffold by `T4` and [`linq2db.cli`](https://www.nuget.org/packages/linq2db.cli)
- [#3541](https://github.com/linq2db/linq2db/issues/3541): improve value nullability tracking, annotate functions in `Sql` class for nullability where it was missing
- [#3542](https://github.com/linq2db/linq2db/issues/3542): fix support for members, marked with `Sql.ExpressionAttribute`, in association queries
- [#3543](https://github.com/linq2db/linq2db/issues/3543): fix rare `IndexOutOfRangeException` in queries with functions
- [#3547](https://github.com/linq2db/linq2db/issues/3547): add `Sql.NullIf` function, mapped to `NULLIF` sql function (with emulation for databases which doesn't support it)
- [#3548](https://github.com/linq2db/linq2db/issues/3548): fixed regression in `PostgreSQL` enum parameters support

#### Packages Support

Database package is a named group of procedures and functions (plus types and variables in some DB), supported by following databases:

- Oracle Database
- DB2 LUW (under `module` name)
- Firebird 3+
- SAP HANA (under `library` name)
- MariaDB

By support of packages in `Linq To DB` we mean following:

- support of package table functions mapping using `Sql.TableFunctionAttribute` by adding `Sql.TableFunctionAttribute.Package` property to specify package name for function
- support of package functions and procedures in `Schema API`
- support for package functions and procedures in database scaffolding (using both `T4` templates and [`linq2db.cli`](https://www.nuget.org/packages/linq2db.cli) utility)

Known issues and limitations:

- [MariaDB] package stored procedures cannot be called using stored procedure API (`QueryProc`, `ExecuteProc`) with `MySql.Data` provider (provider bug). User should use raw sql calls like `CALL package.proc(...)` or even better - switch to [`MySqlConnector`](https://mysqlconnector.net/) provider
- [SAP HANA] library functions/procedures cannot be called using native unmanaged provider due to provider bug. `ODBC` provider should be used
- [SAP HANA][MariaDB] packages not supported by Schema API (and scaffolding) because those databases don't expose required metadata

***

### Release 4.0.0 Release Candidate 1

<a name='release-400-rc1'></a>

Also contains all changes from [Release 3.7.0](#release-370).

For migration notes check [this document](Version-4-Migration).

- [#2452](https://github.com/linq2db/linq2db/issues/2452): Query Extensions API to extend queries with custom SQL at specific points. See [details](#query-extensions-api) below.
  - [SQL Server] adds new SQL Server dialect levels: `SqlServerVersion.v2014` and `SqlServerVersion.v2019` enum values and `ProviderName.SqlServer2019` identifier
  - improved SQL optimization to remove unnecessary nesting for SQL like `SELECT * FROM (sub-query)`
- [#2582](https://github.com/linq2db/linq2db/issues/2582): Improved handling of changes to mapping schema to avoid issues when changes ignored due to cached queries
- [#2619](https://github.com/linq2db/linq2db/issues/2619): Improved support for set (`UNION`-like) queries with sorting
- [#3097](https://github.com/linq2db/linq2db/issues/3097): Default value for `Configuration.ContinueOnCapturedContext` setting changed to `false` 
(as it should be)
- [#3098](https://github.com/linq2db/linq2db/issues/3098): New database scaffold dotnet tool implemented to replace old T4 templates. See [more details](#scaffold-tool) below
- [#3410](https://github.com/linq2db/linq2db/issues/3410): Remote context refactoring. See [more details](#remote-context) below
- [#3411](https://github.com/linq2db/linq2db/issues/3411): [SQL Server] Added pre-generated mappings for `sys` and `INFORMATION_SCHEMA` schemas for SQL Server:
  - `LinqToDB.DataProvider.SqlServer.SqlType`: type name generators
  - `LinqToDB.DataProvider.SqlServer.SqlFn`: functions and variables
  - `LinqToDB.Tools.DataProvider.SqlServer.Schemas.SystemDB` (`linq2db.Tools` nuget package): system schemas data context
- [#3441](https://github.com/linq2db/linq2db/issues/3441): Removed `netcoreapp2.1` TFM. Linq To DB still available for .NET Core 2.1 using `netstandard2.0` TFM.
- [#3496](https://github.com/linq2db/linq2db/issues/3496): [**Breaking**] `DataConnection.GetTable` instance methods removed as they duplicate existing data context extension methods
- [#3499](https://github.com/linq2db/linq2db/issues/3499): Enable CTE support for SQL Server 2005 dialect
- ~[#3502](https://github.com/linq2db/linq2db/issues/3502): `DateOnly` type support (all databases)~ due to packaging error, feature will be shipped in RC2
- [#3508](https://github.com/linq2db/linq2db/issues/3508): Support `IReadOnlyDictionary.ContainsKey` method in queries
- [#3514](https://github.com/linq2db/linq2db/issues/3514): fixed SQL generation for `[NOT] IN (...)` operator in `CompareNullsAsValues = true` mode to use value semantics for `null`
- [#3515](https://github.com/linq2db/linq2db/issues/3515): [**Breaking**] `Sql.<type_name>` database type name generation properties moved to `Sql.Types.` "namespace" to avoid naming conflicts with `using static Sql` code
- [**BREAKING**] Default SQL Server provider changed from `System.Data.SqlClient` to `Microsoft.Data.SqlClient` (you can use `SqlServerTools.Provider` property to change it back)
- [**BREAKING**] We are marking most of database provider classes (e.g. `SqlServerDataProvider`) as abstract. There are many reasons why you shouldn't create provider instance manually. Proper way to get provider instance is to use `<dbname>Tools.GetDataProvider(...)` method or `DataConnection.GetDataProvider(...)` methods. Only situation when you should create provider instance manually is when you sub-class provider to override some of it's methods. And even is such case it is better to register your provider implementation in `DataConnection` with `AddDataProvider` method.

#### Obsoletions

With this release we obsolete some code:
- several properties on `AssociationAttribute` (`KeyName`, `BackReferenceName`, `IsBackReference`, `Relationship`) and `Relationship` enum. It was never used by `Linq To DB`. T4 templates and scaffolding tool will not generate them anymore.
- `DataConnection.OnTrace` property. `LinqToDBConnectionOptions.OnTrace` should be used instead

#### Scaffold Tool

For detailed documentation check [tool nuget readme](https://www.nuget.org/packages/linq2db.cli#readme-tab).

For feedback please use this [discussion](https://github.com/linq2db/linq2db/discussions/3531).

With RC1 we release initial version of new database scaffolding tool, which will replace T4 templates.

We still plan to ship T4 templates for `Linq To DB` 4 but there is no plans to introduce new T4 features and we plan to obsolete them completely in future (`Linq To DB` 5 probably?).

##### Reasoning behind new tool development

T4 templates were introduced in times when Visual Studio and .NET Framework were only development platforms and doesn't reflect current situation on .NET world anymore:
- Visual Studio not available for non-Windows platforms and other IDEs lack support for T4 preprocessing features, required for them to work (e.g. MS Build directives support)
- Visual Studio runs T4 templates using .NET Framework as host (x86 for VS 2017- and x64 process for VS 2022). Other IDEs could use .NET Core runtime for T4 templates. This creates two usability issues:
  - T4 templates use .NET Framework versions of database providers which will not work in .NET Core hosts
  - some database providers use unmanaged code and require specific process architecture, but Visual Studio doesn't give users such choice

Those are main issues, that cannot be solved with current T4 templates architecture.

##### What is implemented for current release

Current release (4.0.0-rc.1) ships base scaffolding functionality and initial support for scaffolding process customization. Currently customization includes hooks for database schema load process. Later releases will add remaining hooks.

List of additional changes:
- new implementation has full control over generated code which allows it to generate valid code where T4 templates could fail:
  - automatic detection and fix of naming conflicts within generated code including method overloads handling and support for conflicting names from external code (requires from user to provide list of conflicting identifiers). E.g. see T4 issues [#1586](https://github.com/linq2db/linq2db/issues/1586), [#2168](https://github.com/linq2db/linq2db/issues/2168)
  - proper literals generation (e.g. escaping of characters in generated strings)
  - language-agnostic model allows generation of data model code in different laanguages/language versions (current release ships only C# support, but at least we plan to introduce F# support in future)
- [#1825](https://github.com/linq2db/linq2db/issues/1825): file-per-class code generation support
- [#1897](https://github.com/linq2db/linq2db/issues/1897): new option to enable/disable `@return` parameter scaffolding for SQL Server stored procedures
- [#2793](https://github.com/linq2db/linq2db/issues/2793): new options to generate various entity `Find` and `FinqQuery` extension methods including async versions of `Find` method
- [Access] support for mixed scaffold mode, which use two database providers to load database schema: `OLE DB` and `ODBC` providers. This feature is needed, because both `OLE DB` and `ODBC` providers return incorrect/incomplete database schema, but those errors are specific only to one provider. When we merge schemas from both providers - we receive correct database schema for scaffolding.
- support for generation of async stored procedure mappings
- more flexible identifier generation options
- extensibility hook to override type mapping of database type to .NET type
- added some more database types mappings to .net type in scaffolding (previously default type `object` used):
  - [Sybase]: `usmallint`, `uint`, `ubigint`, `bigdatetime`, `date`, `time`, `bigtime`, `unitext`, `unichar`, `univarchar`
  - [Oracle]: `BINARY_INTEGER`, `INTERVAL DAY TO ...`, `INTERVAL YEAR TO MONTH`
  - [PostgreSQL]: `regproc` (as string), custom enum (as string, in future we can add C# enum generation), default multi-/range types (except custom range types)
  - scaffold tool will generate error message to console when unknown database type found. If this is standard type - it is recommended to report it as issue so we can add support for it. For custom types it is better to use extensibility hook to specify proper .net type for it.

#### Remote Context

Thanks to [Vyacheslav Avdeev](https://github.com/lsoft) for [PR](https://github.com/linq2db/linq2db/pull/3410).

Remote data context allows `Linq To DB` to work with database indirectly by sending LINQ queries to server application over network. This feature were introduced long time ago mostly to facilitate database access for runtimes with limited functionality (e.g. currently dead Silverlight or mono-based mobile frameworks).

Initial implementation (pre-4 versions) supported only .NET Framework and two transports:
- WCF
- ASMX WebServices

With 4.0 release we refresh this feature to support modern frameworks and transports. List of changes:
- ASMX WebServices transport support removed (this is quite old technology nobody really should use for at least recent 10 years)
- GRPC transport added
- .NET (Core) support added (GRPC-only, WCF implementation currently limited to .NET Framework)
- WCF an GRPC transport implemntations support async transport APIs for async queries (previously all network requests used blocking API)
- Core functionality made public to allow new transport implementations by users
- Existing transports implementations moved to separate nugets: [linq2db.Remote.Grpc](https://www.nuget.org/packages/linq2db.Remote.Grpc) and [linq2db.Remote.Wcf](https://www.nuget.org/packages/linq2db.Remote.Wcf)

We can add more transports in future on request.

For use examples, check examples [here](https://github.com/linq2db/linq2db/tree/master/Examples) (Remote folder).

#### Interceptors (Changes since previous releases)

You can also read about interceptors in `Linq To DB` [here](https://linq2db.github.io/articles/general/interceptors.html).

This release brings some changes to interceptors feature, introduced in earlier releases:
- added new `IUnwrapDataObjectInterceptor` interceptor to work with data connection wrappers, e.g. [MiniProfiler](https://miniprofiler.com/dotnet/)
- moved `EntityCreated` interceptor event from `IDataContextInterceptor` to separate `IEntityServiceInterceptor`
- renamed `ConnectionOpenedEventData` and `ConnectionOpeningEventData` structs to `ConnectionEventData`
- added `AfterExecuteReader` interceptor to `ICommandInterceptor` interface

##### `ICommandInterceptor.AfterExecuteReader`

This interceptor is triggered after `DbCommand.ExecuteReader(CommandBehavior)` or `DbCommand.ExecuteReaderAsync(CommandBehavior, CancellationToken)` calls before reader enumeration. E.g. it could be used to modify reader options before data enumeration (Oracle provider could have such options).

```cs
void AfterExecuteReader(CommandEventData eventData, DbCommand command, CommandBehavior commandBehavior, DbDataReader dataReader);
```

##### `IUnwrapDataObjectInterceptor`

This interceptor replaces old approach, where you need to register unwrap expressions in `MappingSchema`.

Example of interceptor implementation for `MiniProfiler`:
```cs
public class UnwrapProfilerInterceptor : UnwrapDataObjectInterceptor
{
    // as interceptor is thread-safe, we will create
    // and use single instance of it
    public static readonly IInterceptor Instance = new UnwrapProfilerInterceptor();

	public override DbConnection UnwrapConnection(IDataContext dataContext, DbConnection connection)
	{
		return connection is ProfiledDbConnection c ? c.WrappedConnection : connection;
	}

	public override DbTransaction UnwrapTransaction(IDataContext dataContext, DbTransaction transaction)
	{
		return transaction is ProfiledDbTransaction t ? t.WrappedTransaction : transaction;
	}

	public override DbCommand UnwrapCommand(IDataContext dataContext, DbCommand command)
	{
		return command is ProfiledDbCommand c ? c.InternalCommand : command;
	}

	public override DbDataReader UnwrapDataReader(IDataContext dataContext, DbDataReader dataReader)
	{
		return dataReader is ProfiledDbDataReader dr ? dr.WrappedReader : dataReader;
	}
}
```


#### Query Extensions API

For additional examples and documentation check [this article](https://linq2db.github.io/articles/sql/Query-Extensions.html).

This new feature allows user to attach custom SQL to LINQ queries at several extension points. This allows user to use most of database-specific SQL statement extensions without downgrading to raw SQL queries. E.g.:
- specify database-specific query hints
- annotate queries or subqueries with custom comments
- other non-hint code

In previous versions of Linq To DB we had several API with for limited support for such extensions:
- `With` table extension to add MSSQL-style table hint `WITH(...)`
- `WithTableExpression` table extension to add custom table hint
- `DataConnection.QueryHints` and `DataConnection.NextQueryHints` to add custom SQL as suffix or prefix to next query or queries.
Those API are still available and supported. E.g. `QueryHints` and `NextQueryHints` could be useful with non-linq APIs, where new extensions API is not available.

For list of extension points check [this table](https://linq2db.github.io/articles/sql/Query-Extensions.html#common-hint-extensions). More extension points could be added on user request in future.

Except extension API itself we added a lot of ready-to-use extensions (mostly hints) for supported databases. If you still cannot find some hint you need - create feature request. Available extensions:
- `LinqToDB.DataProvider.<DB_NAME>.<DB_NAME>Hints` extension classes with db-specific hints for tables, joins, (sub-)queries
- `As<DB_NAME>()` extension method in `LinqToDB.DataProvider.<DB_NAME>` namespace which could be used to specify extensions for use with specific database type. This is useful for applications that should work with multiple database types (e.g. `Oracle` and `PostgreSQL`) and want to use same linq query code for them.
- `QueryName` extension to set a name to (sub-)query which will be used as reference to query from query-specific hint (for databases with query naming support)
- `TableId`, `Sql.TableName`, `Sql.TableSpec`, `Sql.TableAlias` methods to assign identifier to table for reference from hint. It is similar to `QueryName` but used for tables instead of (sub-)queries
- hint methods `TableHint`, `TablesInScopeHint`, `IndexHint`, `JoinHint`, `SubQueryHint` and `QueryHint`

To create your own extension you can use new `Sql.QueryExtensionAttribute` attribute. Check existing extensions for examples.

***

### Release 4.0.0 Previews 2-10

No new v4-specific features, only changes from underlying v3 releases:
- <a name='release-400-preview10'>preview 10</a>: updates from [3.6.0](#release-360)
- <a name='release-400-preview9'>preview 9</a>: updates from [3.5.2](#release-352)
- <a name='release-400-preview8'>preview 8</a>: updates from [3.5.1](#release-351)
- <a name='release-400-preview7'>preview 7</a>: updates from [3.5.0](#release-350)
- <a name='release-400-preview6'>preview 6</a>: updates from [3.4.5](#release-345)
- <a name='release-400-preview5'>preview 5</a>: updates from [3.4.4](#release-344)
- <a name='release-400-preview4'>preview 4</a>: updates from [3.4.3](#release-343)
- <a name='release-400-preview3'>preview 3</a>: updates from [3.4.2](#release-342)
- <a name='release-400-preview2'>preview 2</a>: updates from [3.4.1](#release-341)

***

### Release 4.0.0 Preview 1

<a name='release-400-preview1'></a>

With this release we start to publish previews of Linq To DB v4 (planned for release later this year). Previews will include all features and fixes from current v3 release and new features, fixes and refactorings for v4.
This will allow users to use new features that require major version bump due to breaking changes without waiting for next major release.

Based on: v3.4.0. For migration notes check [this document](Version-4-Migration)

- [#2728](https://github.com/linq2db/linq2db/issues/2728):
  - [#2643](https://github.com/linq2db/linq2db/issues/2643): MARS-like queries support. This feature will unblock execution of queries inside of enumeration of another open query without force materialization (e.g. using `ToList()/ToAray()` methods):
    - [SQL Server]: `MultipeActiveResutSets=true` connection option required
    - [MySQL/MariaDB][PostgreSQL]: feature is not supported due to provider or database protocol limitation
  - [**BREAKING**] Access to current command data for data connection changed to support multiple active commands:
    - `DataConnection.LastParameters` property removed
    - `DataConnection.Command` property removed
    - procedures, generated using T4 templates should be regenerated, as they were using removed properties
    - to access `Command` (on handle other events/extension points in future) we introduce interceptors support, similar to [EF.Core interceptors](https://docs.microsoft.com/en-us/ef/core/logging-events-diagnostics/interceptors) with some distinctions (see below)
    - following `DataConnection` events replaced with interceptors: `OnBeforeConnectionOpen`, `OnBeforeConnectionOpenAsync`, `OnConnectionOpened`, `OnConnectionOpenedAsync`
  - [Sybase] Native bulk copy against temp table will automatically downgrade to SQL-based bulk copy implementation as native bulk copy doesn't support temp tables
- [#2812](https://github.com/linq2db/linq2db/issues/2812): SQL Server 2000 support was removed (min. supported SQL Server version is 2005 from now). If you still need to support SQL Server 2000 you can use Linq To DB v3 or request support restore from us.
- [#2826](https://github.com/linq2db/linq2db/issues/2826): Adds `Guid` type support for Firebird provider. Thanks to [Eugine Savin](https://github.com/jack128) for contribution. By default `Guid` is mapped to Firebird `UUID` type (`CHAR(16) CHARACTER SET OCTETS`). Specifying `DataType = DataType.Char` or `DataType = DataType.NChar` in mapping will map it to `CHAR(38)`
  - [#2823](https://github.com/linq2db/linq2db/issues/2823): properly generate type name for `Guid` (e.g. for `CreateTable` API or `CAST` expression) based used `DataType`
  - [#2833](https://github.com/linq2db/linq2db/issues/2833): support literal generation for `Guid` based used `DataType`
  - note that in previous versions of `Linq To DB` `Guid` support was limited to `CHAR(38)` string literal generation for parameters and if you want to preserve mapping to string for your model, you should annotate it with `DataType.Char`
- [#2929](https://github.com/linq2db/linq2db/issues/2929): replace se of ADO.NET interfaces with corresponding base classes everywhere. Following changes done:
  - `IDataRecord`/`IDataReader` -> `DbDataReader`
  - `IDbCommand` -> `DbCommand`
  - `IDbDataParameter` -> `DbParameter`
  - `IDbConnection` -> `DbConnection`
  - `IDbTransaction` -> `IDbTransaction`
  - [**BREAKING**]: if you had custom mappings that use those interfaces, they should be updated to use classes, e.g.:
    - `MiniProfiler` unwrap mappings
    - custom data reader expressions
- [#2930](https://github.com/linq2db/linq2db/issues/2930): remove functionality, marked in v3 with `[Obsolete]` attribute
- [#2941](https://github.com/linq2db/linq2db/issues/2941):
  - [#2934](https://github.com/linq2db/linq2db/issues/2934): add support for `LinqToDbConnectionOptions` to `DataContext`
  - [#2927](https://github.com/linq2db/linq2db/issues/2927): migrate more `DataConnection` and `DataContext` events to interceptors (see details [here](https://github.com/linq2db/linq2db/wiki/Releases-and-Roadmap#interceptors))
  - [SQLite] use `temp` schema for temporary tables explicitly to avoid naming conflicts with `main` schema

#### Interceptors

With this release we are starting migration from events to interceptors and introduce first interceptor events. For initial release we concentrating on migration of already existed functionality (e.g. events) to interceptors. New events without prior implementation will be added later or on request.

To see which APIs were replaced with interceptors check [migration notes](Version-4-Migration)

###### `ICommandInterceptor`

This interceptor provides access to events and operations associated with database command.

```cs
// triggered after command initialization but before execution
// it provides access to prepared SQL command and parameters
DbCommand CommandInitialized(CommandEventData eventData, DbCommand command);

// triggered before `ExecuteScalar/ExecuteScalarAsync` call on command
// and could replace actual call by returning results from interceptor
Option<object?>       ExecuteScalar     (
                                         CommandEventData eventData,
                                         DbCommand command,
                                         Option<object?> result);
Task<Option<object?>> ExecuteScalarAsync(
                                         CommandEventData eventData,
                                         DbCommand command,
                                         Option<object?> result,
                                         CancellationToken cancellationToken);

// triggered before `ExecuteNonQuery/ExecuteNonQueryAsync` call on command
// and could replace actual call by returning results from interceptor
Option<int>       ExecuteNonQuery     (CommandEventData eventData, DbCommand command, Option<int> result);
Task<Option<int>> ExecuteNonQueryAsync(
                                       CommandEventData eventData,
                                       DbCommand command,
                                       Option<int> result,
                                       CancellationToken cancellationToken);

// triggered before `ExecuteReader/ExecuteReaderAsync` call on command
// and could replace actual call by returning results from interceptor
Option<DbDataReader>       ExecuteReader     (
                                              CommandEventData eventData,
                                              DbCommand command,
                                              CommandBehavior commandBehavior,
                                              Option<DbDataReader> result);
Task<Option<DbDataReader>> ExecuteReaderAsync(
                                              CommandEventData eventData,
                                              DbCommand command,
                                              CommandBehavior commandBehavior,
                                              Option<DbDataReader> result,
                                              CancellationToken cancellationToken);

struct CommandEventData
{
    public DataConnection DataConnection { get; }
}

// convinience base class for custom interceptor implementation
public abstract class CommandInterceptor : ICommandInterceptor
{
    // interceptor implementation as no-op virtual methods
}
```

###### `IDataContextInterceptor`

This interceptor provides access to events and operations associated with database context (built-in class that implements `IDataContext`, e.g. `DataConnection` or `DataContext`).

```cs
// triggered when new entity created during query materialization
// (except queries with explicit constructor call)
object EntityCreated(DataContextEventData eventData, object entity);

// triggered before data context instance `Close/CloseAsync` method execution
void OnClosing(DataContextEventData eventData);
Task OnClosingAsync(DataContextEventData eventData);

// triggered after data context instance `Close/CloseAsync` method execution
void OnClosed(DataContextEventData eventData);
Task OnClosedAsync(DataContextEventData eventData);

struct DataContextEventData
{
    public IDataContext Context { get; }
}

// convinience base class for custom interceptor implementation
public abstract class DataContextInterceptor : IDataContextInterceptor
{
    // interceptor implementation as no-op virtual methods
}
```

###### `IConnectionInterceptor`

This interceptor provides access to events and operations associated with database connection.

```cs
// triggered before data connection `Open/OpenAsync` method execution
void ConnectionOpening(ConnectionOpeningEventData eventData, DbConnection connection);
Task ConnectionOpeningAsync(
                            ConnectionOpeningEventData eventData,
                            DbConnection connection,
                            CancellationToken cancellationToken);

// triggered after data connection `Open/OpenAsync` method execution
void ConnectionOpened(ConnectionOpenedEventData eventData, DbConnection connection);
Task ConnectionOpenedAsync(
                           ConnectionOpenedEventData eventData,
                           DbConnection connection,
                           CancellationToken cancellationToken);

struct ConnectionOpenedEventData
{
    public DataConnection DataConnection { get; }
}

// convinience base class for custom interceptor implementation
public abstract class ConnectionInterceptor : IConnectionInterceptor
{
    // interceptor implementation as no-op virtual methods
}
```

##### Configuration

To register interceptor you can use:
- `AddInterceptor` method on data context (e.g. `DataConnection` or `DataContext`)
- add interceptor to `LinqToDbConnectionOptions` using `LinqToDbConnectionOptionsBuilder.AddInterceptor(interceptor)` API
- for one-time execution of `ICommandInterceptor.CommandInitialized` event you can use `db.OnNextCommandInitialized(interceptor delegate)` method on `DataConnection` or `DataContext`

```cs
// registration in DataContext
using (var ctx = new DataContext(...))
{
    ctx.AddInterceptor(interceptor);

    // one-time command prepared interceptor
    ctx.OnNextCommandInitialized((args, cmd) =>
    {
        // save next command parameters to external variable
        parameters = cmd.Parameters.Cast<DbParameter>().ToArray();
	return cmd;
    });
}

// registration in DataConnection
using (var ctx = new DataConnection(...))
{
    ctx.AddInterceptor(interceptor);

    // one-time command prepared interceptor
    ctx.OnNextCommandInitialized((args, cmd) =>
    {
        // set oracle-specific command option for next command
        ((OracleCommand)command).BindByName = false;
    });
}

// registration in DataConnection using fluent configuration
var builder = new LinqToDbConnectionOptionsBuilder()
    .UseSqlServer(connectionString)
    .WithInterceptor(interceptor);
var dc = new DataConnection(builder.Build());
```
