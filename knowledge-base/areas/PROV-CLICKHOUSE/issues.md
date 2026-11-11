---
area: PROV-CLICKHOUSE
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: medium
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
---

# PROV-CLICKHOUSE -- GitHub themes

## Open themes
- **Correlated subqueries** -- ClickHouse cannot run correlated subqueries, and linq2db's detection is still incomplete. #5590 (open) tracks the generic "could not be converted to SQL" and wrong-SQL cases for YDB and ClickHouse. The expression-position rejection landed in #5574 (merged 2026-06-04) and the join-hint work in #5555 (merged 2026-07-08). Gap remains for complex nested cases.
- **Type system gaps** -- Array, JSON, tuple and decimal/date type mapping is not covered. #4898 (Array columns) and #4972 ("Unknown type: JSON") remain open; users work around via GetTypeMapping. #5171 (tuples in IN, tagged LINQ) is open. #5789 (Contains over a decimal column matches rows for a truncated probe value) is open. #5914 (DateTimeOffset writes a different day to Date/Date32 than to DateTime/DateTime64) is open. #6044 (attribute-built SQL from Sql.Ext, [Sql.Expression] and [Sql.Function] takes the mapping schema default type instead of the value's type; on ClickHouse an analytic MAX over a whole-second DateTime is typed DateTime64(7), so the DateTime64 coercion is skipped and the server refuses the query) is open.
- **Date and time translations** -- Date translations emit SQL that contradicts the declared type, or call DateTime64-only functions on Date values. The 6.5.0 regression #5955 is closed; its fix #5959 is closed (see Resolved). Open: #5961 (three date translations declare a type that contradicts the emitted SQL; updated 2026-11-10) and #6117 (a TimeSpan constant is written as whole seconds, dropping its sub-second part; updated 2026-10-23). The same narrowing pattern shows in literal comparisons: #5997 (a DateTime literal compared with a coarser DateTime column loses its sub-second part on ClickHouse, open; tagged GLOBAL) and #6081 (a date column IN a list of datetime columns misses a match that == finds on SQLite and ClickHouse, open; indexed under PROV-SQLITE).
- **Decimal typing and arithmetic** -- Decimal values take their type from a default rather than from the value or the column. #5789 (Contains over a decimal column matches rows for a truncated probe value, open) and #6089 (decimal division whose divisor is a missed LEFT JOIN row raises "Decimal convert overflow" on ClickHouse.Driver, open) share one cause family. #6064 (IN list beside an aggregate over a decimal column written at the mapping schema default scale) is closed and moved to Resolved.
- **Octonica client vs newer ClickHouse servers** -- Octonica.ClickHouseClient breaks on server releases. ClickHouse 26.8.2.7 killed the native TCP session mid-run: #5845 dropped Octonica from the CI job, #5846 (closed, diagnostic) isolated it, and #5860 re-enabled it behind a server-side setting. #5962 fixed the CI leg on ClickHouse 26.9. No item is open; kept as a recurring risk: a server bump can break the Octonica leg again.
- **Schema and DDL** -- CREATE TABLE ignores some linq2db settings and engine choice. #4206 (CreateTable does not respect WithTableExpression) is open. Discussion #4441 (schema provider access levels) is open. Discussion #4402 (CREATE TABLE always in-memory, needs MergeTree engine) is closed.
- **Lightweight DELETE** -- ClickHouse supports DELETE FROM for lightweight deletions, but linq2db uses ALTER TABLE DELETE. #4725 requests native syntax support (open).
- **netstandard2.0 asset on modern runtimes** -- A parameterised insert through ClickHouse.Driver fails on the netstandard2.0 build with an unbound parameter (#6086, open) and passes on net10.0. Other providers' netstandard2.0 reports are tracked under their own areas.

## Resolved themes
- **Octonica client library** -- The Octonica.ClickHouseClient NuGet package (v3.1.8) was incompatible with linq2db (broken in #5460, CI disabled). Updated to v4.1.4 and CI re-enabled in #5608 (merged 2026-06-12). #5845, #5846 and #5860 are closed; see the open Octonica theme.
- **ClickHouse.Driver rename and v1.0 support** -- ClickHouse.Client was renamed to ClickHouse.Driver (#5071, merged 2025-08-11). Driver update #5227 and v1.0 provider support #5401 merged 2026-01-06 and 2026-03-06.
- **IN/NOT IN null handling** -- Non-correlated NOT IN / IN emulation was not null-safe for providers without correlated-subquery support (ClickHouse, YDB). Fixed in #5582 (merged 2026-06-04).
- **Window functions (6.4.0 regression)** -- Multiple window functions in one query generated invalid ClickHouse SQL (#5867, worked in 6.3.0). Closed 2026-09-08; the index links no fix PR.
- **Table hints and FINAL** -- TableHint("FINAL") produced "mtFINAL" without a space (#5444), fixed by #5449 (merged 2026-05-07). Earlier FINAL-hint issue #5155 closed 2025-11-03 with linked PR #5163 closed.
- **CTE + let on ClickHouse** -- Invalid SQL with let plus CTE and a join (#5359) is fixed; regression test #5509 merged 2026-05-06.
- **Temp table inserts** -- Temp table creation broke after ClickHouse.Client 7.0.0 (#4389), fixed by #4393 (merged 2024-01-27). INSERT generated as DEFAULT VALUES SELECT in 6.0.0-rc3 (#5176) closed 2025-11-28.
- **Join hints** -- #5555 (merged 2026-07-08) adds ALL, ANY, SEMI, ANTI and ASOF strictness modifiers and the GLOBAL distribution modifier.
- **Remote context column attributes** -- On a remote context the server ignored configuration-scoped column attributes (#5966, closed 2026-10-09). The index links no fix PR.
- **Decimal IN list scale** -- An IN list beside an aggregate over a decimal column was written at the mapping schema default scale instead of the column's facets (#6064, closed; index date 2026-10-22). The index links no closing PR; #6122 (keep a computed IN operand's server precision, closed 2026-10-23) touches the same IN-operand path, but it is not verified as the fix.
- **6.5.0 datetime function regression** -- #5955 (closed; index date 2026-10-22) was fixed by #5959 (closed; index date 2026-10-23), which coerces date operands to DateTime64 before toUnixTimestamp64Milli and toUnixTimestamp64Nano. #6116 (closed 2026-10-23) extends the coercion to every epoch-function operand. Follow-up regression #6115 (.TimeOfDay on an undeclared DateTime column fails with Code 43, from #5959) is closed.
- **Trace DECLARE parameter type names** -- #6198 (PROV-SQLITE tagged; closed, index date 2026-11-10) names SQLite, DuckDB and ClickHouse parameter types in the trace DECLARE block.
- **Client options and connection** -- #5178 (option to specify HttpClient for ClickHouseProvider.ClickHouseDriver) closed 2025-11-15 with PR #5179 closed the same day. #5162 (connection does not honor the server-side default database) is closed with resolution external.
- **ClickHouse scaffold** -- #5088 (Linq2Db.Cli scaffold for ClickHouse) is closed; the index links no PR. The discussion #5089 is still open (see Active discussions).

## Active discussions
- [Wrap s3Cluster ClickHouse function calls](https://github.com/linq2db/linq2db/discussions/5668) -- [Q&A] TableFunction wrapper for ClickHouse s3Cluster remote table function calls; users need to call native s3Cluster() within INSERT INTO .. SELECT.
- [Force * in insert into select](https://github.com/linq2db/linq2db/discussions/5671) -- [Q&A] INSERT INTO .. SELECT from s3Cluster generates explicit columns instead of * (ClickHouse requires * for certain remote sources).
- [Schema Provider -- Access levels](https://github.com/linq2db/linq2db/discussions/4441) -- [General] Determining which system tables/databases need permission grants to make schema provider work.
- [Linq2Db.Cli scaffold for ClickHouse](https://github.com/linq2db/linq2db/discussions/5089) -- Scaffold support for ClickHouse in Linq2Db.Cli; open.

## Stats
- Open issues: 12
- Closed issues: 17
- Open PRs: 0
- Total PRs: 35 (0 open, 35 closed)
- Discussions: 4 (3 open, 1 closed)
- Last fetched: 2026-11-11 (index data through 2026-11-11T14:05:20Z)

<details><summary>Coverage</summary>

- Index entries scanned: 6243 (3245 issues + 2699 PRs + 296 discussions); ClickHouse candidates by area tag or content: 39 issues + 49 PRs + 6 discussions. Stats count area-tagged entries only; #5997, #6081 and #5089 are cited by content.
- Themes extracted: 22 (8 open + 14 resolved)
- Changed in this refresh: 10 new citations (#6117, #6115, #6116, #6122, #6198, #5089, #5088, #5162, #5178, #5179); 3 items moved to resolved (#6064, #5955, #5959).
- Dropped on purpose: #5169, #5965, #6167, #4671 (ClickHouse appears only in body or labels; cross-provider, not this area); #3816 (DistinctBy, unrelated); pre-2025 closed issues and PRs (#1796, #3778, #3954, #4066, #3859, #4558 and the 2022-2024 PR batch) carry no open theme and remain in the Stats counts.
</details>
