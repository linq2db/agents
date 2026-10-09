---
area: PROV-DUCKDB
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: low
last_verified: 2026-10-10
last_verified_sha: 05150894edc2511f0dd0bc7829b2a309cec36ec9
---

# PROV-DUCKDB -- GitHub themes

## Open themes
- **Date/time parameter typing and Now translation** -- DuckDB binds untyped parameters, and `now()` returns `TIMESTAMP WITH TIME ZONE`, so mixing a `DateTime` parameter with `Sql.CurrentTimestamp` in one conditional can shift the stored value by the session's UTC offset. Open: [#5977](https://github.com/linq2db/linq2db/issues/5977). Same family as the Now-translation work in #5518 (resolved below). Only one open item, so confidence is low.

## Resolved themes
- **Now and date translation regressions** -- the Now translation refactor (bare keywords replaced by function-call forms such as `now()` and `current_localtimestamp()`) broke the master build during the #5451 / #5467 merge race; fixed by [#5518](https://github.com/linq2db/linq2db/pull/5518) (merged 2026-05-10).
- **Provider bring-up and native loading** -- DuckDB provider added in [#5451](https://github.com/linq2db/linq2db/pull/5451) (merged 2026-05-10). The x86 native-load guard caught the wrong exception type, which failed both x86 Access jobs on the 6.4.0 release PR; fixed by [#5744](https://github.com/linq2db/linq2db/pull/5744) (merged 2026-08-05).

## Active discussions
- None in the PROV-DUCKDB area.

## Stats
- Open issues: 1
- Closed issues: 0
- Open PRs: 0
- Total PRs: 3
- Discussions: 0
- Last fetched: 2026-10-09

<details><summary>Coverage</summary>

- Index entries scanned: 4 (1 issues + 3 PRs + 0 discussions)
- Themes extracted: 3
- Notes: no cluster reached the 3-item threshold. Themes above are grouped by topic from the area's known recurring subsystems. DuckDB-mentioning items classified under other areas are not counted here.
- Regenerated from github/issues-index.json and github/prs-index.json (index data through 2026-10-09). Prior file absent; created in standard structure.
</details>
