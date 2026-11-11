---
area: PROV-SQLCE
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: high
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
---

# PROV-SQLCE -- GitHub themes

## Open themes
- **BulkCopy exceptions** -- Four open issues report distinct exceptions when bulk-inserting into SQL Server Compact 4.0: ntext field null handling (#4436), large string overflow into ntext (#4581), Expression evaluation overflow (#4438), and StackOverflowException on large batches (#4574). Single-row inserts work correctly, suggesting the issue is in the bulk-copy path or ntext-specific logic.
- **Decimal literal vs parameter scale** -- SQL CE compares a decimal literal at the scale of the other operand, so `1.004` matches a `decimal(18,2)` value of `1.00`, while a parameter compares exactly. linq2db writes constants and captured IN-list values as literals on SqlCe, so these predicates answer true where other providers answer false. Single open item so far (#6062, filed 2026-10-17).
- **Case-sensitive search** -- Incorrect test configuration meant SQLCE case-sensitive-search test never ran; #3444 tracks the regression (related to #2952).
- **CommitMode context option** -- Request to expose CommitMode as a context option for SQL Server Compact (#4686), pending decision on implementation approach. Related closed question #4684 (tagged PROV-SQLSERVER) reports SqlCeTransaction.Commit(CommitMode.Immediate) not committing immediately.
- **SQL CE SQL-shape gaps shared with SQL Server** -- Two items name SQL CE among the affected providers without the PROV-SQLCE tag: #4177 (open PR, opened 2025, fixes string.IsNullOrEmpty / string.Length mapping for SQL CE and MSSQL, fixes #4138) and #6234 (open issue, updated 2026-11-01, a correlated GroupBy keyed on an outer-row member keeps the outer column in GROUP BY, which SQL CE rejects). Only two items so far, so this is a watch-list entry rather than a recurring theme.

## Resolved themes
- **Redistributed binaries and packaging** -- SQL Server Compact binaries were hand-copied into Redist/SqlCe rather than restored from the Microsoft.SqlServer.Compact NuGet package. Resolved by PR #6163 (merged 2026-10-27), which sources SQL Server Compact from its NuGet package and retires Redist/SqlCe; issue #5861 closed the same day. Related: #5535 (tagged PROV-SAPHANA, closed 2026-06-02) reported dotnet pack NU5019 failures for the HintPath-referenced System.Data.SqlServerCe.dll; PR #5565 (closed 2026-06-02) addressed the scaffold-package Redist references.
- **Schema provider PK duplications** -- PR #1761 fixed duplicate primary-key issues in the SQLCE schema provider (issue #695, closed) and related Convert function regressions.
- **Conditional operator** -- Earlier issue #1840 (conditional operator exception) was resolved.
- **Final-alias rewriting** -- By-name column mapping for raw-SQL queries broke when final aliases were applied (#5599, affects SqlCe and YDB). Closed 2026-07-06.
- **SqlCe optimizer table alias reset** -- SqlCeSqlOptimizer with SqlTableType.Expression destroyed the table alias and caused an NRE in UpdatableQuery (#700, closed 2017, tagged EXPR-TRANS).
- **DML service naming** -- PR #5492 renamed SqlCeDMLService to SqlCeDmlService (merged 2026-04-27) per library abbreviation conventions.
- **Test-suite speed** -- PR #5696 set SqlCe Flush Interval=1000 to speed up the test suite (merged 2026-07-10).

## Active discussions
(None currently open)

## Stats
- Open issues: 7
- Closed issues: 6
- Open PRs: 0
- Total PRs: 4
- Discussions: 0 (1 closed)
- Last fetched: 2026-11-11 (index data through 2026-11-11)

<details><summary>Coverage</summary>

- Index entries scanned: 20 (18 PROV-SQLCE-tagged: 7 open issues + 6 closed issues + 4 PRs + 1 closed discussion; plus 2 cross-tagged: #4177, #6234)
- Themes extracted: 12 (5 open + 7 resolved)
</details>
