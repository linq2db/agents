---
area: PROV-SQLITE
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: high
last_verified: 2026-10-10
last_verified_sha: 05150894edc2511f0dd0bc7829b2a309cec36ec9
---

# PROV-SQLITE -- GitHub themes

## Open themes

- **DateTime/duration arithmetic** -- SQLite cannot translate DateTime/DateTimeOffset addition or subtraction of an explicitly declared duration. Open issue #5930 (nullable DateTime minus TimeSpan throws LinqToDBException in 6.5.0); the fix is open PR #5931 (translates declared-duration arithmetic incl. nullable operands, predicates and remote queries). Same area as earlier date bugs: #998 (DateAdd with table data), #1688 with PRs #1689 and #1691 (DateDiff / AddDate), #4904 (DateTime.MaxValue comparison), #2346 and #4038 (Ticks/Int64 wrapping).
- **DateTimeOffset as primary key** -- single open item #3766 (SQLite.Classic with DateTimeOffset primary key). Singleton; no open PR.
- **Dynamic columns through FromQuery** -- single open item #2953: dynamic column mappings are not applied to results of IDataContext.FromQuery(...). Singleton.
- **Metadata loading and configuration** -- open #5906 proposes removing the PreLoadSQLite_BaseDirectory setting (set in three places, likely unused by the System.Data.SQLite 2.x line). Open Q&A on the same surface: discussion #3126 (relative path for LoadSQLiteMetadata) and #4985 (PRAGMA table functions joined with sqlite_master).
- **SQL precedence in string.Join** -- single open item #5984: an arithmetic item in string.Join over object items is emitted without parentheses, so SQLite's concatenation operator binds tighter than plus. Singleton.

## Resolved themes

- **DateTime/DateTimeOffset in SQLite** -- closed #378, #338, #998, #2346, #4038, #4904; DateDiff/AddDate via #1688 with PRs #1689 and #1691; sub-millisecond tick rendering fixed in PR #5682.
- **Schema/Scaffolding** -- closed #784, #930, #934, #1269, #2099, #3330, #4117 (Schema API for Microsoft.Data.Sqlite), #4449, #4736, #4802 (0 tables read via the Microsoft provider). Fixes: PR #5117 (primary key detection, fixes #5014) and PR #5122 (pragma-based metadata queries).
- **Guid mapping** -- closed #159, #1878, #4295, #4808; PRs #3580 (Guid mapping fix) and #5380 (do not type Guid values explicitly). Discussions #4296 and #4500 closed.
- **Type mapping and conversion** -- closed #1279 (char mapping), #1960 (CreateTable SQL type), #2354 (double.MaxValue rounding), #3129 (decimal separator on read-back), #3067 (custom type over byte array); PRs #925 and #1291 (char parameters on Microsoft.Data.Sqlite).
- **Bulk operations** -- closed #330, #2844 (inefficient bulk update SQL from in-memory collection), #5282 (InsertWithIdentity returns incorrect value).
- **Connection, packaging and runtime** -- closed #21, #512, #199, #374, #261, #346, #1493, #4170 (Xamarin/Android DllNotFound), #4512 (Interop.dll delete on multi-targeting); PRs #502 (System.Data.Sqlite on Mono), #1253 (linq2db.sqlite.ms NuGet), #5636 and #5638 (Release build CVE suppression).
- **Compiled queries and interceptors** -- closed #4365 (CompiledQuery did not call IEntityServiceInterceptor.EntityCreated).

## Active discussions
- [How to use relative path for LoadSQLiteMetadata?](https://github.com/linq2db/linq2db/discussions/3126) -- [Q&A] Path resolution for LoadSQLiteMetadata relative to project directory.
- [SQLite PRAGMA functions JOIN with sqlite_master](https://github.com/linq2db/linq2db/discussions/4985) -- [Q&A] Joining PRAGMA result sets (e.g. pragma_table_info) with sqlite_master for schema introspection.
- [Howto limit to limit characters number in a SQLite text column](https://github.com/linq2db/linq2db/discussions/5120) -- [Q&A] TEXT length constraints; SQLite ignores DbType annotations.

## Stats

- Open issues: 5 (#2953, #3766, #5906, #5930, #5984)
- Closed issues: 89
- Open PRs: 1 (#5931)
- Total PRs: 35
- Discussions: 12 (3 open)
- Last fetched: 2026-10-09

<details><summary>Coverage</summary>

- Index entries scanned: 141 (94 issues + 35 PRs + 12 discussions)
- Themes extracted: 12 (5 open, 7 resolved)

</details>
