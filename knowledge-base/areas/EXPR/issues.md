---
area: EXPR
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: low
last_verified: 2026-10-10
last_verified_sha: 05150894edc2511f0dd0bc7829b2a309cec36ec9
---

# EXPR -- GitHub themes

## Open themes
- **No recurring theme yet** -- the index holds two EXPR-classified issues, below the 3-item threshold. Open: [#5815](https://github.com/linq2db/linq2db/issues/5815) -- `ITable<T>`-mutating extensions resolve their target with an unconditional `(ITableMutable<T>)` cast; provider-hint table wrappers (`DatabaseSpecificTable<TSource>` and subclasses such as `SQLiteSpecificTable`, `SqlServerSpecificTable`) do not implement `ITableMutable<T>`, so the cast fails at runtime.

## Resolved themes
- No resolved theme. Closed: [#5788](https://github.com/linq2db/linq2db/issues/5788) (closed 2026-09-08) -- request for analyzers that flag a mismatch between a server-side-only implementation and its declared contract. Single item, no theme.

## Active discussions
- None. No EXPR-classified discussions in the index.

## Stats
- Open issues: 1
- Closed issues: 1
- Open PRs: 0
- Total PRs: 0
- Discussions: 0
- Last fetched: 2026-10-09

<details><summary>Coverage</summary>

- Index entries scanned: 2 (2 issues + 0 PRs + 0 discussions)
- Themes extracted: 0
</details>
