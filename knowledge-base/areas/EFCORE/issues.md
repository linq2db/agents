---
area: EFCORE
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: high
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
---

# EFCORE -- GitHub themes

## Open themes

- **Query logging and diagnostics** -- Gaps in visualizing generated SQL and excluding sensitive data from logs within EF Core integration contexts. Open: #4645 (query logging visibility), #4651 (sensitive data exclusion in logs). Documentation and tooling improvements are still needed for debugging linq2db queries via EF Core.

- **Include and navigation loading** -- Challenges with eager loading of related entities and collections in entity hierarchies, especially with inheritance patterns. Open: #4012 (eager include of collections into CTE results), #4628 (inherited navigation population). Closed precedent #4603 (ThenInclude inside a recursive CTE, closed 2026-06-14). Recurring pattern in complex entity graphs.

- **Mapping incompatibilities with inheritance** -- EF Core TPH (Table Per Hierarchy) discriminator handling and inherited property materialization not translating correctly. Open: #4644 (inherited properties unnecessarily in SQL), #4666 (Merge into TPH table with discriminator), #4628 (inherited navigation interaction). Entity construction and calculated column expansion were addressed in closed PR #5578.

- **EF Core integration lifecycle gaps** -- Transaction, context registration and state management issues when bridging EF Core contexts to linq2db queries. Open: #4653 (transaction assignment on pre-created queryables), #4649 (Set() method tracking semantics, updated 2026-07-11), #4877 (Npgsql TransactionScope with prepared transactions disabled), #4811 (registering multiple DbContext types). Connection leak in the ToLinqToDB helper (#5364) is closed and listed under Resolved themes.

- **Provider support, types and documentation** -- Limited provider support documentation, configuration gaps and type integration for EF Core. Open: #4611 (review of supported providers list and testing matrix), #4665 (integration with EFCore.NetTopologySuite types).

- **Value converters with CLR logic** -- EF Core ValueConverter definitions that run CLR code, or that meet a PostgreSQL/NodaTime read path, failing when linq2db translates or materializes the column. Open: #5981 (Npgsql UseNodaTime read of a value-converted DateTime column, updated 2026-11-10). Recent closed regressions #5975, #5976 and #6181 are listed under Resolved themes.

- **Query filters and query cache keys** -- EF Core global query filters that capture values feeding the linq2db query cache. Open: #6235 (cache reuses queries across mapping schemas whose filters capture different values, opened 2026-11-01).

- **Batch update SQL generation** -- EF Core write paths emitting SQL that a provider rejects. Open: #6180 (batch update with ORDER BY throws a near "ORDER" syntax error, opened 2026-10-27).

- **Shadow properties** -- EF Core shadow properties not visible to linq2db mapping, including temp-table and discriminator cases. Open: #3174 (shadow property with a temp table, MSSQL), discussion [Configure Linq2DB.EntityFrameworkCore to respect shadow Discriminator property](https://github.com/linq2db/linq2db/discussions/5477) (open).

## Resolved themes

- **Include/navigation loading** -- Multiple closed issues (#61, #1149, #2172) demonstrate resolved patterns for navigation property loading and query filters. #4603 (ThenInclude inside a recursive CTE) closed 2026-06-14.

- **Soft delete and query filters** -- Closed issues (#1626) show integration patterns with EF Core's query filters and soft-delete patterns.

- **Query filter edge cases** -- Closed issues #5267 (EF.Property comparison in a tenant filter), #5417 (Truncate on DbSet with a global query filter), #5792 (query filter drops a left-join null check in a set operation operand, closed area GLOBAL). Named multiple query filters mirroring the EF Core 10 API were added in closed PR #5525 (merged 2026-07-02).

- **Complex type mapping** -- Several resolved tickets (#1463, #2082) document support for complex/owned types with field-level mapping.

- **OData interoperability** -- Closed issues (#371) show fixes for OData-over-linq2db query patterns and LINQ expression translation.

- **Concurrency and versioning** -- Issue #553 resolved with optimistic concurrency support patterns documented.

- **Many-to-many navigation translation** -- EF Core skip navigations backed by a hidden join entity failed with "could not be converted to SQL" (#5585, closed). Fixed by PR #5588 (merged 2026-06-09).

- **EF Core value converters** -- Converter handling in parameters, set operations and server-side writes. Closed: #5177 (nullable struct converters), #5388 (ValueConverter ignored for constant values), #5427 (BulkCopy writing Guid.Empty instead of NULL). Regressions #5975 (DML with EF Core DateTime converters) and #5976 (Concat/Union NotEqual operator error), both closed 2026-10-09, are fixed by PR #5978 (merged 2026-10-09). Regression #6181 (DateTime ValueConverters with CLR logic failing under window functions or grouping) closed 2026-11-10; no linked fix PR is recorded in the index.

- **Window function regressions** -- Regression #6182 ("Window functions cannot be used in search condition" with a window function and a left join) closed 2026-10-30; no linked fix PR is recorded in the index.

- **Runtime and package compatibility** -- MissingMethodException and transaction-state errors after framework or EF Core package changes. Closed: #5184 (.NET 10), #5224 (CreateTempTableAsync), #5225 (CreateLinqToDBConnection with an active transaction and no dialect). EF Core 10 F# test coverage with EntityFrameworkCore.FSharp 10.0.0 added in merged PR #6191 (merged 2026-10-28).

- **Multi-provider MappingSchema** -- Closed #5778: wrong MappingSchema when one DbContext type is used with different providers in the same process. No linked fix PR is recorded in the index.

- **Provider-specific EF options documentation** -- Closed docs issue #5830 and closed PR #5832 covering how to configure provider-specific options in the EF Core integration.

- **Connection leak in ToLinqToDB** -- Closed #5364 (ToLinqToDB helper leaked the connection). Area tag in the index is DATA.

## Active discussions

- [AsNoTracking in Linq2db](https://github.com/linq2db/linq2db/discussions/3116) -- [Q&A] Tracking and change-detection patterns with linq2db. (closed)
- [EF Core 6 VS linq2db benchmarks](https://github.com/linq2db/linq2db/discussions/3393) -- [General] Performance comparison analysis. (closed)
- [Dynamically generating nested queries](https://github.com/linq2db/linq2db/discussions/3490) -- [Q&A] Dynamic query composition patterns. (closed)
- [Usage of IDbContextFactory](https://github.com/linq2db/linq2db/discussions/3928) -- [Q&A] Context lifecycle and dependency injection. (closed)
- [Add values from a dictionary when doing CRUD operations](https://github.com/linq2db/linq2db/discussions/4148) -- [Ideas] Bulk operations from dynamic sources. (closed)
- [[Docs] Comparison with Entity Framework](https://github.com/linq2db/linq2db/discussions/4288) -- [General] Feature comparison and gap documentation. (open)
- [How to set DateTimeKind per property?](https://github.com/linq2db/linq2db/discussions/4238) -- [Q&A] Type-specific property configuration. (closed)
- [How to use TIME ZONE AT?](https://github.com/linq2db/linq2db/discussions/4688) -- [Q&A] Temporal type handling in mapping schema. (closed)
- [Is there a way to provide a custom SQL query for an entity?](https://github.com/linq2db/linq2db/discussions/4692) -- [Q&A] ToSqlQuery equivalent for static entity projections. (closed)
- [Configure Linq2DB.EntityFrameworkCore to respect shadow Discriminator property](https://github.com/linq2db/linq2db/discussions/5477) -- [Q&A] Shadow properties in inheritance hierarchies. (open)

## Stats

- Open issues: 10
- Closed issues: 66
- Open PRs: 0
- Total PRs: 35
- Discussions: 10 (2 open)
- Last fetched: 2026-11-11 (index horizon)

<details><summary>Coverage</summary>

- Index entries scanned: 121 (76 issues + 35 PRs + 10 discussions), EFCORE-tagged, plus a keyword sweep of issue and PR titles and summaries
- Themes extracted: 22 (9 open + 13 resolved)
</details>
