---
area: PROV-SQLSERVER
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: high
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
---

# PROV-SQLSERVER -- GitHub themes

## Open themes

- **Scaffolding and schema generation gaps** -- Five open requests: table-valued functions and UDFs not discovered (#449), Azure SQL Edge CLR feature gap blocking schema import (#4195), database-name parameter not applied to generated mappings (#4606), reserved-word-named views causing code-generation errors (#4831), and a request to use DeriveParameters for stored-procedure parameters instead of GetSchema (#3621). Core gap: the T4 and CLI schema provider needs TVF discovery, conditional CLR gating for Azure SQL Edge, and identifier sanitization in generated code.

- **Stored procedure and table-function result mapping** -- #1862 asks for one-to-many mapping of stored procedure results onto objects (eager-load). #1857 asks for calling SQL Server functions, not only stored procedures. It shares the metadata gap with #449 (TVF discovery) and #3621 (procedure parameter discovery): procedure and function shapes are not fully read from the server.

- **EFCore integration gaps** -- Open issues #3174 (EFCore shadow properties not carried to temp tables), #4640 (JSON columns null in MERGE operations), #4656 (JOINs inside temporal queries unsupported), #4665 (NetTopologySuite spatial-type integration), and #4663 (BulkCopy with complex properties, see BulkCopy below). All involve EFCore-to-linq2db mapping translation or provider-feature exposure.

- **BulkCopy limitations** -- #1178 requests API enhancements for BulkCopy performance tuning. #2777 compares BulkCopyAsync with multi-row INSERT tuning on SQL Server. #4663 reports a BulkCopy failure with EFCore complex types because structured type mapping is not propagated to bulk-copy column inference.

- **Temporary table type safety** -- #3174 (shadow property omission), #4659 (TempTable<string> not recognized as a string type by the In predicate, i.e. incorrect type inference for primitive-typed temp tables), and #4598 (SQL Server temp table collation error). Related open discussion #4953 asks how to ignore duplicate keys on a temp table (IGNORE_DUP_KEY).

- **SQL function-translation optimization** -- #1916 requests native CONCAT() mapping (available since SQL Server 2012) instead of the + operator for Sql.Concat. #3314 (labelled has-pr) implements an ISNULL optimization for SQL Server.

- **Recursive CTE type stability** -- #2451 reports type-mismatch errors when recursive CTE branches emit different precisions (NVARCHAR(50) vs NVARCHAR(MAX)). The related silent column drop (#5457) was fixed by #5680 and is listed under Resolved.

- **Type handling (string length, conversions)** -- #4177 (open PR, fixes #4138) maps string.Length for SQL CE and MSSQL. #4138 (GLOBAL-tagged) reports string.IsNullOrEmpty semantics for space-only strings. #5810 (open) reports that SqlFn.Convert emits another call's target type when call shapes match. #6078 (open, updated 2026-10-19) is a date-literal case: a DateTime literal compared with a value computed from a datetime column (MAX, COALESCE) is written as DATETIME2FROMPARTS, so a row stored and read back through that column misses the match, while the column itself is written as DATETIMEFROMPARTS and matches. #4306 (labelled has-pr) concerns the SQL Server type chosen for TimeSpan, which maps to time.

- **VarChar and Unicode string functions cut at 4000 characters** -- Six open items (updated 2026-10-30 to 2026-11-07) share one symptom: an nvarchar result or operand is capped at 4000 characters, or a non-Unicode VarChar operand is implicitly converted to nvarchar(4000) and truncated. #6212 concatenates a string column with a string parameter and returns at most 4000 characters. #6227 translates string.Length through LEN(x + '.') - 1, so a VarChar(8000) value longer than 4000 characters returns 3999. #6236 (Replace with a Unicode argument), #6238 (PadRight / Sql.PadLeft via REPLICATE over N'c') and #6261 (string.Remove via STUFF with N'') repeat the cut. #6247 compares a value with Sql.Convert(NVarChar) over a converted VarChar column and loses non-Latin characters. Resolved siblings #6186 and #6194 cover the encoding loss; their summaries do not mention the 4000-character cut.

- **Correlated sub-query GROUP BY** -- #6234 (tagged here, labelled mssql and firebird): a correlated sub-query whose GROUP BY key includes an outer-row member keeps that outer column in the sub-query GROUP BY. The index summary says SQL Server, SQL CE and Firebird 3+ reject the resulting SQL. Single item, listed because it is tagged to this area.

- **Spatial types** -- #4665 (NetTopologySuite integration) and #6172 (LINQPad driver on non-Windows hosts provisions dotMorten.Microsoft.SqlServer.Types 2.5.0 next to Microsoft.Data.SqlClient 7.0.2; per the index summary the two do not work together). Two items, below the three-item threshold; listed because both are open and tagged to this area.

## Resolved themes

- **Fabric Datawarehouse scaffolding** -- #4536 resolved (closed 2026-06-14): ASSEMBLYPROPERTY exclusion in schema enumeration unblocks the Microsoft Fabric datawarehouse scaffold.

- **Recursive CTE column drop** -- #5680 (PR, merged 2026-07-07) fixes #5457: a recursive CTE whose projection type has an object-typed member collapsed its header to one column.

- **Decimal overflow** -- #5605 (PR, merged 2026-07-11) adds an opt-in [GetSqlDecimal] attribute for high-precision SQL Server decimal values via SqlDecimal.

- **Query simplification regressions** -- #5529 (closed 2026-06-01): SqlServer no longer simplifies LEN(...) - 1 <> 0 and (col + literal) IS NULL in WhereTests. #5777 (closed 2026-10-09): SQL Server before 2016 elapsed-time reach through the shared decomposition; no closing PR recorded in the index.

- **Procedure return value scaffolding** -- #6026 (PR, merged 2026-10-12, refs #4718) maps the SQL Server procedure return value as ReturnValue instead of Output when --mssql-enable-return-value-parameter is set. The Output mapping had made every generated procedure wrapper fail with "too many arguments" (pre-existing since #3098).

- **Windows test-leg image pulls** -- #6011 (PR, merged 2026-10-10) restores the Docker Hub login before setup on the Azure Windows SQL Server legs, after anonymous win-mssql-* pulls hit the Docker Hub rate limit (build 23999).

- **Test infrastructure** -- #5730 (closed 2026-10-26): replace the legacy dotMorten SQL Server types test dependency; no closing PR recorded in the index. #5887 (closed 2026-10-24): ParameterReuse cost test flaky on netfx legs and missing [QueryCacheTest]; no closing PR recorded in the index.

- **Case-sensitive catalog testing** -- #4658 (closed 2026-10-27) adds case-sensitive schema testing for SQL Server. PR #6161 (merged 2026-10-27) tests the SQL Server case-sensitive catalog and merges the custom SQL Server test modes onto 2025.

- **Unicode arguments beside VarChar columns** -- #6186 (PR, merged 2026-11-04) keeps a parameter concatenated with a VarChar column Unicode, so non-Latin text no longer comes back as ?. #6194 (PR, merged 2026-11-10) does the same for parameters and literals passed to string functions over a VarChar or Char column.

## Active discussions
- [SQL Server: Create a temp table with IGNORE_DUP_KEY = ON](https://github.com/linq2db/linq2db/discussions/4953) -- [Q-and-A] asks whether a temp table can silently ignore duplicate-key rows instead of raising a PK violation.

## Stats
- Open issues: 25
- Closed issues: 182
- Open PRs: 1
- Total PRs: 98
- Discussions: 17 (1 open)
- Last fetched: 2026-11-11

<details><summary>Coverage</summary>

- Index entries scanned: 322 (207 issues + 98 PRs + 17 discussions)
- Themes extracted: 11 open + 9 resolved

</details>
