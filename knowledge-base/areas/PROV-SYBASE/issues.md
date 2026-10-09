---
area: PROV-SYBASE
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: high
last_verified: 2026-10-10
last_verified_sha: 05150894edc2511f0dd0bc7829b2a309cec36ec9
---

# PROV-SYBASE -- GitHub themes

## Open themes

- **Eager-loading and query validation on Sybase** -- The element-form eager-loading preamble bypasses query validation and silently drops detail rows (#5865). The fix for silently truncated eager-loaded collections is in draft as PR #5900 (fixes #5865, head branch issue/5865-validate-limited-derived-join).
- **Limited subqueries and MERGE row counts** -- ASE applies a TOP inside a derived table to the outer result, so Take() in a subquery silently limits the whole query (#5895). MERGE over a cross-joined source inserts fewer rows than the source has (#5896). Both are open, both measured on Sybase.Managed (AdoNetCore.AseClient) on net10.0.

## Resolved themes

- **String concatenation and ANSI || emission** -- Sybase ASE string concatenation moved from the Transact-SQL `+` operator to ANSI `||` (#5523, PR #5569, merged 2026-06-07). Bogus IS NULL guards on non-null and literal concat operands were removed (#5530, PR #5566, merged 2026-06-04). Both PRs are tagged EFCORE and PROV-DB2 in the index, not PROV-SYBASE.
- **Parameter length, Unicode and type handling** -- Parameter length limit fixed via PR #3908. Unicode parameter length issue (#3916) with a Unicode test added in PR #1300. Float column read as double by DataReader (#3183). Sybase time/datetime and type handling fixed in PR #1792.
- **DateTime and type conversions** -- Multiple closed issues around DateTime handling, type mismatches, and column reading. Sample resolved: #1707 (1900 conversion), #2026 (template timeout), #2038 (ObjectDisposedException on REST API).
- **Merge statement and InsertOrUpdate** -- Sybase MERGE syntax support and CanCombineParameters handling. Resolved: #811 (merge builder), #814 (CanCombineParameters in merge-based InsertOrUpdate).
- **ODBC, T4 templates, and provider connectivity** -- Earlier issues with ODBC support, T4 template execution, and Stored Procedure execution. Sample: #186 (SQL Anywhere support), #792 (stored procedure execution), #1060 (invalid cast in transformation), #1064 (query for # columns), #2594 (connecting via ODBC), #2115 (command timeout, resolution external).
- **UPDATE FROM and SQL generation** -- Sybase-specific SQL generation quirks for UPDATE FROM and general operator precedence. Resolved: #2875 (UPDATE FROM generation), #1169 (fix for #1064).
- **CI and provider dependency management** -- Dependency updates and CI environment support. Resolved: #1159 (DataAction AseClient), #1408 (DataAction provider), #1692 (static provider parameter setters), #2951 (Fix Sybase on CI). Test database log handling fixed in PR #5920 (merged 2026-09-13): the test database now truncates its log on checkpoint so a full test lane no longer suspends writers.

## Active discussions

- No active discussions.

## Stats

- Open issues: 3
- Closed issues: 18
- Open PRs: 1
- Total PRs: 15
- Discussions: 0
- Last fetched: 2026-10-10

<details><summary>Coverage</summary>

- Index entries scanned: 38 (21 issues + 15 PRs + 0 discussions), plus 2 cross-tagged PRs cited by theme (#5566, #5569)
- Themes extracted: 9 (2 open + 7 resolved)
</details>
