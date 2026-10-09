---
area: PROV-SQLSERVER
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: high
last_verified: 2026-10-10
last_verified_sha: 05150894edc2511f0dd0bc7829b2a309cec36ec9
---

# PROV-SQLSERVER -- GitHub themes

## Open themes

- **Scaffolding and schema generation gaps** -- Five open requests: table-valued functions and UDFs not discovered (#449), Azure SQL Edge CLR feature gap blocking schema import (#4195), database-name parameter not applied to generated mappings (#4606), reserved-word-named views causing code-generation errors (#4831), and a request to use DeriveParameters for stored-procedure parameters instead of GetSchema (#3621, open). Core gap: the T4 and CLI schema provider needs TVF discovery, conditional CLR gating for Azure SQL Edge, and identifier sanitization in generated code.

- **Stored procedure and table-function result mapping** -- #1862 asks for one-to-many mapping of stored procedure results onto objects (eager-load). It shares the metadata gap with #449 (TVF discovery) and #3621 (procedure parameter discovery): procedure and function shapes are not fully read from the server.

- **EFCore integration gaps** -- Open issues #3174 (EFCore shadow properties not carried to temp tables), #4640 (JSON columns null in MERGE operations), #4656 (JOINs inside temporal queries unsupported), #4665 (NetTopologySuite spatial-type integration), and #4663 (BulkCopy with complex properties, see BulkCopy below). All involve EFCore-to-linq2db mapping translation or provider-feature exposure.

- **BulkCopy limitations** -- #1178 requests API enhancements for BulkCopy performance tuning. #4663 reports a BulkCopy failure with EFCore complex types because structured type mapping is not propagated to bulk-copy column inference.

- **Temporary table type safety** -- #3174 (shadow property omission) and #4659 (TempTable<string> not recognized as a string type by the In predicate, i.e. incorrect type inference for primitive-typed temp tables). Related open discussion #4953 asks how to ignore duplicate keys on a temp table (IGNORE_DUP_KEY).

- **SQL string optimization** -- #1916 requests native CONCAT() mapping (available since SQL Server 2012) instead of the + operator for Sql.Concat.

- **Recursive CTE type stability** -- #2451 reports type-mismatch errors when recursive CTE branches emit different precisions (NVARCHAR(50) vs NVARCHAR(MAX)). The related silent column drop (#5457) was fixed by #5680 and is listed under Resolved.

- **Type handling (string length, conversions)** -- #4177 (open PR, fixes #4138) maps string.Length for SQL CE and MSSQL. #5810 (open) reports that SqlFn.Convert emits another call's target type when call shapes match.

- **Test infrastructure** -- #5730 asks to replace the legacy dotMorten SQL Server types test dependency. #5887 reports the ParameterReuse cost test as flaky on netfx legs and missing [QueryCacheTest]. Only two items, below the three-item threshold; listed because both are open and tagged to this area.

## Resolved themes

- **Fabric Datawarehouse scaffolding** -- #4536 resolved (closed 2026-06-14): ASSEMBLYPROPERTY exclusion in schema enumeration unblocks the Microsoft Fabric datawarehouse scaffold.

- **Recursive CTE column drop** -- #5680 (PR, merged 2026-07-07) fixes #5457: a recursive CTE whose projection type has an object-typed member collapsed its header to one column.

- **Decimal overflow** -- #5605 (PR, merged 2026-07-11) adds an opt-in [GetSqlDecimal] attribute for high-precision SQL Server decimal values via SqlDecimal.

- **Query simplification regressions** -- #5529 (closed 2026-06-01): SqlServer no longer simplifies LEN(...) - 1 <> 0 and (col + literal) IS NULL in WhereTests. #5777 (closed 2026-10-09): SQL Server before 2016 elapsed-time reach through the shared decomposition; no closing PR recorded in the index.

## Active discussions
- [SQL Server: Create a temp table with IGNORE_DUP_KEY = ON](https://github.com/linq2db/linq2db/discussions/4953) -- [Q-and-A] asks whether a temp table can silently ignore duplicate-key rows instead of raising a PK violation.

## Stats
- Open issues: 18
- Closed issues: 179
- Open PRs: 1
- Total PRs: 97
- Discussions: 17 (1 open)
- Last fetched: 2026-10-09

<details><summary>Coverage</summary>

- Index entries scanned: 311 (197 issues + 97 PRs + 17 discussions)
- Themes extracted: 9 open + 4 resolved

</details>
