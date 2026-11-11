---
area: PROV-SYBASE
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: high
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
---

# PROV-SYBASE -- GitHub themes

## Open themes

- **Eager-loading and query validation on Sybase** -- The element-form eager-loading preamble bypasses query validation and silently drops detail rows (#5865, still open as of 2026-11-11). The fix for silently truncated eager-loaded collections is PR #5900 (fixes #5865, head branch issue/5865-validate-limited-derived-join), still open as of 2026-11-11.
- **Limited subqueries and MERGE row counts** -- ASE applies a TOP inside a derived table to the outer result, so Take() in a subquery silently limits the whole query (#5895). MERGE over a cross-joined source inserts fewer rows than the source has (#5896). Both are open and both were measured on Sybase.Managed (AdoNetCore.AseClient) on net10.0. A correlated derived table under an aggregate reaches ASE instead of being refused (#6166), the same derived-table family.
- **Date and time type coercion** -- A UNION of a `date` column with a `datetime` value returns the datetime branch truncated to midnight, with no error, because ASE types the UNION column as `date` (#6050). `new DateTime(...)` and `Sql.MakeDateTime` over NULL parts raise a VARCHAR conversion error instead of answering NULL (#6088). Both are open and were measured on Sybase.Managed. Related resolved history: DateTime and type conversions below.
- **Provider selection in SybaseTools** -- `SybaseTools.GetDataProvider` ignores the requested `SybaseProvider`, so the caller's choice is not honoured (#6177, updated 2026-11-10). Single report so far.
- **Unsigned literal limits (cross-provider)** -- A `ulong.MaxValue` literal fails on Sybase, among SQLite, SQL Server and Firebird (#5973, tagged MAPPING). Sybase is one of several providers named in the issue, so it is cited here rather than in a Sybase-only theme.
- **Other Sybase-family products** -- Two open requests for products outside ASE: Sybase IQ (#2040) and SAP Anywhere Database (#3398). Both are tagged GLOBAL. Two reports so far, so this is not yet a recurring theme.

## Resolved themes

- **String concatenation and ANSI || emission** -- Sybase ASE string concatenation moved from the Transact-SQL `+` operator to ANSI `||` (#5523, PR #5569, merged 2026-06-07). Bogus IS NULL guards on non-null and literal concat operands were removed (#5530, PR #5566, merged 2026-06-04). Both PRs are tagged EFCORE and PROV-DB2 in the index, not PROV-SYBASE.
- **Parameter length, Unicode and type handling** -- Parameter length limit fixed via PR #3908. Unicode parameter length issue (#3916) with a Unicode test added in PR #1300. Float column read as double by DataReader (#3183). Sybase time/datetime and type handling fixed in PR #1792.
- **DateTime and type conversions** -- Multiple closed issues around DateTime handling, type mismatches, and column reading. Sample resolved: #1707 (1900 conversion), #2026 (template timeout), #2038 (ObjectDisposedException on REST API).
- **Merge statement and InsertOrUpdate** -- Sybase MERGE syntax support and CanCombineParameters handling. Resolved: #811 (merge builder), #814 (CanCombineParameters in merge-based InsertOrUpdate).
- **ODBC, T4 templates, and provider connectivity** -- Earlier issues with ODBC support, T4 template execution, and Stored Procedure execution. Sample: #186 (SQL Anywhere support), #792 (stored procedure execution), #1060 (invalid cast in transformation), #1064 (query for # columns), #2594 (connecting via ODBC), #2115 (command timeout, resolution external).
- **UPDATE FROM and SQL generation** -- Sybase-specific SQL generation quirks for UPDATE FROM and general operator precedence. Resolved: #2875 (UPDATE FROM generation), #1169 (fix for #1064).
- **CI and provider dependency management** -- Dependency updates and CI environment support. Resolved: #1159 (DataAction AseClient), #1408 (DataAction provider), #1692 (static provider parameter setters), #2951 (Fix Sybase on CI). Test database log handling fixed in PR #5920 (merged 2026-09-13): the test database now truncates its log on checkpoint so a full test lane no longer suspends writers. MERGE segfault in `MergeTests.UnusedSource_Query` killed the ASE session (SIGSEGV); PR #6029 (merged 2026-10-11) excludes Sybase from that test instead of gating it, since #5882 made [ActiveIssue] run the test.
- **Unreferenced parameters in raw SQL** -- Sybase ASE rejects a command parameter that the SQL text never references. FromSql / FromSqlScalar / Sql.Expr now replace such format arguments with NULL before they reach SQL, unless the argument can hold a DataParameter (PR #6008, merged 2026-10-19; cross-tagged, not in the PROV-SYBASE index tag; surfaced by the tests of #6003).
- **Empty identifiers in the Sybase SQL builder** -- `SybaseSqlBuilder.Convert` checked the builder's `Name` before reading `value[0]`, so an empty field name threw IndexOutOfRangeException instead of being quoted (#6023). Fixed by PR #6039 (merged 2026-11-04, adds a regression test). #6023 closed the same day.

## Active discussions
- No active discussions.

## Stats
- Open issues: 7
- Closed issues: 19
- Open PRs: 1
- Total PRs: 17
- Discussions: 0
- Last fetched: 2026-11-11

<details><summary>Coverage</summary>

- Index entries scanned: 43 (26 issues + 17 PRs + 0 discussions) tagged PROV-SYBASE, plus 3 cross-tagged PRs cited by theme (#5566, #5569, #6008), plus 3 GLOBAL or MAPPING issues cited by theme (#2040, #3398, #5973). Keyword sweep covered 6240 entries (3245 issues + 2699 PRs + 296 discussions).
- Themes extracted: 15 (6 open + 9 resolved)
</details>
