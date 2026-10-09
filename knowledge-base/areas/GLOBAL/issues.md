---
area: GLOBAL
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: high
last_verified: 2026-10-10
last_verified_sha: 05150894edc2511f0dd0bc7829b2a309cec36ec9
---

# GLOBAL -- GitHub themes

## Open themes

- **Mapping and inheritance** -- Inheritance filter review (#4305), abstract and intermediate inheritance reads (#3184, #4364, #1473), MultiInsert dropping InheritanceMapping values (#2988), composite property auto-mapping (#2873), composite objects in associations (#4139), fluent-API scope limits (#3041, #3136, #4073, #4893), attribute and fluent merging (#3119), contract-to-implementation mapping (#230). Derived-type writes through base-mapped tables are addressed by closed PR #5840.

- **Query cache and cached-query correctness** -- Recurring class of bugs where SQL or parameters built for one call are reused for another: cache growth and memory pressure (#3009, #5692, PR #5681, PR #5711), extension results served from cache (#4266), and query builders that do not register SQL-shaping values with the cache (#6002). Fix candidates: PR #6003 (stale FromSql/Sql.Expr SQL) and PR #6007 (cached-query mutation in IN->EXISTS). Closed PRs #5723, #5791, #5801 and #5841 cover adjacent cache-mutation fixes.

- **SQL generation and optimization** -- Reserved-word lists for all providers, critical (#1126), NOT EXISTS / EXISTS join optimization (#2815), SQL Server ISNULL optimization (#3314, PR open), Skip/Take without OrderBy (#5342), grouping sets and rollup/cube (#4265), bitwise NOT (#4726), re-enabling an optimization disabled by #5074 (#5081), multiple result-set query builder (#5496), generic backlog (#4745). Recent open defects: set operation with a computed difference and declared duration (#5796), aggregate with an untranslatable selector inside a projection (#5787), date/time literal losing sub-seconds against a coarser column (#5997).

- **Query execution performance** -- Update performance on many tables (#4724), Collection.Contains optimization (#4600), client collection value inlining (#4584), SQL Server LoadWith optimization (#4588), query cache size limits (#3009), Futures support (#1404), task pooling (#3437), remoting serialization cost (#3800), bulk copy tuning (#2777).

- **Associations and eager loading** -- Duplicate association queries (#3806), duplicate entity objects from incomplete association data (#4059), many-to-many associations (#2888), composite-object associations (#4139), LoadWith on fluent-configured children (#3041, #3136). Recent eager-load fixes are in closed PRs #5727, #5809, #5938 and #5939.

- **Remote query execution and LinqService** -- LinqService extensibility (#1949), batched multi-query execution over WCF (#1908), remoting performance (#3800), SQL divergence between direct and remote contexts (#5169).

- **Insert, output and bulk operations** -- Insert overloads that keep identity values (#5021), identity insert into IntoTempTable with IQueryable source (#3795), InsertWithResult multi result-sets (#2982), output on insert/update/delete (#3124, #3832), bulk copy returning inserted IDs (#2960), bulk insert ignore (#5124), ModificationHandler design (#2206), InsertOrReplace with custom key (#3597). Merge API: immutable models (#4237), custom setters for matched rows (#4357).

- **Transaction, retry and connection handling** -- Savepoints (#1935), automatic ambient-transaction enlistment (#2676), EF-style retry strategies (#3219), RetryPolicy with UPDATE statements (#4967), unexpected implicit transaction on SQL Server (#4053), async connection opening (#4930).

- **Type system and conversion** -- BigInteger SumAsync (#4040), .NET 7 numeric types (#3660), TimeSpan mapped to time (#4306), SAP HANA array types (#3302, PR open), DbType in parameter typing (#3787), JSON column types (#1661), union constant/parameter typing (#3360). Recent DateTime/DateTimeOffset work is in draft PRs #5892 and #5913; the sub-second and date-difference defects are #5997 and #5993.

- **Expression translation and LINQ surface** -- Net 9/10 LINQ methods (#4412, PR open), interface property resolution (#4199), C# with expressions (#3177), LastOrDefaultAsync on IOrderedQueryable (#4019), Order/OrderDescending on .NET 7 (#3694), .NET 6 future support (#2977).

- **Schema and DDL** -- CreateTable gaps (#1789), default values on ColumnAttribute (#2277), unique index via fluent mapping (#4073), create and drop database (#5287), temp table indexes (#2827), SQL Server temp table collation (#4598), case-sensitive schema testing (#4658).

- **Providers and new-provider requests** -- Sybase IQ (#2040), SAP Anywhere (#3398), MS SQL function calls without stored procedures (#1857), HANA procedure name escaping (#1740), YDB schema reads racing DDL (PR #5763), per-provider identifier length limits (PR #5772), Access x86 test leg split per provider (PR #6005), Access date-difference query complexity (#5993).

- **Configuration, infrastructure, AOT and tests** -- Secrets.json support (#3868), AOT code stripping (#4018), WASM runtime testing (#5159), reflection BindingFlags review (#4314), source generators (#2687), Examples solution not building in Release (#5945), test heartbeat total under --filter (#5964), attribute-cache growth driving NETFX multi-config OOM (#5692).

- **.NET version and release-line work** -- .NET 11 support and drop of .NET 8/9 (PR #5942), C# 15 and runtime async on net11.0 (PR #5944), LibRed managed Access provider (PR #5956), LibRed extended SQL dialect (PR #5969), PIVOT/UNPIVOT (PR #5708, #1475).

- **Documentation** -- Broken document link (#5494).

## Resolved themes

- **Query correctness regressions (2026-07 to 2026-10)** -- Nested UnionAll ordering (#5684, regression test PR #5685), parasite coalesce on aggregates in 6.3 (#5699), left-join predicate with nullable (#5781), window COUNT(*) with another window function (#5782), chained update/row lock hints (#5714), InheritanceMapping (#5729), OrderBy family (#5935), DistinctBy losing query state (PR #5732), entity filter dropping a null-check in set operations (#5792, PR #5831).

- **Compilation and build performance** -- Query compilation regression since 6.0 (#5719, PR #5737 TPH fix), compiled query with LoadWith (#5842, PR #5844), LoadWith forcing thread-pool use (#5805, PR #5809).

- **Type system and mapping** -- DateTimeOffset.DateTime sorting (#5435), NodaTime Instant? parameter inference (#5549), char null valueConverter (#5654), F# option types (#195), arithmetic between value-converted columns (#5798), UpCastDbDataTypeToFit overwriting Length (#5826).

- **Build and infrastructure** -- Linux DB2/Informix libdb2.so loading (#5538), NuGet pack HintPath resolution, analyzer rules deferred from 6.3.0 (#5532), sqlserver2016 script rename (#5990), analyzers shipped via linq2db.Analyzers (PR #5720).

- **Feature implementations** -- Trim with character parameters (#3296), InsertIfNotExists (#2528), UUIDv7 (#5646), window-function template cleanup (#5674), public IInterceptable (#5803, PR #5804), Sql.Window server-side markers (PR #5783), Enum.HasFlag translation (#3040).

## Active discussions

- [Make association properties can be subclass of types implemented IEnumerable<T>](https://github.com/linq2db/linq2db/discussions/4351) -- [General] Association property inheritance from IEnumerable-implementing base class.
- [I created a .NET 8 template using Linq2Db (also FluentMigrator and FastEndpoints)](https://github.com/linq2db/linq2db/discussions/4425) -- [Show and tell] New .NET template featuring linq2db.
- [Can't get properties correctly](https://github.com/linq2db/linq2db/discussions/4529) -- [Q&A] Property resolution assistance.
- [.NET Maui](https://github.com/linq2db/linq2db/discussions/4679) -- [Q&A] MAUI compatibility.
- [Exotic database reader case](https://github.com/linq2db/linq2db/discussions/4932) -- [Q&A] Unusual custom reader scenario.
- [Who ever used pgbouncer with Linq2db?](https://github.com/linq2db/linq2db/discussions/4956) -- [General] PgBouncer compatibility.
- [Possible release date for 6 version?](https://github.com/linq2db/linq2db/discussions/5007) -- [Q&A] v6 release timeline (stale; v6 has shipped).
- [Association attribute on a method instead of property?](https://github.com/linq2db/linq2db/discussions/5068) -- [Q&A] Association attribute on methods.
- [Any easy way to run non-query from DataContext?](https://github.com/linq2db/linq2db/discussions/5060) -- [Q&A] Non-query execution helper.
- [Linq2Db MySqlConnector with pooling. Closing the connection before disposing.](https://github.com/linq2db/linq2db/discussions/5329) -- [General] MySqlConnector pooling behaviour.
- [NativeAot Support](https://github.com/linq2db/linq2db/discussions/5389) -- [Q&A] AOT compatibility question (updated 2026-09-12).
- [About Change-Tracking](https://github.com/linq2db/linq2db/discussions/5722) -- [General] Change tracking question (updated 2026-07-21).
- [IT Security - Cyber Resiliance Act (EU)](https://github.com/linq2db/linq2db/discussions/5849) -- [General] Regulatory and security inquiry (updated 2026-09-08).

## Stats

- Open issues: 108
- Closed issues: 509
- Open PRs: 28
- Total PRs: 1270
- Discussions: 83 (13 open)
- Last fetched: 2026-10-09

<details><summary>Coverage</summary>

- Index entries scanned: 5957 total (3079 issues + 2582 PRs + 296 discussions); GLOBAL-area subset used for themes: 1970 (617 issues + 1270 PRs + 83 discussions)
- Items updated since 2026-07-06 cursor: 177 issues, 245 PRs, 7 discussions
- Themes extracted: 14 open + 5 resolved clusters
- areas/GLOBAL/decisions.md not regenerated in this run
</details>
