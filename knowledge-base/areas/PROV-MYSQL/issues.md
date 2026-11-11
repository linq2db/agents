---
area: PROV-MYSQL
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: high
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
---

# PROV-MYSQL -- GitHub themes

## Open themes

- **Type Mapping and Schema Handling** -- Issues with mapping MySQL types (enum -> varchar in CreateTable, bit(1) -> bool, UUID support on MariaDB) and schema generation. Recurs across MySQL versions and mapping libraries. CAST to a date/time type ignores Precision, so fractional seconds are dropped in set operations (#6049, open). (#3223, #3554, #86, #4354, #6049)
- **Bulk Operations Gap** -- Bulk INSERT works, but bulk UPDATE is unsupported (#1259). BulkCopy still ignores custom GuidFormat in binary modes (#4354). Provider-specific BulkCopy landed via #2113; BulkCopy timeout handling was fixed in PR #5039.
- **UPSERT / ON DUPLICATE KEY UPDATE** -- MySQL lacks MERGE; bulk upsert must route through INSERT ... ON DUPLICATE KEY UPDATE. Explicit multi-row API support is still requested (#5278). The cross-provider INSERT and UPSERT umbrella (#2558, open) names the same route.
- **MariaDB vs MySQL Dialect Split** -- One MariaDB dialect (`MySqlVersion.MariaDB10`, "MariaDB 10+") covers all MariaDB releases. MariaDB 13 adds `RETURNING` to `UPDATE`, which needs its own dialect (#5933, open). Related: provider detection (#4124, closed), MariaDB 10.11 KeyNotFoundException (#4207, closed), UUID support (#3554).
- **Connection / Initialization** -- Retry logic, T4 model generation and pooling show stress points. RetryingDataConnection rejects re-open (#3431); T4 scaffold timeouts on large schemas (#3313). MySqlConnector pooling and close-before-dispose behaviour was raised in discussion #5329 (open).
- **Critical Error: Unresolved Exception** -- #4669 (critical, open) hits UnreachableException in the EF Core MySQL translation path; may indicate cross-provider integration fragility.
- **netstandard2.0 build on modern runtimes** -- The netstandard2.0 asset misses MySQL conversions that are registered only under net8+ `#if` blocks. #6085 (open): a MySQL VECTOR column cannot be read into `float[]` with MySqlConnector, because the `ReadOnlyMemory<float>` to `float[]` conversion is compiled only for net8+. Same class as reader gaps in other providers still open: DuckDB TIMETZ (#6084) and ClickHouse parameterised insert (#6086). (#6085, #6084, #6086)

## Resolved themes

- **UPSERT via Merge API** -- The Merge-API UPSERT route for databases without MERGE (#1480) closed 2026-06-14.
- **netstandard2.0 reader gap, PostgreSQL sibling** -- Npgsql 10 date, time and daterange values were not readable on the netstandard2.0 asset (PROV-POSTGRES #6077, closed 2026-11-10). Same class as #6085 (open, this area).
- **mysql** -- 38 closed issues share this keyword. Sample: #45, #121, #168, #218, #350, #220, #558, #443.
- **update** -- 8 closed issues share this keyword. Sample: #443, #2573, #2556, #3284, #997, #3905, #4164, #3726.
- **connection** -- 8 closed issues share this keyword. Sample: #1686, #1772, #2567, #3390, #1991, #4457, #4929.
- **Transactions** -- BeginTransaction/Rollback failures (#121, #3513, #1991) and DDL breaking rollback (#4439, fixed by PR #4879). Tracing gap raised in discussion #3073. LoadWith opening a transaction for read-only queries was raised in discussion #5118 (closed 2026-05-23, no linked fix in index).
- **Provider lineage: MySql.Data to MySqlConnector** -- MySqlConnector provider added (PR #1470); MySql.Data support dropped (announcement #3145, PR #3238); MySqlConnector 1.0 namespace update (PR #2270).
- **Test infrastructure** -- MySQL `CreateDatabase` now runs `CREATE DATABASE IF NOT EXISTS` before the drop-and-create script, so an interrupted run no longer leaves every later run failing with `1049 Unknown database` (#6054, merged 2026-10-15; index tags it outside this area). Earlier schema-mutation fix in #5655.

## Active discussions

- [How can we trace BeginTransaction(), RollbackTransaction() and CommitTransaction()?](https://github.com/linq2db/linq2db/discussions/3073) -- [Q&A] Tracing infrastructure doesn't log transaction boundaries; verbose trace shows only queries. (closed)
- [NET 6 with MySql connection](https://github.com/linq2db/linq2db/discussions/3422) -- [Q&A] MySql.Data v8.0.25 raises KeyNotFoundException on column lookup during scaffold. (closed)
- [How can I let linq2db work with MAUI](https://github.com/linq2db/linq2db/discussions/3828) -- [Q&A] MAUI/Xamarin UWP compatibility with MySQL provider. (closed)
- [How to connect with MariaDB](https://github.com/linq2db/linq2db/discussions/4123) -- [Q&A] Provider selection between MySQL and MariaDB; no explicit MariaDB dialect enum in public API. (closed)
- [linq2db CLI, Json scaffolding ignore table back references on indexes?](https://github.com/linq2db/linq2db/discussions/4432) -- [Q&A] Scaffold config for suppressing back-reference properties on indexed columns. (open)
- [Why does using a method similar to LoadWith start a transaction when it's only a query?](https://github.com/linq2db/linq2db/discussions/5118) -- [General] LoadWith on MySQL auto-opens transaction even for read-only query; unexpected behavior. (closed 2026-05-23)
- [Is PublishSingleFile supported for linq2db?](https://github.com/linq2db/linq2db/discussions/5488) -- [Q&A] PublishSingleFile assembly loading fails for dynamically-loaded providers like MySql.Data. (closed 2026-06-22)
- [Linq2Db MySqlConnector with pooling. Closing the connection before disposing.](https://github.com/linq2db/linq2db/discussions/5329) -- [General] MySqlConnector pooling and connection close ordering. (open, index tags it GLOBAL)

## Stats

- Open issues: 12 (all index-tagged PROV-MYSQL)
- Closed issues: 60 (index-tagged PROV-MYSQL)
- Open PRs: 0
- Total PRs: 47 (index-tagged; #6054 is cited above and tagged PROV-MYSQL)
- Discussions: 8 (7 index-tagged, plus #5329 tagged GLOBAL)
- Last fetched: 2026-11-11

<details><summary>Coverage</summary>

- Index entries scanned: 127 (72 issues + 47 PRs + 8 discussions)
- Delta items reviewed: #6049, #6085, #5933 (issues, open); #6084, #6086 (other areas, open, cited as siblings); #6077 (PROV-POSTGRES, closed, moved to resolved); #1480 (closed, moved to resolved); #6054 (PR, merged); #2558, #5329 (new citations); #6167 (dropped, see audit)
- Themes extracted: 7 open + 7 resolved

</details>
