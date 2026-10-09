---
area: DATA
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: medium
last_verified: 2026-10-10
last_verified_sha: 05150894edc2511f0dd0bc7829b2a309cec36ec9
---

# DATA -- GitHub themes

## Open themes

- **BulkCopy timeout and options configuration** -- Where BulkCopy settings are configured and whether they take effect. Live items: #4660 (BulkCopyOptions cannot be set once for the whole context) and #6001 (BulkCopy timeout falls back to the driver default instead of the documented infinite timeout). Closed items with the same shape: #4341 (UseBulkCopyTimeout helpers do not touch options), #418 (BulkCopy should honour the connection CommandTimeout, fixed by PR #2383), #5829 (MaxParametersForBatch can only lower the limit). Only two open items, kept as a theme because both are live and share the same keywords.

## Resolved themes
- **Merge API** -- Multiple bugs and edge cases fixed across versions. Recent: #5476 (Merge API unusable, closed 2026-04-24), #5181 (PGSQL Merge with unused source, fixed by PR #5205), #4971 (entity inheritance, fixed by PR #4983), #4338 (joins with Merge), #2843 (invalid SQL for UpdateWhenMatched on PK-only tables, fixed by PR #2861).
- **BulkCopy operations** -- Error handling, type mapping, async support, and options scoping. Examples: #4672 (NodaTime Period), #4461 (CLOB), #4534 (async cancellation), #1541 (BulkCopyOptions reused across tables).
- **InsertWithOutput variants** -- Correctness issues with aggregates, joins, and output routing. Examples: #5192, #3983, #3834 (column name mismatches).
- **Async API surface** -- Missing or broken async overloads, cancellation and transaction methods. Examples: #1540 (async transaction methods, PR #1582), #2901 (BeginTransactionAsync cast failure), #3171 (missing async Query overloads), #4534 (SelectAsync ignores cancellation token overrides).

## Active discussions
- [How to get records which were failed while bulk copy insert](https://github.com/linq2db/linq2db/discussions/3081) -- [Q&A] Handling failed rows during bulk operations.
- [Is it ok to open another dataconnection inside ProcessQuery?](https://github.com/linq2db/linq2db/discussions/3388) -- [Q&A] Connection lifecycle and interceptor scope.
- [[Update|Insert|Delete]WithOutputIntoOutput](https://github.com/linq2db/linq2db/discussions/3831) -- [Ideas] Chaining output operations.
- [How to write Merge which only updates some columns?](https://github.com/linq2db/linq2db/discussions/4279) -- [Q&A] Selective column updates in MERGE.
- [AsQueryable Paramterization?](https://github.com/linq2db/linq2db/discussions/4421) -- [Q&A] Using InsertWithOutput with AsQueryable client datasets (open).
- [A way to not inline Merge parameters](https://github.com/linq2db/linq2db/discussions/4582) -- [Q&A] Parameter handling in MERGE with custom checks.
- [Options as record type in version 6 is bad idea](https://github.com/linq2db/linq2db/discussions/4704) -- [General] DataOptions record vs class initialization.
- [Tracking the changes](https://github.com/linq2db/linq2db/discussions/4834) -- [Q&A] Identity tracking post-BulkCopy.
- [Still necessary to have two SetConverter](https://github.com/linq2db/linq2db/discussions/5165) -- [Q&A] C# type vs DataParameter converter redundancy.

## Stats

- Open issues: 2 (#4660, #6001)
- Closed issues: 75
- Open PRs: 1 (#3354, WIP COALESCE to ISNULL optimization)
- Total PRs: 83
- Discussions: 9 (1 open: #4421)
- Last fetched: 2026-10-09

<details><summary>Coverage</summary>

- Index entries scanned: 169 (77 issues + 83 PRs + 9 discussions)
- Themes extracted: 5
</details>
