---
area: PROV-MYSQL
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: high
last_verified: 2026-10-10
last_verified_sha: 05150894edc2511f0dd0bc7829b2a309cec36ec9
---

# PROV-MYSQL -- GitHub themes

## Open themes

- **Type Mapping and Schema Handling** -- Issues with mapping MySQL types (enum -> varchar in CreateTable, bit(1) -> bool, UUID support on MariaDB) and schema generation. Recurs across MySQL versions and mapping libraries. (#3223, #3554, #86, #4354)
- **Bulk Operations Gap** -- Bulk INSERT works, but bulk UPDATE is unsupported (#1259). BulkCopy still ignores custom GuidFormat in binary modes (#4354). Provider-specific BulkCopy landed via #2113; BulkCopy timeout handling was fixed in PR #5039.
- **UPSERT / ON DUPLICATE KEY UPDATE** -- MySQL lacks MERGE; bulk upsert must route through INSERT ... ON DUPLICATE KEY UPDATE. Explicit multi-row API support is still requested (#5278). The Merge-API UPSERT route (#1480) closed 2026-07-03.
- **MariaDB vs MySQL Dialect Split** -- One MariaDB dialect (`MySqlVersion.MariaDB10`, "MariaDB 10+") covers all MariaDB releases. MariaDB 13 adds `RETURNING` to `UPDATE`, which needs its own dialect (#5933, open). Related: provider detection (#4124, closed), MariaDB 10.11 KeyNotFoundException (#4207, closed), UUID support (#3554).
- **Connection / Initialization** -- Retry logic and T4 model generation show stress points. RetryingDataConnection rejects re-open (#3431); T4 scaffold timeouts on large schemas (#3313).
- **Critical Error: Unresolved Exception** -- #4669 (critical, open) hits UnreachableException in the EF Core MySQL translation path; may indicate cross-provider integration fragility.

## Resolved themes

- **mysql** -- 38 closed issues share this keyword. Sample: #45, #121, #168, #218, #350, #220, #558, #443.
- **update** -- 8 closed issues share this keyword. Sample: #443, #2573, #2556, #3284, #997, #3905, #4164, #3726.
- **connection** -- 8 closed issues share this keyword. Sample: #1686, #1772, #2567, #3390, #1991, #4457, #4929.
- **Transactions** -- BeginTransaction/Rollback failures (#121, #3513, #1991) and DDL breaking rollback (#4439, fixed by PR #4879). Tracing gap raised in discussion #3073. LoadWith opening a transaction for read-only queries was raised in discussion #5118 (closed 2026-05-23, no linked fix in index).
- **Provider lineage: MySql.Data to MySqlConnector** -- MySqlConnector provider added (PR #1470); MySql.Data support dropped (announcement #3145, PR #3238); MySqlConnector 1.0 namespace update (PR #2270).

## Active discussions

- [How can we trace BeginTransaction(), RollbackTransaction() and CommitTransaction()?](https://github.com/linq2db/linq2db/discussions/3073) -- [Q&A] Tracing infrastructure doesn't log transaction boundaries; verbose trace shows only queries. (closed)
- [NET 6 with MySql connection](https://github.com/linq2db/linq2db/discussions/3422) -- [Q&A] MySql.Data v8.0.25 raises KeyNotFoundException on column lookup during scaffold. (closed)
- [How can I let linq2db work with MAUI](https://github.com/linq2db/linq2db/discussions/3828) -- [Q&A] MAUI/Xamarin UWP compatibility with MySQL provider. (closed)
- [How to connect with MariaDB](https://github.com/linq2db/linq2db/discussions/4123) -- [Q&A] Provider selection between MySQL and MariaDB; no explicit MariaDB dialect enum in public API. (closed)
- [linq2db CLI, Json scaffolding ignore table back references on indexes?](https://github.com/linq2db/linq2db/discussions/4432) -- [Q&A] Scaffold config for suppressing back-reference properties on indexed columns. (open)
- [Why does using a method similar to LoadWith start a transaction when it's only a query?](https://github.com/linq2db/linq2db/discussions/5118) -- [General] LoadWith on MySQL auto-opens transaction even for read-only query; unexpected behavior. (closed 2026-05-23)
- [Is PublishSingleFile supported for linq2db?](https://github.com/linq2db/linq2db/discussions/5488) -- [Q&A] PublishSingleFile assembly loading fails for dynamically-loaded providers like MySql.Data. (closed 2026-06-22)

## Stats

- Open issues: 10
- Closed issues: 60
- Open PRs: 0
- Total PRs: 46
- Discussions: 7
- Last fetched: 2026-10-09

<details><summary>Coverage</summary>

- Index entries scanned: 123 (70 issues + 46 PRs + 7 discussions)
- Themes extracted: 6 open + 5 resolved

</details>
