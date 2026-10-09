---
area: EXPR-TRANS
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: high
last_verified: 2026-10-10
last_verified_sha: 05150894edc2511f0dd0bc7829b2a309cec36ec9
---

# EXPR-TRANS -- GitHub themes

## Open themes

- **Member/Method translation refactoring** -- Migration of expression methods from the legacy `Sql.Extension` + expose-mapping system into the member-translator pipeline. Landed since last refresh: #5613 (string.CompareTo, merged 2026-06-14), #5544 (string.IsNullOrWhiteSpace, merged 2026-06-09), #5577 (expand member/method mappings at expose, merged 2026-06-07). Still open: #5716 -- `IMemberTranslator` public surface is unusable without `LinqToDB.Internal.*` types (open since 2026-07-13). #5541 (ExpressionMethodAttribute.IsColumn=false at materialization) is closed without a merge record in the index.
- **Projection computation & client-side evaluation** -- #5604 (PreferClientCalculation option, merged 2026-06-26) keeps projection computations client-side, restoring v5 behavior for computed columns. Follow-up #5926 (honour it for string interpolation via declarable optional translation) is closed without a merge record. Open: #5901 (refuse an untranslatable aggregate inside a projection) -- open PR.
- **Lateral / APPLY join emulation** -- #5396 (emulate Lateral/Apply join for SQLite and other providers, open issue) and #5397 (lateral join emulation, open PR). Two items; listed as a recurring topic because the same gap blocks correlated projections on providers without native APPLY.
- **Expression/query cache correctness** -- #6000 (query cache reuses stale SQL when FromSqlScalar is nested inside an IN expression, open since 2026-10-08, label needs-tests) and #5769 (expression caching issue with Sql.IExtensionCallBuilder, closed 2026-09-03). Both are cache-key defects where translated SQL outlives the expression shape that produced it.

## Resolved themes

- **String method translation consolidation** -- #5613 (string.CompareTo), #5544 (string.IsNullOrWhiteSpace), #5504 (string.Concat across all providers, merged 2026-05-15) -- moved from legacy `Sql.Extension` into the member-translator pipeline with per-provider overrides.
- **Expression optimization post-AST refactor** -- #5570 (collapse nested case-conversion wraps in Guid-to-string translation), #5567 (restore IS NULL pushdown through SqlConcatExpression), #5566 (skip bogus IS NULL guards on non-null Sybase concat operands), #5569 (Sybase concatenation to ANSI ||), #5602 (MA0006/MA0154 fixes for #5570). All post-#5504 string-concat AST refactor.
- **Correlated subquery detection & validation** -- #5574 (reject unsupported correlated subqueries in expression position on ClickHouse/YDB), #5558 (fix InvalidCastException in APPLY-to-JOIN conversion with correlated Contains).
- **Nullable type handling in subqueries & correlated contexts** -- #5586 (Nullable<T>.HasValue over unbound members, merged 2026-06-19), #5582 (null-safe IN/NOT IN emulation, merged 2026-06-04).
- **Type translation & casting** -- #5605 (SqlServer decimal overflow fallback via SqlDecimal, merged 2026-07-11), #5466 (DateTimeOffset.DateTime as cast, merged 2026-06-05), #5581 (nullable DateTime subtraction, merged 2026-06-12).
- **TimeSpan & date-difference translation** -- #5750 (TimeSpan members and date differences as elapsed time, merged 2026-08-21), #5739 (native TimeSpan translation, closed), #3994 (original TimeSpan WIP, closed; its binary/unary fixes were carried by #5212).
- **Binary/unary operator translation** -- #5212 (merge binary/unary translation fixes from #3994), closed 2026-08-19 without a merge record in the index.
- **Window Functions API** -- #5468 (new Sql.Window fluent API, merged 2026-07-03) replaces the older `Sql.Ext().Over().ToValue()` pattern. #5725 (fold boolean expressions used in window clauses and arguments, merged 2026-09-05).
- **Projection & materialization edge cases** -- #5587 (spurious [item] column on local-collection LEFT JOIN with decimal projection), #5577 (expand member/method mappings during initial expose), #5581 (nullable DateTime subtraction in final projection), #5818 (set-operation projection rejecting an untranslatable concat operand, merged 2026-08-30).


## Active discussions

- [Resolving base or generic properties](https://github.com/linq2db/linq2db/discussions/4604) -- [Q&A] Translation of inherited/interface properties in entity selects.
- [Extension method cannot be converted to SQL](https://github.com/linq2db/linq2db/discussions/4674) -- [Q&A] Custom method translation constraints.
- [Applying SQL functions to column by default](https://github.com/linq2db/linq2db/discussions/4765) -- [Q&A] Default function wrapping for column operations.
- [Selecting multiple dynamic columns into a custom property type](https://github.com/linq2db/linq2db/discussions/4992) -- [Q&A] Dynamic column mapping to custom types.
- [TRANSLATE function](https://github.com/linq2db/linq2db/discussions/5150) -- [Q&A] SQL TRANSLATE function support.
- [failed comparing datetime](https://github.com/linq2db/linq2db/discussions/5185) -- [Q&A] DateTime comparison across zones/formats.
- [Sql.AsSql and constant expressions](https://github.com/linq2db/linq2db/discussions/5153) -- [General] Design clarifications for SQL expression templates.
- [Version 6.2.* migration Q&A](https://github.com/linq2db/linq2db/discussions/5453) -- [Q&A] Translation breakage across versions.

## Stats

- Open issues: 3 (#5716, #1014, #6000)
- Closed issues: 734
- Open PRs: 2 (#5397, #5901)
- Total PRs: 345 (2 open, 303 merged)
- Discussions: 68
- Last fetched: 2026-10-10

<details><summary>Coverage</summary>

- Index entries scanned: 1150 (737 issues + 345 PRs + 68 discussions), EXPR-TRANS area filter over issues-index.json, prs-index.json, discussions-index.json
- Themes extracted: 4 open, 9 resolved
</details>
