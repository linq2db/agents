---
area: PROV-SQLCE
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: high
last_verified: 2026-10-10
last_verified_sha: 05150894edc2511f0dd0bc7829b2a309cec36ec9
---

# PROV-SQLCE -- GitHub themes

## Open themes
- **BulkCopy exceptions** -- Four open issues report distinct exceptions when bulk-inserting into SQL Server Compact 4.0: ntext field null handling (#4436), large string overflow into ntext (#4581), Expression evaluation overflow (#4438), and StackOverflowException on large batches (#4574). Single-row inserts work correctly, suggesting the issue is in the bulk-copy path or ntext-specific logic.
- **Case-sensitive search** -- Incorrect test configuration meant SQLCE case-sensitive-search test never ran; #3444 tracks the regression (related to #2952).
- **CommitMode context option** -- Request to expose CommitMode as a context option for SQL Server Compact (#4686), pending decision on implementation approach. Related closed question #4684 (tagged PROV-SQLSERVER) reports SqlCeTransaction.Commit(CommitMode.Immediate) not committing immediately.
- **Redistributed binaries and packaging** -- SQL Server Compact binaries are hand-copied into Redist/SqlCe rather than restored from the Microsoft.SqlServer.Compact NuGet package (#5861, open, filed 2026-09-03). Related closed issue #5535 (tagged PROV-SAPHANA) reports dotnet pack NU5019 failures for the HintPath-referenced System.Data.SqlServerCe.dll.

## Resolved themes
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
- Closed issues: 5
- Open PRs: 0
- Total PRs: 3
- Discussions: 0 (1 closed)
- Last fetched: 2026-10-10 (index data through 2026-10-09)

<details><summary>Coverage</summary>

- Index entries scanned: 16 (7 open issues + 5 closed issues + 3 PRs + 1 closed discussion)
- Themes extracted: 10 (4 open + 6 resolved)
</details>
