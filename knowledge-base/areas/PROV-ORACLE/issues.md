---
area: PROV-ORACLE
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: high
last_verified: 2026-10-10
last_verified_sha: 05150894edc2511f0dd0bc7829b2a309cec36ec9
---

# PROV-ORACLE -- GitHub themes

## Open themes

- **Bulk copy and LOB size** -- Oracle bulk copy keeps coming back to large values and missing batching. Open: #1880 (default OracleBulkCopy implementation), #2365 (CLOB failure), #2892 (array binding for CommandInfo/BulkCopy), #2960 (BulkCopy returning inserted IDs; now tagged GLOBAL in the index, still open, kept here). Related: #1918 (stream into Oracle BLOB). Discussion #5009 reports NCLOB values over 32767 chars failing in BulkCopy.
- **Stored procedure and collection parameters** -- Passing collections or PL/SQL-side values as parameters is still unsupported. Open: #1605 (array parameters in stored procedures, needs tests), #1645 (table value parameters for stored procedures), #3740 (PL/SQL function returning boolean with input parameters; PR linked).
- **Dialects, version targeting and identity DDL** -- Dialect selection per Oracle version and native identity DDL. Open: #1879 (Oracle 12+ dialect), #5425 (Oracle23SqlBuilder with updated flags), #1010 (GUID as identity column). Open PRs: #4683 (more Oracle dialects), #5773 (native Oracle 12 identity DDL).
- **Functions, analytic and CTE support** -- Oracle-specific function and window/CTE gaps. Open: #1882 (Translate function), #2863 (analytic functions in GROUP BY queries), #3015 (UPDATE CTE support across providers, Oracle included), #4224 (LISTAGG / StringAggregate extension).
- **Boolean and date/time translation** -- Oracle has no boolean column type and its date arithmetic differs from other providers. Open: PR #3754 (add Oracle boolean type support), #5797 (DateTimeOffset difference measured on the local reading instead of the instant; Oracle and SQLite Classic).
- **Row locking, temp tables and large-list filtering** -- Query hints and temp-table strategy for Oracle. Open: #5706 (FOR UPDATE row-locking hint API; PR #5811 closed with a reference to it), #5601 (prefer private temporary tables over global temporary tables for large-list filters). Discussion #5702 asks about FOR UPDATE.
- **Regressions and CI** -- Upgrade regressions and Oracle CI parity. Open: #5360 (Oracle errors since upgrade to V6.2 from 5.x, needs tests), #5888 (pin NUnit parallelism so GitHub Actions Oracle legs match Azure).

## Resolved themes

- **Analytic and boolean ORDER BY translation** -- Bad boolean translation in OVER (ORDER BY) was closed on 2026-09-09 as #2842. No closing PR was located in the index. Earlier boolean ORDER BY fix for databases without a boolean type: PR #2891.
- **Bulk copy SQL length limit** -- Issue #5825 requested a higher limit. PR #5827 and PR #5828 (closed 2026-09-09) raised it to 384KB and made it configurable.
- **Date differences** -- PR #5987 (closed 2026-10-09) fixes date differences regressed in 6.5.0 and translates date shifts on Oracle, SQLite, Firebird and YDB.
- **Correlated UPDATE and COALESCE** -- Issue #5413 was fixed through PRs #5500, #5507 and #5584 (correlated row-setter UPDATE and column-position scalar subqueries). COALESCE to NVL (PR #5443) was reverted by PR #5490.
- **Parameter creation** -- PR #5600 (closed 2026-08-03) moved parameter creation into the providers.
- **ODP.NET statement cache and CI legs** -- PR #5950 (closed 2026-09-21) disabled the ODP.NET statement cache and moved the Oracle legs to GitHub Actions.
- **Identity schema reading** -- PRs #2046 and #2124 added Oracle identity column support to the schema reader.
- **Pagination and APPLY on 12c+** -- PRs #2065 and #2087 added cross/outer apply and skip/take for Oracle 12c.

## Active discussions

- [config.json "include-tables" regex not working as expected](https://github.com/linq2db/linq2db/discussions/4505) -- [Q&A] Regex for include-tables in a config file does not match as expected.
- [Have you guys seen JOOQ?](https://github.com/linq2db/linq2db/discussions/4942) -- [Ideas] Question about the JOOQ project.
- [Oracle Data Type NCLOB - BulkCopy - more than 32767 chars](https://github.com/linq2db/linq2db/discussions/5009) -- [Q&A] NCLOB values over 32767 chars fail in BulkCopy.
- [Truncate(true) fails on Oracle with GENERATED ALWAYS](https://github.com/linq2db/linq2db/discussions/5207) -- [Q&A] Truncate fails for tables with GENERATED ALWAYS columns.
- [FOR UPDATE in Oracle](https://github.com/linq2db/linq2db/discussions/5702) -- [Q&A] How to request FOR UPDATE row locking on Oracle.

## Stats

- Open issues: 19
- Closed issues: 141
- Open PRs: 3
- Total PRs: 109
- Discussions: 9
- Last fetched: 2026-10-10 (index high-water mark 2026-10-09)

<details><summary>Coverage</summary>

- Index entries scanned: 278 (160 issues + 109 PRs + 9 discussions)
- Themes extracted: 15
</details>
