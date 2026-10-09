---
area: PROV-CLICKHOUSE
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: medium
last_verified: 2026-10-10
last_verified_sha: 05150894edc2511f0dd0bc7829b2a309cec36ec9
---

# PROV-CLICKHOUSE -- GitHub themes

## Open themes

- **Correlated subqueries** -- ClickHouse cannot run correlated subqueries, and linq2db's detection is still incomplete. #5590 (open) tracks the generic "could not be converted to SQL" and wrong-SQL cases for YDB and ClickHouse. The expression-position rejection landed in #5574 (merged 2026-06-04) and the join-hint work in #5555 (merged 2026-07-08). Gap remains for complex nested cases.
- **Type system gaps** -- Array, JSON, tuple and decimal/date type mapping is not covered. #4898 (Array columns) and #4972 ("Unknown type: JSON") remain open; users work around via GetTypeMapping. #5171 (tuples in IN, tagged LINQ) and #5789 (Contains over a decimal column matches rows for a truncated probe value) are open. #5914 (DateTimeOffset writes a different day to Date/Date32 than to DateTime/DateTime64) is open.
- **Date and time translations (6.4 / 6.5 cycle)** -- Date translations emit SQL that contradicts the declared type, or call DateTime64-only functions on Date values. #5955 (datetime function regression in 6.5.0) is open; fix PR #5959 (open) coerces date operands to DateTime64 before toUnixTimestamp64Milli and toUnixTimestamp64Nano. #5961 (three date translations declare a type that contradicts the emitted SQL) is open.
- **Octonica client vs newer ClickHouse servers** -- Octonica.ClickHouseClient breaks on server releases. ClickHouse 26.8.2.7 killed the native TCP session mid-run: #5845 dropped Octonica from the CI job, #5846 (draft, diagnostic) isolated it, and #5860 re-enabled it behind a server-side setting. #5962 fixed the CI leg on ClickHouse 26.9. Recurring: a server bump can break the Octonica leg again.
- **Schema and DDL** -- CREATE TABLE ignores some linq2db settings and engine choice. #4206 (CreateTable does not respect WithTableExpression) is open. Discussion #4441 (schema provider access levels) is open. Discussion #4402 (CREATE TABLE always in-memory, needs MergeTree engine) is closed.
- **Lightweight DELETE** -- ClickHouse supports DELETE FROM for lightweight deletions, but linq2db uses ALTER TABLE DELETE. #4725 requests native syntax support (open).

## Resolved themes

- **Octonica client library** -- The Octonica.ClickHouseClient NuGet package (v3.1.8) was incompatible with linq2db (broken in #5460, CI disabled). Updated to v4.1.4 and CI re-enabled in #5608 (merged 2026-06-12).
- **ClickHouse.Driver rename and v1.0 support** -- ClickHouse.Client was renamed to ClickHouse.Driver (#5071, merged 2025-08-11). Driver update #5227 and v1.0 provider support #5401 merged 2026-01-06 and 2026-03-06.
- **IN/NOT IN null handling** -- Non-correlated NOT IN / IN emulation was not null-safe for providers without correlated-subquery support (ClickHouse, YDB). Fixed in #5582 (merged 2026-06-04).
- **Window functions (6.4.0 regression)** -- Multiple window functions in one query generated invalid ClickHouse SQL (#5867, worked in 6.3.0). Closed 2026-09-08; the index links no fix PR.
- **Table hints and FINAL** -- TableHint("FINAL") produced "mtFINAL" without a space (#5444), fixed by #5449 (merged 2026-05-07). Earlier FINAL-hint issue #5155 closed 2025-11-03 with linked PR #5163 closed.
- **CTE + let on ClickHouse** -- Invalid SQL with let plus CTE and a join (#5359) is fixed; regression test #5509 merged 2026-05-06.
- **Temp table inserts** -- Temp table creation broke after ClickHouse.Client 7.0.0 (#4389), fixed by #4393 (merged 2024-01-27). INSERT generated as DEFAULT VALUES SELECT in 6.0.0-rc3 (#5176) closed 2025-11-28.
- **Join hints** -- #5555 (merged 2026-07-08) adds ALL, ANY, SEMI, ANTI and ASOF strictness modifiers and the GLOBAL distribution modifier.
- **Remote context column attributes** -- On a remote context the server ignored configuration-scoped column attributes (#5966, closed 2026-10-09). The index links no fix PR.

## Active discussions

- [Wrap s3Cluster ClickHouse function calls](https://github.com/linq2db/linq2db/discussions/5668) -- [Q&A] TableFunction wrapper for ClickHouse s3Cluster remote table function calls; users need to call native s3Cluster() within INSERT INTO .. SELECT.
- [Force * in insert into select](https://github.com/linq2db/linq2db/discussions/5671) -- [Q&A] INSERT INTO .. SELECT from s3Cluster generates explicit columns instead of * (ClickHouse requires * for certain remote sources).
- [Schema Provider -- Access levels](https://github.com/linq2db/linq2db/discussions/4441) -- [General] Determining which system tables/databases need permission grants to make schema provider work.

## Stats

- Open issues: 9
- Closed issues: 14
- Open PRs: 1
- Total PRs: 33 (1 open, 32 closed)
- Discussions: 4 (3 open, 1 closed)
- Last fetched: 2026-10-09 (index data through this date)

<details><summary>Coverage</summary>

- Index entries scanned: 60 (23 issues + 33 PRs + 4 discussions)
- Themes extracted: 15 (6 open + 9 resolved)
</details>
