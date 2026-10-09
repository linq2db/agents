---
area: PROV-POSTGRES
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: high
last_verified: 2026-10-10
last_verified_sha: 05150894edc2511f0dd0bc7829b2a309cec36ec9
---

# PROV-POSTGRES -- GitHub themes

## Open themes

- **Schema handling & identifier quoting** -- Scaffold generation, T4 template instructions, case-sensitivity mismatches and multi-schema edge cases remain high-friction. Newer reports cover CreateTempTableAsync identity handling (#4333), FK and enum DDL generation (#4334, #4335) and migrating *.tt instructions to the CLI scaffolder (#3957). Citations: #1864, #4671, #3501, #4695, #4708, #3203, #4444, #5086, #4707, #3957, #4333, #4334, #4335.
- **Type mapping for PostgreSQL-native types** -- JSON/JSONB, enums, custom scalar types (ltree, pgvector) and range types (tstzrange) lack complete mapping interceptor support. Open reports include enum mapping (#3845), custom DB type configuration without subclassing (#1651), missing PostgresBinaryExpression operator types under EF (#4652), Overlaps on integer arrays (#4562) and broader type mapping (#4818). Users struggle with Contains operator translation, jsonpath queries (#3869, #4044) and ServerSideOnly interaction. Typed literal and predicate type handling is under review in draft PRs #3318 and #5771. Citations: #4044, #3869, #4915, #2796, #3845, #1651, #4652, #4562, #4818, #3318 (PR), #5771 (PR).
- **Bulk copy & upsert completeness** -- BulkCopy edge cases persist: CheckConstraints option ignored (#1140), KeepIdentity failing to update sequences (#4702), syntax errors on constraint-free operations (#4615) and duplicate-key violations since 5.3.0 (#4641). Insert-with-conflict-action returning rows remains an API gap (#4824). Citations: #1140, #4615, #4702, #4641, #4824.
- **Array & UNNEST support** -- Array type mapping for custom types and UNNEST translation completeness remain active blockers: integer-array queries (#1660, #341) and UNNEST over enum and custom arrays (#4915). Array-of-enum conversion failures were fixed (#4643, see Resolved). Citations: #341, #1660, #4915.
- **DML output & InsertWithOutput** -- Users seek UpdateWithOutput-style semantics on INSERT. Discussion #5679 proposes an INSERT-in-CTE strategy with a materialization trade-off, #3912 asks for the same shape, and #5717 generalizes DML RETURNING as a composable source; draft PR #5982 delivers phase 1 for PostgreSQL. Invalid RETURNING output for UpdateWithOutput (DELETED leakage, discussion #4996) remains open. Citations: #5679, #3912, #5717, #4996, #4824, PR #5982.
- **Date/time zone & NodaTime mapping** -- DateTimeOffset components resolve in the session time zone instead of the value offset (#5751). EF Core with Npgsql UseNodaTime fails on value-converted DateTime columns (#5981). DateOnly array columns do not map (#3929). Citations: #5751, #5981, #3929.
- **Dialect gating for older PostgreSQL servers** -- Features newer than the target server are emitted: filtered aggregates emit FILTER on 9.2/9.3 (#5948), and string.Join over a filtered grouping emits the same clause through STRING_AGG (#5952). Open PR #5949 gates FILTER on the 9.5 dialect tier. Citations: #5948, #5952, PR #5949.
- **Npgsql driver integration & connection/transaction state** -- Prepared transactions are disabled in EF Core with Npgsql 8+ (#4877), NpgsqlDataSource integration gaps (AutoDetect server version, passwordless connections) remain (#5248), and a SET CONSTRAINTS statement issued after BeginTransaction misbehaves (#5461). Citations: #4877, #5248, #5461.
- **FTS & PostgreSQL extensions** -- Full-text search translation and other PostgreSQL-specific extensions remain unimplemented. Citations: #1811.

## Resolved themes
- **FromSqlScalar performance regression** -- Mapper compiled per call (6x slowdown); fixed (#5480, closed 2026-04-29).
- **JSONB mapping with computed columns** -- ServerSideOnly functions on JSONB now work correctly (#5505, closed 2026-05-11).
- **F# option type nullability** -- Mapping F# int option None to 0 instead of NULL fixed (#4646, closed 2026-07-04).
- **Order by NULLS LAST** -- Full support for explicit NULL ordering (#2068, closed 2026-06-05).
- **CTE MATERIALIZED** -- PostgreSQL 12+ MATERIALIZED keyword now supported (#5323, closed 2026-04-20).
- **String-to-JSONB Contains** -- Operator translation now respects case behavior (#5347, closed 2026-06-23).
- **Array of enums conversion** -- LinqToDBConvertException when reading or writing arrays of enums fixed (#4643, closed 2026-09-06).

## Active discussions
- [Idea for adding Postgres InsertWithOutput support](https://github.com/linq2db/linq2db/discussions/5679) -- [Ideas] INSERT in a CTE to enable InsertWithOutput for PostgreSQL despite the materialization penalty.
- [Invalid SQL generated through UpdateWithOutput() for PostgreSQL and SQLite](https://github.com/linq2db/linq2db/discussions/4996) -- [Q&A] DELETED tuple leakage into the RETURNING clause.
- [ScaffoldInterceptors: GetTypeMapping - DatabaseType.Name](https://github.com/linq2db/linq2db/discussions/4703) -- [General] ltree columns report USER-DEFINED, so several custom types cannot be told apart.
- [PostgreSQL custom db type mapping problem](https://github.com/linq2db/linq2db/discussions/4863) -- [General] Reading a pgvector column fails with "Reading as System.Object is not supported".

## Stats
- Open issues: 42
- Closed issues: 203
- Open PRs: 4
- Total PRs: 98
- Discussions: 31
- Last fetched: 2026-10-09

<details><summary>Coverage</summary>

- Index entries scanned: 374 (245 issues + 98 PRs + 31 discussions)
- Themes extracted: 9
</details>
