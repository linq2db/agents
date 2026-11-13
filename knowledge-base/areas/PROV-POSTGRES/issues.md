---
area: PROV-POSTGRES
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: high
last_verified: 2026-11-11
last_verified_sha: 1732302e2365c87b9465ab754b768a149308a537
---

# PROV-POSTGRES -- GitHub themes

## Open themes

- **Schema handling & identifier quoting** -- Scaffold generation, T4 template instructions, case-sensitivity mismatches and multi-schema edge cases remain high-friction. Newer reports cover CreateTempTableAsync identity handling (#4333), FK and enum DDL generation (#4334, #4335) and migrating *.tt instructions to the CLI scaffolder (#3957). T4 function overloading (#3352) and stored procedures and window functions in schema/T4 (#1444) are still open. Identifier length handling is in open PR #5772: PostgreSQL silently truncates identifiers longer than 63 bytes, so distinct aliases can collide. Citations: #1864, #4671, #3501, #4695, #4708, #3203, #4444, #5086, #4707, #3957, #4333, #4334, #4335, #3352, #1444, PR #5772.
- **Type mapping for PostgreSQL-native types** -- JSON/JSONB, enums, custom scalar types (ltree, pgvector) and range types (tstzrange) lack complete mapping interceptor support. Open reports include enum mapping (#3845), custom DB type configuration without subclassing (#1651), missing PostgresBinaryExpression operator types under EF (#4652), Overlaps on integer arrays (#4562) and broader type mapping (#4818). Users struggle with Contains operator translation, jsonpath queries (#3869, #4044) and ServerSideOnly interaction. Typed literal and predicate type handling is under review in draft PRs #3318 and #5771; a typed smallint parameter that C# short binding breaks is reported in #3298. Numeric semantics: Math.Round away from zero on a double is wrong near a midpoint and above 2^52 (#6266). Citations: #4044, #3869, #4915, #2796, #3845, #1651, #4652, #4562, #4818, #3298, #6266, #3318 (PR), #5771 (PR).
- **Bulk copy & upsert completeness** -- BulkCopy edge cases persist: CheckConstraints option ignored (#1140), KeepIdentity failing to update sequences (#4702), syntax errors on constraint-free operations (#4615) and duplicate-key violations since 5.3.0 (#4641). Insert-with-conflict-action returning rows remains an API gap (#4824). Citations: #1140, #4615, #4702, #4641, #4824.
- **Array & UNNEST support** -- Array type mapping for custom types and UNNEST translation completeness remain active blockers: integer-array queries (#1660, #341) and UNNEST over enum and custom arrays (#4915). Array-of-enum conversion failures were fixed (#4643, see Resolved). Citations: #341, #1660, #4915.
- **DML output & InsertWithOutput** -- Users seek UpdateWithOutput-style semantics on INSERT. Discussion #5679 proposes an INSERT-in-CTE strategy with a materialization trade-off, #3912 asks for the same shape, and #5717 generalizes DML RETURNING as a composable source. Draft PR #6133 is the phase 1 PostgreSQL delivery and supersedes closed PR #5982. Invalid RETURNING output for UpdateWithOutput (DELETED leakage, discussion #4996) remains open. Citations: #5679, #3912, #5717, #4996, #4824, PR #6133.
- **Date/time zone & NodaTime mapping** -- DateTimeOffset components resolve in the session time zone instead of the value offset (#5751). EF Core with Npgsql UseNodaTime fails on value-converted DateTime columns (#5981). DateOnly array columns do not map (#3929). A TimeSpan test on PostgreSQL fails when reading Hours (#2950). Citations: #5751, #5981, #3929, #2950.
- **Dialect gating for older PostgreSQL servers** -- Features newer than the target server are emitted. Filtered aggregates emitted FILTER on 9.2/9.3 (#5948, fixed by PR #5949, see Resolved). string.Join over a filtered grouping still emits the same clause through STRING_AGG on 9.2/9.3 (#5952, #6173). The PostgreSQL 11, 12 and 13 providers are created with the 9.5 mapping schema, so they get 9.5 dialect features (#6137). string.Join over object items types the CONCAT_WS result as its first item (#6200). Citations: #5952, #6173, #6137, #6200.
- **Npgsql driver integration & connection/transaction state** -- Prepared transactions are disabled in EF Core with Npgsql 8+ (#4877), NpgsqlDataSource integration gaps (AutoDetect server version, passwordless connections) remain (#5248), and a SET CONSTRAINTS statement issued after BeginTransaction misbehaves (#5461). The WASM remote client loads Npgsql and other ADO.NET assemblies client-side through unguarded provider mapping schemas (#6167). Npgsql 10 date/time handling is resolved (see Resolved). Citations: #4877, #5248, #5461, #6167.
- **FTS & PostgreSQL extensions** -- Full-text search translation and other PostgreSQL-specific extensions remain unimplemented. Citations: #1811.
- **DistinctBy on PostgreSQL (DISTINCT ON lowering)** -- DistinctBy lowers to DISTINCT ON on PostgreSQL and DuckDB, and rows come back wrong when the sequence is ordered and limited (#6192) or when the key comes from the nullable side of a LEFT JOIN (#6223). Round 2 of the DistinctBy row-choice fix is open in PR #6197 (tagged GLOBAL). Citations: #6192, #6223, PR #6197.

## Resolved themes
- **FromSqlScalar performance regression** -- Mapper compiled per call (6x slowdown); fixed (#5480, closed 2026-04-29).
- **JSONB mapping with computed columns** -- ServerSideOnly functions on JSONB now work correctly (#5505, closed 2026-05-11).
- **F# option type nullability** -- Mapping F# int option None to 0 instead of NULL fixed (#4646, closed 2026-07-04).
- **Order by NULLS LAST** -- Full support for explicit NULL ordering (#2068, closed 2026-06-05).
- **CTE MATERIALIZED** -- PostgreSQL 12+ MATERIALIZED keyword now supported (#5323, closed 2026-04-20).
- **String-to-JSONB Contains** -- Operator translation now respects case behavior (#5347, closed 2026-06-23).
- **Array of enums conversion** -- LinqToDBConvertException when reading or writing arrays of enums fixed (#4643, closed 2026-09-06).
- **Negative typed literals** -- long.MinValue rendered as -9223372036854775808::BigInt was parsed as a negation of a bigint; the literal is now parenthesized before the cast (#5972; PR #5974, merged 2026-10-09).
- **Bulk copy timeout on every batch** -- BulkCopyTimeout was applied only to the first COPY batch; now applied to every batch (#5979; PR #5980, merged 2026-10-09).
- **FILTER clause on PostgreSQL 9.2/9.3** -- Filtered aggregates no longer emit FILTER below the 9.5 dialect tier (#5948 closed 2026-10-26; fix PR #5949 merged 2026-10-26).
- **Npgsql 10 date, time and daterange on netstandard2.0** -- The netstandard2.0 build now converts DateOnly, TimeOnly and NpgsqlRange<DateOnly> back to DateTime, TimeSpan and NpgsqlRange<DateTime> (#6077 closed and PR #6092 merged, 2026-11-10).
- **INSERT RETURNING as a composable source (first attempt)** -- PR #5982 was closed without merge on 2026-10-24 and is superseded by draft PR #6133.

## Active discussions
- [Idea for adding Postgres InsertWithOutput support](https://github.com/linq2db/linq2db/discussions/5679) -- [Ideas] INSERT in a CTE to enable InsertWithOutput for PostgreSQL despite the materialization penalty.
- [Invalid SQL generated through UpdateWithOutput() for PostgreSQL and SQLite](https://github.com/linq2db/linq2db/discussions/4996) -- [Q&A] DELETED tuple leakage into the RETURNING clause.
- [ScaffoldInterceptors: GetTypeMapping - DatabaseType.Name](https://github.com/linq2db/linq2db/discussions/4703) -- [General] ltree columns report USER-DEFINED, so several custom types cannot be told apart.
- [PostgreSQL custom db type mapping problem](https://github.com/linq2db/linq2db/discussions/4863) -- [General] Reading a pgvector column fails with "Reading as System.Object is not supported".

## Stats
- Open issues: 53
- Closed issues: 199
- Open PRs: 3
- Total PRs: 101
- Discussions: 31
- Last fetched: 2026-11-11

<details><summary>Coverage</summary>

- Index entries scanned: 384 (252 issues + 101 PRs + 31 discussions)
- Themes extracted: 10
</details>
