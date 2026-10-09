---
area: LINQ
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: high
last_verified: 2026-10-10
last_verified_sha: 05150894edc2511f0dd0bc7829b2a309cec36ec9
---

# LINQ -- GitHub themes

## Open themes
- **Inheritance and polymorphic queries** -- #4585, #4620, #4773 show recurring exceptions when entity hierarchies (base/derived classes, interface-based associations) are used. Child-type associations fail (#4585), unions of interface-implementing types (#4620), and casting-to-interface in SQL generation (#4773) each block real-world patterns. #5838 adds a related case: InsertWithOutput/UpdateWithOutput on an inheritance-mapped table reads the key as the discriminator. 4 open.

- **Eager-load ordering and strategy edge cases** -- #5816, #5823, #5904, #5937, #5941 cover the newer eager-load strategies (CteUnion, keyed strategy, ToSqlQuery over an eager-loaded ITable). Child ordering is not guaranteed under Take/Skip (#5937), OrderBy keys are dropped through Cast/OfType and composite projections (#5941), and the keyed strategy silently falls back to Default when a parent reuses an inner window/aggregate value (#5904). 5 open.

- **PreferClientCalculation and missed LEFT JOIN semantics** -- #5923, #5925, #5928, #5929, #5932, #5985 come from the PreferClientCalculation option (#5604). A missed LEFT JOIN yields default(T) on read but NULL inside SQL calculations (#5929, #5932). Bool-returning members route inconsistently (#5925), a declined instance-method translation gets a null receiver (#5928), Sql.ToNullable over a binary expression returns a value instead of NULL (#5923), and a correlated FirstOrDefault references an outer column out of scope (#5985). Fix in flight: PR #5983 (reader-side missed LEFT JOIN, GLOBAL area). 6 open.

- **Duration and date-difference units** -- #5776 (Contains over a computed duration difference does not reconcile units), #5796 (a set operation mixing a computed difference and a declared duration), #5924 (PreferClientCalculation bypasses the interval unit-declaration guard), #5930 (SQLite: DateTime minus an explicitly declared TimeSpan has no translation). Shares the interval-translation work of #5750 and open PR #5931 (SQLite date arithmetic with declared durations). 4 open, cross-area.

- **Query-build performance and cache keys** -- #5738 (visitor-based tree traversals in query compilation), #5843 (collection constants in the query-cache key compared by reference), #5857 (Sql.Expr FormattableString rebuilt on every execution). Performance work on the translation path; #5911 (whole-tree optimizer runs five times per build, SQL-AST) is the counterpart. 3 open.

- **Expression translation semantics gaps** -- #5879 (IndexExpression rejected by PathVisitor), #5921 (string.Format specifiers silently dropped), #5927 (string.CompareOrdinal mapped onto culture-sensitive CompareTo), #5953 (Sql.Property rejects a name taken from a lambda parameter). Each fails silently or with an undiagnosed exception instead of a clear translation error. 4 open.

- **F# query surface** -- #5790 (chained groupJoin with a correlated inner sequence fails to translate) and #5794 (a trailing join after chained groupJoins silently drops unmatched rows). Small cluster; related to open PR #5673 (F# option mapping). 2 open.

- **Query projection optimization** -- #5303 (6.0.0 regression: different result count depending on which properties are projected; epic eager-load). Composite-property selection (#4568) closed 2026-07-22, see Resolved. 1 open.

- **Configuration and data-context APIs** -- #4039, #5195, #5253 span parameter logging (raw vs masked in `.UseDefaultLogging`), context replacement for reusable `IQueryable` pipelines, and LINQPad configuration. Users need more control over data-context lifetime and introspection. 3 open.

- **Version-specific regressions** -- #5560 (DateTime.Date under MSSQL extensions) remains open. #4624 (3.0.0-rc0 + EF Core 3.2.0 null-ref) closed 2026-08-25, see Resolved. 1 open.

- **Provider-specific features** -- #1014 is a voting thread for new RDBMS platforms (cross-area, EXPR-TRANS), #5171 requests ClickHouse tuple support for Oracle-style `IN (tuple)` clauses. Niche but request-backed. 2 open.

- **Schema and infrastructure improvements** -- #5403 (migrate raw SQL in SchemaProvider implementations to LINQ queries), #5455 (support new .NET 11 LINQ APIs). 2 open.

- **Optimistic concurrency & write-back** -- #5650 proposes a `.UseConcurrencyField()` / `.Fetch()` builder pattern for Update operations with optimistic locking and read-back semantics. 1 open (candidate for next-version feature gate).

## Open PRs
- **#3367** (draft) -- Address multiple issues with SET queries. Support more than two set operations in sequence without wrapping them into subqueries when operations are identical.
- **#5376** (ready) -- Add package-local linq2db AI skill and Expert knowledge pack. Fixes #4437.
- **#5673** (draft) -- Unify combined-command execution and eager loading. Adds automatic mapping of F# `'T option` columns to the `linq2db.FSharp` package.

## Resolved themes
- **Union and set-operation associations** -- 11+ closed issues (sample: #2503, #2505, #2619, #2932, #2966, #3323, #3346, #3669). Recent closures: #5617 (column order inside UnionAll), #5683 (recursive CTE with differing-but-assignable projection types), #5916 (Concat over IQueryable<object> dropping projection members), #5792 (entity query filter dropping a left-join null check in a set-operation operand). Unions, concats, and set operations with entities, calculated fields, and associations were historically broken; now mostly fixed.

- **Inheritance edge cases** -- 6+ closed (sample: #292, #1008, #1017, #2161, #3034, #5274). Base-class load queries, derived-class filters in `LoadWith`, discriminator ambiguity, and interface-inheritance mapping have been addressed. Also closed: #5304 (entity inheriting List<T> produced an unreducible SELECT 1 node) and #4460 (abstract class in a TPH tree, fixed by PR #5661).

- **Calculated fields and projection stability** -- #3150, #2461 were about nested projections losing constants or throwing on union+calculated-field; now resolved. #4568 (selecting all entity columns when only a composite property is selected) closed 2026-07-22 with coverage from PR #5724. #5824 (Update/Delete cannot resolve the target table over a projection that constructs an entity) closed 2026-08-26.

- **Keyed eager-load fixes** -- #5664 (non-deterministic VALUES key order, fixed by PR #5665), #5936 (detail-side Take/Skip applied globally instead of per parent, closed 2026-10-01), and PR #5938 (OrderBy dropped when the ordering key is absent from the projection, closed 2026-10-07).

- **Version and release regressions** -- #4624 (3.0.0-rc0 + linq2db.EntityFrameworkCore 3.2.0 null-ref, closed 2026-08-25), #5649 (LoadWith breaking change between 6.1.0 and 6.2.0, closed 2026-06-27), #5625 ("Table not found" when Concat is followed by a filtering Join, closed 2026-06-19 via PR #5629).

## Active discussions
- No active discussions in the LINQ area.

## Stats
- Open issues: 37 (LINQ-tagged in the index). Cited open items outside LINQ: #1014 (EXPR-TRANS), #5796 (GLOBAL), #5930 (PROV-SQLITE).
- Closed issues: 44
- Open PRs: 3 (#3367, #5376, #5673; #5673 is BUILD-tagged and kept as an existing citation)
- Total PRs: 18+
- Discussions: 0
- Last fetched: 2026-10-10 (index entries through 2026-10-09)

<details><summary>Coverage</summary>

- Index entries scanned: 185 (3 indexes: LINQ-tagged issues 81 and PRs 18, plus 86 cross-area items cited or title-matched)
- Themes extracted: 13 open + 5 resolved
</details>
