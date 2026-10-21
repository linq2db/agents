---
area: LINQ
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: high
last_verified: 2026-10-21
last_verified_sha: 89b5ce16278728b9936ba374827fea002c76e962
---

# LINQ -- GitHub themes

## Open themes
- **Inheritance and polymorphic queries** -- #4585, #4620, #4773 show recurring exceptions when entity hierarchies (base/derived classes, interface-based associations) are used. Child-type associations fail (#4585), unions of interface-implementing types (#4620), and casting-to-interface in SQL generation (#4773) each block real-world patterns. #5838 adds a related case: InsertWithOutput/UpdateWithOutput on an inheritance-mapped table reads the key as the discriminator. 4 open.

- **Eager-load ordering and strategy edge cases** -- #5816, #5823, #5904, #5937, #5941 cover the newer eager-load strategies (CteUnion, keyed strategy, ToSqlQuery over an eager-loaded ITable). Child ordering is not guaranteed under Take/Skip (#5937), OrderBy keys are dropped through Cast/OfType and composite projections (#5941), and the keyed strategy silently falls back to Default when a parent reuses an inner window/aggregate value (#5904). Provider-level instance in open PR #5900 (Sybase silently truncates eager-loaded collections). 5 open issues, 1 open PR.

- **PreferClientCalculation and missed LEFT JOIN semantics** -- #5925, #5928, #5929, #5985 come from the PreferClientCalculation option (#5604). A missed LEFT JOIN yields default(T) on read but NULL inside SQL calculations (#5929). Bool-returning members route inconsistently (#5925), a declined instance-method translation gets a null receiver (#5928), and a correlated FirstOrDefault references an outer column out of scope (#5985). Same family, newly reported: #6046 (missed LEFT JOIN row calculated over NULL in eager-load and CTE projections), #6087 (math functions over a missed LEFT JOIN row throw "Nullable object must have a value"), #6089 (ClickHouse decimal division by a missed LEFT JOIN row overflows). The read-side fix for projection calculations merged in PR #5983 (2026-10-21), and #5923 and #5932 closed the same day, see Resolved. 7 open issues.

- **Duration and date-difference units** -- #5776 (Contains over a computed duration difference does not reconcile units), #5796 (a set operation mixing a computed difference and a declared duration), #5924 (PreferClientCalculation bypasses the interval unit-declaration guard), #5930 (SQLite: DateTime minus an explicitly declared TimeSpan has no translation). Shares the interval-translation work of #5750 (merged 2026-08-21) and open PR #5931 (SQLite date arithmetic with declared durations). Open PRs #5892 (DateTimeOffset difference measured on instants) and #5913 (DateTimeOffset time-zone answers) extend the same date-arithmetic surface. 4 open issues, 3 open PRs, cross-area.

- **Query-build performance and cache keys** -- #5738 (visitor-based tree traversals in query compilation) and #5843 (collection constants in the query-cache key compared by reference) remain open. Newly reported cache-key defects: #6059 ([SqlQueryDependent] values that are Equals-equal but render differently share one cache entry) and #6045 (CompiledQuery raw SQL format or closure-captured arguments reuse the first build). Open PR #6033 caches command text for queries with a constant TAKE/SKIP. #5911 (whole-tree optimizer runs five times per build, SQL-AST) is the counterpart. 4 open issues, 1 open PR.

- **Expression translation semantics gaps** -- #5879 (IndexExpression rejected by PathVisitor), #5921 (string.Format specifiers silently dropped), #5927 (string.CompareOrdinal mapped onto culture-sensitive CompareTo), #5953 (Sql.Property rejects a name taken from a lambda parameter). Newly reported: #6066 (nullable inline-array Contains converted to string returns NULL where C# returns "False"), #6070 (a narrowing numeric conversion followed by a widening back is dropped before SQL is built), #6072 (integer Sql.Degrees overloads keep the fraction where the engine's DEGREES returns a float), #6079 (inline IN list values typed through SUM and type-changing casts, narrowing a literal the operand does not hold), #6047 (Access: GroupBy(...).Select(aggregate).Contains(value) places the aggregate in WHERE). Each fails silently, returns a wrong value, or raises an undiagnosed exception instead of a clear translation error. 9 open.

- **F# query surface** -- #5790 (chained groupJoin with a correlated inner sequence fails to translate) and #5794 (a trailing join after chained groupJoins silently drops unmatched rows). Small cluster; related to open PR #5673 (F# option mapping). 2 open.

- **Query projection optimization** -- #5303 (6.0.0 regression: different result count depending on which properties are projected; epic eager-load). Composite-property selection (#4568) closed 2026-07-22, see Resolved. 1 open.

- **Configuration and data-context APIs** -- #4039, #5195, #5253 span parameter logging (raw vs masked in `.UseDefaultLogging`), context replacement for reusable `IQueryable` pipelines, and LINQPad configuration. Users need more control over data-context lifetime and introspection. 3 open.

- **Version-specific regressions** -- #5560 (DateTime.Date under MSSQL extensions) remains open. #4624 (3.0.0-rc0 + EF Core 3.2.0 null-ref) closed 2026-08-25, see Resolved. 1 open.

- **Provider-specific features** -- #1014 is a voting thread for new RDBMS platforms (cross-area, EXPR-TRANS), #5171 requests ClickHouse tuple support for Oracle-style `IN (tuple)` clauses. Niche but request-backed. 2 open.

- **Schema and infrastructure improvements** -- #5403 (migrate raw SQL in SchemaProvider implementations to LINQ queries), #5455 (support new .NET 11 LINQ APIs). 2 open.

- **Optimistic concurrency & write-back** -- #5650 proposes a `.UseConcurrencyField()` / `.Fetch()` builder pattern for Update operations with optimistic locking and read-back semantics. 1 open (candidate for next-version feature gate).

- **Untranslatable aggregates and correlated subqueries inside projections** -- #5787 (an aggregate with an untranslatable selector inside a projection fails with "There is no method AggregateExecute"), #6035 (ArgumentException "must be reducible node" for a correlated Select(anonymous).Distinct().Count(predicate) inside a projection), #6080 (a provider's refusal inside a projection filtered through AsSubQuery() reports only "could not be converted to SQL"), #6034 (apply joins over set operations are not decorrelated). Open PR #5901 (refuse an untranslatable aggregate inside a projection) is the fix candidate. 4 open issues, 1 open PR.

- **Nullable and struct values built in inner projections** -- #6068 ("Coalesce used with type that cannot be null" when a struct built in an inner projection is referenced twice), #6090 (ArgumentException "Property is not defined for type Nullable<T>" when a nullable struct built in an inner projection is read), #6093 (.Value.member and .HasValue not translated for a nullable struct from an inner projection), #6094 (Union/Concat of a lifted struct with a (T?) null branch throws NullReferenceException on read). Open PRs #6069 (duplicated struct constructor) and #6091 (members of a lifted or upcast value from an inner projection) address parts of this. 4 open issues, 2 open PRs.

- **Date/time literal typing and comparisons** -- cross-area. #5997 (date/time literal compared with a coarser column loses its sub-second part), #6081 (SQLite and ClickHouse: a date column IN a list of datetime columns misses a match that equality finds), #6078 (SQL Server: a datetime literal beside MAX/COALESCE of a datetime column is written as datetime2 and misses a read-back value), #6071 (text to date/time casts are wrong on SQLite and Informix and return no rows on YDB). The LINQ-side typing of IN lists is #6079, listed under Expression translation semantics gaps. 4 open.

- **netstandard2.0 build does not translate modern BCL overloads** -- #6067 ("Contains" cannot be converted to SQL on .NET 10) and open PR #6074 (recognise C# 14 span Contains in the netstandard2.0 build) are one gap. #6075 (netstandard2.0 build misses string.TrimStart() and TrimEnd() no-arg and char overloads) and open PR #6082 (translate them in the netstandard2.0 build) are another. 2 open issues, 2 open PRs.

## Resolved themes
- **Union and set-operation associations** -- 11+ closed issues (sample: #2503, #2505, #2619, #2932, #2966, #3323, #3346, #3669). Recent closures: #5617 (column order inside UnionAll), #5683 (recursive CTE with differing-but-assignable projection types), #5916 (Concat over IQueryable<object> dropping projection members), #5792 (entity query filter dropping a left-join null check in a set-operation operand), #5976 (Concat/Union with EF Core value converters on DateTime properties throws "operands for operator NotEqual do not match"; closed 2026-10-09), and PR #6060 (regression test for Union over columns sharing a value converter class; merged 2026-10-16). Unions, concats, and set operations with entities, calculated fields, and associations were historically broken; now mostly fixed.

- **Inheritance edge cases** -- 6+ closed (sample: #292, #1008, #1017, #2161, #3034, #5274). Base-class load queries, derived-class filters in `LoadWith`, discriminator ambiguity, and interface-inheritance mapping have been addressed. Also closed: #5304 (entity inheriting List<T> produced an unreducible SELECT 1 node), #4460 (abstract class in a TPH tree, fixed by PR #5661), and #4199 (Property X is not defined for interface type Y; closed 2026-10-21, tests rewritten to the issue's repro and the gate removed in PR #6097).

- **Calculated fields and projection stability** -- #3150, #2461 were about nested projections losing constants or throwing on union+calculated-field; now resolved. #4568 (selecting all entity columns when only a composite property is selected) closed 2026-07-22 with coverage from PR #5724. #5824 (Update/Delete cannot resolve the target table over a projection that constructs an entity) closed 2026-08-26.

- **Keyed eager-load fixes** -- #5664 (non-deterministic VALUES key order, fixed by PR #5665), #5936 (detail-side Take/Skip applied globally instead of per parent, closed 2026-10-01), and PR #5938 (OrderBy dropped when the ordering key is absent from the projection, closed 2026-10-07).

- **Version and release regressions** -- #4624 (3.0.0-rc0 + linq2db.EntityFrameworkCore 3.2.0 null-ref, closed 2026-08-25), #5649 (LoadWith breaking change between 6.1.0 and 6.2.0, closed 2026-06-27), #5625 ("Table not found" when Concat is followed by a filtering Join, closed 2026-06-19 via PR #5629).

- **Query cache staleness** -- #6000 (cached SQL reused when FromSqlScalar is nested inside an IN expression; closed 2026-10-16), PR #6003 (stale cached SQL for FromSql, FromSqlScalar and Sql.Expr nested in a query; closed 2026-10-16), PR #6007 (cached-query mutation in IN-to-EXISTS conversion; closed 2026-10-13), and #5857 (Sql.Expr<T>(FormattableString) rebuilt on every execution because the registered FormattableString is compared by reference; closed 2026-10-16).

- **Missed LEFT JOIN read path** -- #5932 (non-nullable member is default(T) when read, NULL inside SQL calculations) and #5923 (Sql.ToNullable over a binary expression returns a value instead of NULL) closed 2026-10-21, with the reader-side fix in PR #5983 (merged 2026-10-21).

- **F# record materialization** -- PR #6025 (fix record materialization when the record declares a static let; closed 2026-10-12).

## Active discussions
- No active discussions in the LINQ area.

## Open PRs
- **#3367** (draft) -- Address multiple issues with SET queries. Support more than two set operations in sequence without wrapping them into subqueries when operations are identical.
- **#5376** (ready) -- Add package-local linq2db AI skill and Expert knowledge pack. Fixes #4437.
- **#5673** (draft) -- Unify combined-command execution and eager loading. Adds automatic mapping of F# option columns to the `linq2db.FSharp` package.
- **#5708** (open) -- PIVOT / UNPIVOT support (#1475).
- **#6069** (open) -- Fix duplicated struct constructor failing with "Coalesce used with type that cannot be null".
- **#6091** (open) -- Fix members of a lifted or upcast value from an inner projection failing with "Property is not defined for type".

## Stats
- Open issues: 48 (area=LINQ in issues-index.json, recounted 2026-10-21)
- Closed issues: 50 (same basis)
- Open PRs: 4 (area=LINQ in prs-index.json: #3367, #5708, #6069, #6091). Cross-area open PRs cited above: #5376, #5673, #5892, #5900, #5901, #5913, #5931, #6033, #6074, #6082.
- Total PRs: 22 (area=LINQ; 4 open, 18 closed)
- Discussions: 0
- Last fetched: 2026-10-21 (index entries through 2026-10-21)

<details><summary>Coverage</summary>

- Index entries scanned: 128 fetched this refresh (63 issues + 65 PRs); LINQ-area index entries 98 issues + 22 PRs
- Themes extracted: 17 open + 8 resolved
- Stats recounted on the index area field this refresh; the prior run used a different basis.
</details>
