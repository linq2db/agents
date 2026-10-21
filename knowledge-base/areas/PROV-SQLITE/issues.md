---
area: PROV-SQLITE
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: high
last_verified: 2026-10-21
last_verified_sha: 89b5ce16278728b9936ba374827fea002c76e962
---

# PROV-SQLITE -- GitHub themes

## Open themes

- **DateTime/duration arithmetic** -- SQLite cannot translate DateTime/DateTimeOffset addition or subtraction of an explicitly declared duration. Open issue #5930 (nullable DateTime minus TimeSpan throws LinqToDBException in 6.5.0); the fix is open PR #5931 (translates declared-duration arithmetic incl. nullable operands, predicates and remote queries; updated 2026-10-12 to also preserve DateTimeOffset offsets through duration arithmetic and Sql.DateAdd/AddX). Same area as earlier date bugs: #998 (DateAdd with table data), #1688 with PRs #1689 and #1691 (DateDiff / AddDate), #4904 (DateTime.MaxValue comparison), #2346 and #4038 (Ticks/Int64 wrapping).
- **DateTimeOffset storage, reads and DateTime() wrapping** -- several open items show DateTime/DateTimeOffset values going wrong around the SQLite DATETIME() wrapper and the read path: #1855 (DateTimeOffset queries generate incorrect SQL), #2432 (linq2db.SQLite.MS problems caused by wrapping values in DateTime()), #6031 (DateTimeOffset columns read through GetDateTime, offset lost, MaxValue throws), #2107 (BulkInsert does not set UTC), #6071 (text to date/time casts return wrong results on SQLite, Informix and return no rows on YDB), #6081 (a date column IN a list of datetime columns misses a match that == finds). Related: #3766 (DateTimeOffset primary key) and the DateTimeOffset arithmetic in PR #5931.
- **DateTimeOffset as primary key** -- single open item #3766 (SQLite.Classic with DateTimeOffset primary key). No open PR; also cited in the DateTimeOffset storage theme above.
- **Microsoft.Data.Sqlite (SQLite.MS) provider runtime** -- problems specific to the Microsoft.Data.Sqlite provider: #4446 (AOT: Method not found for SqliteConnection.ClearAllPools), #6028 (grouped MAX(CASE ... THEN string ELSE NULL END) throws String -> Byte[] on the second, cached execution), plus the SQLite.MS items #2432 and #6031 cited in the DateTimeOffset theme.
- **Join, apply and table-valued function gaps** -- SQL features SQLite lacks, which linq2db has to emulate or cannot yet translate: #1224 (emulate FULL OUTER JOIN for databases without it), #4988 ([SQLite] add apply translation), #5396 (emulate Lateral/Apply join support for SQLite or other providers), #3408 (json_each / json_tree table-valued functions).
- **Numeric affinity and integer arithmetic** -- SQLite type affinity leaks into arithmetic and mapping: #5611 (decimal division renders as integer division because CAST(x AS Decimal) keeps NUMERIC affinity), #6072 (integer Sql.Degrees overloads keep the fraction in SQL where the engine DEGREES returns a float; also DuckDB), #3899 (SQLite unsigned integers mapping).
- **Metadata loading and configuration** -- open #5906 proposes removing the PreLoadSQLite_BaseDirectory setting (set in three places, likely unused by the System.Data.SQLite 2.x line). Open Q&A on the same surface: discussion #3126 (relative path for LoadSQLiteMetadata) and #4985 (PRAGMA table functions joined with sqlite_master).
- **SQL precedence in string.Join** -- single open item #5984: an arithmetic item in string.Join over object items is emitted without parentheses, so SQLite's concatenation operator binds tighter than plus. Singleton.
- **Dynamic columns through FromQuery** -- single open item #2953: dynamic column mappings are not applied to results of IDataContext.FromQuery(...). Singleton.

## Resolved themes

- **DateTime/DateTimeOffset in SQLite** -- closed #378, #338, #998, #2346, #4038, #4904; DateDiff/AddDate via #1688 with PRs #1689 and #1691; sub-millisecond tick rendering fixed in PR #5682.
- **Schema/Scaffolding** -- closed #784, #930, #934, #1269, #2099, #3330, #4117 (Schema API for Microsoft.Data.Sqlite), #4449, #4736, #4802 (0 tables read via the Microsoft provider). Fixes: PR #5117 (primary key detection, fixes #5014), PR #5122 (pragma-based metadata queries) and PR #5606 (deterministic table/view ordering in the schema provider, closed 2026-06-14).
- **Guid mapping** -- closed #159, #1878, #4295, #4808; PRs #3580 (Guid mapping fix) and #5380 (do not type Guid values explicitly). Discussions #4296 and #4500 closed.
- **Type mapping and conversion** -- closed #1279 (char mapping), #1960 (CreateTable SQL type), #2354 (double.MaxValue rounding), #3129 (decimal separator on read-back), #3067 (custom type over byte array); PRs #925 and #1291 (char parameters on Microsoft.Data.Sqlite).
- **Bulk operations** -- closed #330, #2844 (inefficient bulk update SQL from in-memory collection), #5282 (InsertWithIdentity returns incorrect value).
- **Connection, packaging and runtime** -- closed #21, #512, #199, #374, #261, #346, #1493, #4170 (Xamarin/Android DllNotFound), #4512 (Interop.dll delete on multi-targeting); PRs #502 (System.Data.Sqlite on Mono), #1253 (linq2db.sqlite.ms NuGet), #5636 and #5638 (Release build CVE suppression).
- **Compiled queries and interceptors** -- closed #4365 (CompiledQuery did not call IEntityServiceInterceptor.EntityCreated).
- **Query generation** -- PR #5146 (SQLite alias naming issue), closed 2026-10-02.
- **Test infrastructure** -- PR #5698 (SQLite and DuckDB tests against in-memory databases), PR #5634 (isolate and restore tests that mutate the global Common.Convert converter).

## Active discussions
- [How to use relative path for LoadSQLiteMetadata?](https://github.com/linq2db/linq2db/discussions/3126) -- [Q&A] Path resolution for LoadSQLiteMetadata relative to project directory.
- [SQLite PRAGMA functions JOIN with sqlite_master](https://github.com/linq2db/linq2db/discussions/4985) -- [Q&A] Joining PRAGMA result sets (e.g. pragma_table_info) with sqlite_master for schema introspection.
- [Howto limit to limit characters number in a SQLite text column](https://github.com/linq2db/linq2db/discussions/5120) -- [Q&A] TEXT length constraints; SQLite ignores DbType annotations.

## Stats

- Open issues: 20 (#1224, #1855, #2107, #2432, #2953, #3408, #3766, #3899, #4446, #4988, #5396, #5611, #5906, #5930, #5984, #6028, #6031, #6071, #6072, #6081)
- Closed issues: 79
- Open PRs: 1 (#5931)
- Total PRs: 35
- Discussions: 12 (3 open)
- Last fetched: 2026-10-21

<details><summary>Coverage</summary>

- Index entries scanned: 146 (99 issues + 35 PRs + 12 discussions)
- Themes extracted: 18 (9 open, 9 resolved)

</details>
