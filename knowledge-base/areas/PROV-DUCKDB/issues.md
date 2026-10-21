---
area: PROV-DUCKDB
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: low
last_verified: 2026-10-21
last_verified_sha: 89b5ce16278728b9936ba374827fea002c76e962
---

# PROV-DUCKDB -- GitHub themes

## Open themes
- **Date/time parameter typing and Now translation** -- DuckDB binds untyped parameters, and `now()` returns `TIMESTAMP WITH TIME ZONE`, so mixing a `DateTime` parameter with `Sql.CurrentTimestamp` in one conditional can shift the stored value by the session's UTC offset. Open: [#5977](https://github.com/linq2db/linq2db/issues/5977). Same family as the Now-translation work in [#5518](https://github.com/linq2db/linq2db/pull/5518) (resolved below). Only one item in this theme, so confidence stays low.
- **Native reader gaps on the netstandard2.0 asset** -- the ns2.0 build registers DuckDB's date/time readers only under `SUPPORTS_DATEONLY`, so a modern runtime that loads the ns2.0 asset cannot read `TIMETZ` into `TimeSpan`. Open: [#6084](https://github.com/linq2db/linq2db/issues/6084). Single item; the same TFM-gate pattern shows up in other providers' compatibility issues, which are not counted here.
- **Integer function overloads keep the fraction in SQL** -- the integer `Sql.Degrees` overloads translate to the engine's `DEGREES`, which returns a float on DuckDB and SQLite, so the fraction survives into a SQL comparison. Open: [#6072](https://github.com/linq2db/linq2db/issues/6072). Indexed under PROV-SQLITE and labelled `provider: duckdb`; cited here, not counted in Stats.

## Resolved themes
- **Now and date translation regressions** -- the Now translation refactor (bare keywords replaced by function-call forms such as `now()` and `current_localtimestamp()`) broke the master build during the #5451 / #5467 merge race; fixed by [#5518](https://github.com/linq2db/linq2db/pull/5518) (merged 2026-05-10).
- **Provider bring-up and native loading** -- DuckDB provider added in [#5451](https://github.com/linq2db/linq2db/pull/5451) (merged 2026-05-10). The x86 native-load guard caught the wrong exception type, which failed both x86 Access jobs on the 6.4.0 release PR; fixed by [#5744](https://github.com/linq2db/linq2db/pull/5744) (merged 2026-08-05).

## Active discussions
- None in the PROV-DUCKDB area.

## Stats
- Open issues: 2
- Closed issues: 0
- Open PRs: 0
- Total PRs: 3
- Discussions: 0
- Last fetched: 2026-10-21

<details><summary>Coverage</summary>

- Index entries scanned: 5 (2 issues + 3 PRs + 0 discussions), plus 1 DuckDB-labelled issue indexed under PROV-SQLITE (#6072)
- Themes extracted: 3
- Notes: incremental merge on 2026-10-21 from the github-themes refresh. Added #6084 and #6072 as themes; #5977 and all resolved items kept unchanged. The fetch did not update any PROV-DUCKDB-tagged PR. No cluster reached the 3-item threshold, so themes are grouped by topic. DuckDB-mentioning items classified under other areas are not counted in Stats.
</details>
