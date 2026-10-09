---
area: EFCORE
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: high
last_verified: 2026-10-10
last_verified_sha: 05150894edc2511f0dd0bc7829b2a309cec36ec9
---

# EFCORE -- GitHub themes

## Open themes

- **Query logging and diagnostics** -- Gaps in visualizing generated SQL and excluding sensitive data from logs within EF Core integration contexts. Open: #4645 (query logging visibility, updated 2026-06-14), #4651 (sensitive data exclusion in logs). Documentation and tooling improvements are still needed for debugging linq2db queries via EF Core.

- **Include and navigation loading** -- Challenges with eager loading of related entities and collections in entity hierarchies, especially with inheritance patterns. Open: #4012 (eager include of collections into CTE results), #4628 (inherited navigation population, updated 2026-06-15). Closed precedent #4603 (ThenInclude inside a recursive CTE, closed 2026-06-14). Recurring pattern in complex entity graphs.

- **Mapping incompatibilities with inheritance** -- EF Core TPH (Table Per Hierarchy) discriminator handling and inherited property materialization not translating correctly. Open: #4644 (inherited properties unnecessarily in SQL), #4666 (Merge into TPH table with discriminator), #4628 (inherited navigation interaction). Entity construction and calculated column expansion were addressed in closed PR #5578.

- **EF Core integration lifecycle gaps** -- Transaction and state management issues when bridging EF Core contexts to linq2db queries. Open: #4653 (transaction assignment on pre-created queryables), #4649 (Set() method tracking semantics, updated 2026-07-11). Connection leak in the ToLinqToDB helper (#5364) is closed and listed under Resolved themes.

- **Provider support and documentation** -- Limited provider support documentation and configuration gaps for EF Core integration. Open: #4611 (review of supported providers list and testing matrix, updated 2026-06-15).

## Resolved themes

- **Include/navigation loading** -- Multiple closed issues (#61, #1149, #2172) demonstrate resolved patterns for navigation property loading and query filters. #4603 (ThenInclude inside a recursive CTE) closed 2026-06-14.

- **Soft delete and query filters** -- Closed issues (#1626) show integration patterns with EF Core's query filters and soft-delete patterns.

- **Query filter edge cases** -- Closed issues #5267 (EF.Property comparison in a tenant filter), #5417 (Truncate on DbSet with a global query filter). Named multiple query filters mirroring the EF Core 10 API were added in closed PR #5525.

- **Complex type mapping** -- Several resolved tickets (#1463, #2082) document support for complex/owned types with field-level mapping.

- **OData interoperability** -- Closed issues (#371) show fixes for OData-over-linq2db query patterns and LINQ expression translation.

- **Concurrency and versioning** -- Issue #553 resolved with optimistic concurrency support patterns documented.

- **Many-to-many navigation translation** -- EF Core skip navigations backed by a hidden join entity failed with "could not be converted to SQL" (#5585, closed). Fixed by PR #5588 (merged 2026-06-09).

- **EF Core value converters** -- Converter handling in parameters, set operations and server-side writes. Closed: #5177 (nullable struct converters), #5388 (ValueConverter ignored for constant values), #5427 (BulkCopy writing Guid.Empty instead of NULL). Regressions #5975 and #5976 (closed 2026-10-09) are addressed by PR #5978, now on master.

- **Runtime and package compatibility** -- MissingMethodException and transaction-state errors after framework or EF Core package changes. Closed: #5184 (.NET 10), #5224 (CreateTempTableAsync), #5225 (CreateLinqToDBConnection with an active transaction and no dialect).

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

- Open issues: 9
- Closed issues: 64
- Open PRs: 0
- Total PRs: 34
- Discussions: 10 (2 open)
- Last fetched: 2026-10-09 (index horizon)

<details><summary>Coverage</summary>

- Index entries scanned: 117 (73 issues + 34 PRs + 10 discussions)
- Themes extracted: 17 (5 open + 12 resolved)
</details>
